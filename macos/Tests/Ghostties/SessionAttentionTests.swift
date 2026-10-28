import XCTest
@testable import Ghostty

/// The attention model behind "N need you": idle is NOT attention; a
/// permission prompt is bounded; AskUserQuestion / elicitation is freeform.
/// Hook names verified against https://code.claude.com/docs/en/hooks
/// (Notification matcher table; AskUserQuestion `questions[].question`).
/// Fixtures decode through the real `ClaudeHookWrapper`; no state dir is
/// touched (nothing here reads `~/.ghostties/state`).
@MainActor
final class SessionAttentionTests: XCTestCase {
    private let sid = UUID(uuidString: "9B2A6E10-1234-4A11-8B00-000000000001")!

    private func derive(_ hook: String, updatedAt: Int = 1_700_000_000) -> ClaudeState? {
        let json = #"""
        {"ghosttiesSessionId":"\#(sid.uuidString)","updatedAt":\#(updatedAt),"hook":\#(hook)}
        """#
        guard let w = try? JSONDecoder().decode(ClaudeHookWrapper.self, from: Data(json.utf8)) else {
            XCTFail("fixture failed to decode: \(json)")
            return nil
        }
        return ClaudeStateStore.derive(from: w)
    }

    /// The real mapping the sidebar uses (`SessionCoordinator.claudeIndicator`).
    private func indicator(for state: ClaudeState?) -> SessionIndicatorState {
        state.flatMap { SessionCoordinator.claudeIndicator(kind: $0.state, isLongRunning: false) } ?? .idle
    }

    // MARK: - derive: the structural fix

    func testIdlePromptIsIdleNotNeedsInput() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"Notification","message":"idle","notification_type":"idle_prompt","session_id":"c1"}
        """#)
        XCTAssertEqual(state?.state, .idle)
        XCTAssertNil(SessionAttention.make(indicator: indicator(for: state), state: state))
    }

    func testPermissionRequestIsBoundedWithCommand() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c2","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}}
        """#)
        XCTAssertEqual(
            SessionAttention.make(indicator: indicator(for: state), state: state),
            .bounded(prompt: "Run this command?", command: "npm test")
        )
    }

    func testPermissionNotificationWithoutToolIsBoundedNoCommand() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"c3"}
        """#)
        XCTAssertEqual(
            SessionAttention.make(indicator: indicator(for: state), state: state),
            .bounded(prompt: "Needs permission", command: nil)
        )
    }

    func testAskUserQuestionPreToolUseIsFreeformWithQuestionText() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c4","tool_name":"AskUserQuestion","tool_use_id":"tu-9","tool_input":{"questions":[{"question":"Which framework?","header":"Framework","options":[{"label":"React"},{"label":"Vue"}],"multiSelect":false}]}}
        """#)
        XCTAssertEqual(state?.state, .needsInput)
        XCTAssertEqual(
            SessionAttention.make(indicator: indicator(for: state), state: state),
            .freeform(question: "Which framework?")
        )
    }

    func testOtherPreToolUseStaysBusy() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PreToolUse","session_id":"c5","tool_name":"Bash","tool_use_id":"tu-1","tool_input":{"command":"ls"}}
        """#)
        XCTAssertEqual(state?.state, .busy)
        XCTAssertNil(SessionAttention.make(indicator: indicator(for: state), state: state))
    }

    func testElicitationAndAgentNeedsInputAreFreeformWithoutText() {
        for type in ["elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"] {
            let state = derive(#"""
            {"cwd":"/tmp","hook_event_name":"Notification","notification_type":"\#(type)","session_id":"c6"}
            """#)
            XCTAssertEqual(
                SessionAttention.make(indicator: indicator(for: state), state: state),
                .freeform(question: nil), type
            )
        }
    }

    // Hooks docs: Stop does not fire on user interrupt; PostToolUseFailure /
    // PermissionDenied / elicitation_complete|response are the events that DO
    // arrive after a blocked prompt resolves, so each must clear attention.
    func testResolutionEventsClearAttention() {
        let events = [
            #"{"cwd":"/tmp","hook_event_name":"PostToolUseFailure","session_id":"d1","tool_name":"AskUserQuestion","tool_use_id":"t","error":"x","is_interrupt":false}"#,
            #"{"cwd":"/tmp","hook_event_name":"PostToolUseFailure","session_id":"d1","tool_name":"Bash","tool_use_id":"t","error":"x"}"#,
            #"{"cwd":"/tmp","hook_event_name":"PermissionDenied","session_id":"d1","tool_name":"Bash","tool_use_id":"t","reason":"x"}"#,
            #"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"elicitation_complete","session_id":"d1"}"#,
            #"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"elicitation_response","session_id":"d1"}"#,
        ]
        for hook in events {
            let state = derive(hook)
            XCTAssertEqual(state?.state, .busy, hook)
            XCTAssertNil(SessionAttention.make(indicator: indicator(for: state), state: state), hook)
        }
    }

    /// Stop is skipped on user interrupt, so an interrupted failure must land
    /// on idle or the row spins "working" until the stale timeout.
    func testInterruptedFailureGoesIdle() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PostToolUseFailure","session_id":"d3","tool_name":"Bash","tool_use_id":"t","error":"x","is_interrupt":true}
        """#)
        XCTAssertEqual(state?.state, .idle)
    }

    func testIdlePromptKeepsPendingAttention() {
        func wrapper(_ hook: String) -> ClaudeHookWrapper {
            try! JSONDecoder().decode(ClaudeHookWrapper.self, from: Data(#"""
            {"ghosttiesSessionId":"\#(sid.uuidString)","updatedAt":1700000100,"hook":\#(hook)}
            """#.utf8))
        }
        let idleW = wrapper(#"{"cwd":"/tmp","hook_event_name":"Notification","notification_type":"idle_prompt","session_id":"e"}"#)
        let derived = ClaudeStateStore.derive(from: idleW)!
        for kind in [ClaudeState.Kind.needsPermission, .needsInput] {
            let prev = ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: kind,
                                   structuredPrompt: nil, updatedAt: at)
            XCTAssertEqual(ClaudeStateStore.resolve(derived, previous: prev, wrapper: idleW), prev)
        }
        let busy = ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .busy,
                               structuredPrompt: nil, updatedAt: at)
        XCTAssertEqual(ClaudeStateStore.resolve(derived, previous: busy, wrapper: idleW), derived)
        // A real Stop still clears a pending prompt.
        let stopW = wrapper(#"{"cwd":"/tmp","hook_event_name":"Stop","session_id":"e"}"#)
        let stop = ClaudeStateStore.derive(from: stopW)!
        let pending = ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .needsPermission,
                                  structuredPrompt: nil, updatedAt: at)
        XCTAssertEqual(ClaudeStateStore.resolve(stop, previous: pending, wrapper: stopW), stop)
    }

    func testPermissionRequestForAskUserQuestionIsNeverBounded() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"d2","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which one?"}]}}
        """#)
        XCTAssertEqual(
            SessionAttention.make(indicator: indicator(for: state), state: state),
            .freeform(question: "Which one?")
        )
    }

    func testMakeRequiresAttentionIndicator() {
        let state = derive(#"""
        {"cwd":"/tmp","hook_event_name":"PermissionRequest","session_id":"c7","tool_name":"Bash","tool_input":{"command":"ls"}}
        """#)
        XCTAssertNil(SessionAttention.make(indicator: .idle, state: state))
        XCTAssertNil(SessionAttention.make(indicator: .needsAttention, state: nil))
    }

    // MARK: - project count

    func testCountIgnoresIdle() {
        let ids = (0..<4).map { _ in UUID() }
        func mk(_ id: UUID, _ kind: ClaudeState.Kind) -> ClaudeState {
            ClaudeState(ghosttiesSessionId: id, claudeSessionId: "c", cwd: "/tmp", state: kind,
                        structuredPrompt: nil, updatedAt: Date())
        }
        let states: [UUID: ClaudeState] = [
            ids[0]: mk(ids[0], .idle), ids[1]: mk(ids[1], .needsPermission),
            ids[2]: mk(ids[2], .needsInput), ids[3]: mk(ids[3], .busy),
        ]
        let count = SessionAttention.count(
            sessions: ids,
            indicator: { self.indicator(for: states[$0]) },
            state: { states[$0] }
        )
        XCTAssertEqual(count, 2)
    }

    // MARK: - responder stale guard

    private let at = Date(timeIntervalSince1970: 1_700_000_000)

    private let fp = ApprovalFingerprint.make(toolName: "Bash", input: ToolInputSummary(command: "npm test"))

    private func claudeState(_ kind: ClaudeState.Kind, updatedAt: Date, command: String = "npm test") -> ClaudeState {
        ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: kind,
                    structuredPrompt: StructuredPrompt(toolName: "Bash", toolUseId: nil,
                                                       toolInput: ToolInputSummary(command: command)),
                    updatedAt: updatedAt)
    }

    /// updatedAt is whole seconds: a different command in the same second is a different prompt.
    func testResponderDifferentPromptSameSecondSendsNothing() {
        let surface = UUID()
        var sent = 0
        let responder = GuardedApprovalResponder(
            isEnabled: { true },
            currentState: { _ in self.claudeState(.needsPermission, updatedAt: self.at, command: "rm -rf build") },
            ownSurface: { _ in surface }, send: { _, _ in sent += 1 }
        )
        let target = ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: surface, fingerprint: fp)
        XCTAssertEqual(responder.respond(.approve, to: target), .stale)
        XCTAssertEqual(sent, 0)
    }

    func testResponderSendsWhenFreshAndOwnSurface() {
        let surface = UUID()
        var sent: [(ApprovalDecision, UUID)] = []
        let responder = GuardedApprovalResponder(
            isEnabled: { true },
            currentState: { _ in self.claudeState(.needsPermission, updatedAt: self.at) },
            ownSurface: { _ in surface },
            send: { sent.append(($0, $1)) }
        )
        let outcome = responder.respond(.approve, to: ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: surface, fingerprint: fp))
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(sent.count, 1)
    }

    func testResponderStaleStateSendsNothing() {
        let surface = UUID()
        var sent = 0
        func responder(_ state: ClaudeState?) -> GuardedApprovalResponder {
            GuardedApprovalResponder(isEnabled: { true }, currentState: { _ in state },
                                     ownSurface: { _ in surface }, send: { _, _ in sent += 1 })
        }
        let target = ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: surface, fingerprint: fp)
        // Moved on (busy), gone (nil), or a newer prompt (different updatedAt).
        XCTAssertEqual(responder(claudeState(.busy, updatedAt: at)).respond(.approve, to: target), .stale)
        XCTAssertEqual(responder(nil).respond(.deny, to: target), .stale)
        XCTAssertEqual(responder(claudeState(.needsPermission, updatedAt: at + 5)).respond(.approve, to: target), .stale)
        XCTAssertEqual(sent, 0)
    }

    func testResponderRefusesAskUserQuestionEvenWithMatchingFingerprint() {
        let surface = UUID()
        var sent = 0
        let ask = ClaudeState(
            ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .needsPermission,
            structuredPrompt: StructuredPrompt(toolName: "AskUserQuestion", toolUseId: nil,
                                               toolInput: ToolInputSummary(questions: ["Which?"])),
            updatedAt: at)
        let responder = GuardedApprovalResponder(isEnabled: { true }, currentState: { _ in ask },
                                                 ownSurface: { _ in surface }, send: { _, _ in sent += 1 })
        let target = ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: surface,
                                    fingerprint: ApprovalFingerprint.make(ask))
        XCTAssertEqual(responder.respond(.approve, to: target), .stale)
        XCTAssertEqual(sent, 0)
    }

    func testFingerprintDistinguishesFullInputAndNotificationMessage() throws {
        func fp(_ json: String) throws -> String {
            let w = try JSONDecoder().decode(ClaudeHookWrapper.self, from: Data(#"""
            {"ghosttiesSessionId":"\#(sid.uuidString)","updatedAt":1,"hook":\#(json)}
            """#.utf8))
            return ApprovalFingerprint.make(try XCTUnwrap(ClaudeStateStore.derive(from: w)))
        }
        let a = try fp(#"{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/a.swift","old_string":"x","new_string":"1"}}"#)
        let b = try fp(#"{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/a.swift","old_string":"x","new_string":"2"}}"#)
        let a2 = try fp(#"{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"new_string":"1","old_string":"x","file_path":"/a.swift"}}"#)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, a2, "key order must not change the digest")
        let n1 = try fp(#"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission to use Bash"}"#)
        let n2 = try fp(#"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission to use Write"}"#)
        XCTAssertNotEqual(n1, n2)
    }

    func testPopoverDoesNotRenderApprovalForAskUserQuestion() {
        let ask = ClaudeState(
            ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .needsPermission,
            structuredPrompt: StructuredPrompt(toolName: "AskUserQuestion", toolUseId: nil,
                                               toolInput: ToolInputSummary(questions: ["Which?"])),
            updatedAt: Date())
        // C2: the card now shows the question (freeform), never an approval.
        let card = SessionPopoverContent.make(sessionId: sid, indicator: .needsAttention, approval: ask)
        XCTAssertEqual(card?.block, .freeform)
        XCTAssertEqual(card?.isApproval, false)
    }

    func testResponderWrongSurfaceSendsNothing() {
        var sent = 0
        let responder = GuardedApprovalResponder(
            isEnabled: { true },
            currentState: { _ in self.claudeState(.needsPermission, updatedAt: self.at) },
            ownSurface: { _ in UUID() },
            send: { _, _ in sent += 1 }
        )
        let outcome = responder.respond(.approve, to: ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: UUID(), fingerprint: fp))
        XCTAssertEqual(outcome, .wrongSurface)
        XCTAssertEqual(sent, 0)
    }

    func testResponderDisabledAndNoOpSendNothing() {
        let surface = UUID()
        var sent = 0
        let off = GuardedApprovalResponder(
            isEnabled: { false },
            currentState: { _ in self.claudeState(.needsPermission, updatedAt: self.at) },
            ownSurface: { _ in surface }, send: { _, _ in sent += 1 }
        )
        let target = ApprovalTarget(sessionId: sid, updatedAt: at, surfaceId: surface, fingerprint: fp)
        XCTAssertEqual(off.respond(.approve, to: target), .disabled)
        XCTAssertEqual(NoOpApprovalResponder().respond(.deny, to: target), .disabled)
        XCTAssertEqual(sent, 0)
    }

    func testApprovalFlagIsOnByDefaultAndOffWhenSetFalse() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: ApprovalFlag.defaultsKey)
        defer {
            if let saved { defaults.set(saved, forKey: ApprovalFlag.defaultsKey) }
            else { defaults.removeObject(forKey: ApprovalFlag.defaultsKey) }
        }
        defaults.removeObject(forKey: ApprovalFlag.defaultsKey)
        XCTAssertTrue(ApprovalFlag.isEnabled, "inline approvals must be ON when the key is absent")
        defaults.set(false, forKey: ApprovalFlag.defaultsKey)
        XCTAssertFalse(ApprovalFlag.isEnabled)
    }
}
