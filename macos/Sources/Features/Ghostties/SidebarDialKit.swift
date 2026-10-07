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
    /// The defaults domain every dial is read from and written to. Production
    /// never touches it (`.standard`). The test bundle swaps in a throwaway
    /// suite at load (`GhosttiesTestIsolation`) so a hosted test never reads
    /// the dial values tuned in the live Dev app's domain. Every reader's
    /// default argument and every dial `@AppStorage` goes through it.
    nonisolated(unsafe) static var store: UserDefaults = .standard

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
    static let trayVerticalButtonSizeKey = "ghostties.sidebarDial.trayGlass.verticalButtonSize"
    static let trayVerticalIconSizeKey = "ghostties.sidebarDial.trayGlass.verticalIconSize"
    static let trayHorizontalButtonSizeKey = "ghostties.sidebarDial.trayGlass.horizontalButtonSize"
    static let trayHorizontalIconSizeKey = "ghostties.sidebarDial.trayGlass.horizontalIconSize"
    static let trayGlassCornerStyleKey = "ghostties.sidebarDial.trayGlass.cornerStyle"
    static let trayGlassCornerRadiusKey = "ghostties.sidebarDial.trayGlass.cornerRadius"
    static let traySelectedPillWidthKey = "ghostties.sidebarDial.trayGlass.selectedPillWidth"
    /// Retired "Selected style" dial; read only to migrate (`selectedRowStyle`).
    static let legacySelectedStyleKey = "ghostties.sidebarDial.trayGlass.selectedStyle"
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
        let selectedShadowOpacity: String
        let selectedShadowRadius: String
        let selectedShadowYOffset: String

        var all: [String] {
            [variant, tintOpacity, surfaceOpacity, rimWidth, rimOpacity,
             shadowOpacity, shadowRadius, shadowYOffset,
             chromaticIntensity, chromaticWidth, chromaticRotation, chromaticBlur,
             chromaticPalette, chromaticBlend, specularStrength, specularAngle,
             selectedShadowOpacity, selectedShadowRadius, selectedShadowYOffset]
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
        selectedShadowOpacity: "ghostties.sidebarDial.trayGlass.selectedShadowOpacity",
        selectedShadowRadius: "ghostties.sidebarDial.trayGlass.selectedShadowRadius",
        selectedShadowYOffset: "ghostties.sidebarDial.trayGlass.selectedShadowYOffset"
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
        selectedShadowOpacity: "ghostties.sidebarDial.trayGlass.dark.selectedShadowOpacity",
        selectedShadowRadius: "ghostties.sidebarDial.trayGlass.dark.selectedShadowRadius",
        selectedShadowYOffset: "ghostties.sidebarDial.trayGlass.dark.selectedShadowYOffset"
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

    // MARK: Sidebar layout
    static let contentPaddingTopKey = "ghostties.sidebarDial.contentPaddingTop"
    static let contentPaddingLeadingKey = "ghostties.sidebarDial.contentPaddingLeading"
    static let contentPaddingTrailingKey = "ghostties.sidebarDial.contentPaddingTrailing"
    static let listToTrayGapKey = "ghostties.sidebarDial.listToTrayGap"
    static let historyPlacementKey = "ghostties.sidebarDial.historyPlacement"
    static let trayStyleKey = "ghostties.sidebarDial.trayStyle"
    static let selectedRowStyleKey = "ghostties.sidebarDial.selectedRowStyle"

    // MARK: Rail
    static let railExtraWidthKey = "ghostties.sidebarDial.railExtraWidth"

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
    /// Gap between the tray's Create and Toggle capsules, on both axes.
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
            selectedShadowOpacity: double(keys.selectedShadowOpacity, default: base.selectedShadowOpacity, defaults: defaults),
            selectedShadowRadius: cgFloat(keys.selectedShadowRadius, default: base.selectedShadowRadius, defaults: defaults),
            selectedShadowYOffset: cgFloat(keys.selectedShadowYOffset, default: base.selectedShadowYOffset, defaults: defaults)
        )
    }
    /// The selected expanded row's title weight (`TrayGlassStyle.SelectedTitleWeight`).
    static func selectedTitleWeight(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.SelectedTitleWeight {
        choice(selectedTitleWeightKey, default: TrayGlassStyle.selectedTitleWeight, defaults: defaults)
    }
    static func trayGlassInteractive(defaults: UserDefaults = SidebarDialTuning.store) -> Bool {
        bool(trayGlassInteractiveKey, default: TrayGlassStyle.interactive, defaults: defaults)
    }
    static func trayVerticalButtonSize(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayVerticalButtonSizeKey, default: TrayGlassStyle.verticalButtonSize, defaults: defaults)
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
    static func trayGlassCornerRadius(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(trayGlassCornerRadiusKey, default: TrayGlassStyle.cornerRadius, defaults: defaults)
    }
    static func traySelectedPillWidth(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(traySelectedPillWidthKey, default: TrayGlassStyle.selectedPillWidth, defaults: defaults)
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

    /// Where the History row sits, in the expanded list and the rail
    /// (`SidebarSessionSections.HistoryPlacement`).
    static func historyPlacement(defaults: UserDefaults = SidebarDialTuning.store) -> SidebarSessionSections.HistoryPlacement {
        choice(historyPlacementKey, default: SidebarSessionSections.historyPlacement, defaults: defaults)
    }

    /// Whether the tray is drawn as glass capsules or as bare icons on the
    /// sidebar background (`TrayGlassStyle.TrayStyle`).
    static func trayStyle(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.TrayStyle {
        choice(trayStyleKey, default: TrayGlassStyle.trayStyle, defaults: defaults)
    }

    /// How the selected session row is marked (`TrayGlassStyle.SelectedRowStyle`).
    /// Reads the "Selected row" key; if it is absent, migrates (read-only)
    /// from the retired "Selected style" key (`legacySelectedStyleKey`, which
    /// shared the `glass` and `flat` names), else the compiled default.
    static func selectedRowStyle(defaults: UserDefaults = SidebarDialTuning.store) -> TrayGlassStyle.SelectedRowStyle {
        if let raw = defaults.string(forKey: selectedRowStyleKey),
           let style = TrayGlassStyle.SelectedRowStyle(rawValue: raw) {
            return style
        }
        if let raw = defaults.string(forKey: legacySelectedStyleKey),
           let style = TrayGlassStyle.SelectedRowStyle(rawValue: raw) {
            return style
        }
        return TrayGlassStyle.selectedRowStyle
    }

    /// Added on top of `WorkspaceLayout.collapsedRailWidth`'s computed hug
    /// width — see that function's own doc comment. Not folded into
    /// `WorkspaceLayout.railExtraWidth` (the compiled default both this and
    /// that function read) because the hug-width call sites are pure/testable
    /// functions that must not read `UserDefaults` directly.
    static func railExtraWidth(defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        cgFloat(railExtraWidthKey, default: WorkspaceLayout.railExtraWidth, defaults: defaults)
    }

    /// Every storage key this panel owns — used by `resetSidebar()` to clear
    /// back to code defaults in one pass, same shape as
    /// `ComposerSingleLineReset.resetKeys`.
    static let allKeys: [String] = lightGlassKeys.all + darkGlassKeys.all + [
        windowMarginKey, redlinesKey,
        trayInnerPaddingKey, trayGroupGapKey, trayWidthKey, trayGlassInteractiveKey,
        trayVerticalButtonSizeKey, trayVerticalIconSizeKey, trayHorizontalButtonSizeKey,
        trayHorizontalIconSizeKey, trayGlassCornerStyleKey, trayGlassCornerRadiusKey,
        traySelectedPillWidthKey, selectedTitleWeightKey,
        rowHeightKey, rowGapKey, rowTitleSizeKey, rowSubtitleSizeKey, rowGhostSizeKey,
        rowLeadingPaddingKey, rowTrailingPaddingKey,
        contentPaddingTopKey, contentPaddingLeadingKey, contentPaddingTrailingKey, listToTrayGapKey,
        historyPlacementKey, trayStyleKey, selectedRowStyleKey, railExtraWidthKey
    ]

    static func reset(defaults: UserDefaults = SidebarDialTuning.store) {
        for key in allKeys + [legacySelectedStyleKey] {
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
/// DEBUG-only: forces the sidebar's colour scheme (tray, pills, rows, and the
/// chrome behind them) to light or dark, so each glass set can be tuned
/// without changing the system appearance or the terminal theme. `auto`
/// follows the terminal theme, as a Release build always does. Held in
/// memory only: every launch starts at `auto` (a capture-fixture launch can
/// start elsewhere via `GHOSTTIES_CAPTURE_APPEARANCE`). Driven by the
/// inspector's "Preview appearance" control; `WorkspaceViewContainer`
/// applies it.
@MainActor
enum SidebarAppearancePreview {
    enum Mode: String, CaseIterable {
        case auto, light, dark
    }

    static let didChangeNotification = Notification.Name("ghostties.sidebarAppearancePreviewDidChange")

    private(set) static var mode: Mode = CaptureFixture.appearancePreview.flatMap(Mode.init(rawValue:)) ?? .auto

    static func set(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// The appearance to force, or nil to follow the terminal theme.
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
    var shadowOpacity: Double
    var shadowRadius: Double
    var shadowYOffset: Double
    var chromaticIntensity: Double
    var chromaticWidth: Double
    var chromaticRotation: Double
    var chromaticBlur: Double
    var chromaticPalette: String
    var chromaticBlend: String
    var specularStrength: Double
    var specularAngle: Double
    var selectedShadowOpacity: Double
    var selectedShadowRadius: Double
    var selectedShadowYOffset: Double

    init(_ look: TrayGlassStyle.Look) {
        variant = look.variant.rawValue
        tintOpacity = look.tintOpacity
        surfaceOpacity = look.surfaceOpacity
        rimWidth = Double(look.rimWidth)
        rimOpacity = look.rimOpacity
        shadowOpacity = look.shadowOpacity
        shadowRadius = Double(look.shadowRadius)
        shadowYOffset = Double(look.shadowYOffset)
        chromaticIntensity = look.chromaticIntensity
        chromaticWidth = Double(look.chromaticWidth)
        chromaticRotation = look.chromaticRotation
        chromaticBlur = Double(look.chromaticBlur)
        chromaticPalette = look.chromaticPalette.rawValue
        chromaticBlend = look.chromaticBlend.rawValue
        specularStrength = look.specularStrength
        specularAngle = look.specularAngle
        selectedShadowOpacity = look.selectedShadowOpacity
        selectedShadowRadius = Double(look.selectedShadowRadius)
        selectedShadowYOffset = Double(look.selectedShadowYOffset)
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
    var trayHorizontalButtonSize: Double
    var trayHorizontalIconSize: Double
    var trayVerticalButtonSize: Double
    var trayVerticalIconSize: Double
    var trayInnerPadding: Double
    var trayGroupGap: Double
    var trayWidth: String
    var trayGlassCornerStyle: String
    var trayGlassCornerRadius: Double
    var traySelectedPillWidth: Double
    var selectedTitleWeight: String

    var rowHeight: Double
    var rowGap: Double
    var rowTitleSize: Double
    var rowSubtitleSize: Double
    var rowGhostSize: Double
    var rowLeadingPadding: Double
    var rowTrailingPadding: Double


    var contentPaddingTop: Double
    var contentPaddingLeading: Double
    var contentPaddingTrailing: Double
    var listToTrayGap: Double
    var historyPlacement: String
    var trayStyle: String
    var selectedRowStyle: String

    var railExtraWidth: Double
}

@available(macOS 14, *)
@MainActor
final class SidebarDialKitCoordinator: ObservableObject {
    let state: DialPanelState<SidebarDialKitTuningModel>
    private var cancellable: AnyCancellable?
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
            name: "Sidebar Tuning",
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
        selfBox.coordinator = self
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
        let freshModel = Self.readModel(defaults: defaults)
        lastKnownModel = freshModel
        state.values = freshModel
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
            trayHorizontalButtonSize: Double(SidebarDialTuning.trayHorizontalButtonSize(defaults: defaults)),
            trayHorizontalIconSize: Double(SidebarDialTuning.trayHorizontalIconSize(defaults: defaults)),
            trayVerticalButtonSize: Double(SidebarDialTuning.trayVerticalButtonSize(defaults: defaults)),
            trayVerticalIconSize: Double(SidebarDialTuning.trayVerticalIconSize(defaults: defaults)),
            trayInnerPadding: Double(SidebarDialTuning.trayInnerPadding(defaults: defaults)),
            trayGroupGap: Double(SidebarDialTuning.trayGroupGap(defaults: defaults)),
            trayWidth: SidebarDialTuning.trayWidth(defaults: defaults).rawValue,
            trayGlassCornerStyle: SidebarDialTuning.trayGlassCornerStyle(defaults: defaults).rawValue,
            trayGlassCornerRadius: Double(SidebarDialTuning.trayGlassCornerRadius(defaults: defaults)),
            traySelectedPillWidth: Double(SidebarDialTuning.traySelectedPillWidth(defaults: defaults)),
            selectedTitleWeight: SidebarDialTuning.selectedTitleWeight(defaults: defaults).rawValue,
            rowHeight: Double(SidebarDialTuning.rowHeight(defaults: defaults)),
            rowGap: Double(SidebarDialTuning.rowGap(defaults: defaults)),
            rowTitleSize: Double(SidebarDialTuning.rowTitleSize(defaults: defaults)),
            rowSubtitleSize: Double(SidebarDialTuning.rowSubtitleSize(defaults: defaults)),
            rowGhostSize: Double(SidebarDialTuning.rowGhostSize(defaults: defaults)),
            rowLeadingPadding: Double(SidebarDialTuning.rowLeadingPadding(defaults: defaults)),
            rowTrailingPadding: Double(SidebarDialTuning.rowTrailingPadding(defaults: defaults)),
            contentPaddingTop: Double(SidebarDialTuning.contentPaddingTop(defaults: defaults)),
            contentPaddingLeading: Double(SidebarDialTuning.contentPaddingLeading(defaults: defaults)),
            contentPaddingTrailing: Double(SidebarDialTuning.contentPaddingTrailing(defaults: defaults)),
            listToTrayGap: Double(SidebarDialTuning.listToTrayGap(defaults: defaults)),
            historyPlacement: SidebarDialTuning.historyPlacement(defaults: defaults).rawValue,
            trayStyle: SidebarDialTuning.trayStyle(defaults: defaults).rawValue,
            selectedRowStyle: SidebarDialTuning.selectedRowStyle(defaults: defaults).rawValue,
            railExtraWidth: Double(SidebarDialTuning.railExtraWidth(defaults: defaults))
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
            setIfChanged(keys.shadowOpacity, old.shadowOpacity, new.shadowOpacity)
            setIfChanged(keys.shadowRadius, old.shadowRadius, new.shadowRadius)
            setIfChanged(keys.shadowYOffset, old.shadowYOffset, new.shadowYOffset)
            setIfChanged(keys.chromaticIntensity, old.chromaticIntensity, new.chromaticIntensity)
            setIfChanged(keys.chromaticWidth, old.chromaticWidth, new.chromaticWidth)
            setIfChanged(keys.chromaticRotation, old.chromaticRotation, new.chromaticRotation)
            setIfChanged(keys.chromaticBlur, old.chromaticBlur, new.chromaticBlur)
            setStringIfChanged(keys.chromaticPalette, old.chromaticPalette, new.chromaticPalette)
            setStringIfChanged(keys.chromaticBlend, old.chromaticBlend, new.chromaticBlend)
            setIfChanged(keys.specularStrength, old.specularStrength, new.specularStrength)
            setIfChanged(keys.specularAngle, old.specularAngle, new.specularAngle)
            setIfChanged(keys.selectedShadowOpacity, old.selectedShadowOpacity, new.selectedShadowOpacity)
            setIfChanged(keys.selectedShadowRadius, old.selectedShadowRadius, new.selectedShadowRadius)
            setIfChanged(keys.selectedShadowYOffset, old.selectedShadowYOffset, new.selectedShadowYOffset)
        }
        setBoolIfChanged(SidebarDialTuning.redlinesKey, previous.redlines, model.redlines)
        setIfChanged(SidebarDialTuning.windowMarginKey, previous.windowMargin, model.windowMargin)
        writeGlass(SidebarDialTuning.lightGlassKeys, previous.glassLight, model.glassLight)
        writeGlass(SidebarDialTuning.darkGlassKeys, previous.glassDark, model.glassDark)
        setBoolIfChanged(SidebarDialTuning.trayGlassInteractiveKey, previous.trayGlassInteractive, model.trayGlassInteractive)
        setIfChanged(SidebarDialTuning.trayHorizontalButtonSizeKey, previous.trayHorizontalButtonSize, model.trayHorizontalButtonSize)
        setIfChanged(SidebarDialTuning.trayHorizontalIconSizeKey, previous.trayHorizontalIconSize, model.trayHorizontalIconSize)
        setIfChanged(SidebarDialTuning.trayVerticalButtonSizeKey, previous.trayVerticalButtonSize, model.trayVerticalButtonSize)
        setIfChanged(SidebarDialTuning.trayVerticalIconSizeKey, previous.trayVerticalIconSize, model.trayVerticalIconSize)
        setIfChanged(SidebarDialTuning.trayInnerPaddingKey, previous.trayInnerPadding, model.trayInnerPadding)
        setIfChanged(SidebarDialTuning.trayGroupGapKey, previous.trayGroupGap, model.trayGroupGap)
        setStringIfChanged(SidebarDialTuning.trayWidthKey, previous.trayWidth, model.trayWidth)
        setStringIfChanged(SidebarDialTuning.trayGlassCornerStyleKey, previous.trayGlassCornerStyle, model.trayGlassCornerStyle)
        setIfChanged(SidebarDialTuning.trayGlassCornerRadiusKey, previous.trayGlassCornerRadius, model.trayGlassCornerRadius)
        setIfChanged(SidebarDialTuning.traySelectedPillWidthKey, previous.traySelectedPillWidth, model.traySelectedPillWidth)
        setStringIfChanged(SidebarDialTuning.selectedTitleWeightKey, previous.selectedTitleWeight, model.selectedTitleWeight)
        setIfChanged(SidebarDialTuning.rowHeightKey, previous.rowHeight, model.rowHeight)
        setIfChanged(SidebarDialTuning.rowGapKey, previous.rowGap, model.rowGap)
        setIfChanged(SidebarDialTuning.rowTitleSizeKey, previous.rowTitleSize, model.rowTitleSize)
        setIfChanged(SidebarDialTuning.rowSubtitleSizeKey, previous.rowSubtitleSize, model.rowSubtitleSize)
        setIfChanged(SidebarDialTuning.rowGhostSizeKey, previous.rowGhostSize, model.rowGhostSize)
        setIfChanged(SidebarDialTuning.rowLeadingPaddingKey, previous.rowLeadingPadding, model.rowLeadingPadding)
        setIfChanged(SidebarDialTuning.rowTrailingPaddingKey, previous.rowTrailingPadding, model.rowTrailingPadding)
        setIfChanged(SidebarDialTuning.contentPaddingTopKey, previous.contentPaddingTop, model.contentPaddingTop)
        setIfChanged(SidebarDialTuning.contentPaddingLeadingKey, previous.contentPaddingLeading, model.contentPaddingLeading)
        setIfChanged(SidebarDialTuning.contentPaddingTrailingKey, previous.contentPaddingTrailing, model.contentPaddingTrailing)
        setIfChanged(SidebarDialTuning.listToTrayGapKey, previous.listToTrayGap, model.listToTrayGap)
        setStringIfChanged(SidebarDialTuning.historyPlacementKey, previous.historyPlacement, model.historyPlacement)
        setStringIfChanged(SidebarDialTuning.trayStyleKey, previous.trayStyle, model.trayStyle)
        setStringIfChanged(SidebarDialTuning.selectedRowStyleKey, previous.selectedRowStyle, model.selectedRowStyle)
        setIfChanged(SidebarDialTuning.railExtraWidthKey, previous.railExtraWidth, model.railExtraWidth)
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
            .slider("\(prefix)RimWidth", keyPath: glass.appending(path: \.rimWidth), label: "Rim width", range: 0...4, step: 0.25, unit: "pt"),
            .slider("\(prefix)RimOpacity", keyPath: glass.appending(path: \.rimOpacity), label: "Rim opacity", range: 0...1, step: 0.02),
            .slider("\(prefix)ShadowOpacity", keyPath: glass.appending(path: \.shadowOpacity), label: "Shadow opacity", range: 0...0.6, step: 0.002),
            .slider("\(prefix)ShadowYOffset", keyPath: glass.appending(path: \.shadowYOffset), label: "Shadow Y", range: 0...16, step: 0.5, unit: "pt"),
            .slider("\(prefix)ShadowRadius", keyPath: glass.appending(path: \.shadowRadius), label: "Shadow radius", range: 0...32, step: 0.5, unit: "pt"),
            .slider("\(prefix)ChromaticIntensity", keyPath: glass.appending(path: \.chromaticIntensity), label: "Chromatic rim intensity", range: 0...1, step: 0.05),
            .slider("\(prefix)ChromaticWidth", keyPath: glass.appending(path: \.chromaticWidth), label: "Chromatic rim width", range: 0.5...6, step: 0.25, unit: "pt"),
            .slider("\(prefix)ChromaticRotation", keyPath: glass.appending(path: \.chromaticRotation), label: "Chromatic rim rotation", range: 0...360, step: 0.1, unit: "°"),
            .slider("\(prefix)ChromaticBlur", keyPath: glass.appending(path: \.chromaticBlur), label: "Chromatic rim blur", range: 0...3, step: 0.1, unit: "pt"),
            .select("\(prefix)ChromaticPalette", keyPath: glass.appending(path: \.chromaticPalette), label: "Chromatic palette",
                    options: TrayGlassStyle.ChromaticPalette.allCases.map(\.rawValue)),
            .select("\(prefix)ChromaticBlend", keyPath: glass.appending(path: \.chromaticBlend), label: "Chromatic blend",
                    options: TrayGlassStyle.ChromaticBlend.allCases.map(\.rawValue)),
            .slider("\(prefix)SpecularStrength", keyPath: glass.appending(path: \.specularStrength), label: "Specular strength", range: 0...1, step: 0.05),
            .slider("\(prefix)SpecularAngle", keyPath: glass.appending(path: \.specularAngle), label: "Specular angle", range: 0...360, step: 1, unit: "°"),
            .slider("\(prefix)SelectedShadowOpacity", keyPath: glass.appending(path: \.selectedShadowOpacity), label: "Selected shadow opacity (flat)", range: 0...0.6, step: 0.002),
            .slider("\(prefix)SelectedShadowRadius", keyPath: glass.appending(path: \.selectedShadowRadius), label: "Selected shadow radius (flat)", range: 0...32, step: 0.5, unit: "pt"),
            .slider("\(prefix)SelectedShadowYOffset", keyPath: glass.appending(path: \.selectedShadowYOffset), label: "Selected shadow Y (flat)", range: 0...16, step: 0.5, unit: "pt")
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
        // tray on both axes plus the selected session row (rail pill and
        // expanded row, `SidebarSelectedSurface`).
        .group("glassLight", label: "Glass — Light", children: glassControls("light", \.glassLight)),
        .group("glassDark", label: "Glass — Dark", children: glassControls("dark", \.glassDark)),
        // Shape and behaviour, shared by both appearances.
        .group("trayGlass", label: "Tray — shared", children: [
            .select("selectedTitleWeight", keyPath: \.selectedTitleWeight, label: "Selected title weight (expanded)",
                    options: TrayGlassStyle.SelectedTitleWeight.allCases.map(\.rawValue)),
            .toggle("trayGlassInteractive", keyPath: \.trayGlassInteractive, label: "Glass interactive (tray)"),
            .slider("trayHorizontalButtonSize", keyPath: \.trayHorizontalButtonSize, label: "Bar button size (expanded)", range: 24...56, step: 0.5, unit: "pt"),
            .slider("trayHorizontalIconSize", keyPath: \.trayHorizontalIconSize, label: "Bar icon size (expanded)", range: 10...24, step: 0.5, unit: "pt"),
            .select("trayWidth", keyPath: \.trayWidth, label: "Tray width",
                    options: TrayGlassStyle.TrayWidth.allCases.map(\.rawValue)),
            .slider("trayVerticalButtonSize", keyPath: \.trayVerticalButtonSize, label: "Pill button size (rail)", range: 24...56, step: 0.5, unit: "pt"),
            .slider("trayVerticalIconSize", keyPath: \.trayVerticalIconSize, label: "Pill icon size (rail)", range: 10...24, step: 0.5, unit: "pt"),
            .slider("trayInnerPadding", keyPath: \.trayInnerPadding, label: "Inner padding", range: 0...16, step: 0.5, unit: "pt"),
            .slider("trayGroupGap", keyPath: \.trayGroupGap, label: "Tray group gap", range: 0...16, step: 0.5, unit: "pt"),
            .select("trayGlassCornerStyle", keyPath: \.trayGlassCornerStyle, label: "Corner style",
                    options: TrayGlassStyle.CornerStyle.allCases.map(\.rawValue)),
            .slider("trayGlassCornerRadius", keyPath: \.trayGlassCornerRadius, label: "Corner radius (radius style)", range: 0...32, step: 0.5, unit: "pt"),
            .slider("traySelectedPillWidth", keyPath: \.traySelectedPillWidth, label: "Hairline width (rail)", range: 24...96, step: 0.5, unit: "pt"),
        ]),
        // Rows
        .slider("rowHeight", keyPath: \.rowHeight, label: "Row height", range: 32...64, unit: "pt"),
        .slider("rowGap", keyPath: \.rowGap, label: "Row gap", range: 0...12, unit: "pt"),
        .slider("rowTitleSize", keyPath: \.rowTitleSize, label: "Row title size", range: 9...16, unit: "pt"),
        .slider("rowSubtitleSize", keyPath: \.rowSubtitleSize, label: "Row subtitle size", range: 8...14, unit: "pt"),
        .slider("rowGhostSize", keyPath: \.rowGhostSize, label: "Row ghost size", range: 8...24, unit: "pt"),
        .slider("rowLeadingPadding", keyPath: \.rowLeadingPadding, label: "Row leading padding", range: 0...24, unit: "pt"),
        .slider("rowTrailingPadding", keyPath: \.rowTrailingPadding, label: "Row trailing padding", range: 0...24, unit: "pt"),
        // Sidebar layout. Window margin is every outer gutter; the content
        // paddings below are inner spacing inside it.
        .slider("windowMargin", keyPath: \.windowMargin, label: "Window margin", range: 0...32, unit: "pt"),
        .slider("contentPaddingTop", keyPath: \.contentPaddingTop, label: "Content padding top", range: 0...24, unit: "pt"),
        .slider("contentPaddingLeading", keyPath: \.contentPaddingLeading, label: "Content padding leading (inner)", range: 0...24, unit: "pt"),
        .slider("contentPaddingTrailing", keyPath: \.contentPaddingTrailing, label: "Content padding trailing (inner)", range: 0...24, unit: "pt"),
        .slider("listToTrayGap", keyPath: \.listToTrayGap, label: "List-to-tray gap", range: 0...24, unit: "pt"),
        .select("historyPlacement", keyPath: \.historyPlacement, label: "History placement",
                options: SidebarSessionSections.HistoryPlacement.allCases.map(\.rawValue)),
        .select("trayStyle", keyPath: \.trayStyle, label: "Tray style",
                options: TrayGlassStyle.TrayStyle.allCases.map(\.rawValue)),
        .select("selectedRowStyle", keyPath: \.selectedRowStyle, label: "Selected row",
                options: TrayGlassStyle.SelectedRowStyle.allCases.map(\.rawValue)),
        // Rail
        .slider("railExtraWidth", keyPath: \.railExtraWidth, label: "Rail extra width", range: 0...60, unit: "pt"),
        .action(resetActionPath, label: "Reset sidebar")
    ]
}

@available(macOS 14, *)
@MainActor
private final class SidebarDialKitCoordinatorBox {
    weak var coordinator: SidebarDialKitCoordinator?
}

/// DEBUG-only: owns the process-wide sidebar panel and starts the inspector
/// agent. Called once from `AppDelegate.applicationDidFinishLaunching`.
@available(macOS 14, *)
@MainActor
enum SidebarDialInspector {
    private static var coordinator: SidebarDialKitCoordinator?

    static func start() {
        guard coordinator == nil else { return }
        coordinator = SidebarDialKitCoordinator(
            defaults: SidebarDialTuning.store,
            // A row's `.equatable()` gate can't see a tuning change on its
            // own; poking the store re-renders the sidebar and tray.
            // AppKit geometry (the card's inset constraints) listens for
            // `didChangeNotification` instead.
            onChange: {
                WorkspaceStore.shared.objectWillChange.send()
                NotificationCenter.default.post(name: SidebarDialTuning.didChangeNotification, object: nil)
            }
        )
        DialKitAgent.shared.start(appName: "Ghostties")
    }
}
#endif
