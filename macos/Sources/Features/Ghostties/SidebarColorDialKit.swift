import SwiftUI
import AppKit
#if DEBUG
import DialkitmacOS
#endif

// MARK: - Sidebar colors (beta.27)
//
// Every colour the one-view sidebar draws that decides legibility, read
// through one place so a DEBUG build can tune them live in the DialKit
// inspector's "Sidebar colors" panel. Each reader below returns the shipped
// expression verbatim: a Release build compiles exactly that and reads
// nothing. A DEBUG build returns the same expression until a dial for that
// role and appearance is written, so an untouched panel renders
// pixel-identical to Release.
enum SidebarColors {
    /// The tunable colours. Opacity is a dial only where the shipped colour
    /// is translucent.
    enum Role: String, CaseIterable {
        /// The chrome layer behind the sidebar column and the card gutter
        /// (DESIGN.md `chromeBackground`). Also the selected tile's monogram.
        case background
        /// Session names (`Color.primary`) and the "needs input" glyph.
        case primaryText
        /// Project headers and counts, subtitles, History, and the other
        /// status glyphs (DESIGN.md `textSecondary`).
        case secondaryText
        /// A project tile's plain fill.
        case tileFill
        /// A project tile's monogram, and the selected project's solid fill.
        case tileInk
        /// The selected row's chip.
        case selectedRowTint

        var hasOpacity: Bool {
            switch self {
            case .primaryText, .tileFill, .selectedRowTint: return true
            case .background, .secondaryText, .tileInk: return false
            }
        }
    }

    static func background(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> NSColor {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.background, scheme, defaults: defaults) { return tuned.nsColor }
        #endif
        return scheme == .dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight
    }

    static func primaryText(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.primaryText, scheme, defaults: defaults) { return tuned.color }
        #endif
        return Color.primary
    }

    static func secondaryText(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.secondaryText, scheme, defaults: defaults) { return tuned.color }
        #endif
        return scheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }

    /// Option D (`hRCBC`: `#28221E1A`) in light; 7% white in dark.
    static func tileFill(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.tileFill, scheme, defaults: defaults) { return tuned.color }
        #endif
        return scheme == .dark
            ? Color.white.opacity(0.07)
            : Color(red: 40 / 255, green: 34 / 255, blue: 30 / 255).opacity(RailProjectTile.tintOpacity)
    }

    static func tileInk(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.tileInk, scheme, defaults: defaults) { return tuned.color }
        #endif
        return scheme == .dark
            ? Color(red: 0xF0 / 255, green: 0xEF / 255, blue: 0xED / 255)
            : Color(red: 0x23 / 255, green: 0x21 / 255, blue: 0x20 / 255)
    }

    /// The canvas's alpha on solid ink (`RailProjectColumn.tintInk`).
    static func selectedRowTint(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.override(.selectedRowTint, scheme, defaults: defaults) { return tuned.color }
        #endif
        return RailProjectColumn.tintInk(scheme).opacity(RailProjectColumn.selectedChipTintOpacity)
    }

    /// An empty project's header and monogram: one tier below secondary text
    /// on purpose (`WorkspaceLayout.emptyProjectForeground`).
    static func dimmedProject(_ scheme: ColorScheme, defaults: UserDefaults = SidebarDialTuning.store) -> Color {
        #if DEBUG
        if let tuned = SidebarColorTuning.dimmedOverride(scheme, defaults: defaults) { return tuned.color }
        #endif
        return WorkspaceLayout.emptyProjectForeground
    }
}

#if DEBUG
/// DEBUG-only storage, shipped values and contrast maths behind
/// `SidebarColors`. Keys live in `SidebarDialTuning.store`, so "Reset all
/// panels" clears them with every other sidebar dial.
enum SidebarColorTuning {
    /// One colour in sRGB, 0...1 per channel.
    struct RGBA: Equatable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double

        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
        var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
        var opaque: RGBA { RGBA(r: r, g: g, b: b, a: 1) }

        /// `#RRGGBB`, alpha dropped (opacity is its own dial).
        var hex: String {
            func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }

        init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }

        init(_ color: NSColor, _ scheme: ColorScheme) {
            var out = RGBA(r: 0, g: 0, b: 0)
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
            appearance.performAsCurrentDrawingAppearance {
                let c = color.usingColorSpace(.sRGB) ?? color
                out = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
            }
            self = out
        }

        /// `#RGB`, `#RRGGBB` or `#RRGGBBAA` (an `AA` multiplies `a`).
        init?(hex: String, a: Double = 1) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("#") else { return nil }
            s.removeFirst()
            if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
            guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
            let has8 = s.count == 8
            let rgb = has8 ? v >> 8 : v
            self.init(
                r: Double((rgb >> 16) & 0xFF) / 255,
                g: Double((rgb >> 8) & 0xFF) / 255,
                b: Double(rgb & 0xFF) / 255,
                a: a * (has8 ? Double(v & 0xFF) / 255 : 1)
            )
        }
    }

    private static func scope(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    static func hexKey(_ role: SidebarColors.Role, _ scheme: ColorScheme) -> String {
        "ghostties.sidebarDial.colors.\(scope(scheme)).\(role.rawValue)"
    }
    static func opacityKey(_ role: SidebarColors.Role, _ scheme: ColorScheme) -> String {
        hexKey(role, scheme) + ".opacity"
    }
    static func dimmedOpacityKey(_ scheme: ColorScheme) -> String {
        "ghostties.sidebarDial.colors.\(scope(scheme)).dimmedProjectOpacity"
    }

    /// Every key the "Sidebar colors" panel writes.
    static let allKeys: [String] = [ColorScheme.light, .dark].flatMap { scheme in
        SidebarColors.Role.allCases.flatMap { role in
            role.hasOpacity ? [hexKey(role, scheme), opacityKey(role, scheme)] : [hexKey(role, scheme)]
        } + [dimmedOpacityKey(scheme)]
    }

    /// The shipped colour for `role`, in sRGB: what each dial shows unset.
    static func base(_ role: SidebarColors.Role, _ scheme: ColorScheme) -> RGBA {
        let dark = scheme == .dark
        switch role {
        case .background:
            return RGBA(dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight, scheme)
        case .primaryText:
            // `Color.primary` is the label colour: 85% black / white.
            return RGBA(.labelColor, scheme)
        case .secondaryText:
            return dark ? RGBA(r: 0x9A / 255, g: 0x9A / 255, b: 0x9A / 255) : RGBA(r: 0x63 / 255, g: 0x63 / 255, b: 0x63 / 255)
        case .tileFill:
            return dark ? RGBA(r: 1, g: 1, b: 1, a: 0.07) : RGBA(r: 40 / 255, g: 34 / 255, b: 30 / 255, a: RailProjectTile.tintOpacity)
        case .tileInk:
            return dark ? RGBA(r: 0xF0 / 255, g: 0xEF / 255, b: 0xED / 255) : RGBA(r: 0x23 / 255, g: 0x21 / 255, b: 0x20 / 255)
        case .selectedRowTint:
            let ink: Double = dark ? 1 : 0
            return RGBA(r: ink, g: ink, b: ink, a: RailProjectColumn.selectedChipTintOpacity)
        }
    }

    /// The shipped dimmed-project ink (`tertiaryLabelColor`), in sRGB.
    static func baseDimmed(_ scheme: ColorScheme) -> RGBA {
        RGBA(.tertiaryLabelColor, scheme)
    }

    /// `role`'s tuned colour, or nil while neither of its dials is stored
    /// (the reader then draws the shipped expression, not this).
    static func override(_ role: SidebarColors.Role, _ scheme: ColorScheme, defaults: UserDefaults) -> RGBA? {
        let storedHex = defaults.string(forKey: hexKey(role, scheme))
        let storedOpacity = role.hasOpacity ? number(opacityKey(role, scheme), defaults) : nil
        guard storedHex != nil || storedOpacity != nil else { return nil }
        let base = base(role, scheme)
        let opacity = storedOpacity ?? base.a
        return storedHex.flatMap { RGBA(hex: $0, a: opacity) } ?? RGBA(r: base.r, g: base.g, b: base.b, a: opacity)
    }

    static func dimmedOverride(_ scheme: ColorScheme, defaults: UserDefaults) -> RGBA? {
        guard let opacity = number(dimmedOpacityKey(scheme), defaults) else { return nil }
        var c = baseDimmed(scheme)
        c.a = min(max(opacity, 0), 1)
        return c
    }

    /// What a dial shows: the tuned value, else the shipped one.
    static func resolved(_ role: SidebarColors.Role, _ scheme: ColorScheme, defaults: UserDefaults) -> RGBA {
        override(role, scheme, defaults: defaults) ?? base(role, scheme)
    }

    static func resolvedDimmedOpacity(_ scheme: ColorScheme, defaults: UserDefaults) -> Double {
        (dimmedOverride(scheme, defaults: defaults) ?? baseDimmed(scheme)).a
    }

    private static func number(_ key: String, _ defaults: UserDefaults) -> Double? {
        switch defaults.object(forKey: key) {
        case let stored as Double: return stored
        case let argument as String: return Double(argument)
        default: return nil
        }
    }

    // MARK: Contrast (WCAG 2.x)

    /// `top` over `bottom`, source-over, result opaque when `bottom` is.
    static func composite(_ top: RGBA, over bottom: RGBA) -> RGBA {
        let a = top.a + bottom.a * (1 - top.a)
        guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        func ch(_ t: Double, _ b: Double) -> Double { (t * top.a + b * bottom.a * (1 - top.a)) / a }
        return RGBA(r: ch(top.r, bottom.r), g: ch(top.g, bottom.g), b: ch(top.b, bottom.b), a: a)
    }

    static func relativeLuminance(_ c: RGBA) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast of `foreground` drawn on `background`. The background is
    /// taken as opaque; a translucent foreground is composited over it first.
    static func contrastRatio(_ foreground: RGBA, on background: RGBA) -> Double {
        let bg = background.opaque
        let fg = composite(foreground, over: bg)
        let l1 = relativeLuminance(fg), l2 = relativeLuminance(bg)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// The pairs the panel reads out, for one appearance's colours.
    struct ContrastPairs: Equatable {
        var primary: Double
        var secondary: Double
        var secondaryOnCard: Double
        var tile: Double
        var selectedTile: Double
        var dimmed: Double
    }

    /// Against the opaque chrome background. The sidebar has no glass or
    /// vibrancy in pinned and rail modes; overlay mode (the rail's hover
    /// reveal) paints the terminal's own background instead, which these
    /// ratios don't model.
    static func contrastPairs(
        background: RGBA, primary: RGBA, secondary: RGBA, tileFill: RGBA, tileInk: RGBA,
        dimmed: RGBA, cardTint: RGBA
    ) -> ContrastPairs {
        let bg = background.opaque
        let card = composite(cardTint, over: bg)
        let tile = composite(tileFill, over: bg)
        // The selected tile: solid ink (at "Selected tile fill" 1), monogram
        // in the background colour.
        let selectedTile = composite(tileInk, over: bg)
        return ContrastPairs(
            primary: contrastRatio(primary, on: bg),
            secondary: contrastRatio(secondary, on: bg),
            secondaryOnCard: contrastRatio(secondary, on: card),
            tile: contrastRatio(tileInk, on: tile),
            selectedTile: contrastRatio(bg, on: selectedTile),
            dimmed: contrastRatio(dimmed, on: bg)
        )
    }

    /// `5.62:1 · passes AA`, against the 4.5:1 text floor.
    static func readout(_ ratio: Double, dimmed: Bool = false) -> String {
        let value = String(format: "%.2f:1", ratio)
        if dimmed { return "\(value) · dimmed by design" }
        return ratio >= 4.5 ? "\(value) · passes AA" : "\(value) · below AA 4.5"
    }
}

// MARK: - "Sidebar colors" panel (macOS 14+, DEBUG only)

/// The panel's model: one set per appearance, plus read-only contrast rows
/// recomputed from the colours on every change (`derive`).
@available(macOS 14, *)
struct SidebarColorsDialKitTuningModel: Codable, Equatable {
    struct Appearance: Codable, Equatable {
        var background: String
        var primaryText: String
        var primaryTextOpacity: Double
        var secondaryText: String
        var tileFill: String
        var tileFillOpacity: Double
        var tileInk: String
        var selectedRowTint: String
        var selectedRowTintOpacity: Double
        var dimmedProjectOpacity: Double

        // Read-only: never written to defaults; an edit is replaced at once.
        var contrastPrimary = ""
        var contrastSecondary = ""
        var contrastSecondaryOnCard = ""
        var contrastTile = ""
        var contrastSelectedTile = ""
        var contrastDimmed = ""
    }

    var light: Appearance
    var dark: Appearance
}

@available(macOS 14, *)
@MainActor
enum SidebarColorsDialPanel: FocusedDialPanel {
    typealias Model = SidebarColorsDialKitTuningModel
    typealias Appearance = SidebarColorsDialKitTuningModel.Appearance

    static let name = "Sidebar colors"
    static let resetLabel = "Reset sidebar colors"
    static var resetKeys: [String] { SidebarColorTuning.allKeys }

    /// Each role's hex field and, where it has one, its opacity field.
    private static let fields: [(SidebarColors.Role, WritableKeyPath<Appearance, String>, WritableKeyPath<Appearance, Double>?)] = [
        (.background, \.background, nil),
        (.primaryText, \.primaryText, \.primaryTextOpacity),
        (.secondaryText, \.secondaryText, nil),
        (.tileFill, \.tileFill, \.tileFillOpacity),
        (.tileInk, \.tileInk, nil),
        (.selectedRowTint, \.selectedRowTint, \.selectedRowTintOpacity),
    ]

    static func read(_ defaults: UserDefaults) -> Model {
        func appearance(_ scheme: ColorScheme) -> Appearance {
            func c(_ role: SidebarColors.Role) -> SidebarColorTuning.RGBA {
                SidebarColorTuning.resolved(role, scheme, defaults: defaults)
            }
            return Appearance(
                background: c(.background).hex,
                primaryText: c(.primaryText).hex,
                primaryTextOpacity: c(.primaryText).a,
                secondaryText: c(.secondaryText).hex,
                tileFill: c(.tileFill).hex,
                tileFillOpacity: c(.tileFill).a,
                tileInk: c(.tileInk).hex,
                selectedRowTint: c(.selectedRowTint).hex,
                selectedRowTintOpacity: c(.selectedRowTint).a,
                dimmedProjectOpacity: SidebarColorTuning.resolvedDimmedOpacity(scheme, defaults: defaults)
            )
        }
        var model = Model(light: appearance(.light), dark: appearance(.dark))
        derive(&model, defaults: defaults)
        return model
    }

    static func write(_ defaults: UserDefaults, from previous: Model, to model: Model) {
        for (scheme, old, new) in [(ColorScheme.light, previous.light, model.light), (.dark, previous.dark, model.dark)] {
            for (role, hex, opacity) in fields {
                if old[keyPath: hex] != new[keyPath: hex] {
                    defaults.set(new[keyPath: hex], forKey: SidebarColorTuning.hexKey(role, scheme))
                }
                if let opacity, old[keyPath: opacity] != new[keyPath: opacity] {
                    defaults.set(new[keyPath: opacity], forKey: SidebarColorTuning.opacityKey(role, scheme))
                }
            }
            if old.dimmedProjectOpacity != new.dimmedProjectOpacity {
                defaults.set(new.dimmedProjectOpacity, forKey: SidebarColorTuning.dimmedOpacityKey(scheme))
            }
        }
    }

    /// Recomputes the contrast rows from the panel's own colours.
    static func derive(_ model: inout Model, defaults: UserDefaults) {
        let cardOpacity = min(max(SidebarDialTuning.railColumnTintOpacity(defaults: defaults), 0), 1)
        func fill(_ a: inout Appearance, _ scheme: ColorScheme) {
            func rgba(_ hex: String, _ opacity: Double = 1, fallback role: SidebarColors.Role) -> SidebarColorTuning.RGBA {
                SidebarColorTuning.RGBA(hex: hex, a: opacity) ?? SidebarColorTuning.base(role, scheme)
            }
            var dimmed = SidebarColorTuning.baseDimmed(scheme)
            dimmed.a = a.dimmedProjectOpacity
            let ink: Double = scheme == .dark ? 1 : 0
            let pairs = SidebarColorTuning.contrastPairs(
                background: rgba(a.background, fallback: .background),
                primary: rgba(a.primaryText, a.primaryTextOpacity, fallback: .primaryText),
                secondary: rgba(a.secondaryText, fallback: .secondaryText),
                tileFill: rgba(a.tileFill, a.tileFillOpacity, fallback: .tileFill),
                tileInk: rgba(a.tileInk, fallback: .tileInk),
                dimmed: dimmed,
                cardTint: SidebarColorTuning.RGBA(r: ink, g: ink, b: ink, a: cardOpacity)
            )
            a.contrastPrimary = SidebarColorTuning.readout(pairs.primary)
            a.contrastSecondary = SidebarColorTuning.readout(pairs.secondary)
            a.contrastSecondaryOnCard = SidebarColorTuning.readout(pairs.secondaryOnCard)
            a.contrastTile = SidebarColorTuning.readout(pairs.tile)
            a.contrastSelectedTile = SidebarColorTuning.readout(pairs.selectedTile)
            a.contrastDimmed = SidebarColorTuning.readout(pairs.dimmed, dimmed: true)
        }
        fill(&model.light, .light)
        fill(&model.dark, .dark)
    }

    private static func colorControls(
        _ prefix: String, _ set: WritableKeyPath<Model, Appearance>
    ) -> [DialControl<Model>] {
        [
            .color("\(prefix)Background", keyPath: set.appending(path: \.background), label: "Sidebar background"),
            .color("\(prefix)PrimaryText", keyPath: set.appending(path: \.primaryText), label: "Primary text (session names)"),
            .slider("\(prefix)PrimaryTextOpacity", keyPath: set.appending(path: \.primaryTextOpacity), label: "Primary text opacity", range: 0...1, step: 0.01),
            .color("\(prefix)SecondaryText", keyPath: set.appending(path: \.secondaryText), label: "Secondary text (headers, counts, subtitles, glyphs)"),
            .color("\(prefix)TileFill", keyPath: set.appending(path: \.tileFill), label: "Tile fill"),
            .slider("\(prefix)TileFillOpacity", keyPath: set.appending(path: \.tileFillOpacity), label: "Tile fill opacity", range: 0...1, step: 0.01),
            .color("\(prefix)TileInk", keyPath: set.appending(path: \.tileInk), label: "Tile monogram / selected tile fill"),
            .color("\(prefix)SelectedRowTint", keyPath: set.appending(path: \.selectedRowTint), label: "Selected row tint"),
            .slider("\(prefix)SelectedRowTintOpacity", keyPath: set.appending(path: \.selectedRowTintOpacity), label: "Selected row tint opacity", range: 0...0.5, step: 0.01),
            .slider("\(prefix)DimmedProjectOpacity", keyPath: set.appending(path: \.dimmedProjectOpacity), label: "Dimmed project opacity (0 live)", range: 0...1, step: 0.01),
        ]
    }

    private static func contrastControls(
        _ prefix: String, _ set: WritableKeyPath<Model, Appearance>
    ) -> [DialControl<Model>] {
        [
            .text("\(prefix)ContrastPrimary", keyPath: set.appending(path: \.contrastPrimary), label: "Primary on background"),
            .text("\(prefix)ContrastSecondary", keyPath: set.appending(path: \.contrastSecondary), label: "Secondary on background"),
            .text("\(prefix)ContrastSecondaryOnCard", keyPath: set.appending(path: \.contrastSecondaryOnCard), label: "Secondary on group card"),
            .text("\(prefix)ContrastTile", keyPath: set.appending(path: \.contrastTile), label: "Monogram on tile"),
            .text("\(prefix)ContrastSelectedTile", keyPath: set.appending(path: \.contrastSelectedTile), label: "Monogram on selected tile"),
            .text("\(prefix)ContrastDimmed", keyPath: set.appending(path: \.contrastDimmed), label: "Dimmed project on background"),
        ]
    }

    static var controls: [DialControl<Model>] {
        [
            .group("colorsLight", label: "Colors — Light", children: colorControls("light", \.light)),
            .group("colorsDark", label: "Colors — Dark", children: colorControls("dark", \.dark)),
            // Read-only WCAG ratios against the opaque sidebar background.
            .group("contrastLight", label: "Contrast — Light (read-only)", children: contrastControls("light", \.light)),
            .group("contrastDark", label: "Contrast — Dark (read-only)", children: contrastControls("dark", \.dark)),
        ]
    }
}
#endif
