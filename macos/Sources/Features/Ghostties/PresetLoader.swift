import Foundation
import CryptoKit
import OSLog
import GhosttiesCore

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
    static let seedVersion = 3

    /// Presets an earlier build seeded and the bundle has since retired, keyed
    /// by directory name. Each maps a file name to the SHA-256 of every
    /// version of that file the app ever shipped (from git history), so
    /// the seed pass can tell an untouched copy from one the user edited.
    private static let retiredPresets: [String: [String: Set<String>]] = [
        "linear-sync": [
            "README.md": [
                "e61feec5db1a44b0eaed9efb619ea9ff3b724eb7839573a2e6747a72b068d128",
                "08c1850323a731c89e1e3e047b0bde3fbd964d5957959d5f1e89445c1e29665e",
            ],
            "defaults.json": [
                "81db3ea78393ccc4388530f450a7defcf01aa8339239074b8d0d395cbff5eff5",
                "901cbd6993e47b19929fa2229596295a5a032b4bca3ad527fb8d669e2e248f8b",
                "5b96baa59e40dd604aeecefdc89e76ac79e78e9c08dbcd0fea69f31d2f0cd7ca",
            ],
            "mcp-servers.json": [
                "8d392b4270d6d2a951a6098f4d73182ec508ed0f3e8f9d42bd24d98ffedb95a7",
            ],
            "preset.json": [
                "b34679b42468661f1736f9470f4bdc696611b3a0fe66a9229e900fd235df408c",
            ],
            "system.md": [
                "6c55fc9cfdfe333a279af1b0bd9f638b7637393e50f7d72e0f003124e82b4d34",
                "389f1a0f139c2eb957ec1bfe5e082d11af5424775dd9016e4eb742c46d0708e1",
                "edc1e83a584d717c99ae4ce8670e9a4ef451eef5cc6e938a2f5b394d4573648b",
                "67df928325bd08de0f9e3d68e2f36ebd34beaa1d949c36ef72c3fa47ed70d14c",
                "6065f01c13949b43b747d3c196af7bd27f48da04e16960e7960dd641c19bb416",
            ],
        ],
    ]

    /// Seed bundled presets to `~/.ghostties/presets/` using versioned seeding.
    ///
    /// Recursively copies the `presets/` subdirectory from the app bundle into
    /// `~/.ghostties/presets/`. After copying, rewrites any `${HOME}` literals
    /// in `.json` files to the real home path. Only copies items that don't
    /// already exist — never overwrites user edits. A preset the bundle has
    /// retired (`retiredPresets`) is removed only if every file in it still
    /// matches what the app shipped; an edited copy is the user's and stays.
    ///
    /// The app currently bundles no presets (Linear Sync, the last one, was
    /// removed in 0.5.0-beta.26), so a missing bundled directory is the
    /// normal case, not an error: the version marker is written and nothing
    /// is copied. Both paths are parameters so a test can seed into a temp
    /// directory instead of the real `~/.ghostties`.
    @discardableResult
    static func seedIfNeeded(
        presetsDirectoryPath dirPath: String = presetsDirectoryPath,
        bundledPresetsURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("presets"),
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> SeedOutcome {
        let signpostState = Perf.signposter.beginInterval("presets.seed")
        defer { Perf.signposter.endInterval("presets.seed", signpostState) }
        let fm = FileManager.default
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
        guard currentVersion < seedVersion else { return .alreadySeeded }

        // Create the destination directory if it doesn't exist.
        if !fm.fileExists(atPath: dirPath) {
            do {
                try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o700,
                ])
            } catch {
                logger.error("Failed to create presets directory: \(error.localizedDescription)")
                return .failed
            }
        }

        removeRetiredPresets(in: dirPath, home: homeDirectoryPath, fm: fm)

        // Locate the bundled `presets/` resource directory. None bundled:
        // write the marker so this doesn't re-run every launch.
        guard let bundledPresetsURL, fm.fileExists(atPath: bundledPresetsURL.path) else {
            try? "\(seedVersion)".write(toFile: versionFilePath, atomically: true, encoding: .utf8)
            return .nothingBundled
        }

        // Recursively copy subdirectories (folder-format presets).
        let destURL = URL(fileURLWithPath: dirPath)
        copyResourceDirectory(from: bundledPresetsURL, to: destURL, fm: fm)

        // Rewrite ${HOME} literals in all .json files under the seeded directory.
        rewriteHomeInJSONFiles(in: destURL, home: homeDirectoryPath, fm: fm)

        // Write the new seed version marker.
        do {
            try "\(seedVersion)".write(toFile: versionFilePath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write seed version marker: \(error.localizedDescription)")
            return .failed
        }
        return .seeded
    }

    /// What `seedIfNeeded` did — returned so a test can tell "nothing to
    /// seed" apart from a failure without reading the log.
    enum SeedOutcome: Equatable {
        case alreadySeeded
        case nothingBundled
        case seeded
        case failed
    }

    // MARK: - Seed Helpers

    /// Remove each retired preset directory under `dirPath` whose files all
    /// hash to a version the app shipped. Any extra, missing-hash or edited
    /// file means the user touched it, so the whole directory is left alone.
    /// The seed rewrites `${HOME}` in `.json` files, so the home path is
    /// turned back into `${HOME}` before hashing to get the bundle's bytes.
    private static func removeRetiredPresets(in dirPath: String, home: String, fm: FileManager) {
        for (name, shippedHashes) in retiredPresets {
            let dirURL = URL(fileURLWithPath: dirPath).appendingPathComponent(name)
            guard let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            var untouched = true
            for case let fileURL as URL in enumerator {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      fileURL.deletingLastPathComponent().standardizedFileURL == dirURL.standardizedFileURL,
                      let known = shippedHashes[fileURL.lastPathComponent],
                      let data = try? Data(contentsOf: fileURL),
                      known.contains(SHA256.hash(data: unrewrittenHome(data, in: fileURL, home: home)).map { String(format: "%02x", $0) }.joined())
                else {
                    untouched = false
                    break
                }
            }
            guard untouched else { continue }
            do {
                try fm.removeItem(at: dirURL)
            } catch {
                logger.error("Failed to remove retired preset \(name): \(error.localizedDescription)")
            }
        }
    }

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

    /// `data` as the bundle shipped it: for a `.json` file, the real home
    /// path goes back to the `${HOME}` literal the seed replaced.
    private static func unrewrittenHome(_ data: Data, in fileURL: URL, home: String) -> Data {
        guard fileURL.pathExtension == "json", let text = String(data: data, encoding: .utf8) else { return data }
        return Data(text.replacingOccurrences(of: home, with: "${HOME}").utf8)
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

    /// Load all presets from `~/.ghostties/presets/`. Thin wrapper over
    /// `loadPresetsResult()` for callers that only need the templates, not
    /// whether the load genuinely succeeded (`WorkspacePersistence.swift`).
    ///
    /// Handles two formats:
    /// - **Flat `.md` files** with YAML frontmatter (legacy format).
    /// - **Folder presets**: subdirectories containing `preset.json`.
    ///
    /// Returns an array of `AgentTemplate` objects with `isDefault: true` and `isGlobal: true`.
    /// Templates have deterministic UUIDs generated from the filename/foldername so IDs persist across launches.
    static func loadPresets() -> [AgentTemplate] {
        loadPresetsResult().templates
    }

    /// DEFECT 5 fix (Composer UI 11 review round 2): `loadPresets()` alone
    /// cannot distinguish "the presets directory is genuinely empty" from
    /// "loading it soft-failed" (missing directory, a symlinked directory,
    /// an enumeration failure) — both return `[]` with no error surfaced.
    /// `SessionComposerStore.prunePins` needs that distinction to gate
    /// pruning on LOAD SUCCESS rather than inferring it from a count
    /// comparison against the id universe (see that function's doc
    /// comment). `loadSucceeded` is `false` for the directory-level
    /// soft-failure paths below (not a real directory / a symlinked
    /// directory / `contentsOfDirectory` throwing) AND when any individual
    /// `.md` or folder entry fails to parse (I/O failure, malformed
    /// frontmatter, missing `name`, rejected `command`) — those per-entry
    /// nils are exactly the "the preset did not genuinely go away" case
    /// this gate exists to catch (FIX 1, final review round). An
    /// empty-but-real presets directory with every entry parsing cleanly
    /// reports `true` with zero templates, which is the correct "nothing
    /// to prune against was lost" signal.
    static func loadPresetsResult() -> (templates: [AgentTemplate], loadSucceeded: Bool) {
        let signpostState = Perf.signposter.beginInterval("presets.load")
        defer { Perf.signposter.endInterval("presets.load", signpostState) }
        let fm = FileManager.default
        let dirPath = presetsDirectoryPath

        // Verify path is a real directory (not a symlink to an attacker-controlled location).
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { return ([], false) }
        let attrs = try? fm.attributesOfItem(atPath: dirPath)
        if let fileType = attrs?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
            logger.warning("Presets directory is a symlink — refusing to load")
            return ([], false)
        }

        do {
            let entries = try fm.contentsOfDirectory(atPath: dirPath)
            var templates: [AgentTemplate] = []
            var anyEntryFailedToParse = false

            // Flat .md presets (legacy format).
            let mdFiles = entries.filter { $0.hasSuffix(".md") }.sorted()
            for filename in mdFiles {
                let filePath = (dirPath as NSString).appendingPathComponent(filename)
                let url = URL(fileURLWithPath: filePath)
                if let template = parsePreset(at: url, filename: filename) {
                    templates.append(template)
                } else {
                    anyEntryFailedToParse = true
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
                } else {
                    anyEntryFailedToParse = true
                }
            }

            return (templates, !anyEntryFailedToParse)
        } catch {
            logger.error("Failed to read presets directory: \(error.localizedDescription)")
            return ([], false)
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
