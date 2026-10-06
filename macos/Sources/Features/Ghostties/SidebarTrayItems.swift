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
    /// Which symbol animation `TrayIconButton` plays on click. `nil` = none.
    let tapEffect: TrayIconTapEffect?
    let action: () -> Void

    init(
        id: String,
        systemName: String,
        label: String,
        helpText: String? = nil,
        tapEffect: TrayIconTapEffect? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.systemName = systemName
        self.label = label
        self.helpTextOverride = helpText
        self.tapEffect = tapEffect
        self.action = action
    }
}

/// The click-triggered SF Symbol animation a `TrayIconButton` plays, gated
/// by `#available` (symbolEffect needs macOS 14+, `.rotate` needs 15+) and
/// always suppressed under Reduce Motion. Strawman for Sean to react to —
/// restrained on purpose.
enum TrayIconTapEffect {
    case bounce
    case rotate
}

/// Round 5 tray pill tuning — Sean's strawman ("stylized more" than round
/// 4's stock glass, which read as a faint outline on flat chrome), named so
/// every dimension tunes from one place instead of being hand-picked at each
/// call site. Button/icon sizing feeds both the Liquid Glass path (macOS
/// 26+) and the opaque fallback below, so the two never drift into
/// different proportions.
enum TrayGlassStyle {
    /// Hit target / visual size of one `TrayIconButton`. Round 5: 28 → 30.
    /// Round 6 follow-up: 30 → 36 — derived from Flow 07's Icon container
    /// (20×20) plus its "New Session" wrapper's 8pt padding on every side
    /// (`flow07.html` layer `wy7vi`: `padding: 8px` around a 20×20 `Icon`),
    /// measured in design px which the traffic-light ruler confirms are 1:1
    /// with app pt. `innerPadding` (4pt, unchanged) added on top of this
    /// gives a 44pt tray bar, matching the design's measured tray height.
    static let buttonSize: CGFloat = 36
    /// SF Symbol point size inside a tray button. Round 5: 13 → 14.
    /// Round 6 follow-up: 14 → 16, scaled with `buttonSize` (30→36 is
    /// ×1.2; 14×1.2 ≈ 16) — SF Symbols carry more ink per point than
    /// Flow 07's raw 17.5px custom glyphs, so this tracks the button-size
    /// ratio rather than the glyph's own px value directly.
    static let iconSize: CGFloat = 16
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
        return Color(base).opacity(SidebarDialTuning.trayTintOpacity())
    }

    /// 0.5pt inner highlight stroke — the top/light edge a physically
    /// raised glass pill would catch. Brighter in light mode (white against
    /// the warm cream chrome); dimmer in dark mode so it doesn't read as a
    /// glow.
    static func innerHighlightStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(SidebarDialTuning.trayRimOpacityDark()) : Color.white.opacity(SidebarDialTuning.trayRimOpacityLight())
    }

    /// Soft drop shadow lifting the pill off the chrome/terminal behind it —
    /// DESIGN.md's shadow-only-elevation pattern (`composerModalShadow*`),
    /// scaled down for a small floating control rather than a full card.
    static let shadowColor = Color.black.opacity(0.08)
    static let shadowRadius: CGFloat = 4
    static let shadowYOffset: CGFloat = 1

    /// Opacity applied to the chrome-background tint in `glassTint(for:)`.
    static let tintOpacity: Double = 0.55

    /// `innerHighlightStroke(for:)` opacity in light mode.
    static let rimOpacityLight: Double = 0.6

    /// `innerHighlightStroke(for:)` opacity in dark mode.
    static let rimOpacityDark: Double = 0.14
}

/// "Sidebar vnext" (pen.dev `CnDfN`) for the collapsed rail only: the tray
/// and the selected rail row become the same white Liquid Glass pill. Canvas
/// values are retina px (its traffic lights measure 28px, the built app's
/// 14pt), so every value here is the canvas value / 2. The expanded tray
/// keeps `TrayGlassStyle`.
enum RailGlassStyle {
    /// Tray button: canvas 88px (24px padding around a 40px icon frame).
    static let buttonSize: CGFloat = 44
    /// Tray icon: canvas 35px.
    static let iconSize: CGFloat = 17.5
    /// Tray button hover shape: canvas r12px.
    static let buttonCornerRadius: CGFloat = 6
    /// Pill padding around its buttons: canvas 8px.
    static let innerPadding: CGFloat = 4
    /// Canvas buttons are stacked with no gap.
    static let itemGap: CGFloat = 0
    /// Canvas r64px on a 104px-wide pill: clamps to a capsule.
    static let cornerRadius: CGFloat = 32
    /// Pill width — the column the tray and the selected row share
    /// (canvas 104px): one button + padding on both sides.
    static var pillWidth: CGFloat { buttonSize + 2 * innerPadding }

    /// Selected rail row: canvas 72px tall (16px padding around a 40px
    /// icon frame), glyph 35px (vs the 28px it replaces).
    static let selectedRowHeight: CGFloat = 36
    static let selectedGlyphSize: CGFloat = 17.5

    /// Glass tint. Dark mode has no canvas; it keeps the warm chrome tint
    /// the tray already used. Light mode tints nothing: the white comes from
    /// `surfaceFill`, since a native `.tint(white 0.8)` blends far weaker
    /// than the canvas's 80% white and reads grey.
    static func glassTint(for colorScheme: ColorScheme) -> Color? {
        colorScheme == .dark ? TrayGlassStyle.glassTint(for: .dark) : nil
    }

    /// Canvas base fill `#ffffffcc`, laid over the glass (light only).
    static func surfaceFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .clear : Color.white.opacity(0.8)
    }

    /// Bright rim standing in for the shader's fresnel edge (canvas
    /// `u_edgeWidth` 3px). Native glass can't do the chromatic fringe; this
    /// gets the white edge only. Dark mode keeps the tray's dim rim.
    static let rimWidth: CGFloat = 1.5
    static func rimColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? TrayGlassStyle.innerHighlightStroke(for: .dark) : Color.white
    }

    /// Tray icon weight: the canvas's lucide icons are 2px strokes on a
    /// 24px grid (~1.5pt at 17.5pt), which `.regular` matches; the expanded
    /// tray's `.medium` reads heavier.
    static let iconWeight: Font.Weight = .regular

    /// Opaque fallback (pre-26 / Reduce Transparency).
    static func opaqueFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.8)
    }

    /// Canvas outer shadow `#00000014`, y4px, blur 20px.
    static let shadowColor = Color.black.opacity(0.078)
    static let shadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 2

    /// Canvas icon fill `#636363` = `textSecondaryLight`.
    static func iconColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }
}

/// A white Liquid Glass capsule (`RailGlassStyle`) — the rail tray's and the
/// selected rail row's shared surface. Opaque white below macOS 26, under
/// Reduce Transparency, or with `forceOpaque` (tests: `cacheDisplay` can't
/// capture glass).
struct RailGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var forceOpaque = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RailGlassStyle.cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency, !forceOpaque {
                Color.clear
                    .glassEffect(.regular.tint(RailGlassStyle.glassTint(for: colorScheme)), in: shape)
                    .overlay(shape.fill(RailGlassStyle.surfaceFill(for: colorScheme)))
                    .overlay(shape.strokeBorder(RailGlassStyle.rimColor(for: colorScheme), lineWidth: RailGlassStyle.rimWidth))
            } else {
                shape.fill(RailGlassStyle.opaqueFill(for: colorScheme))
            }
        }
        .shadow(
            color: RailGlassStyle.shadowColor,
            radius: RailGlassStyle.shadowRadius,
            y: RailGlassStyle.shadowYOffset
        )
    }
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
    /// Skips the glass effect so the pill renders as plain fill — the same
    /// path Reduce Transparency takes. Test seam: `cacheDisplay` can't capture
    /// glass, and the system setting can't be set from a test.
    var forceOpaque = false
    @ViewBuilder let content: () -> Content

    /// Round 6 (Flow 07, layer `OEpEM`/"Bottom Group"): the tray is a
    /// full-width rounded bar, not a centered capsule — `RoundedRectangle`
    /// at the same 12pt radius the selected-row card and terminal card use,
    /// with a light stroke ("rim") instead of the round-5 inner-highlight-only
    /// treatment. Shape only; the glass/opaque fallback split below is
    /// unchanged.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SidebarDialTuning.selectedCardCornerRadius(), style: .continuous)
    }

    var body: some View {
        if axis == .vertical {
            // The collapsed rail's tray: Sidebar vnext's white glass capsule.
            VStack(spacing: RailGlassStyle.itemGap, content: content)
                .padding(RailGlassStyle.innerPadding)
                .background(RailGlassBackground(forceOpaque: forceOpaque))
        } else if #available(macOS 26.0, *), !reduceTransparency, !forceOpaque {
            GlassEffectContainer {
                pillStack
                    .padding(SidebarDialTuning.trayInnerPadding())
            }
            .glassEffect(
                .regular.tint(TrayGlassStyle.glassTint(for: colorScheme)).interactive(),
                in: shape
            )
            .overlay(
                shape.strokeBorder(rimColor, lineWidth: 0.5)
            )
            .shadow(
                color: TrayGlassStyle.shadowColor,
                radius: TrayGlassStyle.shadowRadius,
                y: TrayGlassStyle.shadowYOffset
            )
        } else {
            pillStack
                .padding(SidebarDialTuning.trayInnerPadding())
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(rimColor, lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var pillStack: some View {
        switch axis {
        case .horizontal:
            // `maxWidth: .infinity` lets the bar's flexible children
            // (`TrayIconButton(stretch: true)`) actually claim the full
            // sidebar width instead of hugging their intrinsic size.
            HStack(spacing: TrayGlassStyle.itemGap, content: content)
                .frame(maxWidth: .infinity)
        case .vertical:
            // Unreached: `body` renders the vertical (rail) pill itself.
            VStack(spacing: TrayGlassStyle.itemGap, content: content)
        }
    }

    private var fill: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
    }

    /// Light rim stroke around the tray bar — Flow 07's caption on the
    /// collapsed export (`yhzPU.png`) calls out this recess explicitly:
    /// "The tray becomes a 5% black recess instead of a 4% white one."
    /// Reuses the same highlight-stroke tokens the glass path already had.
    private var rimColor: Color {
        TrayGlassStyle.innerHighlightStroke(for: colorScheme)
    }
}

/// An icon-only button hosted inside `SidebarTrayPill`, sized from
/// `TrayGlassStyle`. The pill has no visible text, so the item's title
/// carries over as a tooltip and an accessibility label instead.
struct TrayIconButton: View {
    let systemName: String
    let label: String
    var helpText: String? = nil
    /// True in the expanded/overlay horizontal tray, where each icon takes
    /// an equal flexible share of the full-width bar (Flow 07 layer `wy7vi`
    /// et al.: each icon's "New Session"/"Settings"/"Collapse" wrapper is
    /// `flex: 1 1 0`). False (default) in the collapsed rail's fixed-size
    /// vertical pill, which is unchanged.
    var stretch: Bool = false
    /// Symbol animation to play on click — see `TrayIconTapEffect`.
    var tapEffect: TrayIconTapEffect? = nil
    /// True in the collapsed rail: Sidebar vnext sizing and icon colour
    /// (`RailGlassStyle`) instead of the DialKit-tuned expanded tray's.
    var railStyle = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var tapEffectTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var buttonSize: CGFloat {
        railStyle ? RailGlassStyle.buttonSize : SidebarDialTuning.trayButtonSize()
    }

    var body: some View {
        Button {
            tapEffectTrigger += 1
            action()
        } label: {
            icon
                .frame(
                    minWidth: stretch ? nil : buttonSize,
                    maxWidth: stretch ? .infinity : buttonSize,
                    minHeight: buttonSize,
                    maxHeight: buttonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: railStyle ? RailGlassStyle.buttonCornerRadius : 6)
                        .fill(isHovered ? Color.primary.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Hover lift — the glass path's own `.interactive()` reacts to
        // press, not hover, so this is additive rather than doubled-up with
        // it. Reduce Motion suppresses it like every other animation here.
        .scaleEffect(!reduceMotion && isHovered ? 1.06 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
        .help(helpText ?? label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var icon: some View {
        let glyph = Image(systemName: systemName)
            .font(.system(
                size: railStyle ? RailGlassStyle.iconSize : SidebarDialTuning.trayIconSize(),
                weight: railStyle ? RailGlassStyle.iconWeight : TrayGlassStyle.iconWeight
            ))
            .foregroundStyle(railStyle ? AnyShapeStyle(RailGlassStyle.iconColor(for: colorScheme)) : AnyShapeStyle(.secondary))

        if reduceMotion {
            glyph
        } else {
            switch tapEffect {
            case .none:
                glyph
            case .bounce:
                if #available(macOS 14.0, *) {
                    glyph.symbolEffect(.bounce, value: tapEffectTrigger)
                } else {
                    glyph
                }
            case .rotate:
                if #available(macOS 15.0, *) {
                    glyph.symbolEffect(.rotate, value: tapEffectTrigger)
                } else if #available(macOS 14.0, *) {
                    glyph.symbolEffect(.bounce, value: tapEffectTrigger)
                } else {
                    glyph
                }
            }
        }
    }
}

extension WorkspaceViewContainer {
    /// "New Project": the folder picker (`WorkspaceStore.addProjectViaFolderPicker`),
    /// then the composer locked to the new project, so adding a project ends in
    /// a running session instead of dead-ending (Phase 4,
    /// docs/plans/session-creation-unified.html). Shared by the sidebar header
    /// button and the tray item. Returns the new project's id, nil if cancelled.
    @discardableResult
    func addProjectViaFolderPickerAndOpenComposer() -> UUID? {
        let store = WorkspaceStore.shared
        guard let id = store.addProjectViaFolderPicker() else { return nil }
        if let newProject = store.projects.first(where: { $0.id == id }) {
            presentComposerOverlay(projectBinding: .locked(newProject))
        }
        return id
    }

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
            SidebarTrayItem(id: "newSession", systemName: "plus", label: "New Session", tapEffect: .bounce) {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                container.presentComposerOverlay(projectBinding: .open)
            },
            // Same path as the header's "+ New Project" button
            // (`WorkspaceSidebarView.presentFolderPicker`): folder picker, then
            // the composer locked to the new project.
            SidebarTrayItem(id: "newProject", systemName: "folder.badge.plus", label: "New Project", tapEffect: .bounce) {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                _ = container.addProjectViaFolderPickerAndOpenComposer()
            },
            // Round 4: reuses the app's existing "Open Config" action
            // (`AppDelegate.openConfig` -> `Ghostty.App.openConfig()`) rather
            // than a new file-opening path — this container already holds
            // the same `Ghostty.App` instance.
            SidebarTrayItem(id: "settings", systemName: "gearshape", label: "Settings", helpText: "Open Config", tapEffect: .rotate) {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                container.openConfig()
            },
            // No `.contentTransition(.symbolEffect(.replace))` here: the icon
            // is the static "sidebar.left" glyph in every mode (pinned,
            // rail, overlay) — only `toggleLabel` changes — so there's no
            // natural pinned↔rail symbol pair to cross-fade between. Falls
            // back to `.bounce` per the brief.
            SidebarTrayItem(id: "toggleSidebar", systemName: "sidebar.left", label: toggleLabel, tapEffect: .bounce) {
                container?.toggleSidebar()
            }
        ]
    }
}
