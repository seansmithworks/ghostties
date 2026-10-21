// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// A browser tab closed from outside the app (an agent's `Target.closeTarget`,
/// `Page.close`, or the page's own `window.close()`) closes just that tab, or
/// the whole browser session when it was the last tab. The app did not start
/// the close, so it never asks for confirmation and never touches terminals
/// or the window.
///
/// No live window or CEF; see `BrowserCloseConfirmTests` for the seams.
@MainActor
final class CloseBrowserTabTests: XCTestCase {
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

    private func browser() -> UUID {
        let id = UUID()
        coordinator.seedBrowserSessionForTesting(id: id)
        seeded.append(id)
        return id
    }

    private func terminal() -> UUID {
        let id = UUID()
        coordinator.seedEmptySessionTreeForTesting(id: id)
        coordinator.seedRunningSessionForTesting(id: id)
        seeded.append(id)
        return id
    }

    func testClosingOneOfTwoTabsKeepsTheSession() throws {
        let b = browser()
        let manager = try XCTUnwrap(coordinator.browserManagers[b])
        let second = manager.createTab(url: "about:blank")
        let first = try XCTUnwrap(manager.tabs.first { $0.id != second.id })

        coordinator.closeBrowserTab(sessionId: b, tabId: first.id)

        XCTAssertTrue(coordinator.isSessionBrowser(b), "the session stays while a tab remains")
        XCTAssertEqual(manager.tabs.map(\.id), [second.id], "only the closed tab goes")
        XCTAssertEqual(manager.activeTabId, second.id)
    }

    func testClosingTheLastTabClosesTheSessionWithoutAsking() throws {
        let b = browser()
        let t = terminal()
        let manager = try XCTUnwrap(coordinator.browserManagers[b])
        let only = try XCTUnwrap(manager.tabs.first)
        coordinator.setActiveSessionIdForTesting(t)

        var asked = 0
        coordinator.confirmCloseOverrideForTesting = { _, _, _ in asked += 1 }
        var windowCloses = 0
        coordinator.closeWindowOverrideForTesting = { windowCloses += 1 }

        coordinator.closeBrowserTab(sessionId: b, tabId: only.id)

        XCTAssertFalse(coordinator.isSessionBrowser(b), "the last tab takes the session with it")
        XCTAssertEqual(coordinator.statuses[b], .killed)
        XCTAssertEqual(asked, 0, "an outside close never shows the confirmation")
        XCTAssertEqual(windowCloses, 0, "closing a browser never closes the window")
        XCTAssertNotNil(coordinator.sessionTrees[t], "terminal sessions stay")
        XCTAssertEqual(coordinator.activeSessionId, t, "selection is untouched")
    }

    func testClosingAnUnknownSessionIsANoOp() {
        let t = terminal()
        coordinator.closeBrowserTab(sessionId: UUID(), tabId: UUID())
        XCTAssertNotNil(coordinator.sessionTrees[t])
    }
}
