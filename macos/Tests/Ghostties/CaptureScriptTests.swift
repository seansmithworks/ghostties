import AppKit
import Foundation
import GhosttiesCore
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

    @Test func rejectsUnknownFieldsPerOp() {
        #expect(failure(#"{"steps":[{"op":"key","key":"a","modifier":["cmd"]}]}"#)
            == "step 0: unknown field 'modifier' for op 'key'")
        #expect(failure(#"{"steps":[{"op":"newSession","project":"x"}]}"#)
            == "step 0: unknown field 'project' for op 'newSession'")
        #expect(failure(#"{"steps":[{"op":"wait","seconds":1,"secs":2}]}"#)
            == "step 0: unknown field 'secs' for op 'wait'")
    }

    @Test func rejectsDuplicateMarkNames() {
        #expect(failure(#"{"steps":[{"op":"mark","name":"a"},{"op":"wait","seconds":0},{"op":"mark","name":"a"}]}"#)
            == "step 2: duplicate mark 'a'")
        #expect(failure(#"{"steps":[{"op":"mark","name":"a"},{"op":"mark","name":"b"}]}"#) == nil)
    }

    @Test func composerFocusTimeoutWritesErrorAndStops() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        host.focusResult = false
        await CaptureScript.Runner(host: host, stateDir: dir).run([.composerOpen, .type("lost")])
        #expect(host.calls == ["composer.open", "waitFocus"])
        #expect(try String(contentsOf: dir.appendingPathComponent("script.error"), encoding: .utf8)
            == "step 0: composer field never became first responder\n")
    }

    @Test func noFocusWaitWhenTheComposerIsNotOpening() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir).run([.newSession, .rowPlus(project: "p", option: true)])
        #expect(!host.calls.contains("waitFocus"))
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

    // MARK: - Sidebar ops

    @Test func parsesSidebarOps() throws {
        let steps = try parse("""
        {"steps": [
          {"op": "foldAll"}, {"op": "unpin", "project": "trove"}, {"op": "unfold", "project": "switchboard"},
          {"op": "fold", "project": "wren"}, {"op": "select", "session": "rate limiter"}, {"op": "pin", "project": "atlas-api"}
        ]}
        """)
        #expect(steps == [
            .foldAll, .unpin(project: "trove"), .unfold(project: "switchboard"),
            .fold(project: "wren"), .select(session: "rate limiter"), .pin(project: "atlas-api"),
        ])
    }

    @Test func sidebarOpsRejectBadFields() {
        #expect(failure(#"{"steps":[{"op":"fold"}]}"#) == "step 0: fold needs a project string")
        #expect(failure(#"{"steps":[{"op":"unfold","project":""}]}"#) == "step 0: unfold needs a project string")
        #expect(failure(#"{"steps":[{"op":"select"}]}"#) == "step 0: select needs a session string")
        #expect(failure(#"{"steps":[{"op":"select","project":"x"}]}"#) == "step 0: unknown field 'project' for op 'select'")
        #expect(failure(#"{"steps":[{"op":"foldAll","project":"x"}]}"#) == "step 0: unknown field 'project' for op 'foldAll'")
        #expect(failure(#"{"steps":[{"op":"pin","session":"x"}]}"#) == "step 0: unknown field 'session' for op 'pin'")
    }

    @Test func runnerDispatchesSidebarOpsInOrder() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = FakeHost()
        await CaptureScript.Runner(host: host, stateDir: dir).run([
            .foldAll, .unpin(project: "trove"), .unfold(project: "switchboard"), .select(session: "flaky ci"),
            .fold(project: "switchboard"), .pin(project: "trove"),
        ])
        #expect(host.calls == ["foldAll", "unpin:trove", "unfold:switchboard", "select:flaky ci", "fold:switchboard", "pin:trove"])
        #expect(exists(dir, "script.done"))
    }

    @Test func unknownNamesStopTheScriptWithAnError() async throws {
        for (step, message) in [
            (CaptureScript.Step.fold(project: "ghost"), "step 1: fold: no project named 'ghost'"),
            (.select(session: "ghost"), "step 1: select: no session named 'ghost'"),
            (.pin(project: "ghost"), "step 1: pin: no project named 'ghost'"),
        ] {
            let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let host = FakeHost()
            await CaptureScript.Runner(host: host, stateDir: dir).run([.foldAll, step, .foldAll])
            #expect(host.calls == ["foldAll"])
            #expect(try String(contentsOf: dir.appendingPathComponent("script.error"), encoding: .utf8) == message + "\n")
            #expect(!exists(dir, "script.done"))
        }
    }

    @Test func nameResolutionIsCaseInsensitiveAndExact() throws {
        let a = Project(name: "switchboard", rootPath: "/tmp/a")
        let b = Project(name: "atlas-api", rootPath: "/tmp/b")
        #expect(try CaptureScript.resolveProject("SWITCHBOARD", in: [a, b], op: "fold").id == a.id)
        #expect(throws: CaptureScript.Failure.self) { try CaptureScript.resolveProject("switch", in: [a, b], op: "fold") }
        let dup = Project(name: "Switchboard", rootPath: "/tmp/c")
        #expect(throws: CaptureScript.Failure.self) { try CaptureScript.resolveProject("switchboard", in: [a, dup], op: "fold") }

        let t = UUID()
        let s1 = AgentSession(name: "rate limiter", templateId: t, projectId: a.id)
        let s2 = AgentSession(name: "auth migration", templateId: t, projectId: b.id)
        #expect(try CaptureScript.resolveSession("Auth Migration", in: [s1, s2]).id == s2.id)
        #expect(throws: CaptureScript.Failure.self) { try CaptureScript.resolveSession("auth", in: [s1, s2]) }
        let s3 = AgentSession(name: "rate limiter", templateId: t, projectId: b.id)
        #expect(throws: CaptureScript.Failure.self) { try CaptureScript.resolveSession("rate limiter", in: [s1, s3]) }
    }

    @Test func setFoldedEditsTheStoredSet() {
        let a = UUID(), b = UUID()
        let both = ProjectAccordionState.setFolded("", ids: [a, b], folded: true)
        #expect(ProjectAccordionState.decode(both) == [a, b])
        #expect(ProjectAccordionState.decode(ProjectAccordionState.setFolded(both, ids: [a], folded: false)) == [b])
        #expect(ProjectAccordionState.setFolded(both, ids: [a], folded: true) == both)
    }

    // MARK: - Runner

    private final class FakeHost: CaptureScript.Host {
        var calls: [String] = []
        var isReady = true
        var focusResult = true
        func composerOpen() -> Bool { calls.append("composer.open"); return true }
        func rowPlus(project: String, option: Bool) throws -> Bool {
            if project == "ghost" { throw CaptureScript.Failure("rowPlus: no project named 'ghost'") }
            calls.append("rowPlus:\(project):\(option)")
            return !option
        }
        func newSession() -> Bool { calls.append("newSession"); return false }
        func waitForComposerFocus() async -> Bool { calls.append("waitFocus"); return focusResult }
        func newSessionInstant() { calls.append("newSessionInstant") }
        func type(_ text: String) { calls.append("type:\(text)") }
        func key(_ spec: CaptureScript.KeySpec) { calls.append("key:\(spec.key)") }
        func setPref(_ value: Bool?) { calls.append("pref:\(String(describing: value))") }
        func foldAll() { calls.append("foldAll") }
        func setFolded(project: String, folded: Bool) throws {
            try known(project, op: folded ? "fold" : "unfold"); calls.append("\(folded ? "fold" : "unfold"):\(project)")
        }
        func select(session: String) throws {
            if session == "ghost" { throw CaptureScript.Failure("select: no session named 'ghost'") }
            calls.append("select:\(session)")
        }
        func setPinned(project: String, pinned: Bool) throws {
            try known(project, op: pinned ? "pin" : "unpin"); calls.append("\(pinned ? "pin" : "unpin"):\(project)")
        }
        private func known(_ project: String, op: String) throws {
            if project == "ghost" { throw CaptureScript.Failure("\(op): no project named 'ghost'") }
        }
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
        #expect(host.calls == ["composer.open", "waitFocus", "type:a", "key:return", "rowPlus:wren:true"])
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
        let task = _Concurrency.Task { await runner.run([.mark("m1"), .newSession]) }
        try await _Concurrency.Task.sleep(for: .milliseconds(200))
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
