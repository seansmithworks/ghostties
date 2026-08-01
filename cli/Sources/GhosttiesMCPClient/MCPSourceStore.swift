import Foundation
import GhosttiesCore

/// Persists the list of configured MCP sources to `~/.ghostties/mcp-sources.json`.
///
/// This is intentionally the user's home directory ONLY — never a project-relative
/// path. MCP source definitions name a binary to spawn; if discovery walked up from
/// cwd, opening any cloned repo containing a committed `.ghostties/mcp-sources.json`
/// could point Ghostties at an arbitrary binary the repo author chose. Loading only
/// from `~/.ghostties/` means a source must be something the user configured
/// themselves, never something a repo can plant.
///
/// Pretty-printed JSON with sorted keys so the file diffs cleanly in git.
public struct MCPSourceStore {
    /// Filename inside the `.ghostties/` directory.
    public static let filename = "mcp-sources.json"

    /// Resolved absolute path to the sources file.
    public let fileURL: URL

    /// Initialize with an explicit file URL (used by tests).
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Point at `~/.ghostties/mcp-sources.json`. Never walks the project tree —
    /// MCP sources are user-level configuration, not project-level.
    public static func discover() -> MCPSourceStore {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let state = home.appendingPathComponent(".ghostties", isDirectory: true)
        return MCPSourceStore(fileURL: state.appendingPathComponent(filename))
    }

    /// Load sources. Returns `[]` if the file doesn't exist. Throws
    /// `MCPError.decodingFailed` on malformed JSON or schema mismatch.
    public func load() throws -> [MCPSource] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MCPError.decodingFailed("read \(fileURL.path): \(error.localizedDescription)")
        }
        // Empty file is treated as empty list (ergonomic: `touch mcp-sources.json` works).
        if data.isEmpty { return [] }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([MCPSource].self, from: data)
        } catch {
            throw MCPError.decodingFailed("parse \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Save sources. Creates the parent `.ghostties/` directory if needed.
    /// Writes pretty-printed, sorted-keys JSON for git-friendly diffs.
    public func save(_ sources: [MCPSource]) throws {
        let parent = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw MCPError.transportFailed("create \(parent.path): \(error.localizedDescription)")
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(sources)
        } catch {
            throw MCPError.decodingFailed("encode sources: \(error.localizedDescription)")
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw MCPError.transportFailed("write \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
