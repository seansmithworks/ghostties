import SwiftUI
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
        VStack(spacing: 0) {
            // Same top inset as the expanded list's titlebar toolbar
            // (`WorkspaceSidebarView.titlebarToolbar`), so every rail row sits
            // at the y of its expanded row.
            Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)

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

            Spacer(minLength: 0)

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
    }
}

// MARK: - Project column

/// One view's rail selection (Sean, 2026-10-08, strawman C): the selected
/// session's project becomes a column, tile through its last row, its tile
/// filled with ink; each grouped session is a tile-sized chip inside it.
/// Pinned rows, and the rail outside one view, keep the wide row card.
///
/// Every value below is a "Rail column" dial (`SidebarDialTuning`); the
/// `default…` constants are what ships, and what each dial reads unset.
enum RailProjectColumn {
    /// The chip's side and corner default to the monogram tile's
    /// (`RailProjectTile.size`, radius 9), so chip and tile read as one family.
    static let defaultChipSizeOffset: CGFloat = 0
    static let defaultChipCornerRadius: CGFloat = 9
    /// The column: the tile plus this margin on every side.
    static let defaultColumnInset: CGFloat = 4
    /// The column's faint fill: a hovered row's tint.
    static let defaultColumnTintOpacity: Double = SidebarRowCardBackground.hoverTintOpacity
    /// The selected project's tile: 1 is full ink, 0 the plain tile tint.
    static let defaultSelectedTileFill: Double = 1

    /// `RailProjectTile.size` plus the chip-size dial, clamped to the row
    /// height so the chip never spills out of its row.
    static var chipSize: CGFloat {
        min(max(RailProjectTile.size + SidebarDialTuning.railChipSizeOffset(), 0), SidebarDialTuning.rowHeight())
    }
    static var chipCornerRadius: CGFloat { max(SidebarDialTuning.railChipCornerRadius(), 0) }
    static var columnInset: CGFloat { max(SidebarDialTuning.railColumnInset(), 0) }
    static var columnTintOpacity: Double { min(max(SidebarDialTuning.railColumnTintOpacity(), 0), 1) }
    static var selectedTileFill: Double { min(max(SidebarDialTuning.railSelectedTileFill(), 0), 1) }

    /// The group the column marks: the one holding the selected session,
    /// or none (nothing selected, or the selection is pinned).
    static func selectedGroupId(_ groups: [SidebarProjectGroup], selectedSessionId: UUID?) -> SidebarProjectGroup.ID? {
        guard let selectedSessionId else { return nil }
        return groups.first { group in group.sessions.contains { $0.id == selectedSessionId } }?.id
    }
}

/// The bounds of every item in the selected project's group.
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
/// selected group's tile and rows, tile-width plus `columnInset`.
struct RailGroupColumn: View {
    /// Re-renders on every dial write; the body reads the Rail column dials.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    let anchors: [Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let first = anchors.first {
                let union = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                // The column hugs the tile's top (inside the header frame)
                // and the last chip's bottom (inside the last row's frame).
                let inset = RailProjectColumn.columnInset
                let topTrim = (ProjectAccordionHeader.height - RailProjectTile.size) / 2
                let bottomTrim = anchors.count > 1
                    ? (SidebarDialTuning.rowHeight() - RailProjectColumn.chipSize) / 2
                    : topTrim
                let top = union.minY + topTrim - inset
                let bottom = union.maxY - bottomTrim + inset
                let width = RailProjectTile.size + inset * 2
                RoundedRectangle(cornerRadius: RailProjectColumn.chipCornerRadius + inset, style: .continuous)
                    .fill(Color.primary.opacity(RailProjectColumn.columnTintOpacity))
                    .frame(width: width, height: bottom - top)
                    .position(x: union.midX, y: (top + bottom) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                        SidebarRowCardBackground(isActive: isActive, isHovered: isHovered, cornerRadius: RailProjectColumn.chipCornerRadius)
                            .frame(width: RailProjectColumn.chipSize, height: RailProjectColumn.chipSize)
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
