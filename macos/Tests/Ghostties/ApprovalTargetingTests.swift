import XCTest
@testable import Ghostty

/// Which surface an answer may reach, and that "sent" means a key was delivered.
@MainActor
final class ApprovalTargetingTests: XCTestCase {
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

    private func permissionState() -> ClaudeState {
        ClaudeState(ghosttiesSessionId: sid, claudeSessionId: "c", cwd: "/tmp", state: .needsPermission,
                    structuredPrompt: StructuredPrompt(toolName: "Bash", toolUseId: nil,
                                                       toolInput: ToolInputSummary(command: "npm test")),
                    updatedAt: shownAt)
    }

    // MARK: Targeting

    func testSinglePaneSessionTargetsThatPane() {
        let pane = UUID()
        XCTAssertEqual(ApprovalSurfaceResolver.surface(among: [pane]), pane)
    }

    /// Two panes, Claude in pane 2: nothing maps state to a pane, so no target.
    func testSplitSessionHasNoTarget() {
        XCTAssertNil(ApprovalSurfaceResolver.surface(among: [UUID(), UUID()]))
        XCTAssertNil(ApprovalSurfaceResolver.surface(among: []))
    }

    func testSplitSessionRowFallsBackToAnswerInTerminal() {
        let state = permissionState()
        let now = shownAt.addingTimeInterval(1)
        let single = SessionRowPrompt.make(indicator: .needsAttention, state: state, now: now)
        let split = SessionRowPrompt.make(indicator: .needsAttention, state: state, now: now, canAnswerInline: false)
        XCTAssertNotNil(single?.approvalPrompt)
        XCTAssertNotNil(split, "still a needs-you row")
        XCTAssertNil(split?.approvalPrompt, "but no Approve/Deny")
    }

    /// No target surface: the controller never reaches the responder.
    func testControllerSendsNothingWithoutATarget() {
        var sent = 0
        let popover = SessionCoordinator().sessionPopover
        popover.approvalSurfaceIdForTesting = { _ in nil }
        popover.approvalResponder = GuardedApprovalResponder(
            isEnabled: { true }, currentState: { _ in self.permissionState() },
            ownSurface: { _ in self.surface }, send: { _, _ in sent += 1 }
        )
        let shown = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt, fingerprint: fp)
        XCTAssertNil(popover.respond(.approve, sessionId: sid, prompt: shown))
        XCTAssertEqual(sent, 0)
    }

    // MARK: Delivery

    func testDeliveryToAMissingSurfaceReportsFailure() {
        let none: Ghostty.Surface? = nil
        XCTAssertFalse(ApprovalKeys.deliver(.approve, to: none))
    }

    func testResponderReportsUndeliveredWhenNoKeyLands() {
        let responder = GuardedApprovalResponder(
            isEnabled: { true }, currentState: { _ in self.permissionState() },
            ownSurface: { _ in self.surface }, send: { (_: ApprovalDecision, _: UUID) -> Bool in false }
        )
        let target = ApprovalTarget(sessionId: sid, updatedAt: shownAt, surfaceId: surface, fingerprint: fp)
        XCTAssertEqual(responder.respond(.approve, to: target), .undelivered)
    }

    /// A failed delivery must not disable Approve/Deny: the user can still tap.
    func testUndeliveredAnswerIsNotMarkedAnswered() {
        let popover = SessionCoordinator().sessionPopover
        popover.approvalSurfaceIdForTesting = { [surface] _ in surface }
        popover.approvalResponder = GuardedApprovalResponder(
            isEnabled: { true }, currentState: { _ in self.permissionState() },
            ownSurface: { [surface] _ in surface }, send: { (_: ApprovalDecision, _: UUID) -> Bool in false }
        )
        let shown = SessionPopoverContent.ApprovalPrompt(updatedAt: shownAt, fingerprint: fp)
        XCTAssertEqual(popover.respond(.approve, sessionId: sid, prompt: shown), .undelivered)
        XCTAssertFalse(popover.model.isAnswered(shown, for: sid))
    }
}
