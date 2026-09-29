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
    /// Hover tooltip text. Defaults to `label`; only the Settings item
    /// (round 4) diverges — its accessibility label is "Settings" but its
    /// tooltip names the concrete action, "Open Config".
    var helpText: String { helpTextOverride ?? label }
    let helpTextOverride: String?
    let action: () -> Void

    init(id: String, systemName: String, label: String, helpText: String? = nil, action: @escaping () -> Void) {
        self.id = id
        self.systemName = systemName
        self.label = label
        self.helpTextOverride = helpText
        self.action = action
    }
}

/// Round 4 tray pill tuning — Sean's strawman, named so every dimension
/// tunes from one place instead of being hand-picked at each call site.
/// Button/icon sizing feeds both the Liquid Glass path (macOS 26+) and the
/// opaque fallback below, so the two never drift into different proportions.
enum TrayGlassStyle {
    /// Hit target / visual size of one `TrayIconButton`.
    static let buttonSize: CGFloat = 28
    /// SF Symbol point size inside a tray button.
    static let iconSize: CGFloat = 13
    /// SF Symbol weight inside a tray button.
    static let iconWeight: Font.Weight = .medium
    /// Padding between the pill's capsule edge and its buttons.
    static let innerPadding: CGFloat = 4
    /// Gap between adjacent tray buttons.
    static let itemGap: CGFloat = 2
}

/// The floating rounded pill that houses tray icon buttons. On macOS 26+,
/// with transparency effects allowed, this is real Liquid Glass
/// (`.glassEffect(.regular.interactive())`) — Sean wanted to try it,
/// styled beyond the stock look via `TrayGlassStyle`. Everywhere else
/// (pre-26, or Reduce Transparency on) it falls back to the original opaque
/// recess: 5% black in light appearance, 4% white in dark (Flow 01
/// reference, pen-t4 frames 01/02) — a bright terminal behind the pill must
/// never bleed through when the user has asked to avoid transparency, and
/// there's no glass API to fall back on below 26. Shared by the expanded
/// sidebar's horizontal bottom tray and the collapsed rail's vertical tray
/// pill, so both are one component that only changes axis.
struct SidebarTrayPill<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let axis: Axis
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer {
                pillStack
                    .padding(TrayGlassStyle.innerPadding)
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            pillStack
                .padding(TrayGlassStyle.innerPadding)
                .background(Capsule().fill(fill))
        }
    }

    @ViewBuilder
    private var pillStack: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: TrayGlassStyle.itemGap, content: content)
        case .vertical:
            VStack(spacing: TrayGlassStyle.itemGap, content: content)
        }
    }

    private var fill: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
    }
}

/// An icon-only button hosted inside `SidebarTrayPill`, sized from
/// `TrayGlassStyle`. The pill has no visible text, so the item's title
/// carries over as a tooltip and an accessibility label instead.
struct TrayIconButton: View {
    let systemName: String
    let label: String
    var helpText: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: TrayGlassStyle.iconSize, weight: TrayGlassStyle.iconWeight))
                .foregroundStyle(.secondary)
                .frame(width: TrayGlassStyle.buttonSize, height: TrayGlassStyle.buttonSize)
                .background(
                    Circle().fill(isHovered ? Color.primary.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText ?? label)
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
            // Round 4: reuses the app's existing "Open Config" action
            // (`AppDelegate.openConfig` -> `Ghostty.App.openConfig()`) rather
            // than a new file-opening path — this container already holds
            // the same `Ghostty.App` instance.
            SidebarTrayItem(id: "settings", systemName: "gearshape", label: "Settings", helpText: "Open Config") {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                container.openConfig()
            },
            SidebarTrayItem(id: "toggleSidebar", systemName: "sidebar.left", label: toggleLabel) {
                container?.toggleSidebar()
            }
        ]
    }
}
