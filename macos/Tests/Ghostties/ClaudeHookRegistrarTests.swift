import Foundation
import Testing
@testable import Ghostty

/// `ClaudeHookRegistrar.register(settingsPath:scriptPath:)` against temp
/// files only — never the real `~/.claude/settings.json`.
struct ClaudeHookRegistrarTests {
    private let script = "/home/u/.ghostties/hooks/ghostties-status.sh"

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeHookRegistrarTests-\(UUID().uuidString)")
            .appendingPathComponent("settings.json").path
    }

    private func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    private func readJSON(_ path: String) -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private func ghosttiesCount(_ entries: [[String: Any]]) -> Int {
        entries.filter { e in
            ((e["hooks"] as? [[String: Any]]) ?? []).contains {
                ($0["command"] as? String)?.contains("ghostties-status.sh") == true
            }
        }.count
    }

    private func firstCommand(_ entry: [String: Any]) -> String? {
        (entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }

    @Test func mergeKeepsExistingKeysAndHooksAndAddsOursOnce() throws {
        let path = tempPath(); defer { cleanup(path) }
        try write("""
        {"model":"opus","permissions":{"allow":["Bash(ls)"]},
         "hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/usr/bin/other-a"}]},
                          {"matcher":"x","hooks":[{"type":"command","command":"/usr/bin/other-b"}]}],
                  "Custom":[{"matcher":"","hooks":[{"type":"command","command":"keep"}]}]}}
        """, to: path)

        #expect(ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))

        let root = try #require(readJSON(path))
        #expect(root["model"] as? String == "opus")
        #expect((root["permissions"] as? [String: Any]) != nil)
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["Custom"] != nil)
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        // Existing hooks keep positions 0 and 1; ours is appended at 2.
        #expect(stop.count == 3)
        #expect(firstCommand(stop[0]) == "/usr/bin/other-a")
        #expect(firstCommand(stop[1]) == "/usr/bin/other-b")
        #expect(ghosttiesCount(stop) == 1)
        for (event, _) in ClaudeHookRegistrar.events {
            #expect(ghosttiesCount(try #require(hooks[event] as? [[String: Any]])) == 1, "\(event)")
        }
    }

    @Test func secondRunIsANoOp() throws {
        let path = tempPath(); defer { cleanup(path) }
        try write(#"{"model":"opus"}"#, to: path)
        #expect(ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))
        let first = try #require(FileManager.default.contents(atPath: path))
        #expect(ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))
        let second = try #require(FileManager.default.contents(atPath: path))
        #expect(first == second)
    }

    @Test func recognisesAHandPastedEntryAndDoesNotDuplicateIt() throws {
        let path = tempPath(); defer { cleanup(path) }
        try write(#"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"\"$HOME\"/.ghostties/hooks/ghostties-status.sh","async":true}]}]}}"#, to: path)
        #expect(ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))
        let hooks = try #require(readJSON(path)?["hooks"] as? [String: Any])
        #expect(ghosttiesCount(try #require(hooks["Stop"] as? [[String: Any]])) == 1)
    }

    @Test func invalidJSONIsLeftUntouched() throws {
        let path = tempPath(); defer { cleanup(path) }
        let bad = #"{"hooks": {oops"#
        try write(bad, to: path)
        #expect(!ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == bad)
    }

    @Test func missingDirectoryMeansNothingIsCreated() {
        let path = tempPath()
        #expect(!ClaudeHookRegistrar.register(settingsPath: path, scriptPath: script))
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
