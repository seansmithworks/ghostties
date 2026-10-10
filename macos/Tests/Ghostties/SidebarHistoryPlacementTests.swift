import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Where the History row sits when "History in sidebar" is on: anchored
/// just above the tray, in the expanded list and the
/// rail alike, outside the scrolling area. (The "History placement" dial
/// and its `afterActive` option were removed at the vnext lock.)
///
/// Geometry is read off pixels: History is selected (Tint + shimmer, its
/// rim off so only the tint fill marks the card), so its card is the one
/// marked run down the card's leading edge, and the opaque tray is the first
/// marked pixel row below it. Dials are set only in a private suite bound
/// around each render (`withDials`).
@MainActor
final class SidebarHistoryPlacementTests: XCTestCase {
    // MARK: - Section model

    func testOneSectionModelPlacesHistoryForBothViews() {
        let a = AgentSession(name: "a", templateId: UUID(), projectId: UUID(), isPinned: true)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: UUID())
        let sections = SidebarSessionSections(pinned: [a], active: [b], inactive: [], archived: [])
        let bottom = sections.layout(showsHistory: true)
        XCTAssertEqual(bottom.list, [.pinnedRows, .pinnedEnd, .activeRows, .activeEnd])
        XCTAssertEqual(bottom.footer, [.history])
    }

    // MARK: - Harness

    private func railWidth() throws -> CGFloat {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        return WorkspaceLayout.collapsedRailWidth(
            zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
            leadingInset: close.convert(close.bounds, to: nil).minX
        )
    }

    private struct Render {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        let width: CGFloat
        let height: CGFloat
        let store: WorkspaceStore
    }

    /// The sidebar column as the app composes it: the expanded Sessions list
    /// (mirroring `WorkspaceSidebarView`: titlebar band, list, spacer, the
    /// tray's reserved space) or the rail, with the opaque tray overlaid at
    /// the bottom the way the sidebar root hosts it.
    ///
    /// The dials are set in a private suite bound around the render
    /// (`withDials`), so no other test reads or clears them.
    private func render(rail: Bool, sessionCount: Int, height: CGFloat, selectHistory: Bool = true) throws -> Render {
        try withDials({
            // The selected row's rim off: its blur would soften the card's
            // edges; the tint fill alone carries the footprint.
            $0.set(0.0, forKey: SidebarDialTuning.lightGlassKeys.chromaticIntensity)
            // History is off by default since sidebar vnext; these tests
            // measure where it sits when it's on.
            $0.set(true, forKey: SidebarDialTuning.historyInSidebarKey)
        }) {
            try renderOnce(rail: rail, sessionCount: sessionCount, height: height, selectHistory: selectHistory)
        }
    }

    private func renderOnce(rail: Bool, sessionCount: Int, height: CGFloat, selectHistory: Bool) throws -> Render {
        let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
        let sessions = (0..<sessionCount).map { i in
            AgentSession(
                name: "Session \(i)", templateId: AgentTemplate.claudeCode.id, projectId: project.id,
                sortOrder: i, lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true
            )
        }
        let store = WorkspaceStore(
            testingProjects: [project], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        for s in sessions {
            store.updateIndicatorState(id: s.id, state: .inactive)
            store.updateSessionStatus(id: s.id, status: .running)
        }
        let coordinator = SessionCoordinator()
        if selectHistory {
            coordinator.presentHistory()
        } else if let first = sessions.first {
            coordinator.setActiveSessionIdForTesting(first.id)
        }

        let width = rail ? try railWidth() : 260
        let column: AnyView
        if rail {
            column = AnyView(SidebarRailView())
        } else {
            column = AnyView(VStack(spacing: 0) {
                Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)
                RecentsListView()
                Spacer(minLength: 0)
                Color.clear.frame(height: SidebarTray.reservedHeight(isVertical: false))
            })
        }
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        // The list and rail read the sidebar tab from store-less
        // `@AppStorage` (`.standard`, the Dev app's domain); pin it to the
        // Projects tab in a private suite so the saved tab can't swap in the
        // flat Sessions list.
        let tabSuiteName = "com.seansmithdesign.ghostties.tests.sidebar-tab.\(UUID().uuidString)"
        let tabSuite = try XCTUnwrap(UserDefaults(suiteName: tabSuiteName))
        defer { tabSuite.removePersistentDomain(forName: tabSuiteName) }
        tabSuite.set(SidebarTab.projects.rawValue, forKey: "ghostties.sidebarTab")
        let root = column
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                SidebarTray(isVertical: rail, toggleLabel: rail ? "Expand Sidebar" : "Collapse Sidebar", forceOpaque: true)
            }
            .environment(\.sidebarTrailingGutter, 0)
            .environmentObject(store)
            .environmentObject(coordinator)
            .environmentObject(SidebarWidthModel(width: width))
            .defaultAppStorage(tabSuite)
            .background(Color(nsColor: chrome))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return Render(rep: rep, scale: CGFloat(rep.pixelsWide) / width, width: width, height: height, store: store)
    }

    /// Off the chrome either way: the selected tint darkens it, the opaque
    /// tray lifts it.
    private func isMarked(_ r: Render, px x: Int, _ y: Int) -> Bool {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB),
              let c = r.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        let delta = (c.redComponent + c.greenComponent + c.blueComponent)
            - (chrome.redComponent + chrome.greenComponent + chrome.blueComponent)
        return abs(delta) > 0.06
    }

    /// Lighter than the chrome: the opaque tray's white fill.
    private func isLifted(_ r: Render, px x: Int, _ y: Int) -> Bool {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB),
              let c = r.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return (c.redComponent + c.greenComponent + c.blueComponent)
            - (chrome.redComponent + chrome.greenComponent + chrome.blueComponent) > 0.06
    }

    /// Runs of marked pixels down one column, in points.
    private func runsDown(_ r: Render, atX x: CGFloat) -> [ClosedRange<CGFloat>] {
        let px = Int(x * r.scale)
        var runs: [(Int, Int)] = []
        for y in 0..<r.rep.pixelsHigh where isMarked(r, px: px, y) {
            if let last = runs.last, y - last.1 <= 1 { runs[runs.count - 1].1 = y } else { runs.append((y, y)) }
        }
        return runs.map { CGFloat($0.0) / r.scale...CGFloat($0.1 + 1) / r.scale }
    }

    /// The x of a selected card's leading edge plus its corner radius: past
    /// the corner curve, so the card's full height is marked there, and
    /// still clear of the title ink.
    private func cardProbeX(rail: Bool) -> CGFloat {
        SidebarDialTuning.windowMargin() + (rail ? 0 : SidebarDialTuning.contentPaddingLeading())
            + WorkspaceLayout.sidebarRowCornerRadiusResting
    }

    /// The selected card: the marked run one row tall, above the tray (a
    /// tray capsule can be one row tall too).
    private func selectedCard(_ r: Render, rail: Bool) throws -> ClosedRange<CGFloat> {
        let rowHeight = SidebarDialTuning.rowHeight()
        let trayHeight = SidebarTray.reservedHeight(isVertical: rail) - (rail ? 0 : SidebarDialTuning.listToTrayGap())
        let cards = runsDown(r, atX: cardProbeX(rail: rail)).filter {
            abs(($0.upperBound - $0.lowerBound) - rowHeight) <= 1.5 && $0.upperBound <= r.height - trayHeight
        }
        return try XCTUnwrap(cards.first, "no selected card found (rail: \(rail))")
    }

    /// The tray's top edge: the first pixel row below `y` lifted off the
    /// chrome by the opaque tray. Only lighter pixels count: the tray's
    /// shadow darkens the chrome above the pill, and it is not the tray.
    private func trayTop(_ r: Render, below y: CGFloat) throws -> CGFloat {
        for py in Int(y * r.scale) + 1..<r.rep.pixelsHigh {
            for px in 0..<r.rep.pixelsWide where isLifted(r, px: px, py) {
                return CGFloat(py) / r.scale
            }
        }
        XCTFail("no tray found below \(y)")
        return .nan
    }

    /// Where History's card top would be directly after the active rows:
    /// the titlebar band, the column's top padding, `n` rows, the
    /// zero-height end marker, with one row gap between
    /// each.
    private func directlyAfterActiveTop(store: WorkspaceStore, rows n: Int) -> CGFloat {
        store.toolbarRowTopAnchorConstant * 2 + SidebarDialTuning.contentPaddingTop()
            + CGFloat(n) * SidebarDialTuning.rowHeight()
            + CGFloat(n + 1) * SidebarDialTuning.rowGap()
    }

    // MARK: - Bottom

    func testBottomHistorySitsAFixedGapAboveTheTrayExpandedAndRail() throws {
        let gap = SidebarSessionSections.historyToTrayGap()
        XCTAssertEqual(gap, SidebarDialTuning.rowGap() + SidebarDialTuning.listToTrayGap())
        for rail in [false, true] {
            let r = try render(rail: rail, sessionCount: 2, height: 600)
            let card = try selectedCard(r, rail: rail)
            let tray = try trayTop(r, below: card.upperBound)
            XCTAssertEqual(tray - card.upperBound, gap, accuracy: 1.0, "History sits the fixed gap above the tray (rail: \(rail))")
            XCTAssertGreaterThan(card.lowerBound - directlyAfterActiveTop(store: r.store, rows: 2), 100, "History left the active rows (rail: \(rail))")
        }
    }

    /// Long enough to scroll: History stays pinned above the tray instead of
    /// scrolling away below the fold.
    func testBottomHistoryStaysVisibleWhenTheListScrolls() throws {
        let r = try render(rail: false, sessionCount: 20, height: 500)
        let card = try selectedCard(r, rail: false)
        let tray = try trayTop(r, below: card.upperBound)
        XCTAssertEqual(tray - card.upperBound, SidebarSessionSections.historyToTrayGap(), accuracy: 1.0)
    }

    // MARK: - Morph alignment

    /// The first session's row sits at the same y in the expanded list and
    /// the rail. In one view both mark it with a tile-sized chip centred in
    /// the row (option D): in the expanded list behind the leading glyph
    /// slot, inside the group card; in the rail inside its project column
    /// (`RailProjectColumn`). The two chips' centres must match.
    func testFirstRowSitsAtTheSameYInExpandedAndRail() throws {
        let e = try selectedChip(try render(rail: false, sessionCount: 3, height: 600, selectHistory: false), rail: false)
        let r = try selectedChip(try render(rail: true, sessionCount: 3, height: 600, selectHistory: false), rail: true)
        XCTAssertEqual((e.lowerBound + e.upperBound) / 2, (r.lowerBound + r.upperBound) / 2, accuracy: 0.6, "first row centre")
    }

    /// The x of the selected chip's centre: the rail's centre, or, in the
    /// expanded list, the leading glyph slot's (`SidebarListRowChrome`).
    private func chipCentreX(_ r: Render, rail: Bool) -> CGFloat {
        rail ? r.width / 2
            : SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
                + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
    }

    /// The selected chip: the run, down a line 4pt inside the chip's
    /// leading edge (clear of the glyph), whose summed-RGB drop below the
    /// chrome is the chip over the group card or column, not the card or
    /// column alone. Both are black tints, so a tint of alpha `a` drops the
    /// sum by `a * chromeSum`: the card/column (6%, ~0.165) sits below the
    /// window and the chip over it (1 - 0.94 * 0.90 = 15.4%, ~0.424) inside
    /// it, with the lower bound midway between them; ink is far darker. The
    /// run must also be chip-sized (not the card's extent). The chip's
    /// corner trims the run's ends equally, so its centre is the chip's.
    private func selectedChip(_ r: Render, rail: Bool) throws -> ClosedRange<CGFloat> {
        let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
        let base = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        let cardAlpha = RailProjectColumn.columnTintOpacity
        let chipAlpha = RailProjectColumn.selectedChipTintOpacity
        let cardDrop = base * cardAlpha
        let chipOverCardDrop = base * (1 - (1 - cardAlpha) * (1 - chipAlpha))
        let lowerBound = (cardDrop + chipOverCardDrop) / 2
        let upperBound = chipOverCardDrop + (chipOverCardDrop - lowerBound)
        let px = Int((chipCentreX(r, rail: rail) - RailProjectColumn.chipSize / 2 + 4) * r.scale)
        var runs: [(Int, Int)] = []
        for y in 0..<r.rep.pixelsHigh {
            guard let c = r.rep.colorAt(x: px, y: y)?.usingColorSpace(.sRGB) else { continue }
            let delta = base - (c.redComponent + c.greenComponent + c.blueComponent)
            guard delta > lowerBound && delta < upperBound else { continue }
            if let last = runs.last, y - last.1 <= 1 { runs[runs.count - 1].1 = y } else { runs.append((y, y)) }
        }
        let chips = runs.map { CGFloat($0.0) / r.scale...CGFloat($0.1 + 1) / r.scale }
            .filter { abs(($0.upperBound - $0.lowerBound) - RailProjectColumn.chipSize) <= 4 }
        return try XCTUnwrap(chips.first, "no selected chip found (rail: \(rail))")
    }
}
