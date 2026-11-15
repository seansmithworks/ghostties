import AppKit
import Combine
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Where a browser goes is one decision, `BrowserPlacement.presentation(for:)`:
/// a browser made as a session (the composer, an Option-click "+", the tray)
/// fills the canvas, Cmd+B and `gt browser open` split beside the terminal,
/// and a sidebar row shows what its session was made as.
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

    // The four sources of a new browser, by name. Option-click and the tray
    // both call `createQuickSession(for:template:)` with no route, which is
    // `.quickCreate`; these pin where that route goes, not the call sites.

    func testOptionClickInstantCreateFillsTheCanvas() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .quickCreate), .fullCanvas)
    }

    func testTrayInstantCreateFillsTheCanvas() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .quickCreate), .fullCanvas)
    }

    func testCmdBSplitsBesideTheTerminal() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .toggleShortcut), .split)
    }

    func testCLIBrowserOpenSplitsBesideTheTerminal() {
        XCTAssertEqual(BrowserPlacement.presentation(for: .agentOpen), .split)
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

    // MARK: A real container

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    /// A container on an off-screen window, its coordinator reading the
    /// injected store and seeded with `sessions`.
    private func host(_ sessions: [AgentSession] = []) -> (WorkspaceViewContainer, NSWindow, WorkspaceStore) {
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: sessions)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let coordinator = container.coordinatorForTesting
        coordinator.agentKindLookupStoreForTesting = store
        for session in sessions {
            if session.templateId == AgentTemplate.browser.id {
                coordinator.seedBrowserSessionForTesting(id: session.id)
            } else {
                coordinator.seedEmptySessionTreeForTesting(id: session.id)
                coordinator.seedRunningSessionForTesting(id: session.id)
            }
        }
        let window = KeyableWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        window.makeKey()
        container.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        return (container, window, store)
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    /// A browser with one tab and no CEF view.
    private func pageManager() -> BrowserTabManager {
        let manager = BrowserTabManager()
        manager.createTab(url: "about:blank")
        return manager
    }

    // MARK: VoiceOver and the covered terminal

    func testAFullCanvasBrowserHidesTheTerminalItCoversFromVoiceOver() {
        let (container, _, _) = host()
        let manager = pageManager()
        XCTAssertFalse(container.isTerminalCardAccessibilityHiddenForTesting, "no browser: the terminal is read")

        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        XCTAssertTrue(container.isTerminalCardAccessibilityHiddenForTesting, "covered by the browser: skipped")

        container.showTerminalContent()
        XCTAssertFalse(container.isTerminalCardAccessibilityHiddenForTesting, "back on the canvas: read again")

        container.showBrowserContent(manager, bridge: nil, presentation: .split)
        XCTAssertFalse(container.isTerminalCardAccessibilityHiddenForTesting, "beside a split browser: still read")
    }

    func testHistoryOverAFullCanvasBrowserIsReadByVoiceOver() {
        let (container, _, _) = host()
        container.showBrowserContent(pageManager(), bridge: nil, presentation: .fullCanvas)
        XCTAssertTrue(container.isTerminalCardAccessibilityHiddenForTesting)

        // History is mounted in the terminal card and takes the canvas.
        container.coordinatorForTesting.presentHistory()
        settle()
        XCTAssertFalse(container.isTerminalCardAccessibilityHiddenForTesting)

        container.coordinatorForTesting.dismissHistory()
        settle()
        XCTAssertTrue(container.isTerminalCardAccessibilityHiddenForTesting, "the browser has the canvas again")
    }

    // MARK: Cmd+B on a full-canvas browser

    func testCmdBOnAFullCanvasBrowserSelectsTheTerminalTheCanvasShows() {
        let shell = terminal("shell")
        let other = terminal("reconnect race")
        let page = browser("Browser 3", made: .fullCanvas)
        let (container, _, store) = host([shell, other, page])
        let coordinator = container.coordinatorForTesting

        coordinator.focusSession(id: shell.id)
        coordinator.focusSession(id: page.id)
        // Later activity elsewhere must not pull the selection away from
        // the terminal the browser covered.
        store.recordActivity(sessionId: other.id, projectId: atlas.id, now: { Date().addingTimeInterval(60) })
        XCTAssertEqual(container.browserPresentation, .fullCanvas)
        XCTAssertEqual(coordinator.activeSessionId, page.id)

        container.toggleBrowser()

        XCTAssertNil(container.browserPresentation, "the canvas shows the terminal")
        XCTAssertEqual(coordinator.activeSessionId, shell.id, "and the sidebar selects that terminal")
        XCTAssertNil(coordinator.shownBrowserSessionId)
        XCTAssertNil(coordinator.shownBrowserPresentation)
        XCTAssertFalse(container.isTerminalCardAccessibilityHiddenForTesting)
    }

    func testCmdBOnAFullCanvasBrowserFallsBackToTheMostRecentTerminal() {
        let shell = terminal("shell")
        let other = terminal("reconnect race")
        let page = browser("Browser 3", made: .fullCanvas)
        let (container, _, store) = host([shell, other, page])
        let coordinator = container.coordinatorForTesting

        // Selected straight from launch: no terminal was showing before it.
        coordinator.focusSession(id: page.id)
        store.recordActivity(sessionId: other.id, projectId: atlas.id, now: { Date().addingTimeInterval(60) })

        container.toggleBrowser()

        XCTAssertEqual(coordinator.activeSessionId, other.id)
        XCTAssertNil(container.browserPresentation)
    }

    func testCmdBOnAFullCanvasBrowserWithNoTerminalKeepsTheBrowser() {
        let page = browser("Browser 1", made: .fullCanvas)
        let (container, _, _) = host([page])
        let coordinator = container.coordinatorForTesting
        coordinator.focusSession(id: page.id)

        container.toggleBrowser()

        XCTAssertEqual(coordinator.activeSessionId, page.id)
        XCTAssertEqual(container.browserPresentation, .fullCanvas, "nothing else to show: selection and canvas both stay on the browser")
    }

    // MARK: Keys go back to the terminal

    func testTheKeyHandOffTable() {
        typealias Placement = BrowserPlacement
        // The browser left the canvas while it had the keys.
        XCTAssertEqual(Placement.keyHandOff(holder: .browser, presentation: nil, isHistoryPresented: false, terminalWasConcealed: true), .toTerminal)
        XCTAssertEqual(Placement.keyHandOff(holder: .browser, presentation: nil, isHistoryPresented: false, terminalWasConcealed: false), .toTerminal)
        // A browser still on the canvas keeps them.
        XCTAssertNil(Placement.keyHandOff(holder: .browser, presentation: .split, isHistoryPresented: false, terminalWasConcealed: false))
        XCTAssertNil(Placement.keyHandOff(holder: .browser, presentation: .fullCanvas, isHistoryPresented: false, terminalWasConcealed: false))
        // Nobody has them: the terminal takes them only on its way back.
        XCTAssertEqual(Placement.keyHandOff(holder: .nobody, presentation: nil, isHistoryPresented: false, terminalWasConcealed: true), .toTerminal)
        XCTAssertNil(Placement.keyHandOff(holder: .nobody, presentation: nil, isHistoryPresented: false, terminalWasConcealed: false))
        // A covered terminal gives them up.
        XCTAssertEqual(Placement.keyHandOff(holder: .terminalCard, presentation: .fullCanvas, isHistoryPresented: false, terminalWasConcealed: false), .release)
        XCTAssertNil(Placement.keyHandOff(holder: .terminalCard, presentation: .split, isHistoryPresented: false, terminalWasConcealed: false))
        // History and everything outside the two cards are left alone.
        XCTAssertNil(Placement.keyHandOff(holder: .browser, presentation: nil, isHistoryPresented: true, terminalWasConcealed: true))
        XCTAssertNil(Placement.keyHandOff(holder: .terminalCard, presentation: .fullCanvas, isHistoryPresented: true, terminalWasConcealed: true))
        XCTAssertNil(Placement.keyHandOff(holder: .elsewhere, presentation: nil, isHistoryPresented: false, terminalWasConcealed: true))
    }

    /// Text views stand in for the page (CEF) and the focused terminal
    /// surface (a live terminal controller): this proves the container's
    /// hand-off, not that CEF gives up first responder.
    func testKeysGoBackToTheTerminalWhenTheBrowserThatHadThemLeavesTheCanvas() {
        for presentation in [BrowserPresentation.fullCanvas, .split] {
            let (container, window, _) = host()
            let surface = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            container.terminalCardForTesting.addSubview(surface)
            container.terminalKeyTargetForTesting = surface
            let manager = pageManager()
            let page = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            manager.registerBrowserView(page, for: manager.activeTabId!)

            XCTAssertTrue(window.makeFirstResponder(surface))
            container.showBrowserContent(manager, bridge: nil, presentation: presentation)
            if presentation == .fullCanvas {
                XCTAssertTrue(window.firstResponder === window, "a covered terminal gives up the keys")
            }
            XCTAssertTrue(window.makeFirstResponder(page))
            XCTAssertTrue(window.firstResponder === page, "the page has the keys (\(presentation))")

            container.showTerminalContent()

            XCTAssertTrue(window.firstResponder === surface, "the terminal has the keys again (\(presentation))")
        }
    }
}
