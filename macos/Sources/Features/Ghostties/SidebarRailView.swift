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
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Same top inset as the expanded list's titlebar toolbar
            // (`WorkspaceSidebarView.titlebarToolbar`), so every rail row sits
            // at the y of its expanded row.
            Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)

            // Same structure and rhythm as the expanded Sessions list
            // (`RecentsListView`, mock I3/H), element for element, so every
            // rail glyph sits at its expanded row's y across the pinned⇄rail
            // morph: each zero-height end-of-section drop zone becomes a
            // zero-height marker, and the hairline slots (between Pinned and
            // Active, and before the History clock) are the same slot in both.
            let sections = SidebarSessionSections.make(
                sessions: store.sessions,
                statuses: store.globalStatuses,
                sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
            )
            VStack(spacing: SidebarDialTuning.rowGap()) {
                if !sections.pinned.isEmpty {
                    ForEach(sections.pinned) { session in
                        railRow(for: session)
                    }
                    RailSectionEndMarker()
                }
                if !sections.pinned.isEmpty && !sections.active.isEmpty {
                    SidebarSectionHairlineSlot(width: SidebarDialTuning.traySelectedPillWidth())
                }
                ForEach(sections.active) { session in
                    railRow(for: session)
                }
                RailSectionEndMarker()
                if !sections.rowSessions.isEmpty {
                    SidebarSectionHairlineSlot(width: SidebarDialTuning.traySelectedPillWidth())
                }
                RailHistoryRow(
                    subtitle: HistorySummary.subtitle(count: sections.historyCount, lastActiveAt: sections.historyLastActiveAt),
                    isActive: coordinator.isHistoryPresented,
                    onTap: { coordinator.presentHistory() }
                )
            }
            // The window margin on both sides (`columnPadding`), so the
            // row cards centre on the rail, as the tray pill does.
            .modifier(Self.columnPadding)

            Spacer(minLength: 0)

            // The tray itself is hosted once at the sidebar root
            // (`SidebarTray`), over both this rail and the expanded list, so
            // it can morph between them; this reserves its space.
            Color.clear.frame(height: SidebarTray.reservedHeight(isVertical: true))
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
    }

    private func railRow(for session: AgentSession) -> some View {
        RailSessionRow(
            sessionId: session.id,
            name: session.name,
            projectName: store.projects.first { $0.id == session.projectId }?.name ?? "Unknown",
            // Same source as `RecentsListView.sessionRow`, so a
            // session shows the same glyph in the list and the rail.
            indicatorState: store.globalIndicatorStates[session.id] ?? .inactive,
            isActive: coordinator.sidebarSelectedSessionId == session.id,
            dialEpoch: SidebarDialTuning.epoch(),
            onTap: { coordinator.focusSession(id: session.id) }
        )
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
                .frame(maxWidth: .infinity)
            .frame(height: SidebarDialTuning.rowHeight())
            .background(rowBackground)
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
        isActive ? TrayGlassStyle.selectedGlyphSize : SidebarDialTuning.rowGhostSize()
    }

    /// The selected card fills the hover card's footprint
    /// (`SidebarRowCardBackground`), in the selected style's surface.
    private var rowBackground: some View {
        SidebarRowCardBackground(isActive: isActive, isHovered: isHovered, hoverOpacity: 0.06)
    }
}
