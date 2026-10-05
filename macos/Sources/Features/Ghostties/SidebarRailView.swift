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
            // Reserve space for the window's traffic lights, same spacer
            // pattern used by the task-first sidebar.
            Color.clear.frame(height: WorkspaceLayout.titlebarSpacerHeight)

            // Flow 07 round 6, layer `G10V5`/"Chevron Col": the expanded
            // sidebar's section-header chevron collapses down to this single
            // static glyph at the top of the rail — expanding the rail
            // (Cmd+S) is what "opens" it back to full sections, so this
            // glyph is decorative, not an independent tap target.
            PixelChevronView(isExpanded: false)
                .frame(width: WorkspaceLayout.sidebarIconColumnWidth, height: WorkspaceLayout.sidebarIconColumnWidth)
                .padding(.top, 6)

            VStack(spacing: SidebarDialTuning.railRowGap()) {
                ForEach(store.railSessions()) { session in
                    RailSessionRow(
                        sessionId: session.id,
                        indicatorState: coordinator.indicatorState(for: session.id),
                        isActive: coordinator.activeSessionId == session.id,
                        onTap: { coordinator.focusSession(id: session.id) }
                    )
                }

                // Flow 07 round 6 follow-up, layer group under the ghost
                // list in `yhzPU.png`: two bare "›" rows summarizing
                // Inactive/Archived — the rail is too narrow for their
                // counts to render, so the count only reaches VoiceOver/the
                // tooltip. Counts come from `RecentsListView`'s own static
                // bucket functions (`inactiveSessions`/`archiveSessions`) —
                // the same source its section headers already read, not a
                // second copy of the Active/Inactive/Archive rule.
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
            .padding(.top, 14)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            RailTray()
                .padding(.bottom, 12)
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

/// A single 52×32 rail row: centered status glyph, no label — the label
/// drops in the collapsed rail, but the glyph (and the per-row tap target)
/// stays, per spec §02.
private struct RailSessionRow: View {
    let sessionId: UUID
    let indicatorState: SessionIndicatorState
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            SessionStatusGhost(kind: indicatorState.statusGlyphKind, size: SidebarDialTuning.railGhostSize(), isSelected: isActive)
                .frame(width: SidebarDialTuning.railRowWidth(), height: SidebarDialTuning.railRowHeight())
                .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sessionPopoverAnchor(sessionId: sessionId, controller: coordinator.sessionPopover, showsName: true)
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

// MARK: - Rail Section Summary Row

/// A bare "›" row summarizing a collapsed-away section (Inactive/Archived)
/// too narrow for the rail to spell out — Flow 07 round 6 follow-up, layer
/// group beneath the ghost list in `yhzPU.png`. Not a disclosure control:
/// tapping it expands the full sidebar (Cmd+S) rather than inline-listing
/// session rows the rail has no room for, so `count` only reaches VoiceOver
/// and the tooltip.
private struct RailSectionSummaryRow: View {
    let label: String
    let count: Int

    @EnvironmentObject private var coordinator: SessionCoordinator
    @State private var isHovered = false

    var body: some View {
        Button {
            (coordinator.containerView as? WorkspaceViewContainer)?.toggleSidebar()
        } label: {
            PixelChevronView(isExpanded: false)
                .frame(width: SidebarDialTuning.railRowWidth(), height: SidebarDialTuning.railSummaryRowHeight())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
                )
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
private struct RailTray: View {
    @EnvironmentObject private var coordinator: SessionCoordinator

    var body: some View {
        SidebarTrayPill(axis: .vertical) {
            ForEach(WorkspaceViewContainer.sidebarTrayItems(
                container: coordinator.containerView as? WorkspaceViewContainer,
                toggleLabel: "Expand Sidebar"
            )) { item in
                TrayIconButton(systemName: item.systemName, label: item.label, helpText: item.helpText, tapEffect: item.tapEffect, action: item.action)
            }
        }
        // Same margin rule as the expanded sidebar's `SidebarBottomTray`:
        // tray width = container (here, the rail) width − 2×margin, rather
        // than hugging the buttons' intrinsic width.
        .padding(.horizontal, SidebarDialTuning.trayMargin())
    }
}
