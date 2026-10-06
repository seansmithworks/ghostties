import Foundation
import Testing
@testable import Ghostty

/// The dispatch log is the harness's ground truth for "what did the app
/// spawn". Its line shape is fixed by `capture-script-schema.md`.
struct CaptureDispatchLogTests {

    @Test func lineHasTheSchemaFields() throws {
        let data = CaptureFixture.dispatchLine(
            t: 12.5, project: "switchboard", cwd: "/tmp/x", command: "claude", template: "ABC")
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(obj.keys) == ["t", "project", "cwd", "command", "template"])
        #expect(obj["project"] as? String == "switchboard")
        #expect(obj["cwd"] as? String == "/tmp/x")
        #expect(obj["command"] as? String == "claude")
        #expect(obj["template"] as? String == "ABC")
        #expect(obj["t"] as? Double == 12.5)
    }

    @Test func missingCommandAndTemplateAreNull() throws {
        let data = CaptureFixture.dispatchLine(t: 1, project: "p", cwd: "/c", command: nil, template: nil)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["command"] is NSNull)
        #expect(obj["template"] is NSNull)
    }

    @Test func appendWritesOneLinePerCall() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dispatch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("dispatch.jsonl")
        CaptureFixture.appendLine(CaptureFixture.dispatchLine(t: 1, project: "a", cwd: "/", command: nil, template: nil), to: url)
        CaptureFixture.appendLine(CaptureFixture.dispatchLine(t: 2, project: "b", cwd: "/", command: nil, template: nil), to: url)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("\"project\":\"b\""))
    }

    @Test func stateDirResolvesOnlyInFixtureMode() {
        let env = ["GHOSTTIES_STATE_DIR": "/tmp/sd"]
        #expect(CaptureFixture.stateDir(fixtureActive: false, env: env) == nil)
        #expect(CaptureFixture.stateDir(fixtureActive: true, env: [:]) == nil)
        #expect(CaptureFixture.stateDir(fixtureActive: true, env: ["GHOSTTIES_STATE_DIR": ""]) == nil)
        #expect(CaptureFixture.stateDir(fixtureActive: true, env: env)?.path == "/tmp/sd")
    }

    @Test func logDispatchWritesNothingWithoutAStateDir() throws {
        // What a non-fixture launch resolves to, even with the env var set.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dispatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolved = CaptureFixture.stateDir(fixtureActive: false, env: ["GHOSTTIES_STATE_DIR": dir.path])
        CaptureFixture.logDispatch(project: "p", cwd: "/", command: nil, template: nil, stateDir: resolved)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func logDispatchWritesOneLineWithAStateDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dispatch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        CaptureFixture.logDispatch(project: "p", cwd: "/", command: "c", template: "t", stateDir: dir)
        let text = try String(contentsOf: dir.appendingPathComponent("dispatch.jsonl"), encoding: .utf8)
        #expect(text.split(separator: "\n").count == 1)
    }
}
