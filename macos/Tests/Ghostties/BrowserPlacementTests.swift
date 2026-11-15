import XCTest
import GhosttiesCore
@testable import Ghostty

/// Where a browser goes is one decision, `BrowserPlacement.presentation(for:)`:
/// the composer's browser fills the canvas, Cmd+B and `gt browser open` split
/// beside the terminal, and a sidebar row shows what its session was made as.
/// Every store is the injected persistence-disabled kind, never
/// `WorkspaceStore.shared`, and no test needs CEF.
@MainActor
final class BrowserPlacementTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")

    private func terminal(_ name: String) -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: atlas.id)
    }

    private func browser(_ name: String, made presentation: BrowserPresentation?) -> AgentSession {
        AgentSession(
            name: name, templateId: AgentTemplate.browser.id, projectId: atlas.id,
            browserPresentation: presentation
        )
    }

    private func makeCoordinator(_ sessions: [AgentSession]) -> (SessionCoordinator, WorkspaceStore) {
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: sessions)
        let coordinator = SessionCoordinator()
        coordinator.agentKindLookupStoreForTesting = store
        for session in sessions {
            if session.templateId == AgentTemplate.browser.id {
                coordinator.seedBrowserSessionForTesting(id: session.id)
            } else {
                coordinator.seedEmptySessionTreeForTesting(id: session.id)
                coordinator.seedRunningSessionForTesting(id: session.id)
            }
        }
        return (coordinator, store)
    }

    // MARK: The decision, per entry route

    func testComposerRouteFillsTheCanvas() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .composer), .fullCanvas)
    }

    func testToggleShortcutRouteSplitsBesideTheTerminal() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .toggleShortcut), .split)
    }

    func testAgentOpenRouteSplitsBesideTheTerminal() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .agentOpen), .split)
    }

    func testSidebarRowRouteShowsABrowserAsItWasMade() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .browserRow(created: .fullCanvas)), .fullCanvas)
        XCTAssertEqual(BrowserPlacement.presentation(for: .browserRow(created: .split)), .split)
        XCTAssertEqual(
            BrowserPlacement.presentation(for: .browserRow(created: nil)), .split,
            "a browser saved before presentations were recorded keeps the split"
        )
    }

    func testSidebarRowRouteForATerminalWithAPairedBrowserSplits() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .terminalRowWithPairedBrowser), .split)
    }

    func testQuickCreateRouteKeepsTheSplit() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .quickCreate), .split)
    }

    // MARK: Selecting a row

    func testSelectingAComposerMadeBrowserShowsItFullCanvas() {
        let page = browser("Browser 1", made: .fullCanvas)
        let (coordinator, _) = makeCoordinator([page])

        coordinator.focusSession(id: page.id)

        XCTAssertEqual(coordinator.shownBrowserSessionId, page.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .fullCanvas)
    }

    func testSelectingAShortcutMadeOrOlderBrowserShowsItSplit() {
        let shortcut = browser("Browser 1", made: .split)
        let older = browser("Browser 2", made: nil)
        let (coordinator, _) = makeCoordinator([shortcut, older])

        coordinator.focusSession(id: shortcut.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .split)

        coordinator.focusSession(id: older.id)
        XCTAssertEqual(coordinator.shownBrowserSessionId, older.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .split)
    }

    func testSelectingATerminalWithAPairedBrowserShowsTheSplit() {
        let race = terminal("reconnect race")
        // Even a pairing whose browser record says full canvas: beside its
        // terminal, a paired browser is always the split.
        let paired = browser("Browser 2", made: .fullCanvas)
        let (coordinator, _) = makeCoordinator([race, paired])
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: paired.id)

        coordinator.focusSession(id: race.id)

        XCTAssertEqual(coordinator.activeSessionId, race.id)
        XCTAssertEqual(coordinator.shownBrowserSessionId, paired.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .split)
    }

    func testSwitchingAwayAndBackRestoresEachPresentation() {
        let shell = terminal("shell")
        let race = terminal("reconnect race")
        let paired = browser("Browser 2", made: nil)
        let page = browser("Browser 3", made: .fullCanvas)
        let (coordinator, _) = makeCoordinator([shell, race, paired, page])
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: paired.id)

        coordinator.focusSession(id: page.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .fullCanvas)

        coordinator.focusSession(id: shell.id)
        XCTAssertNil(coordinator.shownBrowserSessionId, "a plain terminal shows no browser")
        XCTAssertNil(coordinator.shownBrowserPresentation)

        coordinator.focusSession(id: race.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .split)

        coordinator.focusSession(id: page.id)
        XCTAssertEqual(coordinator.shownBrowserSessionId, page.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .fullCanvas, "back to the composer's browser: full canvas again")

        coordinator.focusSession(id: race.id)
        XCTAssertEqual(coordinator.shownBrowserSessionId, paired.id)
        XCTAssertEqual(coordinator.shownBrowserPresentation, .split, "back to the terminal: its browser beside it again")
    }

    // MARK: What a relaunch restores

    func testTheStoreRecordsABrowsersPresentation() {
        let page = browser("Browser 1", made: nil)
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: [page])

        store.setBrowserPresentation(id: page.id, presentation: .fullCanvas)

        XCTAssertEqual(store.sessions.first?.browserPresentation, .fullCanvas)
    }

    func testASavedSessionKeepsItsPresentation() throws {
        let page = browser("Browser 1", made: .fullCanvas)

        let saved = try JSONEncoder().encode(page)
        let loaded = try JSONDecoder().decode(AgentSession.self, from: saved)

        XCTAssertEqual(loaded.browserPresentation, .fullCanvas)
        XCTAssertEqual(
            BrowserPlacement.presentation(for: .browserRow(created: loaded.browserPresentation)), .fullCanvas,
            "relaunching the row shows it as it was made"
        )
    }

    func testASessionSavedBeforePresentationsLoadsWithNone() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Browser 1",
         "templateId":"\(AgentTemplate.browser.id.uuidString)","projectId":"\(atlas.id.uuidString)"}
        """

        let loaded = try JSONDecoder().decode(AgentSession.self, from: Data(legacy.utf8))

        XCTAssertNil(loaded.browserPresentation)
    }

    // MARK: Who has the canvas

    func testAFullCanvasBrowserTakesTheCanvasUnlessHistoryIsOpen() {
        XCTAssertEqual(BrowserPlacement.canvasOccupant(presentation: .fullCanvas, isHistoryPresented: false), .browser)
        XCTAssertEqual(BrowserPlacement.canvasOccupant(presentation: .fullCanvas, isHistoryPresented: true), .terminalCard)
    }

    func testASplitOrHiddenBrowserLeavesTheCanvasToTheTerminal() {
        for history in [false, true] {
            XCTAssertEqual(BrowserPlacement.canvasOccupant(presentation: .split, isHistoryPresented: history), .terminalCard)
            XCTAssertEqual(BrowserPlacement.canvasOccupant(presentation: nil, isHistoryPresented: history), .terminalCard)
        }
    }
}
