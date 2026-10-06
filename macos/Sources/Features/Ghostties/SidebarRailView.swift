import SwiftUI
import GhosttiesCore

/// The collapsed icon-only rail (Flow 01, sidebar-presence §02), sized to
/// hug the window's traffic lights (`WorkspaceLayout.collapsedRailWidth`).
///
/// Content-agnostic across project-first/task-first sidebar view modes —
/// it lists Pinned + Active sessions (`WorkspaceStore.railSessions()`, same
/// membership/order as `RecentsListView`) regardless of which full sidebar
/// view is otherwise mounted, since the rail has no room for the
/// project/task distinction. Hosted by `WorkspaceViewContainer.applySidebarView()`
/// in place of `WorkspaceSidebarView`/`TaskSidebarView` whenever
/// `sidebarMode == .collapsed`.
///
/// Decision 4 (spec): no account row — no account model exists in the
/// sidebar sources today, so the footer omits it.
struct SidebarRailView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Same top inset as the expanded list's titlebar toolbar
            // (`WorkspaceSidebarView.titlebarToolbar`), so every rail row sits
            // at the y of its expanded row.
            Color.clear.frame(height: store.toolbarRowTopAnchorConstant * 2)

            // Same structure and rhythm as the expanded Sessions list
            // (`RecentsListView`): header, rows, then the Inactive/Archive
            // headers. The rail has no room for header text, so each header
            // collapses to its chevron (`RailChevronRow`, header geometry) —
            // the top one stands in for Active/Pinned. Margins, row gap and
            // top padding are the list's own tokens.
            VStack(spacing: SidebarDialTuning.rowGap()) {
                RailChevronRow()

                ForEach(store.railSessions()) { session in
                    RailSessionRow(
                        sessionId: session.id,
                        name: session.name,
                        projectName: store.projects.first { $0.id == session.projectId }?.name ?? "Unknown",
                        // Same source as `RecentsListView.sessionRow`, so a
                        // session shows the same glyph in the list and the rail.
                        indicatorState: store.globalIndicatorStates[session.id] ?? .inactive,
                        isActive: coordinator.activeSessionId == session.id,
                        onTap: { coordinator.focusSession(id: session.id) }
                    )
                }

                // Two bare chevron rows summarizing Inactive/Archived — the
                // rail is too narrow for their counts to render, so the
                // count only reaches VoiceOver/the tooltip. Counts come from
                // `RecentsListView`'s own static bucket functions
                // (`inactiveSessions`/`archiveSessions`) — the same source
                // its section headers read.
                RailSectionSummaryRow(
                    label: "Inactive",
                    count: RecentsListView.inactiveSessions(
                        from: store.sessions,
                        statuses: store.globalStatuses,
                        sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
                    ).count
                )
                RailSectionSummaryRow(
                    label: "Archived",
                    count: RecentsListView.archiveSessions(
                        from: store.sessions,
                        statuses: store.globalStatuses,
                        sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
                    ).count
                )
            }
            .padding(.leading, SidebarDialTuning.contentPaddingLeading())
            .padding(.trailing, SidebarDialTuning.contentPaddingTrailing())
            .padding(.top, SidebarDialTuning.contentPaddingTop())
            .padding(.bottom, 4)

            Spacer(minLength: 0)

            RailTray()
                .padding(.bottom, SidebarDialTuning.railTrayBottomMargin())
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
}

// MARK: - Rail Session Row

/// A single rail row: the same status glyph as the expanded Sessions list,
/// centered horizontally in the rail card, at the same row height as
/// `RecentsRowView` (Sean, 2026-10-05: rail icons centered; the expanded row
/// keeps its glyph on the trailing edge). The label is dropped; the per-row
/// tap target stays.
struct RailSessionRow: View {
    let sessionId: UUID
    let name: String
    let projectName: String
    let indicatorState: SessionIndicatorState
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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
            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: SidebarDialTuning.rowGhostSize())
                .frame(width: SidebarDialTuning.rowGhostSize(), height: SidebarDialTuning.rowGhostSize())
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

    /// Selected rail row is the same raised card as the expanded sidebar's
    /// selected row (`RecentsRowView.rowBackground`) — Flow 07's collapsed
    /// export (`yhzPU.png`) shows the same white card + shadow around the
    /// top ghost there, not a flat tint.
    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: SidebarDialTuning.selectedCardCornerRadius())
                .fill(colorScheme == .dark ? Color(WorkspaceLayout.canvasBackgroundDark) : Color(WorkspaceLayout.canvasBackgroundLight))
                .shadow(
                    color: Color.black.opacity(SidebarDialTuning.selectedCardShadowOpacity()),
                    radius: SidebarDialTuning.selectedCardShadowRadius(),
                    y: SidebarDialTuning.selectedCardShadowYOffset()
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        }
    }
}

// MARK: - Rail Section Chevron Rows

/// A section header collapsed to its chevron: the expanded
/// `SessionSectionHeader`'s vertical geometry (top/bottom padding, chevron
/// size) with the title dropped, centered horizontally so the chevron sits in
/// the same column as the centered row glyphs below it and at the header's y.
private struct RailChevronRow: View {
    var isHovered = false

    var body: some View {
        PixelChevronView(isExpanded: false)
            .frame(width: SidebarDialTuning.headerChevronSize(), height: SidebarDialTuning.headerChevronSize())
            .frame(maxWidth: .infinity)
        .padding(.top, SidebarDialTuning.headerTopPadding())
        .padding(.bottom, SidebarDialTuning.headerBottomPadding())
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// A chevron row summarizing a collapsed-away section (Inactive/Archived).
/// Not a disclosure control: tapping it expands the full sidebar (Cmd+S)
/// rather than inline-listing session rows the rail has no room for, so
/// `count` only reaches VoiceOver and the tooltip.
private struct RailSectionSummaryRow: View {
    let label: String
    let count: Int

    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var isHovered = false

    var body: some View {
        Button {
            (coordinator.containerView as? WorkspaceViewContainer)?.toggleSidebar()
        } label: {
            RailChevronRow(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(label) (\(count))")
        .accessibilityLabel("\(label), \(count)")
    }
}

// MARK: - Rail Tray

/// The vertical `SidebarTrayPill` holding icon buttons laid out from
/// `WorkspaceViewContainer.sidebarTrayItems` (spec §02) — currently New
/// Session and the sidebar toggle, but the layout doesn't hardcode a count.
/// Decision 4: no account circle, since there's no account model to show
/// one for.
struct RailTray: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    /// See `SidebarTrayPill.forceOpaque`.
    var forceOpaque = false

    var body: some View {
        SidebarTrayPill(axis: .vertical, forceOpaque: forceOpaque) {
            ForEach(WorkspaceViewContainer.sidebarTrayItems(
                container: coordinator.containerView as? WorkspaceViewContainer,
                toggleLabel: "Expand Sidebar"
            )) { item in
                TrayIconButton(systemName: item.systemName, label: item.label, helpText: item.helpText, tapEffect: item.tapEffect, action: item.action)
            }
        }
        // Hugs the icons (button + 2 x `trayInnerPadding`) and sits centered
        // in the rail column (Sean, 2026-10-05); the expanded tray keeps its
        // full-width bar.
        .frame(maxWidth: .infinity)
    }
}
