import SwiftUI

/// One entry in the sidebar's bottom tray — icon, label, and action.
///
/// The single source of truth for what's in the tray. `SidebarTray` renders
/// this same ordered list on both axes (expanded/overlay and collapsed), so
/// adding an item (e.g. a Settings entry) is one new entry here, not new
/// layout code.
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

/// "Sidebar vnext" (pen.dev `CnDfN`): the sidebar tray, on both axes, and the
/// selected session row (rail and expanded, `SidebarSelectedSurface`) share
/// one white Liquid Glass surface. Canvas values are
/// retina px (its traffic lights measure 28px, the built app's 14pt), so each
/// value here is the canvas value / 2. These are the compiled defaults; every
/// one is read through `SidebarDialTuning` so the DialKit inspector can tune
/// it live, and an untouched key reads exactly this value. Colour and
/// material are per appearance (`Look`); geometry is shared.
enum TrayGlassStyle {
    /// Native `Glass` base variant.
    enum Variant: String, CaseIterable {
        case regular, clear, identity
    }

    /// Pill corner treatment. `capsule` is `capsuleCornerRadius`, which clamps
    /// to a full capsule on every pill this tray draws; `radius` uses the
    /// `cornerRadius` dial.
    enum CornerStyle: String, CaseIterable {
        case capsule, radius
    }

    /// Colour stops for the chromatic rim.
    enum ChromaticPalette: String, CaseIterable {
        case pastel, rainbow
    }

    /// Blend mode the chromatic rim composites with.
    enum ChromaticBlend: String, CaseIterable {
        case normal, plusLighter, screen, overlay

        var blendMode: BlendMode {
            switch self {
            case .normal: return .normal
            case .plusLighter: return .plusLighter
            case .screen: return .screen
            case .overlay: return .overlay
            }
        }
    }

    // MARK: Behaviour (shared by both appearances)

    /// The tray's press response (`.interactive()`). The selected row is
    /// never interactive.
    static let interactive = true

    // MARK: Colour and material, per appearance

    /// Every colour/material value the glass draws with, for one appearance.
    /// Light and dark each have their own set (`light`, `dark`), each tuned
    /// by its own DialKit group ("Glass — Light", "Glass — Dark"); geometry
    /// (sizes, padding, corners) stays shared below. Read the live set with
    /// `SidebarDialTuning.trayGlass(for:)`.
    struct Look: Equatable {
        /// Native `Glass` base variant.
        var variant: Variant
        /// Tint on the native glass: white in light, the warm chrome
        /// (`WorkspaceLayout.chromeBackgroundDark`) in dark — never the
        /// terracotta accent.
        var tintOpacity: Double
        /// The layer laid over the glass: white in light, the dark canvas
        /// token (`WorkspaceLayout.canvasBackgroundDark`) in dark.
        var surfaceOpacity: Double
        /// White rim standing in for the shader's fresnel edge.
        var rimWidth: CGFloat
        var rimOpacity: Double
        var shadowOpacity: Double
        var shadowRadius: CGFloat
        var shadowYOffset: CGFloat
        /// The canvas shader's iridescent edge, approximated as an
        /// angular-gradient stroke. 0 = not drawn at all.
        var chromaticIntensity: Double
        var chromaticWidth: CGFloat
        var chromaticRotation: Double
        var chromaticBlur: CGFloat
        var chromaticPalette: ChromaticPalette
        var chromaticBlend: ChromaticBlend
        /// White linear highlight clipped to the pill. 0 = not drawn at all.
        var specularStrength: Double
        /// Direction the light comes from, in degrees (0 = from the right,
        /// 90 = from the top).
        var specularAngle: Double
    }

    /// Light: the canvas (pen.dev `CnDfN`) values, unchanged from before the
    /// light/dark split.
    static let light = Look(
        variant: .regular,
        // 0 = untinted: the white comes from `surfaceOpacity`, since a native
        // `.tint(white 0.8)` blends far weaker than the canvas's 80% white
        // and reads grey.
        tintOpacity: 0,
        // Canvas base fill `#ffffffcc`.
        surfaceOpacity: 0.8,
        // Canvas `u_edgeWidth` 3px.
        rimWidth: 1.5,
        rimOpacity: 1,
        // Canvas outer shadow `#00000014`, y4px, blur 20px.
        shadowOpacity: 0.078,
        shadowRadius: 10,
        shadowYOffset: 2,
        // Off by default. Canvas `chromatic` 0.116, `splitAngle` 136.8°.
        chromaticIntensity: 0,
        chromaticWidth: 1.5,
        chromaticRotation: 136.8,
        chromaticBlur: 0,
        chromaticPalette: .pastel,
        chromaticBlend: .normal,
        // Off by default.
        specularStrength: 0,
        specularAngle: 135
    )

    /// Dark: a raised canvas-grey pill (`canvasBackgroundDark` #2D2D2D over
    /// the #242424 chrome) on the warm-tinted glass, with a faint white rim
    /// and a deeper shadow, since an 8% black shadow vanishes on dark chrome.
    /// No specular and no chromatic: a white highlight on dark glass lifts
    /// the background toward the grey text and icons and collapses their
    /// contrast.
    static let dark = Look(
        variant: .regular,
        tintOpacity: 0.55,
        surfaceOpacity: 0.9,
        rimWidth: 1,
        rimOpacity: 0.14,
        shadowOpacity: 0.3,
        shadowRadius: 8,
        shadowYOffset: 2,
        chromaticIntensity: 0,
        chromaticWidth: 1.5,
        chromaticRotation: 136.8,
        chromaticBlur: 0,
        chromaticPalette: .pastel,
        chromaticBlend: .plusLighter,
        specularStrength: 0,
        specularAngle: 135
    )

    static func defaultLook(for colorScheme: ColorScheme) -> Look {
        colorScheme == .dark ? dark : light
    }

    // MARK: Sizes

    /// Vertical (rail) tray button: canvas 88px (24px padding around a 40px
    /// icon frame). Icon: canvas 35px.
    static let verticalButtonSize: CGFloat = 44
    static let verticalIconSize: CGFloat = 17.5
    /// Horizontal (expanded) tray: Flow 07's 20×20 icon frame plus 8pt
    /// padding, so the bar is 44pt tall with `innerPadding`.
    static let horizontalButtonSize: CGFloat = 36
    static let horizontalIconSize: CGFloat = 16
    /// Pill padding around its buttons: canvas 8px.
    static let innerPadding: CGFloat = 4
    /// Canvas buttons are stacked with no gap; the horizontal bar keeps 2pt.
    static let verticalItemGap: CGFloat = 0
    static let horizontalItemGap: CGFloat = 2
    /// Canvas r64px on a 104px-wide pill: clamps to a capsule.
    static let cornerStyle: CornerStyle = .capsule
    static let capsuleCornerRadius: CGFloat = 32
    static let cornerRadius: CGFloat = 12
    /// Selected rail row: the vertical tray's width (canvas 104px), canvas
    /// 72px tall; glyph 35px (vs the 28px it replaces).
    static let selectedPillWidth: CGFloat = verticalButtonSize + 2 * innerPadding
    static let selectedPillHeight: CGFloat = 36
    static let selectedGlyphSize: CGFloat = 17.5
    /// Tray icon weight: the canvas's lucide icons are 2px strokes on a 24px
    /// grid (~1.5pt at 17.5pt), which `.regular` matches.
    static let iconWeight: Font.Weight = .regular

    // MARK: Derived

    static func glassTint(_ look: Look, for colorScheme: ColorScheme) -> Color? {
        if colorScheme == .dark {
            return Color(WorkspaceLayout.chromeBackgroundDark).opacity(look.tintOpacity)
        }
        return look.tintOpacity > 0 ? Color.white.opacity(look.tintOpacity) : nil
    }

    /// The layer over the glass, and the whole fill on the opaque fallback
    /// (pre-26 / Reduce Transparency / tests).
    static func surfaceFill(_ look: Look, for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(WorkspaceLayout.canvasBackgroundDark).opacity(look.surfaceOpacity)
            : Color.white.opacity(look.surfaceOpacity)
    }

    static func rimColor(_ look: Look) -> Color {
        Color.white.opacity(look.rimOpacity)
    }


    /// Canvas icon fill `#636363` = `textSecondaryLight`.
    static func iconColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }

    static func chromaticColors(_ palette: ChromaticPalette) -> [Color] {
        switch palette {
        case .pastel:
            // Cool on one side of the split, warm on the other (canvas CnDfN).
            return [
                Color(red: 0.62, green: 0.86, blue: 1.00),
                Color(red: 0.80, green: 0.74, blue: 1.00),
                Color(red: 1.00, green: 0.78, blue: 0.90),
                Color(red: 1.00, green: 0.95, blue: 0.70),
                Color(red: 0.74, green: 1.00, blue: 0.86),
                Color(red: 0.62, green: 0.86, blue: 1.00)
            ]
        case .rainbow:
            return [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]
        }
    }

    /// Tray button hover/press highlight, concentric with the pill it sits
    /// in: inner radius = outer radius − `innerPadding`. Capsule style: the
    /// pill is a full capsule, so its buttons' highlight is one too (a circle
    /// on the rail's square buttons). Radius style: `cornerRadius − innerPadding`.
    static func buttonHighlightShape(
        cornerStyle: CornerStyle = SidebarDialTuning.trayGlassCornerStyle(),
        cornerRadius: CGFloat = SidebarDialTuning.trayGlassCornerRadius(),
        innerPadding: CGFloat = SidebarDialTuning.trayInnerPadding()
    ) -> AnyShape {
        switch cornerStyle {
        case .capsule:
            return AnyShape(Capsule(style: .continuous))
        case .radius:
            return AnyShape(RoundedRectangle(cornerRadius: max(0, cornerRadius - innerPadding), style: .continuous))
        }
    }

    /// Unit point on the pill's edge the specular light enters from.
    static func specularStart(angle degrees: Double) -> UnitPoint {
        let r = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * cos(r), y: 0.5 - 0.5 * sin(r))
    }
}

/// Puts a view on the tray's white Liquid Glass (`TrayGlassStyle`) — the
/// tray's (both axes) and the selected rail row's shared surface. The white
/// layer, highlight and rims sit in the view's own background/overlay, so
/// `.glassEffect` draws the glass under them and the content stays on top.
/// Opaque white below macOS 26, under Reduce Transparency, or with
/// `forceOpaque` (tests: `cacheDisplay` can't capture glass).
struct TrayGlassSurface: ViewModifier {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var forceOpaque = false
    var interactive = false

    private var shape: RoundedRectangle {
        let radius = SidebarDialTuning.trayGlassCornerStyle() == .capsule
            ? TrayGlassStyle.capsuleCornerRadius
            : SidebarDialTuning.trayGlassCornerRadius()
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        let look = SidebarDialTuning.trayGlass(for: colorScheme)
        Group {
            if #available(macOS 26.0, *), !reduceTransparency, !forceOpaque {
                GlassEffectContainer {
                    content
                        .background {
                            ZStack {
                                shape.fill(TrayGlassStyle.surfaceFill(look, for: colorScheme))
                                specular(look)
                            }
                        }
                        .overlay(shape.strokeBorder(TrayGlassStyle.rimColor(look), lineWidth: look.rimWidth))
                        .overlay { chromaticRim(look) }
                }
                .glassEffect(glass(look), in: shape)
            } else {
                content.background(shape.fill(TrayGlassStyle.surfaceFill(look, for: colorScheme)))
            }
        }
        .shadow(
            color: Color.black.opacity(look.shadowOpacity),
            radius: look.shadowRadius,
            y: look.shadowYOffset
        )
    }

    @available(macOS 26.0, *)
    private func glass(_ look: TrayGlassStyle.Look) -> Glass {
        let base: Glass
        switch look.variant {
        case .regular: base = .regular
        case .clear: base = .clear
        case .identity: base = .identity
        }
        let tinted = base.tint(TrayGlassStyle.glassTint(look, for: colorScheme))
        return interactive ? tinted.interactive() : tinted
    }

    /// Iridescent edge, in either appearance. Not in the tree at all at
    /// intensity 0, so the default look is untouched.
    @ViewBuilder
    private func chromaticRim(_ look: TrayGlassStyle.Look) -> some View {
        if look.chromaticIntensity > 0 {
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: TrayGlassStyle.chromaticColors(look.chromaticPalette),
                        center: .center,
                        angle: .degrees(look.chromaticRotation)
                    ),
                    lineWidth: look.chromaticWidth
                )
                .blur(radius: look.chromaticBlur)
                .opacity(look.chromaticIntensity)
                .blendMode(look.chromaticBlend.blendMode)
                .allowsHitTesting(false)
        }
    }

    /// White highlight clipped to the pill. Not in the tree at strength 0.
    @ViewBuilder
    private func specular(_ look: TrayGlassStyle.Look) -> some View {
        if look.specularStrength > 0 {
            let start = TrayGlassStyle.specularStart(angle: look.specularAngle)
            shape
                .fill(LinearGradient(
                    colors: [Color.white.opacity(look.specularStrength), Color.white.opacity(0)],
                    startPoint: start,
                    endPoint: UnitPoint(x: 1 - start.x, y: 1 - start.y)
                ))
                .allowsHitTesting(false)
        }
    }
}

/// The selected session row's surface, in the rail and the expanded list
/// alike: the tray's glass (`TrayGlassSurface`, never interactive), so the
/// same per-appearance glass dials drive the tray, the rail pill and the
/// expanded row. Only the size adapts: the caller frames it (the rail's
/// fixed pill, the expanded row's full row frame), and the corner shape
/// follows the tray's corner style dial.
struct SidebarSelectedSurface: View {
    var body: some View {
        Color.clear.modifier(TrayGlassSurface())
    }
}

/// The glass pill that houses tray icon buttons, on either axis. One view,
/// not two: the axis switches its stack between `HStackLayout` and
/// `VStackLayout` through `AnyLayout`, which keeps every button's identity,
/// so flipping the axis inside an animation stretches the same capsule and
/// reflows the same buttons (the pinned⇄rail morph) instead of
/// cross-fading two pills.
struct SidebarTrayPill<Content: View>: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey) private var dialEpochTick = 0
    let axis: Axis
    /// Skips the glass effect so the pill renders as plain fill — the same
    /// path Reduce Transparency takes. Test seam: `cacheDisplay` can't capture
    /// glass, and the system setting can't be set from a test.
    var forceOpaque = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: TrayGlassStyle.verticalItemGap))
            : AnyLayout(HStackLayout(spacing: TrayGlassStyle.horizontalItemGap))
        layout(content)
            // The horizontal bar's flexible buttons claim the full width; the
            // vertical pill hugs its buttons.
            .frame(maxWidth: axis == .horizontal ? .infinity : nil)
            .padding(SidebarDialTuning.trayInnerPadding())
            .modifier(TrayGlassSurface(forceOpaque: forceOpaque, interactive: SidebarDialTuning.trayGlassInteractive()))
    }
}

/// The sidebar's one tray: the expanded sidebar's full-width horizontal bar
/// and the rail's vertical pill are this same view with a different axis.
/// Hosted once at the sidebar root (`SidebarHostRoot` in
/// `WorkspaceViewContainer`), outside the expanded/rail content it sits
/// over, so it keeps its identity while that content swaps and morphs
/// between the two shapes on the pinned⇄rail transition. Under Reduce
/// Motion the axis change snaps instead.
struct SidebarTray: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey) private var dialEpochTick = 0
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// See `EnvironmentValues.sidebarTrailingGutter`.
    @Environment(\.sidebarTrailingGutter) private var trailingGutter

    let isVertical: Bool
    /// "Collapse Sidebar" / "Expand Sidebar" / "Open Sidebar" — see
    /// `WorkspaceViewContainer.sidebarTrayItems`.
    let toggleLabel: String
    var forceOpaque = false
    /// `SidebarDialTuning.epoch()`, so a live dial change re-renders the tray.
    var dialEpoch = 0

    /// Space the tray occupies at the bottom of the sidebar, for the content
    /// underneath to reserve. Horizontal: bar + `bottomPadding`, plus the
    /// list-to-tray gap. Vertical: pill + `bottomPadding`.
    static func reservedHeight(isVertical: Bool, itemCount: Int) -> CGFloat {
        let padding = SidebarDialTuning.trayInnerPadding()
        if isVertical {
            let count = CGFloat(itemCount)
            let buttons = count * SidebarDialTuning.trayVerticalButtonSize()
                + max(0, count - 1) * TrayGlassStyle.verticalItemGap
            return buttons + 2 * padding + bottomPadding(isVertical: true)
        }
        return SidebarDialTuning.listToTrayGap() + SidebarDialTuning.trayHorizontalButtonSize()
            + 2 * padding + bottomPadding(isVertical: false)
    }

    static func bottomPadding(isVertical: Bool) -> CGFloat {
        isVertical ? 12 : 8
    }

    var body: some View {
        SidebarTrayPill(axis: isVertical ? .vertical : .horizontal, forceOpaque: forceOpaque) {
            ForEach(WorkspaceViewContainer.sidebarTrayItems(
                container: coordinator.containerView as? WorkspaceViewContainer,
                toggleLabel: toggleLabel
            )) { item in
                TrayIconButton(
                    itemId: item.id,
                    systemName: item.systemName,
                    label: item.label,
                    helpText: item.helpText,
                    isVertical: isVertical,
                    tapEffect: item.tapEffect,
                    action: item.action
                )
            }
        }
        // `trayMargin` is the visible gap on each side; on the trailing side
        // the gutter outside the column already provides part of it.
        .padding(.leading, isVertical ? 0 : SidebarDialTuning.trayMargin())
        .padding(.trailing, isVertical ? 0 : max(0, SidebarDialTuning.trayMargin() - trailingGutter))
        .padding(.bottom, Self.bottomPadding(isVertical: isVertical))
        // Centers the hugging vertical pill in the rail column.
        .frame(maxWidth: .infinity)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

/// An icon-only button hosted inside `SidebarTrayPill`, sized per axis from
/// `TrayGlassStyle`. The pill has no visible text, so the item's title
/// carries over as a tooltip and an accessibility label instead.
struct TrayIconButton: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey) private var dialEpochTick = 0
    /// `SidebarTrayItem.id`; only read by the capture fixture's hover hook.
    var itemId: String? = nil
    let systemName: String
    let label: String
    var helpText: String? = nil
    /// False in the expanded horizontal tray, where each icon takes an equal
    /// flexible share of the full-width bar (Flow 07 layer `wy7vi` et al.:
    /// each wrapper is `flex: 1 1 0`). True in the rail's vertical pill,
    /// where each button is a fixed square.
    var isVertical = false
    /// Symbol animation to play on click — see `TrayIconTapEffect`.
    var tapEffect: TrayIconTapEffect? = nil
    let action: () -> Void

    @State private var isHovered = false
    @State private var tapEffectTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = isVertical ? SidebarDialTuning.trayVerticalButtonSize() : SidebarDialTuning.trayHorizontalButtonSize()
        Button {
            tapEffectTrigger += 1
            action()
        } label: {
            icon
                // Hover lift on the glyph only: scaling the highlight too
                // would push it off its concentric inset. The glass path's
                // own `.interactive()` reacts to press, not hover. Reduce
                // Motion suppresses it like every other animation here.
                .scaleEffect(!reduceMotion && showsHover ? 1.06 : 1.0)
                .frame(
                    minWidth: isVertical ? size : nil,
                    maxWidth: isVertical ? size : .infinity,
                    minHeight: size,
                    maxHeight: size
                )
                .background(
                    TrayGlassStyle.buttonHighlightShape()
                        .fill(showsHover ? Color.primary.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsHover)
        .help(helpText ?? label)
        .accessibilityLabel(label)
    }

    private var showsHover: Bool {
        #if DEBUG
        isHovered || (itemId != nil && itemId == CaptureFixture.trayHoverItemId)
        #else
        isHovered
        #endif
    }

    @ViewBuilder
    private var icon: some View {
        let glyph = Image(systemName: systemName)
            .font(.system(
                size: isVertical ? SidebarDialTuning.trayVerticalIconSize() : SidebarDialTuning.trayHorizontalIconSize(),
                weight: TrayGlassStyle.iconWeight
            ))
            .foregroundStyle(TrayGlassStyle.iconColor(for: colorScheme))

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
