import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// The "History placement" dial (`SidebarDialTuning.historyPlacement`):
/// `afterActive` keeps the History row directly after the Active rows;
/// `bottom` anchors it (with its hairline) just above the tray, in the
/// expanded list and the rail alike, and keeps it out of the scrolling area.
///
/// Geometry is read off pixels: History is selected (flat style, since
/// `cacheDisplay` can't capture glass), so its card is the one lifted run
/// down the card's leading edge, and the opaque tray is the first lifted
/// pixel row below it. Dials are set only in the isolated
/// `SidebarDialTuning.store` and cleared in `tearDown`.
@MainActor
final class SidebarHistoryPlacementTests: XCTestCase {
    private typealias Placement = SidebarSessionSections.HistoryPlacement

    override func setUp() {
        super.setUp()
        XCTAssertTrue(SidebarDialTuning.store !== UserDefaults.standard, "dial store must be the isolated suite")
        SidebarDialTuning.store.set(TrayGlassStyle.SelectedStyle.flat.rawValue, forKey: SidebarDialTuning.selectedStyleKey)
    }

    override func tearDown() {
        SidebarDialTuning.store.removeObject(forKey: SidebarDialTuning.selectedStyleKey)
        SidebarDialTuning.store.removeObject(forKey: SidebarDialTuning.historyPlacementKey)
        super.tearDown()
    }

    // MARK: - Dial

    func testPlacementDialDefaultsToBottom() {
        let name = "com.seansmithdesign.ghostties.tests.history-placement"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(SidebarDialTuning.historyPlacementKey, "ghostties.sidebarDial.historyPlacement")
        XCTAssertEqual(SidebarDialTuning.historyPlacement(defaults: d), .bottom)
    }

    /// A launch argument (`-ghostties.sidebarDial.historyPlacement afterActive`)
    /// arrives as a string, the same shape a stored string has.
    func testPlacementDialParsesStringsAndFallsBackToTheDefault() {
        let store = SidebarDialTuning.store
        store.set("afterActive", forKey: SidebarDialTuning.historyPlacementKey)
        XCTAssertEqual(SidebarDialTuning.historyPlacement(), .afterActive)
        store.set("bottom", forKey: SidebarDialTuning.historyPlacementKey)
        XCTAssertEqual(SidebarDialTuning.historyPlacement(), .bottom)
        store.set("nonsense", forKey: SidebarDialTuning.historyPlacementKey)
        XCTAssertEqual(SidebarDialTuning.historyPlacement(), .bottom)
        XCTAssertEqual(Placement.allCases.map(\.rawValue), ["afterActive", "bottom"])
    }

    /// On a private suite: a reset of the shared dial suite would clear the
    /// dials of tests running in parallel processes.
    func testResetClearsThePlacementDial() {
        let name = "com.seansmithdesign.ghostties.tests.history-placement-reset"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.historyPlacementKey))
        d.set("afterActive", forKey: SidebarDialTuning.historyPlacementKey)
        SidebarDialTuning.reset(defaults: d)
        XCTAssertNil(d.object(forKey: SidebarDialTuning.historyPlacementKey))
        XCTAssertEqual(SidebarDialTuning.historyPlacement(defaults: d), .bottom)
    }

    // MARK: - Section model

    func testOneSectionModelPlacesHistoryForBothViews() {
        let a = AgentSession(name: "a", templateId: UUID(), projectId: UUID(), isPinned: true)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: UUID())
        let sections = SidebarSessionSections(pinned: [a], active: [b], inactive: [], archived: [])
        let after = sections.layout(historyPlacement: .afterActive)
        XCTAssertEqual(after.list, [.pinnedRows, .pinnedEnd, .pinnedHairline, .activeRows, .activeEnd, .historyHairline, .history])
        XCTAssertEqual(after.footer, [])
        let bottom = sections.layout(historyPlacement: .bottom)
        XCTAssertEqual(bottom.list, [.pinnedRows, .pinnedEnd, .pinnedHairline, .activeRows, .activeEnd])
        XCTAssertEqual(bottom.footer, [.historyHairline, .history])
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
    /// The dial suite is one on-disk domain shared by every parallel test
    /// process, and a process starting up clears it
    /// (`GhosttiesTestIsolation`), so a dial can vanish mid-render. The
    /// render is retried until the dials it set held from start to finish.
    private func render(rail: Bool, placement: Placement, sessionCount: Int, height: CGFloat, selectHistory: Bool = true) throws -> Render {
        for _ in 0..<5 {
            let store = SidebarDialTuning.store
            store.set(TrayGlassStyle.SelectedStyle.flat.rawValue, forKey: SidebarDialTuning.selectedStyleKey)
            store.set(placement.rawValue, forKey: SidebarDialTuning.historyPlacementKey)
            let r = try renderOnce(rail: rail, sessionCount: sessionCount, height: height, selectHistory: selectHistory)
            if SidebarDialTuning.historyPlacement() == placement && SidebarDialTuning.selectedStyle() == .flat { return r }
        }
        struct DialsKeptChanging: Error {}
        throw DialsKeptChanging()
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
        let root = column
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                SidebarTray(isVertical: rail, toggleLabel: rail ? "Expand Sidebar" : "Collapse Sidebar", forceOpaque: true)
            }
            .environment(\.sidebarTrailingGutter, 0)
            .environmentObject(store)
            .environmentObject(coordinator)
            .environmentObject(SidebarWidthModel(width: width))
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

    private func isLifted(_ r: Render, px x: Int, _ y: Int) -> Bool {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB),
              let c = r.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        let lift = (c.redComponent + c.greenComponent + c.blueComponent)
            - (chrome.redComponent + chrome.greenComponent + chrome.blueComponent)
        return lift > 0.06
    }

    /// Runs of lifted pixels down one column, in points.
    private func runsDown(_ r: Render, atX x: CGFloat) -> [ClosedRange<CGFloat>] {
        let px = Int(x * r.scale)
        var runs: [(Int, Int)] = []
        for y in 0..<r.rep.pixelsHigh where isLifted(r, px: px, y) {
            if let last = runs.last, y - last.1 <= 1 { runs[runs.count - 1].1 = y } else { runs.append((y, y)) }
        }
        return runs.map { CGFloat($0.0) / r.scale...CGFloat($0.1 + 1) / r.scale }
    }

    /// The x of a selected card's leading edge plus 3pt (clear of the
    /// title ink; the corner curve costs under 1pt there).
    private func cardProbeX(rail: Bool) -> CGFloat {
        SidebarDialTuning.windowMargin() + (rail ? 0 : SidebarDialTuning.contentPaddingLeading()) + 3
    }

    /// The selected card: the lifted run one row tall, above the tray (a
    /// tray capsule can be one row tall too).
    private func selectedCard(_ r: Render, rail: Bool) throws -> ClosedRange<CGFloat> {
        let rowHeight = SidebarDialTuning.rowHeight()
        let trayHeight = SidebarTray.reservedHeight(isVertical: rail) - (rail ? 0 : SidebarDialTuning.listToTrayGap())
        let cards = runsDown(r, atX: cardProbeX(rail: rail)).filter {
            abs(($0.upperBound - $0.lowerBound) - rowHeight) <= 1.5 && $0.upperBound <= r.height - trayHeight
        }
        return try XCTUnwrap(cards.first, "no selected card found (rail: \(rail))")
    }

    /// The tray's top edge: the first pixel row below `y` with any lifted pixel.
    private func trayTop(_ r: Render, below y: CGFloat) throws -> CGFloat {
        for py in Int(y * r.scale) + 1..<r.rep.pixelsHigh {
            for px in 0..<r.rep.pixelsWide where isLifted(r, px: px, py) {
                return CGFloat(py) / r.scale
            }
        }
        XCTFail("no tray found below \(y)")
        return .nan
    }

    /// History's card top in `afterActive`: the titlebar band, the column's
    /// top padding, `n` rows, the zero-height end marker, the hairline slot,
    /// with one row gap between each.
    private func afterActiveHistoryTop(store: WorkspaceStore, rows n: Int) -> CGFloat {
        store.toolbarRowTopAnchorConstant * 2 + SidebarDialTuning.contentPaddingTop()
            + CGFloat(n) * SidebarDialTuning.rowHeight()
            + CGFloat(n + 2) * SidebarDialTuning.rowGap()
            + WorkspaceLayout.sessionSectionHairlineSlotHeight
    }

    // MARK: - Bottom

    func testBottomHistorySitsAFixedGapAboveTheTrayExpandedAndRail() throws {
        let gap = SidebarSessionSections.historyToTrayGap()
        XCTAssertEqual(gap, SidebarDialTuning.rowGap() + SidebarDialTuning.listToTrayGap())
        for rail in [false, true] {
            let r = try render(rail: rail, placement: .bottom, sessionCount: 2, height: 600)
            let card = try selectedCard(r, rail: rail)
            let tray = try trayTop(r, below: card.upperBound)
            XCTAssertEqual(tray - card.upperBound, gap, accuracy: 1.0, "History sits the fixed gap above the tray (rail: \(rail))")
            XCTAssertGreaterThan(card.lowerBound - afterActiveHistoryTop(store: r.store, rows: 2), 100, "History left the active rows (rail: \(rail))")
        }
    }

    /// Long enough to scroll: History stays pinned above the tray instead of
    /// scrolling away below the fold.
    func testBottomHistoryStaysVisibleWhenTheListScrolls() throws {
        let r = try render(rail: false, placement: .bottom, sessionCount: 20, height: 500)
        let card = try selectedCard(r, rail: false)
        let tray = try trayTop(r, below: card.upperBound)
        XCTAssertEqual(tray - card.upperBound, SidebarSessionSections.historyToTrayGap(), accuracy: 1.0)
    }

    // MARK: - After active

    func testAfterActiveHistoryFollowsTheActiveRowsExpandedAndRail() throws {
        for rail in [false, true] {
            let r = try render(rail: rail, placement: .afterActive, sessionCount: 2, height: 600)
            let card = try selectedCard(r, rail: rail)
            XCTAssertEqual(card.lowerBound, afterActiveHistoryTop(store: r.store, rows: 2), accuracy: 1.0, "History follows Active (rail: \(rail))")
        }
    }

    // MARK: - Morph alignment

    /// The first session's card sits at the same y in the expanded list and
    /// the rail, in either placement.
    func testFirstRowSitsAtTheSameYInExpandedAndRailInBothPlacements() throws {
        for placement in Placement.allCases {
            let e = try selectedCard(try render(rail: false, placement: placement, sessionCount: 3, height: 600, selectHistory: false), rail: false)
            let r = try selectedCard(try render(rail: true, placement: placement, sessionCount: 3, height: 600, selectHistory: false), rail: true)
            XCTAssertEqual(e.lowerBound, r.lowerBound, accuracy: 0.6, "first row top (\(placement))")
            XCTAssertEqual(e.upperBound, r.upperBound, accuracy: 0.6, "first row bottom (\(placement))")
        }
    }
}
