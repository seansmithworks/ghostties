import SwiftUI
import AppKit
#if DEBUG
import Combine
import DialKit
#endif

// MARK: - Sidebar DialKit tunables (session-8 brief, sidebar-presence)
//
// Mirrors `ComposerSingleLineTuning`'s pattern in `ComposerSingleLineStyle.swift`
// exactly: one `enum` of `UserDefaults`-backed accessors, compiled in every
// configuration (not `#if DEBUG`). Each accessor falls back to the shipped
// `WorkspaceLayout`/`TrayGlassStyle` constant when its key is unset — a
// Release build (or a Dev build nobody has ever opened the panel in) reads
// exactly that constant, byte-for-byte. The DialKit panel UI itself (below)
// IS `#if DEBUG`-gated; these accessors are not DialKit — they're the same
// "read a UserDefaults double, else the code default" shape every other
// dial in this app already uses, so a Release binary staying dial-free is
// really "nobody ever wrote these keys," not a compiled-out code path.
enum SidebarDialTuning {
    // MARK: Tray
    static let trayIconSizeKey = "ghostties.sidebarDial.trayIconSize"
    static let trayButtonSizeKey = "ghostties.sidebarDial.trayButtonSize"
    static let trayMarginKey = "ghostties.sidebarDial.trayMargin"
    static let trayInnerPaddingKey = "ghostties.sidebarDial.trayInnerPadding"
    static let trayTintOpacityKey = "ghostties.sidebarDial.trayTintOpacity"
    static let trayRimOpacityLightKey = "ghostties.sidebarDial.trayRimOpacityLight"
    static let trayRimOpacityDarkKey = "ghostties.sidebarDial.trayRimOpacityDark"

    // MARK: Rows (expanded) + the selected-card treatment shared by rows/tray/rail
    static let rowHeightKey = "ghostties.sidebarDial.rowHeight"
    static let rowGapKey = "ghostties.sidebarDial.rowGap"
    static let rowTitleSizeKey = "ghostties.sidebarDial.rowTitleSize"
    static let rowSubtitleSizeKey = "ghostties.sidebarDial.rowSubtitleSize"
    static let rowGhostSizeKey = "ghostties.sidebarDial.rowGhostSize"
    static let rowLeadingPaddingKey = "ghostties.sidebarDial.rowLeadingPadding"
    static let rowTrailingPaddingKey = "ghostties.sidebarDial.rowTrailingPadding"
    static let selectedCardCornerRadiusKey = "ghostties.sidebarDial.selectedCardCornerRadius"
    static let selectedCardShadowOpacityKey = "ghostties.sidebarDial.selectedCardShadowOpacity"
    static let selectedCardShadowRadiusKey = "ghostties.sidebarDial.selectedCardShadowRadius"
    static let selectedCardShadowYOffsetKey = "ghostties.sidebarDial.selectedCardShadowYOffset"

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
    static let railGhostSizeKey = "ghostties.sidebarDial.railGhostSize"
    static let railRowWidthKey = "ghostties.sidebarDial.railRowWidth"
    static let railRowHeightKey = "ghostties.sidebarDial.railRowHeight"
    static let railRowGapKey = "ghostties.sidebarDial.railRowGap"
    static let railSummaryRowHeightKey = "ghostties.sidebarDial.railSummaryRowHeight"
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

    static func trayIconSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayIconSizeKey, default: TrayGlassStyle.iconSize, defaults: defaults)
    }
    static func trayButtonSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayButtonSizeKey, default: TrayGlassStyle.buttonSize, defaults: defaults)
    }
    static func trayMargin(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayMarginKey, default: WorkspaceLayout.trayHorizontalMargin, defaults: defaults)
    }
    static func trayInnerPadding(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(trayInnerPaddingKey, default: TrayGlassStyle.innerPadding, defaults: defaults)
    }
    static func trayTintOpacity(defaults: UserDefaults = .standard) -> Double {
        double(trayTintOpacityKey, default: TrayGlassStyle.tintOpacity, defaults: defaults)
    }
    static func trayRimOpacityLight(defaults: UserDefaults = .standard) -> Double {
        double(trayRimOpacityLightKey, default: TrayGlassStyle.rimOpacityLight, defaults: defaults)
    }
    static func trayRimOpacityDark(defaults: UserDefaults = .standard) -> Double {
        double(trayRimOpacityDarkKey, default: TrayGlassStyle.rimOpacityDark, defaults: defaults)
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
    /// Shared by the selected session/rail row card AND the tray pill shape
    /// (`WorkspaceLayout.selectedRowCornerRadius` — already one constant for
    /// both in code; this dial keeps that sharing, it doesn't split it).
    static func selectedCardCornerRadius(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(selectedCardCornerRadiusKey, default: WorkspaceLayout.selectedRowCornerRadius, defaults: defaults)
    }
    static func selectedCardShadowOpacity(defaults: UserDefaults = .standard) -> Double {
        double(selectedCardShadowOpacityKey, default: WorkspaceLayout.selectedRowShadowOpacity, defaults: defaults)
    }
    static func selectedCardShadowRadius(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(selectedCardShadowRadiusKey, default: WorkspaceLayout.selectedRowShadowRadius, defaults: defaults)
    }
    static func selectedCardShadowYOffset(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(selectedCardShadowYOffsetKey, default: WorkspaceLayout.selectedRowShadowYOffset, defaults: defaults)
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
    static func listToTrayGap(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(listToTrayGapKey, default: WorkspaceLayout.sidebarListToTrayGap, defaults: defaults)
    }

    static func railGhostSize(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railGhostSizeKey, default: WorkspaceLayout.railGhostSize, defaults: defaults)
    }
    static func railRowWidth(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railRowWidthKey, default: WorkspaceLayout.railRowWidth, defaults: defaults)
    }
    static func railRowHeight(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railRowHeightKey, default: WorkspaceLayout.railRowHeight, defaults: defaults)
    }
    static func railRowGap(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railRowGapKey, default: WorkspaceLayout.railRowGap, defaults: defaults)
    }
    static func railSummaryRowHeight(defaults: UserDefaults = .standard) -> CGFloat {
        cgFloat(railSummaryRowHeightKey, default: WorkspaceLayout.railSummaryRowHeight, defaults: defaults)
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
        trayIconSizeKey, trayButtonSizeKey, trayMarginKey, trayInnerPaddingKey,
        trayTintOpacityKey, trayRimOpacityLightKey, trayRimOpacityDarkKey,
        rowHeightKey, rowGapKey, rowTitleSizeKey, rowSubtitleSizeKey, rowGhostSizeKey,
        rowLeadingPaddingKey, rowTrailingPaddingKey, selectedCardCornerRadiusKey,
        selectedCardShadowOpacityKey, selectedCardShadowRadiusKey, selectedCardShadowYOffsetKey,
        headerTextSizeKey, headerTopPaddingKey, headerBottomPaddingKey, headerChevronSizeKey,
        contentPaddingTopKey, contentPaddingLeadingKey, contentPaddingTrailingKey, listToTrayGapKey,
        railGhostSizeKey, railRowWidthKey, railRowHeightKey, railRowGapKey,
        railSummaryRowHeightKey, railExtraWidthKey
    ]

    static func reset(defaults: UserDefaults = .standard) {
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(epoch(defaults: defaults) + 1, forKey: epochKey)
    }
}

// MARK: - DialKit panel (macOS 14+, DEBUG only)
//
// Session-8 brief: "add dial kit for the sidebar... so Sean can tune sizes
// and spacing live in the Dev build, then Copy the values back into code."
// Mirrors `ComposerDialKitCoordinator`/`ComposerDialKitHost` in
// `ComposerSingleLineStyle.swift` exactly — same `DialPanelState` ownership,
// same diff-based `write(from:to:)`, same `.inline` hosting in our own card,
// same Reset-as-`.action`-control shape. Unlike the composer panel, the
// sidebar has no Style switch that swaps the control list, so there is no
// `configure(controls:)` re-invocation and no re-entrancy guard to carry
// over — `controls` is a single static list, set once at construction.
//
// No macOS-13 legacy-slider fallback: the composer's fallback exists only
// because round 12's sliders shipped before round 13 added DialKit and had
// to keep working on the floor OS. This panel is new; macOS 13 users simply
// don't get a tuning UI (every dial still has a working `defaults write`
// escape hatch via `SidebarDialTuning`, matching every other knob in this
// file), which is a reasonable floor for a Dev-only diagnostic tool.
#if DEBUG
@available(macOS 14, *)
struct SidebarDialKitTuningModel: Codable, Equatable {
    var trayIconSize: Double
    var trayButtonSize: Double
    var trayMargin: Double
    var trayInnerPadding: Double
    var trayTintOpacity: Double
    var trayRimOpacityLight: Double
    var trayRimOpacityDark: Double

    var rowHeight: Double
    var rowGap: Double
    var rowTitleSize: Double
    var rowSubtitleSize: Double
    var rowGhostSize: Double
    var rowLeadingPadding: Double
    var rowTrailingPadding: Double
    var selectedCardCornerRadius: Double
    var selectedCardShadowOpacity: Double
    var selectedCardShadowRadius: Double
    var selectedCardShadowYOffset: Double

    var headerTextSize: Double
    var headerTopPadding: Double
    var headerBottomPadding: Double
    var headerChevronSize: Double

    var contentPaddingTop: Double
    var contentPaddingLeading: Double
    var contentPaddingTrailing: Double
    var listToTrayGap: Double

    var railGhostSize: Double
    var railRowWidth: Double
    var railRowHeight: Double
    var railRowGap: Double
    var railSummaryRowHeight: Double
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
            trayIconSize: Double(SidebarDialTuning.trayIconSize(defaults: defaults)),
            trayButtonSize: Double(SidebarDialTuning.trayButtonSize(defaults: defaults)),
            trayMargin: Double(SidebarDialTuning.trayMargin(defaults: defaults)),
            trayInnerPadding: Double(SidebarDialTuning.trayInnerPadding(defaults: defaults)),
            trayTintOpacity: SidebarDialTuning.trayTintOpacity(defaults: defaults),
            trayRimOpacityLight: SidebarDialTuning.trayRimOpacityLight(defaults: defaults),
            trayRimOpacityDark: SidebarDialTuning.trayRimOpacityDark(defaults: defaults),
            rowHeight: Double(SidebarDialTuning.rowHeight(defaults: defaults)),
            rowGap: Double(SidebarDialTuning.rowGap(defaults: defaults)),
            rowTitleSize: Double(SidebarDialTuning.rowTitleSize(defaults: defaults)),
            rowSubtitleSize: Double(SidebarDialTuning.rowSubtitleSize(defaults: defaults)),
            rowGhostSize: Double(SidebarDialTuning.rowGhostSize(defaults: defaults)),
            rowLeadingPadding: Double(SidebarDialTuning.rowLeadingPadding(defaults: defaults)),
            rowTrailingPadding: Double(SidebarDialTuning.rowTrailingPadding(defaults: defaults)),
            selectedCardCornerRadius: Double(SidebarDialTuning.selectedCardCornerRadius(defaults: defaults)),
            selectedCardShadowOpacity: SidebarDialTuning.selectedCardShadowOpacity(defaults: defaults),
            selectedCardShadowRadius: Double(SidebarDialTuning.selectedCardShadowRadius(defaults: defaults)),
            selectedCardShadowYOffset: Double(SidebarDialTuning.selectedCardShadowYOffset(defaults: defaults)),
            headerTextSize: Double(SidebarDialTuning.headerTextSize(defaults: defaults)),
            headerTopPadding: Double(SidebarDialTuning.headerTopPadding(defaults: defaults)),
            headerBottomPadding: Double(SidebarDialTuning.headerBottomPadding(defaults: defaults)),
            headerChevronSize: Double(SidebarDialTuning.headerChevronSize(defaults: defaults)),
            contentPaddingTop: Double(SidebarDialTuning.contentPaddingTop(defaults: defaults)),
            contentPaddingLeading: Double(SidebarDialTuning.contentPaddingLeading(defaults: defaults)),
            contentPaddingTrailing: Double(SidebarDialTuning.contentPaddingTrailing(defaults: defaults)),
            listToTrayGap: Double(SidebarDialTuning.listToTrayGap(defaults: defaults)),
            railGhostSize: Double(SidebarDialTuning.railGhostSize(defaults: defaults)),
            railRowWidth: Double(SidebarDialTuning.railRowWidth(defaults: defaults)),
            railRowHeight: Double(SidebarDialTuning.railRowHeight(defaults: defaults)),
            railRowGap: Double(SidebarDialTuning.railRowGap(defaults: defaults)),
            railSummaryRowHeight: Double(SidebarDialTuning.railSummaryRowHeight(defaults: defaults)),
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
        setIfChanged(SidebarDialTuning.trayIconSizeKey, previous.trayIconSize, model.trayIconSize)
        setIfChanged(SidebarDialTuning.trayButtonSizeKey, previous.trayButtonSize, model.trayButtonSize)
        setIfChanged(SidebarDialTuning.trayMarginKey, previous.trayMargin, model.trayMargin)
        setIfChanged(SidebarDialTuning.trayInnerPaddingKey, previous.trayInnerPadding, model.trayInnerPadding)
        setIfChanged(SidebarDialTuning.trayTintOpacityKey, previous.trayTintOpacity, model.trayTintOpacity)
        setIfChanged(SidebarDialTuning.trayRimOpacityLightKey, previous.trayRimOpacityLight, model.trayRimOpacityLight)
        setIfChanged(SidebarDialTuning.trayRimOpacityDarkKey, previous.trayRimOpacityDark, model.trayRimOpacityDark)
        setIfChanged(SidebarDialTuning.rowHeightKey, previous.rowHeight, model.rowHeight)
        setIfChanged(SidebarDialTuning.rowGapKey, previous.rowGap, model.rowGap)
        setIfChanged(SidebarDialTuning.rowTitleSizeKey, previous.rowTitleSize, model.rowTitleSize)
        setIfChanged(SidebarDialTuning.rowSubtitleSizeKey, previous.rowSubtitleSize, model.rowSubtitleSize)
        setIfChanged(SidebarDialTuning.rowGhostSizeKey, previous.rowGhostSize, model.rowGhostSize)
        setIfChanged(SidebarDialTuning.rowLeadingPaddingKey, previous.rowLeadingPadding, model.rowLeadingPadding)
        setIfChanged(SidebarDialTuning.rowTrailingPaddingKey, previous.rowTrailingPadding, model.rowTrailingPadding)
        setIfChanged(SidebarDialTuning.selectedCardCornerRadiusKey, previous.selectedCardCornerRadius, model.selectedCardCornerRadius)
        setIfChanged(SidebarDialTuning.selectedCardShadowOpacityKey, previous.selectedCardShadowOpacity, model.selectedCardShadowOpacity)
        setIfChanged(SidebarDialTuning.selectedCardShadowRadiusKey, previous.selectedCardShadowRadius, model.selectedCardShadowRadius)
        setIfChanged(SidebarDialTuning.selectedCardShadowYOffsetKey, previous.selectedCardShadowYOffset, model.selectedCardShadowYOffset)
        setIfChanged(SidebarDialTuning.headerTextSizeKey, previous.headerTextSize, model.headerTextSize)
        setIfChanged(SidebarDialTuning.headerTopPaddingKey, previous.headerTopPadding, model.headerTopPadding)
        setIfChanged(SidebarDialTuning.headerBottomPaddingKey, previous.headerBottomPadding, model.headerBottomPadding)
        setIfChanged(SidebarDialTuning.headerChevronSizeKey, previous.headerChevronSize, model.headerChevronSize)
        setIfChanged(SidebarDialTuning.contentPaddingTopKey, previous.contentPaddingTop, model.contentPaddingTop)
        setIfChanged(SidebarDialTuning.contentPaddingLeadingKey, previous.contentPaddingLeading, model.contentPaddingLeading)
        setIfChanged(SidebarDialTuning.contentPaddingTrailingKey, previous.contentPaddingTrailing, model.contentPaddingTrailing)
        setIfChanged(SidebarDialTuning.listToTrayGapKey, previous.listToTrayGap, model.listToTrayGap)
        setIfChanged(SidebarDialTuning.railGhostSizeKey, previous.railGhostSize, model.railGhostSize)
        setIfChanged(SidebarDialTuning.railRowWidthKey, previous.railRowWidth, model.railRowWidth)
        setIfChanged(SidebarDialTuning.railRowHeightKey, previous.railRowHeight, model.railRowHeight)
        setIfChanged(SidebarDialTuning.railRowGapKey, previous.railRowGap, model.railRowGap)
        setIfChanged(SidebarDialTuning.railSummaryRowHeightKey, previous.railSummaryRowHeight, model.railSummaryRowHeight)
        setIfChanged(SidebarDialTuning.railExtraWidthKey, previous.railExtraWidth, model.railExtraWidth)
        // Any write at all is a tuning change a row's `.equatable()` gate
        // can't see on its own — see `SidebarDialTuning.epochKey`'s doc
        // comment.
        defaults.set(SidebarDialTuning.epoch(defaults: defaults) + 1, forKey: SidebarDialTuning.epochKey)
        onChange()
    }

    private static let resetActionPath = "resetSidebar"

    private static let controls: [DialControl<SidebarDialKitTuningModel>] = [
        // Tray
        .slider("trayIconSize", keyPath: \.trayIconSize, label: "Tray icon size", range: 10...24, unit: "pt"),
        .slider("trayButtonSize", keyPath: \.trayButtonSize, label: "Tray button size", range: 24...48, unit: "pt"),
        .slider("trayMargin", keyPath: \.trayMargin, label: "Tray margin", range: 0...24, unit: "pt"),
        .slider("trayInnerPadding", keyPath: \.trayInnerPadding, label: "Tray inner padding", range: 0...16, unit: "pt"),
        .slider("trayTintOpacity", keyPath: \.trayTintOpacity, label: "Tray tint opacity", range: 0...1, step: 0.05),
        .slider("trayRimOpacityLight", keyPath: \.trayRimOpacityLight, label: "Tray rim opacity (light)", range: 0...1, step: 0.05),
        .slider("trayRimOpacityDark", keyPath: \.trayRimOpacityDark, label: "Tray rim opacity (dark)", range: 0...1, step: 0.05),
        // Rows
        .slider("rowHeight", keyPath: \.rowHeight, label: "Row height", range: 32...64, unit: "pt"),
        .slider("rowGap", keyPath: \.rowGap, label: "Row gap", range: 0...12, unit: "pt"),
        .slider("rowTitleSize", keyPath: \.rowTitleSize, label: "Row title size", range: 9...16, unit: "pt"),
        .slider("rowSubtitleSize", keyPath: \.rowSubtitleSize, label: "Row subtitle size", range: 8...14, unit: "pt"),
        .slider("rowGhostSize", keyPath: \.rowGhostSize, label: "Row ghost size", range: 8...24, unit: "pt"),
        .slider("rowLeadingPadding", keyPath: \.rowLeadingPadding, label: "Row leading padding", range: 0...24, unit: "pt"),
        .slider("rowTrailingPadding", keyPath: \.rowTrailingPadding, label: "Row trailing padding", range: 0...24, unit: "pt"),
        .slider("selectedCardCornerRadius", keyPath: \.selectedCardCornerRadius, label: "Selected card radius", range: 0...24, unit: "pt"),
        .slider("selectedCardShadowOpacity", keyPath: \.selectedCardShadowOpacity, label: "Selected card shadow opacity", range: 0...0.4, step: 0.02),
        .slider("selectedCardShadowRadius", keyPath: \.selectedCardShadowRadius, label: "Selected card shadow radius", range: 0...32, unit: "pt"),
        .slider("selectedCardShadowYOffset", keyPath: \.selectedCardShadowYOffset, label: "Selected card shadow Y", range: 0...16, unit: "pt"),
        // Section headers
        .slider("headerTextSize", keyPath: \.headerTextSize, label: "Header text size", range: 8...16, unit: "pt"),
        .slider("headerTopPadding", keyPath: \.headerTopPadding, label: "Header top padding", range: 0...20, unit: "pt"),
        .slider("headerBottomPadding", keyPath: \.headerBottomPadding, label: "Header bottom padding", range: 0...20, unit: "pt"),
        .slider("headerChevronSize", keyPath: \.headerChevronSize, label: "Header chevron size", range: 8...24, unit: "pt"),
        // Sidebar layout
        .slider("contentPaddingTop", keyPath: \.contentPaddingTop, label: "Content padding top", range: 0...24, unit: "pt"),
        .slider("contentPaddingLeading", keyPath: \.contentPaddingLeading, label: "Content padding leading", range: 0...24, unit: "pt"),
        .slider("contentPaddingTrailing", keyPath: \.contentPaddingTrailing, label: "Content padding trailing", range: 0...24, unit: "pt"),
        .slider("listToTrayGap", keyPath: \.listToTrayGap, label: "List-to-tray gap", range: 0...24, unit: "pt"),
        // Rail
        .slider("railGhostSize", keyPath: \.railGhostSize, label: "Rail ghost size", range: 8...24, unit: "pt"),
        .slider("railRowWidth", keyPath: \.railRowWidth, label: "Rail row width", range: 32...80, unit: "pt"),
        .slider("railRowHeight", keyPath: \.railRowHeight, label: "Rail row height", range: 20...48, unit: "pt"),
        .slider("railRowGap", keyPath: \.railRowGap, label: "Rail row gap", range: 0...16, unit: "pt"),
        .slider("railSummaryRowHeight", keyPath: \.railSummaryRowHeight, label: "Rail summary row height", range: 12...36, unit: "pt"),
        .slider("railExtraWidth", keyPath: \.railExtraWidth, label: "Rail extra width", range: 0...60, unit: "pt"),
        .action(resetActionPath, label: "Reset sidebar")
    ]
}

@available(macOS 14, *)
@MainActor
private final class SidebarDialKitCoordinatorBox {
    weak var coordinator: SidebarDialKitCoordinator?
}

/// Hosts DialKit **inline** in a narrow container we own, exactly like
/// `ComposerDialKitHost` — see that type's doc comment for why `.inline`
/// (not `.drawer`) and why a `@StateObject` coordinator. Defaults collapsed
/// (composer's default is expanded because the composer only mounts while
/// summoned; the sidebar is permanent chrome, so this panel starts out of
/// the way and Sean opens it with the same chevron/gear toggle).
@available(macOS 14, *)
private struct SidebarDialKitHost: View {
    @StateObject private var coordinator: SidebarDialKitCoordinator

    static let collapsedDefaultsKey = "ghostties.sidebarDialKitPanelCollapsed"
    private static let panelWidth: CGFloat = 320

    @AppStorage private var isCollapsed: Bool

    init(defaults: UserDefaults, onChange: @escaping () -> Void) {
        _coordinator = StateObject(wrappedValue: SidebarDialKitCoordinator(defaults: defaults, onChange: onChange))
        _isCollapsed = AppStorage(wrappedValue: true, Self.collapsedDefaultsKey, store: defaults)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .trailing, spacing: 8) {
                collapseControl
                if !isCollapsed {
                    ScrollView(showsIndicators: false) {
                        DialRoot(mode: .inline)
                    }
                    .frame(maxHeight: max(0, geometry.size.height - collapsedControlReservedHeight))
                }
            }
            .frame(width: Self.panelWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var collapsedControlReservedHeight: CGFloat { 40 }

    private var collapseControl: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            Image(systemName: isCollapsed ? "slider.horizontal.3" : "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(white: 0.13)))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// DEBUG-only entry point, hosted by `WorkspaceSidebarView` in a
/// `.topTrailing` overlay — the same mount pattern `SessionComposerOverlay`
/// uses for `ComposerDebugTuningControl`. macOS 14+ only (see the file's
/// top-of-section doc comment); below that, nothing renders (no legacy
/// fallback), same "every dial still reachable via `defaults write`, just
/// no live panel" floor.
struct SidebarDebugTuningControl: View {
    let defaults: UserDefaults
    let onChange: () -> Void

    var body: some View {
        if #available(macOS 14, *) {
            SidebarDialKitHost(defaults: defaults, onChange: onChange)
        } else {
            EmptyView()
        }
    }
}
#endif
