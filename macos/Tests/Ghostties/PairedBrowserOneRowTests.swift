import XCTest
import GhosttiesCore
@testable import Ghostty

/// A browser an agent opened (`gt browser open`) is one sidebar row with its
/// terminal: no row of its own in the one-view list, the rail, the Sessions
/// tab or Cmd+Shift+[ / ], the terminal's row carries a browser icon and
/// reads as selected when the browser is up, and closing the terminal closes
/// the browser. Every store is the injected persistence-disabled kind, never
/// `WorkspaceStore.shared`.
@MainActor
final class PairedBrowserOneRowTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")

    private func session(_ name: String, template: UUID = UUID()) -> AgentSession {
        AgentSession(name: name, templateId: template, projectId: atlas.id)
    }

    private func browserSession(_ name: String) -> AgentSession {
        session(name, template: AgentTemplate.browser.id)
    }

    private func makeStore(_ sessions: [AgentSession]) -> WorkspaceStore {
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: sessions)
        for s in sessions { store.updateSessionStatus(id: s.id, status: .running) }
        return store
    }

    private func makeCoordinator(_ store: WorkspaceStore) -> SessionCoordinator {
        let coordinator = SessionCoordinator()
        coordinator.agentKindLookupStoreForTesting = store
        return coordinator
    }

    // MARK: 1. No row of its own

    func testTheSessionsTabAndOneViewListOmitThePairedBrowser() {
        let race = session("reconnect race")
        let browser = browserSession("Browser 2")
        let sections = SidebarSessionSections.make(
            sessions: [race, browser], statuses: [race.id: .running, browser.id: .running],
            sessionIdsStartedThisLaunch: [], pinningAvailable: true,
            pairedBrowsers: [race.id: browser.id]
        )
        XCTAssertEqual(sections.active.map(\.name), ["reconnect race"])
        XCTAssertEqual(sections.rowSessions.map(\.name), ["reconnect race"])

        let groups = SidebarProjectGroup.make(active: sections.active, projects: [atlas])
        XCTAssertEqual(groups.first?.sessions.map(\.name), ["reconnect race"])
    }

    func testTheRailOmitsThePairedBrowser() {
        let race = session("reconnect race")
        let other = session("other")
        let browser = browserSession("Browser 2")
        let store = makeStore([race, other, browser])
        let pairs = [race.id: browser.id]

        XCTAssertEqual(store.railSessions(layout: .oneView, pinningAvailable: true, pairedBrowsers: pairs).map(\.name), ["reconnect race", "other"])
        XCTAssertEqual(store.railSessions(layout: .tabs, pinningAvailable: true, pairedBrowsers: pairs).map(\.name), ["reconnect race", "other"])
    }

    // MARK: 7. An unpaired browser keeps its row

    func testAnUnpairedBrowserKeepsItsOwnRow() {
        let race = session("reconnect race")
        let paired = browserSession("Browser 2")
        let mine = browserSession("Browser 3")
        let store = makeStore([race, paired, mine])

        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true, pairedBrowsers: [race.id: paired.id]).map(\.name),
            ["reconnect race", "Browser 3"]
        )
        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name),
            ["reconnect race", "Browser 2", "Browser 3"], "no pairing: nothing is hidden"
        )
        XCTAssertEqual(PairedBrowserRows.visible([race, paired, mine], pairedBrowsers: [race.id: paired.id]).map(\.name), ["reconnect race", "Browser 3"])
    }

    // MARK: 2. The terminal's row carries the icon

    func testOnlyThePairedTerminalShowsTheBrowserIcon() {
        let race = session("reconnect race")
        let other = session("other")
        let browser = browserSession("Browser 2")
        let pairs = [race.id: browser.id]

        XCTAssertTrue(PairedBrowserRows.hasBrowser(race.id, pairedBrowsers: pairs))
        XCTAssertFalse(PairedBrowserRows.hasBrowser(other.id, pairedBrowsers: pairs))
        XCTAssertFalse(PairedBrowserRows.hasBrowser(race.id, pairedBrowsers: [:]), "closing the browser drops the icon")
    }

    // MARK: 3. Next / previous treat the pair as one stop

    func testCyclingNeverStopsOnThePairedBrowser() {
        let a = session("a"), b = session("b"), c = session("c")
        let browser = browserSession("Browser 2")
        let store = makeStore([a, b, browser, c])
        let coordinator = makeCoordinator(store)
        for s in [a, b, c] {
            coordinator.seedEmptySessionTreeForTesting(id: s.id)
            coordinator.seedRunningSessionForTesting(id: s.id)
        }
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: b.id, browser: browser.id)

        let stops = store.railSessions(layout: .oneView, pinningAvailable: true, pairedBrowsers: coordinator.pairedBrowserByTerminal)
            .filter { coordinator.hasLiveSurface(id: $0.id) }
        XCTAssertEqual(stops.map(\.name), ["a", "b", "c"])

        // From the browser (selected as its terminal's row), next is the row after the terminal.
        coordinator.setActiveSessionIdForTesting(browser.id)
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: 1, in: stops)?.name, "c")
        coordinator.setActiveSessionIdForTesting(browser.id)
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: -1, in: stops)?.name, "a")
    }

    func testTheProjectsTabVisualOrderSkipsThePairedBrowser() {
        let a = session("a")
        let browser = browserSession("Browser 2")
        let store = makeStore([a, browser])
        let coordinator = makeCoordinator(store)
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: a.id, browser: browser.id)

        XCTAssertEqual(store.sessionsInVisualOrder(coordinator: coordinator).map(\.name), ["a"])
    }

    // MARK: 4. Closing the terminal closes the browser

    func testClosingTheTerminalClosesItsPairedBrowser() {
        let race = session("reconnect race")
        let browser = browserSession("Browser 2")
        let store = makeStore([race, browser])
        let coordinator = makeCoordinator(store)
        coordinator.seedEmptySessionTreeForTesting(id: race.id)
        coordinator.seedRunningSessionForTesting(id: race.id)
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: browser.id)
        coordinator.setActiveSessionIdForTesting(race.id)

        coordinator.closeSession(id: race.id)

        XCTAssertFalse(coordinator.isSessionBrowser(browser.id), "the browser outlived its terminal")
        XCTAssertEqual(store.globalStatuses[browser.id], .killed)
        XCTAssertNil(coordinator.pairedBrowserByTerminal[race.id])
        XCTAssertNil(coordinator.activeSessionId)
    }

    func testClosingTheTerminalWhileItsBrowserIsActiveLeavesNothingActive() {
        let race = session("reconnect race")
        let browser = browserSession("Browser 2")
        let store = makeStore([race, browser])
        let coordinator = makeCoordinator(store)
        coordinator.seedEmptySessionTreeForTesting(id: race.id)
        coordinator.seedRunningSessionForTesting(id: race.id)
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: browser.id)
        coordinator.setActiveSessionIdForTesting(browser.id)

        coordinator.closeSession(id: race.id)

        XCTAssertFalse(coordinator.isSessionBrowser(browser.id))
        XCTAssertNil(coordinator.activeSessionId, "neither the dead terminal nor its browser may stay selected")
    }

    func testClosingAnUnpairedTerminalLeavesAnotherBrowserAlone() {
        let race = session("reconnect race")
        let mine = browserSession("Browser 3")
        let store = makeStore([race, mine])
        let coordinator = makeCoordinator(store)
        coordinator.seedEmptySessionTreeForTesting(id: race.id)
        coordinator.seedBrowserSessionForTesting(id: mine.id)

        coordinator.closeSession(id: race.id)

        XCTAssertTrue(coordinator.isSessionBrowser(mine.id))
    }

    // MARK: 5. Closing the browser keeps working

    func testClosingThePairedBrowserKeepsTheTerminalAndDropsThePairing() {
        let race = session("reconnect race")
        let browser = browserSession("Browser 2")
        let store = makeStore([race, browser])
        let coordinator = makeCoordinator(store)
        coordinator.seedEmptySessionTreeForTesting(id: race.id)
        coordinator.seedRunningSessionForTesting(id: race.id)
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: browser.id)
        coordinator.setActiveSessionIdForTesting(race.id)

        coordinator.closeSession(id: browser.id)

        XCTAssertNotNil(coordinator.sessionTrees[race.id])
        XCTAssertNil(coordinator.pairedBrowserByTerminal[race.id])
        XCTAssertFalse(PairedBrowserRows.hasBrowser(race.id, pairedBrowsers: coordinator.pairedBrowserByTerminal))
    }

    // MARK: 6. Selection maps to the terminal's row

    func testTheTerminalRowIsSelectedWhenThePairedBrowserIsActive() {
        let race = session("reconnect race")
        let browser = browserSession("Browser 2")
        let coordinator = makeCoordinator(makeStore([race, browser]))
        coordinator.seedBrowserSessionForTesting(id: browser.id)
        coordinator.seedPairedBrowserForTesting(terminal: race.id, browser: browser.id)

        coordinator.setActiveSessionIdForTesting(browser.id)
        XCTAssertEqual(coordinator.sidebarSelectedSessionId, race.id)

        coordinator.setActiveSessionIdForTesting(race.id)
        XCTAssertEqual(coordinator.sidebarSelectedSessionId, race.id)
    }

    func testAnUnpairedBrowserIsSelectedAsItself() {
        let mine = browserSession("Browser 3")
        let coordinator = makeCoordinator(makeStore([mine]))
        coordinator.seedBrowserSessionForTesting(id: mine.id)
        coordinator.setActiveSessionIdForTesting(mine.id)

        XCTAssertEqual(coordinator.sidebarSelectedSessionId, mine.id)
    }
}
