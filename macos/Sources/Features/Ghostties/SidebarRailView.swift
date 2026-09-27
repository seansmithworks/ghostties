import SwiftUI
import GhosttiesCore

/// The collapsed 72pt icon-only rail (Flow 01, sidebar-presence §02).
///
/// Content-agnostic across project-first/task-first sidebar view modes —
/// it lists every live session in visual order regardless of which full
/// sidebar view is otherwise mounted, since the rail has no room for the
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

            VStack(spacing: 4) {
                ForEach(store.sessionsInVisualOrder(coordinator: coordinator)) { session in
                    RailSessionRow(
                        indicatorState: coordinator.indicatorState(for: session.id),
                        isActive: coordinator.activeSessionId == session.id,
                        onTap: { coordinator.focusSession(id: session.id) }
                    )
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            RailTray()
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(.clear)
    }
}

// MARK: - Rail Session Row

/// A single 52×32 rail row: centered status glyph, no label — the label
/// drops in the collapsed rail, but the glyph (and the per-row tap target)
/// stays, per spec §02.
private struct RailSessionRow: View {
    let indicatorState: SessionIndicatorState
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            SessionStatusGlyph(kind: indicatorState.statusGlyphKind, size: 16)
                .frame(width: 52, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(rowBackground)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isActive { return Color.primary.opacity(0.08) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }
}

// MARK: - Rail Tray

/// The 40pt-wide rounded pill holding icon buttons laid out from
/// `WorkspaceViewContainer.sidebarTrayItems` (spec §02) — currently New
/// Session and the sidebar toggle, but the layout doesn't hardcode a count.
/// Decision 4: no account circle, since there's no account model to show
/// one for.
private struct RailTray: View {
    @EnvironmentObject private var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 2) {
            ForEach(WorkspaceViewContainer.sidebarTrayItems(
                container: coordinator.containerView as? WorkspaceViewContainer,
                toggleLabel: "Expand Sidebar"
            )) { item in
                RailIconButton(systemName: item.systemName, accessibilityLabel: item.label, action: item.action)
            }
        }
        .padding(4)
        .frame(width: 40)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
    }
}

private struct RailIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(isHovered ? Color.primary.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}
