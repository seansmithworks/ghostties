import XCTest
import GhosttiesCore
@testable import Ghostty

/// A browser an agent opened (`gt browser open`) sits directly under its
/// terminal in the one-view list and reads `from <terminal name>`. The
/// pairing is the coordinator's runtime-only terminal-to-browser map, passed
/// in here; an empty map is "no pairing". Every store is persistence-disabled
/// (`WorkspaceStore(testingProjects:)`), never `WorkspaceStore.shared`.
@MainActor
final class PairedBrowserRowTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")

    private func session(_ name: String, _ project: Project, template: UUID = UUID()) -> AgentSession {
        AgentSession(name: name, templateId: template, projectId: project.id)
    }

    private func names(_ groups: [SidebarProjectGroup], _ project: Project) -> [String] {
        groups.first { $0.projectId == project.id }?.sessions.map(\.name) ?? []
    }

    func testAPairedBrowserSitsDirectlyUnderItsTerminalEvenIfCreatedLater() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [race, other, browser]

        let plain = SidebarProjectGroup.make(active: active, projects: [atlas])
        let paired = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [race.id: browser.id])

        XCTAssertEqual(names(plain, atlas), ["reconnect race", "other", "Browser 3"])
        XCTAssertEqual(names(paired, atlas), ["reconnect race", "Browser 3", "other"])
    }

    func testThePairedBrowserFollowsItsTerminalWhenItMoves() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let pairs = [race.id: browser.id]

        let moved = SidebarProjectGroup.make(active: [other, browser, race], projects: [atlas], pairedBrowsers: pairs)

        XCTAssertEqual(names(moved, atlas), ["other", "reconnect race", "Browser 3"])
    }

    func testTheSubtitleNamesTheTerminal() {
        let race = session("reconnect race", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let pairs = [race.id: browser.id]

        XCTAssertEqual(PairedBrowserRows.subtitle(for: browser, in: [race, browser], pairedBrowsers: pairs), "from reconnect race")
        XCTAssertNil(PairedBrowserRows.subtitle(for: race, in: [race, browser], pairedBrowsers: pairs), "the terminal keeps its status word")
    }

    func testUnpairingRestoresOrderAndSubtitle() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [race, other, browser]

        let unpaired = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [:])

        XCTAssertEqual(names(unpaired, atlas), ["reconnect race", "other", "Browser 3"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: browser, in: active, pairedBrowsers: [:]))
    }

    func testUnpairedBrowsersAndEveryOtherRowAreUnchanged() {
        let race = session("reconnect race", atlas)
        let paired = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let loose = session("Browser 4", atlas, template: AgentTemplate.browser.id)
        let field = session("f1", fieldwork)
        let active = [race, loose, paired, field]

        let groups = SidebarProjectGroup.make(active: active, projects: [atlas, fieldwork], pairedBrowsers: [race.id: paired.id])

        XCTAssertEqual(names(groups, atlas), ["reconnect race", "Browser 3", "Browser 4"])
        XCTAssertEqual(names(groups, fieldwork), ["f1"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: loose, in: active, pairedBrowsers: [race.id: paired.id]))
        XCTAssertNil(PairedBrowserRows.subtitle(for: field, in: active, pairedBrowsers: [race.id: paired.id]))
    }

    func testAPairWhoseTerminalIsNotInTheGroupKeepsTheBrowserWhereItIs() {
        let pinnedTerminal = session("pinned", atlas)
        let a1 = session("a1", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let active = [a1, browser]

        let groups = SidebarProjectGroup.make(active: active, projects: [atlas], pairedBrowsers: [pinnedTerminal.id: browser.id])

        XCTAssertEqual(names(groups, atlas), ["a1", "Browser 3"])
        XCTAssertNil(PairedBrowserRows.subtitle(for: browser, in: active, pairedBrowsers: [pinnedTerminal.id: browser.id]))
    }

    func testTheRailFollowsTheSameOrder() {
        let race = session("reconnect race", atlas)
        let other = session("other", atlas)
        let browser = session("Browser 3", atlas, template: AgentTemplate.browser.id)
        let all = [race, other, browser]
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }

        XCTAssertEqual(store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name), ["reconnect race", "other", "Browser 3"])
        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true, pairedBrowsers: [race.id: browser.id]).map(\.name),
            ["reconnect race", "Browser 3", "other"]
        )
    }

    // MARK: - Reorder resolves against the displayed order

    /// Store order T, other, B, extra; displayed T, B, other, extra.
    @MainActor private struct Scene {
        let store: WorkspaceStore
        let project: Project
        let t: AgentSession, o: AgentSession, b: AgentSession, x: AgentSession
        var pairs: [UUID: UUID] { [t.id: b.id] }
        var active: [AgentSession] {
            RecentsListView.activeSessions(from: store.sessions, statuses: store.globalStatuses, pinningAvailable: true)
        }
        var displayed: [String] {
            let groups = SidebarProjectGroup.make(active: active, projects: [project], pairedBrowsers: pairs)
            return groups[0].sessions.map(\.name)
        }
        /// What the view hands the store: the displayed (seated) list.
        func apply(_ drop: PairedBrowserRows.Drop) {
            store.moveSessionsInSessionsView(
                ids: drop.ids, before: drop.beforeId,
                within: PairedBrowserRows.seated(active, pairedBrowsers: pairs)
            )
        }
    }

    private func scene() -> Scene {
        let t = session("T", atlas)
        let o = session("o", atlas)
        let b = session("B", atlas, template: AgentTemplate.browser.id)
        let x = session("X", atlas)
        let store = WorkspaceStore(testingProjects: [atlas], testingSessions: [t, o, b, x])
        for s in [t, o, b, x] { store.updateSessionStatus(id: s.id, status: .running) }
        return Scene(store: store, project: atlas, t: t, o: o, b: b, x: x)
    }

    func testADropBetweenTerminalAndBrowserLandsAfterThePairWhereTheGapShows() {
        let s = scene()
        XCTAssertEqual(s.displayed, ["T", "B", "o", "X"])

        // Displayed rows without X: T, B, o. The gap between T and B is index 1.
        let drop = PairedBrowserRows.drop(dragged: s.x.id, gapIndex: 1, in: s.active, pairedBrowsers: s.pairs)

        XCTAssertEqual(drop, PairedBrowserRows.Drop(ids: [s.x.id], beforeId: s.o.id), "a gap inside a pair is shown, and lands, after the pair")
        let fromDisplayed = PairedBrowserRows.drop(
            dragged: s.x.id, gapIndex: 1, in: PairedBrowserRows.seated(s.active, pairedBrowsers: s.pairs), pairedBrowsers: s.pairs
        )
        XCTAssertEqual(fromDisplayed, drop, "the same drop whichever order the list arrives in")
        s.apply(drop)
        XCTAssertEqual(s.displayed, ["T", "B", "X", "o"])
    }

    func testADropJustAfterTheBrowserLandsThere() {
        let s = scene()

        let drop = PairedBrowserRows.drop(dragged: s.x.id, gapIndex: 2, in: s.active, pairedBrowsers: s.pairs)

        XCTAssertEqual(drop, PairedBrowserRows.Drop(ids: [s.x.id], beforeId: s.o.id))
        s.apply(drop)
        XCTAssertEqual(s.displayed, ["T", "B", "X", "o"])
    }

    func testMoveUpAndDownStepThroughDisplayedNeighbours() throws {
        let up = scene()
        let moveUp = PairedBrowserRows.move(up.x.id, direction: -1, in: up.active, pairedBrowsers: up.pairs)
        XCTAssertEqual(moveUp, PairedBrowserRows.Drop(ids: [up.x.id], beforeId: up.o.id))
        up.apply(try XCTUnwrap(moveUp))
        XCTAssertEqual(up.displayed, ["T", "B", "X", "o"], "X stayed put: it stepped over a row the user cannot see there")

        let down = scene()
        let moveDown = PairedBrowserRows.move(down.o.id, direction: 1, in: down.active, pairedBrowsers: down.pairs)
        XCTAssertEqual(moveDown, PairedBrowserRows.Drop(ids: [down.o.id], beforeId: nil))
        down.apply(try XCTUnwrap(moveDown))
        XCTAssertEqual(down.displayed, ["T", "B", "X", "o"])
    }

    func testMoveHopsAWholePairAndNeverSplitsIt() {
        let t = session("T", atlas), p = session("P", atlas), o = session("o", atlas)
        let b = session("B", atlas, template: AgentTemplate.browser.id)
        let pairs = [t.id: b.id]
        let list = [p, t, o, b]   // displayed: P, T, B, o

        let down = PairedBrowserRows.move(p.id, direction: 1, in: list, pairedBrowsers: pairs)
        XCTAssertEqual(down, PairedBrowserRows.Drop(ids: [p.id], beforeId: o.id), "Move Down from above a pair lands below it")

        let up = PairedBrowserRows.move(o.id, direction: -1, in: list, pairedBrowsers: pairs)
        XCTAssertEqual(up, PairedBrowserRows.Drop(ids: [o.id], beforeId: t.id), "Move Up from below a pair lands above it")

        XCTAssertEqual(
            PairedBrowserRows.move(t.id, direction: 1, in: list, pairedBrowsers: pairs),
            PairedBrowserRows.Drop(ids: [t.id, b.id], beforeId: nil),
            "the terminal carries its browser"
        )
    }

    func testDraggingTheTerminalCarriesItsBrowser() {
        let s = scene()

        // Displayed rows without T and B: o, X. A gap at index 1 is before X.
        let drop = PairedBrowserRows.drop(dragged: s.t.id, gapIndex: 1, in: s.active, pairedBrowsers: s.pairs)

        XCTAssertEqual(drop, PairedBrowserRows.Drop(ids: [s.t.id, s.b.id], beforeId: s.x.id))
        s.apply(drop)
        XCTAssertEqual(s.displayed, ["o", "T", "B", "X"])
    }

    func testAPairedBrowserCannotBeDraggedOrMovedOnItsOwn() {
        let s = scene()
        let list = PairedBrowserRows.seated(s.active, pairedBrowsers: s.pairs)

        XCTAssertTrue(PairedBrowserRows.isSeatedBrowser(s.b.id, in: list, pairedBrowsers: s.pairs))
        XCTAssertFalse(PairedBrowserRows.isSeatedBrowser(s.t.id, in: list, pairedBrowsers: s.pairs))
        XCTAssertFalse(PairedBrowserRows.isSeatedBrowser(s.b.id, in: list, pairedBrowsers: [:]), "unpaired, it is an ordinary row again")
        XCTAssertNil(PairedBrowserRows.move(s.b.id, direction: -1, in: s.active, pairedBrowsers: s.pairs))
        XCTAssertNil(PairedBrowserRows.move(s.b.id, direction: 1, in: s.active, pairedBrowsers: s.pairs))
    }

    func testWithNoPairingReorderIsExactlyToday() {
        let a = session("a", atlas), b = session("b", atlas), c = session("c", atlas), d = session("d", atlas)
        let list = [a, b, c, d]

        XCTAssertEqual(PairedBrowserRows.drop(dragged: a.id, gapIndex: 1, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [a.id], beforeId: c.id))
        XCTAssertEqual(PairedBrowserRows.drop(dragged: a.id, gapIndex: nil, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [a.id], beforeId: nil))
        XCTAssertEqual(PairedBrowserRows.drop(dragged: d.id, gapIndex: 0, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [d.id], beforeId: a.id))
        XCTAssertEqual(PairedBrowserRows.move(b.id, direction: -1, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [b.id], beforeId: a.id))
        XCTAssertEqual(PairedBrowserRows.move(b.id, direction: 1, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [b.id], beforeId: d.id))
        XCTAssertEqual(PairedBrowserRows.move(c.id, direction: 1, in: list, pairedBrowsers: [:]),
                       PairedBrowserRows.Drop(ids: [c.id], beforeId: nil))
        XCTAssertNil(PairedBrowserRows.move(a.id, direction: -1, in: list, pairedBrowsers: [:]))
        XCTAssertNil(PairedBrowserRows.move(d.id, direction: 1, in: list, pairedBrowsers: [:]))
    }
}
