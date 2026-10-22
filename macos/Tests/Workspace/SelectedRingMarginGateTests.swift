import Foundation
import Testing
@testable import Ghostty

/// Gate for the selected icon tile's ring margin (rail 05, Sean's call):
/// the ring's outer edge sat flush on the group card's edge (tile 40, ring
/// 2pt gap + 2pt stroke = 4pt out; card inset 4pt). Thin the ring so there
/// is visible margin between the ring and the card edge. Tile stays 40pt,
/// tile centre stays x=48, rail width unchanged.
///
/// Reads the geometry the views use: `ProjectTileView.ringWidth/ringGap`
/// (the ring) and `SidebarMorphMetrics.card(hasRows:)` (the card), so a
/// fix that changes the constants or the card inset is measured, not
/// restated.
///
/// Red today: (a) the margin is 0 on every side, in both states.
/// Already green guards: (b), (c).
@MainActor
@Suite(.serialized)
struct SelectedRingMarginGateTests {
    private let expandedWidth: CGFloat = 256
    /// macOS 26 traffic-light cluster inputs behind the 96pt rail.
    private let zoomMaxX: CGFloat = 79
    private let leadingInset: CGFloat = 19
    private let minMargin: CGFloat = 1

    private var ringOutset: CGFloat { ProjectTileView.ringGap + ProjectTileView.ringWidth }

    private func metrics(_ progress: CGFloat) -> SidebarMorphMetrics {
        withDials {
            let rail = WorkspaceLayout.collapsedRailWidth(zoomButtonMaxX: zoomMaxX, leadingInset: leadingInset)
            return SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: rail, progress: progress)
        }
    }

    /// Margin between the ring's outer edge and the card edge, per side,
    /// for a selected icon tile. `hasRows` covers a header alone and a
    /// group with rows.
    private func margins(progress: CGFloat, hasRows: Bool) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let m = metrics(progress)
        let card = m.card(hasRows: hasRows)
        let half = m.tileSize / 2 + ringOutset
        return (
            left: (m.tileCenterX - half) - card.minX,
            right: card.maxX - (m.tileCenterX + half),
            // Vertically the card sits `topInset` / `verticalInset` out
            // from the tile (header alone; a last row's chip is the same
            // size as the tile at the shipped dials).
            top: card.topInset - ringOutset,
            bottom: card.verticalInset - ringOutset
        )
    }

    // MARK: (a) margin: RED today

    @Test(arguments: [CGFloat(0), 1], [false, true])
    func ringSitsInsideTheCardOnEverySide(progress: CGFloat, hasRows: Bool) {
        let state = progress == 0 ? "sidebar" : "rail"
        let g = margins(progress: progress, hasRows: hasRows)
        #expect(g.left >= minMargin, "\(state) hasRows=\(hasRows): left margin \(g.left) < \(minMargin)")
        #expect(g.right >= minMargin, "\(state) hasRows=\(hasRows): right margin \(g.right) < \(minMargin)")
        #expect(g.top >= minMargin, "\(state) hasRows=\(hasRows): top margin \(g.top) < \(minMargin)")
        #expect(g.bottom >= minMargin, "\(state) hasRows=\(hasRows): bottom margin \(g.bottom) < \(minMargin)")
    }

    // MARK: (b) ring stays visible and detached: green guard today

    @Test func ringIsVisibleAndDetached() {
        #expect(ProjectTileView.ringWidth >= 1, "ring stroke \(ProjectTileView.ringWidth) < 1")
        #expect(ProjectTileView.ringGap >= 1, "gap tile-to-ring \(ProjectTileView.ringGap) < 1")
    }

    // MARK: (c) tile geometry unchanged: green guard today

    @Test(arguments: [CGFloat(0), 0.5, 1])
    func tileIs40AndCentredOn48(progress: CGFloat) {
        let m = metrics(progress)
        #expect(m.tileSize == 40, "tile size \(m.tileSize) at progress \(progress)")
        #expect(m.tileCenterX == 48, "tile centre x \(m.tileCenterX) at progress \(progress)")
        #expect(m.railWidth == 96, "rail width \(m.railWidth)")
    }
}
