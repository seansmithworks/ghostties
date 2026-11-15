import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// One view folds idle projects into one "Idle · N" row at the bottom of
/// the list (`SidebarIdleFold`): which projects are idle, which never fold,
/// what the row reads, where it sits, that its state persists, and that no
/// project changes sides while the pointer is inside the list.
@MainActor
final class SidebarIdleFoldTests: XCTestCase {
    private func project(_ name: String, pinned: Bool = false) -> Project {
        Project(name: name, rootPath: "~/Code/\(name)", isPinned: pinned)
    }

    private func session(_ name: String, _ project: Project) -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: project.id)
    }

    /// The fold for `projects` and `sessions`, each session showing
    /// `kinds[its name]` (done when absent).
    private func arrangement(
        _ projects: [Project], _ sessions: [AgentSession], kinds: [String: SessionStatusGlyphKind] = [:],
        selected: AgentSession? = nil, held: Set<UUID>? = nil, isExpanded: Bool = false
    ) -> SidebarIdleFold.Arrangement {
        let groups = SidebarProjectGroup.make(active: sessions, projects: projects)
        let active = SidebarIdleFold.activeProjectIds(groups) { kinds[$0.name] ?? .done }
        let live = SidebarIdleFold.unfolded(active: active, selectedProjectId: selected?.projectId)
        let shown = SidebarIdleFold.shown(live: live, held: held, selectedProjectId: selected?.projectId, isExpanded: isExpanded)
        return SidebarIdleFold.arrange(groups, unfolded: shown, isExpanded: isExpanded)
    }

    private func names(_ groups: [SidebarProjectGroup]) -> [String] { groups.map(\.name) }

    /// The list's items as short words: a project's name for its header,
    /// "idle" for the fold row, "-" for a spacer, "row" for a thread.
    private func itemWords(_ arrangement: SidebarIdleFold.Arrangement) -> [String] {
        SidebarProjectGroupItem.items(arrangement.groups, collapsed: [], idleFold: arrangement.row).map { item in
            switch item {
            case .spacer: return "-"
            case .header(let group, _): return group.name
            case .row: return "row"
            case .idleFold: return "idle"
            }
        }
    }

    // MARK: - Active or idle

    func testAProjectIsActiveOnlyWhileAThreadIsWorkingOrNeedsYou() {
        XCTAssertTrue(SidebarIdleFold.isActive([.working]))
        XCTAssertTrue(SidebarIdleFold.isActive([.needsInput]))
        XCTAssertTrue(SidebarIdleFold.isActive([.done, .stopped, .working]), "one working thread is enough")
        XCTAssertFalse(SidebarIdleFold.isActive([.done, .stopped, .error]), "done, stopped and error threads are idle")
        XCTAssertFalse(SidebarIdleFold.isActive([]), "a project with no threads is idle")
    }

    func testAThreadsStatusIsWhatItsRowShows() {
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .processing, state: nil), .working)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .longRunning, state: nil), .working)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .needsAttention, state: nil), .needsInput)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .waiting, state: nil), .done)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .idle, state: nil), .done)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .error, state: nil), .error)
        XCTAssertEqual(SessionNeedsYou.shownKind(indicator: .inactive, state: nil), .stopped)
    }

    func testIdleProjectsFoldAndActiveOnesStayInAlphabeticalOrder() {
        let wren = project("wren"), atlas = project("atlas"), silo = project("silo"), empty = project("empty")
        let w = session("w", wren), a = session("a", atlas), s = session("s", silo)
        let result = arrangement([wren, atlas, silo, empty], [w, a, s], kinds: ["w": .working, "a": .needsInput, "s": .error])

        XCTAssertEqual(names(result.listed), ["atlas", "wren"], "a working and a needs-you project, by name")
        XCTAssertEqual(names(result.idle), ["empty", "silo"], "no threads, and an error thread only")
        XCTAssertEqual(names(result.groups), ["atlas", "wren"], "folded: the idle projects are not drawn")
    }

    // MARK: - Never folded

    func testPinnedProjectsNeverFold() {
        let pinnedIdle = project("pinned-idle", pinned: true), pinnedEmpty = project("pinned-empty", pinned: true)
        let busy = project("busy"), quiet = project("quiet")
        let p = session("p", pinnedIdle), b = session("b", busy), q = session("q", quiet)
        let result = arrangement([pinnedIdle, pinnedEmpty, busy, quiet], [p, b, q], kinds: ["p": .stopped, "b": .working])

        XCTAssertEqual(names(result.listed), ["pinned-idle", "pinned-empty", "busy"], "pinned stay on top, active or not")
        XCTAssertEqual(names(result.idle), ["quiet"])
    }

    func testTheSelectedThreadsIdleProjectStaysOutOfTheFold() {
        let busy = project("busy"), here = project("here"), quiet = project("quiet")
        let b = session("b", busy), h = session("h", here), q = session("q", quiet)
        let result = arrangement([busy, here, quiet], [b, h, q], kinds: ["b": .working], selected: h)

        XCTAssertEqual(names(result.listed), ["busy", "here"], "the selected thread's project is listed, in its place by name")
        XCTAssertEqual(names(result.idle), ["quiet"])
        XCTAssertEqual(result.row?.count, 1)
    }

    func testThreadsWhoseProjectIsGoneNeverFold() {
        let busy = project("busy")
        let b = session("b", busy)
        let orphan = AgentSession(name: "orphan", templateId: UUID(), projectId: UUID())
        let result = arrangement([busy], [b, orphan], kinds: ["b": .working])

        XCTAssertEqual(names(result.listed), ["busy", "Unknown"])
        XCTAssertNil(result.row)
    }

    // MARK: - The row

    func testTheIdleRowCountsTheFoldedProjects() {
        let busy = project("busy")
        let b = session("b", busy)
        let three = arrangement([busy, project("x"), project("y"), project("z")], [b], kinds: ["b": .working])
        XCTAssertEqual(three.row?.count, 3)
        XCTAssertEqual(SidebarIdleFold.label(count: 3), "Idle · 3")

        let one = arrangement([busy, project("x")], [b], kinds: ["b": .working])
        XCTAssertEqual(one.row?.count, 1, "one idle project still folds")
        XCTAssertEqual(SidebarIdleFold.label(count: 1), "Idle · 1")
    }

    func testTheIdleRowIsAbsentWithNoIdleProject() {
        let busy = project("busy"), pinned = project("pinned", pinned: true)
        let b = session("b", busy)
        let result = arrangement([busy, pinned], [b], kinds: ["b": .working])

        XCTAssertNil(result.row)
        XCTAssertEqual(itemWords(result), ["pinned", "-", "busy", "row"])
    }

    func testTheFoldedRowEndsTheList() {
        let pinned = project("pinned", pinned: true), busy = project("busy")
        let b = session("b", busy)
        let result = arrangement([pinned, busy, project("x"), project("y")], [b], kinds: ["b": .working])

        XCTAssertEqual(itemWords(result), ["pinned", "-", "busy", "row", "-", "idle"])
    }

    func testTheExpandedRowLeadsTheIdleProjects() {
        let busy = project("busy"), x = project("x")
        let b = session("b", busy), x1 = session("x1", x)
        let result = arrangement([busy, x, project("y")], [b, x1], kinds: ["b": .working], isExpanded: true)

        XCTAssertEqual(names(result.groups), ["busy", "x", "y"])
        XCTAssertEqual(itemWords(result), ["busy", "row", "-", "idle", "-", "x", "row", "-", "y"])
        XCTAssertEqual(result.row, SidebarIdleFold.Row(count: 2, isExpanded: true, beforeGroupId: x.id.uuidString))
    }

    /// One break above the row, never a second one under it: with only
    /// pinned projects listed, the pinned break would otherwise fall on the
    /// first idle project.
    func testThePinnedBreakSitsAboveTheRowNotUnderIt() {
        let pinned = project("pinned", pinned: true), x = project("x")
        let result = arrangement([pinned, x], [], isExpanded: true)
        let items = SidebarProjectGroupItem.items(result.groups, collapsed: [], idleFold: result.row)
        let heights = items.compactMap { item -> CGFloat? in
            if case .spacer(_, let height) = item { return height }
            return nil
        }

        XCTAssertEqual(itemWords(result), ["pinned", "-", "idle", "-", "x"])
        XCTAssertEqual(heights, [
            SidebarProjectGroupItem.spacerHeight + SidebarProjectGroupItem.idleBreakHeight,
            SidebarProjectGroupItem.spacerHeight,
        ])
    }

    func testTheRowHasItsPlaceInTheExpandCascade() {
        let busy = project("busy")
        let b = session("b", busy)
        let result = arrangement([busy, project("x")], [b], kinds: ["b": .working])
        let items = SidebarProjectGroupItem.items(result.groups, collapsed: [], idleFold: result.row)
        let cascade = SidebarProjectGroupItem.cascade(items, start: 0)

        XCTAssertEqual(cascade.headers[busy.id.uuidString], 0)
        XCTAssertEqual(cascade.rows[b.id], 1)
        XCTAssertEqual(cascade.headers[SidebarIdleFold.rowId], 2)
        XCTAssertEqual(cascade.end, 3)
    }

    // MARK: - Persistence

    func testTheFoldIsClosedByDefaultAndPersistsAcrossADefaultsReload() throws {
        let suite = "ghostties.tests.idle-fold.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let first = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(SidebarIdleFold.isExpanded(defaults: first), "folded by default")

        SidebarIdleFold.setExpanded(true, defaults: first)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(SidebarIdleFold.isExpanded(defaults: reloaded), "expanded survives a reload")

        SidebarIdleFold.setExpanded(false, defaults: reloaded)
        let again = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(SidebarIdleFold.isExpanded(defaults: again), "folded survives a reload")
    }

    // MARK: - The pointer

    func testNoProjectChangesSidesWhileThePointerIsInsideTheList() {
        let a = UUID(), b = UUID(), c = UUID()
        // The pointer entered with a and b unfolded; since then b went idle
        // and c started working.
        let held: Set<UUID> = [a, b]
        let live: Set<UUID> = [a, c]

        XCTAssertEqual(
            SidebarIdleFold.shown(live: live, held: held, selectedProjectId: nil, isExpanded: false), held,
            "inside: the list is as it was when the pointer entered"
        )
        XCTAssertEqual(
            SidebarIdleFold.shown(live: live, held: nil, selectedProjectId: nil, isExpanded: false), live,
            "outside: the list follows the threads"
        )
    }

    func testTheSelectedThreadsProjectLeavesAClosedFoldEvenUnderThePointer() {
        let a = UUID(), picked = UUID()
        let live = SidebarIdleFold.unfolded(active: [a], selectedProjectId: picked)

        XCTAssertEqual(
            SidebarIdleFold.shown(live: live, held: [a], selectedProjectId: picked, isExpanded: false), [a, picked],
            "folded: its row has to exist, so it comes out at once"
        )
        XCTAssertEqual(
            SidebarIdleFold.shown(live: live, held: [a], selectedProjectId: picked, isExpanded: true), [a],
            "expanded: its row is already on screen, so it stays put until the pointer leaves"
        )
    }

    func testArrangingByTheHeldSetKeepsEveryProjectWhereItWas() {
        let alpha = project("alpha"), beta = project("beta"), gamma = project("gamma")
        let a = session("a", alpha), b = session("b", beta), g = session("g", gamma)
        let before = arrangement([alpha, beta, gamma], [a, b, g], kinds: ["a": .working, "b": .working])
        // beta finishes and gamma starts while the pointer is inside.
        let during = arrangement(
            [alpha, beta, gamma], [a, b, g], kinds: ["a": .working, "g": .working], held: [alpha.id, beta.id]
        )
        let after = arrangement([alpha, beta, gamma], [a, b, g], kinds: ["a": .working, "g": .working])

        XCTAssertEqual(names(during.listed), names(before.listed))
        XCTAssertEqual(names(during.idle), names(before.idle))
        XCTAssertEqual(names(after.listed), ["alpha", "gamma"], "once the pointer leaves, the projects change sides")
        XCTAssertEqual(names(after.idle), ["beta"])
    }

    // MARK: - Accessibility

    func testTheRowSpeaksItsCountAndWhatAClickDoes() {
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityLabel(count: 4), "Idle projects, 4")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityHint(isExpanded: false), "Shows the idle projects")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityHint(isExpanded: true), "Hides the idle projects")
    }
}
