import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Parsing, error paths and the mark handshake of the capture script
/// (`capture-script-schema.md`). The host is a fake; no window, no app.
@MainActor
@Suite(.serialized)
struct CaptureScriptTests {

    private func parse(_ json: String) throws -> [CaptureScript.Step] {
        try CaptureScript.parse(Data(json.utf8))
    }

    private func failure(_ json: String) -> String? {
        do { _ = try parse(json); return nil } catch let f as CaptureScript.Failure { return f.message } catch { return "other" }
    }

    // MARK: - Parsing

    @Test func parsesTheSchemaExample() throws {
        let steps = try parse("""
        {"steps": [
          {"op": "composer.open"},
          {"op": "rowPlus", "project": "switchboard", "option": false},
          {"op": "newSession"}, {"op": "newSessionInstant"},
          {"op": "type", "text": "switchboard ccp"},
          {"op": "key", "key": "return", "modifiers": []},
          {"op": "mark", "name": "after-return"},
          {"op": "wait", "seconds": 2},
          {"op": "pref", "key": "newSessionOpensComposer", "value": false}
        ]}
        """)
        #expect(steps == [
            .composerOpen, .rowPlus(project: "switchboard", option: false), .newSession, .newSessionInstant,
            .type("switchboard ccp"), .key(.init(key: "return", modifiers: [])), .mark("after-return"),
            .wait(2), .pref(false),
        ])
    }

    @Test func keyModifiersParse() throws {
        let steps = try parse(#"{"steps":[{"op":"key","key":"t","modifiers":["cmd","shift","option","ctrl"]}]}"#)
        #expect(steps == [.key(.init(key: "t", modifiers: [.command, .shift, .option, .control]))])
    }

    @Test func prefNullRemovesAndTrueParses() throws {
        #expect(try parse(#"{"steps":[{"op":"pref","key":"newSessionOpensComposer","value":null}]}"#) == [.pref(nil)])
        #expect(try parse(#"{"steps":[{"op":"pref","key":"newSessionOpensComposer","value":true}]}"#) == [.pref(true)])
    }

    // MARK: - Error paths

    @Test func rejectsBadInput() {
        #expect(failure("nope") == "script is not a JSON object")
        #expect(failure("{}") == "missing steps array")
        #expect(failure(#"{"steps":[{"op":"explode"}]}"#) == "step 0: unknown op 'explode'")
        #expect(failure(#"{"steps":[{}]}"#) == "step 0: missing op")
        #expect(failure(#"{"steps":[{"op":"newSession"},{"op":"type"}]}"#) == "step 1: type needs a text string")
        #expect(failure(#"{"steps":[{"op":"key","key":"pageup"}]}"#) == "step 0: unknown key 'pageup'")
        #expect(failure(#"{"steps":[{"op":"key","key":"a","modifiers":["hyper"]}]}"#) == "step 0: unknown modifier 'hyper'")
        #expect(failure(#"{"steps":[{"op":"wait","seconds":-1}]}"#) == "step 0: wait needs seconds >= 0")
        #expect(failure(#"{"steps":[{"op":"mark","name":"../x"}]}"#) != nil)
        #expect(failure(#"{"steps":[{"op":"rowPlus","project":"p","option":"yes"}]}"#) == "step 0: option must be a boolean")
    }

    @Test func prefRejectsUnknownKeyAndBadValue() {
        #expect(failure(#"{"steps":[{"op":"pref","key":"sidebarTab","value":true}]}"#)
            == "step 0: pref key must be newSessionOpensComposer")
        #expect(failure(#"{"steps":[{"op":"pref","key":"newSessionOpensComposer","value":1}]}"#)
            == "step 0: value must be a boolean")
        #expect(failure(#"{"steps":[{"op":"pref","key":"newSessionOpensComposer"}]}"#)
            == "step 0: pref needs a value (true, false or null)")
    }

    // MARK: - pref lands in the capture suite only

    @Test func prefWritesTheCaptureSuiteNotStandard() {
        let key = "ghostties.newSessionOpensComposer"
        let standardBefore = UserDefaults.standard.object(forKey: key) as? Bool
        let suite = UserDefaults(suiteName: CaptureFixture.defaultsSuiteName)!
        defer {
            CaptureFixture.cleanUpDefaults(fixtureActive: true)
            // A regression would have written Dev's domain; put it back.
            if let standardBefore { UserDefaults.standard.set(standardBefore, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        CaptureScript.applyPref(!(standardBefore ?? true))
        #expect(suite.object(forKey: key) as? Bool == !(standardBefore ?? true))
        #expect(UserDefaults.standard.object(forKey: key) as? Bool == standardBefore)

        CaptureScript.applyPref(nil)
        #expect(suite.object(forKey: key) == nil)
        #expect(UserDefaults.standard.object(forKey: key) as? Bool == standardBefore)
    }

    // MARK: - Runner

    private final class FakeHost: CaptureScript.Host {
        var calls: [String] = []
        var isReady = true
        func composerOpen() { calls.append("composer.open") }
        func rowPlus(project: String, option: Bool) throws {
            if project == "ghost" { throw CaptureScript.Failure("rowPlus: no project named 'ghost'") }
            calls.append("rowPlus:\(project):\(option)")
        }
        func newSession() { calls.append("newSession") }
        func newSessionInstant() { calls.append("newSessionInstant") }
        func type(_ text: String) { calls.append("type:\(text)") }
        func key(_ spec: CaptureScript.KeySpec) { calls.append("key:\(spec.key)") }
        func setPref(_ value: Bool?) { calls.append("pref:\(String(describing: value))") }
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString)", isDirectory: true)
    }

    private func exists(_ dir: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    @Test func runnerRunsStepsInOrderAndWritesDone() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir).run([
            .composerOpen, .type("a"), .key(.init(key: "return", modifiers: [])), .rowPlus(project: "wren", option: true), .wait(0),
        ])
        #expect(host.calls == ["composer.open", "type:a", "key:return", "rowPlus:wren:true"])
        #expect(exists(dir, "script.done"))
        #expect(!exists(dir, "script.error"))
    }

    @Test func runnerStopsAndWritesOneLineErrorOnHostFailure() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir).run([
            .newSession, .rowPlus(project: "ghost", option: false), .newSessionInstant,
        ])
        #expect(host.calls == ["newSession"])
        let text = try String(contentsOf: dir.appendingPathComponent("script.error"), encoding: .utf8)
        #expect(text == "step 1: rowPlus: no project named 'ghost'\n")
        #expect(!exists(dir, "script.done"))
    }

    @Test func badScriptFileWritesErrorAndRunsNothing() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"steps":[{"op":"newSession"},{"op":"nope"}]}"#.utf8).write(to: file)
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir).run(scriptAt: file.path)
        #expect(host.calls.isEmpty)
        #expect(try String(contentsOf: dir.appendingPathComponent("script.error"), encoding: .utf8)
            == "step 1: unknown op 'nope'\n")
    }

    @Test func markWaitsForDoneThenContinues() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        let runner = CaptureScript.Runner(host: host, stateDir: dir, markTimeout: 5, pollInterval: 0.01)
        let task = Task { await runner.run([.mark("m1"), .newSession]) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(host.calls.isEmpty) // still blocked on the handshake
        let log = try String(contentsOf: dir.appendingPathComponent("marks.jsonl"), encoding: .utf8)
        #expect(log.contains("\"name\":\"m1\""))
        try Data().write(to: dir.appendingPathComponent("marks/m1.done"))
        await task.value
        #expect(host.calls == ["newSession"])
        #expect(exists(dir, "script.done"))
    }

    @Test func markTimeoutWritesErrorAndStops() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir, markTimeout: 0.2, pollInterval: 0.01)
            .run([.mark("never"), .newSession])
        #expect(host.calls.isEmpty)
        #expect(try String(contentsOf: dir.appendingPathComponent("script.error"), encoding: .utf8)
            == "step 0: mark 'never' timed out waiting for .done\n")
        #expect(!exists(dir, "script.done"))
    }
}
