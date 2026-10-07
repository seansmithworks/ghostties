import SwiftUI

/// The tray's capsules, in order (pen.dev `bA1y9`, layout "B — Split
/// (2 + 1)"): Create (new session, new project), then the sidebar toggle on
/// its own. Leading to trailing in the expanded bar, top to bottom on the rail.
enum SidebarTrayGroup: String, CaseIterable {
    case create, toggle
}

/// One entry in the sidebar's bottom tray — icon, label, capsule, and action.
///
/// The single source of truth for what's in the tray. `SidebarTray` renders
/// this same ordered list on both axes (expanded/overlay and collapsed),
/// split into its `group`'s capsule, so adding an item is one new entry
/// here, not new layout code.
struct SidebarTrayItem: Identifiable {
    let id: String
    let systemName: String
    /// Accessibility label and hover tooltip.
    let label: String
    let group: SidebarTrayGroup
    /// Which symbol animation `TrayIconButton` plays on click. `nil` = none.
    let tapEffect: TrayIconTapEffect?
    let action: () -> Void

    init(
        id: String,
        systemName: String,
        label: String,
        group: SidebarTrayGroup,
        tapEffect: TrayIconTapEffect? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.systemName = systemName
        self.label = label
        self.group = group
        self.tapEffect = tapEffect
        self.action = action
    }
}

/// The click-triggered SF Symbol animation a `TrayIconButton` plays, gated
/// by `#available` (symbolEffect needs macOS 14+) and always suppressed
/// under Reduce Motion. Strawman for Sean to react to — restrained on purpose.
enum TrayIconTapEffect {
    case bounce
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
    /// How the selected session row (rail pill and expanded row) is drawn.
    /// `glass`: the tray's full glass treatment (`TrayGlassSurface`).
    /// `flat`: the tray's fill colour and corner shape only, with no glass,
    /// rims or specular, and a softer, closer shadow (`Look.selectedShadow…`),
    /// so the row reads as the tray's sibling rather than a second tray.
    enum SelectedStyle: String, CaseIterable {
        case glass, flat
    }

    /// The selected expanded row's title weight. The rail has no title.
    enum SelectedTitleWeight: String, CaseIterable {
        case regular, semibold

        var fontWeight: Font.Weight {
            self == .semibold ? .semibold : .regular
        }
    }

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
        /// The selected row's shadow in the `flat` selected style. The glass
        /// style uses the tray's shadow above.
        var selectedShadowOpacity: Double
        var selectedShadowRadius: CGFloat
        var selectedShadowYOffset: CGFloat
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
        specularAngle: 135,
        // Flat selected row: a soft contact shadow, well under the tray's.
        selectedShadowOpacity: 0.06,
        selectedShadowRadius: 4,
        selectedShadowYOffset: 1
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
        specularAngle: 135,
        // Flat selected row: the canvas-grey fill already sits lighter than
        // the chrome; a faint, tight shadow edges it without a halo.
        selectedShadowOpacity: 0.22,
        selectedShadowRadius: 3,
        selectedShadowYOffset: 1
    )

    static func defaultLook(for colorScheme: ColorScheme) -> Look {
        colorScheme == .dark ? dark : light
    }

    // MARK: Sizes

    /// Vertical (rail) tray button: canvas 88px (24px padding around a 40px
    /// icon frame). Icon: canvas 35px.
    static let verticalButtonSize: CGFloat = 44
    static let verticalIconSize: CGFloat = 17.5
    /// Horizontal (expanded) tray button, square like the rail's: Flow 07's
    /// 20×20 icon frame plus 8pt padding, so a capsule is 44pt tall with
    /// `innerPadding`.
    static let horizontalButtonSize: CGFloat = 36
    static let horizontalIconSize: CGFloat = 16
    /// Pill padding around its buttons: canvas 8px.
    static let innerPadding: CGFloat = 4
    /// Canvas buttons are stacked with no gap; the horizontal bar keeps 2pt.
    static let verticalItemGap: CGFloat = 0
    static let horizontalItemGap: CGFloat = 2
    /// Gap between the Create and Toggle capsules, on both axes: canvas 10px
    /// (`bA1y9` layout B).
    static let groupGap: CGFloat = 5
    /// Canvas r64px on a 104px-wide pill: clamps to a capsule.
    static let cornerStyle: CornerStyle = .capsule
    static let capsuleCornerRadius: CGFloat = 32
    static let cornerRadius: CGFloat = 12
    /// Default selected-row style (see `SelectedStyle`).
    static let selectedStyle: SelectedStyle = .flat
    /// Default selected-row title weight (see `SelectedTitleWeight`).
    static let selectedTitleWeight: SelectedTitleWeight = .semibold
    /// Selected rail row: the vertical tray's width (canvas 104px), canvas
    /// 72px tall; glyph 35px (vs the 28px it replaces).
    static let selectedPillWidth: CGFloat = verticalButtonSize + 2 * innerPadding
    static let selectedPillHeight: CGFloat = 36
    static let selectedGlyphSize: CGFloat = 17.5
    /// Tray icon weight: the canvas's lucide icons are 2px strokes on a 24px
    /// grid (~1.5pt at 17.5pt), which `.regular` matches.
    static let iconWeight: Font.Weight = .regular

    // MARK: Derived

    /// The pill shape the tray and the selected row share, from the corner
    /// style dial.
    static func pillShape() -> RoundedRectangle {
        let radius = SidebarDialTuning.trayGlassCornerStyle() == .capsule
            ? capsuleCornerRadius
            : SidebarDialTuning.trayGlassCornerRadius()
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

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
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var forceOpaque = false
    var interactive = false

    private var shape: RoundedRectangle { TrayGlassStyle.pillShape() }

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
/// alike, in the "Selected style" dial's style (`TrayGlassStyle.SelectedStyle`):
/// `glass` is the tray's glass (`TrayGlassSurface`, never interactive);
/// `flat` is the tray's fill colour and corner shape with the look's softer
/// selected shadow and nothing else. Either way the same per-appearance
/// dials drive the tray and this surface. Only the size adapts: the caller
/// frames it (the rail's fixed pill, the expanded row's full row frame).
struct SidebarSelectedSurface: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch SidebarDialTuning.selectedStyle() {
        case .glass:
            Color.clear.modifier(TrayGlassSurface())
        case .flat:
            let look = SidebarDialTuning.trayGlass(for: colorScheme)
            TrayGlassStyle.pillShape()
                .fill(TrayGlassStyle.surfaceFill(look, for: colorScheme))
                .shadow(
                    color: Color.black.opacity(look.selectedShadowOpacity),
                    radius: look.selectedShadowRadius,
                    y: look.selectedShadowYOffset
                )
        }
    }
}

/// One glass capsule of tray icon buttons, on either axis; it hugs its
/// buttons. One view, not two: the axis switches its stack between
/// `HStackLayout` and `VStackLayout` through `AnyLayout`, which keeps every
/// button's identity, so flipping the axis inside an animation stretches the
/// same capsule and reflows the same buttons (the pinned⇄rail morph) instead
/// of cross-fading two pills.
struct SidebarTrayPill<Content: View>: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
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
            .padding(SidebarDialTuning.trayInnerPadding())
            .modifier(TrayGlassSurface(forceOpaque: forceOpaque, interactive: SidebarDialTuning.trayGlassInteractive()))
    }
}

/// The sidebar's one tray: two capsules (`SidebarTrayGroup`), Create then
/// Toggle, side by side and leading-aligned in the expanded sidebar, stacked
/// and centred on the rail. Both axes are this same view: an outer
/// `AnyLayout` places the capsules and each capsule's own `AnyLayout` places
/// its buttons, so every capsule and button keeps its identity. Hosted once
/// at the sidebar root (`SidebarHostRoot` in `WorkspaceViewContainer`),
/// outside the expanded/rail content it sits over, so it keeps its identity
/// while that content swaps, and both capsules morph and reflow on the
/// pinned⇄rail transition. Under Reduce Motion the axis change snaps instead.
struct SidebarTray: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
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
    /// underneath to reserve. Horizontal: one capsule row + `bottomPadding`,
    /// plus the list-to-tray gap. Vertical: the stacked capsules, the gaps
    /// between them, and `bottomPadding`.
    static func reservedHeight(isVertical: Bool) -> CGFloat {
        let padding = SidebarDialTuning.trayInnerPadding()
        if isVertical {
            let counts = groupItemCounts()
            let capsules = counts.map { n -> CGFloat in
                let count = CGFloat(n)
                return count * SidebarDialTuning.trayVerticalButtonSize()
                    + max(0, count - 1) * TrayGlassStyle.verticalItemGap
                    + 2 * padding
            }
            let gaps = CGFloat(max(0, counts.count - 1)) * SidebarDialTuning.trayGroupGap()
            return capsules.reduce(0, +) + gaps + bottomPadding(isVertical: true)
        }
        return SidebarDialTuning.listToTrayGap() + SidebarDialTuning.trayHorizontalButtonSize()
            + 2 * padding + bottomPadding(isVertical: false)
    }

    static func bottomPadding(isVertical: Bool) -> CGFloat {
        isVertical ? 12 : 8
    }

    /// Item count per capsule, in `SidebarTrayGroup` order, empty capsules
    /// dropped.
    static func groupItemCounts() -> [Int] {
        let items = WorkspaceViewContainer.sidebarTrayItems(container: nil, toggleLabel: "")
        return SidebarTrayGroup.allCases
            .map { group in items.filter { $0.group == group }.count }
            .filter { $0 > 0 }
    }

    var body: some View {
        let items = WorkspaceViewContainer.sidebarTrayItems(
            container: coordinator.containerView as? WorkspaceViewContainer,
            toggleLabel: toggleLabel
        )
        let groups = SidebarTrayGroup.allCases.filter { group in items.contains { $0.group == group } }
        let axis: Axis = isVertical ? .vertical : .horizontal
        let gap = SidebarDialTuning.trayGroupGap()
        let groupLayout = isVertical
            ? AnyLayout(VStackLayout(alignment: .center, spacing: gap))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: gap))
        groupLayout {
            ForEach(groups, id: \.self) { group in
                SidebarTrayPill(axis: axis, forceOpaque: forceOpaque) {
                    ForEach(items.filter { $0.group == group }) { item in
                        TrayIconButton(
                            itemId: item.id,
                            systemName: item.systemName,
                            label: item.label,
                            isVertical: isVertical,
                            tapEffect: item.tapEffect,
                            action: item.action
                        )
                    }
                }
            }
        }
        // One glass container for both capsules, so neither samples the other.
        .modifier(TrayGlassGroupContainer(forceOpaque: forceOpaque))
        // `trayMargin` is the visible gap on each side; on the trailing side
        // the gutter outside the column already provides part of it.
        .padding(.leading, isVertical ? 0 : SidebarDialTuning.trayMargin())
        .padding(.trailing, isVertical ? 0 : max(0, SidebarDialTuning.trayMargin() - trailingGutter))
        .padding(.bottom, Self.bottomPadding(isVertical: isVertical))
        // Leading in the expanded sidebar (layout B); centred on the rail.
        .frame(maxWidth: .infinity, alignment: isVertical ? .center : .leading)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

/// Wraps both tray capsules in one `GlassEffectContainer` on the glass path,
/// so their glass renders together instead of one sampling the other.
/// Spacing 0: the capsules never melt into each other across the group gap.
/// A pass-through wherever `TrayGlassSurface` draws no glass.
private struct TrayGlassGroupContainer: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var forceOpaque = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency, !forceOpaque {
            GlassEffectContainer(spacing: 0) { content }
        } else {
            content
        }
    }
}

/// An icon-only square button hosted inside `SidebarTrayPill`, sized per
/// axis from `TrayGlassStyle`. The pill has no visible text, so the item's
/// title carries over as a tooltip and an accessibility label instead.
struct TrayIconButton: View {
    /// Subscribes this view to every dial write (`SidebarDialTuning.epochKey`):
    /// SwiftUI skips a body whose inputs are unchanged, and these views read
    /// `UserDefaults` inside it, so without this a live dial change never lands.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    /// `SidebarTrayItem.id`; only read by the capture fixture's hover hook.
    var itemId: String? = nil
    let systemName: String
    let label: String
    /// Picks the size dials: the rail's (true) or the expanded bar's (false).
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
                .frame(width: size, height: size)
                .background(
                    TrayGlassStyle.buttonHighlightShape()
                        .fill(showsHover ? Color.primary.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsHover)
        .help(label)
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
    /// collapsed rail's tray, each item tagged with its capsule. Settings is
    /// not in the tray; it lives in the app menu (Preferences…, Cmd+,).
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
            SidebarTrayItem(id: "newSession", systemName: "plus", label: "New Session", group: .create, tapEffect: .bounce) {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                container.presentComposerOverlay(projectBinding: .open)
            },
            // Same path as the header's "+ New Project" button
            // (`WorkspaceSidebarView.presentFolderPicker`): folder picker, then
            // the composer locked to the new project.
            SidebarTrayItem(id: "newProject", systemName: "folder.badge.plus", label: "New Project", group: .create, tapEffect: .bounce) {
                guard let container else {
                    assertionFailure("sidebarTrayItems: coordinator.containerView is not a WorkspaceViewContainer")
                    return
                }
                _ = container.addProjectViaFolderPickerAndOpenComposer()
            },
            // No `.contentTransition(.symbolEffect(.replace))` here: the icon
            // is the static "sidebar.left" glyph in every mode (pinned,
            // rail, overlay) — only `toggleLabel` changes — so there's no
            // natural pinned↔rail symbol pair to cross-fade between. Falls
            // back to `.bounce` per the brief.
            SidebarTrayItem(id: "toggleSidebar", systemName: "sidebar.left", label: toggleLabel, group: .toggle, tapEffect: .bounce) {
                container?.toggleSidebar()
            }
        ]
    }
}
