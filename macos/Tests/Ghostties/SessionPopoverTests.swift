// IDE-ONLY: not currently exercised in CI macos job (build-only).
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Coverage for the sidebar session popover's data path: `tool_input`
/// decoding on `PermissionRequest`, the pure state -> card content mapping,
/// and the rule that approval text never outlives its `.needsPermission`
/// state. Payloads are invented (no real paths or commands).
@MainActor
final class SessionPopoverTests: XCTestCase {
    private let sessionId = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000AA")!
    private let now = Date(timeIntervalSince1970: 1_700_000_100)

    // MARK: - Helpers

    private func derive(_ hook: String) -> ClaudeState? {
        let json = #"""
        {"ghosttiesSessionId":"\#(sessionId.uuidString)","updatedAt":1700000090,"hook":\#(hook)}
        """#
        guard let wrapper = try? JSONDecoder().decode(ClaudeHookWrapper.self, from: Data(json.utf8)) else {
            XCTFail("fixture failed to decode: \(json)")
            return nil
        }
        return ClaudeStateStore.derive(from: wrapper)
    }

    private func content(
        indicator: SessionIndicatorState,
        approval: ClaudeState?
    ) -> SessionPopoverContent {
        SessionPopoverContent.make(
            sessionId: sessionId,
            title: "DAB",
            cwd: "/Users/example/work/dab",
            agent: "claude",
            indicator: indicator,
            approval: approval,
            fallbackDate: nil,
            now: now,
            homeDirectory: "/Users/example"
        )
    }

    private let bashPermission = #"""
    {"cwd":"/Users/example/work/dab","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"rm -rf build/","description":"Clean stale artifacts before rebuild"}}
    """#

    private let editPermission = #"""
    {"cwd":"/Users/example/work/dab","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Edit","tool_input":{"file_path":"src/server/config.ts","old_string":"a","new_string":"b"}}
    """#

    // MARK: - (a) Decoding

    func testDecodesBashToolInput() {
        let state = derive(bashPermission)
        XCTAssertEqual(state?.state, .needsPermission)
        XCTAssertEqual(state?.structuredPrompt?.toolName, "Bash")
        XCTAssertEqual(state?.structuredPrompt?.toolInput?.command, "rm -rf build/")
        XCTAssertEqual(state?.structuredPrompt?.toolInput?.description, "Clean stale artifacts before rebuild")
        XCTAssertNil(state?.structuredPrompt?.toolInput?.filePath)
    }

    func testDecodesEditToolInput() {
        let state = derive(editPermission)
        XCTAssertEqual(state?.structuredPrompt?.toolName, "Edit")
        XCTAssertEqual(state?.structuredPrompt?.toolInput?.filePath, "src/server/config.ts")
        XCTAssertNil(state?.structuredPrompt?.toolInput?.command)
    }

    func testMissingToolInputStillDerivesNeedsPermission() {
        let state = derive(#"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Write"}"#)
        XCTAssertEqual(state?.state, .needsPermission)
        XCTAssertEqual(state?.structuredPrompt?.toolName, "Write")
        XCTAssertNil(state?.structuredPrompt?.toolInput)
    }

    func testOddToolInputShapesDoNotFailTheWholeState() {
        // tool_input as a string, and with wrongly-typed fields: the state
        // must still derive (a decode failure would silently drop the session).
        let asString = derive(#"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":"rm -rf build/"}"#)
        XCTAssertEqual(asString?.state, .needsPermission)
        XCTAssertNil(asString?.structuredPrompt?.toolInput?.command)

        let wrongTypes = derive(#"{"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"Bash","tool_input":{"command":42,"description":["x"]}}"#)
        XCTAssertEqual(wrongTypes?.state, .needsPermission)
        XCTAssertNil(wrongTypes?.structuredPrompt?.toolInput?.command)
    }

    func testToolInputIsNotCarriedOnNonPermissionStates() {
        let busy = derive(#"{"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(busy?.state, .busy)
        XCTAssertNil(busy?.structuredPrompt)
    }

    // MARK: - (b) State -> content

    func testNeedsBashMapsToCommandHero() {
        let card = content(indicator: .needsAttention, approval: derive(bashPermission))
        XCTAssertTrue(card.isApproval)
        XCTAssertEqual(card.statusLabel, "Needs approval")
        XCTAssertEqual(card.statusDetail, "Bash")
        XCTAssertEqual(card.subtitle, "~/work/dab · claude")
        XCTAssertEqual(card.body, .commandHero(command: "rm -rf build/", description: "Clean stale artifacts before rebuild"))
    }

    func testNeedsEditMapsToMiniTerminalLines() {
        var input = derive(editPermission)
        input = input.map {
            ClaudeState(
                ghosttiesSessionId: $0.ghosttiesSessionId, claudeSessionId: $0.claudeSessionId, cwd: $0.cwd,
                state: $0.state,
                structuredPrompt: StructuredPrompt(
                    toolName: "Edit", toolUseId: nil,
                    toolInput: ToolInputSummary(description: "Raise the timeout", filePath: "src/server/config.ts")
                ),
                updatedAt: $0.updatedAt
            )
        }
        let card = content(indicator: .needsAttention, approval: input)
        XCTAssertEqual(card.body, .miniTerminal(lines: [
            .init(text: "● Edit(src/server/config.ts)", tone: .primary),
            .init(text: "  Raise the timeout", tone: .secondary),
            .init(text: "  Do you want to proceed?", tone: .alert),
        ]))
    }

    func testEditWithoutDescriptionOmitsThatLine() {
        let card = content(indicator: .needsAttention, approval: derive(editPermission))
        XCTAssertEqual(card.body, .miniTerminal(lines: [
            .init(text: "● Edit(src/server/config.ts)", tone: .primary),
            .init(text: "  Do you want to proceed?", tone: .alert),
        ]))
    }

    func testRunningIsPassiveWithNoApprovalText() {
        let card = content(indicator: .processing, approval: nil)
        XCTAssertFalse(card.isApproval)
        XCTAssertEqual(card.statusLabel, "Running")
        XCTAssertNil(card.statusDetail)
        XCTAssertEqual(card.body, .none)
    }

    // MARK: - (c) Staleness

    func testStateChangeFromPermissionToBusyDropsApprovalContent() {
        // Real derive() path: PermissionRequest, then the PostToolUse that
        // lands once the user answers in the terminal.
        let needs = derive(bashPermission)
        let shownWhileWaiting = content(indicator: .needsAttention, approval: needs)
        XCTAssertEqual(shownWhileWaiting.statusDetail, "Bash")

        let after = derive(#"{"cwd":"/tmp","hook_event_name":"PostToolUse","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}"#)
        XCTAssertEqual(after?.state, .busy)
        let card = content(indicator: .processing, approval: after)
        XCTAssertFalse(card.isApproval)
        XCTAssertEqual(card.body, .none)
        XCTAssertNil(card.statusDetail)
        XCTAssertFalse(String(describing: card).contains("rm -rf"))
    }

    func testOldPermissionStateIsNotShownAsApproval() {
        guard let needs = derive(bashPermission) else { return }
        let later = needs.updatedAt.addingTimeInterval(ClaudeStateStore.staleInterval + 1)
        let card = SessionPopoverContent.make(
            sessionId: sessionId, title: "DAB", cwd: nil, agent: "claude",
            indicator: .idle, approval: needs, fallbackDate: nil, now: later
        )
        XCTAssertFalse(card.isApproval)
        XCTAssertEqual(card.body, .none)
    }

    func testPermissionWithoutToolDetailHasNoBodyBlock() {
        let state = derive(#"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"c-1"}"#)
        let card = content(indicator: .needsAttention, approval: state)
        XCTAssertTrue(card.isApproval)
        XCTAssertEqual(card.body, .none)
    }

    // MARK: - "What's happening" summary (invented text only)

    private func hookPayload(_ json: String) -> ClaudeHookPayload {
        try! JSONDecoder().decode(ClaudeHookPayload.self, from: Data(json.utf8))
    }

    private let promptEvent = #"{"hook_event_name":"UserPromptSubmit","session_id":"c-1","prompt":"fix  the flaky\n  router tests"}"#
    private let bashEvent = #"{"hook_event_name":"PreToolUse","session_id":"c-1","tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"npm test\nsecond line"}}"#
    private func editDone(_ id: String) -> String {
        #"{"hook_event_name":"PostToolUse","session_id":"c-1","tool_name":"Edit","tool_use_id":"\#(id)","tool_input":{"file_path":"src/server/config.ts"}}"#
    }
    private let stopEvent = #"{"hook_event_name":"Stop","session_id":"c-1"}"#

    /// Feed events one second apart, as the state file would deliver them.
    private func ingest(_ events: [String], into summary: SessionSummary = SessionSummary()) -> SessionSummary {
        var summary = summary
        for (index, event) in events.enumerated() {
            summary.ingest(hookPayload(event), updatedAt: now.addingTimeInterval(Double(index - 20)))
        }
        return summary
    }

    private func card(_ summary: SessionSummary?, indicator: SessionIndicatorState) -> SessionPopoverContent {
        SessionPopoverContent.make(
            sessionId: sessionId, title: "DAB", cwd: nil, agent: "claude",
            indicator: indicator, approval: nil, summary: summary, fallbackDate: nil, now: now
        )
    }

    func testRunningSummaryShowsPromptStepAndEditCount() {
        let summary = ingest([promptEvent, bashEvent, editDone("e1"), editDone("e2")])
        let running = card(summary, indicator: .processing)
        XCTAssertEqual(running.statusLabel, "Running")
        XCTAssertEqual(running.statusDetail, "npm test")
        XCTAssertEqual(running.body, .summary(
            task: "fix the flaky router tests",
            detail: "Now: running npm test \u{00B7} 2 edits so far"
        ))
    }

    func testRepeatedReadOfTheSameEventDoesNotDoubleCount() {
        var summary = ingest([promptEvent, editDone("e1")])
        // refresh() re-decodes an unchanged file: same event, same timestamp.
        summary.ingest(hookPayload(editDone("e1")), updatedAt: now.addingTimeInterval(-19))
        summary.ingest(hookPayload(editDone("e1")), updatedAt: now.addingTimeInterval(-19))
        XCTAssertEqual(summary.editCount, 1)
    }

    func testNewPromptResetsCountAndPrompt() {
        var summary = ingest([promptEvent, bashEvent, editDone("e1")])
        XCTAssertEqual(summary.editCount, 1)
        summary.ingest(
            hookPayload(#"{"hook_event_name":"UserPromptSubmit","session_id":"c-1","prompt":"tidy the config"}"#),
            updatedAt: now.addingTimeInterval(-5)
        )
        XCTAssertEqual(summary.prompt, "tidy the config")
        XCTAssertEqual(summary.editCount, 0)
        XCTAssertNil(summary.currentStep)
        XCTAssertEqual(card(summary, indicator: .processing).body, .summary(task: "tidy the config", detail: nil))
    }

    func testStopShowsDoneWithEditCountAndNoNowLine() {
        let summary = ingest([promptEvent, bashEvent, editDone("e1"), editDone("e2"), stopEvent])
        let done = card(summary, indicator: .idle)
        XCTAssertEqual(done.body, .summary(task: "Done: fix the flaky router tests", detail: "2 edits"))
        XCTAssertNil(done.statusDetail)
        // A finished summary must not decorate a card that says Running.
        XCTAssertEqual(card(summary, indicator: .processing).body, .none)
    }

    func testNoSummaryDataMeansNoBlock() {
        XCTAssertEqual(card(nil, indicator: .processing).body, .none)
        // Mid-turn events with no prompt seen (app relaunched): still omitted.
        let midTurn = ingest([bashEvent, editDone("e1")])
        XCTAssertEqual(card(midTurn, indicator: .processing).body, .none)
        XCTAssertNil(card(midTurn, indicator: .processing).statusDetail)
    }

    func testNowLineWording() {
        func step(_ tool: String, _ input: String) -> String? {
            let event = #"{"hook_event_name":"PreToolUse","tool_name":"\#(tool)","tool_input":\#(input)}"#
            return ingest([promptEvent, event]).currentStep
        }
        XCTAssertEqual(step("Write", #"{"file_path":"src/server/config.ts"}"#), "editing config.ts")
        XCTAssertEqual(step("Read", #"{"file_path":"src/server/config.ts"}"#), "reading config.ts")
        XCTAssertEqual(step("Grep", #"{"pattern":"router"}"#), "searching")
        XCTAssertEqual(step("Task", "{}"), "running a subagent")
        XCTAssertEqual(step("WebFetch", #"{"url":"https://example.com"}"#), "webfetch")
    }

    func testPromptDecodingIsTolerant() {
        let odd = hookPayload(#"{"hook_event_name":"UserPromptSubmit","prompt":42,"tool_use_id":{"a":1}}"#)
        XCTAssertNil(odd.prompt)
        XCTAssertNil(odd.toolUseId)
        XCTAssertEqual(odd.hookEventName, "UserPromptSubmit")
    }

    func testApprovalCardIgnoresSummary() {
        guard let needs = derive(bashPermission) else { return }
        let summary = ingest([promptEvent, bashEvent])
        let withSummary = SessionPopoverContent.make(
            sessionId: sessionId, title: "DAB", cwd: nil, agent: "claude",
            indicator: .needsAttention, approval: needs, summary: summary, fallbackDate: nil, now: now
        )
        let without = SessionPopoverContent.make(
            sessionId: sessionId, title: "DAB", cwd: nil, agent: "claude",
            indicator: .needsAttention, approval: needs, summary: nil, fallbackDate: nil, now: now
        )
        XCTAssertEqual(withSummary, without)
    }

    func testStoreBuildsSummaryFromFilesWithoutChangingState() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSummaryTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClaudeStateStore(directoryURL: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        store.resumeWriterForTesting = { _, _ in }

        let base = Int(Date().timeIntervalSince1970)
        func write(_ hook: String, at offset: Int) {
            let json = #"{"ghosttiesSessionId":"\#(sessionId.uuidString)","updatedAt":\#(base + offset),"hook":\#(hook)}"#
            try? json.write(to: dir.appendingPathComponent("\(sessionId.uuidString).json"), atomically: true, encoding: .utf8)
            store.refreshForTesting()
        }
        write(promptEvent, at: 0)
        write(bashEvent, at: 1)
        write(editDone("e1"), at: 2)
        store.refreshForTesting() // unchanged file re-read
        XCTAssertEqual(store.summary(for: sessionId)?.prompt, "fix the flaky router tests")
        XCTAssertEqual(store.summary(for: sessionId)?.editCount, 1)
        XCTAssertEqual(store.state(for: sessionId)?.state, .busy)

        write(stopEvent, at: 3)
        XCTAssertEqual(store.summary(for: sessionId)?.isDone, true)
        XCTAssertEqual(store.state(for: sessionId)?.state, .idle)

        store.removeState(for: sessionId)
        XCTAssertNil(store.summary(for: sessionId))
    }

    // MARK: - Summary lifetime (the `seen` filter in refresh())

    private func makeStore() -> (store: ClaudeStateStore, dir: URL, write: (String) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionPopoverTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClaudeStateStore(directoryURL: dir)
        store.resumeWriterForTesting = { _, _ in }
        let id = sessionId
        let write: (String) -> Void = { hook in
            // Fresh timestamps: approval and summary staleness use the real clock.
            let json = #"{"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(Int(Date().timeIntervalSince1970)),"hook":\#(hook)}"#
            try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
            store.refreshForTesting()
        }
        return (store, dir, write)
    }

    func testSummaryIsDroppedOnSessionEnd() {
        let (store, dir, write) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        write(promptEvent)
        XCTAssertNotNil(store.summary(for: sessionId), "precondition: summary exists")
        write(#"{"hook_event_name":"SessionEnd","session_id":"c-1"}"#)
        XCTAssertNil(store.summary(for: sessionId))
    }

    func testSummaryIsDroppedWhenItsStateFileDisappears() {
        let (store, dir, write) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        write(promptEvent)
        XCTAssertNotNil(store.summary(for: sessionId), "precondition: summary exists")
        // The file goes away out-of-band (not via removeState).
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(sessionId.uuidString).json"))
        store.refreshForTesting()
        XCTAssertNil(store.summary(for: sessionId))
    }

    // MARK: - Decode strictness of pre-existing fields

    func testWronglyTypedPreExistingFieldStillFailsTheDecode() {
        // Same outcome as before the popover fields existed: the payload
        // fails to decode (and the state file is skipped).
        for field in [#""notification_type":5"#, #""tool_name":{"a":1}"#, #""session_id":7"#, #""cwd":false"#, #""transcript_path":[1]"#] {
            let json = #"{"hook_event_name":"Notification",\#(field)}"#
            XCTAssertThrowsError(try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(json.utf8)), field)
        }
    }

    func testWronglyTypedNotificationTypeSkipsTheStateFile() {
        let (store, dir, write) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // PreToolUse derives .busy on its own, so a state here would mean the
        // bad field was tolerated rather than the file skipped.
        write(#"{"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","notification_type":5,"session_id":"c-1"}"#)
        XCTAssertNil(store.state(for: sessionId))
        XCTAssertNil(store.summary(for: sessionId))
    }

    // MARK: - Controller refresh path (no GUI)

    private func makeController() -> (SessionPopoverController, WorkspaceStore, ClaudeStateStore, URL, (String) -> Void) {
        let project = Project(name: "dab", rootPath: "/Users/example/work/dab")
        let session = AgentSession(id: sessionId, name: "DAB", templateId: UUID(), projectId: project.id)
        let workspace = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let (claude, dir, write) = makeStore()
        let controller = SessionPopoverController(coordinator: nil, workspace: workspace, claudeState: claude)
        return (controller, workspace, claude, dir, write)
    }

    func testRefreshDropsApprovalTextWhenStateLeavesPermission() {
        let (controller, _, _, dir, write) = makeController()
        defer { try? FileManager.default.removeItem(at: dir) }

        write(bashPermission)
        controller.openForTesting(sessionId: sessionId)
        XCTAssertEqual(controller.contentForTesting?.isApproval, true)
        XCTAssertEqual(controller.contentForTesting?.statusDetail, "Bash")

        write(#"{"cwd":"/tmp","hook_event_name":"PostToolUse","session_id":"c-1","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}"#)
        controller.refreshForTesting()

        let card = controller.contentForTesting
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.isApproval, false)
        XCTAssertEqual(card?.body, SessionPopoverContent.Body.none)
        XCTAssertNil(card?.statusDetail)
        XCTAssertFalse(String(describing: card).contains("rm -rf"))
    }

    func testRefreshDismissesWhenTheSessionIsRemoved() {
        let (controller, workspace, _, dir, write) = makeController()
        defer { try? FileManager.default.removeItem(at: dir) }
        write(bashPermission)
        controller.openForTesting(sessionId: sessionId)
        XCTAssertNotNil(controller.contentForTesting)

        workspace.removeSession(id: sessionId)
        controller.refreshForTesting()

        XCTAssertNil(controller.contentForTesting)
        XCTAssertNil(controller.currentSessionIdForTesting)
    }

    // MARK: - Esc scoping

    func testEscapeIsConsumedOnlyWhileVisibleAndHovered() {
        let esc: UInt16 = 53
        typealias C = SessionPopoverController
        XCTAssertTrue(C.shouldConsumeEscape(keyCode: esc, isVisible: true, cardHovered: true))
        XCTAssertFalse(C.shouldConsumeEscape(keyCode: esc, isVisible: true, cardHovered: false))
        XCTAssertFalse(C.shouldConsumeEscape(keyCode: esc, isVisible: false, cardHovered: true))
        XCTAssertFalse(C.shouldConsumeEscape(keyCode: esc, isVisible: false, cardHovered: false))
        XCTAssertFalse(C.shouldConsumeEscape(keyCode: 36, isVisible: true, cardHovered: true), "only Esc")
    }

    // MARK: - Hover survives a rebuilt anchor

    func testRebuiltAnchorForTheSameSessionAdoptsTheHover() {
        let (controller, _, _, dir, _) = makeController()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = NSView(), new = NSView(), stray = NSView()
        controller.register(anchor: old, for: sessionId)
        controller.rowHoverChanged(sessionId: sessionId, anchor: old, hovering: true)
        XCTAssertTrue(controller.isRowHoveredForTesting)

        // An unrelated anchor going away does not end the hover.
        controller.unregister(anchor: stray, for: sessionId)
        XCTAssertTrue(controller.isRowHoveredForTesting)

        // The hovered row is rebuilt: teardown, then a new anchor, same id.
        controller.unregister(anchor: old, for: sessionId)
        controller.register(anchor: new, for: sessionId)
        XCTAssertTrue(controller.isRowHoveredForTesting)
    }

    // MARK: - Teardown

    func testWindowCloseTearsDownLiveUpdates() {
        let (controller, _, _, dir, write) = makeController()
        defer { try? FileManager.default.removeItem(at: dir) }
        write(bashPermission)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        controller.openForTesting(sessionId: sessionId)
        controller.startLiveUpdatesForTesting(window: window)
        XCTAssertTrue(controller.liveUpdatesActiveForTesting)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        let released = expectation(description: "live updates released")
        DispatchQueue.main.async { released.fulfill() }
        wait(for: [released], timeout: 2)

        XCTAssertFalse(controller.liveUpdatesActiveForTesting)
        XCTAssertNil(controller.currentSessionIdForTesting)
    }

    func testControllerDeallocationReleasesLiveUpdates() {
        weak var weakController: SessionPopoverController?
        autoreleasepool {
            let (controller, _, _, dir, _) = makeController()
            defer { try? FileManager.default.removeItem(at: dir) }
            controller.startLiveUpdatesForTesting(window: nil)
            XCTAssertTrue(controller.liveUpdatesActiveForTesting)
            weakController = controller
        }
        // A retain cycle through the timer/monitor closures would keep it alive.
        XCTAssertNil(weakController)
    }
}
