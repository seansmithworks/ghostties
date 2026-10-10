import XCTest
import SwiftUI
import GhosttiesCore
@testable import Ghostty

/// Option D's group card (expanded list) and project column (rail), read off
/// rendered pixels. `SidebarProjectsLayoutTests.testOptionDGroupCardAndColumnGeometry`
/// computes the same gaps from the helpers (`RailProjectColumn.verticalExtent`,
/// `columnWidth`, `ExpandedGroupCard.horizontalOutset`); it cannot see a view
/// that stops calling them or pads differently. This renders the real views
/// and measures the card's and column's edges against the tile's and the
/// selected chip's.
///
/// The last of three sessions is selected, so the chip sits on the group's
/// last row: the card's top is measured to the tile (ink-filled, selected
/// project), its bottom to that chip, its leading side to the chip. Colours:
/// the 6% card/column and the 10% chip over it are black tints on the chrome
/// (summed-RGB drop ~0.165 and ~0.424, as `SidebarHistoryPlacementTests`).
@MainActor
final class SidebarOptionDRenderedGeometryTests: XCTestCase {
    private struct Render {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Read inside the dial scope: the chip-size dial is only bound there.
        let chipSize: CGFloat
    }

    private func railWidth() throws -> CGFloat {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        return WorkspaceLayout.collapsedRailWidth(
            zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
            leadingInset: close.convert(close.bounds, to: nil).minX
        )
    }

    private func render(rail: Bool, chipSizeOffset: Double = 0) throws -> Render {
        try withDials({ $0.set(chipSizeOffset, forKey: SidebarDialTuning.railChipSizeOffsetKey) }) {
            let project = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
            let sessions = (0..<3).map { i in
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
            coordinator.setActiveSessionIdForTesting(try XCTUnwrap(sessions.last).id)

            let width = rail ? try railWidth() : 260
            let height: CGFloat = 400
            let column: AnyView
            if rail {
                column = AnyView(SidebarRailView())
            } else {
                column = AnyView(VStack(spacing: 0) {
                    Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)
                    RecentsListView()
                    Spacer(minLength: 0)
                })
            }
            let chrome = try XCTUnwrap(WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB))
            let tabSuiteName = "com.seansmithdesign.ghostties.tests.sidebar-tab.\(UUID().uuidString)"
            let tabSuite = try XCTUnwrap(UserDefaults(suiteName: tabSuiteName))
            defer { tabSuite.removePersistentDomain(forName: tabSuiteName) }
            tabSuite.set(SidebarTab.projects.rawValue, forKey: "ghostties.sidebarTab")
            let root = column
                .frame(width: width, height: height)
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
            return Render(rep: rep, scale: CGFloat(rep.pixelsWide) / width, width: width, height: height, chipSize: RailProjectColumn.chipSize)
        }
    }

    // MARK: - Pixel classes (summed-RGB drop below the chrome)

    private enum Mark { case none, card, chip, ink }

    private func drop(_ r: Render, px x: Int, _ y: Int) -> CGFloat {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB),
              x >= 0, y >= 0, x < r.rep.pixelsWide, y < r.rep.pixelsHigh,
              let c = r.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
        return (chrome.redComponent + chrome.greenComponent + chrome.blueComponent)
            - (c.redComponent + c.greenComponent + c.blueComponent)
    }

    private func mark(_ r: Render, px x: Int, _ y: Int) -> Mark {
        guard let chrome = WorkspaceLayout.chromeBackgroundLight.usingColorSpace(.sRGB) else { return .none }
        let base = chrome.redComponent + chrome.greenComponent + chrome.blueComponent
        let cardDrop = base * RailProjectColumn.columnTintOpacity
        let chipDrop = base * (1 - (1 - RailProjectColumn.columnTintOpacity) * (1 - RailProjectColumn.selectedChipTintOpacity))
        let d = drop(r, px: x, y)
        if d < cardDrop / 2 { return .none }
        if d < (cardDrop + chipDrop) / 2 { return .card }
        if d < chipDrop + (chipDrop - (cardDrop + chipDrop) / 2) { return .chip }
        return .ink
    }

    // MARK: - Measurements (points)

    private struct Edges {
        var cardLeading: CGFloat, cardTrailing: CGFloat
        var cardTop: CGFloat, cardBottom: CGFloat
        var chipLeading: CGFloat, chipTrailing: CGFloat, chipBottom: CGFloat
        var tileTop: CGFloat
    }

    /// The probe line sits 8pt in, the end of the chip's 8pt corner curve; the
    /// +/-1pt tolerance covers the continuous corner's small offset there.
    ///
    /// Reads the card's (or column's) edges and the marks inside it: down a
    /// line 8pt inside the chip's leading edge (past the corner curve, clear
    /// of the tile's monogram) for the vertical edges; along the chip's
    /// centre row for the horizontal ones.
    private func measure(_ r: Render, centreX: CGFloat) throws -> Edges {
        let chipSize = r.chipSize
        let tileSize = RailProjectTile.size
        let outerHalf = max(chipSize, tileSize) / 2
        let probeX = Int((centreX - outerHalf + 8) * r.scale)
        // Down the probe line: card run, with the ink tile and the chip in it.
        var cardTop: Int?, cardBottom = 0, tileTop: Int?, chipBottom = 0
        for y in 0..<r.rep.pixelsHigh {
            switch mark(r, px: probeX, y) {
            case .none: continue
            case .card: if cardTop == nil { cardTop = y }; cardBottom = y
            case .ink: if tileTop == nil { tileTop = y }; cardBottom = y
            case .chip: chipBottom = y; cardBottom = y
            }
        }
        let top = try XCTUnwrap(cardTop, "no card found")
        let tile = try XCTUnwrap(tileTop, "no ink tile found")
        XCTAssertGreaterThan(chipBottom, tile, "no selected chip below the tile")
        // Across the chip's centre row.
        let midY = chipBottom - Int((chipSize / 2) * r.scale)
        var chipLeading: Int?, chipTrailing = 0, cardLeading: Int?, cardTrailing = 0
        for x in 0..<r.rep.pixelsWide {
            let m = mark(r, px: x, midY)
            if m != .none { if cardLeading == nil { cardLeading = x }; cardTrailing = x }
            if m == .chip { if chipLeading == nil { chipLeading = x }; chipTrailing = x }
        }
        return Edges(
            cardLeading: CGFloat(try XCTUnwrap(cardLeading)) / r.scale,
            cardTrailing: CGFloat(cardTrailing + 1) / r.scale,
            cardTop: CGFloat(top) / r.scale, cardBottom: CGFloat(cardBottom + 1) / r.scale,
            chipLeading: CGFloat(try XCTUnwrap(chipLeading, "no chip on the centre row")) / r.scale,
            chipTrailing: CGFloat(chipTrailing + 1) / r.scale,
            chipBottom: CGFloat(chipBottom + 1) / r.scale,
            tileTop: CGFloat(tile) / r.scale
        )
    }

    // MARK: - Tests

    /// Expanded: the card is `groupCardInset` from the tile (above) and the
    /// selected chip (leading, below); the trailing side mirrors the leading.
    func testExpandedGroupCardIsInsetFromTileAndChipOnAllSides() throws {
        for chipOffset in [0.0, 4.0] {
            let r = try render(rail: false, chipSizeOffset: chipOffset)
            XCTAssertEqual(r.chipSize, RailProjectTile.size + chipOffset)
            let slotMidX = SidebarDialTuning.windowMargin() + SidebarDialTuning.contentPaddingLeading()
                + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
            let e = try measure(r, centreX: slotMidX)
            let inset = SidebarDialTuning.groupCardInset()
            let tag = "chip offset \(chipOffset)"
            XCTAssertEqual(e.tileTop - e.cardTop, inset, accuracy: 1.0, "top \(tag)")
            XCTAssertEqual(e.cardBottom - e.chipBottom, inset, accuracy: 1.0, "bottom \(tag)")
            // The wider of tile and chip is the outer element at the sides.
            let outer = max(r.chipSize, RailProjectTile.size)
            XCTAssertEqual(slotMidX - outer / 2 - e.cardLeading, inset, accuracy: 1.0, "leading (from constants) \(tag)")
            // Pixel to pixel: the rendered chip's edge (the chip is the
            // outer element at both offsets; its tile-sized slot has no
            // chip on the trailing side in the expanded list).
            XCTAssertEqual(e.chipLeading - e.cardLeading, inset, accuracy: 1.0, "leading (pixels) \(tag)")
            // Trailing: the rows' trailing edge is the column's, less the
            // trailing paddings; the mirrored slot ends `rowLeadingPadding`
            // inside it.
            let rowsMaxX = r.width - SidebarDialTuning.contentColumnTrailingPadding(gutter: 0)
                - SidebarDialTuning.contentPaddingTrailing()
            let mirroredMidX = rowsMaxX - SidebarDialTuning.rowLeadingPadding() - SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
            XCTAssertEqual(e.cardTrailing - (mirroredMidX + outer / 2), inset, accuracy: 1.0, "trailing \(tag)")
        }
    }

    /// Rail: the column is centred on the rail, `columnInset` from the tile
    /// above, the chip below and the wider of the two at the sides, and as
    /// wide as the tile plus the inset twice (38pt at the defaults).
    func testRailProjectColumnIsInsetFromTileAndChipOnAllSides() throws {
        for chipOffset in [0.0, 4.0] {
            let r = try render(rail: true, chipSizeOffset: chipOffset)
            XCTAssertEqual(r.chipSize, RailProjectTile.size + chipOffset)
            let e = try measure(r, centreX: r.width / 2)
            let inset = RailProjectColumn.columnInset
            let tag = "chip offset \(chipOffset)"
            XCTAssertEqual(e.tileTop - e.cardTop, inset, accuracy: 1.0, "top \(tag)")
            XCTAssertEqual(e.cardBottom - e.chipBottom, inset, accuracy: 1.0, "bottom \(tag)")
            let outer = max(r.chipSize, RailProjectTile.size)
            XCTAssertEqual(r.width / 2 - outer / 2 - e.cardLeading, inset, accuracy: 1.0, "leading (from constants) \(tag)")
            XCTAssertEqual(e.cardTrailing - (r.width / 2 + outer / 2), inset, accuracy: 1.0, "trailing (from constants) \(tag)")
            // Pixel to pixel: the rendered chip's edges.
            XCTAssertEqual(e.chipLeading - e.cardLeading, inset, accuracy: 1.0, "leading (pixels) \(tag)")
            XCTAssertEqual(e.cardTrailing - e.chipTrailing, inset, accuracy: 1.0, "trailing (pixels) \(tag)")
            XCTAssertEqual(e.cardTrailing - e.cardLeading, outer + 2 * inset, accuracy: 1.0, "width \(tag)")
            if chipOffset == 0 {
                XCTAssertEqual(e.cardTrailing - e.cardLeading, RailProjectTile.size + 2 * inset, accuracy: 1.0)
            }
        }
    }
}
