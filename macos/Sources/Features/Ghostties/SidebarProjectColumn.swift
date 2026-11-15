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
    /// The column's and the expanded group card's fill in dark: white at
    /// this opacity over the chrome (beta.26 sidebar contrast, was 6%).
    /// The "Column tint" dial.
    static let defaultColumnTintOpacity: Double = 0.04
    /// The column's and the expanded group card's fill in light: a lift,
    /// white at this opacity over the chrome (beta.26 sidebar contrast,
    /// was a 6% black shade), so secondary text
    /// reads on it at the same contrast as on the chrome.
    static let lightColumnLiftOpacity: Double = 0.45
    /// The selected project's tile: 1 is full ink, 0 the plain tile tint.
    static let defaultSelectedTileFill: Double = 1
    /// The selected chip's fill (option D `#0000001A`). Flat: no chromatic
    /// rim.
    static let selectedChipTintOpacity: Double = 0.10
    /// The selected row's fill: `ink` at `selectedChipTintOpacity` in light,
    /// black at the same opacity in dark. White over the dark group card
    /// fails AA for `inkSecondary` (4.14:1); black keeps it at 6.03:1.
    static func selectedChipTint(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.black : tintInk(scheme)).opacity(selectedChipTintOpacity)
    }
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

    /// The column's and the expanded group card's fill: white in both
    /// appearances, a lift over the chrome, at `columnFillOpacity`.
    static func columnFill(_ colorScheme: ColorScheme) -> Color {
        Color.white.opacity(columnFillOpacity(colorScheme))
    }
    /// `columnFill`'s opacity: the light lift, or the dark "Column tint" dial.
    static func columnFillOpacity(_ colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? columnTintOpacity : lightColumnLiftOpacity
    }

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
    /// `inset` above the tile; below, `inset` past the last row's chip on
    /// the rail, `ProjectGroupCard.plateGap` past the last row's frame (the
    /// plate's box) expanded, and `inset` below the tile when the header is
    /// alone (Sean, 2026-10-09; the expanded bottom, Amendment 5, 2026-10-20).
    static func verticalExtent(union: CGRect, anchorCount: Int, inset: CGFloat, context: SidebarTileContext) -> ClosedRange<CGFloat> {
        let tileTrim = (ProjectAccordionHeader.height(context) - RailProjectTile.size(context)) / 2
        let chipTrim = max(0, (SidebarDialTuning.rowHeight() - chipSize(context)) / 2)
        let top = union.minY + tileTrim - inset
        let bottom: CGFloat
        if anchorCount <= 1 {
            bottom = union.maxY - tileTrim + inset
        } else if context == .sidebar {
            bottom = union.maxY + ProjectGroupCard.plateGap
        } else {
            bottom = union.maxY - chipTrim + inset
        }
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

/// The selected project's group card (option D) and, on the rail, its
/// column: one rounded, faintly tinted rect behind the group's tile and
/// rows, inset from the tile and chips on all four sides, at the chip's
/// corner plus the inset. Expanded it wraps the row frames by `plateGap`
/// at the sides and the bottom (concentric with the selected-row plate) and
/// sits `groupCardInset` above the tile; on the rail it is the tile (or wider
/// chip) plus `railColumnInset` each side, centred on the rail. Between the
/// two it narrows on a straight line, every edge at once
/// (`SidebarMorphMetrics.card`), so collapsing reads as one shape.
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

    /// The expanded card's gap round the selected-row plate, whose box is
    /// the whole row frame: at the sides and the bottom, so the card's
    /// corner (plate radius 8 + 4 = 12) is concentric with the plate's
    /// (contract Amendment 5). The rail column's `columnInset` is its gap.
    static let plateGap: CGFloat = 4

    /// How far the expanded card reaches past the row frames on each side:
    /// with rows, the plate gap (the plate is the row frame); a header
    /// alone, the card inset round its tile, less the row's own leading
    /// padding before the tile slot.
    static func horizontalOutset(hasRows: Bool, cardInset: CGFloat, rowLeadingPadding: CGFloat) -> CGFloat {
        hasRows ? plateGap : cardInset - rowLeadingPadding
    }

    /// The expanded card's overhang past the column's trailing edge, the
    /// widest it gets: the room the list and the sidebar's clip leave for it.
    static func trailingBleed() -> CGFloat {
        let cardInset = SidebarDialTuning.groupCardInset(), lead = SidebarDialTuning.rowLeadingPadding()
        return max(0, horizontalOutset(hasRows: true, cardInset: cardInset, rowLeadingPadding: lead),
                   horizontalOutset(hasRows: false, cardInset: cardInset, rowLeadingPadding: lead))
    }

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
        RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
            .fill(RailProjectColumn.columnFill(colorScheme))
            .frame(width: card.width, height: bottom - top)
            .redlineFrame(isPrimary ? RedlineID.groupCard : nil)
            .morphIdentityProbe(isPrimary ? RedlineID.groupCard : nil)
            .position(x: card.minX - originX + card.width / 2, y: (top + bottom) / 2)
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

// MARK: - Following the selection

/// What the list does when the selection changes: which project unfolds
/// and which row scrolls into view. Rows never reorder: a project's
/// threads stay in the user's order.
enum SidebarSelectionFollow {
    /// How the selection moved.
    enum Route: Equatable {
        /// A click, the composer, the CLI, a new or resumed session.
        case direct
        /// Next/Previous Session or Cmd+1-9.
        case keyboard
    }

    struct Plan: Equatable {
        /// The folded project to unfold, so the selected row exists.
        var unfold: UUID?
        /// The row to scroll into view (`SidebarProjectGroupItem.id`).
        var scrollTo: String?
        /// Keyboard moves don't animate (motion spec, "stays still").
        var animates = false
    }

    /// The rows the list draws, and which projects are folded.
    struct Rows: Equatable {
        var pinned: [AgentSession] = []
        var active: [AgentSession] = []
        var collapsed: Set<UUID> = []
    }

    /// One view follows every selection. The tabs layout keeps what it had:
    /// only the rail scrolls, and only for a keyboard move.
    static func plan(
        layout: SidebarProjectsLayout, route: Route, selected: UUID?, rows: Rows, isRail: Bool
    ) -> Plan {
        guard let selected else { return Plan() }
        guard layout == .oneView else {
            return Plan(scrollTo: route == .keyboard && isRail ? selected.uuidString : nil)
        }
        let animates = route == .direct
        if rows.pinned.contains(where: { $0.id == selected }) {
            return Plan(scrollTo: selected.uuidString, animates: animates)
        }
        // A session with no row (History's, or one whose terminal closed)
        // has nothing to scroll to.
        guard let session = rows.active.first(where: { $0.id == selected }) else { return Plan() }
        return Plan(
            unfold: rows.collapsed.contains(session.projectId) ? session.projectId : nil,
            scrollTo: selected.uuidString,
            animates: animates
        )
    }

    /// Clear space a followed row keeps above the tray (or whatever ends
    /// the list's viewport).
    static let trayClearance: CGFloat = 8

    /// The id one view scrolls to for the row `rowId`: its `ScrollTarget`,
    /// not the row itself.
    static func scrollTargetId(row rowId: String) -> String { "follow.\(rowId)" }

    /// A row's scroll target, as its background: the row's frame reaching
    /// `trayClearance` past its bottom edge, so scrolling the least distance
    /// that shows the target rests the row that far above the tray. Takes
    /// no room and no clicks. The selected row's also reports where it is
    /// (`SelectedTargetFrameKey`), for `KeepClear`.
    struct ScrollTarget: View {
        let rowId: String
        var isSelected = false

        var body: some View {
            Color.clear
                .id(SidebarSelectionFollow.scrollTargetId(row: rowId))
                .padding(.bottom, -SidebarSelectionFollow.trayClearance)
                .background {
                    if isSelected {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SelectedTargetFrameKey.self,
                                value: SelectedTargetFrame(
                                    rowId: rowId,
                                    contentMinY: proxy.frame(in: .named(SidebarSelectionFollow.contentSpace)).minY,
                                    viewport: proxy.frame(in: .named(SidebarSelectionFollow.viewportSpace))
                                )
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Keeping the selected row clear

    /// The list's content, inside the scroll view: a frame in it moves
    /// only when the list's layout does, never on a scroll.
    static let contentSpace = "ghostties.sidebar.list.content"
    /// The scroll view: a frame in it is where a row is on screen.
    static let viewportSpace = "ghostties.sidebar.list.viewport"

    /// The selected row, as laid out.
    struct SelectedTargetFrame: Equatable {
        var rowId: String
        /// Its top in `contentSpace`.
        var contentMinY: CGFloat
        /// Its frame in `viewportSpace`: the row's own, without the
        /// clearance its scroll target adds below it.
        var viewport: CGRect
    }

    struct SelectedTargetFrameKey: PreferenceKey {
        static var defaultValue: SelectedTargetFrame?
        static func reduce(value: inout SelectedTargetFrame?, nextValue: () -> SelectedTargetFrame?) {
            value = value ?? nextValue()
        }
    }

    /// The scroll view's height above the tray: its safe area, which the
    /// tray's reserve insets (`MorphTrayReserve`).
    struct ViewportHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Where the selected row's scroll target sits: in the list's layout,
    /// and on screen.
    struct Placement: Equatable {
        var rowId: String
        /// The target's top in the list's content (`contentSpace`).
        var contentMinY: CGFloat
        /// The target's top and bottom in the viewport (`viewportSpace`);
        /// the bottom is `trayClearance` below the row's.
        var minY: CGFloat
        var maxY: CGFloat
        /// The viewport's height above the tray.
        var visibleHeight: CGFloat

        static let tolerance: CGFloat = 0.5
        /// The least change that counts as the layout moving the row. Far
        /// under a point: an animated growth arrives in steps smaller than
        /// `tolerance`, and each one is still the layout's doing.
        static let layoutEpsilon: CGFloat = 0.01

        /// The whole row is in view, `trayClearance` clear of the tray.
        var isClear: Bool { minY >= -Self.tolerance && maxY <= visibleHeight + Self.tolerance }
    }

    /// Keeps the selected row in full view when the list's layout moves it:
    /// a row above it grows (a thread starts needing you), a project above
    /// it unfolds, the tray grows. A row that was in full view and is
    /// pushed part-way out, under the tray or past the top, scrolls back
    /// the least distance. Nothing else scrolls: a row the user scrolled
    /// away from stays where they left it, and a scroll never triggers one.
    struct KeepClear: Equatable {
        private(set) var last: Placement?
        /// The row was in full view before the layout last moved it.
        private(set) var wasClear = false

        /// Takes the selected row's placement after a layout or a scroll;
        /// true when the list should scroll the row back into view.
        mutating func take(_ placement: Placement?) -> Bool {
            defer { last = placement }
            guard let placement else {
                wasClear = false
                return false
            }
            // A new selection is the follower's to scroll to.
            guard let last, last.rowId == placement.rowId else {
                wasClear = placement.isClear
                return false
            }
            let layoutMoved = abs(placement.contentMinY - last.contentMinY) > Placement.layoutEpsilon
                || abs(placement.visibleHeight - last.visibleHeight) > Placement.layoutEpsilon
            // A scroll: the row is wherever the user (or the follower) put it.
            guard layoutMoved else {
                wasClear = placement.isClear
                return false
            }
            if placement.isClear {
                wasClear = true
                return false
            }
            // Still owed its place until a scroll says otherwise.
            return wasClear
        }
    }
}

/// Keeps the list on the selected session (`SidebarSelectionFollow`).
///
/// One view: any selection (a click, a shortcut, the composer, the CLI)
/// unfolds the selected session's project if it is folded and scrolls its
/// row into view, the least distance (`anchor: nil`), `trayClearance` clear
/// of the tray. Only a change of selection scrolls: the pointer, activity
/// and time never do, except to hold the selected row in full view when
/// the list's layout pushes it out (`SidebarSelectionFollow.KeepClear`).
/// Keyboard moves don't animate (motion spec, "stays still"); Reduce Motion
/// animates nothing.
///
/// The tabs layout keeps what it had: on the rail, a selection moved by
/// keyboard (Next/Previous Session, Cmd+1-9) scrolls into view, instantly.
struct SidebarSelectionFollower: ViewModifier {
    let selectedSessionId: UUID?
    /// The rows the list draws: Pinned, then Active.
    let pinned: [AgentSession]
    let active: [AgentSession]
    let layout: SidebarProjectsLayout
    let window: () -> NSWindow?
    let scrollProxy: ScrollViewProxy

    /// The selected row's last placement (`KeepClear`). A reference, not
    /// view state: it changes on every scroll and redraws nothing.
    private final class KeepClearBox {
        var state = SidebarSelectionFollow.KeepClear()
        var frame: SidebarSelectionFollow.SelectedTargetFrame?
        /// The viewport's height above the tray (`ViewportHeightKey`).
        var viewportHeight: CGFloat = 0
        var isOneView = false
    }

    @State private var keyboardMovedSelection = false
    @State private var keepClear = KeepClearBox()
    @EnvironmentObject private var widthModel: SidebarWidthModel
    @AppStorage(ProjectAccordionState.collapsedKey, store: SidebarDialTuning.store) private var collapsedRaw = ""

    /// Everything a change is read from. `onChange` runs the closure of
    /// the body before the change, whose own properties are one render
    /// old, so every handler below takes the new value explicitly and
    /// never reads `self`'s.
    private struct Inputs: Equatable {
        var selected: UUID?
        var pinned: [AgentSession]
        var active: [AgentSession]
        var layout: SidebarProjectsLayout

        /// The selection's row, if it has one yet: a new session is
        /// selected before its terminal is up, so its row can arrive after.
        var selectedRowId: String? {
            (pinned + active).contains { $0.id == selected } ? selected?.uuidString : nil
        }
    }

    func body(content: Content) -> some View {
        let inputs = Inputs(selected: selectedSessionId, pinned: pinned, active: active, layout: layout)
        // Read by the preference handlers below, which run outside `body`.
        let _ = keepClear.isOneView = layout == .oneView
        content
            .onPreferenceChange(SidebarSelectionFollow.SelectedTargetFrameKey.self) { [keepClear] frame in
                keepClear.frame = frame
                keepSelectedRowClear()
            }
            .onPreferenceChange(SidebarSelectionFollow.ViewportHeightKey.self) { [keepClear] height in
                keepClear.viewportHeight = height
                keepSelectedRowClear()
            }
            .onReceive(Self.keyboardSelection) { note in
                guard let target = note.object as? NSWindow, target === window() else { return }
                keyboardMovedSelection = true
            }
            .onChange(of: inputs) { [old = inputs] new in
                // Nothing but the selection (or its row arriving) scrolls.
                guard new.selected != old.selected || new.selectedRowId != old.selectedRowId else { return }
                let route: SidebarSelectionFollow.Route = keyboardMovedSelection ? .keyboard : .direct
                keyboardMovedSelection = false
                follow(new, route: route)
            }
            .onAppear {
                guard inputs.layout == .oneView else { return }
                scroll(to: inputs.selectedRowId, in: inputs, animated: false)
            }
    }

    /// Scrolls the selected row back into full view when the list's layout
    /// has pushed it out (`SidebarSelectionFollow.KeepClear`). Not
    /// animated: the row holds its place while the list moves round it.
    private func keepSelectedRowClear() {
        let box = keepClear
        guard box.isOneView, let frame = box.frame, box.viewportHeight > 0 else {
            _ = box.state.take(nil)
            return
        }
        let placement = SidebarSelectionFollow.Placement(
            rowId: frame.rowId, contentMinY: frame.contentMinY,
            minY: frame.viewport.minY, maxY: frame.viewport.maxY + SidebarSelectionFollow.trayClearance,
            visibleHeight: box.viewportHeight
        )
        guard box.state.take(placement) else { return }
        // On the next turn: this runs inside a layout pass.
        DispatchQueue.main.async { [scrollProxy] in
            scrollProxy.scrollTo(SidebarSelectionFollow.scrollTargetId(row: frame.rowId))
        }
    }

    private func follow(_ inputs: Inputs, route: SidebarSelectionFollow.Route) {
        let plan = SidebarSelectionFollow.plan(
            layout: inputs.layout, route: route, selected: inputs.selected,
            rows: SidebarSelectionFollow.Rows(
                pinned: inputs.pinned, active: inputs.active, collapsed: ProjectAccordionState.decode(collapsedRaw)
            ),
            isRail: widthModel.isCollapsedPresentation
        )
        if let projectId = plan.unfold {
            withAnimation(plan.animates ? ProjectAccordionState.toggleAnimation(unfolding: true) : nil) {
                collapsedRaw = ProjectAccordionState.expanded(collapsedRaw, projectId)
            }
        }
        scroll(to: plan.scrollTo, in: inputs, animated: plan.animates)
    }

    private func scroll(to rowId: String?, in inputs: Inputs, animated: Bool) {
        guard let rowId else { return }
        guard inputs.layout == .oneView else {
            // The list's row ids are uuid strings (`SidebarProjectGroupItem.id`).
            scrollProxy.scrollTo(rowId)
            return
        }
        // After this update, so an unfolded row is laid out where it will
        // rest.
        DispatchQueue.main.async {
            withAnimation(animated ? SidebarUISpring.reflow.animation() : nil) {
                scrollProxy.scrollTo(SidebarSelectionFollow.scrollTargetId(row: rowId))
            }
        }
    }

    /// The notifications the session shortcuts post, with the window.
    private static let keyboardSelection = NotificationCenter.default.publisher(for: .workspaceSelectNextSession)
        .merge(with: NotificationCenter.default.publisher(for: .workspaceSelectPreviousSession))
        .merge(with: NotificationCenter.default.publisher(for: .workspaceFocusSessionAtIndex))
}
