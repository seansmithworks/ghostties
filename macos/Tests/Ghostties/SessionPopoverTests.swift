// IDE-ONLY: not currently exercised in CI macos job (build-only).
import XCTest
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
}
