// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Cmd+W on a browser asks first and closes only the browser; and the focus
/// rule after a browser is stopped or closed.
///
/// No live window or CEF: the confirmation sheet and the window close are
/// replaced by the coordinator's DEBUG seams, and WorkspaceStore is an
/// isolated in-memory instance (never `.shared`'s workspace.json).
@MainActor
final class BrowserCloseConfirmTests: XCTestCase {
    private var coordinator: SessionCoordinator!
    private var seeded: [UUID] = []

    override func setUp() {
        coordinator = SessionCoordinator()
        seeded = []
    }

    override func tearDown() {
        for id in seeded {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
        }
        coordinator = nil
    }

    private func browser(_ id: UUID = UUID()) -> UUID {
        coordinator.seedBrowserSessionForTesting(id: id)
        seeded.append(id)
        return id
    }

    private func terminal(_ id: UUID = UUID()) -> UUID {
        coordinator.seedEmptySessionTreeForTesting(id: id)
        coordinator.seedRunningSessionForTesting(id: id)
        seeded.append(id)
        return id
    }

    // MARK: - Cmd+W on a browser

    func testCmdWOnBrowserAsksFirstThenClosesOnlyTheBrowser() {
        let b = browser()
        let t = terminal()
        coordinator.setActiveSessionIdForTesting(b)

        var windowCloses = 0
        coordinator.closeWindowOverrideForTesting = { windowCloses += 1 }
        var asked: [(String, String)] = []
        var proceed: (() -> Void)?
        coordinator.confirmCloseOverrideForTesting = { message, info, go in
            asked.append((message, info))
            proceed = go
        }

        coordinator.closeCurrentSessionWithConfirmation()

        XCTAssertEqual(asked.count, 1, "Cmd+W on a browser must show the confirmation")
        XCTAssertEqual(asked.first?.0, "Close browser?")
        XCTAssertEqual(
            asked.first?.1,
            "This tab will close. Your terminal sessions stay open."
        )
        XCTAssertTrue(coordinator.isSessionBrowser(b), "browser must stay until confirmed")
        XCTAssertEqual(windowCloses, 0)

        proceed?()

        XCTAssertFalse(coordinator.isSessionBrowser(b), "confirm closes the browser")
        XCTAssertNotNil(coordinator.sessionTrees[t], "terminal sessions stay")
        XCTAssertEqual(windowCloses, 0, "closing a browser never closes the window")
    }

    func testConfirmationTextCountsManyTabs() {
        let b = browser()
        coordinator.browserManagers[b]?.createTab(url: "about:blank")
        coordinator.browserManagers[b]?.createTab(url: "about:blank")
        var info: String?
        coordinator.confirmCloseOverrideForTesting = { _, text, _ in info = text }

        coordinator.stopSessionWithConfirmation(id: b)

        XCTAssertEqual(info, "Its 3 tabs will close. Your terminal sessions stay open.")
    }

    func testCmdWOnLastBrowserNeverClosesTheWindow() {
        let b = browser()
        coordinator.setActiveSessionIdForTesting(b)

        var windowCloses = 0
        coordinator.closeWindowOverrideForTesting = { windowCloses += 1 }
        coordinator.confirmCloseOverrideForTesting = { _, _, go in go() }

        coordinator.closeCurrentSessionWithConfirmation()

        XCTAssertFalse(coordinator.isSessionBrowser(b))
        XCTAssertEqual(windowCloses, 0, "an empty window stays open after its browser closes")
    }

    func testCancelKeepsTheBrowser() {
        let b = browser()
        let t = terminal()
        coordinator.setActiveSessionIdForTesting(b)

        var windowCloses = 0
        coordinator.closeWindowOverrideForTesting = { windowCloses += 1 }
        var asked = 0
        coordinator.confirmCloseOverrideForTesting = { _, _, _ in asked += 1 } // dropped = Cancel

        coordinator.closeCurrentSessionWithConfirmation()

        XCTAssertEqual(asked, 1)
        XCTAssertTrue(coordinator.isSessionBrowser(b))
        XCTAssertNotNil(coordinator.sessionTrees[t])
        XCTAssertEqual(coordinator.activeSessionId, b)
        XCTAssertEqual(windowCloses, 0)
    }

    // MARK: - Focus after closing the active browser

    private struct World {
        let store: WorkspaceStore
        let p: Project
        let q: Project
    }

    private func world(_ sessions: [AgentSession], _ p: Project, _ q: Project) -> World {
        let store = WorkspaceStore(testingProjects: [p, q], testingSessions: sessions)
        coordinator.agentKindLookupStoreForTesting = store
        return World(store: store, p: p, q: q)
    }

    private func session(_ project: Project, id: UUID = UUID(), minutesAgo: Double) -> AgentSession {
        AgentSession(
            id: id,
            name: "s",
            templateId: UUID(),
            projectId: project.id,
            lastActiveAt: Date().addingTimeInterval(-minutesAgo * 60)
        )
    }

    func testFocusPrefersRunningTerminalInSameProject() {
        let p = Project(name: "p", rootPath: "/tmp/p")
        let q = Project(name: "q", rootPath: "/tmp/q")
        let bId = UUID()
        let sameProject = UUID()
        var all = [session(p, id: bId, minutesAgo: 1), session(p, id: sameProject, minutesAgo: 500)]
        // Many more-recent sessions elsewhere, so dictionary order can't pass by luck.
        var others: [UUID] = []
        for i in 0..<8 {
            let id = UUID()
            others.append(id)
            all.append(session(q, id: id, minutesAgo: Double(i)))
        }
        _ = world(all, p, q)

        _ = browser(bId)
        _ = terminal(sameProject)
        others.forEach { _ = terminal($0) }
        coordinator.setActiveSessionIdForTesting(bId)

        coordinator.stopSessionWithConfirmation(id: bId)
        // No override and no controller: stop closes directly.

        XCTAssertEqual(coordinator.activeSessionId, sameProject)
    }

    func testFocusFallsBackToMostRecentlyActiveSessionAnywhere() {
        let p = Project(name: "p", rootPath: "/tmp/p")
        let q = Project(name: "q", rootPath: "/tmp/q")
        let bId = UUID()
        let newest = UUID()
        var all = [session(p, id: bId, minutesAgo: 1), session(q, id: newest, minutesAgo: 2)]
        var others: [UUID] = []
        for i in 0..<8 {
            let id = UUID()
            others.append(id)
            all.append(session(q, id: id, minutesAgo: Double(10 + i)))
        }
        _ = world(all, p, q)

        _ = browser(bId)
        _ = terminal(newest)
        others.forEach { _ = terminal($0) }
        coordinator.setActiveSessionIdForTesting(bId)

        coordinator.stopSessionWithConfirmation(id: bId)

        XCTAssertEqual(coordinator.activeSessionId, newest)
    }

    func testFocusIsNilWhenNothingElseIsRunning() {
        let p = Project(name: "p", rootPath: "/tmp/p")
        let q = Project(name: "q", rootPath: "/tmp/q")
        let bId = UUID()
        _ = world([session(p, id: bId, minutesAgo: 1)], p, q)

        _ = browser(bId)
        coordinator.setActiveSessionIdForTesting(bId)

        coordinator.stopSessionWithConfirmation(id: bId)

        XCTAssertNil(coordinator.activeSessionId)
    }

    func testClosingABackgroundBrowserLeavesFocusAlone() {
        let p = Project(name: "p", rootPath: "/tmp/p")
        let q = Project(name: "q", rootPath: "/tmp/q")
        let bId = UUID()
        let t = UUID()
        _ = world([session(p, id: bId, minutesAgo: 1), session(p, id: t, minutesAgo: 2)], p, q)

        _ = browser(bId)
        _ = terminal(t)
        coordinator.setActiveSessionIdForTesting(t)

        coordinator.stopSessionWithConfirmation(id: bId)

        XCTAssertEqual(coordinator.activeSessionId, t)
    }
}
