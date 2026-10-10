import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

/// `SidebarMorphMetrics` (morph plan, slice 1) at the shipped dials: the
/// expanded and rail ends match option D, and every value at p = 0.5 is the
/// midpoint of its ends. Dials are read from an isolated suite (`withDials`).
@MainActor
struct SidebarMorphMetricsTests {
    /// Option D's expanded sidebar (`WorkspaceLayout.sidebarWidth`) and rail
    /// (traffic lights x 19–79, + 19).
    private let expandedWidth: CGFloat = 256
    private let railWidth: CGFloat = 98

    private func metrics(_ progress: CGFloat) -> SidebarMorphMetrics {
        withDials {
            SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: progress)
        }
    }

    @Test func expandedEndMatchesOptionD() {
        let m = metrics(0)
        #expect(m.tileCenterX == 27, "tile at x 12, 30 wide")
        #expect(m.tileSize == 30)
        #expect(m.chipSize == 30)
        #expect(m.glyphSize == 20)
        #expect(m.labelOpacity == 1)
        let card = m.card(hasRows: true)
        #expect(card.minX == 6, "list x 8, card 2pt past it")
        #expect(card.maxX == 258, "list x 256, card 2pt past it")
        #expect(card.verticalInset == 6)
        #expect(card.cornerRadius == 12)
    }

    /// Option D's rail, with the rail's tiles a third larger (Sean,
    /// 2026-10-10): 40pt tile and chip, 26pt glyph.
    @Test func railEndMatchesOptionD() {
        let m = metrics(1)
        #expect(m.tileCenterX == 49, "centred on the 98pt rail")
        #expect(m.tileSize == 40)
        #expect(m.chipSize == 40)
        #expect(m.glyphSize == 26)
        #expect(m.labelOpacity == 0)
        let column = m.card(hasRows: true)
        #expect(column.width == 48, "tile ±4")
        #expect(column.midX == 49)
        #expect(column.verticalInset == 4)
        #expect(column.cornerRadius == 12)
    }

    @Test func midpointIsHalfwayOnEveryValue() {
        let a = metrics(0), b = metrics(1), m = metrics(0.5)
        #expect(m.tileCenterX == (a.tileCenterX + b.tileCenterX) / 2)
        #expect(m.tileCenterX == 38)
        #expect(m.tileSize == (a.tileSize + b.tileSize) / 2)
        #expect(m.chipSize == (a.chipSize + b.chipSize) / 2)
        #expect(m.glyphSize == (a.glyphSize + b.glyphSize) / 2)
        let ca = a.card(hasRows: true), cb = b.card(hasRows: true), cm = m.card(hasRows: true)
        #expect(cm.minX == (ca.minX + cb.minX) / 2)
        #expect(cm.maxX == (ca.maxX + cb.maxX) / 2)
        #expect(cm.verticalInset == 5)
        #expect(m.labelOpacity == 0, "labels are gone by the midpoint")
        #expect(metrics(0.25).labelOpacity == 0.5)
    }

    @Test func progressIsClamped() {
        #expect(metrics(-1) == metrics(0))
        #expect(metrics(2) == metrics(1))
    }

    /// The ends agree with what the settled views draw today, at non-default
    /// dials too: the expanded card's outset (`ExpandedGroupCard`) and the
    /// rail column's width (`RailProjectColumn.columnWidth`).
    @Test func endsAgreeWithTheSettledViews() {
        withDials({ d in
            d.set(10.0, forKey: SidebarDialTuning.groupCardInsetKey)
            d.set(6.0, forKey: SidebarDialTuning.railColumnInsetKey)
            d.set(36.0, forKey: SidebarDialTuning.railThreadTileSizeKey)
            d.set(34.0, forKey: SidebarDialTuning.sidebarThreadTileSizeKey)
            d.set(18.0, forKey: SidebarDialTuning.railThreadTileIconKey)
        }) {
            let expanded = SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: 0)
            let outset = ExpandedGroupCard.horizontalOutset(
                cardInset: SidebarDialTuning.groupCardInset(),
                rowLeadingPadding: SidebarDialTuning.rowLeadingPadding(),
                chipOverhang: RailProjectColumn.sideOverhang(anchorCount: 2, context: .sidebar)
            )
            #expect(expanded.card(hasRows: true).minX == expanded.listMinX - outset)
            #expect(expanded.chipSize == RailProjectColumn.chipSize(.sidebar))

            let rail = SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: 1)
            #expect(rail.card(hasRows: true).width == RailProjectColumn.columnWidth(anchorCount: 2, inset: RailProjectColumn.columnInset))
            #expect(rail.card(hasRows: false).width == RailProjectColumn.columnWidth(anchorCount: 1, inset: RailProjectColumn.columnInset))
            #expect(rail.chipSize == RailProjectColumn.chipSize(.rail))
            #expect(rail.glyphSize == RailProjectColumn.chipGlyphSize(.rail))
        }
    }

    @Test func collapsedPresentationFollowsMorph() {
        let model = SidebarWidthModel(width: expandedWidth)
        #expect(!model.isCollapsedPresentation)
        model.morph = 0.49
        #expect(!model.isCollapsedPresentation)
        model.morph = 0.5
        #expect(model.isCollapsedPresentation)
        model.morph = 1
        #expect(model.isCollapsedPresentation)
    }
}
