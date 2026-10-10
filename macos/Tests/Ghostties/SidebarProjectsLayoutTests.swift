import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Sidebar vnext B5: the "Projects layout" dial, the one-view grouping, its
/// persisted per-project collapse state, and the rail's monograms.
///
/// Every store here is persistence-disabled (`WorkspaceStore(testingProjects:)`).
@MainActor
final class SidebarProjectsLayoutTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let fieldwork = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")
    private let orbit = Project(name: "orbit-web", rootPath: "~/Code/orbit-web")
    private let empty = Project(name: "quiet", rootPath: "~/Code/quiet")

    private func session(_ name: String, _ project: Project, pinned: Bool = false) -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: project.id, isPinned: pinned)
    }

    private func suite(_ name: String) -> UserDefaults {
        let full = "com.seansmithdesign.ghostties.tests.projects-layout.\(name)"
        let d = UserDefaults(suiteName: full)!
        d.removePersistentDomain(forName: full)
        addTeardownBlock { d.removePersistentDomain(forName: full) }
        return d
    }

    // MARK: - Dial

    func testLayoutDefaultsToOneViewAndResets() {
        let d = suite("dial")
        XCTAssertEqual(SidebarDialTuning.projectsLayout(defaults: d), .oneView)
        d.set("tabs", forKey: SidebarDialTuning.projectsLayoutKey)
        XCTAssertEqual(SidebarDialTuning.projectsLayout(defaults: d), .tabs)
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.projectsLayoutKey))
        SidebarDialTuning.reset(defaults: d)
        XCTAssertEqual(SidebarDialTuning.projectsLayout(defaults: d), .oneView)
    }

    func testUnknownStoredLayoutFallsBackToOneView() {
        let d = suite("unknown")
        d.set("accordion", forKey: SidebarDialTuning.projectsLayoutKey)
        XCTAssertEqual(SidebarDialTuning.projectsLayout(defaults: d), .oneView)
    }

    // MARK: - Grouping

    func testGroupsFollowProjectOrderKeepEmptyProjectsAndKeepRowOrder() {
        let a1 = session("Claude Code 4", atlas)
        let f1 = session("docs pass", fieldwork)
        let a2 = session("auth refactor", atlas)
        let o1 = session("landing hero", orbit)
        let f2 = session("build fix", fieldwork)
        let groups = SidebarProjectGroup.make(active: [a1, f1, a2, o1, f2], projects: [atlas, empty, fieldwork, orbit])

        XCTAssertEqual(groups.map(\.name), ["atlas-api", "quiet", "fieldwork", "orbit-web"])
        XCTAssertEqual(groups.map { $0.sessions.map(\.name) }, [
            ["Claude Code 4", "auth refactor"],
            [],
            ["docs pass", "build fix"],
            ["landing hero"],
        ])
        XCTAssertEqual(groups.map(\.isEmpty), [false, true, false, false])
    }

    /// An empty project is a header with no rows, and never folds — even
    /// when a stale fold for it is stored — so its rail tile never wears a
    /// count badge.
    func testEmptyProjectIsAHeaderThatNeverFolds() {
        let groups = SidebarProjectGroup.make(active: [session("a", atlas)], projects: [empty, atlas])
        let items = SidebarProjectGroupItem.items(groups, collapsed: [empty.id])
        let shape: [String] = items.map {
            switch $0 {
            case .spacer: return "-"
            case .header(let g, let folded): return "\(g.name)\(folded ? "+" : "")"
            case .row(let s, _): return s.name
            }
        }
        XCTAssertEqual(shape, ["quiet", "-", "atlas-api", "a"])
    }

    // MARK: - Header click

    /// Clicking an empty project's header (or rail tile) selects it, as the
    /// Projects tab's header does, and leaves the folds alone.
    func testClickingAnEmptyProjectSelectsIt() {
        let d = suite("select")
        let folds = AppStorage(wrappedValue: "", ProjectAccordionState.collapsedKey, store: d)
        let store = WorkspaceStore(testingProjects: [atlas, empty], testingSessions: [session("a", atlas)])
        let coordinator = SessionCoordinator()
        let group = SidebarProjectGroup.make(active: [], projects: [empty])[0]
        XCTAssertNil(store.lastSelectedProjectId)

        ProjectAccordionState.headerClicked(group, collapsedRaw: folds.projectedValue) { id in
            ProjectSelection.select(id, store: store, coordinator: coordinator, window: nil)
        }

        XCTAssertEqual(store.lastSelectedProjectId, empty.id)
        XCTAssertNil(d.string(forKey: ProjectAccordionState.collapsedKey))
    }

    /// Clicking a non-empty project's header folds it and does not select.
    func testClickingAProjectWithSessionsFoldsItWithoutSelecting() {
        let d = suite("fold-no-select")
        let folds = AppStorage(wrappedValue: "", ProjectAccordionState.collapsedKey, store: d)
        let group = SidebarProjectGroup.make(active: [session("a", atlas)], projects: [atlas])[0]
        var selected: UUID?
        ProjectAccordionState.headerClicked(group, collapsedRaw: folds.projectedValue) { selected = $0 }
        XCTAssertNil(selected)
        XCTAssertEqual(ProjectAccordionState.decode(d.string(forKey: ProjectAccordionState.collapsedKey) ?? ""), [atlas.id])
    }

    func testSessionsOfAMissingProjectTrailInOneUnknownGroup() {
        let gone = Project(name: "deleted", rootPath: "~/gone")
        let a1 = session("kept", atlas)
        let lost = session("orphan", gone)
        let groups = SidebarProjectGroup.make(active: [lost, a1], projects: [atlas])
        XCTAssertEqual(groups.map(\.name), ["atlas-api", "Unknown"])
        XCTAssertNil(groups.last?.projectId)
        XCTAssertEqual(groups.last?.sessions.map(\.name), ["orphan"])
    }

    func testItemsFoldACollapsedProjectToItsHeader() {
        let groups = SidebarProjectGroup.make(
            active: [session("a", atlas), session("b", atlas), session("c", fieldwork)],
            projects: [atlas, fieldwork]
        )
        func shape(_ collapsed: Set<UUID>) -> [String] {
            SidebarProjectGroupItem.items(groups, collapsed: collapsed).map {
                switch $0 {
                case .spacer: return "-"
                case .header(let g, let folded): return "\(g.name)\(folded ? "+" : "")"
                case .row(let s, _): return s.name
                }
            }
        }
        XCTAssertEqual(shape([]), ["atlas-api", "a", "b", "-", "fieldwork", "c"])
        XCTAssertEqual(shape([atlas.id]), ["atlas-api+", "-", "fieldwork", "c"])
    }

    /// Pinned stays on top in one view: pinned sessions never join a
    /// project group, and the rail/shortcut order is Pinned then each
    /// project's sessions.
    func testRailOrderIsPinnedThenProjectByProjectInOneView() {
        let pinned = session("orchestrator", orbit, pinned: true)
        let a1 = session("a1", atlas)
        let f1 = session("f1", fieldwork)
        let a2 = session("a2", atlas)
        let all = [pinned, a1, f1, a2]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, orbit], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }

        XCTAssertEqual(store.railSessions(layout: .tabs, pinningAvailable: true).map(\.name), ["orchestrator", "a1", "f1", "a2"])
        XCTAssertEqual(store.railSessions(layout: .oneView, pinningAvailable: true).map(\.name), ["orchestrator", "a1", "a2", "f1"])
    }

    /// The rail's project column (`RailProjectColumn`) marks the selected
    /// session's project, and only it; a pinned or absent selection marks
    /// no project.
    func testRailColumnMarksTheSelectedSessionsProject() {
        let pinned = session("orchestrator", orbit, pinned: true)
        let a1 = session("a1", atlas)
        let f1 = session("f1", fieldwork)
        let f2 = session("f2", fieldwork)
        let groups = SidebarProjectGroup.make(active: [a1, f1, f2], projects: [atlas, fieldwork, orbit])

        XCTAssertEqual(RailProjectColumn.selectedGroupId(groups, selectedSessionId: f2.id), fieldwork.id.uuidString)
        XCTAssertEqual(RailProjectColumn.selectedGroupId(groups, selectedSessionId: a1.id), atlas.id.uuidString)
        XCTAssertNil(RailProjectColumn.selectedGroupId(groups, selectedSessionId: pinned.id))
        XCTAssertNil(RailProjectColumn.selectedGroupId(groups, selectedSessionId: nil))
    }

    // MARK: - Rail column dials

    /// Unset, every "Rail column" dial reads option D's value (pen.dev
    /// `p6osQ7`/`ZiGlb`: tint 6%, inset 4, chip radius 8 = the tile's, chip =
    /// the 30pt tile, full ink).
    func testRailColumnDialDefaultsAreOptionD() {
        withDials {
            XCTAssertEqual(RailProjectColumn.columnTintOpacity, 0.06)
            XCTAssertEqual(RailProjectColumn.columnInset, 4)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, 8)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, RailProjectTile.cornerRadius)
            XCTAssertEqual(RailProjectColumn.columnCornerRadius, 12)
            XCTAssertEqual(RailProjectTile.size, 30)
            XCTAssertEqual(RailProjectColumn.chipSize, 30)
            XCTAssertEqual(RailProjectColumn.selectedTileFill, 1)
            // The column fits the rail's content width (the real rail,
            // hugging a titled window's traffic lights, less the window
            // margin each side), so it never clips.
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
            if let close = window.standardWindowButton(.closeButton), let zoom = window.standardWindowButton(.zoomButton) {
                let railWidth = WorkspaceLayout.collapsedRailWidth(
                    zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
                    leadingInset: close.convert(close.bounds, to: nil).minX
                )
                XCTAssertLessThanOrEqual(
                    RailProjectTile.size + 2 * RailProjectColumn.columnInset,
                    railWidth - 2 * SidebarDialTuning.windowMargin()
                )
            } else {
                XCTFail("no traffic lights on a titled window")
            }
        }
        for key in [
            SidebarDialTuning.railColumnTintOpacityKey, SidebarDialTuning.railColumnInsetKey,
            SidebarDialTuning.railChipCornerRadiusKey, SidebarDialTuning.railChipSizeOffsetKey,
            SidebarDialTuning.railSelectedTileFillKey,
        ] {
            XCTAssertTrue(SidebarDialTuning.allKeys.contains(key), "Reset sidebar must clear \(key)")
            XCTAssertTrue(SidebarDialTuning.railKeys.contains(key), "Reset rail must clear \(key)")
        }
    }

    /// Option D's group geometry (pen.dev `T6FfX`, `p6osQ7`), with Sean's
    /// equal-inset rule (2026-10-09): from a 30pt header at y 0 and four
    /// 48pt rows below it (4pt gaps, last row ends at 238), the expanded
    /// card sits 6 from the tile and the chips on all four sides (2 past the
    /// row frames: 6, less the row's 4pt leading padding); the rail column
    /// sits 4 from them on all four sides, 38 wide. Both at radius 12. The
    /// old bottom edge (last row frame + inset) left 15 below the last chip.
    /// A chip grown past the tile (`chipSizeOffset` +4, a 34pt chip in the
    /// 30pt slot) is the outer element at the sides: the gaps are measured
    /// from its edges, so they stay at the inset.
    func testOptionDGroupCardAndColumnGeometry() {
        withDials {
            XCTAssertEqual(SidebarDialTuning.groupCardInset(), 6)
            XCTAssertEqual(SidebarDialTuning.rowLeadingPadding(), 4)
            XCTAssertEqual(RailProjectColumn.columnInset, 4)
            XCTAssertEqual(RailProjectColumn.chipOverhang, 0)
            XCTAssertEqual(ExpandedGroupCard.horizontalOutset(cardInset: 6, rowLeadingPadding: 4, chipOverhang: 0), 2)
            XCTAssertEqual(RailProjectColumn.columnWidth(anchorCount: 5, inset: RailProjectColumn.columnInset), 38)
            assertGroupCardAndColumnInsetOnAllSides(chipSize: 30)
            // Fills: tile 10%, selected chip 10%, card/column 6%.
            XCTAssertEqual(RailProjectTile.tintOpacity, 0.10)
            XCTAssertEqual(RailProjectTile.cornerRadius, 8)
            XCTAssertEqual(RailProjectColumn.selectedChipTintOpacity, 0.10)
        }
        withDials({ $0.set(4.0, forKey: SidebarDialTuning.railChipSizeOffsetKey) }) {
            XCTAssertEqual(RailProjectColumn.chipSize, 34)
            assertGroupCardAndColumnInsetOnAllSides(chipSize: 34)
        }
        XCTAssertTrue(SidebarDialTuning.sidebarListKeys.contains(SidebarDialTuning.groupCardInsetKey))
        XCTAssertTrue(SidebarDialTuning.railKeys.contains(SidebarDialTuning.railTrayPillSizeKey))
    }

    /// Lays out a header and four rows, places the card and column as their
    /// views do, and measures each gap to the tile's or chip's own edge
    /// (centred in its slot, `midX ± size / 2`), whichever is outermost.
    private func assertGroupCardAndColumnInsetOnAllSides(chipSize: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(RailProjectColumn.chipSize, chipSize, file: file, line: line)
        let cardInset: CGFloat = 6, columnInset = RailProjectColumn.columnInset
        // The anchors as laid out: header, then rows at the row pitch.
        let width: CGFloat = 248, minX: CGFloat = 8, rows = 4
        let rowHeight = SidebarDialTuning.rowHeight(), gap = SidebarDialTuning.rowGap()
        let header = CGRect(x: minX, y: 0, width: width, height: ProjectAccordionHeader.height)
        let lastRow = CGRect(
            x: minX, y: header.maxY + gap + CGFloat(rows - 1) * (rowHeight + gap),
            width: width, height: rowHeight
        )
        let union = header.union(lastRow)
        XCTAssertEqual(union.maxY, 238, file: file, line: line)
        let anchorCount = 1 + rows
        // The visual marks: the tile centred in the header, the chip in the row.
        let tileSize = RailProjectTile.size
        let tileTop = header.midY - tileSize / 2
        let chipBottom = lastRow.midY + chipSize / 2

        // Vertical: above the tile, below the last chip.
        for inset in [cardInset, columnInset] {
            let extent = RailProjectColumn.verticalExtent(union: union, anchorCount: anchorCount, inset: inset)
            XCTAssertEqual(tileTop - extent.lowerBound, inset, "top, inset \(inset), chip \(chipSize)", file: file, line: line)
            XCTAssertEqual(extent.upperBound - chipBottom, inset, "bottom, inset \(inset), chip \(chipSize)", file: file, line: line)
        }

        // Expanded card: tile and chip centred in the leading glyph slot,
        // after the row's leading padding; the trailing side mirrors it.
        let lead = SidebarDialTuning.rowLeadingPadding()
        let slotWidth = SidebarListRowChrome<Text, Text>.glyphSlotWidth
        XCTAssertEqual(slotWidth, tileSize, file: file, line: line)
        let slotMidX = minX + lead + slotWidth / 2
        let mirroredSlotMidX = union.maxX - lead - slotWidth / 2
        let markLeading = min(slotMidX - tileSize / 2, slotMidX - chipSize / 2)
        let markTrailing = max(mirroredSlotMidX + tileSize / 2, mirroredSlotMidX + chipSize / 2)
        let outset = ExpandedGroupCard.horizontalOutset(
            cardInset: cardInset, rowLeadingPadding: lead,
            chipOverhang: RailProjectColumn.sideOverhang(anchorCount: anchorCount)
        )
        let cardMinX = union.midX - (union.width + outset * 2) / 2
        let cardMaxX = union.midX + (union.width + outset * 2) / 2
        XCTAssertEqual(markLeading - cardMinX, cardInset, "card leading, chip \(chipSize)", file: file, line: line)
        XCTAssertEqual(cardMaxX - markTrailing, cardInset, "card trailing, chip \(chipSize)", file: file, line: line)

        // Rail column: tile, chip and column all centred on the rail.
        let railMidX: CGFloat = 49
        let column = RailProjectColumn.columnWidth(anchorCount: anchorCount, inset: columnInset)
        let columnMinX = railMidX - column / 2, columnMaxX = railMidX + column / 2
        let railMarkLeading = min(railMidX - tileSize / 2, railMidX - chipSize / 2)
        let railMarkTrailing = max(railMidX + tileSize / 2, railMidX + chipSize / 2)
        XCTAssertEqual(railMarkLeading - columnMinX, columnInset, "column leading, chip \(chipSize)", file: file, line: line)
        XCTAssertEqual(columnMaxX - railMarkTrailing, columnInset, "column trailing, chip \(chipSize)", file: file, line: line)

        // A folded selected group: the header alone, no chips, the card
        // round the tile on all four sides.
        let folded = RailProjectColumn.verticalExtent(union: header, anchorCount: 1, inset: cardInset)
        XCTAssertEqual(tileTop - folded.lowerBound, cardInset, file: file, line: line)
        XCTAssertEqual(folded.upperBound - (tileTop + tileSize), cardInset, file: file, line: line)
        let foldedOutset = ExpandedGroupCard.horizontalOutset(
            cardInset: cardInset, rowLeadingPadding: lead,
            chipOverhang: RailProjectColumn.sideOverhang(anchorCount: 1)
        )
        let foldedMinX = header.midX - (header.width + foldedOutset * 2) / 2
        XCTAssertEqual(slotMidX - tileSize / 2 - foldedMinX, cardInset, "folded card leading", file: file, line: line)
        XCTAssertEqual(RailProjectColumn.columnWidth(anchorCount: 1, inset: columnInset), tileSize + 2 * columnInset, file: file, line: line)
    }

    /// The focused panels own disjoint keys, all inside `allKeys` ("Reset
    /// all panels"), and each panel's Reset clears its own keys only.
    func testFocusedPanelsOwnDisjointKeysAndResetOnlyTheirOwn() {
        let rail = Set(SidebarDialTuning.railKeys), list = Set(SidebarDialTuning.sidebarListKeys)
        XCTAssertTrue(rail.isDisjoint(with: list))
        XCTAssertTrue(rail.isSubset(of: SidebarDialTuning.allKeys))
        XCTAssertTrue(list.isSubset(of: SidebarDialTuning.allKeys))
        XCTAssertTrue(list.isSuperset(of: [SidebarDialTuning.rowHeightKey, SidebarDialTuning.trayWidthKey, SidebarDialTuning.contentPaddingLeadingKey]))
        let name = "com.seansmithdesign.ghostties.tests.focused-panel-reset"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        for key in rail.union(list) { d.set(3.0, forKey: key) }
        SidebarDialTuning.reset(keys: SidebarDialTuning.sidebarListKeys, defaults: d)
        for key in list { XCTAssertNil(d.object(forKey: key), key) }
        for key in rail { XCTAssertNotNil(d.object(forKey: key), key) }
    }

    /// Each stored dial moves the value `RailProjectColumn` reports, and the
    /// chip never outgrows its row.
    func testRailColumnDialsDriveTheColumn() {
        withDials({ d in
            d.set(0.12, forKey: SidebarDialTuning.railColumnTintOpacityKey)
            d.set(7.0, forKey: SidebarDialTuning.railColumnInsetKey)
            d.set(5.5, forKey: SidebarDialTuning.railChipCornerRadiusKey)
            d.set(-6.0, forKey: SidebarDialTuning.railChipSizeOffsetKey)
            d.set(0.3, forKey: SidebarDialTuning.railSelectedTileFillKey)
        }) {
            XCTAssertEqual(RailProjectColumn.columnTintOpacity, 0.12)
            XCTAssertEqual(RailProjectColumn.columnInset, 7)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, 5.5)
            XCTAssertEqual(RailProjectColumn.chipSize, 24)
            XCTAssertEqual(RailProjectColumn.selectedTileFill, 0.3)
        }
        withDials({ d in
            d.set(40.0, forKey: SidebarDialTuning.railChipSizeOffsetKey)
            d.set(36.0, forKey: SidebarDialTuning.rowHeightKey)
        }) {
            XCTAssertEqual(RailProjectColumn.chipSize, 36, "the chip is clamped to the row height")
        }
    }

    // MARK: - One view is the Projects tab's layout only

    /// With the dial on One view, the Sessions tab still mounts the Sessions
    /// list; only the Projects tab gets the accordion.
    func testSessionsTabKeepsItsViewWhenDialIsOneView() {
        XCTAssertEqual(SidebarBodyKind.resolve(tab: .sessions, dial: .oneView), .sessionsList)
        XCTAssertEqual(SidebarBodyKind.resolve(tab: .projects, dial: .oneView), .oneViewAccordion)
        XCTAssertEqual(SidebarBodyKind.resolve(tab: .sessions, dial: .tabs), .sessionsList)
        XCTAssertEqual(SidebarBodyKind.resolve(tab: .projects, dial: .tabs), .projectsList)
    }

    /// Rail order and the Cmd+1-9 order follow the Sessions list in the
    /// Sessions tab and One view in the Projects tab.
    func testRailAndShortcutOrderFollowTheTab() {
        let pinned = session("orchestrator", orbit, pinned: true)
        let all = [pinned, session("a1", atlas), session("f1", fieldwork), session("a2", atlas)]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork, orbit], testingSessions: all)
        for s in all { store.updateSessionStatus(id: s.id, status: .running) }

        let sessionsTab = SidebarProjectsLayout.effective(dial: .oneView, tab: .sessions)
        let projectsTab = SidebarProjectsLayout.effective(dial: .oneView, tab: .projects)
        XCTAssertEqual(sessionsTab, .tabs)
        XCTAssertEqual(projectsTab, .oneView)
        XCTAssertEqual(store.railSessions(layout: sessionsTab, pinningAvailable: true).map(\.name), ["orchestrator", "a1", "f1", "a2"])
        XCTAssertEqual(store.railSessions(layout: projectsTab, pinningAvailable: true).map(\.name), ["orchestrator", "a1", "a2", "f1"])
    }

    // MARK: - Collapse state

    func testCollapseStateRoundTripsAndToggles() {
        var raw = ""
        raw = ProjectAccordionState.toggled(raw, atlas.id)
        raw = ProjectAccordionState.toggled(raw, orbit.id)
        XCTAssertEqual(ProjectAccordionState.decode(raw), [atlas.id, orbit.id])
        raw = ProjectAccordionState.toggled(raw, atlas.id)
        XCTAssertEqual(ProjectAccordionState.decode(raw), [orbit.id])
        raw = ProjectAccordionState.expanded(raw, orbit.id)
        XCTAssertEqual(ProjectAccordionState.decode(raw), [])
        XCTAssertEqual(ProjectAccordionState.decode("not-a-uuid,\(atlas.id.uuidString)"), [atlas.id])
    }

    /// The fold persists: a header click writes through the views'
    /// `@AppStorage` declaration (same key, injected store) into the
    /// defaults store, so a relaunch (a fresh read) sees the same folds.
    func testCollapseStatePersistsInDefaults() {
        let d = suite("collapse")
        let folds = AppStorage(wrappedValue: "", ProjectAccordionState.collapsedKey, store: d)
        let group = SidebarProjectGroup.make(active: [session("f", fieldwork)], projects: [fieldwork])[0]
        XCTAssertNil(d.string(forKey: ProjectAccordionState.collapsedKey))

        ProjectAccordionState.headerClicked(group, collapsedRaw: folds.projectedValue) { _ in XCTFail("a project with sessions folds, never selects") }
        XCTAssertEqual(ProjectAccordionState.decode(d.string(forKey: ProjectAccordionState.collapsedKey) ?? ""), [fieldwork.id])

        let fresh = AppStorage(wrappedValue: "", ProjectAccordionState.collapsedKey, store: d)
        XCTAssertEqual(ProjectAccordionState.decode(fresh.wrappedValue), [fieldwork.id])
        // Not a dial: Reset sidebar leaves folds alone.
        SidebarDialTuning.reset(defaults: d)
        XCTAssertNotNil(d.string(forKey: ProjectAccordionState.collapsedKey))
    }

    // MARK: - Monograms

    func testMonogramIsOneLetterUnlessFirstLettersCollide() {
        XCTAssertEqual(ProjectMonogram.monograms(for: ["atlas-api", "fieldwork", "orbit-web"]), ["A", "F", "O"])
        XCTAssertEqual(ProjectMonogram.monograms(for: ["atlas-api", "api", "fieldwork"]), ["AA", "AP", "F"])
        XCTAssertEqual(ProjectMonogram.monograms(for: ["_x", "--"]), ["X", "?"])
    }

    // MARK: - Row subtitle

    func testGroupedRowSubtitleNamesTheStatusNotTheProject() {
        XCTAssertEqual(SessionIndicatorState.processing.statusGlyphKind.groupedRowSubtitle, "working")
        XCTAssertEqual(SessionIndicatorState.needsAttention.statusGlyphKind.groupedRowSubtitle, "needs you")
        XCTAssertEqual(SessionIndicatorState.idle.statusGlyphKind.groupedRowSubtitle, "done")
        XCTAssertEqual(SessionIndicatorState.inactive.statusGlyphKind.groupedRowSubtitle, "stopped")
    }

    // MARK: - Rendered list

    /// One view renders a header per project and folds rows away; Tabs
    /// renders neither header. Measured as the list's laid-out height.
    func testOneViewRendersHeadersAndCollapseRemovesRows() throws {
        let sessions = [session("a", atlas), session("b", atlas), session("c", fieldwork)]
        let store = WorkspaceStore(testingProjects: [atlas, fieldwork], testingSessions: sessions)
        for s in sessions { store.updateSessionStatus(id: s.id, status: .running) }

        // Each measurement binds its own private dial suite (`withDials`),
        // so no other test reads or clears the layout it sets.
        func height(_ layout: SidebarProjectsLayout, collapsed: Set<UUID>) -> CGFloat {
            withDials({
                $0.set(layout.rawValue, forKey: SidebarDialTuning.projectsLayoutKey)
                $0.set(ProjectAccordionState.encode(collapsed), forKey: ProjectAccordionState.collapsedKey)
            }) {
                let view = RecentsListView(previewDragState: SessionDragState())
                    .environmentObject(store)
                    .environmentObject(SessionCoordinator())
                    .environmentObject(SidebarWidthModel(width: 260))
                    .frame(width: 260)
                let hosting = NSHostingView(rootView: view)
                hosting.layoutSubtreeIfNeeded()
                return hosting.fittingSize.height
            }
        }

        let row = SidebarDialTuning.rowHeight()
        let gap = SidebarDialTuning.rowGap()
        let tabs = height(.tabs, collapsed: [])
        let open = height(.oneView, collapsed: [])
        let folded = height(.oneView, collapsed: [atlas.id])

        // Two headers, one spacer between groups, each with its row gap.
        XCTAssertEqual(open - tabs, 2 * (ProjectAccordionHeader.height + gap) + SidebarProjectGroupItem.spacerHeight + gap, accuracy: 0.5)
        // Folding atlas-api removes its two rows.
        XCTAssertEqual(open - folded, 2 * (row + gap), accuracy: 0.5)
    }

    // MARK: - Accessibility

    /// The header and its rail tile share one hint (`RailProjectTile` reads
    /// `ProjectAccordionHeader.accessibilityHint`), so an empty project's
    /// tile says what a click does: it selects the project.
    func testEmptyProjectHintSelectsAndOthersFold() {
        XCTAssertEqual(ProjectAccordionHeader.accessibilityHint(isEmpty: true, isCollapsed: false), "Selects this project")
        XCTAssertEqual(ProjectAccordionHeader.accessibilityHint(isEmpty: true, isCollapsed: true), "Selects this project")
        XCTAssertEqual(ProjectAccordionHeader.accessibilityHint(isEmpty: false, isCollapsed: true), "Shows this project's sessions")
        XCTAssertEqual(ProjectAccordionHeader.accessibilityHint(isEmpty: false, isCollapsed: false), "Hides this project's sessions")
    }
}
