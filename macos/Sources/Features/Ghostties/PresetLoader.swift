import Foundation
import CryptoKit
import OSLog

/// Loads agent presets from `~/.ghostties/presets/` as `.md` files with YAML frontmatter.
///
/// Each preset file has the format:
/// ```
/// ---
/// name: Code Reviewer
/// description: Reviews code for bugs and security issues
/// command: claude
/// model: sonnet
/// permissionMode: plan
/// icon: magnifyingglass
/// access: read-only
/// allowedTools:
///   - Read
///   - Grep
/// ---
///
/// System prompt body goes here...
/// ```
///
/// On first launch, bundled presets are seeded to the presets directory.
/// Community presets can be added by dropping `.md` files in the folder.
struct PresetLoader {
    static let presetsDirectoryPath = ("~/.ghostties/presets" as NSString).expandingTildeInPath

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ghostties",
        category: "PresetLoader"
    )

    // MARK: - Public API

    /// Current seed version. Bump this when bundled presets change to trigger re-seeding.
    static let seedVersion = 2

    /// Seed bundled presets to `~/.ghostties/presets/` using versioned seeding.
    ///
    /// Recursively copies the `presets/` subdirectory from the app bundle into
    /// `~/.ghostties/presets/`. After copying, rewrites any `${HOME}` literals
    /// in `.json` files to the real home path. Only copies items that don't
    /// already exist — never overwrites user edits.
    static func seedIfNeeded() {
        let signpostState = Perf.signposter.beginInterval("presets.seed")
        defer { Perf.signposter.endInterval("presets.seed", signpostState) }
        let fm = FileManager.default
        let dirPath = presetsDirectoryPath
        let versionFilePath = (dirPath as NSString).appendingPathComponent(".seed-version")

        // Check the current seed version.
        let currentVersion: Int
        if let versionData = fm.contents(atPath: versionFilePath),
           let versionString = String(data: versionData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let version = Int(versionString) {
            currentVersion = version
        } else {
            currentVersion = 0
        }

        // Skip if already at or above the current seed version.
        guard currentVersion < seedVersion else { return }

        // Create the destination directory if it doesn't exist.
        if !fm.fileExists(atPath: dirPath) {
            do {
                try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o700,
                ])
            } catch {
                logger.error("Failed to create presets directory: \(error.localizedDescription)")
                return
            }
        }

        // Locate the bundled `presets/` resource directory.
        guard let bundledPresetsURL = Bundle.main.resourceURL?.appendingPathComponent("presets") else {
            logger.warning("No bundled presets directory found in app bundle")
            // Write seed version marker anyway to avoid repeated attempts.
            try? "\(seedVersion)".write(toFile: versionFilePath, atomically: true, encoding: .utf8)
            return
        }

        // Recursively copy subdirectories (folder-format presets).
        let destURL = URL(fileURLWithPath: dirPath)
        copyResourceDirectory(from: bundledPresetsURL, to: destURL, fm: fm)

        // Rewrite ${HOME} literals in all .json files under the seeded directory.
        let realHome = fm.homeDirectoryForCurrentUser.path
        rewriteHomeInJSONFiles(in: destURL, home: realHome, fm: fm)

        // Write the new seed version marker.
        do {
            try "\(seedVersion)".write(toFile: versionFilePath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write seed version marker: \(error.localizedDescription)")
        }
    }

    // MARK: - Seed Helpers

    /// Recursively copy `src` directory contents into `dest`, skipping items
    /// that already exist (additive, never overwrites).
    private static func copyResourceDirectory(from src: URL, to dest: URL, fm: FileManager) {
        guard let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else {
            logger.warning("Could not list bundled presets at \(src.path)")
            return
        }

        for item in items {
            let destItem = dest.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                // Create the subdirectory if needed, then recurse.
                if !fm.fileExists(atPath: destItem.path) {
                    do {
                        try fm.createDirectory(at: destItem, withIntermediateDirectories: true, attributes: [
                            .posixPermissions: 0o700,
                        ])
                    } catch {
                        logger.error("Failed to create preset subdirectory \(destItem.lastPathComponent): \(error.localizedDescription)")
                        continue
                    }
                }
                copyResourceDirectory(from: item, to: destItem, fm: fm)
            } else {
                // Copy file only if it doesn't already exist.
                if !fm.fileExists(atPath: destItem.path, isDirectory: &isDir) {
                    do {
                        try fm.copyItem(at: item, to: destItem)
                    } catch {
                        logger.error("Failed to copy preset file \(item.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Walk `directory` and rewrite `${HOME}` in any `.json` files to `home`.
    private static func rewriteHomeInJSONFiles(in directory: URL, home: String, fm: FileManager) {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  content.contains("${HOME}") else { continue }
            let rewritten = content.replacingOccurrences(of: "${HOME}", with: home)
            try? rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Load all presets from `~/.ghostties/presets/`.
    ///
    /// Handles two formats:
    /// - **Flat `.md` files** with YAML frontmatter (legacy format).
    /// - **Folder presets**: subdirectories containing `preset.json`.
    ///
    /// Returns an array of `AgentTemplate` objects with `isDefault: true` and `isGlobal: true`.
    /// Templates have deterministic UUIDs generated from the filename/foldername so IDs persist across launches.
    static func loadPresets() -> [AgentTemplate] {
        let signpostState = Perf.signposter.beginInterval("presets.load")
        defer { Perf.signposter.endInterval("presets.load", signpostState) }
        let fm = FileManager.default
        let dirPath = presetsDirectoryPath

        // Verify path is a real directory (not a symlink to an attacker-controlled location).
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { return [] }
        let attrs = try? fm.attributesOfItem(atPath: dirPath)
        if let fileType = attrs?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
            logger.warning("Presets directory is a symlink — refusing to load")
            return []
        }

        do {
            let entries = try fm.contentsOfDirectory(atPath: dirPath)
            var templates: [AgentTemplate] = []

            // Flat .md presets (legacy format).
            let mdFiles = entries.filter { $0.hasSuffix(".md") }.sorted()
            for filename in mdFiles {
                let filePath = (dirPath as NSString).appendingPathComponent(filename)
                let url = URL(fileURLWithPath: filePath)
                if let template = parsePreset(at: url, filename: filename) {
                    templates.append(template)
                }
            }

            // Folder-format presets: subdirectories containing preset.json.
            let subdirs = entries
                .filter { entry in
                    var entryIsDir: ObjCBool = false
                    let entryPath = (dirPath as NSString).appendingPathComponent(entry)
                    fm.fileExists(atPath: entryPath, isDirectory: &entryIsDir)
                    return entryIsDir.boolValue && !entry.hasPrefix(".")
                }
                .sorted()

            for subdir in subdirs {
                let folderURL = URL(fileURLWithPath: (dirPath as NSString).appendingPathComponent(subdir))
                if let template = parseFolderPreset(at: folderURL) {
                    templates.append(template)
                }
            }

            return templates
        } catch {
            logger.error("Failed to read presets directory: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Parsing

    /// Parse a single `.md` preset file into an `AgentTemplate`.
    ///
    /// Returns nil if the file can't be read or has invalid frontmatter.
    static func parsePreset(at url: URL, filename: String) -> AgentTemplate? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            logger.warning("Failed to read preset file: \(url.path)")
            return nil
        }

        // Split on "---" boundaries.
        // Expected format: "---\n<frontmatter>\n---\n<body>"
        // The content may or may not start with "---".
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            logger.warning("Preset file missing frontmatter delimiter: \(filename)")
            return nil
        }

        // Remove the leading "---" and find the closing "---"
        let afterFirstDelimiter = String(trimmed.dropFirst(3))
        guard let closingRange = afterFirstDelimiter.range(of: "\n---") else {
            logger.warning("Preset file missing closing frontmatter delimiter: \(filename)")
            return nil
        }

        let frontmatterText = String(afterFirstDelimiter[afterFirstDelimiter.startIndex..<closingRange.lowerBound])
        let bodyText = String(afterFirstDelimiter[closingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse frontmatter key-value pairs.
        let frontmatter = parseFrontmatter(frontmatterText)

        guard let name = frontmatter["name"] as? String, !name.isEmpty else {
            logger.warning("Preset file missing required 'name' field: \(filename)")
            return nil
        }

        // Generate a deterministic UUID from the filename.
        let stableId = deterministicUUID(from: filename)

        // Extract values from frontmatter.
        let description = frontmatter["description"] as? String
        let command = frontmatter["command"] as? String
        let model = frontmatter["model"] as? String

        // Validate the command field contains no whitespace or shell metacharacters.
        if let command = command {
            let invalidChars = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ";&|`$(){}"))
            if command.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
                logger.warning("Rejecting preset with invalid command '\(command)': \(filename)")
                return nil
            }
        }
        let permissionMode = frontmatter["permissionMode"] as? String
        let effort = frontmatter["effort"] as? String
        let icon = frontmatter["icon"] as? String
        let access = frontmatter["access"] as? String
        let allowedTools = frontmatter["allowedTools"] as? [String]

        // Determine the template kind from the command.
        let kind: AgentTemplate.Kind
        switch command {
        case nil: kind = .shell
        case "claude": kind = .claudeCode
        default: kind = .custom
        }

        // Build AgentConfig if there's any agent-related config.
        let agentConfig: AgentTemplate.AgentConfig?
        if model != nil || permissionMode != nil || effort != nil || allowedTools != nil || !bodyText.isEmpty {
            agentConfig = AgentTemplate.AgentConfig(
                systemPrompt: bodyText.isEmpty ? nil : bodyText,
                model: model,
                permissionMode: permissionMode,
                effort: effort,
                allowedTools: allowedTools
            )
        } else {
            agentConfig = nil
        }

        return AgentTemplate(
            id: stableId,
            name: name,
            kind: kind,
            command: command,
            isDefault: true,
            isGlobal: true,
            agent: agentConfig,
            templateDescription: description,
            icon: icon,
            accessLabel: access
        )
    }

    // MARK: - Folder-format Preset

    /// JSON manifest structure for folder-format presets (`preset.json`).
    private struct FolderPresetManifest: Decodable {
        let name: String
        let description: String
        let icon: String?
        let model: String?
        let permissionMode: String?
    }

    /// Parse a folder-format preset at `folderURL`.
    ///
    /// Expects the folder to contain:
    /// - `preset.json` — required manifest (name, description, icon?, model?, permissionMode?)
    /// - `system.md` — system prompt file (path stored; file may or may not exist yet)
    /// - `mcp-servers.json` — optional MCP config
    ///
    /// Returns nil if `preset.json` doesn't exist or can't be decoded.
    static func parseFolderPreset(at folderURL: URL) -> AgentTemplate? {
        let fm = FileManager.default
        let manifestURL = folderURL.appendingPathComponent("preset.json")
        guard fm.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        let manifest: FolderPresetManifest
        do {
            manifest = try JSONDecoder().decode(FolderPresetManifest.self, from: data)
        } catch {
            logger.warning("Failed to decode preset.json in \(folderURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }

        let folderName = folderURL.lastPathComponent
        let stableId = deterministicUUID(from: "folder:\(folderName)")

        let systemPromptPath = folderURL.appendingPathComponent("system.md").path

        let mcpConfigURL = folderURL.appendingPathComponent("mcp-servers.json")
        let mcpConfigPath: String? = fm.fileExists(atPath: mcpConfigURL.path) ? mcpConfigURL.path : nil

        let agentConfig = AgentTemplate.AgentConfig(
            systemPromptFile: systemPromptPath,
            model: manifest.model,
            permissionMode: manifest.permissionMode
        )

        return AgentTemplate(
            id: stableId,
            name: manifest.name,
            kind: .claudeCode,
            command: "claude",
            isDefault: true,
            isGlobal: true,
            agent: agentConfig,
            templateDescription: manifest.description,
            icon: manifest.icon ?? "",
            mcpConfigPath: mcpConfigPath
        )
    }

    /// Parse YAML-like frontmatter into a dictionary.
    ///
    /// Handles simple `key: value` pairs and list values in both inline `[a, b]`
    /// and multi-line `- item` syntax.
    static func parseFrontmatter(_ text: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = text.components(separatedBy: .newlines)

        var currentListKey: String?
        var currentList: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check if this is a list item (starts with "- ")
            if trimmedLine.hasPrefix("- "), let key = currentListKey {
                let value = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    currentList.append(value)
                    result[key] = currentList
                }
                continue
            }

            // If we were collecting a list and this line isn't a list item, finalize.
            if currentListKey != nil {
                currentListKey = nil
                currentList = []
            }

            // Skip empty lines.
            guard !trimmedLine.isEmpty else { continue }

            // Split on first colon.
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else { continue }

            let key = String(trimmedLine[trimmedLine.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            guard !key.isEmpty else { continue }

            if rawValue.isEmpty {
                // Value is on subsequent lines as a list.
                currentListKey = key
                currentList = []
            } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                // Inline list: [Read, Grep, Glob]
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
                result[key] = items
            } else {
                result[key] = rawValue
            }
        }

        return result
    }

    /// Generate a deterministic UUID from a string using SHA-256.
    ///
    /// Uses the first 16 bytes of the SHA-256 hash, with version/variant bits set
    /// for a UUID v5-like result. The same filename always produces the same UUID.
    static func deterministicUUID(from input: String) -> UUID {
        let namespace = "com.ghostties.presets"
        let combined = "\(namespace):\(input)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        var bytes = Array(hash.prefix(16))

        // Set version to 5 (name-based SHA).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        // Set variant to RFC 4122.
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

}
