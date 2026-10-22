import XCTest
@testable import Ghostty

/// A sidebar row's Approve/Deny go through the same responder, and the same
/// stale guard, as the hover card's, and one prompt is answered once.
@MainActor
final class RowApprovalPathTests: XCTestCase {
    private let sid = UUID()
    private let surface = UUID()
    private let shownAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let fp = ApprovalFingerprint.make(toolName: "Bash", input: ToolInputSummary(command: "npm test"))

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: ApprovalFlag.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ApprovalFlag.defaultsKey)
        super.tearDown()
    }

    private func state(updatedAt: Date) -> ClaudeState {
        ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .needsPermission,
                    structuredPrompt: StructuredPrompt(toolName: "Bash", toolUseId: nil,
                                                       toolInput: ToolInputSummary(command: "npm test")),
                    updatedAt: updatedAt)
    }

    /// The popover controller the sidebar rows call, with a guarded
    /// responder whose live state `live` returns.
    private func controller(live: @escaping () -> ClaudeState?, sends: @escaping () -> Void) -> (SessionCoordinator, SessionPopoverController) {
        let coordinator = SessionCoordinator()
        let popover = coordinator.sessionPopover
        popover.approvalSurfaceIdForTesting = { [surface] _ in surface }
        popover.approvalResponder = GuardedApprovalResponder(
            isEnabled: { ApprovalFlag.isEnabled }, currentState: { _ in live() },
            ownSurface: { [surface] _ in surface }, send: { _, _ in sends() }
        )
        return (coordinator, popover)
    }

    /// The prompt the row showed has moved on (a newer updatedAt): the
    /// row's tap reaches the guard, which sends nothing.
    func testTheRowPathRunsTheStaleGuard() {
        var sent = 0
        let (coordinator, popover) = controller(live: { self.state(updatedAt: self.shownAt + 5) }, sends: { sent += 1 })
        let shown = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt, fingerprint: fp)
        XCTAssertEqual(popover.respond(.approve, sessionId: sid, prompt: shown), .stale)
        XCTAssertEqual(sent, 0)
        _ = coordinator
    }

    /// Only a sent answer disables Approve/Deny: a tap the guard turned
    /// away (stale) leaves the prompt answerable.
    func testOnlyASentAnswerMarksThePromptAnswered() {
        var live = state(updatedAt: shownAt + 5)
        let (coordinator, popover) = controller(live: { live }, sends: {})
        let shown = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt, fingerprint: fp)
        XCTAssertEqual(popover.respond(.approve, sessionId: sid, prompt: shown), .stale)
        XCTAssertFalse(popover.model.isAnswered(shown, for: sid), "a stale outcome leaves Approve/Deny enabled")

        live = state(updatedAt: shownAt)
        XCTAssertEqual(popover.respond(.approve, sessionId: sid, prompt: shown), .sent)
        XCTAssertTrue(popover.model.isAnswered(shown, for: sid), "a sent outcome disables them")
        _ = coordinator
    }

    /// A second tap on the same prompt never reaches the responder, from
    /// the row or the card; a new prompt is answerable again.
    func testOnePromptIsAnsweredOnce() {
        var live = state(updatedAt: shownAt)
        var sent = 0
        let (coordinator, popover) = controller(live: { live }, sends: { sent += 1 })
        let first = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt, fingerprint: fp)
        XCTAssertEqual(popover.respond(.approve, sessionId: sid, prompt: first), .sent)
        XCTAssertTrue(popover.model.isAnswered(first, for: sid), "the row and card disable Approve/Deny")
        XCTAssertNil(popover.respond(.approve, sessionId: sid, prompt: first), "a second tap sends nothing")
        XCTAssertNil(popover.respond(.deny, sessionId: sid, prompt: first))
        XCTAssertEqual(sent, 1)

        live = state(updatedAt: shownAt + 60)
        let next = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt + 60, fingerprint: fp)
        XCTAssertFalse(popover.model.isAnswered(next, for: sid), "a new prompt enables them again")
        XCTAssertEqual(popover.respond(.deny, sessionId: sid, prompt: next), .sent)
        XCTAssertEqual(sent, 2)
        _ = coordinator
    }
}
