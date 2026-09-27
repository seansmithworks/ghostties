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
