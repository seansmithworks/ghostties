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
    // MARK: Tray glass (both axes + the selected session row; `TrayGlassStyle`)
    static let trayMarginKey = "ghostties.sidebarDial.trayMargin"
    static let trayInnerPaddingKey = "ghostties.sidebarDial.trayInnerPadding"
    /// Dark-mode warm tint opacity.
    static let trayTintOpacityKey = "ghostties.sidebarDial.trayTintOpacity"
    static let trayRimOpacityDarkKey = "ghostties.sidebarDial.trayRimOpacityDark"
    static let trayGlassVariantKey = "ghostties.sidebarDial.trayGlass.variant"
    static let trayGlassInteractiveKey = "ghostties.sidebarDial.trayGlass.interactive"
    static let trayGlassTintOpacityLightKey = "ghostties.sidebarDial.trayGlass.tintOpacityLight"
    static let trayGlassSurfaceOpacityKey = "ghostties.sidebarDial.trayGlass.surfaceOpacity"
    static let trayGlassRimWidthKey = "ghostties.sidebarDial.trayGlass.rimWidth"
    static let trayGlassRimOpacityLightKey = "ghostties.sidebarDial.trayGlass.rimOpacityLight"
    static let trayGlassShadowOpacityKey = "ghostties.sidebarDial.trayGlass.shadowOpacity"
    static let trayGlassShadowRadiusKey = "ghostties.sidebarDial.trayGlass.shadowRadius"
    static let trayGlassShadowYOffsetKey = "ghostties.sidebarDial.trayGlass.shadowYOffset"
    static let trayVerticalButtonSizeKey = "ghostties.sidebarDial.trayGlass.verticalButtonSize"
    static let trayVerticalIconSizeKey = "ghostties.sidebarDial.trayGlass.verticalIconSize"
    static let trayHorizontalButtonSizeKey = "ghostties.sidebarDial.trayGlass.horizontalButtonSize"
    static let trayHorizontalIconSizeKey = "ghostties.sidebarDial.trayGlass.horizontalIconSize"
    static let trayGlassCornerStyleKey = "ghostties.sidebarDial.trayGlass.cornerStyle"
    static let trayGlassCornerRadiusKey = "ghostties.sidebarDial.trayGlass.cornerRadius"
    static let traySelectedPillWidthKey = "ghostties.sidebarDial.trayGlass.selectedPillWidth"
    static let traySelectedPillHeightKey = "ghostties.sidebarDial.trayGlass.selectedPillHeight"
    static let trayChromaticIntensityKey = "ghostties.sidebarDial.trayGlass.chromaticIntensity"
    static let trayChromaticWidthKey = "ghostties.sidebarDial.trayGlass.chromaticWidth"
    static let trayChromaticRotationKey = "ghostties.sidebarDial.trayGlass.chromaticRotation"
    static let trayChromaticBlurKey = "ghostties.sidebarDial.trayGlass.chromaticBlur"
    static let trayChromaticPaletteKey = "ghostties.sidebarDial.trayGlass.chromaticPalette"
    static let trayChromaticBlendKey = "ghostties.sidebarDial.trayGlass.chromaticBlend"
    static let traySpecularStrengthKey = "ghostties.sidebarDial.trayGlass.specularStrength"
    static let traySpecularAngleKey = "ghostties.sidebarDial.trayGlass.specularAngle"

    // MARK: Rows (expanded)
    static let rowHeightKey = "ghostties.sidebarDial.rowHeight"
    static let rowGapKey = "ghostties.sidebarDial.rowGap"
    static let rowTitleSizeKey = "ghostties.sidebarDial.rowTitleSize"
    static let rowSubtitleSizeKey = "ghostties.sidebarDial.rowSubtitleSize"
    static let rowGhostSizeKey = "ghostties.sidebarDial.rowGhostSize"
    static let rowLeadingPaddingKey = "ghostties.sidebarDial.rowLeadingPadding"
    static let rowTrailingPaddingKey = "ghostties.sidebarDial.rowTrailingPadding"

    // MARK: Section headers
    static let headerTextSizeKey = "ghostties.sidebarDial.headerTextSize"
    static let headerTopPaddingKey = "ghostties.sidebarDial.headerTopPadding"
    static let headerBottomPaddingKey = "ghostties.sidebarDial.headerBottomPadding"
    static let headerChevronSizeKey = "ghostties.sidebarDial.headerChevronSize"

    // MARK: Sidebar layout
    static let contentPaddingTopKey = "ghostties.sidebarDial.contentPaddingTop"
    static let contentPaddingLeadingKey = "ghostties.sidebarDial.contentPaddingLeading"
    static let contentPaddingTrailingKey = "ghostties.sidebarDial.contentPaddingTrailing"
    static let listToTrayGapKey = "ghostties.sidebarDial.listToTrayGap"

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

    static func epoch(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: epochKey)
    }

    private static func cgFloat(_ key: String, default value: CGFloat, defaults: UserDefaults) -> CGFloat {
        let stored = defaults.object(forKey: key) as? Double
        return CGFloat(stored ?? Double(value))
    }

    private static func double(_ key: String, default value: Double, defaults: UserDefaults) -> Double {
        let stored = defaults.object(forKey: key) as? Double
        return stored ?? value
    }

    private static func bool(_ key: String, default value: Bool, defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? value
    }

    private static func choice<T: RawRepresentable>(_ key: String, default value: T, defaults: UserDefaults) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? value
    }

    /// Horizontal tray only: gap between the bar and the sidebar's edges.
    static func trayMargin(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayMarginKey, default: WorkspaceLayout.trayHorizontalMargin, defaults: defaults)
    }
    static func trayInnerPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayInnerPaddingKey, default: TrayGlassStyle.innerPadding, defaults: defaults)
    }
    static func trayTintOpacity(defaults: UserDefaults = .standard) -> Double {
        double(trayTintOpacityKey, default: TrayGlassStyle.tintOpacityDark, defaults: defaults)
    }
    static func trayRimOpacityDark(defaults: UserDefaults = .standard) -> Double {
        double(trayRimOpacityDarkKey, default: TrayGlassStyle.rimOpacityDark, defaults: defaults)
    }
    static func trayGlassVariant(defaults: UserDefaults = .standard) -> TrayGlassStyle.Variant {
        choice(trayGlassVariantKey, default: TrayGlassStyle.variant, defaults: defaults)
    }
    static func trayGlassInteractive(defaults: UserDefaults = .standard) -> Bool {
        bool(trayGlassInteractiveKey, default: TrayGlassStyle.interactive, defaults: defaults)
    }
    static func trayGlassTintOpacityLight(defaults: UserDefaults = .standard) -> Double {
        double(trayGlassTintOpacityLightKey, default: TrayGlassStyle.tintOpacityLight, defaults: defaults)
    }
    static func trayGlassSurfaceOpacity(defaults: UserDefaults = .standard) -> Double {
        double(trayGlassSurfaceOpacityKey, default: TrayGlassStyle.surfaceOpacity, defaults: defaults)
    }
    static func trayGlassRimWidth(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayGlassRimWidthKey, default: TrayGlassStyle.rimWidth, defaults: defaults)
    }
    static func trayGlassRimOpacityLight(defaults: UserDefaults = .standard) -> Double {
        double(trayGlassRimOpacityLightKey, default: TrayGlassStyle.rimOpacityLight, defaults: defaults)
    }
    static func trayGlassShadowOpacity(defaults: UserDefaults = .standard) -> Double {
        double(trayGlassShadowOpacityKey, default: TrayGlassStyle.shadowOpacity, defaults: defaults)
    }
    static func trayGlassShadowRadius(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayGlassShadowRadiusKey, default: TrayGlassStyle.shadowRadius, defaults: defaults)
    }
    static func trayGlassShadowYOffset(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayGlassShadowYOffsetKey, default: TrayGlassStyle.shadowYOffset, defaults: defaults)
    }
    static func trayVerticalButtonSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayVerticalButtonSizeKey, default: TrayGlassStyle.verticalButtonSize, defaults: defaults)
    }
    static func trayVerticalIconSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayVerticalIconSizeKey, default: TrayGlassStyle.verticalIconSize, defaults: defaults)
    }
    static func trayHorizontalButtonSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayHorizontalButtonSizeKey, default: TrayGlassStyle.horizontalButtonSize, defaults: defaults)
    }
    static func trayHorizontalIconSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayHorizontalIconSizeKey, default: TrayGlassStyle.horizontalIconSize, defaults: defaults)
    }
    static func trayGlassCornerStyle(defaults: UserDefaults = .standard) -> TrayGlassStyle.CornerStyle {
        choice(trayGlassCornerStyleKey, default: TrayGlassStyle.cornerStyle, defaults: defaults)
    }
    static func trayGlassCornerRadius(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayGlassCornerRadiusKey, default: TrayGlassStyle.cornerRadius, defaults: defaults)
    }
    static func traySelectedPillWidth(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(traySelectedPillWidthKey, default: TrayGlassStyle.selectedPillWidth, defaults: defaults)
    }
    static func traySelectedPillHeight(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(traySelectedPillHeightKey, default: TrayGlassStyle.selectedPillHeight, defaults: defaults)
    }
    static func trayChromaticIntensity(defaults: UserDefaults = .standard) -> Double {
        double(trayChromaticIntensityKey, default: TrayGlassStyle.chromaticIntensity, defaults: defaults)
    }
    static func trayChromaticWidth(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayChromaticWidthKey, default: TrayGlassStyle.chromaticWidth, defaults: defaults)
    }
    static func trayChromaticRotation(defaults: UserDefaults = .standard) -> Double {
        double(trayChromaticRotationKey, default: TrayGlassStyle.chromaticRotation, defaults: defaults)
    }
    static func trayChromaticBlur(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayChromaticBlurKey, default: TrayGlassStyle.chromaticBlur, defaults: defaults)
    }
    static func trayChromaticPalette(defaults: UserDefaults = .standard) -> TrayGlassStyle.ChromaticPalette {
        choice(trayChromaticPaletteKey, default: TrayGlassStyle.chromaticPalette, defaults: defaults)
    }
    static func trayChromaticBlend(defaults: UserDefaults = .standard) -> TrayGlassStyle.ChromaticBlend {
        choice(trayChromaticBlendKey, default: TrayGlassStyle.chromaticBlend, defaults: defaults)
    }
    static func traySpecularStrength(defaults: UserDefaults = .standard) -> Double {
        double(traySpecularStrengthKey, default: TrayGlassStyle.specularStrength, defaults: defaults)
    }
    static func traySpecularAngle(defaults: UserDefaults = .standard) -> Double {
        double(traySpecularAngleKey, default: TrayGlassStyle.specularAngle, defaults: defaults)
    }

    static func rowHeight(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowHeightKey, default: WorkspaceLayout.recentsRowHeight, defaults: defaults)
    }
    static func rowGap(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowGapKey, default: WorkspaceLayout.recentsRowGap, defaults: defaults)
    }
    static func rowTitleSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowTitleSizeKey, default: WorkspaceLayout.recentsRowTitleSize, defaults: defaults)
    }
    static func rowSubtitleSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowSubtitleSizeKey, default: WorkspaceLayout.recentsRowSubtitleSize, defaults: defaults)
    }
    static func rowGhostSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowGhostSizeKey, default: WorkspaceLayout.sessionGhostSize, defaults: defaults)
    }
    static func rowLeadingPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowLeadingPaddingKey, default: WorkspaceLayout.sidebarRowLeadingPadding, defaults: defaults)
    }
    static func rowTrailingPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(rowTrailingPaddingKey, default: WorkspaceLayout.recentsRowTrailingPadding, defaults: defaults)
    }

    static func headerTextSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(headerTextSizeKey, default: WorkspaceLayout.sessionSectionHeaderTextSize, defaults: defaults)
    }
    static func headerTopPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(headerTopPaddingKey, default: WorkspaceLayout.sessionSectionHeaderTopPadding, defaults: defaults)
    }
    static func headerBottomPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(headerBottomPaddingKey, default: WorkspaceLayout.sessionSectionHeaderBottomPadding, defaults: defaults)
    }
    static func headerChevronSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(headerChevronSizeKey, default: WorkspaceLayout.sessionSectionHeaderChevronSize, defaults: defaults)
    }

    static func contentPaddingTop(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(contentPaddingTopKey, default: WorkspaceLayout.sidebarContentPaddingTop, defaults: defaults)
    }
    static func contentPaddingLeading(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(contentPaddingLeadingKey, default: WorkspaceLayout.sidebarContentPaddingLeading, defaults: defaults)
    }
    static func contentPaddingTrailing(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(contentPaddingTrailingKey, default: WorkspaceLayout.sidebarContentPaddingTrailing, defaults: defaults)
    }
    /// The expanded list column's own trailing padding: the visible inset
    /// (`contentPaddingTrailing`) less the gutter already outside the column
    /// (`WorkspaceLayout.sidebarTrailingGutter`).
    static func contentColumnTrailingPadding(gutter: CGFloat, defaults: UserDefaults = .standard) -> CGFloat {
        max(0, contentPaddingTrailing(defaults: defaults) - gutter)
    }
    static func listToTrayGap(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(listToTrayGapKey, default: WorkspaceLayout.sidebarListToTrayGap, defaults: defaults)
    }

    /// Added on top of `WorkspaceLayout.collapsedRailWidth`'s computed hug
    /// width — see that function's own doc comment. Not folded into
    /// `WorkspaceLayout.railExtraWidth` (the compiled default both this and
    /// that function read) because the hug-width call sites are pure/testable
    /// functions that must not read `UserDefaults` directly.
    static func railExtraWidth(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railExtraWidthKey, default: WorkspaceLayout.railExtraWidth, defaults: defaults)
    }

    /// Every storage key this panel owns — used by `resetSidebar()` to clear
    /// back to code defaults in one pass, same shape as
    /// `ComposerSingleLineReset.resetKeys`.
    static let allKeys: [String] = [
        trayMarginKey, trayInnerPaddingKey, trayTintOpacityKey, trayRimOpacityDarkKey,
        trayGlassVariantKey, trayGlassInteractiveKey, trayGlassTintOpacityLightKey,
        trayGlassSurfaceOpacityKey, trayGlassRimWidthKey, trayGlassRimOpacityLightKey,
        trayGlassShadowOpacityKey, trayGlassShadowRadiusKey, trayGlassShadowYOffsetKey,
        trayVerticalButtonSizeKey, trayVerticalIconSizeKey, trayHorizontalButtonSizeKey,
        trayHorizontalIconSizeKey, trayGlassCornerStyleKey, trayGlassCornerRadiusKey,
        traySelectedPillWidthKey, traySelectedPillHeightKey,
        trayChromaticIntensityKey, trayChromaticWidthKey, trayChromaticRotationKey,
        trayChromaticBlurKey, trayChromaticPaletteKey, trayChromaticBlendKey,
        traySpecularStrengthKey, traySpecularAngleKey,
        rowHeightKey, rowGapKey, rowTitleSizeKey, rowSubtitleSizeKey, rowGhostSizeKey,
        rowLeadingPaddingKey, rowTrailingPaddingKey,
        headerTextSizeKey, headerTopPaddingKey, headerBottomPaddingKey, headerChevronSizeKey,
        contentPaddingTopKey, contentPaddingLeadingKey, contentPaddingTrailingKey, listToTrayGapKey,
        railExtraWidthKey
    ]

    static func reset(defaults: UserDefaults = .standard) {
        for key in allKeys {
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
@available(macOS 14, *)
struct SidebarDialKitTuningModel: Codable, Equatable {
    var trayGlassVariant: String
    var trayGlassInteractive: Bool
    var trayGlassTintOpacityLight: Double
    var trayTintOpacity: Double
    var trayGlassSurfaceOpacity: Double
    var trayGlassRimWidth: Double
    var trayGlassRimOpacityLight: Double
    var trayRimOpacityDark: Double
    var trayGlassShadowOpacity: Double
    var trayGlassShadowRadius: Double
    var trayGlassShadowYOffset: Double
    var trayHorizontalButtonSize: Double
    var trayHorizontalIconSize: Double
    var trayMargin: Double
    var trayVerticalButtonSize: Double
    var trayVerticalIconSize: Double
    var trayInnerPadding: Double
    var trayGlassCornerStyle: String
    var trayGlassCornerRadius: Double
    var traySelectedPillWidth: Double
    var traySelectedPillHeight: Double
    var trayChromaticIntensity: Double
    var trayChromaticWidth: Double
    var trayChromaticRotation: Double
    var trayChromaticBlur: Double
    var trayChromaticPalette: String
    var trayChromaticBlend: String
    var traySpecularStrength: Double
    var traySpecularAngle: Double

    var rowHeight: Double
    var rowGap: Double
    var rowTitleSize: Double
    var rowSubtitleSize: Double
    var rowGhostSize: Double
    var rowLeadingPadding: Double
    var rowTrailingPadding: Double

    var headerTextSize: Double
    var headerTopPadding: Double
    var headerBottomPadding: Double
    var headerChevronSize: Double

    var contentPaddingTop: Double
    var contentPaddingLeading: Double
    var contentPaddingTrailing: Double
    var listToTrayGap: Double

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
            trayGlassVariant: SidebarDialTuning.trayGlassVariant(defaults: defaults).rawValue,
            trayGlassInteractive: SidebarDialTuning.trayGlassInteractive(defaults: defaults),
            trayGlassTintOpacityLight: SidebarDialTuning.trayGlassTintOpacityLight(defaults: defaults),
            trayTintOpacity: SidebarDialTuning.trayTintOpacity(defaults: defaults),
            trayGlassSurfaceOpacity: SidebarDialTuning.trayGlassSurfaceOpacity(defaults: defaults),
            trayGlassRimWidth: Double(SidebarDialTuning.trayGlassRimWidth(defaults: defaults)),
            trayGlassRimOpacityLight: SidebarDialTuning.trayGlassRimOpacityLight(defaults: defaults),
            trayRimOpacityDark: SidebarDialTuning.trayRimOpacityDark(defaults: defaults),
            trayGlassShadowOpacity: SidebarDialTuning.trayGlassShadowOpacity(defaults: defaults),
            trayGlassShadowRadius: Double(SidebarDialTuning.trayGlassShadowRadius(defaults: defaults)),
            trayGlassShadowYOffset: Double(SidebarDialTuning.trayGlassShadowYOffset(defaults: defaults)),
            trayHorizontalButtonSize: Double(SidebarDialTuning.trayHorizontalButtonSize(defaults: defaults)),
            trayHorizontalIconSize: Double(SidebarDialTuning.trayHorizontalIconSize(defaults: defaults)),
            trayMargin: Double(SidebarDialTuning.trayMargin(defaults: defaults)),
            trayVerticalButtonSize: Double(SidebarDialTuning.trayVerticalButtonSize(defaults: defaults)),
            trayVerticalIconSize: Double(SidebarDialTuning.trayVerticalIconSize(defaults: defaults)),
            trayInnerPadding: Double(SidebarDialTuning.trayInnerPadding(defaults: defaults)),
            trayGlassCornerStyle: SidebarDialTuning.trayGlassCornerStyle(defaults: defaults).rawValue,
            trayGlassCornerRadius: Double(SidebarDialTuning.trayGlassCornerRadius(defaults: defaults)),
            traySelectedPillWidth: Double(SidebarDialTuning.traySelectedPillWidth(defaults: defaults)),
            traySelectedPillHeight: Double(SidebarDialTuning.traySelectedPillHeight(defaults: defaults)),
            trayChromaticIntensity: SidebarDialTuning.trayChromaticIntensity(defaults: defaults),
            trayChromaticWidth: Double(SidebarDialTuning.trayChromaticWidth(defaults: defaults)),
            trayChromaticRotation: SidebarDialTuning.trayChromaticRotation(defaults: defaults),
            trayChromaticBlur: Double(SidebarDialTuning.trayChromaticBlur(defaults: defaults)),
            trayChromaticPalette: SidebarDialTuning.trayChromaticPalette(defaults: defaults).rawValue,
            trayChromaticBlend: SidebarDialTuning.trayChromaticBlend(defaults: defaults).rawValue,
            traySpecularStrength: SidebarDialTuning.traySpecularStrength(defaults: defaults),
            traySpecularAngle: SidebarDialTuning.traySpecularAngle(defaults: defaults),
            rowHeight: Double(SidebarDialTuning.rowHeight(defaults: defaults)),
            rowGap: Double(SidebarDialTuning.rowGap(defaults: defaults)),
            rowTitleSize: Double(SidebarDialTuning.rowTitleSize(defaults: defaults)),
            rowSubtitleSize: Double(SidebarDialTuning.rowSubtitleSize(defaults: defaults)),
            rowGhostSize: Double(SidebarDialTuning.rowGhostSize(defaults: defaults)),
            rowLeadingPadding: Double(SidebarDialTuning.rowLeadingPadding(defaults: defaults)),
            rowTrailingPadding: Double(SidebarDialTuning.rowTrailingPadding(defaults: defaults)),
            headerTextSize: Double(SidebarDialTuning.headerTextSize(defaults: defaults)),
            headerTopPadding: Double(SidebarDialTuning.headerTopPadding(defaults: defaults)),
            headerBottomPadding: Double(SidebarDialTuning.headerBottomPadding(defaults: defaults)),
            headerChevronSize: Double(SidebarDialTuning.headerChevronSize(defaults: defaults)),
            contentPaddingTop: Double(SidebarDialTuning.contentPaddingTop(defaults: defaults)),
            contentPaddingLeading: Double(SidebarDialTuning.contentPaddingLeading(defaults: defaults)),
            contentPaddingTrailing: Double(SidebarDialTuning.contentPaddingTrailing(defaults: defaults)),
            listToTrayGap: Double(SidebarDialTuning.listToTrayGap(defaults: defaults)),
            railExtraWidth: Double(SidebarDialTuning.railExtraWidth(defaults: defaults))
        )
    }

    /// Diff-based, same rationale as `ComposerDialKitCoordinator.write` —
    /// only a field that actually moved between `previous`/`model` is
    /// persisted, so this panel never clobbers a key it didn't touch.
    private func write(from previous: SidebarDialKitTuningModel, to model: SidebarDialKitTuningModel) {
        guard previous != model else { return }
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
        setStringIfChanged(SidebarDialTuning.trayGlassVariantKey, previous.trayGlassVariant, model.trayGlassVariant)
        setBoolIfChanged(SidebarDialTuning.trayGlassInteractiveKey, previous.trayGlassInteractive, model.trayGlassInteractive)
        setIfChanged(SidebarDialTuning.trayGlassTintOpacityLightKey, previous.trayGlassTintOpacityLight, model.trayGlassTintOpacityLight)
        setIfChanged(SidebarDialTuning.trayTintOpacityKey, previous.trayTintOpacity, model.trayTintOpacity)
        setIfChanged(SidebarDialTuning.trayGlassSurfaceOpacityKey, previous.trayGlassSurfaceOpacity, model.trayGlassSurfaceOpacity)
        setIfChanged(SidebarDialTuning.trayGlassRimWidthKey, previous.trayGlassRimWidth, model.trayGlassRimWidth)
        setIfChanged(SidebarDialTuning.trayGlassRimOpacityLightKey, previous.trayGlassRimOpacityLight, model.trayGlassRimOpacityLight)
        setIfChanged(SidebarDialTuning.trayRimOpacityDarkKey, previous.trayRimOpacityDark, model.trayRimOpacityDark)
        setIfChanged(SidebarDialTuning.trayGlassShadowOpacityKey, previous.trayGlassShadowOpacity, model.trayGlassShadowOpacity)
        setIfChanged(SidebarDialTuning.trayGlassShadowRadiusKey, previous.trayGlassShadowRadius, model.trayGlassShadowRadius)
        setIfChanged(SidebarDialTuning.trayGlassShadowYOffsetKey, previous.trayGlassShadowYOffset, model.trayGlassShadowYOffset)
        setIfChanged(SidebarDialTuning.trayHorizontalButtonSizeKey, previous.trayHorizontalButtonSize, model.trayHorizontalButtonSize)
        setIfChanged(SidebarDialTuning.trayHorizontalIconSizeKey, previous.trayHorizontalIconSize, model.trayHorizontalIconSize)
        setIfChanged(SidebarDialTuning.trayMarginKey, previous.trayMargin, model.trayMargin)
        setIfChanged(SidebarDialTuning.trayVerticalButtonSizeKey, previous.trayVerticalButtonSize, model.trayVerticalButtonSize)
        setIfChanged(SidebarDialTuning.trayVerticalIconSizeKey, previous.trayVerticalIconSize, model.trayVerticalIconSize)
        setIfChanged(SidebarDialTuning.trayInnerPaddingKey, previous.trayInnerPadding, model.trayInnerPadding)
        setStringIfChanged(SidebarDialTuning.trayGlassCornerStyleKey, previous.trayGlassCornerStyle, model.trayGlassCornerStyle)
        setIfChanged(SidebarDialTuning.trayGlassCornerRadiusKey, previous.trayGlassCornerRadius, model.trayGlassCornerRadius)
        setIfChanged(SidebarDialTuning.traySelectedPillWidthKey, previous.traySelectedPillWidth, model.traySelectedPillWidth)
        setIfChanged(SidebarDialTuning.traySelectedPillHeightKey, previous.traySelectedPillHeight, model.traySelectedPillHeight)
        setIfChanged(SidebarDialTuning.trayChromaticIntensityKey, previous.trayChromaticIntensity, model.trayChromaticIntensity)
        setIfChanged(SidebarDialTuning.trayChromaticWidthKey, previous.trayChromaticWidth, model.trayChromaticWidth)
        setIfChanged(SidebarDialTuning.trayChromaticRotationKey, previous.trayChromaticRotation, model.trayChromaticRotation)
        setIfChanged(SidebarDialTuning.trayChromaticBlurKey, previous.trayChromaticBlur, model.trayChromaticBlur)
        setStringIfChanged(SidebarDialTuning.trayChromaticPaletteKey, previous.trayChromaticPalette, model.trayChromaticPalette)
        setStringIfChanged(SidebarDialTuning.trayChromaticBlendKey, previous.trayChromaticBlend, model.trayChromaticBlend)
        setIfChanged(SidebarDialTuning.traySpecularStrengthKey, previous.traySpecularStrength, model.traySpecularStrength)
        setIfChanged(SidebarDialTuning.traySpecularAngleKey, previous.traySpecularAngle, model.traySpecularAngle)
        setIfChanged(SidebarDialTuning.rowHeightKey, previous.rowHeight, model.rowHeight)
        setIfChanged(SidebarDialTuning.rowGapKey, previous.rowGap, model.rowGap)
        setIfChanged(SidebarDialTuning.rowTitleSizeKey, previous.rowTitleSize, model.rowTitleSize)
        setIfChanged(SidebarDialTuning.rowSubtitleSizeKey, previous.rowSubtitleSize, model.rowSubtitleSize)
        setIfChanged(SidebarDialTuning.rowGhostSizeKey, previous.rowGhostSize, model.rowGhostSize)
        setIfChanged(SidebarDialTuning.rowLeadingPaddingKey, previous.rowLeadingPadding, model.rowLeadingPadding)
        setIfChanged(SidebarDialTuning.rowTrailingPaddingKey, previous.rowTrailingPadding, model.rowTrailingPadding)
        setIfChanged(SidebarDialTuning.headerTextSizeKey, previous.headerTextSize, model.headerTextSize)
        setIfChanged(SidebarDialTuning.headerTopPaddingKey, previous.headerTopPadding, model.headerTopPadding)
        setIfChanged(SidebarDialTuning.headerBottomPaddingKey, previous.headerBottomPadding, model.headerBottomPadding)
        setIfChanged(SidebarDialTuning.headerChevronSizeKey, previous.headerChevronSize, model.headerChevronSize)
        setIfChanged(SidebarDialTuning.contentPaddingTopKey, previous.contentPaddingTop, model.contentPaddingTop)
        setIfChanged(SidebarDialTuning.contentPaddingLeadingKey, previous.contentPaddingLeading, model.contentPaddingLeading)
        setIfChanged(SidebarDialTuning.contentPaddingTrailingKey, previous.contentPaddingTrailing, model.contentPaddingTrailing)
        setIfChanged(SidebarDialTuning.listToTrayGapKey, previous.listToTrayGap, model.listToTrayGap)
        setIfChanged(SidebarDialTuning.railExtraWidthKey, previous.railExtraWidth, model.railExtraWidth)
        // Any write at all is a tuning change a row's `.equatable()` gate
        // can't see on its own — see `SidebarDialTuning.epochKey`'s doc
        // comment.
        defaults.set(SidebarDialTuning.epoch(defaults: defaults) + 1, forKey: SidebarDialTuning.epochKey)
        onChange()
    }

    private static let resetActionPath = "resetSidebar"

    private static let controls: [DialControl<SidebarDialKitTuningModel>] = [
        // Tray glass: the tray on both axes, plus the selected session row
        // (rail pill and expanded row, `SidebarSelectedSurface`).
        .group("trayGlass", label: "Tray glass", children: [
            .select("trayGlassVariant", keyPath: \.trayGlassVariant, label: "Glass variant",
                    options: TrayGlassStyle.Variant.allCases.map(\.rawValue)),
            .toggle("trayGlassInteractive", keyPath: \.trayGlassInteractive, label: "Glass interactive (tray)"),
            .slider("trayGlassTintOpacityLight", keyPath: \.trayGlassTintOpacityLight, label: "Glass white tint (light)", range: 0...1, step: 0.05),
            .slider("trayTintOpacity", keyPath: \.trayTintOpacity, label: "Glass warm tint (dark)", range: 0...1, step: 0.05),
            .slider("trayGlassSurfaceOpacity", keyPath: \.trayGlassSurfaceOpacity, label: "White layer opacity", range: 0...1, step: 0.05),
            .slider("trayGlassRimWidth", keyPath: \.trayGlassRimWidth, label: "Rim width", range: 0...4, step: 0.25, unit: "pt"),
            .slider("trayGlassRimOpacityLight", keyPath: \.trayGlassRimOpacityLight, label: "Rim opacity (light)", range: 0...1, step: 0.05),
            .slider("trayRimOpacityDark", keyPath: \.trayRimOpacityDark, label: "Rim opacity (dark)", range: 0...1, step: 0.02),
            .slider("trayGlassShadowOpacity", keyPath: \.trayGlassShadowOpacity, label: "Shadow opacity", range: 0...0.4, step: 0.002),
            .slider("trayGlassShadowYOffset", keyPath: \.trayGlassShadowYOffset, label: "Shadow Y", range: 0...16, step: 0.5, unit: "pt"),
            .slider("trayGlassShadowRadius", keyPath: \.trayGlassShadowRadius, label: "Shadow radius", range: 0...32, step: 0.5, unit: "pt"),
            .slider("trayHorizontalButtonSize", keyPath: \.trayHorizontalButtonSize, label: "Bar button height (expanded)", range: 24...56, step: 0.5, unit: "pt"),
            .slider("trayHorizontalIconSize", keyPath: \.trayHorizontalIconSize, label: "Bar icon size (expanded)", range: 10...24, step: 0.5, unit: "pt"),
            .slider("trayMargin", keyPath: \.trayMargin, label: "Bar side margin (expanded, visible)", range: 0...24, unit: "pt"),
            .slider("trayVerticalButtonSize", keyPath: \.trayVerticalButtonSize, label: "Pill button size (rail)", range: 24...56, step: 0.5, unit: "pt"),
            .slider("trayVerticalIconSize", keyPath: \.trayVerticalIconSize, label: "Pill icon size (rail)", range: 10...24, step: 0.5, unit: "pt"),
            .slider("trayInnerPadding", keyPath: \.trayInnerPadding, label: "Inner padding", range: 0...16, step: 0.5, unit: "pt"),
            .select("trayGlassCornerStyle", keyPath: \.trayGlassCornerStyle, label: "Corner style",
                    options: TrayGlassStyle.CornerStyle.allCases.map(\.rawValue)),
            .slider("trayGlassCornerRadius", keyPath: \.trayGlassCornerRadius, label: "Corner radius (radius style)", range: 0...32, step: 0.5, unit: "pt"),
            .slider("traySelectedPillWidth", keyPath: \.traySelectedPillWidth, label: "Selected pill width (rail)", range: 24...96, step: 0.5, unit: "pt"),
            .slider("traySelectedPillHeight", keyPath: \.traySelectedPillHeight, label: "Selected pill height (rail)", range: 20...64, step: 0.5, unit: "pt"),
            .slider("trayChromaticIntensity", keyPath: \.trayChromaticIntensity, label: "Chromatic rim intensity (light)", range: 0...1, step: 0.05),
            .slider("trayChromaticWidth", keyPath: \.trayChromaticWidth, label: "Chromatic rim width", range: 0.5...6, step: 0.25, unit: "pt"),
            .slider("trayChromaticRotation", keyPath: \.trayChromaticRotation, label: "Chromatic rim rotation", range: 0...360, step: 0.1, unit: "°"),
            .slider("trayChromaticBlur", keyPath: \.trayChromaticBlur, label: "Chromatic rim blur", range: 0...3, step: 0.1, unit: "pt"),
            .select("trayChromaticPalette", keyPath: \.trayChromaticPalette, label: "Chromatic palette",
                    options: TrayGlassStyle.ChromaticPalette.allCases.map(\.rawValue)),
            .select("trayChromaticBlend", keyPath: \.trayChromaticBlend, label: "Chromatic blend",
                    options: TrayGlassStyle.ChromaticBlend.allCases.map(\.rawValue)),
            .slider("traySpecularStrength", keyPath: \.traySpecularStrength, label: "Specular strength", range: 0...1, step: 0.05),
            .slider("traySpecularAngle", keyPath: \.traySpecularAngle, label: "Specular angle", range: 0...360, step: 1, unit: "°")
        ]),
        // Rows
        .slider("rowHeight", keyPath: \.rowHeight, label: "Row height", range: 32...64, unit: "pt"),
        .slider("rowGap", keyPath: \.rowGap, label: "Row gap", range: 0...12, unit: "pt"),
        .slider("rowTitleSize", keyPath: \.rowTitleSize, label: "Row title size", range: 9...16, unit: "pt"),
        .slider("rowSubtitleSize", keyPath: \.rowSubtitleSize, label: "Row subtitle size", range: 8...14, unit: "pt"),
        .slider("rowGhostSize", keyPath: \.rowGhostSize, label: "Row ghost size", range: 8...24, unit: "pt"),
        .slider("rowLeadingPadding", keyPath: \.rowLeadingPadding, label: "Row leading padding", range: 0...24, unit: "pt"),
        .slider("rowTrailingPadding", keyPath: \.rowTrailingPadding, label: "Row trailing padding", range: 0...24, unit: "pt"),
        // Section headers
        .slider("headerTextSize", keyPath: \.headerTextSize, label: "Header text size", range: 8...16, unit: "pt"),
        .slider("headerTopPadding", keyPath: \.headerTopPadding, label: "Header top padding", range: 0...20, unit: "pt"),
        .slider("headerBottomPadding", keyPath: \.headerBottomPadding, label: "Header bottom padding", range: 0...20, unit: "pt"),
        .slider("headerChevronSize", keyPath: \.headerChevronSize, label: "Header chevron size", range: 8...24, unit: "pt"),
        // Sidebar layout
        .slider("contentPaddingTop", keyPath: \.contentPaddingTop, label: "Content padding top", range: 0...24, unit: "pt"),
        .slider("contentPaddingLeading", keyPath: \.contentPaddingLeading, label: "Content padding leading", range: 0...24, unit: "pt"),
        .slider("contentPaddingTrailing", keyPath: \.contentPaddingTrailing, label: "Content padding trailing (visible)", range: 0...24, unit: "pt"),
        .slider("listToTrayGap", keyPath: \.listToTrayGap, label: "List-to-tray gap", range: 0...24, unit: "pt"),
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
            defaults: .standard,
            // A row's `.equatable()` gate can't see a tuning change on its
            // own; poking the store re-renders the sidebar and tray.
            onChange: { WorkspaceStore.shared.objectWillChange.send() }
        )
        DialKitAgent.shared.start(appName: "Ghostties")
    }
}
#endif
