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

        // Unpinned projects read by name (`ProjectListOrder`).
        XCTAssertEqual(groups.map(\.name), ["atlas-api", "fieldwork", "orbit-web", "quiet"])
        XCTAssertEqual(groups.map { $0.sessions.map(\.name) }, [
            ["Claude Code 4", "auth refactor"],
            ["docs pass", "build fix"],
            ["landing hero"],
            [],
        ])
        XCTAssertEqual(groups.map(\.isEmpty), [false, false, false, true])
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
        XCTAssertEqual(shape, ["atlas-api", "a", "-", "quiet"])
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
    /// `p6osQ7`/`ZiGlb`: inset 4, chip radius 8 = the tile's, full ink),
    /// with the rail's tile and chip at 40 (Sean, 2026-10-10; the sidebar's
    /// stay 30). The column tint is beta.26's sidebar contrast fill: 4% in
    /// dark, a 45% white lift in light (was option D's 6%).
    func testRailColumnDialDefaultsAreOptionD() {
        withDials {
            XCTAssertEqual(RailProjectColumn.columnInset, 4)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, 8)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, RailProjectTile.cornerRadius)
            XCTAssertEqual(RailProjectColumn.columnCornerRadius, 12)
            // One tile and chip size in both states (rail stays put).
            XCTAssertEqual(RailProjectTile.size, 40)
            XCTAssertEqual(RailProjectColumn.chipSize(.rail), 40)
            XCTAssertEqual(RailProjectColumn.chipSize(.sidebar), 40)
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
            SidebarDialTuning.railChipCornerRadiusKey, SidebarDialTuning.railThreadTileSizeKey,
            SidebarDialTuning.railSelectedTileFillKey,
        ] {
            XCTAssertTrue(SidebarDialTuning.allKeys.contains(key), "Reset sidebar must clear \(key)")
            XCTAssertTrue(SidebarDialTuning.railKeys.contains(key), "Reset rail must clear \(key)")
        }
    }

    /// Option D's group geometry with the rail staying put (rail stays put,
    /// 2026-10-22): the card is the rail column in both states, hugging the
    /// tile column only. From a 40pt header at y 0 and four 48pt rows below
    /// it (4pt gaps), the column sits 4 from the tile and chips on all four
    /// sides, 48 wide round the 40pt tile, at radius 12; a folded card sits
    /// 4 round its tile. A chip grown past the tile ("Thread tile size" 34
    /// round a 30pt tile) is the outer element at the sides: the gaps are
    /// measured from its edges, so they stay at the inset.
    func testOptionDGroupCardAndColumnGeometry() {
        withDials {
            XCTAssertEqual(SidebarDialTuning.rowLeadingPadding(), 4)
            XCTAssertEqual(RailProjectColumn.columnInset, 4)
            XCTAssertEqual(RailProjectColumn.chipOverhang(.sidebar), 0)
            XCTAssertEqual(RailProjectColumn.chipOverhang(.rail), 0)
            XCTAssertEqual(RailProjectColumn.columnWidth(anchorCount: 5, inset: RailProjectColumn.columnInset), 48)
            assertGroupCardAndColumnInsetOnAllSides(railChipSize: 40)
            // Fills: tile 10%, selected chip 10%, card/column 6%.
            XCTAssertEqual(RailProjectTile.tintOpacity, 0.10)
            XCTAssertEqual(RailProjectTile.cornerRadius, 8)
            XCTAssertEqual(RailProjectColumn.selectedChipTintOpacity, 0.10)
        }
        withDials({ d in
            d.set(34.0, forKey: SidebarDialTuning.sidebarThreadTileSizeKey)
            d.set(34.0, forKey: SidebarDialTuning.railThreadTileSizeKey)
            d.set(30.0, forKey: SidebarDialTuning.railProjectTileSizeKey)
        }) {
            assertGroupCardAndColumnInsetOnAllSides(railChipSize: 34)
        }
        XCTAssertTrue(SidebarDialTuning.retiredKeys.contains(SidebarDialTuning.retiredGroupCardInsetKey))
        XCTAssertTrue(SidebarDialTuning.railKeys.contains(SidebarDialTuning.railTrayPillSizeKey))
    }

    /// Lays out a header and four rows, places the column as its view does,
    /// and measures each gap to the tile's or chip's own edge (centred on the
    /// rail's tile column, `midX ± size / 2`), whichever is outermost.
    private func assertGroupCardAndColumnInsetOnAllSides(railChipSize: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(RailProjectColumn.chipSize(.rail), railChipSize, file: file, line: line)
        let columnInset = RailProjectColumn.columnInset
        // The anchors as laid out: header, then rows at the row pitch.
        let width: CGFloat = 232, minX: CGFloat = 24, rows = 4
        let rowHeight = SidebarDialTuning.rowHeight(), gap = SidebarDialTuning.rowGap()
        let header = CGRect(x: minX, y: 0, width: width, height: ProjectAccordionHeader.height)
        let lastRow = CGRect(x: minX, y: header.maxY + gap + CGFloat(rows - 1) * (rowHeight + gap), width: width, height: rowHeight)
        let union = header.union(lastRow)
        // The 40pt header (keyframe spec D1) and four rows.
        XCTAssertEqual(union.maxY, 248, file: file, line: line)
        let anchorCount = 1 + rows
        let tileSize = RailProjectTile.size

        // Vertical: above the tile, below the last chip.
        let extent = RailProjectColumn.verticalExtent(union: union, anchorCount: anchorCount, inset: columnInset)
        XCTAssertEqual(header.midY - tileSize / 2 - extent.lowerBound, columnInset, "top, chip \(railChipSize)", file: file, line: line)
        XCTAssertEqual(extent.upperBound - (lastRow.midY + railChipSize / 2), columnInset, "bottom, chip \(railChipSize)", file: file, line: line)

        // The row's glyph slot is the tile's width, on the tile column.
        XCTAssertEqual(SidebarListRowChrome<Text, Text>.glyphSlotWidth, tileSize, file: file, line: line)

        // Column: tile, chip and column all centred on the rail.
        let railMidX: CGFloat = 48
        let column = RailProjectColumn.columnWidth(anchorCount: anchorCount, inset: columnInset)
        let columnMinX = railMidX - column / 2, columnMaxX = railMidX + column / 2
        let railMarkLeading = min(railMidX - tileSize / 2, railMidX - railChipSize / 2)
        let railMarkTrailing = max(railMidX + tileSize / 2, railMidX + railChipSize / 2)
        XCTAssertEqual(railMarkLeading - columnMinX, columnInset, "column leading, chip \(railChipSize)", file: file, line: line)
        XCTAssertEqual(columnMaxX - railMarkTrailing, columnInset, "column trailing, chip \(railChipSize)", file: file, line: line)

        // A folded selected group: the header alone, no chips, the column
        // round the tile on all four sides.
        let tileTop = header.midY - tileSize / 2
        let folded = RailProjectColumn.verticalExtent(union: header, anchorCount: 1, inset: columnInset)
        XCTAssertEqual(tileTop - folded.lowerBound, columnInset, file: file, line: line)
        XCTAssertEqual(folded.upperBound - (tileTop + tileSize), columnInset, file: file, line: line)
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
            d.set(24.0, forKey: SidebarDialTuning.railThreadTileSizeKey)
            d.set(0.3, forKey: SidebarDialTuning.railSelectedTileFillKey)
        }) {
            XCTAssertEqual(RailProjectColumn.columnTintOpacity, 0.12)
            XCTAssertEqual(RailProjectColumn.columnInset, 7)
            XCTAssertEqual(RailProjectColumn.chipCornerRadius, 5.5)
            XCTAssertEqual(RailProjectColumn.chipSize(.rail), 24)
            XCTAssertEqual(RailProjectColumn.selectedTileFill, 0.3)
        }
        withDials({ d in
            d.set(70.0, forKey: SidebarDialTuning.railThreadTileSizeKey)
            d.set(36.0, forKey: SidebarDialTuning.rowHeightKey)
        }) {
            XCTAssertEqual(RailProjectColumn.chipSize(.rail), 36, "the chip is clamped to the row height")
        }
    }

    // MARK: - Tile dials (project / thread, per context)

    /// Unset, the tile is 40pt in both states (rail stays put) with a 13pt
    /// monogram (11 for two letters); chips are 40pt with a 16pt glyph in
    /// both. Each dial, written alone, moves exactly its own value and
    /// nothing in the other context or the other tile.
    func testTileDialsDefaultToTodayAndMoveIndependently() {
        let probes: [(key: String, read: () -> CGFloat)] = [
            (SidebarDialTuning.sidebarProjectTileTextKey, { RailProjectTile.textSize(.sidebar, letters: 1) }),
            (SidebarDialTuning.sidebarThreadTileSizeKey, { RailProjectColumn.chipSize(.sidebar) }),
            (SidebarDialTuning.sidebarThreadTileIconKey, { RailProjectColumn.chipGlyphSize(.sidebar) }),
            (SidebarDialTuning.railProjectTileSizeKey, { RailProjectTile.size }),
            (SidebarDialTuning.railProjectTileTextKey, { RailProjectTile.textSize(.rail, letters: 1) }),
            (SidebarDialTuning.railThreadTileSizeKey, { RailProjectColumn.chipSize(.rail) }),
            (SidebarDialTuning.railThreadTileIconKey, { RailProjectColumn.chipGlyphSize(.rail) }),
        ]
        let defaults: [CGFloat] = withDials {
            XCTAssertEqual(RailProjectTile.textSize(.sidebar, letters: 2), 11)
            XCTAssertEqual(RailProjectTile.textSize(.rail, letters: 2), 11)
            XCTAssertEqual(SidebarListRowChrome<Text, Text>.glyphSlotWidth, 40)
            XCTAssertEqual(RailProjectColumn.columnWidth(anchorCount: 5, inset: RailProjectColumn.columnInset), 48)
            return probes.map { $0.read() }
        }
        XCTAssertEqual(defaults, [13, 40, 16, 40, 13, 40, 16])

        for (index, probe) in probes.enumerated() {
            let written: CGFloat = 23
            withDials({ $0.set(Double(written), forKey: probe.key) }) {
                for (other, otherProbe) in probes.enumerated() {
                    XCTAssertEqual(otherProbe.read(), other == index ? written : defaults[other], "writing \(probe.key) read at \(otherProbe.key)")
                }
            }
            XCTAssertTrue(SidebarDialTuning.allKeys.contains(probe.key), probe.key)
            let ownPanel = probe.key.contains(".railColumn.") ? SidebarDialTuning.railKeys : SidebarDialTuning.sidebarListKeys
            XCTAssertTrue(ownPanel.contains(probe.key), "its panel's Reset must clear \(probe.key)")
        }

        // The one project tile drives the column and the row slot alike.
        withDials({ $0.set(36.0, forKey: SidebarDialTuning.railProjectTileSizeKey) }) {
            XCTAssertEqual(RailProjectColumn.columnWidth(anchorCount: 1, inset: RailProjectColumn.columnInset), 44)
            XCTAssertEqual(SidebarListRowChrome<Text, Text>.glyphSlotWidth, 36)
        }
        XCTAssertTrue(SidebarDialTuning.retiredKeys.contains(SidebarDialTuning.retiredSidebarProjectTileSizeKey))
        XCTAssertTrue(SidebarDialTuning.retiredKeys.contains(SidebarDialTuning.retiredRailChipSizeOffsetKey))
    }

    /// A project tile past the 40pt header grows the header that hosts it
    /// (in both states, one header), so the column, measured from the
    /// header's frame, still encloses the tile with its inset on every side.
    /// Unset, the header is 40 (keyframe spec D1).
    func testABigProjectTileGrowsItsHeaderAndStaysInsideTheCard() {
        withDials {
            XCTAssertEqual(ProjectAccordionHeader.height, 40)
        }
        withDials({ $0.set(44.0, forKey: SidebarDialTuning.railProjectTileSizeKey) }) {
            XCTAssertEqual(ProjectAccordionHeader.height, 44)
            let tile = RailProjectTile.size
            XCTAssertEqual(tile, 44)

            let minX: CGFloat = 24, width: CGFloat = 232
            let rowHeight = SidebarDialTuning.rowHeight(), gap = SidebarDialTuning.rowGap()
            let header = CGRect(x: minX, y: 0, width: width, height: ProjectAccordionHeader.height)
            let lastRow = CGRect(x: minX, y: header.maxY + gap + 3 * (rowHeight + gap), width: width, height: rowHeight)
            let lead = SidebarDialTuning.rowLeadingPadding()
            // The tile as laid out: centred in its header and its slot.
            let tileMidX = minX + lead + SidebarListRowChrome<Text, Text>.glyphSlotWidth / 2
            let tileFrame = CGRect(x: tileMidX - tile / 2, y: header.midY - tile / 2, width: tile, height: tile)
            let inset = RailProjectColumn.columnInset

            for (union, anchorCount) in [(header.union(lastRow), 5), (header, 1)] {
                let extent = RailProjectColumn.verticalExtent(union: union, anchorCount: anchorCount, inset: inset)
                let cardWidth = RailProjectColumn.columnWidth(anchorCount: anchorCount, inset: inset)
                let card = CGRect(x: tileMidX - cardWidth / 2, y: extent.lowerBound, width: cardWidth, height: extent.upperBound - extent.lowerBound)
                XCTAssertTrue(card.contains(tileFrame), "\(anchorCount) anchors: card \(card) must enclose tile \(tileFrame)")
                XCTAssertEqual(tileFrame.minY - card.minY, inset, "\(anchorCount) anchors: inset above the tile")
                XCTAssertEqual(tileFrame.minX - card.minX, inset, "\(anchorCount) anchors: inset beside the tile")
            }
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
