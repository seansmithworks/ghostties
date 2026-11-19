import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// One view folds idle projects into one "No threads · N" row at the bottom of
/// the list (`SidebarIdleFold`): which projects are idle (only those with no
/// thread), which never fold,
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

    func testAProjectIsActiveWhileItHasAnyThread() {
        XCTAssertTrue(SidebarIdleFold.isActive([.working]))
        XCTAssertTrue(SidebarIdleFold.isActive([.needsInput]))
        XCTAssertTrue(SidebarIdleFold.isActive([.done]), "a done thread is an open thread")
        XCTAssertTrue(SidebarIdleFold.isActive([.stopped, .error]), "so are stopped and error ones")
        XCTAssertFalse(SidebarIdleFold.isActive([]), "a project with no threads is idle")
    }

    func testAProjectWithOnlyADoneThreadIsOutsideTheFold() {
        let quiet = project("quiet")
        let result = arrangement([quiet], [session("q", quiet)], kinds: ["q": .done])

        XCTAssertEqual(names(result.listed), ["quiet"])
        XCTAssertTrue(result.idle.isEmpty)
        XCTAssertNil(result.row)
    }

    func testAProjectWithOnlyAPlainShellIsOutsideTheFold() {
        let shell = project("shell")
        let result = arrangement([shell], [session("sh", shell)], kinds: ["sh": .stopped])

        XCTAssertEqual(names(result.listed), ["shell"])
        XCTAssertNil(result.row)
    }

    func testAProjectWithNoThreadFolds() {
        let empty = project("empty")
        let result = arrangement([empty], [])

        XCTAssertTrue(result.listed.isEmpty)
        XCTAssertEqual(names(result.idle), ["empty"])
        XCTAssertEqual(result.row?.count, 1)
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

        XCTAssertEqual(names(result.listed), ["atlas", "silo", "wren"], "any thread, whatever its status, by name")
        XCTAssertEqual(names(result.idle), ["empty"], "no threads")
        XCTAssertEqual(names(result.groups), ["atlas", "silo", "wren"], "folded: the idle project is not drawn")
    }

    // MARK: - Never folded

    func testPinnedProjectsNeverFold() {
        let pinnedIdle = project("pinned-idle", pinned: true), pinnedEmpty = project("pinned-empty", pinned: true)
        let busy = project("busy"), quiet = project("quiet")
        let p = session("p", pinnedIdle), b = session("b", busy)
        let result = arrangement([pinnedIdle, pinnedEmpty, busy, quiet], [p, b], kinds: ["p": .stopped, "b": .working])

        XCTAssertEqual(names(result.listed), ["pinned-idle", "pinned-empty", "busy"], "pinned stay on top, with a thread or without")
        XCTAssertEqual(names(result.idle), ["quiet"])
    }

    func testTheSelectedThreadsIdleProjectStaysOutOfTheFold() {
        let busy = project("busy"), here = project("here"), quiet = project("quiet")
        let b = session("b", busy), h = session("h", here)
        let result = arrangement([busy, here, quiet], [b, h], kinds: ["b": .working], selected: h)

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
        XCTAssertEqual(SidebarIdleFold.label(count: 3), "No threads · 3")

        let one = arrangement([busy, project("x")], [b], kinds: ["b": .working])
        XCTAssertEqual(one.row?.count, 1, "one idle project still folds")
        XCTAssertEqual(SidebarIdleFold.label(count: 1), "No threads · 1")
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
        let b = session("b", busy)
        let result = arrangement([busy, x, project("y")], [b], kinds: ["b": .working], isExpanded: true)

        XCTAssertEqual(names(result.groups), ["busy", "x", "y"])
        XCTAssertEqual(itemWords(result), ["busy", "row", "-", "idle", "-", "x", "-", "y"])
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
        let first = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
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
        let before = arrangement([alpha, beta, gamma], [a, b])
        // beta's thread closes and gamma gets one while the pointer is inside.
        let during = arrangement([alpha, beta, gamma], [a, g], held: [alpha.id, beta.id])
        let after = arrangement([alpha, beta, gamma], [a, g])

        XCTAssertEqual(names(during.listed), names(before.listed))
        XCTAssertEqual(names(during.idle), names(before.idle))
        XCTAssertEqual(names(after.listed), ["alpha", "gamma"], "once the pointer leaves, the projects change sides")
        XCTAssertEqual(names(after.idle), ["beta"])
    }

    func testAProjectGainingAThreadStaysFoldedUnderThePointer() {
        let alpha = project("alpha"), beta = project("beta")
        let a = session("a", alpha), b = session("b", beta)
        let during = arrangement([alpha, beta], [a, b], held: [alpha.id])

        XCTAssertEqual(names(during.idle), ["beta"], "the hold keeps beta where it was")
        XCTAssertNil(arrangement([alpha, beta], [a, b]).row, "pointer gone: beta comes out")
    }

    /// The pointer's exit is what ends a hold, and none arrives when the
    /// sidebar hides or goes to the rail under a still pointer, or when the
    /// user leaves the window with the pointer resting over the list.
    func testAHoldEndsWhenTheSidebarHidesCollapsesOrTheWindowIsLeft() {
        let live: Set<UUID> = [UUID(), UUID()]
        XCTAssertEqual(SidebarIdleFold.held(after: .pointerEntered, live: live), live, "entering holds the list as it is")
        XCTAssertNil(SidebarIdleFold.held(after: .pointerLeft, live: live))
        XCTAssertNil(SidebarIdleFold.held(after: .sidebarModeChanged, live: live), "hidden, or collapsed to the rail")
        XCTAssertNil(SidebarIdleFold.held(after: .windowResignedKey, live: live), "the window lost the pointer without an exit")
    }

    // MARK: - A pinned thread

    /// A pinned thread draws in the Pinned section, not under its
    /// project's header, so no group holds it. Its project is still active.
    func testAProjectWhoseOnlyThreadIsPinnedIsActive() {
        let wren = project("wren"), silo = project("silo"), atlas = project("atlas")
        let pinnedWorking = session("pw", wren), pinnedAsking = session("pa", silo), pinnedDone = session("pd", atlas)
        let quiet = session("q", wren)
        let kinds: [String: SessionStatusGlyphKind] = ["pw": .working, "pa": .needsInput, "pd": .done]
        // Active holds only the unpinned thread.
        let groups = SidebarProjectGroup.make(active: [quiet], projects: [wren, silo, atlas])

        XCTAssertEqual(
            SidebarIdleFold.activeProjectIds(groups) { kinds[$0.name] ?? .done }, [wren.id],
            "control: by their own rows alone, only wren has a thread"
        )
        let active = SidebarIdleFold.activeProjectIds(groups, pinned: [pinnedWorking, pinnedAsking, pinnedDone]) {
            kinds[$0.name] ?? .done
        }
        XCTAssertEqual(active, [wren.id, silo.id, atlas.id], "a pinned thread, whatever its status, makes its project active")

        let result = SidebarIdleFold.arrange(
            groups, unfolded: SidebarIdleFold.unfolded(active: active, selectedProjectId: nil), isExpanded: false
        )
        XCTAssertEqual(names(result.listed), ["atlas", "silo", "wren"])
        XCTAssertTrue(result.idle.isEmpty)
    }

    // MARK: - Needs you, behind the fold

    func testTheIdleRowReadsNNeedYouWhenAFoldedProjectNeedsYou() {
        let silo = project("silo"), wren = project("wren")
        let s1 = session("s1", silo), s2 = session("s2", silo), w = session("w", wren)
        let idle = SidebarProjectGroup.make(active: [s1, s2, w], projects: [silo, wren])
        let asking: Set<String> = ["s1", "w"]

        let count = SidebarIdleFold.needYouCount(idle) { asking.contains($0.name) }
        XCTAssertEqual(count, 2, "every asking thread in every folded project")
        XCTAssertEqual(SidebarIdleFold.needYouLabel(count), "2 need you")
        XCTAssertEqual(
            SidebarIdleFold.needYouLabel(count), SessionNeedsYou.headerCountLabel(sessionCount: 3, needYou: count),
            "a project header's own words"
        )
    }

    func testTheIdleRowHasNoNeedYouLabelWhenNothingFoldedNeedsYou() {
        let silo = project("silo")
        let idle = SidebarProjectGroup.make(active: [session("s", silo)], projects: [silo])

        let count = SidebarIdleFold.needYouCount(idle) { _ in false }
        XCTAssertEqual(count, 0)
        XCTAssertNil(SidebarIdleFold.needYouLabel(count))
        XCTAssertNil(SidebarIdleFold.needYouLabel(SidebarIdleFold.needYouCount([]) { _ in true }), "an empty fold")
    }

    /// The pointer is in the list when a folded project's thread starts
    /// needing you: the hold keeps the project folded, and the row counts
    /// the thread from its state now, not from the held set.
    func testTheNeedYouCountIsLiveWhileTheFoldIsHeld() {
        let alpha = project("alpha"), beta = project("beta")
        let a = session("a", alpha), b = session("b", beta)
        // The pointer entered with only alpha outside the fold; since then
        // beta's thread started needing you.
        let during = arrangement([alpha, beta], [a, b], kinds: ["a": .working, "b": .needsInput], held: [alpha.id])
        XCTAssertEqual(names(during.idle), ["beta"], "control: the hold keeps beta folded")
        XCTAssertEqual(during.row?.count, 1, "and the row where it was")

        let count = SidebarIdleFold.needYouCount(during.idle) { $0.name == "b" }
        XCTAssertEqual(SidebarIdleFold.needYouLabel(count), "1 need you")

        // The pointer leaves: beta comes out, and the row has nothing to say.
        let after = arrangement([alpha, beta], [a, b], kinds: ["a": .working, "b": .needsInput])
        XCTAssertNil(after.row, "beta is listed, under its own \"1 need you\" header")
    }

    // MARK: - Accessibility

    func testTheIdleRowSpeaksHowManyNeedYou() {
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityLabel(count: 5, needYouCount: 1), "Projects with no threads, 5, 1 need you")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityLabel(count: 5, needYouCount: 3), "Projects with no threads, 5, 3 need you")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityLabel(count: 5, needYouCount: 0), "Projects with no threads, 5")
    }

    // MARK: - Capture knob

    func testTheHeldFoldCaptureKnobNamesTheProjectsOutsideTheFold() {
        let alpha = project("alpha"), beta = project("beta")
        XCTAssertNil(CaptureFixture.parseIdleFoldHeld(nil, projects: [alpha, beta]), "unset: no hold")
        XCTAssertNil(CaptureFixture.parseIdleFoldHeld("", projects: [alpha, beta]))
        XCTAssertEqual(CaptureFixture.parseIdleFoldHeld("none", projects: [alpha, beta]), [], "held with nothing outside")
        XCTAssertEqual(CaptureFixture.parseIdleFoldHeld("beta, gone", projects: [alpha, beta]), [beta.id])
    }

    func testTheRowSpeaksItsCountAndWhatAClickDoes() {
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityLabel(count: 4), "Projects with no threads, 4")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityHint(isExpanded: false), "Shows the idle projects")
        XCTAssertEqual(IdleProjectsFoldRow.accessibilityHint(isExpanded: true), "Hides the idle projects")
    }
}
