// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// `gt browser open` from an agent's terminal: the browser appears under the
/// terminal's project, is paired with that terminal, stays beside it, and
/// never moves the user's selection.
///
/// Hosted: `createBrowserSession` needs CEF initialized, so these FAIL rather
/// than skip when it is not. No window is attached, so no Chromium browser is
/// created; the DevTools target lookup times out (asserted on separately in
/// `DevToolsTargetIdTests`). The store is an isolated in-memory instance and
/// never `.shared`'s workspace.json.
@MainActor
final class AgentBrowserPairingTests: XCTestCase {
    private var coordinator: SessionCoordinator!
    private var store: WorkspaceStore!
    private var project: Project!
    private var terminal: UUID!
    private var seeded: [UUID] = []

    override func setUp() {
        CEFBridgeManager.initializeIfNeeded()
        XCTAssertTrue(CEFBridgeManager.isInitialized, "CEF did not initialize (this must fail, not skip)")

        project = Project(name: "p", rootPath: "/tmp/p")
        terminal = UUID()
        let record = AgentSession(id: terminal, name: "Shell 1", templateId: AgentTemplate.shell.id, projectId: project.id)
        store = WorkspaceStore(testingProjects: [project], testingSessions: [record])
        coordinator = SessionCoordinator()
        coordinator.agentKindLookupStoreForTesting = store
        coordinator.seedEmptySessionTreeForTesting(id: terminal)
        coordinator.seedRunningSessionForTesting(id: terminal)
        coordinator.setActiveSessionIdForTesting(terminal)
        seeded = [terminal]
    }

    override func tearDown() {
        for id in seeded + store.sessions.map(\.id) {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
        }
        coordinator = nil
    }

    private func open(_ url: String = "about:blank") async -> BrowserAgentHTTP.Response {
        await coordinator.openAgentBrowser(sessionId: terminal, url: url, targetTimeout: 0.2)
    }

    private func browserSessions() -> [AgentSession] {
        store.sessions.filter { $0.templateId == AgentTemplate.browser.id }
    }

    func testOpeningABrowserNeverMovesTheUsersSelection() async {
        XCTAssertFalse(coordinator.isHistoryPresented)
        _ = await open()

        XCTAssertEqual(coordinator.activeSessionId, terminal, "the agent's browser took the selection")
        XCTAssertNil(coordinator.lastActiveSessionPerProject[project.id], "the agent's browser became the project's last session")
        XCTAssertFalse(coordinator.isHistoryPresented)
        XCTAssertEqual(browserSessions().count, 1)
    }

    func testTheBrowserIsNamedAndFiledUnderTheTerminalsProject() async throws {
        _ = await open()

        let browser = try XCTUnwrap(browserSessions().first)
        XCTAssertEqual(browser.name, "Browser 2", "existing sidebar naming: template name + count")
        XCTAssertEqual(browser.projectId, project.id)
        XCTAssertEqual(coordinator.pairedBrowserByTerminal[terminal], browser.id)
        XCTAssertTrue(coordinator.isSessionBrowser(browser.id))
    }

    func testAskingAgainReusesThePairedBrowser() async {
        _ = await open("about:blank")
        _ = await open("about:blank")

        XCTAssertEqual(browserSessions().count, 1, "a second open must navigate the same browser, not add one")
    }

    func testFocusingTheTerminalKeepsItsPairedBrowserBesideIt() async throws {
        _ = await open()
        let browser = try XCTUnwrap(browserSessions().first)

        coordinator.focusSession(id: terminal)

        XCTAssertEqual(coordinator.activeSessionId, terminal)
        XCTAssertEqual(coordinator.shownBrowserSessionId, browser.id, "focusing the terminal collapsed its browser")
    }

    func testFocusingAnUnpairedTerminalStillCollapsesThePanel() async {
        _ = await open()
        let other = UUID()
        coordinator.seedEmptySessionTreeForTesting(id: other)
        seeded.append(other)

        coordinator.focusSession(id: other)

        XCTAssertNil(coordinator.shownBrowserSessionId, "an unpaired terminal must not show someone else's browser")
    }

    func testClosingThePairedBrowserLeavesTheTerminalSelectedAndDropsThePairing() async throws {
        _ = await open()
        let browser = try XCTUnwrap(browserSessions().first)

        coordinator.closeSession(id: browser.id)

        XCTAssertEqual(coordinator.activeSessionId, terminal)
        XCTAssertNil(coordinator.shownBrowserSessionId)
        XCTAssertNil(coordinator.pairedBrowserByTerminal[terminal])
        XCTAssertNotNil(coordinator.sessionTrees[terminal], "the terminal stays")
    }

    func testOnlyWebURLsAreOpened() async {
        let response = await open("file:///etc/passwd")

        XCTAssertEqual(response.status, 400)
        XCTAssertTrue(browserSessions().isEmpty, "a refused URL must not leave a browser behind")
    }

    func testAnUnknownTerminalIsRefused() async {
        let response = await coordinator.openAgentBrowser(sessionId: UUID(), url: "about:blank", targetTimeout: 0.2)

        XCTAssertEqual(response.status, 404)
        XCTAssertTrue(browserSessions().isEmpty)
    }
}
