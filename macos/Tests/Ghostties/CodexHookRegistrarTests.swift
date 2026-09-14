import Foundation
import Testing
@testable import Ghostty

/// Coverage for `CodexHookRegistrar.register(hooksJSONPath:scriptPath:)`:
/// append-only, idempotent, and malformed/missing-file safe. Every test
/// works against a temp file — never `~/.codex/hooks.json`.
struct CodexHookRegistrarTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexHookRegistrarTests-\(UUID().uuidString)")
            .appendingPathComponent("hooks.json")
            .path
    }

    private func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func createsHooksJSONWhenAbsent() {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let ok = CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh")
        #expect(ok)
        #expect(FileManager.default.fileExists(atPath: path))

        let root = readJSON(path)
        let hooks = root?["hooks"] as? [String: Any]
        for event in CodexHookRegistrar.events {
            #expect(hooks?[event] != nil, "missing event \(event)")
        }
    }

    @Test func isIdempotentOnASecondRegister() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh"))
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh"))

        let root = readJSON(path)
        let hooks = try #require(root?["hooks"] as? [String: Any])
        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stopEntries.count == 1, "registering twice must not duplicate the entry")
    }

    @Test func appendsAfterExistingEntriesWithoutModifyingThem() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let existing = """
        {"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":["/usr/bin/some-other-hook"],"async":true}]}]}}
        """
        try existing.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh"))

        let root = readJSON(path)
        let hooks = try #require(root?["hooks"] as? [String: Any])
        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])

        #expect(stopEntries.count == 2, "the pre-existing entry must survive, with Ghostties' appended")

        let firstCommand = ((stopEntries[0]["hooks"] as? [[String: Any]])?.first?["command"] as? [String])?.first
        #expect(firstCommand == "/usr/bin/some-other-hook", "existing entry must stay at index 0, unreordered")

        let secondCommand = ((stopEntries[1]["hooks"] as? [[String: Any]])?.first?["command"] as? [String])?.first
        #expect(secondCommand == "/scripts/ghostties-status.sh", "Ghostties' entry must be appended, not prepended")
    }

    @Test func leavesAMalformedFileUntouched() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let malformed = "{ this is not valid json"
        try malformed.write(toFile: path, atomically: true, encoding: .utf8)

        let ok = CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh")

        #expect(!ok)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == malformed, "a malformed file must be left byte-for-byte untouched, never overwritten")
    }

    @Test func neverWritesATrustOrBypassKey() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh"))

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!contents.contains("trusted_hash"))
        #expect(!contents.contains("hooks.state"))
        #expect(!contents.contains("dangerously-bypass"))
    }
}
