import SwiftUI

/// One entry in the sidebar's bottom tray — icon, label, and action.
///
/// The single source of truth for what's in the tray. `SidebarBottomTray`
/// (expanded/overlay) and `RailTray` (collapsed) both render this same
/// ordered list instead of hand-laying-out their own buttons, so adding an
/// item (e.g. a Settings entry) is one new entry here, not new layout code
/// in two places.
struct SidebarTrayItem: Identifiable {
    let id: String
    let systemName: String
    let label: String
    let action: () -> Void
}

/// The floating rounded pill that houses tray icon buttons — opaque, no
/// blur: a 5% black recess in light appearance, 4% white in dark (Flow 01
/// reference, pen-t4 frames 01/02). Shared by the expanded sidebar's
/// horizontal bottom tray and the collapsed rail's vertical tray pill, so
/// both are one component that only changes axis.
struct SidebarTrayPill<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let axis: Axis
    @ViewBuilder let content: () -> Content

    var body: some View {
        pillStack
            .padding(4)
            .background(Capsule().fill(fill))
    }

    @ViewBuilder
    private var pillStack: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: 2, content: content)
        case .vertical:
            VStack(spacing: 2, content: content)
        }
    }

    private var fill: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
    }
}

/// A 32×32 icon-only button hosted inside `SidebarTrayPill`. The pill has
/// no visible text, so the item's title carries over as a tooltip and an
/// accessibility label instead.
struct TrayIconButton: View {
    let systemName: String
    let label: String
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
        .help(label)
        .accessibilityLabel(label)
    }
}

extension WorkspaceViewContainer {
    /// Builds the ordered tray item list shared by the expanded tray and the
    /// collapsed rail's tray pill.
    ///
    /// - Parameters:
    ///   - container: The owning `WorkspaceViewContainer`, resolved by each
    ///     call site from `coordinator.containerView`. Actions no-op (with an
    ///     assertion failure in debug) if this is nil, matching the prior
    ///     per-view behavior.
    ///   - toggleLabel: The sidebar-toggle item's label, since its wording
    ///     depends on which surface is rendering it ("Collapse Sidebar" in
    ///     the expanded tray, "Open Sidebar" in the overlay, "Expand Sidebar"
    ///     in the rail) — the one piece of state callers still supply.
    static func sidebarTrayItems(
        container: WorkspaceViewContainer?,
        toggleLabel: String
    ) -> [SidebarTrayItem] {
        [
            SidebarTrayItem(id: "newSession", systemName: "plus", label: "New Session") {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                container.presentComposerOverlay(projectBinding: .open)
            },
            SidebarTrayItem(id: "toggleSidebar", systemName: "sidebar.left", label: toggleLabel) {
                container?.toggleSidebar()
            }
        ]
    }
}
