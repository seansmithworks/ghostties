import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// One view: a project's threads keep the user's order (creation order
/// until dragged), the list follows the selection
/// (`SidebarSelectionFollow`), and a project header's "+" chip sits where
/// its count was (`ProjectAccordionHeader`).
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

    /// A store whose sessions all have a live terminal, so all are Active.
    private func runningStore(_ sessions: [AgentSession], projects: [Project]? = nil) -> WorkspaceStore {
        let store = WorkspaceStore(testingProjects: projects ?? [atlas, fieldwork], testingSessions: sessions)
        for s in sessions { store.updateSessionStatus(id: s.id, status: .running) }
        return store
    }

    /// Each project's rows as one view draws them, by project name.
    private func oneViewRows(_ store: WorkspaceStore) -> [String: [String]] {
        let active = RecentsListView.activeSessions(from: store.sessions, statuses: store.globalStatuses, pinningAvailable: true)
        let groups = SidebarProjectGroup.make(active: active, projects: store.projects)
        return Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.sessions.map(\.name)) })
    }

    /// The rows the rail and the session shortcuts walk.
    private func railRows(_ store: WorkspaceStore) -> [String] {
        store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name)
    }

    // MARK: - Fixed order

    /// The newest activity is on the last row and the oldest on the first:
    /// rows stay in creation order, whatever their timestamps.
    func testThreadsKeepCreationOrderWhateverTheirLastActivity() {
        let a1 = session("a1", atlas, minutesAgo: 50)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let a2 = session("a2", atlas, minutesAgo: nil)
        let a3 = session("a3", atlas, minutesAgo: 1)
        let store = runningStore([a1, f1, a2, a3])

        XCTAssertEqual(oneViewRows(store), ["atlas-api": ["a1", "a2", "a3"], "fieldwork": ["f1"]])
        XCTAssertEqual(railRows(store), ["a1", "a2", "a3", "f1"])
    }

    /// A thread that starts working, prints and takes the selection's
    /// activity stamp stays on its row.
    func testAThreadBecomingActiveDoesNotMoveItsRow() {
        let a1 = session("a1", atlas, minutesAgo: 1)
        let a2 = session("a2", atlas, minutesAgo: 30)
        let a3 = session("a3", atlas, minutesAgo: 600)
        let f1 = session("f1", fieldwork, minutesAgo: 5)
        let store = runningStore([a1, a2, a3, f1])
        let before = oneViewRows(store)
        let railBefore = railRows(store)

        // `a3`, the stalest, starts working and prints now.
        store.updateIndicatorState(id: a3.id, state: .processing)
        store.recordActivity(sessionId: a3.id, projectId: atlas.id, isOutput: true)
        XCTAssertEqual(
            store.sessions.max { ($0.lastActiveAt ?? .distantPast) < ($1.lastActiveAt ?? .distantPast) }?.name, "a3",
            "a3 is now the most recently active thread"
        )
        XCTAssertEqual(oneViewRows(store), before)
        XCTAssertEqual(railRows(store), railBefore)

        // And when it finishes.
        store.updateIndicatorState(id: a3.id, state: .idle)
        XCTAssertEqual(oneViewRows(store), before)
        XCTAssertEqual(railRows(store), railBefore)
    }

    // MARK: - Dragging within a project

    /// One view's drop: a row's reorder acts on the whole Active list
    /// (`RecentsListView.groupedActiveRows` hands every row `sectionList:
    /// active`) through `moveSessionInSessionsView`.
    private func drop(_ dragged: AgentSession, before target: AgentSession?, in store: WorkspaceStore) {
        let active = RecentsListView.activeSessions(from: store.sessions, statuses: store.globalStatuses, pinningAvailable: true)
        store.moveSessionInSessionsView(id: dragged.id, before: target?.id, within: active)
    }

    func testDraggingAThreadWithinItsProjectReordersItAndTheOrderSticks() {
        let a1 = session("a1", atlas, minutesAgo: 1)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let a2 = session("a2", atlas, minutesAgo: 3)
        let a3 = session("a3", atlas, minutesAgo: 4)
        let store = runningStore([a1, f1, a2, a3])

        // The last atlas row, dropped on the first.
        drop(a3, before: a1, in: store)
        XCTAssertEqual(oneViewRows(store), ["atlas-api": ["a3", "a1", "a2"], "fieldwork": ["f1"]])
        XCTAssertEqual(railRows(store), ["a3", "a1", "a2", "f1"], "the rail and the shortcuts follow the dragged order")

        // The first, dropped after the last row of its project (before
        // nothing: the end of Active).
        drop(a3, before: nil, in: store)
        XCTAssertEqual(oneViewRows(store)["atlas-api"], ["a1", "a2", "a3"])
        drop(a2, before: a1, in: store)
        XCTAssertEqual(oneViewRows(store)["atlas-api"], ["a2", "a1", "a3"])

        // It sticks: activity on another row moves nothing.
        store.updateIndicatorState(id: a3.id, state: .processing)
        store.recordActivity(sessionId: a3.id, projectId: atlas.id, isOutput: true)
        XCTAssertEqual(oneViewRows(store)["atlas-api"], ["a2", "a1", "a3"])

        // And it is the sessions' own saved order (`sessionViewOrder`), so a
        // store loaded from them draws the same rows.
        let reloaded = runningStore(store.sessions)
        XCTAssertEqual(oneViewRows(reloaded), ["atlas-api": ["a2", "a1", "a3"], "fieldwork": ["f1"]])
    }

    func testPinnedStaysOnTopOfTheRailAndProjectsStayAlphabetical() {
        let pinned = session("orchestrator", fieldwork, minutesAgo: 500, pinned: true)
        let f1 = session("f1", fieldwork, minutesAgo: 2)
        let a1 = session("a1", atlas, minutesAgo: 50)
        let store = runningStore([pinned, f1, a1], projects: [fieldwork, atlas])

        // fieldwork holds the newest thread and was added first; atlas-api
        // still leads.
        XCTAssertEqual(railRows(store), ["orchestrator", "a1", "f1"])
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
            SidebarSelectionFollow.Plan(unfold: fieldwork.id, scrollTo: f1.id.uuidString, animates: true)
        )
        // Another project's fold is left alone.
        XCTAssertEqual(
            plan(selected: a1.id, active: [a1, f1], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(unfold: nil, scrollTo: a1.id.uuidString, animates: true)
        )
    }

    func testAKeyboardMoveScrollsAndUnfoldsWithoutAnimating() {
        let f1 = session("f1", fieldwork, minutesAgo: 2)

        XCTAssertEqual(
            plan(route: .keyboard, selected: f1.id, active: [f1], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(unfold: fieldwork.id, scrollTo: f1.id.uuidString, animates: false)
        )
    }

    func testAPinnedSelectionScrollsWithoutUnfoldingItsProject() {
        let pinned = session("orchestrator", fieldwork, minutesAgo: 2, pinned: true)

        XCTAssertEqual(
            plan(selected: pinned.id, pinned: [pinned], active: [], collapsed: [fieldwork.id]),
            SidebarSelectionFollow.Plan(unfold: nil, scrollTo: pinned.id.uuidString, animates: true)
        )
    }

    func testASelectionWithNoRowScrollsNowhere() {
        let a1 = session("a1", atlas, minutesAgo: 1)

        XCTAssertEqual(plan(selected: nil, active: [a1]), SidebarSelectionFollow.Plan())
        // History's session, or one whose terminal has not opened yet.
        XCTAssertEqual(plan(selected: UUID(), active: [a1], collapsed: [atlas.id]), SidebarSelectionFollow.Plan())
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

    /// The list scrolls to a row's target, which is the row plus the clear
    /// space kept above the tray (`SidebarSelectionFollowGateTests` measures
    /// it in a window).
    func testAFollowedRowKeepsEightPointsClearOfTheTray() {
        XCTAssertEqual(SidebarSelectionFollow.trayClearance, 8)
        let id = UUID().uuidString
        XCTAssertNotEqual(SidebarSelectionFollow.scrollTargetId(row: id), id, "the target is not the row's own frame")
    }

    // MARK: - Header "+" chip

    /// Over a plain count the chip is centred on the count's text, so the
    /// "+" glyph takes the digits' place: the icon aligns, not the square.
    func testTheChipIsCentredOnAPlainCount() {
        let size = ProjectAccordionHeader.newThreadChipSize
        // "7" and "128" as drawn: different widths, both ending at 200.
        let centres = [(193.0, 200.0), (180.0, 200.0)].map { minX, maxX in
            ProjectAccordionHeader.newThreadChipMinX(labelMinX: minX, labelMaxX: maxX, needYouCount: 0) + size / 2
        }
        XCTAssertEqual(centres, [196.5, 190])
        // The chip drawn is the click target: one size, a square on the 8pt grid.
        XCTAssertEqual(size, 24)
    }

    func testTheChipSitsBesideANeedYouLabelAndNeverOverIt() {
        let size = ProjectAccordionHeader.newThreadChipSize
        let minX = ProjectAccordionHeader.newThreadChipMinX(labelMinX: 140, labelMaxX: 200, needYouCount: 2)
        XCTAssertEqual(minX + size, 140 - ProjectAccordionHeader.newThreadLabelGap, "the chip ends one gap before the label")
        // The label keeps drawing under hover; a plain count gives way.
        XCTAssertFalse(ProjectAccordionHeader.hidesCountLabel(showsNewThread: true, needYouCount: 2))
        XCTAssertTrue(ProjectAccordionHeader.hidesCountLabel(showsNewThread: true, needYouCount: 0))
        XCTAssertFalse(ProjectAccordionHeader.hidesCountLabel(showsNewThread: false, needYouCount: 0))
    }

    func testANeedYouHeaderAlwaysKeepsRoomForTheChip() {
        XCTAssertEqual(ProjectAccordionHeader.newThreadReserve(needYouCount: 0, canCreate: true), 0)
        XCTAssertEqual(
            ProjectAccordionHeader.newThreadReserve(needYouCount: 1, canCreate: true),
            ProjectAccordionHeader.newThreadChipSize + ProjectAccordionHeader.newThreadLabelGap
        )
        // The "Unknown" group has no project to create in.
        XCTAssertEqual(ProjectAccordionHeader.newThreadReserve(needYouCount: 1, canCreate: false), 0)
        // The name gives way to the reserve, never the chip to the name.
        XCTAssertEqual(ProjectAccordionHeader.trailingLabelSpacing(needYouCount: 0, canCreate: true), 8)
        XCTAssertEqual(ProjectAccordionHeader.trailingLabelSpacing(needYouCount: 1, canCreate: false), 8)
        XCTAssertGreaterThan(
            ProjectAccordionHeader.trailingLabelSpacing(needYouCount: 1, canCreate: true),
            ProjectAccordionHeader.newThreadReserve(needYouCount: 1, canCreate: true)
        )
    }

    func testTheChipShowsOnHoverOrFocusOnTheExpandedSidebarOnly() {
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

    /// The fill is the row's hover tint, and the chip ink at the selected
    /// chip's opacity under the pointer: existing tokens only.
    func testTheChipFillsWithTheRowHoverTintAndBrightensUnderThePointer() {
        XCTAssertGreaterThan(RailProjectColumn.selectedChipTintOpacity, RailProjectColumn.hoverChipTintOpacity)
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(
                ProjectAccordionHeader.newThreadChipFill(isPointed: false, scheme),
                Color.primary.opacity(RailProjectColumn.hoverChipTintOpacity)
            )
            XCTAssertEqual(
                ProjectAccordionHeader.newThreadChipFill(isPointed: true, scheme),
                RailProjectColumn.tintInk(scheme).opacity(RailProjectColumn.selectedChipTintOpacity)
            )
        }
    }

    /// The tooltip and the VoiceOver label are one string.
    func testTheChipsTooltipNamesItsProject() {
        XCTAssertEqual(ProjectAccordionHeader.newThreadLabel(project: "atlas-api"), "New thread in atlas-api")
        XCTAssertEqual(ProjectAccordionHeader.newThreadLabel(project: "wren"), "New thread in wren")
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
