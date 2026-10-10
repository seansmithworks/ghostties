import CoreGraphics
import Foundation
import SwiftUI

/// The one-object sidebar ⇄ rail morph's geometry (plan
/// `vnext/morph/plan.md`, slice 1): every shared element's size and
/// position as a pure function of the dials and one progress value,
/// 0 = the expanded sidebar, 1 = the rail. Nothing reads it yet; the
/// unified list (slice 3) and the morph itself (slice 4) will.
///
/// Every x is measured from the sidebar's leading edge, never from the
/// centre of the current width, so a sub-frame mismatch between the AppKit
/// and SwiftUI widths mid-flight moves nothing.
struct SidebarMorphMetrics: Equatable {
    /// The dial values the metrics are built from. `current` reads the live
    /// dials; tests build one directly or read an isolated suite.
    struct Dials: Equatable {
        var windowMargin: CGFloat
        var contentPaddingLeading: CGFloat
        var contentPaddingTrailing: CGFloat
        /// The expanded list's trailing column padding
        /// (`SidebarDialTuning.contentColumnTrailingPadding` at the pinned
        /// gutter).
        var columnTrailingPadding: CGFloat
        var rowLeadingPadding: CGFloat
        var rowHeight: CGFloat
        var groupCardInset: CGFloat
        var columnInset: CGFloat
        var chipCornerRadius: CGFloat
        var sidebarTileSize: CGFloat
        var railTileSize: CGFloat
        var sidebarChipSize: CGFloat
        var railChipSize: CGFloat
        var sidebarGlyphSize: CGFloat
        var railGlyphSize: CGFloat

        /// The live dials, clamped as the views clamp them
        /// (`RailProjectTile.size`, `RailProjectColumn.chipSize`, …).
        static func current(defaults: UserDefaults = SidebarDialTuning.store) -> Dials {
            let margin = SidebarDialTuning.windowMargin(defaults: defaults)
            let rowHeight = SidebarDialTuning.rowHeight(defaults: defaults)
            let chip = { (size: CGFloat) in min(max(size, 0), rowHeight) }
            return Dials(
                windowMargin: margin,
                contentPaddingLeading: SidebarDialTuning.contentPaddingLeading(defaults: defaults),
                contentPaddingTrailing: SidebarDialTuning.contentPaddingTrailing(defaults: defaults),
                columnTrailingPadding: SidebarDialTuning.contentColumnTrailingPadding(
                    gutter: WorkspaceLayout.sidebarTrailingGutter(for: .pinned, margin: margin),
                    defaults: defaults
                ),
                rowLeadingPadding: SidebarDialTuning.rowLeadingPadding(defaults: defaults),
                rowHeight: rowHeight,
                groupCardInset: SidebarDialTuning.groupCardInset(defaults: defaults),
                columnInset: max(SidebarDialTuning.railColumnInset(defaults: defaults), 0),
                chipCornerRadius: max(SidebarDialTuning.railChipCornerRadius(defaults: defaults), 0),
                sidebarTileSize: max(SidebarDialTuning.sidebarProjectTileSize(defaults: defaults), 0),
                railTileSize: max(SidebarDialTuning.railProjectTileSize(defaults: defaults), 0),
                sidebarChipSize: chip(SidebarDialTuning.sidebarThreadTileSize(defaults: defaults)),
                railChipSize: chip(SidebarDialTuning.railThreadTileSize(defaults: defaults)),
                sidebarGlyphSize: max(SidebarDialTuning.sidebarThreadTileIcon(defaults: defaults), 0),
                railGlyphSize: max(SidebarDialTuning.railThreadTileIcon(defaults: defaults), 0)
            )
        }
    }

    /// The selected group's card in the expanded list and its column on the
    /// rail, as one shape: horizontal span, the inset above the tile and
    /// below the last chip, and corner radius.
    struct Card: Equatable {
        var minX: CGFloat
        var width: CGFloat
        var verticalInset: CGFloat
        var cornerRadius: CGFloat
        var maxX: CGFloat { minX + width }
        var midX: CGFloat { minX + width / 2 }
    }

    let dials: Dials
    /// The expanded sidebar's width (`WorkspaceLayout.sidebarWidth` or the
    /// dragged width).
    let expandedWidth: CGFloat
    /// The rail's width (`SidebarWidthModel.railWidth`).
    let railWidth: CGFloat
    /// 0 = expanded sidebar, 1 = rail; clamped.
    let progress: CGFloat

    init(dials: Dials = .current(), expandedWidth: CGFloat, railWidth: CGFloat, progress: CGFloat) {
        self.dials = dials
        self.expandedWidth = expandedWidth
        self.railWidth = railWidth
        self.progress = min(max(progress, 0), 1)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        Self.lerp(a, b, progress)
    }

    // MARK: Ends

    /// The expanded list's leading and trailing edges (`SidebarColumnPadding`).
    var listMinX: CGFloat { dials.windowMargin + dials.contentPaddingLeading }
    var listMaxX: CGFloat { expandedWidth - dials.contentPaddingTrailing - dials.columnTrailingPadding }

    /// The tile column's centre in the expanded list: the list's leading
    /// edge, the row's leading padding, then half the tile slot
    /// (`SidebarListRowChrome.glyphSlotWidth`, the sidebar tile's side).
    var sidebarTileCenterX: CGFloat { listMinX + dials.rowLeadingPadding + dials.sidebarTileSize / 2 }
    /// The rail centres everything (`SidebarRailView.columnPadding` is
    /// symmetric).
    var railTileCenterX: CGFloat { railWidth / 2 }

    // MARK: Interpolated

    /// The centre x of the project tile, and of every row's chip and glyph
    /// beneath it.
    var tileCenterX: CGFloat { lerp(sidebarTileCenterX, railTileCenterX) }
    var tileSize: CGFloat { lerp(dials.sidebarTileSize, dials.railTileSize) }
    var chipSize: CGFloat { lerp(dials.sidebarChipSize, dials.railChipSize) }
    var glyphSize: CGFloat { lerp(dials.sidebarGlyphSize, dials.railGlyphSize) }

    /// Row title, subtitle, header name, chevron and count: fully visible
    /// expanded, gone by the midpoint, where `isCollapsedPresentation`
    /// flips.
    var labelOpacity: Double { Double(max(0, 1 - progress * 2)) }

    /// How far a context's chip reaches past its tile on each side when it
    /// is the wider of the two (`RailProjectColumn.chipOverhang`); a header
    /// alone has no chip, so the tile is the outer element.
    private func sideOverhang(tile: CGFloat, chip: CGFloat, hasRows: Bool) -> CGFloat {
        hasRows ? max(0, chip - tile) / 2 : 0
    }

    /// The expanded group card: the list, widened past each edge by the card
    /// inset less the row's leading padding, plus the chip's overhang
    /// (`ExpandedGroupCard.horizontalOutset`).
    func sidebarCard(hasRows: Bool) -> Card {
        let outset = dials.groupCardInset - dials.rowLeadingPadding
            + sideOverhang(tile: dials.sidebarTileSize, chip: dials.sidebarChipSize, hasRows: hasRows)
        return Card(
            minX: listMinX - outset,
            width: max(0, listMaxX - listMinX + outset * 2),
            verticalInset: dials.groupCardInset,
            cornerRadius: dials.chipCornerRadius + dials.columnInset
        )
    }

    /// The rail column: the tile (or the wider chip) plus the column inset
    /// on each side, centred on the rail (`RailProjectColumn.columnWidth`).
    func railColumn(hasRows: Bool) -> Card {
        let width = dials.railTileSize
            + (sideOverhang(tile: dials.railTileSize, chip: dials.railChipSize, hasRows: hasRows) + dials.columnInset) * 2
        return Card(
            minX: railTileCenterX - width / 2,
            width: width,
            verticalInset: dials.columnInset,
            cornerRadius: dials.chipCornerRadius + dials.columnInset
        )
    }

    /// The card narrowing into the column: every edge on a straight line
    /// between the two.
    func card(hasRows: Bool) -> Card {
        let from = sidebarCard(hasRows: hasRows)
        let to = railColumn(hasRows: hasRows)
        return Card(
            minX: lerp(from.minX, to.minX),
            width: lerp(from.width, to.width),
            verticalInset: lerp(from.verticalInset, to.verticalInset),
            cornerRadius: lerp(from.cornerRadius, to.cornerRadius)
        )
    }
}

// MARK: - Gate probes (DEBUG)

#if DEBUG
/// Counts, per sidebar element, how many times it mounted, and how many
/// times `RecentsListView.body` ran (morph plan §4: the identity and perf
/// gates). One per container, injected at the sidebar root, read by
/// `SidebarMorphGateTests`; nothing in the app reads it.
@MainActor
final class MorphProbe {
    private(set) var appearCounts: [String: Int] = [:]
    private(set) var bodyCounts: [String: Int] = [:]

    func appeared(_ id: String) { appearCounts[id, default: 0] += 1 }
    func evaluated(_ name: String) { bodyCounts[name, default: 0] += 1 }
}

private struct MorphProbeKey: EnvironmentKey {
    static let defaultValue: MorphProbe? = nil
}

extension EnvironmentValues {
    /// The container's `MorphProbe`; nil outside a workspace sidebar.
    var morphProbe: MorphProbe? {
        get { self[MorphProbeKey.self] }
        set { self[MorphProbeKey.self] = newValue }
    }
}

private struct MorphIdentityProbeModifier: ViewModifier {
    let id: String
    @Environment(\.morphProbe) private var probe

    func body(content: Content) -> some View {
        content.onAppear { probe?.appeared(id) }
    }
}
#endif

extension View {
    /// Counts this element's mounts under `id` in the container's
    /// `MorphProbe` (DEBUG; a no-op in Release or when `id` is nil). The
    /// same element carries the same id in every sidebar mode.
    @ViewBuilder
    func morphIdentityProbe(_ id: String?) -> some View {
        #if DEBUG
        if let id {
            modifier(MorphIdentityProbeModifier(id: id))
        } else {
            self
        }
        #else
        self
        #endif
    }
}
