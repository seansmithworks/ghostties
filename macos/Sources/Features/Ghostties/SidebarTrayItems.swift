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

/// "Sidebar vnext" (pen.dev `CnDfN`): the sidebar tray, on both axes, is one
/// white Liquid Glass surface, and the selected session row's rim
/// (`SidebarRowCardBackground`) is its chromatic rim. Canvas values are
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

    /// The expanded tray's width. `fill`: the Create capsule stretches across
    /// the bar, from the leading margin to the group gap before the Toggle
    /// capsule, and its buttons share that width evenly. `hug`: both capsules
    /// hug their buttons, leading-aligned. The rail always hugs.
    enum TrayWidth: String, CaseIterable {
        case fill, hug
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
    }

    /// Light: the canvas (pen.dev `CnDfN`) values, unchanged from before the
    /// light/dark split.
    static let light = Look(
        variant: .identity,
        // 0 = untinted: the white comes from `surfaceOpacity`, since a native
        // `.tint(white 0.8)` blends far weaker than the canvas's 80% white
        // and reads grey.
        tintOpacity: 0.15,
        // Canvas base fill `#ffffffcc`.
        surfaceOpacity: 0.7,
        // Canvas `u_edgeWidth` 3px.
        rimWidth: 1.25,
        rimOpacity: 0.25,
        // Canvas outer shadow `#00000014`, y4px, blur 20px.
        shadowOpacity: 0.15,
        shadowRadius: 8,
        shadowYOffset: 3,
        // Tuned in the Dev DialKit (locked for beta.26).
        chromaticIntensity: 0.3,
        chromaticWidth: 2.25,
        chromaticRotation: 202.7,
        chromaticBlur: 1.7,
        chromaticPalette: .pastel,
        chromaticBlend: .normal,
        specularStrength: 0.5,
        specularAngle: 189
    )

    /// Dark: a raised canvas-grey pill (`canvasBackgroundDark` #2D2D2D over
    /// the #242424 chrome) on the warm-tinted glass, with a faint white rim
    /// and a deeper shadow, since an 8% black shadow vanishes on dark chrome.
    /// Specular is kept faint and no chromatic: a strong white highlight on dark glass lifts
    /// the background toward the grey text and icons and collapses their
    /// contrast.
    static let dark = Look(
        variant: .regular,
        tintOpacity: 0.55,
        surfaceOpacity: 0.9,
        rimWidth: 0.75,
        rimOpacity: 0.12,
        shadowOpacity: 0.506,
        shadowRadius: 8,
        shadowYOffset: 2,
        chromaticIntensity: 0,
        chromaticWidth: 1,
        chromaticRotation: 72.9,
        chromaticBlur: 0,
        chromaticPalette: .pastel,
        chromaticBlend: .plusLighter,
        specularStrength: 0.1,
        specularAngle: 268
    )

    static func defaultLook(for colorScheme: ColorScheme) -> Look {
        colorScheme == .dark ? dark : light
    }

    // MARK: Sizes

    /// Vertical (rail) tray button: canvas 88px (24px padding around a 40px
    /// icon frame). Icon: canvas 35px.
    static let verticalButtonSize: CGFloat = 44
    static let verticalIconSize: CGFloat = 18
    /// Horizontal (expanded) tray button, square like the rail's: Flow 07's
    /// 20×20 icon frame plus 8pt padding, so a capsule is 44pt tall with
    /// `innerPadding`.
    static let horizontalButtonSize: CGFloat = 44
    static let horizontalIconSize: CGFloat = 18
    /// Pill padding around its buttons: canvas 8px.
    static let innerPadding: CGFloat = 8
    /// Canvas buttons are stacked with no gap; the horizontal bar keeps 2pt.
    static let verticalItemGap: CGFloat = 0
    static let horizontalItemGap: CGFloat = 2
    /// Gap between the Create and Toggle capsules, on both axes: canvas 10px
    /// (`bA1y9` layout B).
    static let groupGap: CGFloat = 5
    /// Canvas r64px on a 104px-wide pill: clamps to a capsule.
    static let cornerStyle: CornerStyle = .radius
    static let capsuleCornerRadius: CGFloat = 32
    static let cornerRadius: CGFloat = 16.5
    /// Default expanded tray width (see `TrayWidth`).
    static let trayWidth: TrayWidth = .fill
    /// Default selected-row title weight (see `SelectedTitleWeight`).
    static let selectedTitleWeight: SelectedTitleWeight = .semibold
    /// Default rim intensity of the Tint + shimmer selected row in dark: the
    /// light look's, so the row reads the same across themes.
    static let tintShimmerDarkIntensity: Double = light.chromaticIntensity
    /// Rail hairline width (`SidebarSectionHairlineSlot`), the vertical
    /// tray's width (canvas 104px). Selected rows no longer read it: they
    /// fill the hover card (`SidebarRowCardBackground`).
    static let selectedPillWidth: CGFloat = 44
    /// Selected rail glyph: canvas 35px (vs the 28px it replaces).
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

    /// Tray button hover/press highlight, Finder's toolbar rule (Sean,
    /// 2026-10-08). A capsule holding one button: the highlight is the
    /// capsule itself (`pillShape()`, drawn by the button, which owns the
    /// capsule's padding). A capsule holding several: concentric with it,
    /// inset by `innerPadding` on every outer edge, inner radius = outer
    /// radius − `innerPadding` on all four corners, the shared edges
    /// included, like Finder's segmented groups. Capsule style: the pill is a
    /// full capsule, so its buttons' highlight is one too. Radius style:
    /// `cornerRadius − innerPadding`.
    static func buttonHighlightShape(
        soleInCapsule: Bool,
        cornerStyle: CornerStyle = SidebarDialTuning.trayGlassCornerStyle(),
        cornerRadius: CGFloat = SidebarDialTuning.trayGlassCornerRadius(),
        innerPadding: CGFloat = SidebarDialTuning.trayInnerPadding()
    ) -> AnyShape {
        if soleInCapsule { return AnyShape(pillShape()) }
        return concentricHighlightShape(cornerStyle: cornerStyle, cornerRadius: cornerRadius, innerPadding: innerPadding)
    }

    private static func concentricHighlightShape(
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

/// The iridescent edge, in either appearance: the tray glass's and the
/// "Tint + shimmer" selected row's shared rim. Not in the tree at all at
/// intensity 0, so the default look is untouched.
struct TrayChromaticRim: View {
    let look: TrayGlassStyle.Look
    let shape: RoundedRectangle

    var body: some View {
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
}

/// Puts a view on the tray's white Liquid Glass (`TrayGlassStyle`), on both
/// axes. The white
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

    private func chromaticRim(_ look: TrayGlassStyle.Look) -> some View {
        TrayChromaticRim(look: look, shape: shape)
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

/// A sidebar row card's background, hover and selected alike, in the rail
/// and the expanded list. Both states draw the same shape filling the row
/// frame, so the selected card's footprint is the hover's by construction
/// (Sean, 2026-10-07: "the size of the hover feels good to me, filling the
/// space"). Selected is "Tint + shimmer" (Sean, 2026-10-08): a faint primary
/// tint with the tray glass's chromatic rim; hover is a fainter tint, and
/// the selected row ignores it.
struct SidebarRowCardBackground: View {
    let isActive: Bool
    let isHovered: Bool
    var cornerRadius: CGFloat = WorkspaceLayout.sidebarRowCornerRadiusResting

    /// Tint behind the selected row.
    static let selectedTintOpacity: Double = 0.075
    /// Tint behind a hovered, unselected row: subordinate to the selected tint.
    static let hoverTintOpacity: Double = 0.04

    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if isActive {
            shape
                .fill(Color.primary.opacity(Self.selectedTintOpacity))
                .overlay {
                    TrayChromaticRim(look: tintShimmerLook, shape: shape)
                }
        } else {
            shape.fill(isHovered ? Color.primary.opacity(Self.hoverTintOpacity) : .clear)
        }
    }

    /// The rim look. Dark's glass look has no rim (intensity 0), so this row
    /// alone takes its dark intensity from its own dial ("Shimmer (dark)").
    private var tintShimmerLook: TrayGlassStyle.Look {
        var look = SidebarDialTuning.trayGlass(for: colorScheme)
        if colorScheme == .dark {
            look.chromaticIntensity = SidebarDialTuning.tintShimmerDarkIntensity()
        }
        return look
    }
}

/// One glass capsule of tray icon buttons, on either axis; it hugs its
/// buttons, which may themselves flex (`TrayIconButton.fillsWidth`). One view, not two: the axis switches its stack between
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
    /// DEBUG Redlines tag for this capsule (its content is `<id>.content`).
    var redlineID: String? = nil
    /// Rail A2: the capsule fills the width it is offered instead of hugging,
    /// its buttons (still their dial size) centred inside.
    var stretchesAcross = false
    /// The capsule holds one button, which takes the capsule's padding
    /// itself (`TrayIconButton.fillsCapsule`) so its hover fills the whole
    /// capsule. Same capsule size either way.
    var soleButton = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: TrayGlassStyle.verticalItemGap))
            : AnyLayout(HStackLayout(spacing: TrayGlassStyle.horizontalItemGap))
        let framed = layout(content)
            .frame(maxWidth: stretchesAcross ? .infinity : nil)
            .redlineFrame(redlineID.map { $0 + ".content" })
            .padding(soleButton ? 0 : SidebarDialTuning.trayInnerPadding())
            .redlineFrame(redlineID)
        framed.modifier(TrayGlassSurface(forceOpaque: forceOpaque, interactive: SidebarDialTuning.trayGlassInteractive()))
    }
}

/// The sidebar's one tray: two capsules (`SidebarTrayGroup`), Create then
/// Toggle, side by side in the expanded sidebar (Create filling the bar, or
/// both hugging and leading-aligned, per the "Tray width" dial), stacked and
/// centred on the rail. Both axes are this same view: an outer
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

    /// The tray's gap to the window's bottom edge: the window margin, on
    /// both axes, so it matches the terminal card's bottom inset.
    static func bottomPadding(isVertical: Bool) -> CGFloat {
        SidebarDialTuning.windowMargin()
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
        // Expanded "Tray width: fill": the Create capsule takes the bar's
        // spare width (its buttons flex; the Toggle capsule's stay square).
        let fillsCreate = !isVertical && SidebarDialTuning.trayWidth() == .fill
        groupLayout {
            ForEach(groups, id: \.self) { group in
                let groupItems = items.filter { $0.group == group }
                let sole = groupItems.count == 1
                SidebarTrayPill(axis: axis, forceOpaque: forceOpaque, redlineID: RedlineID.trayPill(group.rawValue), stretchesAcross: isVertical, soleButton: sole) {
                    ForEach(groupItems) { item in
                        TrayIconButton(
                            itemId: item.id,
                            systemName: item.systemName,
                            label: item.label,
                            isVertical: isVertical,
                            // Rail: the stretched capsule is wider than its
                            // buttons, so they fill it to keep the highlight's
                            // side inset equal to its top and bottom inset.
                            fillsWidth: isVertical || (fillsCreate && group == .create),
                            fillsCapsule: sole,
                            tapEffect: item.tapEffect,
                            action: item.action
                        )
                    }
                }
            }
        }
        // One glass container for both capsules, so neither samples the other.
        .modifier(TrayGlassGroupContainer(forceOpaque: forceOpaque))
        .redlineFrame(RedlineID.trayGroup)
        // Expanded: the window margin is the visible gap on each side; on
        // the trailing side the gutter outside the column already provides
        // part of it. Rail (A2): the stretched capsules sit
        // `railTrayCapsuleInset` from the window edge and from the card,
        // centred on the full rail, the same centre as its row column.
        .padding(.leading, isVertical ? WorkspaceLayout.railTrayCapsuleInset : SidebarDialTuning.windowMargin())
        .padding(.trailing, isVertical ? WorkspaceLayout.railTrayCapsuleInset : max(0, SidebarDialTuning.windowMargin() - trailingGutter))
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
    /// Takes an equal share of its capsule's spare width instead of staying
    /// square (the expanded Create capsule under "Tray width: fill", and every
    /// rail capsule, which is stretched wider than its buttons). Height
    /// is fixed either way, and the hover highlight fills the cell, so it
    /// keeps the capsule's concentric inset.
    var fillsWidth = false
    /// The only button in its capsule (`SidebarTrayPill.soleButton`): it
    /// carries the capsule's padding, so its hover fill and hit area are the
    /// capsule's own shape (`TrayGlassStyle.buttonHighlightShape`).
    var fillsCapsule = false
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
                // One flexible frame for both widths, so flipping
                // `fillsWidth` (the pinned⇄rail morph) animates the cell's
                // width instead of swapping modifiers. min = ideal = max =
                // `size` is the square cell.
                .frame(
                    minWidth: size,
                    idealWidth: size,
                    maxWidth: fillsWidth ? .infinity : size,
                    minHeight: size,
                    maxHeight: size
                )
                .padding(fillsCapsule ? SidebarDialTuning.trayInnerPadding() : 0)
                .background {
                    highlightShape
                        .fill(showsHover ? Color.primary.opacity(0.10) : .clear)
                }
                // Hover and click land anywhere in the highlight's shape,
                // not just on the glyph.
                .contentShape(highlightShape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsHover)
        .help(label)
        .accessibilityLabel(label)
    }

    private var highlightShape: AnyShape {
        TrayGlassStyle.buttonHighlightShape(soleInCapsule: fillsCapsule)
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
