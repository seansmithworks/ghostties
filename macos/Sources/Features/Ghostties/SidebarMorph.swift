import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// The one-object sidebar ⇄ rail morph's geometry (plan
/// `vnext/morph/plan.md`): every shared element's size and position as a
/// pure function of the dials and one progress value, 0 = the expanded
/// sidebar, 1 = the rail. One view tree renders both (`SidebarMorphFrame`
/// lays it out at the expanded width); the leaves below read their ends
/// from here once per change and interpolate between them per frame.
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
        /// "Project tile text": a one-letter monogram's size in each context.
        var sidebarTileText: CGFloat
        var railTileText: CGFloat

        /// The monogram's font size; two letters draw 2pt smaller
        /// (`RailProjectTile.textSize`).
        func tileTextSize(rail: Bool, letters: Int) -> CGFloat {
            max((rail ? railTileText : sidebarTileText) - (letters > 1 ? 2 : 0), 1)
        }

        /// The project header's height in each context: 40 in both (keyframe
        /// spec D1), so the rows never reflow across the morph; only a tile
        /// dialled past 40 grows it (`ProjectAccordionHeader.height`).
        var sidebarHeaderHeight: CGFloat { max(SidebarMorphMetrics.headerBaseHeight, sidebarTileSize) }
        var railHeaderHeight: CGFloat { max(SidebarMorphMetrics.headerBaseHeight, railTileSize) }

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
                railGlyphSize: max(SidebarDialTuning.railThreadTileIcon(defaults: defaults), 0),
                sidebarTileText: SidebarDialTuning.sidebarProjectTileText(defaults: defaults),
                railTileText: SidebarDialTuning.railProjectTileText(defaults: defaults)
            )
        }
    }

    /// The project header's height on the sidebar and the rail alike
    /// (keyframe spec D1), which a tile at or under 40pt sits in
    /// (`ProjectAccordionHeader.baseHeight`).
    static let headerBaseHeight: CGFloat = 40

    /// The selected group's card in the expanded list and its column on the
    /// rail, as one shape: horizontal span, the inset above the tile and
    /// below the last chip, corner radius, and how far the tile and the
    /// last chip sit inside their header and row (the card's top and
    /// bottom are measured from those, not from the frames).
    struct Card: Equatable {
        var minX: CGFloat
        var width: CGFloat
        var verticalInset: CGFloat
        var cornerRadius: CGFloat
        /// The tile's inset from its header's top and bottom.
        var tileTrim: CGFloat
        /// The chip's inset from its row's top and bottom.
        var chipTrim: CGFloat
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

    /// The width a project header's chevron and count are laid out at
    /// through the morph: their resting width, at every step. They are never
    /// narrowed or truncated; what keeps them uncut by the panel's shrinking
    /// clip is `trailingClusterTravel`, which moves them with its edge.
    static func trailingClusterWidth(resting: CGFloat, progress _: CGFloat) -> CGFloat {
        resting
    }

    /// How far left a project header's count or chevron is drawn at this
    /// step so the panel's trailing edge never cuts it while it fades
    /// (keyframe spec, defect 5). The list is laid out at `expandedWidth`
    /// and clipped to the current width, `lerp(expandedWidth, railWidth)`,
    /// so the edge moves in by `(expandedWidth - railWidth) * progress`. The
    /// count, the cluster's trailing element (`slack` 0), rides that edge
    /// from the first frame, keeping its resting gap to it; the chevron,
    /// `slack` short of the count's trailing edge, stays put until the edge
    /// reaches it, then rides too. 0 on the expanded sidebar.
    func trailingClusterTravel(slack: CGFloat) -> CGFloat {
        min(0, max(slack, 0) - (expandedWidth - railWidth) * progress)
    }

    // MARK: Ends

    /// The expanded list's leading and trailing edges (`SidebarColumnPadding`).
    var listMinX: CGFloat { dials.windowMargin + dials.contentPaddingLeading }
    var listMaxX: CGFloat { expandedWidth - dials.contentPaddingTrailing - dials.columnTrailingPadding }

    /// The tile column's centre in the expanded list: the list's leading
    /// edge, the row's leading padding, then half the tile slot
    /// (`SidebarListRowChrome.glyphSlotWidth`, the sidebar tile's side).
    var sidebarTileCenterX: CGFloat { listMinX + dials.rowLeadingPadding + dials.sidebarTileSize / 2 }
    /// The rail centres everything: tiles, chips, glyphs and the column.
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
    /// flips. Its timing is the label's own (`MorphLabelFade`), not the
    /// panel's: an animated toggle writes the end value, so this only
    /// shapes the held steps (`applyMorphStep`).
    var labelOpacity: Double { Self.labelOpacity(progress) }
    static func labelOpacity(_ progress: CGFloat) -> Double { Double(min(max(1 - progress * 2, 0), 1)) }

    /// How far the tile column travels, sidebar to rail: every tile, chip
    /// and glyph is laid out in its sidebar slot and drawn this much
    /// further right, scaled by progress (`MorphTravel`).
    var tileTravel: CGFloat { railTileCenterX - sidebarTileCenterX }

    /// How far a context's chip reaches past its tile on each side when it
    /// is the wider of the two (`RailProjectColumn.chipOverhang`); a header
    /// alone has no chip, so the tile is the outer element.
    private func sideOverhang(tile: CGFloat, chip: CGFloat, hasRows: Bool) -> CGFloat {
        hasRows ? max(0, chip - tile) / 2 : 0
    }

    /// The expanded group card: the list, widened past each edge by the card
    /// inset less the row's leading padding, plus the chip's overhang
    /// (`ProjectGroupCard.horizontalOutset`).
    func sidebarCard(hasRows: Bool) -> Card {
        let outset = dials.groupCardInset - dials.rowLeadingPadding
            + sideOverhang(tile: dials.sidebarTileSize, chip: dials.sidebarChipSize, hasRows: hasRows)
        return Card(
            minX: listMinX - outset,
            width: max(0, listMaxX - listMinX + outset * 2),
            verticalInset: dials.groupCardInset,
            cornerRadius: dials.chipCornerRadius + dials.columnInset,
            tileTrim: (dials.sidebarHeaderHeight - dials.sidebarTileSize) / 2,
            chipTrim: max(0, (dials.rowHeight - dials.sidebarChipSize) / 2)
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
            cornerRadius: dials.chipCornerRadius + dials.columnInset,
            tileTrim: (dials.railHeaderHeight - dials.railTileSize) / 2,
            chipTrim: max(0, (dials.rowHeight - dials.railChipSize) / 2)
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
            cornerRadius: lerp(from.cornerRadius, to.cornerRadius),
            tileTrim: lerp(from.tileTrim, to.tileTrim),
            chipTrim: lerp(from.chipTrim, to.chipTrim)
        )
    }
}

// MARK: - Leaves

/// The progress the leaves draw at: an override (the crossfade's two
/// trees, each held at its own end) or the live `SidebarWidthModel.morph`.
private struct SidebarMorphOverrideKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Holds every morph leaf below at this progress, whatever
    /// `SidebarWidthModel.morph` says: 0 for the expanded tree and 1 for the
    /// rail tree while `SidebarCollapseCrossfade` fades between them (the
    /// task-first and Projects-tabs layouts, which don't morph). Nil, the
    /// leaves follow the model.
    var sidebarMorphOverride: CGFloat? {
        get { self[SidebarMorphOverrideKey.self] }
        set { self[SidebarMorphOverrideKey.self] = newValue }
    }
}

/// The dials, read once per sidebar tree (`SidebarMorphFrame`, re-read on
/// every dial write) and handed to every morph leaf, so a row or header
/// body never reads them from `UserDefaults` itself.
private struct SidebarMorphDialsKey: EnvironmentKey {
    static let defaultValue: SidebarMorphMetrics.Dials? = nil
}

extension EnvironmentValues {
    var sidebarMorphDials: SidebarMorphMetrics.Dials? {
        get { self[SidebarMorphDialsKey.self] }
        set { self[SidebarMorphDialsKey.self] = newValue }
    }
}

extension SidebarWidthModel {
    /// This model's metrics at `progress`, from `dials` (the tree's, or
    /// the live dials for a view hosted outside `SidebarMorphFrame`).
    func metrics(_ progress: CGFloat, dials: SidebarMorphMetrics.Dials?) -> SidebarMorphMetrics {
        SidebarMorphMetrics(dials: dials ?? .current(), expandedWidth: expandedWidth, railWidth: railWidth, progress: progress)
    }
}

/// The tile column's horizontal travel: render-only, so a frame of the
/// morph moves pixels, not layout.
struct MorphTravel: GeometryEffect {
    /// The full travel, at progress 1 (`SidebarMorphMetrics.tileTravel`).
    var distance: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: distance * progress, y: 0))
    }
}

/// A tile's shape (the project tile, a row's chip) through the morph: one
/// fixed square at the rail's size in both states, the shape scaled down to
/// the sidebar's size (32 of 40, 0.8) and back up, so the container and the
/// row never resize and the monogram or glyph inside stays its own size.
enum MorphTileScale {
    /// The shape's scale at `progress`: the size this frame draws
    /// (`SidebarMorphMetrics.tileSize`/`chipSize`) over the container's.
    static func scale(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        guard to > 0 else { return 0 }
        return SidebarMorphMetrics.lerp(from, to, progress) / to
    }
}

/// Draws a project header's count or chevron `trailingClusterTravel` to the
/// left at this frame's progress: render-only, so the header's layout
/// never changes.
struct MorphTrailingClusterRide: GeometryEffect {
    let metrics: SidebarMorphMetrics
    let slack: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let step = SidebarMorphMetrics(
            dials: metrics.dials, expandedWidth: metrics.expandedWidth, railWidth: metrics.railWidth, progress: progress
        )
        return ProjectionTransform(CGAffineTransform(translationX: step.trailingClusterTravel(slack: slack), y: 0))
    }
}

/// A frame height between two ends: the project header (40 at both ends
/// at the defaults; a tile dialled past 40 grows it).
struct MorphHeight: ViewModifier, Animatable {
    var from: CGFloat
    var to: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(height: SidebarMorphMetrics.lerp(from, to, progress))
    }
}

/// A row's leading slot: the status glyph at its size for this frame of
/// the morph (the "Thread tile icon" dials, 16 at both ends), over its chip,
/// centred in the sidebar's tile slot (the layout never changes;
/// `MorphTravel` moves it). The chip is one rail-sized square in both
/// states, its shape scaled to this frame's size (`MorphTileScale`), so
/// its frame never resizes and the glyph is never scaled with it.
struct MorphGlyphSlot<Glyph: View>: View, Animatable {
    var progress: CGFloat
    /// The slot's laid-out width: the sidebar tile's side.
    let slotWidth: CGFloat
    let glyphSizes: (from: CGFloat, to: CGFloat)
    let chipSizes: (from: CGFloat, to: CGFloat)
    let isActive: Bool
    let isHovered: Bool
    let chipID: String
    @ViewBuilder let glyph: (CGFloat) -> Glyph

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let glyphSize = SidebarMorphMetrics.lerp(glyphSizes.from, glyphSizes.to, progress)
        glyph(glyphSize)
            .frame(width: glyphSize, height: glyphSize)
            .frame(width: slotWidth)
            .background {
                SidebarRowChipBackground(
                    size: chipSizes.to,
                    scale: MorphTileScale.scale(from: chipSizes.from, to: chipSizes.to, progress: progress),
                    isActive: isActive, isHovered: isHovered, redlineID: chipID
                )
                .morphIdentityProbe(chipID)
            }
    }
}

/// Fades row and header labels out on the way to the rail and back in on
/// the way out of it, on their own direction-aware clocks
/// (`WorkspaceLayout.morphFadeWindow`): on collapse names fade 0–90ms and a
/// header's count and chevron 0–60ms, drifting 4pt left; on expand each
/// fades in place over 120ms on the cascade (`SidebarLabelCascade`).
/// Reduce Motion: a 120ms fade, no drift. Off the expanded sidebar, labels
/// take no clicks.
struct MorphLabelFade: ViewModifier {
    var element: SidebarMorphElement = .names
    /// The label's place in the cascade (`SidebarLabelCascade`).
    var staggerIndex: Int = 0

    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override

    func body(content: Content) -> some View {
        let progress = override ?? widthModel.morph
        let opacity = SidebarMorphMetrics.labelOpacity(progress)
        let appearing = opacity > 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let window = WorkspaceLayout.morphFadeWindow(
            element: element, direction: appearing ? .expand : .collapse,
            reduceMotion: reduceMotion, staggerIndex: staggerIndex
        )
        let fade = WorkspaceLayout.morphFadeAnimation(window, reduceMotion: reduceMotion)
        let drift = WorkspaceLayout.sidebarLabelDriftTravel(appearing: appearing, reduceMotion: reduceMotion)
        content
            // The drift plays only where it is non-zero (collapse); on the
            // way back the label returns to its place at once, hidden, and
            // fades in there.
            .offset(x: appearing ? 0 : drift)
            .animation(drift == 0 ? nil : fade, value: appearing)
            .opacity(opacity)
            .animation(fade, value: opacity)
            // `morph` is the target as soon as a toggle starts, so labels
            // fading back in stay unclickable until the morph has landed.
            .allowsHitTesting(progress == 0 && !widthModel.isMorphing)
    }
}

/// A folded project's count badge on its rail tile: the labels' fade
/// reversed, on the badge's own clock (`WorkspaceLayout.morphFadeWindow`):
/// it arrives 110–270ms into a collapse, growing 0.9 → 1, and leaves in the
/// first 50ms of an expand.
struct MorphRailOnlyFade: ViewModifier {
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override

    func body(content: Content) -> some View {
        let progress = override ?? widthModel.morph
        let opacity = Double(min(max(progress * 2 - 1, 0), 1))
        let appearing = opacity > 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let window = WorkspaceLayout.morphFadeWindow(element: .badge, direction: appearing ? .collapse : .expand, reduceMotion: reduceMotion)
        let fade = WorkspaceLayout.morphFadeAnimation(window, reduceMotion: reduceMotion)
        // The arrival's scale; leaving, the badge only fades, and is back
        // at the arrival's start once hidden.
        let arrival = WorkspaceLayout.morphFadeWindow(element: .badge, direction: .collapse, reduceMotion: reduceMotion)
        content
            .scaleEffect(appearing ? arrival.scaleTo : arrival.scaleFrom)
            .animation(appearing ? fade : nil, value: appearing)
            .opacity(opacity)
            .animation(fade, value: opacity)
    }
}

/// The space the tray takes under the list: the horizontal bar's on the
/// sidebar, the rail's taller stack on the rail, following the morph's
/// progress frame by frame (`height(progress:railWidth:)`), so it never
/// jumps when a toggle writes its target at t=0 (keyframe spec, defect 2).
struct MorphTrayReserve: View {
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override
    /// The rail's width as the tray reads it (`EnvironmentValues.sidebarRailWidth`),
    /// so the reservation and the rail tray's pills agree.
    @Environment(\.sidebarRailWidth) private var railWidth
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The reservation at `progress`: the horizontal tray's at 0, the rail
    /// stack's at 1, on a straight line between.
    static func height(progress: CGFloat, railWidth: CGFloat) -> CGFloat {
        SidebarMorphMetrics.lerp(
            SidebarTray.reservedHeight(isVertical: false, railWidth: railWidth),
            SidebarTray.reservedHeight(isVertical: true, railWidth: railWidth),
            min(max(progress, 0), 1)
        )
    }

    var body: some View {
        Color.clear
            .modifier(Frame(progress: override ?? widthModel.morph, railWidth: railWidth))
            .accessibilityHidden(true)
    }

    /// Interpolates `progress` on the toggle's transaction, so the height
    /// is read per frame, not at the target.
    private struct Frame: ViewModifier, Animatable {
        var progress: CGFloat
        let railWidth: CGFloat

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            content.frame(height: MorphTrayReserve.height(progress: progress, railWidth: railWidth))
        }
    }
}

/// The gap under the pinned History row: one History-to-tray gap above the
/// tray. The horizontal tray's reservation already holds the list-to-tray
/// gap; the rail's doesn't, so on the rail the footer adds all of it.
struct MorphHistoryFooterGap: ViewModifier {
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    func body(content: Content) -> some View {
        let vertical = (override ?? widthModel.morph) >= 0.5
        content.padding(.bottom, SidebarSessionSections.historyToTrayGap() - (vertical ? 0 : SidebarDialTuning.listToTrayGap()))
    }
}

/// Hosts the one sidebar tree for every morph step: laid out at the
/// expanded width always, leading-anchored, and clipped to the current
/// width, so nothing re-lays out as the panel narrows; only the leaves'
/// own sizes and offsets move. The list column always pads for the pinned
/// gutter (its layout is the expanded sidebar's, at every step).
struct SidebarMorphFrame<Content: View>: View {
    @ObservedObject var model: SidebarWidthModel
    let content: Content
    /// Read in `body` (below): an `@AppStorage` the body never reads does not
    /// invalidate it, so the dials in the environment stayed at their first
    /// values and no rail dial change reached a leaf.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The live dials, keyed by the epoch so the body depends on it.
    private static func dials(epoch _: Int) -> SidebarMorphMetrics.Dials { .current() }

    var body: some View {
        // The dials are a function of the epoch, which every panel write bumps.
        let dials = Self.dials(epoch: dialEpochTick)
        content
            .environment(\.sidebarTrailingGutter, WorkspaceLayout.sidebarTrailingGutter(for: .pinned))
            .environment(\.sidebarMorphDials, dials)
            .frame(width: model.expandedWidth)
            // Every frame top-leading: a frame narrower than its child
            // centres it by default, which would slide the whole list left
            // as the panel narrows.
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(width: model.width, alignment: .topLeading)
            // The group card reaches a little past the column's trailing
            // edge on the expanded sidebar; nothing else draws past it.
            .clipShape(Rectangle().inset(by: -ProjectGroupCard.trailingBleed()))
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
