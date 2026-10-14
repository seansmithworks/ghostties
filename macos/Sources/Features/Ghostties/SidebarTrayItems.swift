import SwiftUI

/// The tray's capsules, in order (pen.dev `bA1y9`, layout "B — Split
/// (2 + 1)"): Create (new session, new project), then the sidebar toggle on
/// its own. Leading to trailing in the expanded bar, top to bottom on the rail.
enum SidebarTrayGroup: String, CaseIterable {
    case create, toggle

    /// The capsule's end of the expanded bar, which picks the corner that
    /// nests in the hover bar (`TrayGlassStyle.hoverBarPillCorners`).
    var side: HorizontalEdge { self == .create ? .leading : .trailing }
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
/// white Liquid Glass surface. Canvas values are
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
    /// to a full capsule on every pill this tray draws; `radius` is
    /// concentric with the window corner (`SidebarDialTuning.trayCornerRadius`).
    enum CornerStyle: String, CaseIterable {
        case capsule, radius
    }

    /// Colour stops for the chromatic rim. `pastel` and `rainbow` are the
    /// canvas's own; the rest are built from `WorkspaceLayout` tokens
    /// (`chromaticColors(_:for:)` lists each stop and its token).
    enum ChromaticPalette: String, CaseIterable {
        case pastel, rainbow
        /// Terracotta warming into the chrome/canvas creams.
        case ember
        /// Warm grey into the chrome/canvas creams: a brushed-metal edge.
        case chrome
        /// One graphite tone all the way round: a plain hairline ring.
        case mono
        /// The session-status colours: your-turn blue, decision gold,
        /// long-running orange.
        case signal
    }

    /// A system material drawn under the surface layer: a real blur of
    /// whatever sits behind the pill (the list scrolling under the tray).
    /// The native `Glass` has no blur amount of its own, only its variant,
    /// so these steps are the blur control. `none` draws no layer at all.
    enum BackdropMaterial: String, CaseIterable {
        case none, ultraThin, thin, regular, thick, ultraThick

        var material: Material? {
            switch self {
            case .none: return nil
            case .ultraThin: return .ultraThinMaterial
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            case .ultraThick: return .ultraThickMaterial
            }
        }
    }

    /// The expanded tray's width. `fill`: the Create capsule stretches across
    /// the bar, from the leading margin to the group gap before the Toggle
    /// capsule, and its buttons share that width evenly. `hug`: both capsules
    /// hug their buttons, leading-aligned. `split` (option D): both hug,
    /// Create at the leading margin, Toggle at the trailing one. The rail
    /// always hugs.
    enum TrayWidth: String, CaseIterable {
        case fill, hug, split
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
        /// terracotta accent. The `.identity` variant draws no material, so
        /// it ignores the tint; it only shows on `.regular`/`.clear`.
        var tintOpacity: Double
        /// The layer laid over the glass: white in light, the chrome
        /// (`WorkspaceLayout.chromeBackgroundDark`) in dark, so dark glass
        /// is never lighter than the chrome it floats on.
        var surfaceOpacity: Double
        /// Rim standing in for the shader's fresnel edge: white in light,
        /// the dark border in dark (`rimColor`).
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
        // The blur dials. Each defaults to "not drawn", so a `Look(...)`
        // that omits them draws no blur; `light` and `dark` set them.
        /// Material blurring what's behind the pill, under the surface
        /// layer. Only shows where the surface layer lets it through.
        var backdropMaterial: BackdropMaterial = .none
        /// The backdrop material's opacity, 0–1.
        var backdropOpacity: Double = 1
        /// Gaussian blur on the surface layer, clipped to the pill: the
        /// layer thins toward the edge and the backdrop shows there. 0 =
        /// not blurred.
        var surfaceBlur: CGFloat = 0
    }

    /// Light: Sean's DialKit export (re-baked 2026-10-11, second export).
    /// The base was the canvas (pen.dev `CnDfN`) values; the white layer is
    /// now thinner than the canvas so the regular backdrop blur shows
    /// through it, and the chromatic edge is the status-colour `signal`.
    static let light = Look(
        variant: .identity,
        // The white comes from the tint and the layer together, since a
        // native `.tint(white)` blends far weaker than the canvas's white
        // fill and reads grey.
        tintOpacity: 0.35,
        // Canvas base fill was `#ffffffcc` (0.8); tuned to 0.6, so the
        // backdrop blur under it reads.
        surfaceOpacity: 0.6,
        // Canvas `u_edgeWidth` was 3px (1.25pt); tuned to 1pt.
        rimWidth: 1,
        rimOpacity: 0.6,
        // Option D (`ab279`) was 15%, blur 16, y 3. A canvas blur is twice
        // a SwiftUI shadow radius, as on the canvas card (blur 16 = radius
        // 8). Sean (2026-10-11): too heavy and riding high, and light-mode
        // shadows stay at or under 20% — lightened to 10% and dropped 3pt
        // (SwiftUI's positive y is down), so less of it shows above the pill.
        // Sean's "Tray shadow" DialKit tune (beta.27): 12%, radius 8, y 4,
        // the default for every state (sidebar, rail, hover bar).
        shadowOpacity: 0.12,
        shadowRadius: 8,
        shadowYOffset: 4,
        // Tuned in the Dev DialKit (re-baked 2026-10-11, second export).
        chromaticIntensity: 0.15,
        chromaticWidth: 1.5,
        chromaticRotation: 80,
        chromaticBlur: 2.5,
        chromaticPalette: .signal,
        chromaticBlend: .normal,
        specularStrength: 0.75,
        specularAngle: 270,
        backdropMaterial: .regular,
        backdropOpacity: 0.75,
        surfaceBlur: 6
    )

    /// Dark: Sean's DialKit export (2026-10-11, second export), drawn as dark
    /// glass: the layer is the chrome (`chromeBackgroundDark`, never the
    /// lighter canvas grey) over the regular backdrop blur, and the rim is
    /// a dark stroke (`WorkspaceLayout.borderDark`, `rimColor`), not white:
    /// a white rim drew a bright outline on the dark toolbar. The specular
    /// stays faint (0.10): any white gradient lifts the fill above the
    /// chrome, and a 0.6 one from below turned the pill's lower half pale
    /// grey and dropped the icons to 1.1:1. A deeper shadow than light's,
    /// since an 8% black shadow vanishes on dark chrome.
    static let dark = Look(
        variant: .identity,
        tintOpacity: 0.35,
        surfaceOpacity: 0.6,
        rimWidth: 1,
        rimOpacity: 0.6,
        // Light's lift, at the opacity dark chrome needs to show it.
        shadowOpacity: 0.4,
        shadowRadius: 12,
        shadowYOffset: 4,
        chromaticIntensity: 0.15,
        chromaticWidth: 1.5,
        chromaticRotation: 80,
        chromaticBlur: 2.5,
        chromaticPalette: .signal,
        chromaticBlend: .normal,
        specularStrength: 0.1,
        specularAngle: 270,
        backdropMaterial: .regular,
        backdropOpacity: 0.75,
        surfaceBlur: 6
    )

    static func defaultLook(for colorScheme: ColorScheme) -> Look {
        colorScheme == .dark ? dark : light
    }

    // MARK: Sizes

    /// Vertical (rail) tray icon: canvas 35px. The rail's button size is
    /// not a constant: it follows the rail's width (`RailTrayGeometry`).
    static let verticalIconSize: CGFloat = 18
    /// Horizontal (expanded) tray button, square like the rail's. Option D:
    /// 48, the capsule's full height (no padding across the bar).
    static let horizontalButtonSize: CGFloat = 48
    static let horizontalIconSize: CGFloat = 18
    /// A capsule's padding along its axis, outside its first and last
    /// button, when it holds more than one (option D `[0, 2]` / `[2, 0]`).
    /// Across the axis the buttons fill the capsule; a one-button capsule
    /// is its button.
    static let innerPadding: CGFloat = 2
    /// Between the two icons of the rail's stacked Create pill
    /// (`RailTrayGeometry.iconGap`). Option D: the stacked buttons are
    /// square 48pt cells like the bar's, so icon + gap = 48 (centres 48pt
    /// apart).
    static let railIconGap: CGFloat = 30
    /// The rail tray's square pill side (option D `emGcV`: 48, centred on
    /// the rail). Read it through `SidebarDialTuning.railTrayPillSize()`.
    static let railPillSize: CGFloat = 48
    /// The hover chip's inset from its button cell on every side, Finder's
    /// toolbar rule. Read it through `SidebarDialTuning.trayHoverInset()`.
    static let hoverInset: CGFloat = 4
    /// The smallest corner a grouped pill's hover chip takes (Sean,
    /// 2026-10-11): below 6pt the chip reads square.
    static let hoverMinimumCornerRadius: CGFloat = 6
    /// Gap between the expanded bar's buttons (option D: none, the square
    /// cells abut). The rail's follows from its cells (`RailTrayGeometry.itemGap`).
    static let horizontalItemGap: CGFloat = 0
    /// Gap between the Create and Toggle capsules in the expanded bar
    /// (`bA1y9` layout B; tuned in the Dev DialKit to the 8pt grid). The
    /// rail's is its window margin (`RailTrayGeometry.groupGap`).
    static let groupGap: CGFloat = 8
    /// Canvas r64px on a 104px-wide pill: clamps to a capsule.
    static let cornerStyle: CornerStyle = .radius
    static let capsuleCornerRadius: CGFloat = 32
    /// Default expanded tray width (see `TrayWidth`; option D: `split`).
    static let trayWidth: TrayWidth = .split
    /// Default selected-row title weight (see `SelectedTitleWeight`).
    static let selectedTitleWeight: SelectedTitleWeight = .regular
    /// Tray icon weight: the canvas's lucide icons are 2px strokes on a 24px
    /// grid (~1.5pt at 17.5pt), which `.regular` matches.
    static let iconWeight: Font.Weight = .regular

    // MARK: Derived

    /// The pill shape the tray and the selected row share, from the corner
    /// style dial. In the hover bar (overlay, "radius" style) a pill at
    /// `side` nests only its outer corner (`hoverBarPillCorners`); every
    /// other mode, or with no side, all four corners are one radius.
    static func pillShape(for mode: SidebarMode = .pinned, side: HorizontalEdge? = nil) -> TrayPillShape {
        if mode == .overlay, let side, SidebarDialTuning.trayGlassCornerStyle() == .radius {
            let c = hoverBarPillCorners(side: side)
            return TrayPillShape(
                topLeading: c.topLeading, topTrailing: c.topTrailing,
                bottomLeading: c.bottomLeading, bottomTrailing: c.bottomTrailing
            )
        }
        return TrayPillShape(cornerRadius: pillCornerRadius(for: mode))
    }

    /// The hover bar's pill corners (beta.26 round 2, Sean): the pinned and
    /// rail pills' radius on three corners; only the corner sitting in the
    /// overlay card's own bottom corner nests, concentric with the card
    /// (`trayCornerRadius(for: .overlay)`: 12 − 8 = 4 at the default margin).
    /// `.leading` is the Create pill (bottom-leading nests), `.trailing` the
    /// Toggle pill (bottom-trailing).
    static func hoverBarPillCorners(
        side: HorizontalEdge,
        defaults: UserDefaults = SidebarDialTuning.store
    ) -> (topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        let open = SidebarDialTuning.trayCornerRadius(for: .pinned, defaults: defaults)
        let nested = SidebarDialTuning.trayCornerRadius(for: .overlay, defaults: defaults)
        switch side {
        case .leading: return (open, open, nested, open)
        case .trailing: return (open, open, open, nested)
        }
    }

    /// The pill's corner radius in `mode`, from the corner style dial.
    static func pillCornerRadius(for mode: SidebarMode = .pinned) -> CGFloat {
        SidebarDialTuning.trayGlassCornerStyle() == .capsule
            ? capsuleCornerRadius
            : SidebarDialTuning.trayCornerRadius(for: mode)
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
            ? Color(WorkspaceLayout.chromeBackgroundDark).opacity(look.surfaceOpacity)
            : Color.white.opacity(look.surfaceOpacity)
    }

    /// The glass rim: white in light, the dark border token
    /// (`WorkspaceLayout.borderDark`) in dark, so the dark pill's edge is a
    /// dark-mode stroke, not a bright outline. The rim opacity and width
    /// dials scale it in both.
    static func rimColor(_ look: Look, for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(WorkspaceLayout.borderDark).opacity(look.rimOpacity)
            : Color.white.opacity(look.rimOpacity)
    }

    /// The opaque fallback's dark edge (Reduce Transparency / pre-26). That
    /// path draws no glass rim or chromatic stroke, and its chrome-coloured
    /// fill sits on the chrome, so without this hairline only a shadow,
    /// invisible on dark chrome, separated the pill. A dark-mode stroke like
    /// the glass rim, at the beta.26 canvas grey #2D2D2D (pinned here when
    /// `canvasBackgroundDark` moved to #141413, below the chrome, in beta.27):
    /// the strongest dark token step off the #242424 chrome (1.13:1, the
    /// same step that sets the terminal card off the chrome; `borderDark`
    /// is 1.08:1). 3:1 needs about #717171, a light grey, which is the
    /// bright outline this replaces. The icons, which identify the buttons,
    /// keep 5.45:1. An edge, not a fill: the pill stays at the chrome's
    /// lightness.
    static let opaqueDarkEdgeColor = Color(NSColor(white: 0.18, alpha: 1))
    static let opaqueDarkEdgeWidth: CGFloat = 1


    /// Canvas icon fill: `textSecondaryLight`.
    static func iconColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }

    /// The rim's gradient stops, swept round the pill from
    /// `chromaticRotation`. The token palettes resolve their neutral stops
    /// per appearance: in dark they are the dark chrome/canvas greys, the
    /// glass's own colour, so they add next to nothing under the dark
    /// look's `plusLighter` blend and only the accent stops show.
    static func chromaticColors(_ palette: ChromaticPalette, for colorScheme: ColorScheme = .light) -> [Color] {
        let dark = colorScheme == .dark
        let chrome = Color(dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight)
        let canvas = Color(dark ? WorkspaceLayout.canvasBackgroundDark : WorkspaceLayout.canvasBackgroundLight)
        let graphite = dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
        switch palette {
        case .ember:
            // waitingTerracotta → chromeBackground → canvasBackground → chromeBackground → waitingTerracotta
            let accent = WorkspaceLayout.waitingTerracotta
            return [accent, chrome, canvas, chrome, accent]
        case .chrome:
            // textSecondary → chromeBackground → canvasBackground → chromeBackground → textSecondary
            return [graphite, chrome, canvas, chrome, graphite]
        case .mono:
            // textSecondary, one tone.
            return [graphite, graphite]
        case .signal:
            // statusYourTurnBlue → statusNeedsDecisionGold → statusLongRunningOrange → statusYourTurnBlue.
            // Dark puts chromeBackgroundDark between them, so the bright
            // gold and orange are short arcs instead of the whole rim.
            let blue = WorkspaceLayout.statusYourTurnBlue
            let gold = WorkspaceLayout.statusNeedsDecisionGold
            let orange = WorkspaceLayout.statusLongRunningOrange
            return dark
                ? [blue, chrome, gold, chrome, orange, chrome, blue]
                : [blue, gold, orange, blue]
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

    /// Tray button hover highlight (Sean, 2026-10-11). A sole button in
    /// its capsule (`fillsCapsule`, the sidebar toggle) hovers full bleed,
    /// like a macOS toolbar button: the chip is the whole cell, which is the
    /// capsule, with the pill's corner radius (concentric, inset 0). A button in a grouped pill
    /// keeps an inset chip, the cell inset by `inset` on every side, so
    /// adjacent chips sit `2 × inset` apart and a chip never touches its
    /// pill's edge. Its corner is concentric with the pill's (the pill
    /// radius less the capsule padding `innerPadding` and `inset`, the same
    /// concentric step `buttonHitShape` takes) but never under
    /// `hoverMinimumCornerRadius`, so it always reads rounded. A capsule
    /// pill's radius makes either chip a capsule.
    struct HoverChip: Equatable {
        let frame: CGRect
        let cornerRadius: CGFloat
    }

    static func hoverChip(
        cell: CGRect,
        soleInCapsule: Bool,
        inset: CGFloat = SidebarDialTuning.trayHoverInset(),
        innerPadding: CGFloat = SidebarDialTuning.trayInnerPadding(),
        pillCornerRadius: CGFloat = TrayGlassStyle.pillCornerRadius()
    ) -> HoverChip {
        if soleInCapsule {
            // Full bleed: the chip is the capsule, inset 0 from the pill.
            return HoverChip(
                frame: cell,
                cornerRadius: WorkspaceLayout.concentricRadius(parent: pillCornerRadius, inset: 0)
            )
        }
        let inset = max(0, inset)
        let concentric = WorkspaceLayout.concentricRadius(
            parent: pillCornerRadius, inset: max(0, innerPadding) + inset
        )
        return HoverChip(
            frame: cell.insetBy(dx: inset, dy: inset),
            cornerRadius: max(concentric, hoverMinimumCornerRadius)
        )
    }

    /// A tray button's hit area. A capsule holding one button: the capsule
    /// itself (`pillShape()`, the button owns the capsule's padding). A
    /// capsule holding several: the cell, concentric with the capsule,
    /// radius `cornerRadius − innerPadding` (capsule style: a capsule).
    static func buttonHitShape(
        soleInCapsule: Bool,
        mode: SidebarMode = .pinned,
        side: HorizontalEdge? = nil,
        cornerStyle: CornerStyle = SidebarDialTuning.trayGlassCornerStyle(),
        innerPadding: CGFloat = SidebarDialTuning.trayInnerPadding()
    ) -> AnyShape {
        let cornerRadius = SidebarDialTuning.trayCornerRadius(for: mode)
        if soleInCapsule { return AnyShape(pillShape(for: mode, side: side)) }
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

/// The collapsed rail's tray (option D, 2026-10-09: the expanded bar's
/// square 48pt cells, stacked and centred on the rail). Everything follows
/// from the dials:
///
/// - `cell`: the pill width, the pill size dial capped at the rail width less
///   the window margin on each side. The Toggle pill is one square cell.
/// - The Create pill stacks its buttons, each `cell` wide and `icon +
///   iconGap` tall (48 at the defaults: square), abutting, with the capsule
///   padding (`stackedPadding`) above the first and below the last; that
///   padding still takes clicks for the outer buttons.
/// - Outside the pills, the gap between them and the bottom margin are the
///   window margin.
///
/// Pure values, so tests can check the geometry without rendering.
struct RailTrayGeometry: Equatable {
    let railWidth: CGFloat
    /// `SidebarDialTuning.windowMargin()`.
    let margin: CGFloat
    /// `SidebarDialTuning.trayInnerPadding()`.
    let padding: CGFloat
    /// `SidebarDialTuning.trayVerticalIconSize()`.
    var iconSize: CGFloat = TrayGlassStyle.verticalIconSize
    /// `SidebarDialTuning.railTrayIconGap()`.
    var iconGap: CGFloat = TrayGlassStyle.railIconGap
    /// `SidebarDialTuning.railTrayPillSize()`.
    var pillSize: CGFloat = TrayGlassStyle.railPillSize

    /// The live geometry at the current dial values.
    static func current(railWidth: CGFloat) -> RailTrayGeometry {
        RailTrayGeometry(
            railWidth: railWidth,
            margin: SidebarDialTuning.windowMargin(),
            padding: SidebarDialTuning.trayInnerPadding(),
            iconSize: SidebarDialTuning.trayVerticalIconSize(),
            iconGap: max(0, SidebarDialTuning.railTrayIconGap()),
            pillSize: SidebarDialTuning.railTrayPillSize()
        )
    }

    /// The pill's width, and the side of the Toggle pill's square: the
    /// pill size dial (option D: 48), never wider than the rail less its
    /// margins.
    var cell: CGFloat { max(0, min(pillSize, railWidth - 2 * margin)) }
    /// An icon's inset to its pill's side edges.
    var edgeInset: CGFloat { max(0, (cell - iconSize) / 2) }
    /// A button's width inside its pill, and the Toggle button's side: the
    /// buttons fill the pill across the rail (option D).
    var buttonSize: CGFloat { cell }
    /// One stacked Create button's height: its icon and half the gap on
    /// each side.
    var stackedButtonHeight: CGFloat { iconSize + iconGap }
    /// The stacked pill's top and bottom padding, outside its outer buttons:
    /// the capsule padding along its axis (option D: 2).
    var stackedPadding: CGFloat { max(0, padding) }
    /// Between two stacked buttons: none, the gap lives inside them.
    var itemGap: CGFloat { 0 }
    /// Between the Create and Toggle pills.
    var groupGap: CGFloat { margin }
    /// Below the Toggle pill, to the window's bottom edge.
    var bottomMargin: CGFloat { margin }

    /// A pill holding `items` buttons, as `SidebarTray` lays it out: one
    /// square cell for a single button, else the stacked buttons and their
    /// top and bottom padding.
    func pillHeight(items: Int) -> CGFloat {
        guard items > 1 else { return cell }
        return CGFloat(items) * stackedButtonHeight + 2 * stackedPadding
    }

    /// The whole tray, pills, gaps and bottom margin, for the rail to reserve.
    func trayHeight(groupItemCounts: [Int]) -> CGFloat {
        let pills = groupItemCounts.map(pillHeight(items:)).reduce(0, +)
        return pills + CGFloat(max(0, groupItemCounts.count - 1)) * groupGap + bottomMargin
    }
}

/// The tray pill's outline: a continuous rounded rectangle, one radius on
/// all four corners or, in the hover bar, one nested corner
/// (`TrayGlassStyle.pillShape`). Four equal corners draw exactly the
/// `RoundedRectangle` the pill always was; the radii animate either way.
struct TrayPillShape: InsettableShape {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat
    private var insetAmount: CGFloat = 0

    init(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    init(cornerRadius: CGFloat) {
        self.init(topLeading: cornerRadius, topTrailing: cornerRadius, bottomLeading: cornerRadius, bottomTrailing: cornerRadius)
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(topLeading, topTrailing), AnimatablePair(bottomLeading, bottomTrailing)) }
        set {
            topLeading = newValue.first.first
            topTrailing = newValue.first.second
            bottomLeading = newValue.second.first
            bottomTrailing = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if topLeading == topTrailing, topLeading == bottomLeading, topLeading == bottomTrailing {
            return RoundedRectangle(cornerRadius: topLeading, style: .continuous)
                .inset(by: insetAmount)
                .path(in: rect)
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing,
            style: .continuous
        )
        .inset(by: insetAmount)
        .path(in: rect)
    }

    func inset(by amount: CGFloat) -> TrayPillShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// The iridescent edge of the tray glass, in either appearance. Not in the tree at all at
/// intensity 0, so the default look is untouched.
struct TrayChromaticRim: View {
    let look: TrayGlassStyle.Look
    let shape: TrayPillShape
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if look.chromaticIntensity > 0 {
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: TrayGlassStyle.chromaticColors(look.chromaticPalette, for: colorScheme),
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
    /// Which state's light shadow to draw (`SidebarHostRoot` injects the
    /// sidebar's mode; the target mode as soon as a transition starts, so a
    /// morph switches once rather than flickering).
    @Environment(\.sidebarMode) private var sidebarMode
    var forceOpaque = false
    var interactive = false
    /// The capsule's end of the bar (`SidebarTrayGroup.side`), for the hover
    /// bar's nested corner. Nil: four equal corners.
    var side: HorizontalEdge? = nil

    private var shape: TrayPillShape { TrayGlassStyle.pillShape(for: sidebarMode, side: side) }

    func body(content: Content) -> some View {
        let look = SidebarDialTuning.trayGlass(for: colorScheme, state: .init(sidebarMode))
        if #available(macOS 26.0, *), !reduceTransparency, !forceOpaque {
            GlassEffectContainer {
                content
                    .background {
                        ZStack {
                            backdrop(look)
                            surface(look)
                            specular(look)
                        }
                    }
                    .overlay(shape.strokeBorder(TrayGlassStyle.rimColor(look, for: colorScheme), lineWidth: look.rimWidth))
                    .overlay { chromaticRim(look) }
            }
            .glassEffect(glass(look), in: shape)
            // A glass view casts no SwiftUI `.shadow`, so the glass path
            // draws its shadow as its own layer, outside the pill only.
            .background { TrayPillShadow(shape: shape, look: look) }
        } else {
            // Pre-26 the material still blurs; under Reduce Transparency
            // (and `forceOpaque`) the system would flatten it to an opaque
            // grey, so it is left out and the surface alone draws.
            let translucent = !reduceTransparency && !forceOpaque
            content
                .background {
                    ZStack {
                        if translucent { backdrop(look) }
                        surface(look)
                    }
                }
                .overlay {
                    if colorScheme == .dark {
                        shape.strokeBorder(TrayGlassStyle.opaqueDarkEdgeColor, lineWidth: TrayGlassStyle.opaqueDarkEdgeWidth)
                    }
                }
                .shadow(
                    color: Color.black.opacity(look.shadowOpacity),
                    radius: look.shadowRadius,
                    y: look.shadowYOffset
                )
        }
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

    /// The backdrop material (`Look.backdropMaterial`). Not in the tree at
    /// `none` or opacity 0.
    @ViewBuilder
    private func backdrop(_ look: TrayGlassStyle.Look) -> some View {
        if let material = look.backdropMaterial.material, look.backdropOpacity > 0 {
            shape
                .fill(material)
                .opacity(look.backdropOpacity)
                .allowsHitTesting(false)
        }
    }

    /// The white (light) or canvas-grey (dark) layer. With `surfaceBlur`,
    /// blurred and clipped back to the pill; at 0 the plain fill it has
    /// always been.
    @ViewBuilder
    private func surface(_ look: TrayGlassStyle.Look) -> some View {
        let fill = shape.fill(TrayGlassStyle.surfaceFill(look, for: colorScheme))
        if look.surfaceBlur > 0 {
            fill
                .blur(radius: look.surfaceBlur)
                .clipShape(shape)
        } else {
            fill
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

/// The tray glass's drop shadow (`TrayGlassStyle.Look`'s shadow dials):
/// a solid copy of the pill casts it and is then masked away, so only the
/// shadow outside the pill is drawn and the glass samples the chrome as
/// before.
private struct TrayPillShadow: View {
    let shape: TrayPillShape
    let look: TrayGlassStyle.Look

    var body: some View {
        let reach = 2 * look.shadowRadius + abs(look.shadowYOffset)
        shape
            .fill(Color.black)
            .shadow(color: Color.black.opacity(look.shadowOpacity), radius: look.shadowRadius, y: look.shadowYOffset)
            .mask {
                ZStack {
                    Rectangle().padding(-reach)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    /// Space between the capsule's buttons.
    var itemSpacing: CGFloat = TrayGlassStyle.horizontalItemGap
    /// The capsule holds one button, which takes the capsule's padding
    /// itself (`TrayIconButton.fillsCapsule`) so its hit area is the whole
    /// capsule. Same capsule size either way.
    var soleButton = false
    /// The capsule's top and bottom padding when it differs from the rule
    /// above: the rail's stacked Create pill, whose outer buttons carry it
    /// themselves (`RailTrayGeometry.stackedPadding`), so it is 0 here.
    var verticalPadding: CGFloat? = nil
    /// See `TrayGlassSurface.side`.
    var side: HorizontalEdge? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: itemSpacing))
            : AnyLayout(HStackLayout(spacing: itemSpacing))
        // Option D: padding along the capsule's axis only; across it the
        // buttons fill the capsule.
        let along = soleButton ? 0 : SidebarDialTuning.trayInnerPadding()
        let framed = layout(content)
            .redlineFrame(redlineID.map { $0 + ".content" })
            .padding(.horizontal, axis == .horizontal ? along : 0)
            .padding(.vertical, verticalPadding ?? (axis == .vertical ? along : 0))
            .redlineFrame(redlineID)
        framed.modifier(TrayGlassSurface(forceOpaque: forceOpaque, interactive: SidebarDialTuning.trayGlassInteractive(), side: side))
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
    /// See `EnvironmentValues.sidebarRailWidth`.
    @Environment(\.sidebarRailWidth) private var railWidth

    let isVertical: Bool
    /// "Collapse Sidebar" / "Expand Sidebar" / "Open Sidebar" — see
    /// `WorkspaceViewContainer.sidebarTrayItems`.
    let toggleLabel: String
    var forceOpaque = false
    /// `SidebarDialTuning.epoch()`, so a live dial change re-renders the tray.
    var dialEpoch = 0
    /// The panel's width as SwiftUI animates it (`SidebarWidthModel.width`).
    /// Set, the tray is laid out in a box of exactly that width (the rail's
    /// width when vertical), from the sidebar's leading edge, so a pinned ⇄
    /// rail toggle moves it as one animated change of a number on the
    /// toggle's transaction, never reading the AppKit-driven host width
    /// mid-flight. Nil (a tray rendered on its own), it fills its proposal.
    var panelWidth: CGFloat? = nil

    /// Space the tray occupies at the bottom of the sidebar, for the content
    /// underneath to reserve. Horizontal: one capsule row + `bottomPadding`,
    /// plus the list-to-tray gap. Vertical: the stacked square pills at
    /// `railWidth` (`RailTrayGeometry.trayHeight`), the gap between them,
    /// and the bottom margin.
    static func reservedHeight(isVertical: Bool, railWidth: CGFloat = WorkspaceLayout.sidebarRailWidth) -> CGFloat {
        if isVertical {
            return RailTrayGeometry.current(railWidth: railWidth).trayHeight(groupItemCounts: groupItemCounts())
        }
        // The capsules carry no padding across the bar (`SidebarTrayPill`).
        return SidebarDialTuning.listToTrayGap() + SidebarDialTuning.trayHorizontalButtonSize()
            + bottomPadding(isVertical: false)
    }

    /// The tray's gap to the window's bottom edge: the window margin, on
    /// both axes, so it matches the terminal card's bottom inset (and, on
    /// the rail, `RailTrayGeometry.bottomMargin`).
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
        let rail = RailTrayGeometry.current(railWidth: railWidth)
        let gap = isVertical ? rail.groupGap : SidebarDialTuning.trayGroupGap()
        let groupLayout = isVertical
            ? AnyLayout(VStackLayout(alignment: .center, spacing: gap))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: gap))
        // Expanded "Tray width: fill": the Create capsule takes the bar's
        // spare width (its buttons flex; the Toggle capsule's stay square).
        let fillsCreate = !isVertical && SidebarDialTuning.trayWidth() == .fill
        // "Tray width: split" (option D): the Create capsule hugs, but its
        // slot takes the spare width, pushing Toggle to the trailing edge.
        let splits = !isVertical && SidebarDialTuning.trayWidth() == .split
        groupLayout {
            ForEach(groups, id: \.self) { group in
                let groupItems = items.filter { $0.group == group }
                let sole = groupItems.count == 1
                // The rail's stacked pill (`RailTrayGeometry`): short buttons
                // abutting, its top and bottom padding taken by the outer
                // buttons' hit areas.
                let stacked = isVertical && !sole
                SidebarTrayPill(
                    axis: axis,
                    forceOpaque: forceOpaque,
                    redlineID: RedlineID.trayPill(group.rawValue),
                    itemSpacing: isVertical ? rail.itemGap : TrayGlassStyle.horizontalItemGap,
                    soleButton: sole,
                    verticalPadding: stacked ? 0 : nil,
                    side: group.side
                ) {
                    ForEach(groupItems) { item in
                        let isFirst = item.id == groupItems.first?.id
                        let isLast = item.id == groupItems.last?.id
                        TrayIconButton(
                            itemId: item.id,
                            systemName: item.systemName,
                            label: item.label,
                            isVertical: isVertical,
                            cellSize: isVertical ? rail.buttonSize : SidebarDialTuning.trayHorizontalButtonSize(),
                            cellHeight: stacked ? rail.stackedButtonHeight : nil,
                            hitInsets: stacked
                                ? EdgeInsets(top: isFirst ? rail.stackedPadding : 0, leading: 0,
                                             bottom: isLast ? rail.stackedPadding : 0, trailing: 0)
                                : EdgeInsets(),
                            fillsWidth: fillsCreate && group == .create,
                            fillsCapsule: sole,
                            side: group.side,
                            tapEffect: item.tapEffect,
                            action: item.action
                        )
                    }
                }
                .frame(maxWidth: splits && group == .create ? .infinity : nil, alignment: .leading)
            }
        }
        // One glass container for both capsules, so neither samples the other.
        .modifier(TrayGlassGroupContainer(forceOpaque: forceOpaque))
        .redlineFrame(RedlineID.trayGroup)
        // Expanded: the window margin is the visible gap on each side; on
        // the trailing side the gutter outside the column already provides
        // part of it. Rail: the square pills sit the window margin from the
        // window edge and from the card (`RailTrayGeometry`), centred on the
        // full rail, the same centre as its row column.
        .padding(.leading, isVertical ? rail.margin : SidebarDialTuning.windowMargin())
        .padding(.trailing, isVertical ? rail.margin : max(0, SidebarDialTuning.windowMargin() - trailingGutter))
        .padding(.bottom, Self.bottomPadding(isVertical: isVertical))
        // Leading in the expanded sidebar (layout B); centred on the rail.
        // With `panelWidth`, both are a box of a concrete width (the panel's,
        // or the rail's) from the leading edge, so the toggle animates one
        // width and one position, and the rail stack lands on the rail's
        // centre instead of sliding with the narrowing host.
        .frame(width: panelWidth.map { isVertical ? railWidth : $0 }, alignment: isVertical ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: panelWidth == nil && isVertical ? .center : .leading)
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
    /// Picks the icon size dial: the rail's (true) or the expanded bar's (false).
    var isVertical = false
    /// The square button's side: the expanded bar's dial, or the rail's
    /// `RailTrayGeometry.buttonSize`.
    let cellSize: CGFloat
    /// The cell's height when it isn't square: the rail's stacked Create
    /// buttons (`RailTrayGeometry.stackedButtonHeight`). Nil is `cellSize`.
    var cellHeight: CGFloat? = nil
    /// Hit area beyond the cell, on the pill's padding: the rail's
    /// stacked pill gives its outer buttons the padding above and below
    /// them, so the whole pill takes clicks.
    var hitInsets = EdgeInsets()
    /// Takes an equal share of its capsule's spare width instead of staying
    /// square (the expanded Create capsule under "Tray width: fill"). Height
    /// is fixed either way, and the hover chip is the cell inset
    /// (`TrayGlassStyle.hoverChip`), so it keeps its inset.
    var fillsWidth = false
    /// The only button in its capsule (`SidebarTrayPill.soleButton`): it is
    /// the capsule (option D: no padding), so its hit area is the capsule's
    /// own shape (`TrayGlassStyle.buttonHitShape`).
    var fillsCapsule = false
    /// The capsule's end of the bar (`SidebarTrayGroup.side`): a sole
    /// button's hit area and full-bleed hover chip are the capsule's own
    /// shape, nested corner included.
    var side: HorizontalEdge? = nil
    /// Symbol animation to play on click — see `TrayIconTapEffect`.
    var tapEffect: TrayIconTapEffect? = nil
    /// Draws the hover chip without a pointer. Test seam: a render test
    /// can't hover.
    var forceHover = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var tapEffectTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarMode) private var sidebarMode

    var body: some View {
        let size = cellSize
        let height = cellHeight ?? size
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
                // The lift rides the hover spring in and settles out
                // (`SidebarUISpring.hover`); at 1.06 its overshoot is
                // sub-pixel, so it reads as a quick ease, not a bounce.
                .animation(SidebarUISpring.hover.animation(entering: showsHover, reduceMotion: reduceMotion), value: showsHover)
                // One flexible frame for both widths, so flipping
                // `fillsWidth` (the pinned⇄rail morph) animates the cell's
                // width instead of swapping modifiers. min = ideal = max =
                // `size` is the square cell.
                .frame(
                    minWidth: size,
                    idealWidth: size,
                    maxWidth: fillsWidth ? .infinity : size,
                    minHeight: height,
                    maxHeight: height
                )
                .redlineFrame(itemId.map(RedlineID.trayCell))
                .background {
                    GeometryReader { proxy in
                        let chip = TrayGlassStyle.hoverChip(
                            cell: CGRect(origin: .zero, size: proxy.size),
                            soleInCapsule: fillsCapsule,
                            pillCornerRadius: TrayGlassStyle.pillCornerRadius(for: sidebarMode)
                        )
                        // Placed by `.position` (layout), not `.offset` (a
                        // draw-time shift), so the published redline frame
                        // is where the chip is drawn.
                        chipShape(chip)
                            .fill(showsHover ? Color.primary.opacity(0.10) : .clear)
                            // A tint: fades on the hover spring, never
                            // overshooting.
                            .animation(SidebarUISpring.hover.settle(reduceMotion: reduceMotion), value: showsHover)
                            .frame(width: chip.frame.width, height: chip.frame.height)
                            .redlineFrame(itemId.map { RedlineID.trayCell($0) + ".chip" })
                            .position(x: chip.frame.midX, y: chip.frame.midY)
                    }
                }
                // Hover and click land anywhere in the cell, not just on the
                // chip or the glyph, and on `hitInsets` around it.
                .modifier(TrayButtonHitArea(shape: hitShape, insets: hitInsets))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }

    private var hitShape: AnyShape {
        TrayGlassStyle.buttonHitShape(soleInCapsule: fillsCapsule, mode: sidebarMode, side: side)
    }

    /// A full-bleed chip is the capsule (`TrayGlassStyle.hoverChip`), so it
    /// takes the capsule's shape, the hover bar's nested corner included.
    private func chipShape(_ chip: TrayGlassStyle.HoverChip) -> AnyShape {
        fillsCapsule
            ? AnyShape(TrayGlassStyle.pillShape(for: sidebarMode, side: side))
            : AnyShape(RoundedRectangle(cornerRadius: chip.cornerRadius, style: .continuous))
    }

    private var showsHover: Bool {
        #if DEBUG
        forceHover || isHovered || (itemId != nil && itemId == CaptureFixture.trayHoverItemId)
        #else
        forceHover || isHovered
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

/// A tray button's hit area: its hit shape, or with `insets`, that
/// frame grown by them (`TrayIconButton.hitInsets`).
private struct TrayButtonHitArea: ViewModifier {
    let shape: AnyShape
    let insets: EdgeInsets

    /// One branch-free chain, so the button keeps its identity across the
    /// pinned⇄rail morph; with no insets the padding is zero and the hit
    /// area is the hit shape.
    func body(content: Content) -> some View {
        content
            .padding(insets)
            .contentShape(insets == EdgeInsets() ? shape : AnyShape(Rectangle()))
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
