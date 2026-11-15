import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// One view: rows order by last activity and hold still under the pointer
/// (`SessionRecencyOrder`), the list follows the selection
/// (`SidebarSelectionFollow`), and a project header's "+" sits where its
/// count was (`ProjectAccordionHeader`).
///
/// Every store here is persistence-disabled (`WorkspaceStore(testingProjects:)`).
@MainActor
final class SidebarSwitchCreateTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")
    private let base = Date(timeIntervalSince1970: 1_000_000)

    /// A session last active `minutesAgo` before `base`; nil for never.
    private func session(_ name: String, _ project: Project, minutesAgo: Double?, pinned: Bool = false) -> AgentSession {
        AgentSession(
            name: name, templateId: UUID(), projectId: project.id,
            lastActiveAt: minutesAgo.map { base.addingTimeInterval(-$0 * 60) }, isPinned: pinned
        )
    }

    private func names(_ ids: [UUID], in sessions: [AgentSession]) -> [String] {
        ids.compactMap { id in sessions.first { $0.id == id }?.name }
    }

    // MARK: - Ranking

    func testRankingIsNewestFirstWithUndatedLastAndTiesInListOrder() {
        let old = session("old", atlas, minutesAgo: 60)
        let never = session("never", atlas, minutesAgo: nil)
        let fresh = session("fresh", atlas, minutesAgo: 1)
        let tieA = session("tieA", atlas, minutesAgo: 10)
        let tieB = session("tieB", atlas, minutesAgo: 10)
        let all = [old, never, fresh, tieA, tieB]

        XCTAssertEqual(
            names(SessionRecencyOrder.ranking(all, selected: nil), in: all),
            ["fresh", "tieA", "tieB", "old", "never"]
        )
    }

    /// Focus advances `lastActiveAt` in 5s steps, so the session just
    /// switched to can carry an older timestamp than the one switched from.
    func testSelectedSessionLeadsEvenWhenItsTimestampIsOlder() {
        let fresh = session("fresh", atlas, minutesAgo: 1)
        let older = session("older", atlas, minutesAgo: 30)
        let all = [fresh, older]

        XCTAssertEqual(names(SessionRecencyOrder.ranking(all, selected: older.id), in: all), ["older", "fresh"])
    }

    // MARK: - Holding still

    func testOrderIsHeldWhileTimestampsMove() {
        var a = session("a", atlas, minutesAgo: 1)
        let b = session("b", atlas, minutesAgo: 5)
        var order = SessionRecencyOrder()
        XCTAssertTrue(order.handle(.listAppeared, sessions: [a, b], selected: nil, pointerOverList: false))
        XCTAssertEqual(order.ordered([b, a]).map(\.name), ["a", "b"])

        // `a` goes quiet and `b` prints: no event, so no row moves.
        a.lastActiveAt = base.addingTimeInterval(-3600)
        XCTAssertEqual(order.ordered([b, a]).map(\.name), ["a", "b"])
        // A second appearance (the rail mounting) keeps the held order.
        XCTAssertFalse(order.handle(.listAppeared, sessions: [a, b], selected: nil, pointerOverList: false))
        XCTAssertEqual(order.ordered([b, a]).map(\.name), ["a", "b"])
    }

    func testSelectionChangeReordersWhenThePointerIsOffTheList() {
        let a = session("a", atlas, minutesAgo: 1)
        let b = session("b", atlas, minutesAgo: 5)
        let c = session("c", atlas, minutesAgo: 9)
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a, b, c], selected: a.id, pointerOverList: false)

        XCTAssertTrue(order.handle(.selectionChanged, sessions: [a, b, c], selected: c.id, pointerOverList: false))
        XCTAssertEqual(order.ordered([a, b, c]).map(\.name), ["c", "a", "b"])
        XCTAssertFalse(order.isPending)
    }

    func testReorderWaitsWhileThePointerIsOverTheListThenAppliesOnExit() {
        let a = session("a", atlas, minutesAgo: 1)
        let b = session("b", atlas, minutesAgo: 5)
        let c = session("c", atlas, minutesAgo: 9)
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a, b, c], selected: a.id, pointerOverList: false)

        // A click on `c`: the pointer is on the list, so nothing moves.
        XCTAssertFalse(order.handle(.selectionChanged, sessions: [a, b, c], selected: c.id, pointerOverList: true))
        XCTAssertEqual(order.ordered([a, b, c]).map(\.name), ["a", "b", "c"])
        XCTAssertTrue(order.isPending)
        // A session finishing meanwhile waits too.
        XCTAssertFalse(order.handle(.sessionFinished, sessions: [a, b, c], selected: c.id, pointerOverList: true))
        XCTAssertEqual(order.ordered([a, b, c]).map(\.name), ["a", "b", "c"])

        XCTAssertTrue(order.handle(.pointerExited, sessions: [a, b, c], selected: c.id, pointerOverList: false))
        XCTAssertEqual(order.ordered([a, b, c]).map(\.name), ["c", "a", "b"])
        XCTAssertFalse(order.isPending)
    }

    func testPointerExitWithNothingWaitingChangesNothing() {
        var a = session("a", atlas, minutesAgo: 1)
        let b = session("b", atlas, minutesAgo: 5)
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a, b], selected: nil, pointerOverList: false)
        a.lastActiveAt = base.addingTimeInterval(-3600)

        XCTAssertFalse(order.handle(.pointerExited, sessions: [a, b], selected: nil, pointerOverList: false))
        XCTAssertEqual(order.ordered([a, b]).map(\.name), ["a", "b"])
    }

    func testASessionFinishingReorders() {
        let a = session("a", atlas, minutesAgo: 20)
        var b = session("b", atlas, minutesAgo: 30)
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a, b], selected: nil, pointerOverList: false)
        XCTAssertEqual(order.ordered([a, b]).map(\.name), ["a", "b"])

        // `b` worked until now, then stopped.
        b.lastActiveAt = base
        let before = SessionRecencyOrder.working([a, b], indicators: [b.id: .processing])
        let after = SessionRecencyOrder.working([a, b], indicators: [b.id: .idle])
        XCTAssertEqual(before, [b.id])
        XCTAssertTrue(SessionRecencyOrder.finished(from: before, to: after))
        XCTAssertTrue(order.handle(.sessionFinished, sessions: [a, b], selected: nil, pointerOverList: false))
        XCTAssertEqual(order.ordered([a, b]).map(\.name), ["b", "a"])
    }

    func testOnlyASessionLeavingTheWorkingSetCountsAsFinished() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(SessionRecencyOrder.finished(from: [a], to: [a, b]), "a session starting work is not a finish")
        XCTAssertFalse(SessionRecencyOrder.finished(from: [a], to: [a]))
        XCTAssertTrue(SessionRecencyOrder.finished(from: [a, b], to: [a]))
        // A long run is still working; a question, a failure and a stop are not.
        let s = session("s", atlas, minutesAgo: 1)
        XCTAssertEqual(SessionRecencyOrder.working([s], indicators: [s.id: .longRunning]), [s.id])
        for state in [SessionIndicatorState.needsAttention, .error, .inactive, .idle] {
            XCTAssertTrue(SessionRecencyOrder.working([s], indicators: [s.id: state]).isEmpty, "\(state)")
        }
    }

    /// A session created since the last reorder has no held rank: it leads
    /// its project, the newest of several first.
    func testANewSessionLeadsBeforeTheNextReorder() {
        let a = session("a", atlas, minutesAgo: 1)
        let b = session("b", atlas, minutesAgo: 5)
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a, b], selected: nil, pointerOverList: false)
        let new1 = session("new1", atlas, minutesAgo: 0)
        let new2 = session("new2", atlas, minutesAgo: 0)

        XCTAssertEqual(order.ordered([a, b, new1, new2]).map(\.name), ["new2", "new1", "a", "b"])
    }

    // MARK: - Groups, rail and shortcuts

    func testEachProjectOrdersByRecencyAndProjectOrderIsUnchanged() {
        let a1 = session("a1", atlas, minutesAgo: 50)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let a2 = session("a2", atlas, minutesAgo: 3)
        let f2 = session("f2", fieldwork, minutesAgo: 40)
        let a3 = session("a3", atlas, minutesAgo: 10)
        let active = [a1, f1, a2, f2, a3]
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: active, selected: nil, pointerOverList: false)

        let groups = SidebarProjectGroup.make(active: order.ordered(active), projects: [fieldwork, atlas])
        // Projects stay alphabetical, though fieldwork holds the newest session.
        XCTAssertEqual(groups.map(\.name), ["atlas-api", "fieldwork"])
        XCTAssertEqual(groups.map { $0.sessions.map(\.name) }, [["a2", "a3", "a1"], ["f1", "f2"]])
    }

    func testRailAndShortcutOrderFollowTheHeldOrderAndPinnedStaysOnTop() {
        let pinned = session("orchestrator", fieldwork, minutesAgo: 500, pinned: true)
        let a1 = session("a1", atlas, minutesAgo: 50)
        let a2 = session("a2", atlas, minutesAgo: 3)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let all = [pinned, a1, a2, f1]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: [a1, a2, f1], selected: nil, pointerOverList: false)

        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true, recency: order).map(\.name),
            ["orchestrator", "a2", "a1", "f1"]
        )
        // Without a window's order, creation order as before.
        XCTAssertEqual(
            store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name),
            ["orchestrator", "a1", "a2", "f1"]
        )
    }

    func testTheTabsLayoutIgnoresRecency() {
        let a1 = session("a1", atlas, minutesAgo: 50)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let a2 = session("a2", atlas, minutesAgo: 3)
        let all = [a1, f1, a2]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }
        var order = SessionRecencyOrder()
        order.handle(.listAppeared, sessions: all, selected: nil, pointerOverList: false)

        XCTAssertEqual(store.railSessions(layout: .tabs, recency: order).map(\.name), ["a1", "f1", "a2"])
    }

    // MARK: - Following the selection

    private func plan(
        layout: SidebarProjectsLayout = .oneView, route: SidebarSelectionFollow.Route = .direct, selected: UUID?,
        pinned: [AgentSession] = [], active: [AgentSession], collapsed: Set<UUID> = [], isRail: Bool = false
    ) -> SidebarSelectionFollow.Plan {
        SidebarSelectionFollow.plan(
            layout: layout, route: route, selected: selected,
            rows: SidebarSelectionFollow.Rows(pinned: pinned, active: active, collapsed: collapsed),
            isRail: isRail
        )
    }

    func testSelectingARowInAFoldedProjectUnfoldsItAndScrollsToTheRow() {
        let a1 = session("a1", atlas, minutesAgo: 1)
        let f1 = session("f1", fieldwork, minutesAgo: 2)

        XCTAssertEqual(
            plan(selected: f1.id, active: [a1, f1], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(reorders: true, unfold: fieldwork.id, scrollTo: f1.id.uuidString, animates: true)
        )
        // Another project's fold is left alone.
        XCTAssertEqual(
            plan(selected: a1.id, active: [a1, f1], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(reorders: true, unfold: nil, scrollTo: a1.id.uuidString, animates: true)
        )
    }

    /// The session shortcuts walk the list by position: reordering on each
    /// press would send Next Session back and forth between two rows.
    func testAKeyboardMoveScrollsAndUnfoldsButNeitherReordersNorAnimates() {
        let f1 = session("f1", fieldwork, minutesAgo: 2)

        XCTAssertEqual(
            plan(route: .keyboard, selected: f1.id, active: [f1], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(reorders: false, unfold: fieldwork.id, scrollTo: f1.id.uuidString, animates: false)
        )
    }

    func testAPinnedSelectionScrollsWithoutUnfoldingItsProject() {
        let pinned = session("orchestrator", fieldwork, minutesAgo: 2, pinned: true)

        XCTAssertEqual(
            plan(selected: pinned.id, pinned: [pinned], active: [], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(reorders: true, unfold: nil, scrollTo: pinned.id.uuidString, animates: true)
        )
    }

    func testASelectionWithNoRowScrollsNowhere() {
        let a1 = session("a1", atlas, minutesAgo: 1)

        XCTAssertEqual(plan(selected: nil, active: [a1]), SidebarSelectionFollow.Plan())
        // History's session, or one whose terminal has not opened yet.
        let rowless = plan(selected: UUID(), active: [a1], collapsed: [atlas.id])
        XCTAssertNil(rowless.scrollTo)
        XCTAssertNil(rowless.unfold)
    }

    func testTheTabsLayoutKeepsItsRailOnlyKeyboardScroll() {
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        func tabs(_ route: SidebarSelectionFollow.Route, isRail: Bool) -> SidebarSelectionFollow.Plan {
            plan(layout: .tabs, route: route, selected: f1.id, active: [f1], collapsed: [fieldwork.id], isRail: isRail)
        }

        XCTAssertEqual(tabs(.keyboard, isRail: true), SidebarSelectionFollow.Plan(scrollTo: f1.id.uuidString))
        XCTAssertEqual(tabs(.keyboard, isRail: false), SidebarSelectionFollow.Plan())
        XCTAssertEqual(tabs(.direct, isRail: true), SidebarSelectionFollow.Plan())
        XCTAssertEqual(tabs(.direct, isRail: false), SidebarSelectionFollow.Plan())
    }

    // MARK: - Header "+"

    func testThePlusTakesAPlainCountsPlaceAndSitsBesideANeedYouLabel() {
        let glyph = ProjectAccordionHeader.newThreadGlyphWidth
        // A plain count: the glyph's trailing edge on the count's.
        let overCount = ProjectAccordionHeader.newThreadCenterX(labelMinX: 182, labelMaxX: 200, needYouCount: 0)
        XCTAssertEqual(overCount + glyph / 2, 200)
        // "2 need you": the glyph ends one gap before the label, which stays.
        let beside = ProjectAccordionHeader.newThreadCenterX(labelMinX: 140, labelMaxX: 200, needYouCount: 2)
        XCTAssertEqual(beside + glyph / 2, 140 - ProjectAccordionHeader.newThreadLabelGap)
    }

    func testANeedYouHeaderAlwaysKeepsRoomForThePlus() {
        XCTAssertEqual(ProjectAccordionHeader.newThreadReserve(needYouCount: 0, canCreate: true), 0)
        XCTAssertEqual(
            ProjectAccordionHeader.newThreadReserve(needYouCount: 1, canCreate: true),
            ProjectAccordionHeader.newThreadGlyphWidth + ProjectAccordionHeader.newThreadLabelGap
        )
        // The "Unknown" group has no project to create in.
        XCTAssertEqual(ProjectAccordionHeader.newThreadReserve(needYouCount: 1, canCreate: false), 0)
    }

    func testThePlusShowsOnHoverOrFocusOnTheExpandedSidebarOnly() {
        func shows(canCreate: Bool = true, hovered: Bool = false, focused: Bool = false, morph: CGFloat = 0) -> Bool {
            ProjectAccordionHeader.showsNewThread(canCreate: canCreate, isHovered: hovered, isFocused: focused, morph: morph)
        }
        XCTAssertFalse(shows(), "at rest the count shows")
        XCTAssertTrue(shows(hovered: true))
        XCTAssertTrue(shows(focused: true), "keyboard focus draws it without the pointer")
        XCTAssertFalse(shows(canCreate: false, hovered: true))
        XCTAssertFalse(shows(hovered: true, morph: 1), "the rail's header is its tile alone")
        XCTAssertFalse(shows(hovered: true, morph: 0.4), "nor mid-morph")
    }

    func testThePlusIsLabelledWithItsProject() {
        XCTAssertEqual(ProjectAccordionHeader.newThreadAccessibilityLabel(project: "atlas-api"), "New thread in atlas-api")
    }

    /// The header "+" and the Projects tab row's "+" are one route: a plain
    /// press opens the composer on the project, Option creates at once when
    /// the project has a default template.
    func testThePlusRoutesLikeTheProjectRowsPlus() {
        let defaultTemplate = AgentTemplate.defaults[0]
        var project = atlas
        project.defaultTemplateId = defaultTemplate.id

        guard case .openComposer(let binding) = ProjectRowNewSession.action(
            for: project, optionHeld: false, templates: AgentTemplate.defaults
        ), case .prefilled(let prefilled) = binding else {
            return XCTFail("a plain press opens the composer with the project filled in")
        }
        XCTAssertEqual(prefilled.id, project.id)
        guard case .instantCreate(let template) = ProjectRowNewSession.action(
            for: project, optionHeld: true, templates: AgentTemplate.defaults
        ) else {
            return XCTFail("Option creates at once")
        }
        XCTAssertEqual(template.id, defaultTemplate.id)
    }
}
