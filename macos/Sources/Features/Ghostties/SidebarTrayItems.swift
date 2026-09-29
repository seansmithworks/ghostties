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

/// Round 5 tray pill tuning — Sean's strawman ("stylized more" than round
/// 4's stock glass, which read as a faint outline on flat chrome), named so
/// every dimension tunes from one place instead of being hand-picked at each
/// call site. Button/icon sizing feeds both the Liquid Glass path (macOS
/// 26+) and the opaque fallback below, so the two never drift into
/// different proportions.
enum TrayGlassStyle {
    /// Hit target / visual size of one `TrayIconButton`. Round 5: 28 → 30.
    static let buttonSize: CGFloat = 30
    /// SF Symbol point size inside a tray button. Round 5: 13 → 14.
    static let iconSize: CGFloat = 14
    /// SF Symbol weight inside a tray button.
    static let iconWeight: Font.Weight = .medium
    /// Padding between the pill's capsule edge and its buttons.
    static let innerPadding: CGFloat = 4
    /// Gap between adjacent tray buttons.
    static let itemGap: CGFloat = 2

    /// Round 5 glass tint — a warm tone drawn from DESIGN.md's own
    /// `chromeBackground`/`darkChromeBackground` tokens (`WorkspaceLayout
    /// .chromeBackgroundLight/Dark`), NOT the terracotta accent
    /// (`waitingTerracotta`), which DESIGN.md reserves exclusively for the
    /// `waiting` session-status dot. Opacity is tuned so the pill reads as a
    /// raised, tinted surface rather than the round-4 near-invisible
    /// outline.
    static func glassTint(for colorScheme: ColorScheme) -> Color {
        let base = colorScheme == .dark
            ? WorkspaceLayout.chromeBackgroundDark
            : WorkspaceLayout.chromeBackgroundLight
        return Color(base).opacity(0.55)
    }

    /// 0.5pt inner highlight stroke — the top/light edge a physically
    /// raised glass pill would catch. Brighter in light mode (white against
    /// the warm cream chrome); dimmer in dark mode so it doesn't read as a
    /// glow.
    static func innerHighlightStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.6)
    }

    /// Soft drop shadow lifting the pill off the chrome/terminal behind it —
    /// DESIGN.md's shadow-only-elevation pattern (`composerModalShadow*`),
    /// scaled down for a small floating control rather than a full card.
    static let shadowColor = Color.black.opacity(0.08)
    static let shadowRadius: CGFloat = 4
    static let shadowYOffset: CGFloat = 1
}

/// The floating rounded pill that houses tray icon buttons. On macOS 26+,
/// with transparency effects allowed, this is real Liquid Glass
/// (`.glassEffect(.regular.tint(...).interactive())`) — Sean wanted to try
/// it; round 5 stylizes it further via `TrayGlassStyle` (warm tint, inner
/// highlight stroke, soft shadow) after round 4's stock look read as a
/// faint outline on flat chrome. Everywhere else (pre-26, or Reduce
/// Transparency on) it falls back to the original opaque recess: 5% black
/// in light appearance, 4% white in dark (Flow 01 reference, pen-t4 frames
/// 01/02) — a bright terminal behind the pill must never bleed through when
/// the user has asked to avoid transparency, and there's no glass API to
/// fall back on below 26. Shared by the expanded sidebar's horizontal
/// bottom tray and the collapsed rail's vertical tray pill, so both are one
/// component that only changes axis.
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
            .glassEffect(
                .regular.tint(TrayGlassStyle.glassTint(for: colorScheme)).interactive(),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(TrayGlassStyle.innerHighlightStroke(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(
                color: TrayGlassStyle.shadowColor,
                radius: TrayGlassStyle.shadowRadius,
                y: TrayGlassStyle.shadowYOffset
            )
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
