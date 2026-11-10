import Foundation
import Testing
@testable import Ghostty

/// Coverage for `CodexHookRegistrar.register(hooksJSONPath:scriptPath:)`:
/// append-only, idempotent, and malformed/missing-file safe. Every test
/// works against a temp file and a private defaults suite — never
/// `~/.codex/hooks.json` or a real Ghostties defaults domain.
final class CodexHookRegistrarTests {
    private let suiteName = "ghostties.tests.codex-hook.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

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

        let ok = CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults)
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

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults))
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults))

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

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults))

        let root = readJSON(path)
        let hooks = try #require(root?["hooks"] as? [String: Any])
        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])

        #expect(stopEntries.count == 2, "the pre-existing entry must survive, with Ghostties' appended")

        let firstCommand = ((stopEntries[0]["hooks"] as? [[String: Any]])?.first?["command"] as? [String])?.first
        #expect(firstCommand == "/usr/bin/some-other-hook", "existing entry must stay at index 0, unreordered")

        let secondCommand = (stopEntries[1]["hooks"] as? [[String: Any]])?.first?["command"] as? [String]
        #expect(secondCommand == CodexHookRegistrar.guardedCommand(scriptPath: "/scripts/ghostties-status.sh"), "Ghostties' entry must be appended, not prepended")
    }

    @Test func leavesAMalformedFileUntouched() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let malformed = "{ this is not valid json"
        try malformed.write(toFile: path, atomically: true, encoding: .utf8)

        let ok = CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults)

        #expect(!ok)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == malformed, "a malformed file must be left byte-for-byte untouched, never overwritten")
    }

    @Test func neverWritesATrustOrBypassKey() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: "/scripts/ghostties-status.sh", defaults: defaults))

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!contents.contains("trusted_hash"))
        #expect(!contents.contains("hooks.state"))
        #expect(!contents.contains("dangerously-bypass"))
    }

    private let script = "/scripts/ghostties-status.sh"

    private func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test func writtenCommandIsGuardedExecForm() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))
        let hooks = try #require(readJSON(path)?["hooks"] as? [String: Any])
        let entry = try #require((hooks["Stop"] as? [[String: Any]])?.first)
        let inner = try #require((entry["hooks"] as? [[String: Any]])?.first)
        #expect(inner["command"] as? [String] == ["/bin/sh", "-c", "[ -x \"$1\" ] && \"$1\" codex || true", "sh", script])
        #expect(inner["async"] as? Bool == true)
    }

    @Test func migratesAnOldUnguardedEntryInPlaceAndLeavesOthersIntact() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        try write("""
        {"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":["/scripts/ghostties-status.sh","codex"],"async":true}]},
                          {"matcher":"x","hooks":[{"type":"command","command":["/usr/bin/other"],"async":true}]}]}}
        """, to: path)
        // Registered on an earlier version: only the migration is outstanding.
        defaults.set(true, forKey: CodexHookRegistrar.registeredKey)

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))

        let hooks = try #require(readJSON(path)?["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 2)
        let first = (stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? [String]
        #expect(first == CodexHookRegistrar.guardedCommand(scriptPath: script), "rewritten at the same position")
        let second = (stop[1]["hooks"] as? [[String: Any]])?.first?["command"] as? [String]
        #expect(second == ["/usr/bin/other"])
        #expect(hooks["PreToolUse"] == nil, "migration must not add entries to other events")
        #expect(defaults.bool(forKey: CodexHookRegistrar.guardedKey))
    }

    @Test func migrationIsIdempotent() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))
        let first = try #require(FileManager.default.contents(atPath: path))
        defaults.removeObject(forKey: CodexHookRegistrar.guardedKey)
        defaults.removeObject(forKey: CodexHookRegistrar.registeredKey)
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))
        #expect(try #require(FileManager.default.contents(atPath: path)) == first)
    }

    @Test func removedHookIsNotReAddedOnALaterLaunch() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))
        #expect(defaults.bool(forKey: CodexHookRegistrar.registeredKey))

        let removed = #"{"hooks":{}}"#
        try write(removed, to: path)

        #expect(CodexHookRegistrar.register(hooksJSONPath: path, scriptPath: script, defaults: defaults))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == removed)
    }
}
