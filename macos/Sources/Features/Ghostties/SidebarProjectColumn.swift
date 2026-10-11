import SwiftUI
import Combine
import GhosttiesCore

// MARK: - Project column

/// One view's selection (Sean, 2026-10-08, strawman C; option D,
/// 2026-10-09): the selected session's project sits on a card the full row
/// width in the expanded list, which narrows into a column on the rail, tile
/// through its last row (`ProjectGroupCard`); its tile is filled with ink.
/// Every session row, grouped or not, and History, is marked by a
/// tile-sized chip behind its glyph, in both.
///
/// Every value below is a "Rail column" dial (`SidebarDialTuning`); the
/// `default…` constants are what ships, and what each dial reads unset.
enum RailProjectColumn {
    /// The chip (thread tile) defaults to the monogram tile's side and
    /// corner (`RailProjectTile.defaultSize`, `RailProjectTile.cornerRadius`),
    /// so chip and tile read as one family.
    static let defaultThreadTileSize: CGFloat = RailProjectTile.defaultSize
    /// The rail's chip, unset: the rail's tile (`RailProjectTile.defaultRailSize`).
    static let defaultRailThreadTileSize: CGFloat = RailProjectTile.defaultRailSize
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
    /// The column's and the expanded group card's faint fill (option D
    /// `#0000000F`).
    static let defaultColumnTintOpacity: Double = 0.06
    /// The selected project's tile: 1 is full ink, 0 the plain tile tint.
    static let defaultSelectedTileFill: Double = 1
    /// The selected chip's fill (option D `#0000001A`). Flat: no chromatic
    /// rim.
    static let selectedChipTintOpacity: Double = 0.10
    /// A hovered, unselected chip's fill: subordinate to the selected tint.
    static let hoverChipTintOpacity: Double = 0.04

    /// `context`'s "Thread tile size", clamped to the row height so the
    /// chip never spills out of its row.
    static func chipSize(_ context: SidebarTileContext) -> CGFloat {
        let size = switch context {
        case .sidebar: SidebarDialTuning.sidebarThreadTileSize()
        case .rail: SidebarDialTuning.railThreadTileSize()
        }
        return min(max(size, 0), SidebarDialTuning.rowHeight())
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

    /// The ink the column, card and chip tints are laid in: solid black in
    /// light, white in dark, so an opacity here is the canvas's alpha.
    /// (`Color.primary` is 85% black in light, which drew option D's 10%
    /// chip at 8.5%.)
    static func tintInk(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
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
        max(0, chipSize(context) - RailProjectTile.size(context)) / 2
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
        RailProjectTile.size(.rail) + (sideOverhang(anchorCount: anchorCount, context: .rail) + inset) * 2
    }

    /// The column's or card's vertical extent around its anchors' union:
    /// `inset` above the tile and `inset` below the last row's chip (below
    /// the tile when the header is alone), so with the side gaps the card
    /// is inset from the tile and chips on all four sides (Sean, 2026-10-09,
    /// over option D's "runs past the last row").
    static func verticalExtent(union: CGRect, anchorCount: Int, inset: CGFloat, context: SidebarTileContext) -> ClosedRange<CGFloat> {
        let tileTrim = (ProjectAccordionHeader.height(context) - RailProjectTile.size(context)) / 2
        let chipTrim = max(0, (SidebarDialTuning.rowHeight() - chipSize(context)) / 2)
        let top = union.minY + tileTrim - inset
        let bottom = union.maxY - (anchorCount > 1 ? chipTrim : tileTrim) + inset
        return top...max(top, bottom)
    }
}

/// The bounds of every item in the selected project's group: the rail's
/// column and the expanded list's group card both read it.
struct RailGroupColumnKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

extension View {
    @ViewBuilder
    func railGroupColumn(_ isInColumn: Bool) -> some View {
        if isInColumn {
            anchorPreference(key: RailGroupColumnKey.self, value: .bounds) { [$0] }
        } else {
            self
        }
    }
}

/// The selected project's group card (option D) and, on the rail, its
/// column: one rounded, faintly tinted rect behind the group's tile and
/// rows, inset from the tile and chips on all four sides, at the chip's
/// corner plus the inset. Expanded it spans the row width, `groupCardInset`
/// past the wider of tile and chip; on the rail it is the tile (or wider
/// chip) plus `railColumnInset` each side, centred on the rail. Between the
/// two it narrows on a straight line, every edge at once
/// (`SidebarMorphMetrics.card`), so collapsing reads as one shape.
struct ProjectGroupCard: View {
    /// Re-renders on every dial write; the body reads the column dials.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @Environment(\.sidebarMorphOverride) private var morphOverride
    @Environment(\.sidebarMorphDials) private var morphDials
    let anchors: [Anchor<CGRect>]

    /// How far the expanded card reaches past the row frames on each side:
    /// the card inset, less the row's own leading padding before its tile
    /// slot, plus the chip's overhang past that slot
    /// (`RailProjectColumn.sideOverhang`).
    static func horizontalOutset(cardInset: CGFloat, rowLeadingPadding: CGFloat, chipOverhang: CGFloat) -> CGFloat {
        cardInset - rowLeadingPadding + chipOverhang
    }

    /// The expanded card's overhang past the column's trailing edge, the
    /// widest it gets (with the chip's overhang): the room the list and the
    /// sidebar's clip leave for it.
    static func trailingBleed() -> CGFloat {
        max(0, horizontalOutset(
            cardInset: SidebarDialTuning.groupCardInset(),
            rowLeadingPadding: SidebarDialTuning.rowLeadingPadding(),
            chipOverhang: RailProjectColumn.chipOverhang(.sidebar)
        ))
    }

    var body: some View {
        let metrics = widthModel.metrics(morphOverride ?? widthModel.morph, dials: morphDials)
        GeometryReader { proxy in
            if let first = anchors.first {
                let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                ProjectGroupCardShape(
                    metrics: metrics,
                    progress: metrics.progress,
                    hasRows: anchors.count > 1,
                    unionMinY: union.minY,
                    unionMaxY: union.maxY,
                    originX: proxy.frame(in: .global).minX
                )
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

    @Environment(\.colorScheme) private var colorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let card = SidebarMorphMetrics(
            dials: metrics.dials, expandedWidth: metrics.expandedWidth, railWidth: metrics.railWidth, progress: progress
        ).card(hasRows: hasRows)
        let top = unionMinY + card.tileTrim - card.verticalInset
        let bottom = max(top, unionMaxY - (hasRows ? card.chipTrim : card.tileTrim) + card.verticalInset)
        RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
            .fill(RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.columnTintOpacity))
            .frame(width: card.width, height: bottom - top)
            .redlineFrame(RedlineID.groupCard)
            .morphIdentityProbe(RedlineID.groupCard)
            .position(x: card.minX - originX + card.width / 2, y: (top + bottom) / 2)
    }
}

/// A session row's (and History's) selection and hover mark (option D), in
/// the expanded list and the rail alike: a tile-sized chip behind its glyph,
/// flat (`RailProjectColumn.selectedChipTintOpacity`), no chromatic rim;
/// hover is the row's hover tint.
///
/// Motion (`SidebarUISpring`): hover fades in and out on the hover spring,
/// never overshooting; a new selection's chip travels from the previously
/// selected row on the `.move` spring when the list provides a namespace
/// (`sidebarSelectionChipNamespace`), else it appears in place. Reduce
/// Motion: both snap.
struct SidebarRowChipBackground: View {
    /// The chip's container: the rail's chip side (`RailProjectColumn.chipSize`).
    let size: CGFloat
    /// The shape's scale inside it at this step of the morph
    /// (`MorphTileScale`): the sidebar's chip over the rail's at 0, 1 on the
    /// rail.
    var scale: CGFloat = 1
    let isActive: Bool
    let isHovered: Bool
    /// DEBUG Redlines tag for the chip's frame.
    var redlineID: String? = nil

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarSelectionChipNamespace) private var selectionNamespace

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius, style: .continuous)
        ZStack {
            // Hover keeps the row hover's `.primary` tint, under the
            // selection. Carries the Redlines tag: always present, same
            // frame as the selection.
            // A tint: it settles on either change, never riding the
            // selection's bounce.
            face(shape.fill(Color.primary.opacity(isHovered && !isActive ? RailProjectColumn.hoverChipTintOpacity : 0)), redlineID: redlineID)
                .animation(SidebarUISpring.hover.settle(), value: isHovered)
                .animation(SidebarUISpring.move.settle(), value: isActive)
            // Selection: the canvas's alpha on solid ink. Matched outside
            // the morph's scale, so the travel is exact at any scale. Only
            // its geometry bounces; its fade in and out settles.
            if isActive {
                face(shape.fill(RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.selectedChipTintOpacity)), redlineID: nil)
                    .modifier(SelectionChipTravel(namespace: selectionNamespace))
                    .transition(AnyTransition.opacity.animation(SidebarUISpring.move.settle()))
            }
        }
        .animation(SidebarUISpring.move.animation(), value: isActive)
    }

    private func face(_ fill: some View, redlineID: String?) -> some View {
        fill
            .frame(width: size, height: size)
            // Inside the scale, so Redlines reports the drawn chip.
            .redlineFrame(redlineID)
            .scaleEffect(scale)
    }
}

/// The selected chip's travel between rows: one matched geometry across the
/// list's rows, so the chip leaving the old row and the one arriving in the
/// new row are one moving chip.
private struct SelectionChipTravel: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: SidebarUISpring.selectionChipID, in: namespace)
        } else {
            content
        }
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
