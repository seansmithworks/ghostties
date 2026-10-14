import SwiftUI
import AppKit
#if DEBUG
import Combine
import DialkitmacOS
import DialkitmacOSAgent
#endif

// MARK: - Sidebar DialKit tunables (session-8 brief, sidebar-presence)
//
// Mirrors `ComposerSingleLineTuning`'s pattern in `ComposerSingleLineStyle.swift`
// exactly: one `enum` of `UserDefaults`-backed accessors, compiled in every
// configuration (not `#if DEBUG`). Each accessor falls back to the shipped
// `WorkspaceLayout`/`TrayGlassStyle` constant when its key is unset — a
// Release build (or a Dev build nobody has ever opened the panel in) reads
// exactly that constant, byte-for-byte. The dial panel (below, hosted by the
// floating DialkitmacOS inspector) IS `#if DEBUG`-gated; these accessors are not DialKit — they're the same
// "read a UserDefaults double, else the code default" shape every other
// dial in this app already uses, so a Release binary staying dial-free is
// really "nobody ever wrote these keys," not a compiled-out code path.
enum SidebarDialTuning {
    /// The defaults domain every dial is read from and written to: the
    /// scoped store when one is bound, else the shared one. Every reader's
    /// default argument and every dial `@AppStorage` goes through it.
    static var store: UserDefaults { scopedStore ?? sharedStore }

    /// Production never touches it (`.standard`). The test bundle swaps in a
    /// throwaway suite private to its process at load (`GhosttiesTestIsolation`)
    /// so a hosted test never reads the dial values tuned in the live Dev
    /// app's domain. A capture-fixture launch (DEBUG) reads the fixture's
    /// throwaway suite for the same reason: a capture shows the code
    /// defaults, never the Dev app's tuning, and never writes to it.
    nonisolated(unsafe) static var sharedStore: UserDefaults = {
        #if DEBUG
        if CaptureFixture.isActive { return CaptureFixture.defaults(fixtureActive: true) }
        #endif
        return .standard
    }()

    /// A store bound for one scope only (`$scopedStore.withValue(suite) { … }`):
    /// a test that needs its own dial values binds a private suite around
    /// the render instead of writing a store other tests read concurrently.
    /// Nil in production.
    @TaskLocal static var scopedStore: UserDefaults?

    // MARK: Window
    /// Every outer gutter in the window: the terminal (and browser) card's
    /// inset on all four sides, the gap between the sidebar and the card,
    /// and the sidebar's own outer edge (list column leading, tray leading/
    /// trailing visible margin, tray bottom), in every sidebar mode.
    static let windowMarginKey = "ghostties.sidebarDial.windowMargin"
    /// DEBUG-only Redlines overlay (`SidebarRedlines.swift`): spacing bands
    /// measured from real frames. Read in every configuration but only a
    /// DEBUG build draws anything.
    static let redlinesKey = "ghostties.sidebarDial.redlines"

    /// Posted by the dial panel after every write or reset, so AppKit-side
    /// geometry (the card's inset constraints) can re-read its dials live.
    /// SwiftUI views re-render through `epochKey` instead.
    static let didChangeNotification = Notification.Name("ghostties.sidebarDial.didChange")

    // MARK: Tray glass (both axes + the selected session row; `TrayGlassStyle`)
    static let trayInnerPaddingKey = "ghostties.sidebarDial.trayInnerPadding"
    static let trayGroupGapKey = "ghostties.sidebarDial.trayGroupGap"
    static let trayWidthKey = "ghostties.sidebarDial.trayWidth"
    static let trayGlassInteractiveKey = "ghostties.sidebarDial.trayGlass.interactive"
    static let trayVerticalIconSizeKey = "ghostties.sidebarDial.trayGlass.verticalIconSize"
    static let trayHorizontalButtonSizeKey = "ghostties.sidebarDial.trayGlass.horizontalButtonSize"
    static let trayHorizontalIconSizeKey = "ghostties.sidebarDial.trayGlass.horizontalIconSize"
    static let trayGlassCornerStyleKey = "ghostties.sidebarDial.trayGlass.cornerStyle"
    static let selectedTitleWeightKey = "ghostties.sidebarDial.selectedTitleWeight"

    // MARK: Glass colour and material, one key set per appearance (`TrayGlassStyle.Look`)

    /// The storage keys for one appearance's `TrayGlassStyle.Look`.
    struct GlassKeys {
        let variant: String
        let tintOpacity: String
        let surfaceOpacity: String
        let rimWidth: String
        let rimOpacity: String
        let shadowOpacity: String
        let shadowRadius: String
        let shadowYOffset: String
        let chromaticIntensity: String
        let chromaticWidth: String
        let chromaticRotation: String
        let chromaticBlur: String
        let chromaticPalette: String
        let chromaticBlend: String
        let specularStrength: String
        let specularAngle: String
        let backdropMaterial: String
        let backdropOpacity: String
        let surfaceBlur: String

        var all: [String] {
            [variant, tintOpacity, surfaceOpacity, rimWidth, rimOpacity,
             shadowOpacity, shadowRadius, shadowYOffset,
             chromaticIntensity, chromaticWidth, chromaticRotation, chromaticBlur,
             chromaticPalette, chromaticBlend, specularStrength, specularAngle,
             backdropMaterial, backdropOpacity, surfaceBlur]
        }
    }

    /// Light reuses the keys these dials had before the light/dark split,
    /// when one set drove both appearances (plus the two that were already
    /// light-only). Saved tuning therefore carries straight into the light
    /// set with no migration step to run or get wrong.
    static let lightGlassKeys = GlassKeys(
        variant: "ghostties.sidebarDial.trayGlass.variant",
        tintOpacity: "ghostties.sidebarDial.trayGlass.tintOpacityLight",
        surfaceOpacity: "ghostties.sidebarDial.trayGlass.surfaceOpacity",
        rimWidth: "ghostties.sidebarDial.trayGlass.rimWidth",
        rimOpacity: "ghostties.sidebarDial.trayGlass.rimOpacityLight",
        shadowOpacity: "ghostties.sidebarDial.trayGlass.shadowOpacity",
        shadowRadius: "ghostties.sidebarDial.trayGlass.shadowRadius",
        shadowYOffset: "ghostties.sidebarDial.trayGlass.shadowYOffset",
        chromaticIntensity: "ghostties.sidebarDial.trayGlass.chromaticIntensity",
        chromaticWidth: "ghostties.sidebarDial.trayGlass.chromaticWidth",
        chromaticRotation: "ghostties.sidebarDial.trayGlass.chromaticRotation",
        chromaticBlur: "ghostties.sidebarDial.trayGlass.chromaticBlur",
        chromaticPalette: "ghostties.sidebarDial.trayGlass.chromaticPalette",
        chromaticBlend: "ghostties.sidebarDial.trayGlass.chromaticBlend",
        specularStrength: "ghostties.sidebarDial.trayGlass.specularStrength",
        specularAngle: "ghostties.sidebarDial.trayGlass.specularAngle",
        backdropMaterial: "ghostties.sidebarDial.trayGlass.backdropMaterial",
        backdropOpacity: "ghostties.sidebarDial.trayGlass.backdropOpacity",
        surfaceBlur: "ghostties.sidebarDial.trayGlass.surfaceBlur"
    )

    /// Dark keeps its two pre-split dark-only keys (warm tint, rim opacity);
    /// everything else is new, so it starts at `TrayGlassStyle.dark`.
    static let darkGlassKeys = GlassKeys(
        variant: "ghostties.sidebarDial.trayGlass.dark.variant",
        tintOpacity: "ghostties.sidebarDial.trayTintOpacity",
        surfaceOpacity: "ghostties.sidebarDial.trayGlass.dark.surfaceOpacity",
        rimWidth: "ghostties.sidebarDial.trayGlass.dark.rimWidth",
        rimOpacity: "ghostties.sidebarDial.trayRimOpacityDark",
        shadowOpacity: "ghostties.sidebarDial.trayGlass.dark.shadowOpacity",
        shadowRadius: "ghostties.sidebarDial.trayGlass.dark.shadowRadius",
        shadowYOffset: "ghostties.sidebarDial.trayGlass.dark.shadowYOffset",
        chromaticIntensity: "ghostties.sidebarDial.trayGlass.dark.chromaticIntensity",
        chromaticWidth: "ghostties.sidebarDial.trayGlass.dark.chromaticWidth",
        chromaticRotation: "ghostties.sidebarDial.trayGlass.dark.chromaticRotation",
        chromaticBlur: "ghostties.sidebarDial.trayGlass.dark.chromaticBlur",
        chromaticPalette: "ghostties.sidebarDial.trayGlass.dark.chromaticPalette",
        chromaticBlend: "ghostties.sidebarDial.trayGlass.dark.chromaticBlend",
        specularStrength: "ghostties.sidebarDial.trayGlass.dark.specularStrength",
        specularAngle: "ghostties.sidebarDial.trayGlass.dark.specularAngle",
        backdropMaterial: "ghostties.sidebarDial.trayGlass.dark.backdropMaterial",
        backdropOpacity: "ghostties.sidebarDial.trayGlass.dark.backdropOpacity",
        surfaceBlur: "ghostties.sidebarDial.trayGlass.dark.surfaceBlur"
    )

    static func glassKeys(for colorScheme: ColorScheme) -> GlassKeys {
        colorScheme == .dark ? darkGlassKeys : lightGlassKeys
    }

    // MARK: Rows (expanded)
    static let rowHeightKey = "ghostties.sidebarDial.rowHeight"
    static let rowGapKey = "ghostties.sidebarDial.rowGap"
    static let rowTitleSizeKey = "ghostties.sidebarDial.rowTitleSize"
    static let rowSubtitleSizeKey = "ghostties.sidebarDial.rowSubtitleSize"
    static let rowGhostSizeKey = "ghostties.sidebarDial.rowGhostSize"
    static let rowLeadingPaddingKey = "ghostties.sidebarDial.rowLeadingPadding"
    static let rowTrailingPaddingKey = "ghostties.sidebarDial.rowTrailingPadding"
    /// The selected project's group card (option D): its margin, inset from
    /// the tile and chips on all four sides (`ProjectGroupCard`).
    static let groupCardInsetKey = "ghostties.sidebarDial.groupCardInset"
    // MARK: Tiles, per context (`SidebarTileContext`; "Tiles" in the Sidebar
    // panel, "Rail tiles" in the Rail panel). A project tile is the monogram
    // tile heading a group; a thread tile is a grouped session row's chip,
    // with its status glyph inside.
    /// The expanded group header's tile, and the row glyph slot under it.
    static let sidebarProjectTileSizeKey = "ghostties.sidebarDial.sidebarTile.size"
    /// The expanded tile's monogram font size (one letter; two letters draw 2pt smaller).
    static let sidebarProjectTileTextKey = "ghostties.sidebarDial.sidebarTile.text"
    /// A grouped expanded row's chip side.
    static let sidebarThreadTileSizeKey = "ghostties.sidebarDial.sidebarTile.threadSize"
    /// A grouped expanded row's status glyph size.
    static let sidebarThreadTileIconKey = "ghostties.sidebarDial.sidebarTile.threadIcon"

    // MARK: Sidebar layout
    static let contentPaddingTopKey = "ghostties.sidebarDial.contentPaddingTop"
    static let contentPaddingLeadingKey = "ghostties.sidebarDial.contentPaddingLeading"
    static let contentPaddingTrailingKey = "ghostties.sidebarDial.contentPaddingTrailing"
    static let listToTrayGapKey = "ghostties.sidebarDial.listToTrayGap"
    static let historyInSidebarKey = "ghostties.sidebarDial.historyInSidebar"
    static let projectsLayoutKey = "ghostties.sidebarDial.projectsLayout"

    // MARK: Hover reveal (`RailHoverReveal`): on the rail, resting the
    // pointer reveals the full sidebar over the terminal.
    static let hoverRevealEnabledKey = "ghostties.sidebarDial.hoverReveal.enabled"
    static let hoverRevealDwellKey = "ghostties.sidebarDial.hoverReveal.dwell"
    static let hoverRevealExitGraceKey = "ghostties.sidebarDial.hoverReveal.exitGrace"
    static let hoverRevealStyleKey = "ghostties.sidebarDial.hoverReveal.style"

    // MARK: UI springs: the sidebar's small motion (`SidebarUISpring`).
    // Bounce 0 is critically damped: no overshoot.
    static let uiSpringResponseKey = "ghostties.sidebarDial.uiSpring.response"
    static let uiSpringBounceKey = "ghostties.sidebarDial.uiSpring.bounce"
    static let uiSpringHoverResponseKey = "ghostties.sidebarDial.uiSpring.hoverResponse"

    // MARK: Motion: the sidebar ⇄ rail morph's springs
    // (`WorkspaceLayout.sidebarMorphSpring`). Bounce 0 is critically damped:
    // no overshoot.
    static let motionOpenResponseKey = "ghostties.sidebarDial.motion.openResponse"
    static let motionOpenBounceKey = "ghostties.sidebarDial.motion.openBounce"
    static let motionCollapseResponseKey = "ghostties.sidebarDial.motion.collapseResponse"
    static let motionCollapseBounceKey = "ghostties.sidebarDial.motion.collapseBounce"

    // MARK: Tray shadow per sidebar state (light appearance)
    // The tray pills' shadow in light, tuned per state: the pinned sidebar,
    // the rail, and the hover bar (the overlay revealed from closed).
    // Dark keeps the one shared shadow (`darkGlassKeys`).
    enum TrayShadowState: String, CaseIterable {
        case sidebar, rail, hoverBar

        /// The state whose shadow a mode's tray draws. Closed has no tray
        /// on screen; it takes the sidebar's.
        init(_ mode: SidebarMode) {
            switch mode {
            case .pinned, .closed: self = .sidebar
            case .collapsed: self = .rail
            case .overlay: self = .hoverBar
            }
        }
    }

    struct TrayShadowKeys {
        let opacity: String
        let radius: String
        let yOffset: String
        var all: [String] { [opacity, radius, yOffset] }
    }

    static func trayShadowKeys(_ state: TrayShadowState) -> TrayShadowKeys {
        let prefix = "ghostties.sidebarDial.trayShadow.\(state.rawValue)"
        return TrayShadowKeys(opacity: "\(prefix).opacity", radius: "\(prefix).radius", yOffset: "\(prefix).yOffset")
    }

    static let trayShadowStateKeys: [String] = TrayShadowState.allCases.flatMap { trayShadowKeys($0).all }

    // MARK: Retired (sidebar vnext lock, 2026-10-08)
    // Dials whose losing options were removed. Nothing reads them, so a
    // value stored under one changes nothing: the survivor (Tint + shimmer,
    // the glass tray, History at the bottom) draws whatever it holds.
    // "Reset sidebar" still clears them.
    static let retiredSelectedRowStyleKey = "ghostties.sidebarDial.selectedRowStyle"
    static let retiredLegacySelectedStyleKey = "ghostties.sidebarDial.trayGlass.selectedStyle"
    static let retiredTrayStyleKey = "ghostties.sidebarDial.trayStyle"
    static let retiredHistoryPlacementKey = "ghostties.sidebarDial.historyPlacement"
    /// The rail hairline's width: the section dividers were removed (beta.26).
    static let retiredHairlineWidthKey = "ghostties.sidebarDial.trayGlass.selectedPillWidth"
    /// The rail tray's button size: the rail's square pills take it from
    /// the rail's width (`RailTrayGeometry`) since 2026-10-08.
    static let retiredTrayVerticalButtonSizeKey = "ghostties.sidebarDial.trayGlass.verticalButtonSize"
    /// The tray pills' corner radius: concentric with the window corner
    /// (`trayCornerRadius`) since 2026-10-08.
    static let retiredTrayCornerRadiusKey = "ghostties.sidebarDial.trayGlass.cornerRadius"
    /// The chip's size as an offset from the tile: an absolute "Thread tile
    /// size" per context replaced it (2026-10-10).
    static let retiredRailChipSizeOffsetKey = "ghostties.sidebarDial.railColumn.chipSizeOffset"
    /// The rail's selected row card's dark rim ("Shimmer (dark)"): every
    /// rail row selects with the flat chip since 2026-10-10.
    static let retiredTintShimmerDarkIntensityKey = "ghostties.sidebarDial.tintShimmerDarkIntensity"
    static let retiredKeys: [String] = [
        retiredSelectedRowStyleKey, retiredLegacySelectedStyleKey, retiredTrayStyleKey, retiredHistoryPlacementKey,
        retiredHairlineWidthKey, retiredTrayVerticalButtonSizeKey, retiredTrayCornerRadiusKey, retiredRailChipSizeOffsetKey,
        retiredTintShimmerDarkIntensityKey,
        // The flat selected row's shadow, per appearance.
        "ghostties.sidebarDial.trayGlass.selectedShadowOpacity",
        "ghostties.sidebarDial.trayGlass.selectedShadowRadius",
        "ghostties.sidebarDial.trayGlass.selectedShadowYOffset",
        "ghostties.sidebarDial.trayGlass.dark.selectedShadowOpacity",
        "ghostties.sidebarDial.trayGlass.dark.selectedShadowRadius",
        "ghostties.sidebarDial.trayGlass.dark.selectedShadowYOffset"
    ]

    // MARK: Rail
    static let railExtraWidthKey = "ghostties.sidebarDial.railExtraWidth"
    /// Between the two icons of the rail's stacked Create pill
    /// (`RailTrayGeometry.iconGap`).
    static let railTrayIconGapKey = "ghostties.sidebarDial.trayGlass.railIconGap"
    /// The rail tray's square pill side (`RailTrayGeometry.cell`), capped
    /// at the rail's width less its margins.
    static let railTrayPillSizeKey = "ghostties.sidebarDial.trayGlass.railPillSize"
    /// The tray buttons' hover chip inset from its button cell on every
    /// side (`TrayGlassStyle.hoverChip`), both trays.
    static let trayHoverInsetKey = "ghostties.sidebarDial.trayGlass.hoverInset"

    // MARK: Rail column (one view's selected project, `RailProjectColumn`)
    static let railColumnTintOpacityKey = "ghostties.sidebarDial.railColumn.tintOpacity"
    static let railColumnInsetKey = "ghostties.sidebarDial.railColumn.inset"
    static let railChipCornerRadiusKey = "ghostties.sidebarDial.railColumn.chipCornerRadius"
    /// The rail's project tile, and the column width and trims derived from it.
    static let railProjectTileSizeKey = "ghostties.sidebarDial.railColumn.tileSize"
    /// The rail tile's monogram font size (one letter; two letters draw 2pt smaller).
    static let railProjectTileTextKey = "ghostties.sidebarDial.railColumn.tileText"
    /// A grouped rail row's chip side (replaced the chip-size offset).
    static let railThreadTileSizeKey = "ghostties.sidebarDial.railColumn.threadTileSize"
    /// A grouped rail row's status glyph size.
    static let railThreadTileIconKey = "ghostties.sidebarDial.railColumn.threadTileIcon"
    static let railSelectedTileFillKey = "ghostties.sidebarDial.railColumn.selectedTileFill"

    /// Bumped every time the panel writes any key (`SidebarDialKitCoordinator
    /// .write`) — read by `RecentsRowView`'s `Equatable` conformance so a live
    /// dial change actually invalidates rows whose OWN stored properties
    /// (session/projectName/indicatorState/etc.) didn't change. Without this,
    /// `.equatable()`'s body-skip (a deliberate perf gate — see
    /// `RecentsRowView`'s doc comment) would swallow a tuning change to
    /// row height/title size/ghost size/etc. until some unrelated row
    /// mutation happened to force a re-render.
    static let epochKey = "ghostties.sidebarDial.epoch"

    static func epoch(defaults: UserDefaults = SidebarDialTuning.store) -> Int {
        defaults.integer(forKey: epochKey)
    }

    private static func cgFloat(_ key: String, default value: CGFloat, defaults: UserDefaults) -> CGFloat {
        CGFloat(number(key, defaults: defaults) ?? Double(value))
    }

    private static func double(_ key: String, default value: Double, defaults: UserDefaults) -> Double {
        number(key, defaults: defaults) ?? value
    }

    /// A stored number, or a launch argument (`-<key> 16` arrives as a
    /// string in the argument domain), else nil.
    private static func number(_ key: String, defaults: UserDefaults) -> Double? {
        switch defaults.object(forKey: key) {
        case let stored as Double: return stored
        case let argument as String: return Double(argument)
        default: return nil
        }
    }

    private static func bool(_ key: String, default value: Bool, defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? value
    }

    private static func choice<T: RawRepresentable>(_ key: String, default value: T, defaults: UserDefaults) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? value
    }

    /// See `windowMarginKey`. Defaults to `WorkspaceLayout.terminalInset`.
    static func windowMargin(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(windowMarginKey, default: WorkspaceLayout.terminalInset, defaults: defaults)
    }
    /// See `redlinesKey`. Off by default. `bool(forKey:)`, not a cast, so
    /// a `-ghostties.sidebarDial.redlines YES` launch argument (a string)
    /// reads as on, the same way `@AppStorage` reads it.
    static func redlines(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        defaults.bool(forKey: redlinesKey)
    }
    static func trayInnerPadding(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayInnerPaddingKey, default: TrayGlassStyle.innerPadding, defaults: defaults)
    }
    /// Gap between the expanded tray's Create and Toggle capsules. The
    /// rail's is the window margin (`RailTrayGeometry.groupGap`).
    static func trayGroupGap(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayGroupGapKey, default: TrayGlassStyle.groupGap, defaults: defaults)
    }
    /// Expanded tray only: whether the Create capsule fills the bar's width
    /// or hugs its buttons (`TrayGlassStyle.TrayWidth`).
    static func trayWidth(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.TrayWidth {
        choice(trayWidthKey, default: TrayGlassStyle.trayWidth, defaults: defaults)
    }
    /// The glass's colour/material set for one appearance: each value its
    /// own saved dial, else `TrayGlassStyle.light`/`.dark`.
    static func trayGlass(for colorScheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.Look {
        let keys = glassKeys(for: colorScheme)
        let base = TrayGlassStyle.defaultLook(for: colorScheme)
        return TrayGlassStyle.Look(
            variant: choice(keys.variant, default: base.variant, defaults: defaults),
            tintOpacity: double(keys.tintOpacity, default: base.tintOpacity, defaults: defaults),
            surfaceOpacity: double(keys.surfaceOpacity, default: base.surfaceOpacity, defaults: defaults),
            rimWidth: cgFloat(keys.rimWidth, default: base.rimWidth, defaults: defaults),
            rimOpacity: double(keys.rimOpacity, default: base.rimOpacity, defaults: defaults),
            shadowOpacity: double(keys.shadowOpacity, default: base.shadowOpacity, defaults: defaults),
            shadowRadius: cgFloat(keys.shadowRadius, default: base.shadowRadius, defaults: defaults),
            shadowYOffset: cgFloat(keys.shadowYOffset, default: base.shadowYOffset, defaults: defaults),
            chromaticIntensity: double(keys.chromaticIntensity, default: base.chromaticIntensity, defaults: defaults),
            chromaticWidth: cgFloat(keys.chromaticWidth, default: base.chromaticWidth, defaults: defaults),
            chromaticRotation: double(keys.chromaticRotation, default: base.chromaticRotation, defaults: defaults),
            chromaticBlur: cgFloat(keys.chromaticBlur, default: base.chromaticBlur, defaults: defaults),
            chromaticPalette: choice(keys.chromaticPalette, default: base.chromaticPalette, defaults: defaults),
            chromaticBlend: choice(keys.chromaticBlend, default: base.chromaticBlend, defaults: defaults),
            specularStrength: double(keys.specularStrength, default: base.specularStrength, defaults: defaults),
            specularAngle: double(keys.specularAngle, default: base.specularAngle, defaults: defaults),
            backdropMaterial: choice(keys.backdropMaterial, default: base.backdropMaterial, defaults: defaults),
            backdropOpacity: double(keys.backdropOpacity, default: base.backdropOpacity, defaults: defaults),
            surfaceBlur: cgFloat(keys.surfaceBlur, default: base.surfaceBlur, defaults: defaults)
        )
    }
    /// The glass for a tray in `state`: `trayGlass(for:)`, with light's
    /// shadow taken from that state's own dials (default: light's baked
    /// shadow). Dark's shadow is shared across states.
    static func trayGlass(for colorScheme: ColorScheme, state: TrayShadowState, defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.Look {
        var look = trayGlass(for: colorScheme, defaults: defaults)
        guard colorScheme == .light else { return look }
        let keys = trayShadowKeys(state)
        let base = TrayGlassStyle.light
        look.shadowOpacity = double(keys.opacity, default: base.shadowOpacity, defaults: defaults)
        look.shadowRadius = cgFloat(keys.radius, default: base.shadowRadius, defaults: defaults)
        look.shadowYOffset = cgFloat(keys.yOffset, default: base.shadowYOffset, defaults: defaults)
        return look
    }
    /// The selected expanded row's title weight (`TrayGlassStyle.SelectedTitleWeight`).
    static func selectedTitleWeight(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.SelectedTitleWeight {
        choice(selectedTitleWeightKey, default: TrayGlassStyle.selectedTitleWeight, defaults: defaults)
    }
    static func trayGlassInteractive(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        bool(trayGlassInteractiveKey, default: TrayGlassStyle.interactive, defaults: defaults)
    }
    static func trayVerticalIconSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayVerticalIconSizeKey, default: TrayGlassStyle.verticalIconSize, defaults: defaults)
    }
    static func trayHorizontalButtonSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayHorizontalButtonSizeKey, default: TrayGlassStyle.horizontalButtonSize, defaults: defaults)
    }
    static func trayHorizontalIconSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayHorizontalIconSizeKey, default: TrayGlassStyle.horizontalIconSize, defaults: defaults)
    }
    static func trayGlassCornerStyle(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.CornerStyle {
        choice(trayGlassCornerStyleKey, default: TrayGlassStyle.cornerStyle, defaults: defaults)
    }
    /// The tray pills' radius ("radius" corner style) in `mode`: concentric
    /// with the surface they sit in (`WorkspaceLayout.trayParentCornerRadius`),
    /// the window margin in from its edges — the tray's own leading, trailing
    /// and bottom padding in every mode.
    static func trayCornerRadius(for mode: SidebarMode = .pinned, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        let margin = windowMargin(defaults: defaults)
        return WorkspaceLayout.concentricRadius(
            parent: WorkspaceLayout.trayParentCornerRadius(for: mode, margin: margin),
            inset: margin
        )
    }

    static func rowHeight(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowHeightKey, default: WorkspaceLayout.recentsRowHeight, defaults: defaults)
    }
    static func rowGap(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowGapKey, default: WorkspaceLayout.recentsRowGap, defaults: defaults)
    }
    static func rowTitleSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowTitleSizeKey, default: WorkspaceLayout.recentsRowTitleSize, defaults: defaults)
    }
    static func rowSubtitleSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowSubtitleSizeKey, default: WorkspaceLayout.recentsRowSubtitleSize, defaults: defaults)
    }
    static func rowGhostSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowGhostSizeKey, default: WorkspaceLayout.sessionGhostSize, defaults: defaults)
    }
    static func rowLeadingPadding(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowLeadingPaddingKey, default: WorkspaceLayout.recentsRowLeadingPadding, defaults: defaults)
    }
    static func rowTrailingPadding(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(rowTrailingPaddingKey, default: WorkspaceLayout.recentsRowTrailingPadding, defaults: defaults)
    }
    /// See `groupCardInsetKey`. Defaults to `WorkspaceLayout.sidebarGroupCardInset`.
    static func groupCardInset(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        max(0, cgFloat(groupCardInsetKey, default: WorkspaceLayout.sidebarGroupCardInset, defaults: defaults))
    }
    /// See `sidebarProjectTileSizeKey`. Defaults to `RailProjectTile.defaultSize`.
    static func sidebarProjectTileSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(sidebarProjectTileSizeKey, default: RailProjectTile.defaultSize, defaults: defaults)
    }
    /// See `sidebarProjectTileTextKey`. Defaults to `RailProjectTile.defaultTextSize`.
    static func sidebarProjectTileText(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(sidebarProjectTileTextKey, default: RailProjectTile.defaultTextSize, defaults: defaults)
    }
    /// See `sidebarThreadTileSizeKey`. Defaults to `RailProjectColumn.defaultThreadTileSize`.
    static func sidebarThreadTileSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(sidebarThreadTileSizeKey, default: RailProjectColumn.defaultThreadTileSize, defaults: defaults)
    }
    /// See `sidebarThreadTileIconKey`. Defaults to `RailProjectColumn.defaultSidebarThreadTileIcon`.
    static func sidebarThreadTileIcon(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(sidebarThreadTileIconKey, default: RailProjectColumn.defaultSidebarThreadTileIcon, defaults: defaults)
    }


    static func contentPaddingTop(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(contentPaddingTopKey, default: WorkspaceLayout.sidebarContentPaddingTop, defaults: defaults)
    }
    static func contentPaddingLeading(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(contentPaddingLeadingKey, default: WorkspaceLayout.sidebarContentPaddingLeading, defaults: defaults)
    }
    static func contentPaddingTrailing(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(contentPaddingTrailingKey, default: WorkspaceLayout.sidebarContentPaddingTrailing, defaults: defaults)
    }
    /// The list column's outer trailing padding: the window margin less the
    /// gutter already outside the column (`WorkspaceLayout.sidebarTrailingGutter`),
    /// so the visible gap to the next surface is the window margin. The
    /// inner `contentPaddingTrailing` is applied on top of this.
    static func contentColumnTrailingPadding(gutter: CGFloat, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        max(0, windowMargin(defaults: defaults) - gutter)
    }
    static func listToTrayGap(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(listToTrayGapKey, default: WorkspaceLayout.sidebarListToTrayGap, defaults: defaults)
    }

    /// Whether the History row (and its rail clock) renders at all. Off by
    /// default since sidebar vnext: past sessions resume from the Cmd+T
    /// composer instead (`ComposerResumeLayout`). Pinned and Active are
    /// unaffected either way.
    static func historyInSidebar(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        switch defaults.object(forKey: historyInSidebarKey) {
        case let stored as Bool: return stored
        // A launch argument (`-ghostties.sidebarDial.historyInSidebar YES`)
        // arrives as a string.
        case let argument as String: return (argument as NSString).boolValue
        default: return false
        }
    }

    /// Projects tab + Sessions tab, or one list with each project as an
    /// accordion header (`SidebarProjectsLayout`). One view by default.
    static func projectsLayout(defaults: UserDefaults = SidebarDialTuning.store) -> SidebarProjectsLayout {
        choice(projectsLayoutKey, default: SidebarProjectsLayout.shipped, defaults: defaults)
    }

    /// `SidebarUISpring.fold` and `.move`'s response, in seconds.
    static func uiSpringResponse(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(uiSpringResponseKey, default: SidebarUISpring.defaultResponse, defaults: defaults)
    }
    /// Every `SidebarUISpring`'s overshoot on an entrance or travel; 0 is
    /// no overshoot.
    static func uiSpringBounce(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(uiSpringBounceKey, default: SidebarUISpring.defaultBounce, defaults: defaults)
    }
    /// `SidebarUISpring.hover`'s response, in seconds.
    static func uiSpringHoverResponse(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(uiSpringHoverResponseKey, default: SidebarUISpring.defaultHoverResponse, defaults: defaults)
    }

    /// See `hoverRevealEnabledKey`. On by default.
    static func hoverRevealEnabled(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        switch defaults.object(forKey: hoverRevealEnabledKey) {
        case let stored as Bool: return stored
        // A launch argument arrives as a string.
        case let argument as String: return (argument as NSString).boolValue
        default: return true
        }
    }
    /// Seconds the pointer rests on the rail before the sidebar reveals.
    static func hoverRevealDwell(defaults: UserDefaults = SidebarDialTuning.store) -> TimeInterval {
        double(hoverRevealDwellKey, default: WorkspaceLayout.railHoverRevealDwell, defaults: defaults)
    }
    /// Seconds after the pointer leaves the revealed sidebar before it
    /// morphs back to the rail.
    static func hoverRevealExitGrace(defaults: UserDefaults = SidebarDialTuning.store) -> TimeInterval {
        double(hoverRevealExitGraceKey, default: WorkspaceLayout.railHoverRevealExitGrace, defaults: defaults)
    }

    /// Rail -> sidebar spring (toggle expand, hover reveal).
    static func motionOpenResponse(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(motionOpenResponseKey, default: WorkspaceLayout.sidebarMorphOpenSpring.response, defaults: defaults)
    }
    static func motionOpenBounce(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(motionOpenBounceKey, default: WorkspaceLayout.sidebarMorphOpenSpring.bounce, defaults: defaults)
    }
    /// Sidebar -> rail spring.
    static func motionCollapseResponse(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(motionCollapseResponseKey, default: WorkspaceLayout.sidebarMorphCollapseSpring.response, defaults: defaults)
    }
    static func motionCollapseBounce(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(motionCollapseBounceKey, default: WorkspaceLayout.sidebarMorphCollapseSpring.bounce, defaults: defaults)
    }

    /// See `RailRevealStyle`. Push by default.
    static func hoverRevealStyle(defaults: UserDefaults = SidebarDialTuning.store) -> RailRevealStyle {
        choice(hoverRevealStyleKey, default: .push, defaults: defaults)
    }

    /// Added on top of `WorkspaceLayout.collapsedRailWidth`'s computed hug
    /// width — see that function's own doc comment. Not folded into
    /// `WorkspaceLayout.railExtraWidth` (the compiled default both this and
    /// that function read) because the hug-width call sites are pure/testable
    /// functions that must not read `UserDefaults` directly.
    static func railExtraWidth(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railExtraWidthKey, default: WorkspaceLayout.railExtraWidth, defaults: defaults)
    }

    /// See `railTrayIconGapKey`. Defaults to `TrayGlassStyle.railIconGap`.
    static func railTrayIconGap(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railTrayIconGapKey, default: TrayGlassStyle.railIconGap, defaults: defaults)
    }
    /// See `railTrayPillSizeKey`. Defaults to `TrayGlassStyle.railPillSize`.
    static func railTrayPillSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railTrayPillSizeKey, default: TrayGlassStyle.railPillSize, defaults: defaults)
    }
    /// See `trayHoverInsetKey`. Defaults to `TrayGlassStyle.hoverInset`.
    static func trayHoverInset(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayHoverInsetKey, default: TrayGlassStyle.hoverInset, defaults: defaults)
    }

    /// The project column's fill in dark (`RailProjectColumn.columnTintOpacity`).
    static func railColumnTintOpacity(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(railColumnTintOpacityKey, default: RailProjectColumn.defaultColumnTintOpacity, defaults: defaults)
    }
    /// The column's margin around its tile and chips (`RailProjectColumn.columnInset`).
    static func railColumnInset(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railColumnInsetKey, default: RailProjectColumn.defaultColumnInset, defaults: defaults)
    }
    /// The chip's corner (`RailProjectColumn.chipCornerRadius`).
    static func railChipCornerRadius(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railChipCornerRadiusKey, default: RailProjectColumn.defaultChipCornerRadius, defaults: defaults)
    }
    /// See `railProjectTileSizeKey`. Defaults to `RailProjectTile.defaultRailSize`.
    static func railProjectTileSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railProjectTileSizeKey, default: RailProjectTile.defaultRailSize, defaults: defaults)
    }
    /// See `railProjectTileTextKey`. Defaults to `RailProjectTile.defaultRailTextSize`.
    static func railProjectTileText(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railProjectTileTextKey, default: RailProjectTile.defaultRailTextSize, defaults: defaults)
    }
    /// See `railThreadTileSizeKey`; unclamped here, `RailProjectColumn.chipSize`
    /// clamps it. Defaults to `RailProjectColumn.defaultRailThreadTileSize`.
    static func railThreadTileSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railThreadTileSizeKey, default: RailProjectColumn.defaultRailThreadTileSize, defaults: defaults)
    }
    /// See `railThreadTileIconKey`. Defaults to `RailProjectColumn.defaultRailThreadTileIcon`.
    static func railThreadTileIcon(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railThreadTileIconKey, default: RailProjectColumn.defaultRailThreadTileIcon, defaults: defaults)
    }
    /// The selected project's tile fill, 0 (plain tile tint) to 1 (full ink).
    static func railSelectedTileFill(defaults: UserDefaults = SidebarDialTuning.store) -> Double {
        double(railSelectedTileFillKey, default: RailProjectColumn.defaultSelectedTileFill, defaults: defaults)
    }

    /// Every storage key this panel owns — used by `resetSidebar()` to clear
    /// back to code defaults in one pass, same shape as
    /// `ComposerSingleLineReset.resetKeys`.
    static let allKeys: [String] = lightGlassKeys.all + darkGlassKeys.all + [
        windowMarginKey, redlinesKey,
        trayInnerPaddingKey, trayGroupGapKey, trayWidthKey, trayGlassInteractiveKey,
        trayHorizontalButtonSizeKey,
        trayHorizontalIconSizeKey, trayGlassCornerStyleKey,
        selectedTitleWeightKey,
        rowHeightKey, rowGapKey, rowTitleSizeKey, rowSubtitleSizeKey, rowGhostSizeKey,
        rowLeadingPaddingKey, rowTrailingPaddingKey, groupCardInsetKey,
        sidebarProjectTileSizeKey, sidebarProjectTileTextKey, sidebarThreadTileSizeKey, sidebarThreadTileIconKey,
        contentPaddingTopKey, contentPaddingLeadingKey, contentPaddingTrailingKey, listToTrayGapKey,
        historyInSidebarKey, projectsLayoutKey,
        hoverRevealEnabledKey, hoverRevealDwellKey, hoverRevealExitGraceKey, hoverRevealStyleKey,
        motionOpenResponseKey, motionOpenBounceKey, motionCollapseResponseKey, motionCollapseBounceKey,
        uiSpringResponseKey, uiSpringBounceKey, uiSpringHoverResponseKey
    ] + railKeys + trayShadowStateKeys + colorKeys

    /// The "Sidebar colors" panel's keys (`SidebarColorTuning.allKeys`),
    /// DEBUG only: a Release build has no colour dials to clear.
    static var colorKeys: [String] {
        #if DEBUG
        SidebarColorTuning.allKeys
        #else
        []
        #endif
    }

    /// The keys the Rail panel owns (`RailDialPanel`): its own
    /// "Reset rail" clears only these. Part of `allKeys`, so "Reset all
    /// panels" clears them too.
    static let railKeys: [String] = [
        trayVerticalIconSizeKey, railTrayIconGapKey, railTrayPillSizeKey, trayHoverInsetKey, railExtraWidthKey,
        darkGlassKeys.shadowOpacity, darkGlassKeys.shadowRadius, darkGlassKeys.shadowYOffset,
        railColumnTintOpacityKey, railColumnInsetKey, railChipCornerRadiusKey,
        railSelectedTileFillKey,
        railProjectTileSizeKey, railProjectTileTextKey, railThreadTileSizeKey, railThreadTileIconKey
    ]

    /// The keys the "Sidebar" panel owns (`SidebarListDialPanel`): the
    /// expanded sidebar's rows, selected row, expanded tray and side
    /// margins. Part of `allKeys`.
    static let sidebarListKeys: [String] = [
        rowHeightKey, rowGapKey, selectedTitleWeightKey,
        trayHorizontalButtonSizeKey, trayGroupGapKey, trayWidthKey,
        contentPaddingLeadingKey, contentPaddingTrailingKey, groupCardInsetKey,
        sidebarProjectTileSizeKey, sidebarProjectTileTextKey, sidebarThreadTileSizeKey, sidebarThreadTileIconKey,
        hoverRevealEnabledKey, hoverRevealDwellKey, hoverRevealExitGraceKey, hoverRevealStyleKey,
        motionOpenResponseKey, motionOpenBounceKey, motionCollapseResponseKey, motionCollapseBounceKey,
        uiSpringResponseKey, uiSpringBounceKey, uiSpringHoverResponseKey
    ]

    /// Posted after either panel's Reset, so the other panel re-reads the
    /// keys it shares with it.
    static let didResetNotification = Notification.Name("ghostties.sidebarDial.didReset")

    static func reset(defaults: UserDefaults = SidebarDialTuning.store) {
        clear(allKeys + retiredKeys, defaults: defaults)
    }

    /// A focused panel's Reset: its keys only.
    static func reset(keys: [String], defaults: UserDefaults = SidebarDialTuning.store) {
        clear(keys, defaults: defaults)
    }

    private static func clear(_ keys: [String], defaults: UserDefaults) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(epoch(defaults: defaults) + 1, forKey: epochKey)
    }
}

// MARK: - Dial panel (macOS 14+, DEBUG only)
//
// The panel is no longer drawn inside the sidebar. It is exposed to the
// floating DialkitmacOS inspector (github.com/mikelikesdesign/dialkit-macos,
// a separate Mac app that talks to this one over 127.0.0.1:44777). Same
// `DialPanelState` ownership, diff-based `write(from:to:)`, and
// Reset-as-`.action` shape as `ComposerDialKitCoordinator`; the composer
// keeps its own in-app DialKit. `SidebarDialInspector.start()` (called from
// `AppDelegate`) builds the one coordinator for the process and starts the
// agent. DEBUG only: Release neither imports nor starts any of it.
//
// No macOS-13 fallback: the inspector package needs macOS 14; every dial
// still has a working `defaults write` escape hatch via `SidebarDialTuning`.
#if DEBUG
/// DEBUG-only: forces the whole app light or dark (`NSApp.appearance`:
/// windows, sidebar, chrome, and every terminal, which re-themes through
/// AppDelegate's `effectiveAppearance` observer), so each glass set can be
/// judged in context without changing the system appearance. `auto` hands
/// the app back to the config's `window-theme` (nil follows the system), as
/// a Release build always does. Held in memory only: every launch starts at
/// `auto` (a capture-fixture launch can start elsewhere via
/// `GHOSTTIES_CAPTURE_APPEARANCE`). Driven by the inspector's "Preview
/// appearance" control; `AppDelegate.syncAppearance` hands it the config's
/// appearance on every config load.
@MainActor
enum SidebarAppearancePreview {
    enum Mode: String, CaseIterable {
        case auto, light, dark
    }

    private(set) static var mode: Mode = CaptureFixture.appearancePreview.flatMap(Mode.init(rawValue:)) ?? .auto

    /// The config's `window-theme` appearance (nil follows the system), as
    /// last handed over by `AppDelegate.syncAppearance`: what `auto` restores.
    private static var configuredAppearance: NSAppearance?

    static func set(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        NSApp.appearance = appAppearance(configured: configuredAppearance)
    }

    /// Called on every config load in place of setting `NSApp.appearance`
    /// directly, so a config reload never drops a forced preview.
    static func applyAppAppearance(configured: NSAppearance?) {
        configuredAppearance = configured
        NSApp.appearance = appAppearance(configured: configured)
    }

    /// The app's appearance: the forced preview, else `configured` (the
    /// config's `window-theme`; nil follows the system).
    static func appAppearance(configured: NSAppearance?) -> NSAppearance? {
        forcedAppearance ?? configured
    }

    /// The appearance to force, or nil when not previewing.
    static var forcedAppearance: NSAppearance? {
        switch mode {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// The panel's view of one appearance's `TrayGlassStyle.Look`, in the plain
/// `String`/`Double` fields the inspector's controls bind to.
@available(macOS 14, *)
struct SidebarDialKitGlassModel: Codable, Equatable {
    var variant: String
    var tintOpacity: Double
    var surfaceOpacity: Double
    var rimWidth: Double
    var rimOpacity: Double
    var chromaticIntensity: Double
    var chromaticWidth: Double
    var chromaticRotation: Double
    var chromaticBlur: Double
    var chromaticPalette: String
    var chromaticBlend: String
    var specularStrength: Double
    var specularAngle: Double
    var backdropMaterial: String
    var backdropOpacity: Double
    var surfaceBlur: Double

    init(_ look: TrayGlassStyle.Look) {
        variant = look.variant.rawValue
        tintOpacity = look.tintOpacity
        surfaceOpacity = look.surfaceOpacity
        rimWidth = Double(look.rimWidth)
        rimOpacity = look.rimOpacity
        chromaticIntensity = look.chromaticIntensity
        chromaticWidth = Double(look.chromaticWidth)
        chromaticRotation = look.chromaticRotation
        chromaticBlur = Double(look.chromaticBlur)
        chromaticPalette = look.chromaticPalette.rawValue
        chromaticBlend = look.chromaticBlend.rawValue
        specularStrength = look.specularStrength
        specularAngle = look.specularAngle
        backdropMaterial = look.backdropMaterial.rawValue
        backdropOpacity = look.backdropOpacity
        surfaceBlur = Double(look.surfaceBlur)
    }
}

@available(macOS 14, *)
struct SidebarDialKitTuningModel: Codable, Equatable {
    /// `SidebarAppearancePreview.Mode` — never persisted.
    var previewAppearance: String
    var redlines: Bool
    var windowMargin: Double

    var glassLight: SidebarDialKitGlassModel
    var glassDark: SidebarDialKitGlassModel

    var trayGlassInteractive: Bool
    var trayHorizontalIconSize: Double
    var trayInnerPadding: Double
    var trayGlassCornerStyle: String

    var rowTitleSize: Double
    var rowSubtitleSize: Double
    var rowGhostSize: Double
    var rowLeadingPadding: Double
    var rowTrailingPadding: Double


    var contentPaddingTop: Double
    var listToTrayGap: Double
    var historyInSidebar: Bool
    var projectsLayout: String
}

/// The Sidebar panel's model: the expanded sidebar's own knobs.
@available(macOS 14, *)
struct SidebarListDialKitTuningModel: Codable, Equatable {
    var rowHeight: Double
    var rowGap: Double
    var selectedTitleWeight: String
    var trayHorizontalButtonSize: Double
    var trayGroupGap: Double
    var trayWidth: String
    var contentPaddingLeading: Double
    var contentPaddingTrailing: Double
    var groupCardInset: Double
    var sidebarProjectTileSize: Double
    var sidebarProjectTileText: Double
    var sidebarThreadTileSize: Double
    var sidebarThreadTileIcon: Double
    var hoverRevealEnabled: Bool
    var hoverRevealDwell: Double
    var hoverRevealExitGrace: Double
    var hoverRevealStyle: String
    var motionOpenResponse: Double
    var motionOpenBounce: Double
    var motionCollapseResponse: Double
    var motionCollapseBounce: Double
    var uiSpringResponse: Double
    var uiSpringBounce: Double
    var uiSpringHoverResponse: Double
}

/// The Rail panel's model: every knob that only changes the collapsed rail.
@available(macOS 14, *)
struct RailDialKitTuningModel: Codable, Equatable {
    /// Dark's tray shadow (every state): `TrayGlassStyle.Look`'s. Light's
    /// is per state, in the "Tray shadow" panel.
    struct Shadow: Codable, Equatable {
        var opacity: Double
        var radius: Double
        var yOffset: Double
    }

    var trayVerticalIconSize: Double
    var railTrayIconGap: Double
    var railTrayPillSize: Double
    var trayHoverInset: Double
    var shadowDark: Shadow
    var railExtraWidth: Double

    var railColumnTintOpacity: Double
    var railColumnInset: Double
    var railChipCornerRadius: Double
    var railSelectedTileFill: Double
    var railProjectTileSize: Double
    var railProjectTileText: Double
    var railThreadTileSize: Double
    var railThreadTileIcon: Double
}

@available(macOS 14, *)
@MainActor
final class SidebarDialKitCoordinator: ObservableObject {
    let state: DialPanelState<SidebarDialKitTuningModel>
    private var cancellable: AnyCancellable?
    private var resetObserver: AnyCancellable?
    private let defaults: UserDefaults
    private let onChange: () -> Void
    private var lastKnownModel: SidebarDialKitTuningModel

    init(defaults: UserDefaults, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        let initial = Self.readModel(defaults: defaults)
        lastKnownModel = initial
        let selfBox = SidebarDialKitCoordinatorBox()
        state = DialPanelState(
            name: "Glass & Layout",
            initial: initial,
            controls: Self.controls,
            onAction: { path in selfBox.coordinator?.handleAction(path) }
        )
        // See `ComposerDialKitCoordinator.init`'s identical comment: capture
        // the panel's own (possibly range/step-normalized) `state.values`,
        // not the pre-normalization `initial`, so the first real edit never
        // diffs against a phantom rounding drift and clobbers an untouched key.
        lastKnownModel = state.values
        cancellable = state.$values
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handle(newValue)
            }
        // The Rail panel's Reset clears keys this panel also reads.
        resetObserver = NotificationCenter.default
            .publisher(for: SidebarDialTuning.didResetNotification)
            .sink { [weak self] note in
                guard let self, (note.object as AnyObject?) !== self else { return }
                self.reloadFromDefaults()
            }
        selfBox.coordinator = self
    }

    private func reloadFromDefaults() {
        let freshModel = Self.readModel(defaults: defaults)
        lastKnownModel = freshModel
        state.values = freshModel
    }

    private func handle(_ model: SidebarDialKitTuningModel) {
        let previous = lastKnownModel
        lastKnownModel = model
        write(from: previous, to: model)
    }

    func handleAction(_ path: String) {
        guard path == Self.resetActionPath else { return }
        resetSidebar()
    }

    private func resetSidebar() {
        SidebarDialTuning.reset(defaults: defaults)
        reloadFromDefaults()
        NotificationCenter.default.post(name: SidebarDialTuning.didResetNotification, object: self)
        onChange()
    }

    private static func readModel(defaults: UserDefaults) -> SidebarDialKitTuningModel {
        SidebarDialKitTuningModel(
            previewAppearance: SidebarAppearancePreview.mode.rawValue,
            redlines: SidebarDialTuning.redlines(defaults: defaults),
            windowMargin: Double(SidebarDialTuning.windowMargin(defaults: defaults)),
            glassLight: SidebarDialKitGlassModel(SidebarDialTuning.trayGlass(for: .light, defaults: defaults)),
            glassDark: SidebarDialKitGlassModel(SidebarDialTuning.trayGlass(for: .dark, defaults: defaults)),
            trayGlassInteractive: SidebarDialTuning.trayGlassInteractive(defaults: defaults),
            trayHorizontalIconSize: Double(SidebarDialTuning.trayHorizontalIconSize(defaults: defaults)),
            trayInnerPadding: Double(SidebarDialTuning.trayInnerPadding(defaults: defaults)),
            trayGlassCornerStyle: SidebarDialTuning.trayGlassCornerStyle(defaults: defaults).rawValue,
            rowTitleSize: Double(SidebarDialTuning.rowTitleSize(defaults: defaults)),
            rowSubtitleSize: Double(SidebarDialTuning.rowSubtitleSize(defaults: defaults)),
            rowGhostSize: Double(SidebarDialTuning.rowGhostSize(defaults: defaults)),
            rowLeadingPadding: Double(SidebarDialTuning.rowLeadingPadding(defaults: defaults)),
            rowTrailingPadding: Double(SidebarDialTuning.rowTrailingPadding(defaults: defaults)),
            contentPaddingTop: Double(SidebarDialTuning.contentPaddingTop(defaults: defaults)),
            listToTrayGap: Double(SidebarDialTuning.listToTrayGap(defaults: defaults)),
            historyInSidebar: SidebarDialTuning.historyInSidebar(defaults: defaults),
            projectsLayout: SidebarDialTuning.projectsLayout(defaults: defaults).rawValue
        )
    }

    /// Diff-based, same rationale as `ComposerDialKitCoordinator.write` —
    /// only a field that actually moved between `previous`/`model` is
    /// persisted, so this panel never clobbers a key it didn't touch.
    private func write(from previous: SidebarDialKitTuningModel, to model: SidebarDialKitTuningModel) {
        guard previous != model else { return }
        // The appearance preview is process state, not a dial: it never
        // reaches `UserDefaults`, and the sidebar re-renders through the
        // appearance change itself.
        if previous.previewAppearance != model.previewAppearance,
           let mode = SidebarAppearancePreview.Mode(rawValue: model.previewAppearance) {
            SidebarAppearancePreview.set(mode)
        }
        var persisted = model
        persisted.previewAppearance = previous.previewAppearance
        guard previous != persisted else { return }

        func setIfChanged(_ key: String, _ old: Double, _ new: Double) {
            guard old != new else { return }
            defaults.set(new, forKey: key)
        }
        func setStringIfChanged(_ key: String, _ old: String, _ new: String) {
            guard old != new else { return }
            defaults.set(new, forKey: key)
        }
        func setBoolIfChanged(_ key: String, _ old: Bool, _ new: Bool) {
            guard old != new else { return }
            defaults.set(new, forKey: key)
        }
        func writeGlass(_ keys: SidebarDialTuning.GlassKeys, _ old: SidebarDialKitGlassModel, _ new: SidebarDialKitGlassModel) {
            setStringIfChanged(keys.variant, old.variant, new.variant)
            setIfChanged(keys.tintOpacity, old.tintOpacity, new.tintOpacity)
            setIfChanged(keys.surfaceOpacity, old.surfaceOpacity, new.surfaceOpacity)
            setIfChanged(keys.rimWidth, old.rimWidth, new.rimWidth)
            setIfChanged(keys.rimOpacity, old.rimOpacity, new.rimOpacity)
            setIfChanged(keys.chromaticIntensity, old.chromaticIntensity, new.chromaticIntensity)
            setIfChanged(keys.chromaticWidth, old.chromaticWidth, new.chromaticWidth)
            setIfChanged(keys.chromaticRotation, old.chromaticRotation, new.chromaticRotation)
            setIfChanged(keys.chromaticBlur, old.chromaticBlur, new.chromaticBlur)
            setStringIfChanged(keys.chromaticPalette, old.chromaticPalette, new.chromaticPalette)
            setStringIfChanged(keys.chromaticBlend, old.chromaticBlend, new.chromaticBlend)
            setIfChanged(keys.specularStrength, old.specularStrength, new.specularStrength)
            setIfChanged(keys.specularAngle, old.specularAngle, new.specularAngle)
            setStringIfChanged(keys.backdropMaterial, old.backdropMaterial, new.backdropMaterial)
            setIfChanged(keys.backdropOpacity, old.backdropOpacity, new.backdropOpacity)
            setIfChanged(keys.surfaceBlur, old.surfaceBlur, new.surfaceBlur)
        }
        setBoolIfChanged(SidebarDialTuning.redlinesKey, previous.redlines, model.redlines)
        setIfChanged(SidebarDialTuning.windowMarginKey, previous.windowMargin, model.windowMargin)
        writeGlass(SidebarDialTuning.lightGlassKeys, previous.glassLight, model.glassLight)
        writeGlass(SidebarDialTuning.darkGlassKeys, previous.glassDark, model.glassDark)
        setBoolIfChanged(SidebarDialTuning.trayGlassInteractiveKey, previous.trayGlassInteractive, model.trayGlassInteractive)
        setIfChanged(SidebarDialTuning.trayHorizontalIconSizeKey, previous.trayHorizontalIconSize, model.trayHorizontalIconSize)
        setIfChanged(SidebarDialTuning.trayInnerPaddingKey, previous.trayInnerPadding, model.trayInnerPadding)
        setStringIfChanged(SidebarDialTuning.trayGlassCornerStyleKey, previous.trayGlassCornerStyle, model.trayGlassCornerStyle)
        setIfChanged(SidebarDialTuning.rowTitleSizeKey, previous.rowTitleSize, model.rowTitleSize)
        setIfChanged(SidebarDialTuning.rowSubtitleSizeKey, previous.rowSubtitleSize, model.rowSubtitleSize)
        setIfChanged(SidebarDialTuning.rowGhostSizeKey, previous.rowGhostSize, model.rowGhostSize)
        setIfChanged(SidebarDialTuning.rowLeadingPaddingKey, previous.rowLeadingPadding, model.rowLeadingPadding)
        setIfChanged(SidebarDialTuning.rowTrailingPaddingKey, previous.rowTrailingPadding, model.rowTrailingPadding)
        setIfChanged(SidebarDialTuning.contentPaddingTopKey, previous.contentPaddingTop, model.contentPaddingTop)
        setIfChanged(SidebarDialTuning.listToTrayGapKey, previous.listToTrayGap, model.listToTrayGap)
        setBoolIfChanged(SidebarDialTuning.historyInSidebarKey, previous.historyInSidebar, model.historyInSidebar)
        setStringIfChanged(SidebarDialTuning.projectsLayoutKey, previous.projectsLayout, model.projectsLayout)
        // Any write at all is a tuning change a row's `.equatable()` gate
        // can't see on its own — see `SidebarDialTuning.epochKey`'s doc
        // comment.
        defaults.set(SidebarDialTuning.epoch(defaults: defaults) + 1, forKey: SidebarDialTuning.epochKey)
        onChange()
    }

    private static let resetActionPath = "resetSidebar"

    /// One appearance's glass group. Control paths are prefixed (`light…`,
    /// `dark…`) so the two groups never share an id.
    private static func glassControls(
        _ prefix: String,
        _ glass: WritableKeyPath<SidebarDialKitTuningModel, SidebarDialKitGlassModel>
    ) -> [DialControl<SidebarDialKitTuningModel>] {
        [
            .select("\(prefix)Variant", keyPath: glass.appending(path: \.variant), label: "Glass variant",
                    options: TrayGlassStyle.Variant.allCases.map(\.rawValue)),
            .slider("\(prefix)TintOpacity", keyPath: glass.appending(path: \.tintOpacity),
                    label: prefix == "dark" ? "Glass warm tint" : "Glass white tint", range: 0...1, step: 0.05),
            .slider("\(prefix)SurfaceOpacity", keyPath: glass.appending(path: \.surfaceOpacity),
                    label: prefix == "dark" ? "Grey layer opacity" : "White layer opacity", range: 0...1, step: 0.05),
            // Blur. The native glass has no blur amount (only its variant:
            // `regular` frosts, `clear` barely does, `identity` is no glass),
            // so the blur is a system material under the layer above. It
            // shows only where that layer is below 1.
            .select("\(prefix)BackdropMaterial", keyPath: glass.appending(path: \.backdropMaterial),
                    label: "Backdrop blur (thicker = more)",
                    options: TrayGlassStyle.BackdropMaterial.allCases.map(\.rawValue)),
            .slider("\(prefix)BackdropOpacity", keyPath: glass.appending(path: \.backdropOpacity),
                    label: "Backdrop blur opacity", range: 0...1, step: 0.05),
            .slider("\(prefix)SurfaceBlur", keyPath: glass.appending(path: \.surfaceBlur),
                    label: prefix == "dark" ? "Grey layer edge blur" : "White layer edge blur",
                    range: 0...16, step: 0.5, unit: "pt"),
            .slider("\(prefix)RimWidth", keyPath: glass.appending(path: \.rimWidth), label: "Rim width", range: 0...4, step: 0.25, unit: "pt"),
            .slider("\(prefix)RimOpacity", keyPath: glass.appending(path: \.rimOpacity), label: "Rim opacity", range: 0...1, step: 0.02),
            .slider("\(prefix)ChromaticIntensity", keyPath: glass.appending(path: \.chromaticIntensity), label: "Chromatic rim intensity", range: 0...1, step: 0.05),
            .slider("\(prefix)ChromaticWidth", keyPath: glass.appending(path: \.chromaticWidth), label: "Chromatic rim width", range: 0.5...6, step: 0.25, unit: "pt"),
            .slider("\(prefix)ChromaticRotation", keyPath: glass.appending(path: \.chromaticRotation), label: "Chromatic rim rotation", range: 0...360, step: 0.1, unit: "°"),
            .slider("\(prefix)ChromaticBlur", keyPath: glass.appending(path: \.chromaticBlur), label: "Chromatic rim blur", range: 0...3, step: 0.1, unit: "pt"),
            .select("\(prefix)ChromaticPalette", keyPath: glass.appending(path: \.chromaticPalette), label: "Chromatic palette",
                    options: TrayGlassStyle.ChromaticPalette.allCases.map(\.rawValue)),
            .select("\(prefix)ChromaticBlend", keyPath: glass.appending(path: \.chromaticBlend), label: "Chromatic blend",
                    options: TrayGlassStyle.ChromaticBlend.allCases.map(\.rawValue)),
            .slider("\(prefix)SpecularStrength", keyPath: glass.appending(path: \.specularStrength), label: "Specular strength", range: 0...1, step: 0.05),
            .slider("\(prefix)SpecularAngle", keyPath: glass.appending(path: \.specularAngle), label: "Specular angle", range: 0...360, step: 1, unit: "°")
        ]
    }

    private static let controls: [DialControl<SidebarDialKitTuningModel>] = [
        // Not a dial: flips the sidebar between light and dark for this
        // session only, so each glass group can be tuned on its own look.
        .select("previewAppearance", keyPath: \.previewAppearance, label: "Preview appearance",
                options: SidebarAppearancePreview.Mode.allCases.map(\.rawValue)),
        // Not a dial either: spacing bands measured off the live layout.
        .toggle("redlines", keyPath: \.redlines, label: "Redlines"),
        // Colour and material, one group per appearance. Each drives the
        // tray on both axes. The selected chip has no rim.
        .group("glassLight", label: "Glass — Light", children: glassControls("light", \.glassLight)),
        .group("glassDark", label: "Glass — Dark", children: glassControls("dark", \.glassDark)),
        // Shape and behaviour, shared by both appearances.
        .group("trayGlass", label: "Tray — shared", children: [
            .toggle("trayGlassInteractive", keyPath: \.trayGlassInteractive, label: "Glass interactive (tray)"),
            .slider("trayHorizontalIconSize", keyPath: \.trayHorizontalIconSize, label: "Bar icon size (expanded)", range: 10...24, step: 0.5, unit: "pt"),
            .slider("trayInnerPadding", keyPath: \.trayInnerPadding, label: "Inner padding", range: 0...16, step: 0.5, unit: "pt"),
            .select("trayGlassCornerStyle", keyPath: \.trayGlassCornerStyle, label: "Corner style",
                    options: TrayGlassStyle.CornerStyle.allCases.map(\.rawValue)),
        ]),
        // Rows
        .slider("rowTitleSize", keyPath: \.rowTitleSize, label: "Row title size", range: 9...16, unit: "pt"),
        .slider("rowSubtitleSize", keyPath: \.rowSubtitleSize, label: "Row subtitle size", range: 8...14, unit: "pt"),
        .slider("rowGhostSize", keyPath: \.rowGhostSize, label: "Row ghost size", range: 8...24, unit: "pt"),
        .slider("rowLeadingPadding", keyPath: \.rowLeadingPadding, label: "Row leading padding", range: 0...24, unit: "pt"),
        .slider("rowTrailingPadding", keyPath: \.rowTrailingPadding, label: "Row trailing padding", range: 0...24, unit: "pt"),
        // Sidebar layout. Window margin is every outer gutter; the content
        // paddings below are inner spacing inside it.
        .slider("windowMargin", keyPath: \.windowMargin, label: "Window margin", range: 0...32, unit: "pt"),
        .slider("contentPaddingTop", keyPath: \.contentPaddingTop, label: "Content padding top", range: 0...24, unit: "pt"),
        .slider("listToTrayGap", keyPath: \.listToTrayGap, label: "List-to-tray gap", range: 0...24, unit: "pt"),
        .toggle("historyInSidebar", keyPath: \.historyInSidebar, label: "History in sidebar"),
        .select("projectsLayout", keyPath: \.projectsLayout, label: "Projects layout",
                options: SidebarProjectsLayout.allCases.map(\.rawValue)),
        // The expanded sidebar's and the rail's own knobs live in their
        // own panels (`SidebarListDialPanel`, `RailDialPanel`).
        // Clears every panel's keys: this one's, "Sidebar"'s and "Rail"'s.
        .action(resetActionPath, label: "Reset all panels")
    ]
}

@available(macOS 14, *)
@MainActor
private final class SidebarDialKitCoordinatorBox {
    weak var coordinator: SidebarDialKitCoordinator?
}

/// A focused panel: one area's knobs in the inspector, moved out of
/// "Sidebar Tuning" with their keys unchanged so saved values carry over.
/// Its Reset clears `resetKeys` only; "Reset sidebar" clears them too.
@available(macOS 14, *)
@MainActor
protocol FocusedDialPanel {
    associatedtype Model: Codable & Equatable
    static var name: String { get }
    static var resetLabel: String { get }
    static var resetKeys: [String] { get }
    static var controls: [DialControl<Model>] { get }
    static func read(_ defaults: UserDefaults) -> Model
    /// Writes only the fields that moved between `old` and `new`.
    static func write(_ defaults: UserDefaults, from old: Model, to new: Model)
    /// Recomputes any read-only fields from the rest of the model (the
    /// colours panel's contrast rows). Never writes defaults.
    static func derive(_ model: inout Model, defaults: UserDefaults)
}

@available(macOS 14, *)
extension FocusedDialPanel {
    static func derive(_ model: inout Model, defaults: UserDefaults) {}
}

/// Owns one `FocusedDialPanel`'s `DialPanelState`: the same diff-based
/// write and Reset shape as `SidebarDialKitCoordinator`.
@available(macOS 14, *)
@MainActor
final class FocusedDialKitCoordinator<Panel: FocusedDialPanel>: ObservableObject {
    let state: DialPanelState<Panel.Model>
    private var cancellable: AnyCancellable?
    private var resetObserver: AnyCancellable?
    private let defaults: UserDefaults
    private let onChange: () -> Void
    private var lastKnownModel: Panel.Model

    init(defaults: UserDefaults, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        let initial = Panel.read(defaults)
        lastKnownModel = initial
        let selfBox = FocusedDialKitCoordinatorBox<Panel>()
        state = DialPanelState(
            name: Panel.name,
            initial: initial,
            controls: Panel.controls + [.action(Self.resetActionPath, label: Panel.resetLabel)],
            onAction: { path in selfBox.coordinator?.handleAction(path) }
        )
        lastKnownModel = state.values
        cancellable = state.$values
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handle(newValue)
            }
        // Another panel's Reset may have cleared keys this one reads.
        resetObserver = NotificationCenter.default
            .publisher(for: SidebarDialTuning.didResetNotification)
            .sink { [weak self] note in
                guard let self, (note.object as AnyObject?) !== self else { return }
                self.reloadFromDefaults()
            }
        selfBox.coordinator = self
    }

    func handleAction(_ path: String) {
        guard path == Self.resetActionPath else { return }
        SidebarDialTuning.reset(keys: Panel.resetKeys, defaults: defaults)
        reloadFromDefaults()
        NotificationCenter.default.post(name: SidebarDialTuning.didResetNotification, object: self)
        onChange()
    }

    private func reloadFromDefaults() {
        let freshModel = Panel.read(defaults)
        lastKnownModel = freshModel
        state.values = freshModel
    }

    private func handle(_ model: Panel.Model) {
        let previous = lastKnownModel
        lastKnownModel = model
        guard previous != model else { return }
        Panel.write(defaults, from: previous, to: model)
        defaults.set(SidebarDialTuning.epoch(defaults: defaults) + 1, forKey: SidebarDialTuning.epochKey)
        onChange()
        var derived = model
        Panel.derive(&derived, defaults: defaults)
        guard derived != model else { return }
        // Next turn, not inside this `values` sink: re-derive from whatever
        // the panel holds by then so a value still arriving is never undone.
        DispatchQueue.main.async { [weak self] in self?.applyDerived() }
    }

    private func applyDerived() {
        var derived = state.values
        Panel.derive(&derived, defaults: defaults)
        guard derived != state.values else { return }
        lastKnownModel = derived
        state.values = derived
    }

    private static var resetActionPath: String { "reset" }
}

@available(macOS 14, *)
@MainActor
private final class FocusedDialKitCoordinatorBox<Panel: FocusedDialPanel> {
    weak var coordinator: FocusedDialKitCoordinator<Panel>?
}

/// Writes `new` under `key` when it differs from `old`.
private func setIfChanged<T: Equatable>(_ defaults: UserDefaults, _ key: String, _ old: T, _ new: T) {
    guard old != new else { return }
    defaults.set(new, forKey: key)
}

/// The "Rail" panel: only the knobs that change the collapsed rail, plus
/// dark's tray shadow, shared by every state (light's is per state, in
/// "Tray shadow").
@available(macOS 14, *)
@MainActor
enum RailDialPanel: FocusedDialPanel {
    static let name = "Rail"
    static let resetLabel = "Reset rail"
    static var resetKeys: [String] { SidebarDialTuning.railKeys }

    static func read(_ defaults: UserDefaults) -> RailDialKitTuningModel {
        RailDialKitTuningModel(
            trayVerticalIconSize: Double(SidebarDialTuning.trayVerticalIconSize(defaults: defaults)),
            railTrayIconGap: Double(SidebarDialTuning.railTrayIconGap(defaults: defaults)),
            railTrayPillSize: Double(SidebarDialTuning.railTrayPillSize(defaults: defaults)),
            trayHoverInset: Double(SidebarDialTuning.trayHoverInset(defaults: defaults)),
            shadowDark: shadow(SidebarDialTuning.trayGlass(for: .dark, defaults: defaults)),
            railExtraWidth: Double(SidebarDialTuning.railExtraWidth(defaults: defaults)),
            railColumnTintOpacity: SidebarDialTuning.railColumnTintOpacity(defaults: defaults),
            railColumnInset: Double(SidebarDialTuning.railColumnInset(defaults: defaults)),
            railChipCornerRadius: Double(SidebarDialTuning.railChipCornerRadius(defaults: defaults)),
            railSelectedTileFill: SidebarDialTuning.railSelectedTileFill(defaults: defaults),
            railProjectTileSize: Double(SidebarDialTuning.railProjectTileSize(defaults: defaults)),
            railProjectTileText: Double(SidebarDialTuning.railProjectTileText(defaults: defaults)),
            railThreadTileSize: Double(SidebarDialTuning.railThreadTileSize(defaults: defaults)),
            railThreadTileIcon: Double(SidebarDialTuning.railThreadTileIcon(defaults: defaults))
        )
    }

    static func write(_ defaults: UserDefaults, from previous: RailDialKitTuningModel, to model: RailDialKitTuningModel) {
        setIfChanged(defaults, SidebarDialTuning.trayVerticalIconSizeKey, previous.trayVerticalIconSize, model.trayVerticalIconSize)
        setIfChanged(defaults, SidebarDialTuning.railTrayIconGapKey, previous.railTrayIconGap, model.railTrayIconGap)
        setIfChanged(defaults, SidebarDialTuning.railTrayPillSizeKey, previous.railTrayPillSize, model.railTrayPillSize)
        setIfChanged(defaults, SidebarDialTuning.trayHoverInsetKey, previous.trayHoverInset, model.trayHoverInset)
        let darkKeys = SidebarDialTuning.darkGlassKeys
        setIfChanged(defaults, darkKeys.shadowOpacity, previous.shadowDark.opacity, model.shadowDark.opacity)
        setIfChanged(defaults, darkKeys.shadowRadius, previous.shadowDark.radius, model.shadowDark.radius)
        setIfChanged(defaults, darkKeys.shadowYOffset, previous.shadowDark.yOffset, model.shadowDark.yOffset)
        setIfChanged(defaults, SidebarDialTuning.railExtraWidthKey, previous.railExtraWidth, model.railExtraWidth)
        setIfChanged(defaults, SidebarDialTuning.railColumnTintOpacityKey, previous.railColumnTintOpacity, model.railColumnTintOpacity)
        setIfChanged(defaults, SidebarDialTuning.railColumnInsetKey, previous.railColumnInset, model.railColumnInset)
        setIfChanged(defaults, SidebarDialTuning.railChipCornerRadiusKey, previous.railChipCornerRadius, model.railChipCornerRadius)
        setIfChanged(defaults, SidebarDialTuning.railSelectedTileFillKey, previous.railSelectedTileFill, model.railSelectedTileFill)
        setIfChanged(defaults, SidebarDialTuning.railProjectTileSizeKey, previous.railProjectTileSize, model.railProjectTileSize)
        setIfChanged(defaults, SidebarDialTuning.railProjectTileTextKey, previous.railProjectTileText, model.railProjectTileText)
        setIfChanged(defaults, SidebarDialTuning.railThreadTileSizeKey, previous.railThreadTileSize, model.railThreadTileSize)
        setIfChanged(defaults, SidebarDialTuning.railThreadTileIconKey, previous.railThreadTileIcon, model.railThreadTileIcon)
    }

    private static func shadow(_ look: TrayGlassStyle.Look) -> RailDialKitTuningModel.Shadow {
        .init(opacity: look.shadowOpacity, radius: Double(look.shadowRadius), yOffset: Double(look.shadowYOffset))
    }

    private static func shadowControls(
        _ prefix: String,
        _ shadow: WritableKeyPath<RailDialKitTuningModel, RailDialKitTuningModel.Shadow>
    ) -> [DialControl<RailDialKitTuningModel>] {
        [
            .slider("\(prefix)ShadowOpacity", keyPath: shadow.appending(path: \.opacity), label: "Shadow opacity", range: 0...0.6, step: 0.01),
            .slider("\(prefix)ShadowRadius", keyPath: shadow.appending(path: \.radius), label: "Shadow radius", range: 0...32, step: 0.5, unit: "pt"),
            .slider("\(prefix)ShadowYOffset", keyPath: shadow.appending(path: \.yOffset), label: "Shadow Y", range: 0...16, step: 0.5, unit: "pt"),
        ]
    }

    static var controls: [DialControl<RailDialKitTuningModel>] {
        [
            // The square pills (`RailTrayGeometry`): the icon size sets each
            // icon's inset to its pill edge; the gap groups the stacked pair.
            .group("railTray", label: "Tray", children: [
                .slider("trayVerticalIconSize", keyPath: \.trayVerticalIconSize, label: "Pill icon size (rail)", range: 10...24, step: 0.5, unit: "pt"),
                .slider("railTrayIconGap", keyPath: \.railTrayIconGap, label: "Tray icon gap (rail)", range: 0...40, step: 1, unit: "pt"),
                .slider("railTrayPillSize", keyPath: \.railTrayPillSize, label: "Pill size (rail)", range: 28...82, step: 1, unit: "pt"),
                // Both trays: the hover chip's inset from its button cell.
                .slider("trayHoverInset", keyPath: \.trayHoverInset, label: "Hover inset", range: 0...12, step: 0.5, unit: "pt"),
            ]),
            // The tray pills' shadow in dark, every state. Light's is per
            // state, in the "Tray shadow" panel.
            .group("trayShadowDark", label: "Tray shadow — Dark (all states)", children: shadowControls("dark", \.shadowDark)),
            .slider("railExtraWidth", keyPath: \.railExtraWidth, label: "Rail extra width", range: 0...60, unit: "pt"),
            // One view's selected project column (`RailProjectColumn`).
            .group("railColumn", label: "Rail column", children: [
                .slider("railColumnTintOpacity", keyPath: \.railColumnTintOpacity, label: "Column tint (dark)", range: 0...0.3, step: 0.005),
                .slider("railColumnInset", keyPath: \.railColumnInset, label: "Column inset", range: 0...12, step: 0.5, unit: "pt"),
                .slider("railChipCornerRadius", keyPath: \.railChipCornerRadius, label: "Chip corner radius", range: 0...20, step: 0.5, unit: "pt"),
                .slider("railSelectedTileFill", keyPath: \.railSelectedTileFill, label: "Selected tile fill", range: 0...1, step: 0.05),
            ]),
            // The column's project tile and its rows' thread tiles (chips).
            .group("railTiles", label: "Rail tiles", children: [
                .slider("railProjectTileSize", keyPath: \.railProjectTileSize, label: "Project tile size", range: 20...44, step: 1, unit: "pt"),
                .slider("railProjectTileText", keyPath: \.railProjectTileText, label: "Project tile text", range: 8...20, step: 0.5, unit: "pt"),
                .slider("railThreadTileSize", keyPath: \.railThreadTileSize, label: "Thread tile size", range: 20...44, step: 1, unit: "pt"),
                .slider("railThreadTileIcon", keyPath: \.railThreadTileIcon, label: "Thread tile icon", range: 8...32, step: 0.5, unit: "pt"),
            ]),
        ]
    }
}

/// The "Tray shadow" panel's model: light's tray pill shadow per state.
@available(macOS 14, *)
struct TrayShadowDialKitTuningModel: Codable, Equatable {
    struct Shadow: Codable, Equatable {
        var opacity: Double
        var radius: Double
        var yOffset: Double
    }

    var sidebar: Shadow
    var rail: Shadow
    var hoverBar: Shadow
}

/// The "Tray shadow" panel: the tray pills' shadow in light appearance,
/// independent for the pinned sidebar, the rail and the hover bar. Each
/// tray reads its current mode's set live (`trayGlass(for:state:)`).
@available(macOS 14, *)
@MainActor
enum TrayShadowDialPanel: FocusedDialPanel {
    static let name = "Tray shadow"
    static let resetLabel = "Reset tray shadow"
    static var resetKeys: [String] { SidebarDialTuning.trayShadowStateKeys }

    static func read(_ defaults: UserDefaults) -> TrayShadowDialKitTuningModel {
        func shadow(_ state: SidebarDialTuning.TrayShadowState) -> TrayShadowDialKitTuningModel.Shadow {
            let look = SidebarDialTuning.trayGlass(for: .light, state: state, defaults: defaults)
            return .init(opacity: look.shadowOpacity, radius: Double(look.shadowRadius), yOffset: Double(look.shadowYOffset))
        }
        return TrayShadowDialKitTuningModel(sidebar: shadow(.sidebar), rail: shadow(.rail), hoverBar: shadow(.hoverBar))
    }

    static func write(_ defaults: UserDefaults, from previous: TrayShadowDialKitTuningModel, to model: TrayShadowDialKitTuningModel) {
        let pairs: [(SidebarDialTuning.TrayShadowState, TrayShadowDialKitTuningModel.Shadow, TrayShadowDialKitTuningModel.Shadow)] = [
            (.sidebar, previous.sidebar, model.sidebar),
            (.rail, previous.rail, model.rail),
            (.hoverBar, previous.hoverBar, model.hoverBar),
        ]
        for (state, old, new) in pairs {
            let keys = SidebarDialTuning.trayShadowKeys(state)
            setIfChanged(defaults, keys.opacity, old.opacity, new.opacity)
            setIfChanged(defaults, keys.radius, old.radius, new.radius)
            setIfChanged(defaults, keys.yOffset, old.yOffset, new.yOffset)
        }
    }

    private static func controls(
        _ prefix: String,
        _ shadow: WritableKeyPath<TrayShadowDialKitTuningModel, TrayShadowDialKitTuningModel.Shadow>
    ) -> [DialControl<TrayShadowDialKitTuningModel>] {
        [
            .slider("\(prefix)Opacity", keyPath: shadow.appending(path: \.opacity), label: "Opacity", range: 0...0.25, step: 0.01),
            .slider("\(prefix)Radius", keyPath: shadow.appending(path: \.radius), label: "Radius", range: 0...24, step: 0.5, unit: "pt"),
            .slider("\(prefix)YOffset", keyPath: shadow.appending(path: \.yOffset), label: "Y offset (down)", range: 0...16, step: 0.5, unit: "pt"),
        ]
    }

    static var controls: [DialControl<TrayShadowDialKitTuningModel>] {
        [
            .group("sidebar", label: "Sidebar — Light", children: controls("sidebar", \.sidebar)),
            .group("rail", label: "Rail — Light", children: controls("rail", \.rail)),
            .group("hoverBar", label: "Hover bar — Light", children: controls("hoverBar", \.hoverBar)),
        ]
    }
}

/// The "Sidebar" panel: only the expanded sidebar's own knobs. The tray
/// shadow lives in "Tray shadow" (light) and "Rail" (dark); the pills' and card's corner
/// radius has no dial, it follows the window margin ("Glass & Layout").
@available(macOS 14, *)
@MainActor
enum SidebarListDialPanel: FocusedDialPanel {
    static let name = "Sidebar"
    static let resetLabel = "Reset sidebar list"
    static var resetKeys: [String] { SidebarDialTuning.sidebarListKeys }

    static func read(_ defaults: UserDefaults) -> SidebarListDialKitTuningModel {
        SidebarListDialKitTuningModel(
            rowHeight: Double(SidebarDialTuning.rowHeight(defaults: defaults)),
            rowGap: Double(SidebarDialTuning.rowGap(defaults: defaults)),
            selectedTitleWeight: SidebarDialTuning.selectedTitleWeight(defaults: defaults).rawValue,
            trayHorizontalButtonSize: Double(SidebarDialTuning.trayHorizontalButtonSize(defaults: defaults)),
            trayGroupGap: Double(SidebarDialTuning.trayGroupGap(defaults: defaults)),
            trayWidth: SidebarDialTuning.trayWidth(defaults: defaults).rawValue,
            contentPaddingLeading: Double(SidebarDialTuning.contentPaddingLeading(defaults: defaults)),
            contentPaddingTrailing: Double(SidebarDialTuning.contentPaddingTrailing(defaults: defaults)),
            groupCardInset: Double(SidebarDialTuning.groupCardInset(defaults: defaults)),
            sidebarProjectTileSize: Double(SidebarDialTuning.sidebarProjectTileSize(defaults: defaults)),
            sidebarProjectTileText: Double(SidebarDialTuning.sidebarProjectTileText(defaults: defaults)),
            sidebarThreadTileSize: Double(SidebarDialTuning.sidebarThreadTileSize(defaults: defaults)),
            sidebarThreadTileIcon: Double(SidebarDialTuning.sidebarThreadTileIcon(defaults: defaults)),
            hoverRevealEnabled: SidebarDialTuning.hoverRevealEnabled(defaults: defaults),
            hoverRevealDwell: SidebarDialTuning.hoverRevealDwell(defaults: defaults),
            hoverRevealExitGrace: SidebarDialTuning.hoverRevealExitGrace(defaults: defaults),
            hoverRevealStyle: SidebarDialTuning.hoverRevealStyle(defaults: defaults).rawValue,
            motionOpenResponse: SidebarDialTuning.motionOpenResponse(defaults: defaults),
            motionOpenBounce: SidebarDialTuning.motionOpenBounce(defaults: defaults),
            motionCollapseResponse: SidebarDialTuning.motionCollapseResponse(defaults: defaults),
            motionCollapseBounce: SidebarDialTuning.motionCollapseBounce(defaults: defaults),
            uiSpringResponse: SidebarDialTuning.uiSpringResponse(defaults: defaults),
            uiSpringBounce: SidebarDialTuning.uiSpringBounce(defaults: defaults),
            uiSpringHoverResponse: SidebarDialTuning.uiSpringHoverResponse(defaults: defaults)
        )
    }

    static func write(_ defaults: UserDefaults, from previous: SidebarListDialKitTuningModel, to model: SidebarListDialKitTuningModel) {
        setIfChanged(defaults, SidebarDialTuning.rowHeightKey, previous.rowHeight, model.rowHeight)
        setIfChanged(defaults, SidebarDialTuning.rowGapKey, previous.rowGap, model.rowGap)
        setIfChanged(defaults, SidebarDialTuning.selectedTitleWeightKey, previous.selectedTitleWeight, model.selectedTitleWeight)
        setIfChanged(defaults, SidebarDialTuning.trayHorizontalButtonSizeKey, previous.trayHorizontalButtonSize, model.trayHorizontalButtonSize)
        setIfChanged(defaults, SidebarDialTuning.trayGroupGapKey, previous.trayGroupGap, model.trayGroupGap)
        setIfChanged(defaults, SidebarDialTuning.trayWidthKey, previous.trayWidth, model.trayWidth)
        setIfChanged(defaults, SidebarDialTuning.contentPaddingLeadingKey, previous.contentPaddingLeading, model.contentPaddingLeading)
        setIfChanged(defaults, SidebarDialTuning.contentPaddingTrailingKey, previous.contentPaddingTrailing, model.contentPaddingTrailing)
        setIfChanged(defaults, SidebarDialTuning.groupCardInsetKey, previous.groupCardInset, model.groupCardInset)
        setIfChanged(defaults, SidebarDialTuning.sidebarProjectTileSizeKey, previous.sidebarProjectTileSize, model.sidebarProjectTileSize)
        setIfChanged(defaults, SidebarDialTuning.sidebarProjectTileTextKey, previous.sidebarProjectTileText, model.sidebarProjectTileText)
        setIfChanged(defaults, SidebarDialTuning.sidebarThreadTileSizeKey, previous.sidebarThreadTileSize, model.sidebarThreadTileSize)
        setIfChanged(defaults, SidebarDialTuning.sidebarThreadTileIconKey, previous.sidebarThreadTileIcon, model.sidebarThreadTileIcon)
        setIfChanged(defaults, SidebarDialTuning.hoverRevealEnabledKey, previous.hoverRevealEnabled, model.hoverRevealEnabled)
        setIfChanged(defaults, SidebarDialTuning.hoverRevealDwellKey, previous.hoverRevealDwell, model.hoverRevealDwell)
        setIfChanged(defaults, SidebarDialTuning.hoverRevealExitGraceKey, previous.hoverRevealExitGrace, model.hoverRevealExitGrace)
        setIfChanged(defaults, SidebarDialTuning.hoverRevealStyleKey, previous.hoverRevealStyle, model.hoverRevealStyle)
        setIfChanged(defaults, SidebarDialTuning.motionOpenResponseKey, previous.motionOpenResponse, model.motionOpenResponse)
        setIfChanged(defaults, SidebarDialTuning.motionOpenBounceKey, previous.motionOpenBounce, model.motionOpenBounce)
        setIfChanged(defaults, SidebarDialTuning.motionCollapseResponseKey, previous.motionCollapseResponse, model.motionCollapseResponse)
        setIfChanged(defaults, SidebarDialTuning.motionCollapseBounceKey, previous.motionCollapseBounce, model.motionCollapseBounce)
        setIfChanged(defaults, SidebarDialTuning.uiSpringResponseKey, previous.uiSpringResponse, model.uiSpringResponse)
        setIfChanged(defaults, SidebarDialTuning.uiSpringBounceKey, previous.uiSpringBounce, model.uiSpringBounce)
        setIfChanged(defaults, SidebarDialTuning.uiSpringHoverResponseKey, previous.uiSpringHoverResponse, model.uiSpringHoverResponse)
    }

    static var controls: [DialControl<SidebarListDialKitTuningModel>] {
        [
            .group("rows", label: "Rows", children: [
                .slider("rowHeight", keyPath: \.rowHeight, label: "Row height", range: 32...64, unit: "pt"),
                .slider("rowGap", keyPath: \.rowGap, label: "Row gap", range: 0...12, unit: "pt"),
            ]),
            // The selected row's title weight; the row itself is marked by
            // the chip (`SidebarRowChipBackground`).
            .group("selectedRow", label: "Selected row", children: [
                .select("selectedTitleWeight", keyPath: \.selectedTitleWeight, label: "Selected title weight",
                        options: TrayGlassStyle.SelectedTitleWeight.allCases.map(\.rawValue)),
            ]),
            .group("expandedTray", label: "Tray (expanded)", children: [
                .slider("trayHorizontalButtonSize", keyPath: \.trayHorizontalButtonSize, label: "Pill height", range: 24...56, step: 0.5, unit: "pt"),
                .slider("trayGroupGap", keyPath: \.trayGroupGap, label: "Tray group gap", range: 0...16, step: 0.5, unit: "pt"),
                .select("trayWidth", keyPath: \.trayWidth, label: "Tray width",
                        options: TrayGlassStyle.TrayWidth.allCases.map(\.rawValue)),
            ]),
            // The selected project's group card (`ProjectGroupCard`).
            .group("groupCard", label: "Group card", children: [
                .slider("groupCardInset", keyPath: \.groupCardInset, label: "Card inset", range: 0...16, step: 0.5, unit: "pt"),
            ]),
            // A group's project tile and its rows' thread tiles (chips).
            .group("tiles", label: "Tiles", children: [
                .slider("sidebarProjectTileSize", keyPath: \.sidebarProjectTileSize, label: "Project tile size", range: 20...44, step: 1, unit: "pt"),
                .slider("sidebarProjectTileText", keyPath: \.sidebarProjectTileText, label: "Project tile text", range: 8...20, step: 0.5, unit: "pt"),
                .slider("sidebarThreadTileSize", keyPath: \.sidebarThreadTileSize, label: "Thread tile size", range: 20...44, step: 1, unit: "pt"),
                .slider("sidebarThreadTileIcon", keyPath: \.sidebarThreadTileIcon, label: "Thread tile icon", range: 8...24, step: 0.5, unit: "pt"),
            ]),
            // Inner side margins of the list column, inside the window margin.
            .group("sideMargins", label: "Side margins", children: [
                .slider("contentPaddingLeading", keyPath: \.contentPaddingLeading, label: "Leading (inner)", range: 0...24, unit: "pt"),
                .slider("contentPaddingTrailing", keyPath: \.contentPaddingTrailing, label: "Trailing (inner)", range: 0...24, unit: "pt"),
            ]),
            // On the rail, resting the pointer reveals this sidebar over the
            // terminal (`RailHoverReveal`).
            .group("hoverReveal", label: "Hover reveal", children: [
                .toggle("hoverRevealEnabled", keyPath: \.hoverRevealEnabled, label: "Reveal on hover"),
                .select("hoverRevealStyle", keyPath: \.hoverRevealStyle, label: "Reveal style",
                        options: RailRevealStyle.allCases.map(\.rawValue)),
                .slider("hoverRevealDwell", keyPath: \.hoverRevealDwell, label: "Dwell", range: 0.3...3.0, step: 0.1, unit: "s"),
                .slider("hoverRevealExitGrace", keyPath: \.hoverRevealExitGrace, label: "Exit grace", range: 0...1.0, step: 0.05, unit: "s"),
            ]),
            // The sidebar ⇄ rail morph's springs (toggle and hover reveal).
            // Bounce 0 = no overshoot (critically damped).
            .group("motion", label: "Morph springs", children: [
                .slider("motionOpenResponse", keyPath: \.motionOpenResponse, label: "Open response", range: 0.15...0.8, step: 0.01, unit: "s"),
                .slider("motionOpenBounce", keyPath: \.motionOpenBounce, label: "Open bounce", range: 0...0.5, step: 0.01),
                .slider("motionCollapseResponse", keyPath: \.motionCollapseResponse, label: "Collapse response", range: 0.15...0.8, step: 0.01, unit: "s"),
                .slider("motionCollapseBounce", keyPath: \.motionCollapseBounce, label: "Collapse bounce", range: 0...0.5, step: 0.01),
            ]),
            // The small motion's springs (`SidebarUISpring`): fold, chip,
            // reflow, hover. Bounce 0 = no overshoot (critically damped);
            // closes and fades never overshoot at any bounce.
            .group("uiSprings", label: "UI springs", children: [
                .slider("uiSpringResponse", keyPath: \.uiSpringResponse, label: "Response", range: 0.1...0.8, step: 0.01, unit: "s"),
                .slider("uiSpringBounce", keyPath: \.uiSpringBounce, label: "Bounce", range: 0...0.5, step: 0.01),
                .slider("uiSpringHoverResponse", keyPath: \.uiSpringHoverResponse, label: "Hover response", range: 0.05...0.6, step: 0.01, unit: "s"),
            ]),
        ]
    }
}

/// DEBUG-only: owns the process-wide panels, "Glass & Layout", "Sidebar"
/// and "Rail" (the inspector's header menu switches between them), and starts the
/// inspector agent. Called once from `AppDelegate.applicationDidFinishLaunching`.
@available(macOS 14, *)
@MainActor
enum SidebarDialInspector {
    private static var coordinator: SidebarDialKitCoordinator?
    private static var sidebarListCoordinator: FocusedDialKitCoordinator<SidebarListDialPanel>?
    private static var railCoordinator: FocusedDialKitCoordinator<RailDialPanel>?
    private static var trayShadowCoordinator: FocusedDialKitCoordinator<TrayShadowDialPanel>?
    private static var colorsCoordinator: FocusedDialKitCoordinator<SidebarColorsDialPanel>?

    static func start() {
        guard coordinator == nil else { return }
        // A row's `.equatable()` gate can't see a tuning change on its
        // own; poking the store re-renders the sidebar and tray. AppKit
        // geometry (the card's inset constraints) listens for
        // `didChangeNotification` instead.
        let onChange = {
            WorkspaceStore.shared.objectWillChange.send()
            NotificationCenter.default.post(name: SidebarDialTuning.didChangeNotification, object: nil)
        }
        coordinator = SidebarDialKitCoordinator(defaults: SidebarDialTuning.store, onChange: onChange)
        sidebarListCoordinator = FocusedDialKitCoordinator(defaults: SidebarDialTuning.store, onChange: onChange)
        railCoordinator = FocusedDialKitCoordinator(defaults: SidebarDialTuning.store, onChange: onChange)
        trayShadowCoordinator = FocusedDialKitCoordinator(defaults: SidebarDialTuning.store, onChange: onChange)
        colorsCoordinator = FocusedDialKitCoordinator(defaults: SidebarDialTuning.store, onChange: onChange)
        DialKitAgent.shared.start(appName: "Ghostties")
    }
}
#endif
