import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// `SidebarMorphMetrics` (morph plan, slice 1) at the shipped dials: the
/// expanded and rail ends match option D with the rail staying put (the
/// tile column, its card and its chips identical at both ends), and every
/// value at p = 0.5 is the midpoint of its ends. Dials are read from an
/// isolated suite (`withDials`).
@MainActor
struct SidebarMorphMetricsTests {
    /// Option D's expanded sidebar (`WorkspaceLayout.sidebarWidth`) and rail
    /// (traffic lights x 19–79, + 19, on the 8pt grid).
    private let expandedWidth: CGFloat = 256
    private let railWidth: CGFloat = 96

    private func metrics(_ progress: CGFloat) -> SidebarMorphMetrics {
        withDials {
            SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: progress)
        }
    }

    @Test func expandedEndMatchesOptionD() {
        let m = metrics(0)
        #expect(m.tileCenterX == 48, "on the rail's tile column")
        #expect(m.tileSize == 40)
        #expect(m.chipSize == 40)
        #expect(m.glyphSize == 16)
        #expect(m.labelOpacity == 1)
        #expect(m.listMinX == 24, "row padding 4, then the tile at x 28")
        #expect(m.namesMinX == 109, "divider at 96, 1pt, then 12")
        let card = m.card(hasRows: true)
        #expect(card == m.railColumn(hasRows: true), "the card hugs the rail column")
        #expect(card.minX == 24)
        #expect(card.width == 48, "tile ±4")
    }

    /// Option D's rail, with the rail's tiles a third larger (Sean,
    /// 2026-10-10): 40pt tile and chip, 16pt glyph
    /// (the content stays at the sidebar's size).
    @Test func railEndMatchesOptionD() {
        let m = metrics(1)
        #expect(m.tileCenterX == 48, "centred on the 96pt rail")
        #expect(m.tileSize == 40)
        #expect(m.chipSize == 40)
        #expect(m.glyphSize == 16)
        #expect(m.labelOpacity == 0)
        let column = m.card(hasRows: true)
        #expect(column.width == 48, "tile ±4")
        #expect(column.midX == 48)
        #expect(column.verticalInset == 4)
        #expect(column.cornerRadius == 12)
    }

    @Test func midpointIsHalfwayOnEveryValue() {
        let a = metrics(0), b = metrics(1), m = metrics(0.5)
        #expect(m.tileCenterX == (a.tileCenterX + b.tileCenterX) / 2)
        #expect(m.tileCenterX == 48)
        #expect(m.tileSize == (a.tileSize + b.tileSize) / 2)
        #expect(m.chipSize == (a.chipSize + b.chipSize) / 2)
        #expect(m.glyphSize == (a.glyphSize + b.glyphSize) / 2)
        let ca = a.card(hasRows: true), cb = b.card(hasRows: true), cm = m.card(hasRows: true)
        #expect(cm.minX == (ca.minX + cb.minX) / 2)
        #expect(cm.maxX == (ca.maxX + cb.maxX) / 2)
        #expect(cm.verticalInset == (ca.verticalInset + cb.verticalInset) / 2)
        #expect(cm.verticalInset == 4)
        #expect(m.labelOpacity == 0, "labels are gone by the midpoint")
        #expect(metrics(0.25).labelOpacity == 0.5)
    }

    @Test func progressIsClamped() {
        #expect(metrics(-1) == metrics(0))
        #expect(metrics(2) == metrics(1))
    }

    /// The ends agree with what the settled views draw today, at non-default
    /// dials too: the list's anchored leading edge and the rail column's
    /// width (`RailProjectColumn.columnWidth`).
    @Test func endsAgreeWithTheSettledViews() {
        withDials({ d in
            d.set(6.0, forKey: SidebarDialTuning.railColumnInsetKey)
            d.set(36.0, forKey: SidebarDialTuning.railThreadTileSizeKey)
            d.set(34.0, forKey: SidebarDialTuning.sidebarThreadTileSizeKey)
            d.set(18.0, forKey: SidebarDialTuning.railThreadTileIconKey)
        }) {
            let expanded = SidebarMorphMetrics(expandedWidth: expandedWidth, railWidth: railWidth, progress: 0)
            #expect(expanded.listMinX + SidebarDialTuning.rowLeadingPadding() + SidebarListRowChrome<EmptyView, EmptyView>.glyphSlotWidth / 2
                == railWidth / 2)
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
