import SwiftUI
import Combine
import GhosttiesCore

// MARK: - Project column

/// One view's selection (Sean, 2026-10-08, strawman C; option D,
/// 2026-10-09; rail stays put, 2026-10-22): the selected session's project
/// sits on one card round the rail's tile column, tile through its last
/// row, the same in the expanded list and on the rail (`ProjectGroupCard`);
/// its tile is filled with ink. Every session row, grouped or not, and
/// History, is marked by a tile-sized chip behind its glyph, in both.
///
/// Every value below is a "Rail column" dial (`SidebarDialTuning`); the
/// `default…` constants are what ships, and what each dial reads unset.
enum RailProjectColumn {
    /// The chip (thread tile) defaults to the project tile's side and
    /// corner (`RailProjectTile.defaultSize`, `RailProjectTile.cornerRadius`),
    /// so chip and tile read as one family, in both states: nothing
    /// resizes across the morph.
    static let defaultThreadTileSize: CGFloat = RailProjectTile.defaultSize
    /// The rail's chip, unset: the same tile side.
    static let defaultRailThreadTileSize: CGFloat = RailProjectTile.defaultSize
    /// The sidebar's status glyph inside its chip, unset (Sean, 2026-10-10:
    /// the 8pt grid). Not "Row ghost size", which the Sessions rows keep.
    static let defaultSidebarThreadTileIcon: CGFloat = 16
    /// The rail's status glyph inside its chip, unset: the sidebar's 16pt
    /// glyph in the rail's larger chip (Sean, 2026-10-10).
    static let defaultRailThreadTileIcon: CGFloat = 16
    static let defaultChipCornerRadius: CGFloat = RailProjectTile.cornerRadius
    /// The rail column: the tile plus this margin on every side (option D:
    /// 4, a 38pt column round the 30pt tile).
    static let defaultColumnInset: CGFloat = 4
    /// The "Column tint" dial's default: the dark flat fill the glass card
    /// replaced (`ProjectGroupCardGlass`); the Colors panel's contrast
    /// readout still reads it.
    static let defaultColumnTintOpacity: Double = 0.04
    /// The light flat fill's lift the glass card replaced; the Colors
    /// panel's contrast readout still reads it.
    static let lightColumnLiftOpacity: Double = 0.45
    /// The selected project's tile: 1 is full ink, 0 the plain tile tint.
    static let defaultSelectedTileFill: Double = 1
    /// The selected chip's fill (option D `#0000001A`). Flat: no chromatic
    /// rim.
    static let selectedChipTintOpacity: Double = 0.10
    /// The selected row's fill: `ink` at `selectedChipTintOpacity` in light,
    /// black at the same opacity in dark. White over the dark glass card
    /// fails AA for `inkSecondary` (3.35:1); black keeps it at 4.98:1.
    static func selectedChipTint(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.black : tintInk(scheme)).opacity(selectedChipTintOpacity)
    }
    /// A hovered, unselected chip's fill: subordinate to the selected tint.
    static let hoverChipTintOpacity: Double = 0.04

    /// The chip's side, one size in both contexts (rail stays put, so a chip
    /// never resizes across the morph): the rail's "Thread tile size",
    /// clamped to the row height so the chip never spills out of its row.
    static func chipSize(_: SidebarTileContext) -> CGFloat {
        min(max(SidebarDialTuning.railThreadTileSize(), 0), SidebarDialTuning.rowHeight())
    }
    /// The status glyph inside a chip: `context`'s "Thread tile icon".
    static func chipGlyphSize(_ context: SidebarTileContext) -> CGFloat {
        switch context {
        case .sidebar: max(SidebarDialTuning.sidebarThreadTileIcon(), 0)
        case .rail: max(SidebarDialTuning.railThreadTileIcon(), 0)
        }
    }
    static var chipCornerRadius: CGFloat { max(SidebarDialTuning.railChipCornerRadius(), 0) }
    static var columnInset: CGFloat { max(SidebarDialTuning.railColumnInset(), 0) }
    static var columnTintOpacity: Double { min(max(SidebarDialTuning.railColumnTintOpacity(), 0), 1) }
    static var selectedTileFill: Double { min(max(SidebarDialTuning.railSelectedTileFill(), 0), 1) }
    /// The column's corner, concentric with the chip inside it (option D:
    /// 8 + 4 = 12). The expanded group card takes the same corner.
    static var columnCornerRadius: CGFloat { chipCornerRadius + columnInset }

    /// The ink the chip tints are laid in: solid black in
    /// light, white in dark (`ChromeTheme.ink`), so an opacity here is the
    /// canvas's alpha. (`Color.primary` is 85% black in light, which drew
    /// option D's 10% chip at 8.5%.)
    static func tintInk(_ colorScheme: ColorScheme) -> Color {
        Color(ChromeTheme.active(colorScheme).ink)
    }

    /// The group the column marks: the one holding the selected session,
    /// or none (nothing selected, or the selection is pinned).
    static func selectedGroupId(_ groups: [SidebarProjectGroup], selectedSessionId: UUID?) -> SidebarProjectGroup.ID? {
        guard let selectedSessionId else { return nil }
        return groups.first { group in group.sessions.contains { $0.id == selectedSessionId } }?.id
    }

    /// How far the chip reaches past the tile on each side when the
    /// thread tile is the wider of the two; 0 when the project tile is.
    static func chipOverhang(_ context: SidebarTileContext) -> CGFloat {
        max(0, chipSize(context) - RailProjectTile.size) / 2
    }

    /// The overhang the card's or column's side gaps are measured past the
    /// tile slot: the chip's when the group shows rows; a header alone has
    /// no chip, so the tile is the outer element.
    static func sideOverhang(anchorCount: Int, context: SidebarTileContext) -> CGFloat {
        anchorCount > 1 ? chipOverhang(context) : 0
    }

    /// The rail column's width: the wider of the rail's tile and chip, plus
    /// `inset` on each side.
    static func columnWidth(anchorCount: Int, inset: CGFloat) -> CGFloat {
        RailProjectTile.size + (sideOverhang(anchorCount: anchorCount, context: .rail) + inset) * 2
    }

    /// The column's vertical extent around its anchors' union, the same
    /// expanded and on the rail: `inset` above the tile; below, `inset` past
    /// the last row's chip, or below the tile when the header is alone
    /// (Sean, 2026-10-09).
    static func verticalExtent(union: CGRect, anchorCount: Int, inset: CGFloat) -> ClosedRange<CGFloat> {
        let tileTrim = (ProjectAccordionHeader.height - RailProjectTile.size) / 2
        let chipTrim = max(0, (SidebarDialTuning.rowHeight() - chipSize(.rail)) / 2)
        let top = union.minY + tileTrim - inset
        let bottom = anchorCount <= 1 ? union.maxY - tileTrim + inset : union.maxY - chipTrim + inset
        return top...max(top, bottom)
    }
}

/// The bounds of every item in each project group whose card is lit or
/// fading, by group: the rail's column and the expanded list's group card
/// both read it.
struct RailGroupColumnKey: PreferenceKey {
    static var defaultValue: [SidebarProjectGroup.ID: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [SidebarProjectGroup.ID: [Anchor<CGRect>]], nextValue: () -> [SidebarProjectGroup.ID: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

extension View {
    @ViewBuilder
    func railGroupColumn(_ group: SidebarProjectGroup.ID, isLit: Bool) -> some View {
        if isLit {
            anchorPreference(key: RailGroupColumnKey.self, value: .bounds) { [group: [$0]] }
        } else {
            self
        }
    }
}

/// The selected project's group card (option D; rail stays put): one
/// rounded, faintly tinted rect behind the group's tile and its rows'
/// chips, hugging only the rail's tile column: the tile (or wider chip)
/// plus `railColumnInset` each side, centred on the rail, at the chip's
/// corner plus the inset. The same shape expanded and on the rail
/// (`SidebarMorphMetrics.card`); the names panel opens beside it.
struct ProjectGroupCard: View {
    /// The sidebar's own coordinate space, named on its root
    /// (`SidebarHostRoot`): x = 0 at the sidebar's leading edge, wherever
    /// the sidebar sits in the window. Hosts without it (previews, render
    /// tests) fall back to `.global`, where the two coincide.
    static let sidebarSpace = "ghostties.sidebar"

    /// Re-renders on every dial write; the body reads the column dials.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    /// Each lit or fading group's laid-out items.
    let groups: [SidebarProjectGroup.ID: [Anchor<CGRect>]]
    /// The selected session's group: its card carries the Redlines tag.
    let selected: SidebarProjectGroup.ID?

    var body: some View {
        let metrics = widthModel.metrics(morphOverride ?? widthModel.morph, dials: morphDials)
        GeometryReader { proxy in
            ForEach(groups.keys.sorted(), id: \.self) { id in
                if let anchors = groups[id], let first = anchors.first {
                    let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                    // The card's opacity: 1 at rest on the selected group,
                    // cross-fading between groups on a project switch.
                    SelectedRowMixGroupReader(id: id, fallback: 1) { card in
                        ProjectGroupCardShape(
                            metrics: metrics,
                            progress: metrics.progress,
                            hasRows: anchors.count > 1,
                            unionMinY: union.minY,
                            unionMaxY: union.maxY,
                            originX: proxy.frame(in: .named(Self.sidebarSpace)).minX,
                            isPrimary: id == selected
                        )
                        .opacity(card)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The card at one step of the morph: `SidebarMorphMetrics.card` at this
/// frame's progress for its span, inset and trims, set round the group's
/// laid-out tile and last row.
private struct ProjectGroupCardShape: View, Animatable {
    /// The ends (dials and widths); its own progress is not used.
    let metrics: SidebarMorphMetrics
    var progress: CGFloat
    let hasRows: Bool
    /// The group's laid-out top and bottom, in the card's local space.
    let unionMinY: CGFloat
    let unionMaxY: CGFloat
    /// The local space's x from the sidebar's leading edge, where the
    /// metrics measure from.
    let originX: CGFloat
    /// The selected group's card: the one Redlines and the morph probe tag.
    let isPrimary: Bool

    @ChromeScheme private var colorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let card = SidebarMorphMetrics(
            dials: metrics.dials, expandedWidth: metrics.expandedWidth, railWidth: metrics.railWidth, progress: progress
        ).card(hasRows: hasRows)
        let top = unionMinY + card.tileTrim - card.topInset
        let bottom = max(top, unionMaxY - (hasRows ? card.chipTrim : card.tileTrim) + card.verticalInset)
        ProjectGroupCardGlass(cornerRadius: card.cornerRadius)
            .frame(width: card.width, height: bottom - top)
            .redlineFrame(isPrimary ? RedlineID.groupCard : nil)
            .morphIdentityProbe(isPrimary ? RedlineID.groupCard : nil)
            .position(x: card.minX - originX + card.width / 2, y: (top + bottom) / 2)
    }
}

/// The active-group card's material (r8 05's glass, contract "Glass"), in
/// tokens over the chrome. Dark: `ink` 11% at the top to 6% at the bottom
/// (the mock's 12% top stop leaves `inkSecondary` under the header at
/// 4.39:1; 11% keeps it at AA), a 1px inner top highlight of `ink` at 16%,
/// a 0.5pt inner hairline of `ink` at 8%, a `0 2 12` glow of `shadow` at
/// 6%. Light: `canvas` 90% to 55%, a 1px `canvas` top highlight, a 0.5pt
/// `ink` hairline at 6%, a `0 2 12` shadow of `shadow` at 8%. The mock's
/// backdrop blur is invisible over the flat chrome, so it is left out.
struct ProjectGroupCardGlass: View {
    let cornerRadius: CGFloat

    @ChromeScheme private var colorScheme

    /// The dark gradient's top stop: the mock's 12% less the AA margin.
    static let darkTopStop: Double = 0.11

    private struct Stops {
        let top: Color, bottom: Color, highlight: Color, hairline: Color, shadow: Color
    }

    private static func stops(_ theme: ChromeTheme) -> Stops {
        let ink = Color(theme.ink), canvas = Color(theme.canvas), shadow = Color(theme.shadow)
        return theme.polarity == .dark
            ? Stops(top: ink.opacity(darkTopStop), bottom: ink.opacity(0.06), highlight: ink.opacity(0.16),
                    hairline: ink.opacity(0.08), shadow: shadow.opacity(0.06))
            : Stops(top: canvas.opacity(0.9), bottom: canvas.opacity(0.55), highlight: canvas,
                    hairline: ink.opacity(0.06), shadow: shadow.opacity(0.08))
    }

    /// The card's top stop over the chrome, opaque: the worst case for the
    /// muted text under its header, and the colour that stands for the
    /// card wherever one flat colour must.
    static func representative(_ scheme: ColorScheme) -> NSColor {
        let theme = ChromeTheme.active(scheme)
        let chrome = theme.chrome.usingColorSpace(.sRGB) ?? theme.chrome
        let (fill, alpha) = theme.polarity == .dark ? (theme.ink, darkTopStop) : (theme.canvas, 0.9)
        let top = fill.usingColorSpace(.sRGB) ?? fill
        func over(_ f: CGFloat, _ b: CGFloat) -> CGFloat { f * alpha + b * (1 - alpha) }
        return NSColor(
            srgbRed: over(top.redComponent, chrome.redComponent),
            green: over(top.greenComponent, chrome.greenComponent),
            blue: over(top.blueComponent, chrome.blueComponent), alpha: 1
        )
    }

    var body: some View {
        let stops = Self.stops(ChromeTheme.active(colorScheme))
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [stops.top, stops.bottom], startPoint: .top, endPoint: .bottom))
            // Inner top highlight: the shape less itself 1pt lower.
            .overlay {
                GlassRimShape(cornerRadius: cornerRadius, kind: .topHighlight)
                    .fill(stops.highlight, style: FillStyle(eoFill: true))
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(stops.hairline, lineWidth: 0.5) }
            // An outer shadow only, as CSS draws it: the glow, masked to
            // outside the shape (the fill is translucent, so a shadow of it
            // would be too).
            .background {
                shape.fill(Color.black)
                    .shadow(color: stops.shadow, radius: 6, x: 0, y: 2)
                    .mask {
                        GlassRimShape(cornerRadius: cornerRadius, kind: .outside)
                            .fill(style: FillStyle(eoFill: true))
                    }
            }
    }
}

/// Even-odd regions for the glass's rim, so nothing needs a blend mode
/// (offscreen renders draw `.destinationOut` as solid black).
private struct GlassRimShape: Shape {
    enum Kind { case topHighlight, outside }
    let cornerRadius: CGFloat
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        var path = shape.path(in: rect)
        switch kind {
        case .topHighlight:
            path.addPath(shape.path(in: rect.offsetBy(dx: 0, dy: 1)))
        case .outside:
            path.addRect(rect.insetBy(dx: -24, dy: -24))
        }
        return path
    }
}

/// A session row's (and History's) hover mark (option D), in the
/// expanded list and the rail alike: a tile-sized chip behind its glyph,
/// the row's hover tint, fading in and out on the hover spring, never
/// overshooting. Selection is the row's outline (`SelectedRowOutlineSurface`).
/// Reduce Motion: it snaps.
struct SidebarRowChipBackground: View {
    /// The chip's container: the rail's chip side (`RailProjectColumn.chipSize`).
    let size: CGFloat
    /// The shape's scale inside it at this step of the morph
    /// (`MorphTileScale`): the sidebar's chip over the rail's at 0, 1 on the
    /// rail.
    var scale: CGFloat = 1
    let isHovered: Bool
    /// DEBUG Redlines tag for the chip's frame.
    var redlineID: String? = nil

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius, style: .continuous)
        // Carries the Redlines tag: always present.
        shape.fill(Color.primary.opacity(isHovered ? RailProjectColumn.hoverChipTintOpacity : 0))
            .frame(width: size, height: size)
            // Inside the scale, so Redlines reports the drawn chip.
            .redlineFrame(redlineID)
            .scaleEffect(scale)
            .animation(SidebarUISpring.hover.settle(), value: isHovered)
    }
}

// MARK: - Rail keyboard scroll

/// On the rail, scrolls the list to the selected session when the
/// selection moved by keyboard (Next/Previous Session, Cmd+1-9), so a
/// selection cycled past the clip edge comes into view; instantly, since
/// keyboard actions don't animate (motion spec, "stays still"). A click
/// selects a row that is already visible, so it doesn't scroll. Scrolls the
/// least distance (`anchor: nil`). The expanded list leaves scrolling to
/// the user, as before.
struct RailScrollToKeyboardSelection: ViewModifier {
    let selectedSessionId: UUID?
    let window: () -> NSWindow?
    let scrollProxy: ScrollViewProxy

    @State private var keyboardMovedSelection = false
    @EnvironmentObject private var widthModel: SidebarWidthModel

    func body(content: Content) -> some View {
        content
            .onReceive(Self.keyboardSelection) { note in
                guard let target = note.object as? NSWindow, target === window() else { return }
                keyboardMovedSelection = true
            }
            .onChange(of: selectedSessionId) { id in
                guard keyboardMovedSelection else { return }
                keyboardMovedSelection = false
                guard let id, widthModel.isCollapsedPresentation else { return }
                // The list's row ids are uuid strings (`SidebarProjectGroupItem.id`).
                scrollProxy.scrollTo(id.uuidString)
            }
    }

    /// The notifications the session shortcuts post, with the window.
    private static let keyboardSelection = NotificationCenter.default.publisher(for: .workspaceSelectNextSession)
        .merge(with: NotificationCenter.default.publisher(for: .workspaceSelectPreviousSession))
        .merge(with: NotificationCenter.default.publisher(for: .workspaceFocusSessionAtIndex))
}
