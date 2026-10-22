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
        var contentPaddingTrailing: CGFloat
        /// The expanded list's trailing column padding
        /// (`SidebarDialTuning.contentColumnTrailingPadding` at the pinned
        /// gutter).
        var columnTrailingPadding: CGFloat
        var rowLeadingPadding: CGFloat
        var rowHeight: CGFloat
        var columnInset: CGFloat
        var chipCornerRadius: CGFloat
        /// The project tile, one size in both states (rail stays put): the
        /// rail's "Project tile size" dial.
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

        /// The project header's height, the same in both states: 40 (keyframe
        /// spec D1), so the rows never reflow across the morph; only a tile
        /// dialled past 40 grows it (`ProjectAccordionHeader.height`).
        var headerHeight: CGFloat { max(SidebarMorphMetrics.headerBaseHeight, railTileSize) }

        /// The live dials, clamped as the views clamp them
        /// (`RailProjectTile.size`, `RailProjectColumn.chipSize`, …).
        static func current(defaults: UserDefaults = SidebarDialTuning.store) -> Dials {
            let margin = SidebarDialTuning.windowMargin(defaults: defaults)
            let rowHeight = SidebarDialTuning.rowHeight(defaults: defaults)
            let chip = { (size: CGFloat) in min(max(size, 0), rowHeight) }
            return Dials(
                contentPaddingTrailing: SidebarDialTuning.contentPaddingTrailing(defaults: defaults),
                columnTrailingPadding: SidebarDialTuning.contentColumnTrailingPadding(
                    gutter: WorkspaceLayout.sidebarTrailingGutter(for: .pinned, margin: margin),
                    defaults: defaults
                ),
                rowLeadingPadding: SidebarDialTuning.rowLeadingPadding(defaults: defaults),
                rowHeight: rowHeight,
                columnInset: max(SidebarDialTuning.railColumnInset(defaults: defaults), 0),
                chipCornerRadius: max(SidebarDialTuning.railChipCornerRadius(defaults: defaults), 0),
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

    /// The selected group's card: the rail column, the same shape in the
    /// expanded list and on the rail (it hugs only the rail column, never
    /// the names panel): horizontal span, the inset above the tile and below
    /// the group's last mark, corner radius, and how far the tile and the
    /// last row's chip sit inside their header and row (the card's top and
    /// bottom are measured from those, not from the frames).
    struct Card: Equatable {
        var minX: CGFloat
        var width: CGFloat
        /// Above the tile.
        var topInset: CGFloat
        /// Below the group's last mark: the last row's chip, or the tile when
        /// the header is alone.
        var verticalInset: CGFloat
        var cornerRadius: CGFloat
        /// The tile's inset from its header's top and bottom.
        var tileTrim: CGFloat
        /// The last row's chip's inset from the row's top and bottom.
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

    // MARK: The tile column (rail stays put)

    /// The tile column's centre, owned by the rail: tiles, chips, glyphs and
    /// the group card sit on it in both states and at every step between.
    var railTileCenterX: CGFloat { railWidth / 2 }

    /// The expanded list's leading edge (`SidebarColumnPadding`), anchored
    /// to the rail's tile column: a row's leading padding, then its tile
    /// slot, puts the slot exactly where the rail draws the tile.
    var listMinX: CGFloat { railTileCenterX - dials.railTileSize / 2 - dials.rowLeadingPadding }
    var listMaxX: CGFloat { expandedWidth - dials.contentPaddingTrailing - dials.columnTrailingPadding }

    /// The tile column's centre in the expanded list: the list's leading
    /// edge, the row's leading padding, then half the tile slot
    /// (`SidebarListRowChrome.glyphSlotWidth`, the tile's side). The rail
    /// tile's centre, by construction.
    var sidebarTileCenterX: CGFloat { listMinX + dials.rowLeadingPadding + dials.railTileSize / 2 }

    /// How far the tile column travels, sidebar to rail: nothing, since
    /// the list is anchored to the rail's column.
    var tileTravel: CGFloat { railTileCenterX - sidebarTileCenterX }

    /// The names panel, right of the rail: the 1pt divider on the rail's
    /// trailing edge (`RailNamesDivider`), then the panel's leading inset,
    /// where every header name and row title starts.
    var namesMinX: CGFloat { railWidth + WorkspaceLayout.railDividerWidth + WorkspaceLayout.namesPanelLeadingInset }

    /// The gap between a tile slot and its labels that puts the labels at
    /// `namesMinX`.
    var labelGap: CGFloat { max(0, namesMinX - (railTileCenterX + dials.railTileSize / 2)) }

    // MARK: Interpolated

    /// The centre x of the project tile, and of every row's chip and glyph
    /// beneath it: the same at every step.
    var tileCenterX: CGFloat { lerp(sidebarTileCenterX, railTileCenterX) }
    var tileSize: CGFloat { dials.railTileSize }
    var chipSize: CGFloat { lerp(dials.sidebarChipSize, dials.railChipSize) }
    var glyphSize: CGFloat { lerp(dials.sidebarGlyphSize, dials.railGlyphSize) }

    /// Row title, subtitle, header name, chevron and count: fully visible
    /// expanded, gone by the midpoint, where `isCollapsedPresentation`
    /// flips. Its timing is the label's own (`MorphLabelFade`), not the
    /// panel's: an animated toggle writes the end value, so this only
    /// shapes the held steps (`applyMorphStep`).
    var labelOpacity: Double { Self.labelOpacity(progress) }
    static func labelOpacity(_ progress: CGFloat) -> Double { Double(min(max(1 - progress * 2, 0), 1)) }

    /// How far a context's chip reaches past its tile on each side when it
    /// is the wider of the two (`RailProjectColumn.chipOverhang`); a header
    /// alone has no chip, so the tile is the outer element.
    private func sideOverhang(tile: CGFloat, chip: CGFloat, hasRows: Bool) -> CGFloat {
        hasRows ? max(0, chip - tile) / 2 : 0
    }

    /// The rail column: the tile (or the wider chip) plus the column inset
    /// on each side, centred on the rail (`RailProjectColumn.columnWidth`).
    func railColumn(hasRows: Bool) -> Card {
        let width = dials.railTileSize
            + (sideOverhang(tile: dials.railTileSize, chip: dials.railChipSize, hasRows: hasRows) + dials.columnInset) * 2
        return Card(
            minX: railTileCenterX - width / 2,
            width: width,
            topInset: dials.columnInset,
            verticalInset: dials.columnInset,
            cornerRadius: dials.chipCornerRadius + dials.columnInset,
            tileTrim: (dials.headerHeight - dials.railTileSize) / 2,
            chipTrim: max(0, (dials.rowHeight - dials.railChipSize) / 2)
        )
    }

    /// The group card at this step: the rail column at every step, so the
    /// card never moves either; the names panel opens beside it.
    func card(hasRows: Bool) -> Card {
        railColumn(hasRows: hasRows)
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

/// A row's chip through the morph: one fixed square at the rail's size in
/// both states, the shape scaled to the sidebar's size and back up (1 at
/// the shipped dials, where both are 40), so the container and the row
/// never resize and the glyph inside stays its own size.
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

/// A row's leading slot: the status glyph at its size for this frame of
/// the morph (the "Thread tile icon" dials, 16 at both ends), over its chip,
/// centred in the tile slot, which sits on the rail's tile column in both
/// states, so it never moves. The chip is one rail-sized square in both
/// states, its shape scaled to this frame's size (`MorphTileScale`), so
/// its frame never resizes and the glyph is never scaled with it.
struct MorphGlyphSlot<Glyph: View>: View, Animatable {
    var progress: CGFloat
    /// The slot's laid-out width: the tile's side.
    let slotWidth: CGFloat
    let glyphSizes: (from: CGFloat, to: CGFloat)
    let chipSizes: (from: CGFloat, to: CGFloat)
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
                    // Hover only: selection is the row's outline
                    // (`SelectedRowOutlineSurface`).
                    isHovered: isHovered, redlineID: chipID
                )
                .morphIdentityProbe(chipID)
            }
    }
}

/// The names panel's left edge on the expanded sidebar (rail stays put,
/// project-icon-tile card 05): a 1pt line on the rail's trailing edge, the
/// height of the list, above the tray. It sits just past the rail's width,
/// so the rail's own clip hides it there; as the panel widens it is the
/// first thing revealed, and the names fade in to its right.
struct RailNamesDivider: View {
    @Environment(\.sidebarRailWidth) private var railWidth
    @ChromeScheme private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            // Measured from the sidebar's leading edge, like the group card.
            let originX = proxy.frame(in: .named(ProjectGroupCard.sidebarSpace)).minX
            Rectangle()
                .fill(ChromeTheme.active(colorScheme).ink(.row))
                .frame(width: WorkspaceLayout.railDividerWidth, height: proxy.size.height)
                .offset(x: railWidth - originX)
                .redlineFrame(RedlineID.railNamesDivider)
        }
        .modifier(MorphTrayReserve())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fades row and header labels out on the way to the rail and back in on
/// the way out of it, as a function of the morph's progress
/// (`WorkspaceLayout.morphFadeWindow`), so they play on the spring's clock
/// and reverse with it: names go by 0.5 of the travel, drifting 4pt left;
/// on the way back they arrive in reading order (`SidebarLabelCascade`),
/// drifting back into place. Reduce Motion: the morph snaps, so the labels
/// fade over 120ms instead, with no drift. Off the expanded sidebar, labels
/// take no clicks.
struct MorphLabelFade: ViewModifier {
    var element: SidebarMorphElement = .names
    /// The label's place in the cascade (`SidebarLabelCascade`).
    var staggerIndex: Int = 0

    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override

    func body(content: Content) -> some View {
        let target = override ?? widthModel.morph
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let effect = Effect(progress: target, element: element, staggerIndex: staggerIndex, reduceMotion: reduceMotion)
        Group {
            if reduceMotion {
                content.modifier(effect)
                    .animation(.easeInOut(duration: WorkspaceLayout.sidebarReducedMotionCrossfadeDuration), value: target)
            } else {
                content.modifier(effect)
            }
        }
        // `morph` is the target as soon as a toggle starts, so labels
        // fading back in stay unclickable until the morph has landed.
        .allowsHitTesting(target == 0 && !widthModel.isMorphing)
    }

    /// The fade at one frame of the morph's progress.
    private struct Effect: ViewModifier, Animatable {
        var progress: CGFloat
        let element: SidebarMorphElement
        let staggerIndex: Int
        let reduceMotion: Bool

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let opacity = WorkspaceLayout.morphFadeOpacity(element: element, progress: progress, staggerIndex: staggerIndex, reduceMotion: reduceMotion)
            content
                .offset(x: WorkspaceLayout.sidebarLabelDrift(opacity: opacity, reduceMotion: reduceMotion))
                .opacity(opacity)
        }
    }
}

/// A folded project's count badge on its rail tile: the labels' fade
/// reversed, as a function of the morph's progress
/// (`WorkspaceLayout.morphFadeWindow`): it shows over 0.55–0.85 of the way
/// to the rail, growing 0.9 → 1, and goes the same way back.
struct MorphRailOnlyFade: ViewModifier {
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override

    func body(content: Content) -> some View {
        let target = override ?? widthModel.morph
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let effect = Effect(progress: target, reduceMotion: reduceMotion)
        if reduceMotion {
            content.modifier(effect)
                .animation(.easeInOut(duration: WorkspaceLayout.sidebarReducedMotionCrossfadeDuration), value: target)
        } else {
            content.modifier(effect)
        }
    }

    private struct Effect: ViewModifier, Animatable {
        var progress: CGFloat
        let reduceMotion: Bool

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let opacity = WorkspaceLayout.morphFadeOpacity(element: .badge, progress: progress, reduceMotion: reduceMotion)
            let window = WorkspaceLayout.morphFadeWindow(element: .badge)
            let scale = reduceMotion ? 1 : window.scaleFrom + (window.scaleTo - window.scaleFrom) * CGFloat(opacity)
            content
                .scaleEffect(scale)
                .opacity(opacity)
        }
    }
}

/// The tray's height as a bottom inset on whatever sits under it: the
/// horizontal bar's on the sidebar, the rail's taller stack on the rail,
/// following the morph's progress frame by frame (`height(progress:railWidth:)`),
/// so it never jumps when a toggle writes its target at t=0 (keyframe spec,
/// defect 2). Never a layout slot under the list: the tray floats over it
/// (Flow 07). On a scroll view (`scrolls`) it is a bottom safe-area inset,
/// so the viewport runs to the panel's bottom, rows scroll under the glass,
/// and the last row's resting place (and any `scrollTo`) clears the tray.
/// On anything else it is plain bottom padding.
struct MorphTrayReserve: ViewModifier {
    var scrolls = false
    /// False, the inset is zero (same view, so toggling it keeps identity).
    var isActive = true
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var override
    /// The rail's width as the tray reads it (`EnvironmentValues.sidebarRailWidth`),
    /// so the inset and the rail tray's pills agree.
    @Environment(\.sidebarRailWidth) private var railWidth
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    /// The inset at `progress`: the horizontal tray's at 0, the rail
    /// stack's at 1, on a straight line between.
    static func height(progress: CGFloat, railWidth: CGFloat) -> CGFloat {
        SidebarMorphMetrics.lerp(
            SidebarTray.reservedHeight(isVertical: false, railWidth: railWidth),
            SidebarTray.reservedHeight(isVertical: true, railWidth: railWidth),
            min(max(progress, 0), 1)
        )
    }

    func body(content: Content) -> some View {
        content.modifier(Inset(progress: override ?? widthModel.morph, railWidth: railWidth, scrolls: scrolls, isActive: isActive))
    }

    /// Interpolates `progress` on the toggle's transaction, so the inset
    /// is read per frame, not at the target.
    private struct Inset: ViewModifier, Animatable {
        var progress: CGFloat
        let railWidth: CGFloat
        let scrolls: Bool
        let isActive: Bool

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        @ViewBuilder
        func body(content: Content) -> some View {
            let height = isActive ? MorphTrayReserve.height(progress: progress, railWidth: railWidth) : 0
            if scrolls {
                content.safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: height).accessibilityHidden(true)
                }
            } else {
                content.padding(.bottom, height)
            }
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
            // The list anchors its tile column to the rail's centre
            // (`SidebarColumnPadding`): this tree's own rail, wherever it is
            // hosted.
            .environment(\.sidebarRailWidth, model.railWidth)
            .frame(width: model.expandedWidth)
            // Every frame top-leading: a frame narrower than its child
            // centres it by default, which would slide the whole list left
            // as the panel narrows.
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(width: model.width, alignment: .topLeading)
            .clipShape(Rectangle())
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
