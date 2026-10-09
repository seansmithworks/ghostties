import SwiftUI
import Combine
import GhosttiesCore

/// The collapsed icon-only rail (Flow 01, sidebar-presence §02), sized to
/// hug the window's traffic lights (`WorkspaceLayout.collapsedRailWidth`).
///
/// Content-agnostic across project-first/task-first sidebar view modes —
/// it lists Pinned + Active sessions (`WorkspaceStore.railSessions()`, same
/// membership/order as `RecentsListView`) and the History row, regardless
/// of which full sidebar view is otherwise mounted, since the rail has no room for the
/// project/task distinction. Hosted by `WorkspaceViewContainer.applySidebarView()`
/// in place of `WorkspaceSidebarView`/`TaskSidebarView` whenever
/// `sidebarMode == .collapsed`.
///
/// Decision 4 (spec): no account row — no account model exists in the
/// sidebar sources today, so the footer omits it.
struct SidebarRailView: View {
    /// The rail column's padding: symmetric, so rows and the tray pill
    /// share the rail's centre (`SidebarColumnPadding`).
    static let columnPadding = SidebarColumnPadding(symmetric: true)
    /// The pinned History footer's padding: the column's insets, no
    /// vertical padding.
    static let footerPadding = SidebarColumnPadding(symmetric: true, horizontalOnly: true)
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator
    /// Folded projects in one view (`ProjectAccordionState`), shared with
    /// the expanded list.
    @AppStorage(ProjectAccordionState.collapsedKey, store: SidebarDialTuning.store) private var collapsedProjectsRaw = ""
    @AppStorage("ghostties.sidebarTab") private var sidebarTab: SidebarTab = .projects
    /// See `EnvironmentValues.sidebarRailWidth`: the tray's square pills,
    /// and so the space reserved for them, follow it.
    @Environment(\.sidebarRailWidth) private var railWidth

    var body: some View {
        let titlebarInset = store.toolbarRowTopAnchorConstant * 2
        let bleed = Self.scrollBleed(titlebarInset: titlebarInset)
        VStack(spacing: 0) {
            // Same top inset as the expanded list's titlebar toolbar
            // (`WorkspaceSidebarView.titlebarToolbar`), so every rail row sits
            // at the y of its expanded row. The scroll region starts `bleed`
            // above it and its content is padded by the same, so rows keep
            // their y.
            Color.clear.frame(height: titlebarInset - bleed)

            // Same structure and rhythm as the expanded Sessions list
            // (`RecentsListView`, mock I3/H): both render the one section
            // layout (`SidebarSessionSections.layout`), slot for slot, so
            // every rail glyph sits at its expanded row's y across the
            // pinned⇄rail morph: each zero-height end-of-section drop zone
            // becomes a zero-height marker, and the hairline slots (between
            // Pinned and Active, and before the History clock) are the same
            // slot in both.
            let sections = SidebarSessionSections.make(
                sessions: store.sessions,
                statuses: store.globalStatuses,
                sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
            )
            let layout = sections.layout(showsHistory: SidebarDialTuning.historyInSidebar())
            // The list scrolls between the titlebar and the tray, and is
            // clipped to that region, like a macOS source list: on a short
            // window nothing draws under the traffic lights or the tray.
            // No scroll indicator, so the rail's width never changes.
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(spacing: SidebarDialTuning.rowGap()) {
                        ForEach(layout.list, id: \.self) { slot in
                            railSlot(slot, sections)
                        }
                    }
                    // One view: one tinted column behind the selected session's
                    // project, tile through last row (`RailProjectColumn`).
                    .backgroundPreferenceValue(RailGroupColumnKey.self) { anchors in
                        RailGroupColumn(anchors: anchors)
                    }
                    // The window margin on both sides (`columnPadding`), so the
                    // row cards centre on the rail, as the tray pill does.
                    .modifier(Self.columnPadding)
                    // Room for the column's inset above the first tile and
                    // below the last chip, inside the clip.
                    .padding(.vertical, bleed)
                }
                .scrollIndicators(.never)
                .accessibilityLabel("Sessions")
                .modifier(RailScrollToKeyboardSelection(
                    selectedSessionId: coordinator.sidebarSelectedSessionId,
                    window: { [coordinator] in coordinator.containerView?.window },
                    scrollProxy: scrollProxy
                ))
            }

            // The History clock and its hairline, just above the
            // tray, the same gap from it as in the expanded list (the
            // rail's reserved space holds no list-to-tray gap, so all of it
            // is added here).
            if !layout.footer.isEmpty {
                VStack(spacing: SidebarDialTuning.rowGap()) {
                    ForEach(layout.footer, id: \.self) { slot in
                        railSlot(slot, sections)
                    }
                }
                .modifier(Self.footerPadding)
                .padding(.bottom, SidebarSessionSections.historyToTrayGap())
            }

            // The tray itself is hosted once at the sidebar root
            // (`SidebarTray`), over both this rail and the expanded list, so
            // it can morph between them; this reserves its space.
            Color.clear.frame(height: SidebarTray.reservedHeight(isVertical: true, railWidth: railWidth))
        }
        .frame(maxWidth: .infinity)
        .background(.clear)
        .onAppear {
            // Round 6 follow-up: a capture can cold-launch straight into
            // `.collapsed` mode, in which case `WorkspaceSidebarView` (and
            // its own identical call) never mounts — see this method's doc
            // comment. No-ops outside `GHOSTTIES_CAPTURE_FIXTURE`.
            #if DEBUG
            coordinator.applyCaptureFixtureFocusIfNeeded()
            #endif
        }
        .modifier(ProjectAccordionAutoExpand(window: { [coordinator] in coordinator.containerView?.window }))
    }

    /// How far the scroll region reaches above the first row, so the
    /// project column's inset above its tile isn't clipped: the column
    /// inset, but never up into the traffic lights' row, which is centred
    /// at `titlebarInset / 2` and 16pt tall.
    static func scrollBleed(titlebarInset: CGFloat) -> CGFloat {
        min(RailProjectColumn.columnInset, max(0, titlebarInset / 2 - 8))
    }

    /// One slot of the section layout, as `RecentsListView.slotContent`
    /// renders it in the expanded list.
    @ViewBuilder
    private func railSlot(_ slot: SidebarSessionSections.Slot, _ sections: SidebarSessionSections) -> some View {
        switch slot {
        case .pinnedRows:
            ForEach(sections.pinned) { session in
                railRow(for: session)
            }
        case .activeRows:
            if SidebarProjectsLayout.effective(tab: sidebarTab) == .oneView {
                groupedRailRows(sections.active)
            } else {
                ForEach(sections.active) { session in
                    railRow(for: session)
                }
            }
        case .pinnedEnd, .activeEnd:
            RailSectionEndMarker()
        case .history:
            RailHistoryRow(
                subtitle: HistorySummary.subtitle(count: sections.historyCount, lastActiveAt: sections.historyLastActiveAt),
                isActive: coordinator.isHistoryPresented,
                onTap: { coordinator.presentHistory() }
            )
        }
    }

    /// One view (mock B5): each project's monogram tile at its header's y,
    /// its sessions' glyphs beneath, slot for slot with
    /// `RecentsListView.groupedActiveRows`.
    @ViewBuilder
    private func groupedRailRows(_ active: [AgentSession]) -> some View {
        let groups = SidebarProjectGroup.make(active: active, projects: store.projects)
        let monograms = Dictionary(
            zip(groups.map(\.id), ProjectMonogram.monograms(for: groups.map(\.name))),
            uniquingKeysWith: { first, _ in first }
        )
        // The group holding the selected session becomes the column.
        let selectedGroupId = RailProjectColumn.selectedGroupId(groups, selectedSessionId: coordinator.sidebarSelectedSessionId)
        ForEach(SidebarProjectGroupItem.items(groups, collapsed: ProjectAccordionState.decode(collapsedProjectsRaw))) { item in
            switch item {
            case .spacer:
                Color.clear
                    .frame(height: SidebarProjectGroupItem.spacerHeight)
                    .accessibilityHidden(true)
            case .header(let group, let isCollapsed):
                RailProjectTile(
                    name: group.name,
                    monogram: monograms[group.id] ?? "?",
                    count: group.sessions.count,
                    isCollapsed: isCollapsed,
                    isEmpty: group.isEmpty,
                    isSelectedProject: group.id == selectedGroupId
                ) {
                    ProjectAccordionState.headerClicked(group, collapsedRaw: $collapsedProjectsRaw) { projectId in
                        ProjectSelection.select(projectId, store: store, coordinator: coordinator, window: coordinator.containerView?.window)
                    }
                }
                .railGroupColumn(group.id == selectedGroupId)
            case .row(let session, let group):
                railRow(for: session, inProjectColumn: true)
                    .railGroupColumn(group.id == selectedGroupId)
            }
        }
    }

    private func railRow(for session: AgentSession, inProjectColumn: Bool = false) -> some View {
        RailSessionRow(
            sessionId: session.id,
            name: session.name,
            projectName: store.projects.first { $0.id == session.projectId }?.name ?? "Unknown",
            // Same source as `RecentsListView.sessionRow`, so a
            // session shows the same glyph in the list and the rail.
            indicatorState: store.globalIndicatorStates[session.id] ?? .inactive,
            isActive: coordinator.sidebarSelectedSessionId == session.id,
            dialEpoch: SidebarDialTuning.epoch(),
            inProjectColumn: inProjectColumn,
            onTap: { coordinator.focusSession(id: session.id) }
        )
        // `RailScrollToKeyboardSelection` scrolls to this id.
        .id(session.id)
    }
}

/// Scrolls the rail to the selected session when the selection moved by
/// keyboard (Next/Previous Session, Cmd+1-9), so a selection cycled past
/// the clip edge comes into view. A click selects a row that is already
/// visible, so it doesn't scroll. Scrolls the least distance (`anchor: nil`).
private struct RailScrollToKeyboardSelection: ViewModifier {
    let selectedSessionId: UUID?
    let window: () -> NSWindow?
    let scrollProxy: ScrollViewProxy

    @State private var keyboardMovedSelection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onReceive(Self.keyboardSelection) { note in
                guard let target = note.object as? NSWindow, target === window() else { return }
                keyboardMovedSelection = true
            }
            .onChange(of: selectedSessionId) { id in
                guard keyboardMovedSelection else { return }
                keyboardMovedSelection = false
                guard let id else { return }
                if reduceMotion {
                    scrollProxy.scrollTo(id)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { scrollProxy.scrollTo(id) }
                }
            }
    }

    /// The notifications the session shortcuts post, with the window.
    private static let keyboardSelection = NotificationCenter.default.publisher(for: .workspaceSelectNextSession)
        .merge(with: NotificationCenter.default.publisher(for: .workspaceSelectPreviousSession))
        .merge(with: NotificationCenter.default.publisher(for: .workspaceFocusSessionAtIndex))
}

// MARK: - Project column

/// One view's selection (Sean, 2026-10-08, strawman C; option D,
/// 2026-10-09): the selected session's project becomes a column on the rail,
/// tile through its last row, its tile filled with ink, and a card the full
/// row width in the expanded list (`ExpandedGroupCard`). Each grouped
/// session is marked by a tile-sized chip behind its glyph, in both.
/// Pinned rows, and the Sessions tab, keep the wide row card.
///
/// Every value below is a "Rail column" dial (`SidebarDialTuning`); the
/// `default…` constants are what ships, and what each dial reads unset.
enum RailProjectColumn {
    /// The chip's side and corner default to the monogram tile's
    /// (`RailProjectTile.size`, `RailProjectTile.cornerRadius`), so chip and
    /// tile read as one family.
    static let defaultChipSizeOffset: CGFloat = 0
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
    /// rim, unlike the wide selected row card.
    static let selectedChipTintOpacity: Double = 0.10

    /// `RailProjectTile.size` plus the chip-size dial, clamped to the row
    /// height so the chip never spills out of its row.
    static var chipSize: CGFloat {
        min(max(RailProjectTile.size + SidebarDialTuning.railChipSizeOffset(), 0), SidebarDialTuning.rowHeight())
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
    /// chip-size dial makes it the wider of the two; 0 when the tile is.
    static var chipOverhang: CGFloat { max(0, chipSize - RailProjectTile.size) / 2 }

    /// The overhang the card's or column's side gaps are measured past the
    /// tile slot: the chip's when the group shows rows; a header alone has
    /// no chip, so the tile is the outer element.
    static func sideOverhang(anchorCount: Int) -> CGFloat {
        anchorCount > 1 ? chipOverhang : 0
    }

    /// The rail column's width: the wider of tile and chip, plus `inset`
    /// on each side.
    static func columnWidth(anchorCount: Int, inset: CGFloat) -> CGFloat {
        RailProjectTile.size + (sideOverhang(anchorCount: anchorCount) + inset) * 2
    }

    /// The column's or card's vertical extent around its anchors' union:
    /// `inset` above the tile and `inset` below the last row's chip (below
    /// the tile when the header is alone), so with the side gaps the card
    /// is inset from the tile and chips on all four sides (Sean, 2026-10-09,
    /// over option D's "runs past the last row").
    static func verticalExtent(union: CGRect, anchorCount: Int, inset: CGFloat) -> ClosedRange<CGFloat> {
        let tileTrim = max(0, (ProjectAccordionHeader.height - RailProjectTile.size) / 2)
        let chipTrim = max(0, (SidebarDialTuning.rowHeight() - chipSize) / 2)
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

/// The project column: one rounded, faintly tinted rect spanning the
/// selected group's tile and rows, `columnInset` from the tile and chips
/// on all four sides.
private struct RailGroupColumn: View {
    /// Re-renders on every dial write; the body reads the Rail column dials.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme
    let anchors: [Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let first = anchors.first {
                let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                let inset = RailProjectColumn.columnInset
                let extent = RailProjectColumn.verticalExtent(union: union, anchorCount: anchors.count, inset: inset)
                let width = RailProjectColumn.columnWidth(anchorCount: anchors.count, inset: inset)
                RoundedRectangle(cornerRadius: RailProjectColumn.columnCornerRadius, style: .continuous)
                    .fill(RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.columnTintOpacity))
                    .frame(width: width, height: extent.upperBound - extent.lowerBound)
                    .position(x: union.midX, y: (extent.lowerBound + extent.upperBound) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The expanded list's group card (option D): the rail column widened to
/// the row width, inset from the tile and chips on all four sides: `inset`
/// beside the wider of tile and chip (mirrored on the trailing side), above
/// the tile and below the last row's chip, at the column's corner and tint,
/// so collapsing reads as one shape narrowing to the column.
struct ExpandedGroupCard: View {
    /// Re-renders on every dial write; the body reads the column dials.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme
    let anchors: [Anchor<CGRect>]

    /// How far the card reaches past the row frames on each side: the
    /// card inset, less the row's own leading padding before its tile slot,
    /// plus the chip's overhang past that slot (`RailProjectColumn.sideOverhang`).
    static func horizontalOutset(cardInset: CGFloat, rowLeadingPadding: CGFloat, chipOverhang: CGFloat) -> CGFloat {
        cardInset - rowLeadingPadding + chipOverhang
    }

    var body: some View {
        GeometryReader { proxy in
            if let first = anchors.first {
                let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                let inset = SidebarDialTuning.groupCardInset()
                let outset = Self.horizontalOutset(
                    cardInset: inset,
                    rowLeadingPadding: SidebarDialTuning.rowLeadingPadding(),
                    chipOverhang: RailProjectColumn.sideOverhang(anchorCount: anchors.count)
                )
                let extent = RailProjectColumn.verticalExtent(union: union, anchorCount: anchors.count, inset: inset)
                RoundedRectangle(cornerRadius: RailProjectColumn.columnCornerRadius, style: .continuous)
                    .fill(RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.columnTintOpacity))
                    .frame(width: max(0, union.width + outset * 2), height: extent.upperBound - extent.lowerBound)
                    .position(x: union.midX, y: (extent.lowerBound + extent.upperBound) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A grouped session's selection and hover mark (option D): a tile-sized
/// chip behind its glyph, flat (`RailProjectColumn.selectedChipTintOpacity`),
/// no chromatic rim; hover is the row's hover tint.
struct SidebarRowChipBackground: View {
    let isActive: Bool
    let isHovered: Bool

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Hover keeps the row hover's `.primary` tint; selection is the
        // canvas's alpha on solid ink.
        let fill = isActive
            ? RailProjectColumn.tintInk(colorScheme).opacity(RailProjectColumn.selectedChipTintOpacity)
            : Color.primary.opacity(isHovered ? SidebarRowCardBackground.hoverTintOpacity : 0)
        RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: RailProjectColumn.chipSize, height: RailProjectColumn.chipSize)
    }
}

// MARK: - Rail Session Row

/// A single rail row: the same status glyph as the expanded Sessions list,
/// centered horizontally in the rail card, at the same row height as
/// `RecentsRowView` (Sean, 2026-10-05: rail icons centered; the expanded row
/// keeps its glyph on the trailing edge). The label is dropped; the per-row
/// tap target stays.
struct RailSessionRow: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    let sessionId: UUID
    let name: String
    let projectName: String
    let indicatorState: SessionIndicatorState
    let isActive: Bool
    /// `SidebarDialTuning.epoch()`: a live Tray glass dial change must
    /// re-render the selected pill even when nothing else about the row did.
    var dialEpoch = 0
    /// A one-view grouped row: marked by a tile-sized chip inside its
    /// project's column (`RailProjectColumn`), not the wide row card.
    var inProjectColumn = false
    let onTap: () -> Void

    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var isHovered = false

    /// Same wording as the expanded row's label (name, project, spoken
    /// status, active) minus the last-output time.
    static func accessibilityLabel(name: String, projectName: String, kind: SessionStatusGlyphKind, isActive: Bool) -> String {
        var parts = [name, "in \(projectName)", kind.spokenStatus]
        if isActive { parts.append("active") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            // No side padding: the card spans the rail's content margins
            // (symmetric), so centering in the card centers on the rail.
            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: glyphSize)
                .frame(width: glyphSize, height: glyphSize)
                .background {
                    if inProjectColumn {
                        SidebarRowChipBackground(isActive: isActive, isHovered: isHovered)
                    }
                }
                .frame(maxWidth: .infinity)
            .frame(height: SidebarDialTuning.rowHeight())
            .background {
                if !inProjectColumn {
                    rowBackground
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sessionPopoverAnchor(sessionId: sessionId, controller: coordinator.sessionPopover, showsName: true)
        .accessibilityLabel(Self.accessibilityLabel(name: name, projectName: projectName, kind: indicatorState.statusGlyphKind, isActive: isActive))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Sidebar vnext (pen.dev `CnDfN`): the selected glyph grows to the
    /// canvas's 35px (17.5pt).
    private var glyphSize: CGFloat {
        // The chip marks selection in a project column, not a glyph size
        // change, so every grouped row keeps the resting size.
        guard !inProjectColumn else { return SidebarDialTuning.rowGhostSize() }
        return isActive ? TrayGlassStyle.selectedGlyphSize : SidebarDialTuning.rowGhostSize()
    }

    /// The selected card fills the hover card's footprint
    /// (`SidebarRowCardBackground`).
    private var rowBackground: some View {
        SidebarRowCardBackground(isActive: isActive, isHovered: isHovered)
    }
}
