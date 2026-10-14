import SwiftUI
import AppKit
#if DEBUG
import DialkitmacOS
#endif

// MARK: - Canvas (beta.27)
//
// The canvas card's fill and its drop shadow, read through one place so a
// DEBUG build can tune them live, per appearance, in the DialKit inspector's
// "Canvas" panel. The chrome around the card is the "Sidebar colors" panel's
// "Sidebar background" (`SidebarColors.background`), not a dial here. Each
// reader below returns the shipped expression verbatim: a Release build
// compiles exactly that and reads nothing. A DEBUG build returns the same
// expression until that dial for that appearance is written, so an
// untouched panel renders pixel-identical to Release.
enum CanvasStyle {
    /// The terminal and browser cards' fill (DESIGN.md `canvasBackground`).
    static func background(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> NSColor {
        #if DEBUG
        if let tuned = CanvasTuning.hex(.background, scheme, defaults: defaults) { return tuned.nsColor }
        #endif
        return scheme == .dark ? WorkspaceLayout.canvasBackgroundDark : WorkspaceLayout.canvasBackgroundLight
    }

    static func shadowColor(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> CGColor {
        #if DEBUG
        if let tuned = CanvasTuning.hex(.shadowColor, scheme, defaults: defaults) { return tuned.nsColor.cgColor }
        #endif
        return scheme == .dark ? WorkspaceLayout.canvasShadowColorDark : WorkspaceLayout.canvasShadowColorLight
    }

    /// The opacity a card casts while it casts at all.
    static func shadowOpacity(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Float {
        #if DEBUG
        if let tuned = CanvasTuning.number(.shadowOpacity, scheme, defaults: defaults) { return Float(tuned) }
        #endif
        return WorkspaceLayout.canvasShadowOpacity
    }

    static func shadowRadius(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        #if DEBUG
        if let tuned = CanvasTuning.number(.shadowRadius, scheme, defaults: defaults) { return CGFloat(tuned) }
        #endif
        return WorkspaceLayout.canvasShadowRadius
    }

    static func shadowOffset(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> CGSize {
        #if DEBUG
        if let tuned = CanvasTuning.number(.shadowOffsetY, scheme, defaults: defaults) {
            return CGSize(width: WorkspaceLayout.canvasShadowOffset.width, height: CGFloat(tuned))
        }
        #endif
        return WorkspaceLayout.canvasShadowOffset
    }
}

#if DEBUG
/// DEBUG-only storage and shipped values behind `CanvasStyle`. Keys live in
/// `SidebarDialTuning.store`, so "Reset all panels" clears them with every
/// other dial.
enum CanvasTuning {
    enum Dial: String, CaseIterable {
        case background
        case shadowColor
        case shadowOpacity
        case shadowRadius
        case shadowOffsetY
    }

    static func key(_ dial: Dial, _ scheme: ColorScheme) -> String {
        "ghostties.sidebarDial.canvas.\(scheme == .dark ? "dark" : "light").\(dial.rawValue)"
    }

    /// Every key the "Canvas" panel writes.
    static let allKeys: [String] = [ColorScheme.light, .dark].flatMap { scheme in
        Dial.allCases.map { key($0, scheme) }
    }

    /// A colour dial's tuned value, or nil while it isn't stored.
    static func hex(_ dial: Dial, _ scheme: ColorScheme, defaults: UserDefaults) -> SidebarColorTuning.RGBA? {
        defaults.string(forKey: key(dial, scheme)).flatMap { SidebarColorTuning.RGBA(hex: $0) }
    }

    /// A number dial's tuned value, or nil while it isn't stored.
    static func number(_ dial: Dial, _ scheme: ColorScheme, defaults: UserDefaults) -> Double? {
        switch defaults.object(forKey: key(dial, scheme)) {
        case let stored as Double: return stored
        case let argument as String: return Double(argument)
        default: return nil
        }
    }
}

// MARK: - "Canvas" panel (macOS 14+, DEBUG only)

@available(macOS 14, *)
struct CanvasDialKitTuningModel: Codable, Equatable {
    struct Appearance: Codable, Equatable {
        var background: String
        var shadowColor: String
        var shadowOpacity: Double
        var shadowRadius: Double
        var shadowOffsetY: Double
    }

    var light: Appearance
    var dark: Appearance
}

@available(macOS 14, *)
@MainActor
enum CanvasDialPanel: FocusedDialPanel {
    typealias Model = CanvasDialKitTuningModel
    typealias Appearance = CanvasDialKitTuningModel.Appearance

    static let name = "Canvas"
    static let resetLabel = "Reset canvas"
    static var resetKeys: [String] { CanvasTuning.allKeys }

    static func read(_ defaults: UserDefaults) -> Model {
        func appearance(_ scheme: ColorScheme) -> Appearance {
            Appearance(
                background: SidebarColorTuning.RGBA(CanvasStyle.background(scheme, defaults: defaults), scheme).hex,
                shadowColor: SidebarColorTuning.RGBA(
                    NSColor(cgColor: CanvasStyle.shadowColor(scheme, defaults: defaults)) ?? .black, scheme
                ).hex,
                shadowOpacity: Double(CanvasStyle.shadowOpacity(scheme, defaults: defaults)),
                shadowRadius: Double(CanvasStyle.shadowRadius(scheme, defaults: defaults)),
                shadowOffsetY: Double(CanvasStyle.shadowOffset(scheme, defaults: defaults).height)
            )
        }
        return Model(light: appearance(.light), dark: appearance(.dark))
    }

    static func write(_ defaults: UserDefaults, from previous: Model, to model: Model) {
        for (scheme, old, new) in [(ColorScheme.light, previous.light, model.light), (.dark, previous.dark, model.dark)] {
            if old.background != new.background {
                defaults.set(new.background, forKey: CanvasTuning.key(.background, scheme))
            }
            if old.shadowColor != new.shadowColor {
                defaults.set(new.shadowColor, forKey: CanvasTuning.key(.shadowColor, scheme))
            }
            if old.shadowOpacity != new.shadowOpacity {
                defaults.set(new.shadowOpacity, forKey: CanvasTuning.key(.shadowOpacity, scheme))
            }
            if old.shadowRadius != new.shadowRadius {
                defaults.set(new.shadowRadius, forKey: CanvasTuning.key(.shadowRadius, scheme))
            }
            if old.shadowOffsetY != new.shadowOffsetY {
                defaults.set(new.shadowOffsetY, forKey: CanvasTuning.key(.shadowOffsetY, scheme))
            }
        }
    }

    private static func controls(
        _ prefix: String, _ set: WritableKeyPath<Model, Appearance>
    ) -> [DialControl<Model>] {
        [
            .color("\(prefix)Background", keyPath: set.appending(path: \.background), label: "Canvas background"),
            .color("\(prefix)ShadowColor", keyPath: set.appending(path: \.shadowColor), label: "Card shadow color"),
            .slider("\(prefix)ShadowOpacity", keyPath: set.appending(path: \.shadowOpacity), label: "Card shadow opacity", range: 0...1, step: 0.01),
            .slider("\(prefix)ShadowRadius", keyPath: set.appending(path: \.shadowRadius), label: "Card shadow blur", range: 0...40, step: 0.5, unit: "pt"),
            .slider("\(prefix)ShadowOffsetY", keyPath: set.appending(path: \.shadowOffsetY), label: "Card shadow Y offset (ships -2)", range: -20...20, step: 0.5, unit: "pt"),
        ]
    }

    static var controls: [DialControl<Model>] {
        [
            // The window chrome around the card is "Sidebar colors" →
            // "Sidebar background".
            .group("canvasLight", label: "Canvas — Light", children: controls("light", \.light)),
            .group("canvasDark", label: "Canvas — Dark", children: controls("dark", \.dark)),
        ]
    }
}
#endif
