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

    // MARK: Coordinator wiring (real surfaces; the stale-tree case)

    private static var apps: [Ghostty.App] = []

    private func makeViews(_ count: Int) throws -> [Ghostty.SurfaceView] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ApprovalTargetingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let configURL = dir.appendingPathComponent("config.ghostty")
        try "confirm-close-surface = false\n".write(to: configURL, atomically: true, encoding: .utf8)
        let app = Ghostty.App(configPath: configURL.path)
        Self.apps.append(app)
        let cApp = try XCTUnwrap(app.app)
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        config.workingDirectory = NSTemporaryDirectory()
        return (0..<count).map { _ in Ghostty.SurfaceView(cApp, baseConfig: config) }
    }

    /// The active session was split live (Cmd+D): the controller's tree has two
    /// panes while `sessionTrees` still holds the one-pane snapshot.
    func testActiveSessionSplitLiveHasNoTargetAndRowHandsOff() throws {
        let views = try makeViews(2)
        let coordinator = SessionCoordinator()
        coordinator.seedSessionTreeForTesting(id: sid, tree: SplitTree(view: views[0]))
        coordinator.setActiveSessionIdForTesting(sid)
        coordinator.liveActiveTreeForTesting = try SplitTree(view: views[0])
            .inserting(view: views[1], at: views[0], direction: .right)

        XCTAssertNil(coordinator.approvalSurfaceId(forSession: sid), "stale one-pane snapshot must not win")
        XCTAssertTrue(coordinator.isSplit(session: sid))
        // canAnswerInline(session:) is exactly what RecentsListView.rowPrompt passes (a view-level test is not feasible).
        XCTAssertNil(SessionRowPrompt.make(indicator: .needsAttention, state: permissionState(),
                                           now: shownAt.addingTimeInterval(1),
                                           canAnswerInline: coordinator.canAnswerInline(session: sid))?.approvalPrompt)
    }

    /// A background session is read from its stored tree, whatever the active
    /// session's live tree looks like.
    func testBackgroundSinglePaneSessionTargetsItsPane() throws {
        let views = try makeViews(3)
        let other = UUID()
        let coordinator = SessionCoordinator()
        coordinator.seedSessionTreeForTesting(id: sid, tree: SplitTree(view: views[0]))
        coordinator.seedSessionTreeForTesting(id: other, tree: SplitTree(view: views[1]))
        coordinator.setActiveSessionIdForTesting(other)
        coordinator.liveActiveTreeForTesting = try SplitTree(view: views[1])
            .inserting(view: views[2], at: views[1], direction: .right)

        XCTAssertEqual(coordinator.approvalSurfaceId(forSession: sid), views[0].id)
        XCTAssertFalse(coordinator.isSplit(session: sid))
        XCTAssertNil(coordinator.approvalSurfaceId(forSession: other), "the active one is split")
    }

    func testActiveUnsplitSessionTargetsItsPane() throws {
        let views = try makeViews(1)
        let coordinator = SessionCoordinator()
        coordinator.seedSessionTreeForTesting(id: sid, tree: SplitTree(view: views[0]))
        coordinator.setActiveSessionIdForTesting(sid)
        coordinator.liveActiveTreeForTesting = SplitTree(view: views[0])
        XCTAssertEqual(coordinator.approvalSurfaceId(forSession: sid), views[0].id)
    }

    func testSessionWithNoTreeHasNoTarget() {
        let coordinator = SessionCoordinator()
        XCTAssertNil(coordinator.approvalSurfaceId(forSession: sid))
        XCTAssertFalse(coordinator.sendApproval(.approve, toSurface: UUID()), "and nothing is delivered")
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
