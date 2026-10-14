import AppKit
import SwiftUI

/// The chrome's colour tokens, one value per appearance (appearance-themes
/// plan, slice 1). Five base colours; every other chrome tint is one of them
/// at a named step, so a value lives in exactly one place.
///
/// - `canvas`: the terminal card's fill. No Swift copy: read from the
///   bundled theme file's `background`, the one source of truth.
/// - `chrome`: the layer behind the sidebar column and the card gutter.
/// - `ink`: solid black in light, white in dark, so an opacity on it is
///   the alpha that is drawn (`Color.primary` is 85% black, not that).
/// - `inkSecondary`: muted text, clears 4.5:1 on the chrome and the group card.
/// - `shadow`: the canvas card's shadow colour.
///
/// The chrome follows the terminal theme (slice 2): `resolve` maps the
/// terminal's background and foreground to the hand-tuned Ghostties pair
/// when they are that pair's, and to `derived` values otherwise.
/// `ChromeThemeStore` holds the one active theme; readers ask
/// `ChromeTheme.active(_:)`.
struct ChromeTheme {
    enum Polarity { case light, dark }

    /// Ink at an opacity that differs by polarity. Replaces the free-floating
    /// per-appearance opacity literals; the numbers are today's, unchanged.
    enum Step {
        /// The active session row (`activeRow`).
        case row
        /// The highlighted row in the Cmd+T composer, heavier than `row`: it
        /// floats over live terminal output.
        case composerRow
        /// A project tile's plain fill in dark. Light lays `tileFillBase` at
        /// `RailProjectTile.tintOpacity` instead.
        case tile

        func opacity(_ polarity: Polarity) -> Double {
            switch (self, polarity) {
            case (.row, .light): return 0.04
            case (.row, .dark): return 0.06
            case (.composerRow, .light): return 0.06
            case (.composerRow, .dark): return 0.10
            case (.tile, .light), (.tile, .dark): return 0.07
            }
        }
    }

    /// The chrome lifted toward white by a fraction: the opaque surfaces that
    /// sit one step above it.
    enum Lift {
        /// The expanded project group's container.
        case container
        /// A hairline one step above the chrome (the tray glass's rim).
        case border

        func fraction(_ polarity: Polarity) -> Double {
            switch (self, polarity) {
            case (.container, .light), (.border, .light): return 1
            case (.container, .dark): return 0.0233
            case (.border, .dark): return 0.0288
            }
        }
    }

    let polarity: Polarity
    let canvas: NSColor
    let chrome: NSColor
    let ink: NSColor
    let inkSecondary: NSColor
    let shadow: NSColor

    // Exceptions, not base colours: values the goldens freeze that no step
    // of the five reproduces. Slice 4's design pass decides their fate.
    /// A project tile's monogram, and the selected project's solid fill.
    let tileInk: NSColor
    /// The light tile fill's base (laid at `RailProjectTile.tintOpacity`).
    let tileFillBase: NSColor

    // MARK: Lookup

    static func ghostties(_ scheme: ColorScheme) -> ChromeTheme {
        scheme == .dark ? ghosttiesDark : ghosttiesLight
    }

    private static let ghosttiesLight = ChromeTheme(
        polarity: .light,
        canvas: ThemeFile.background(named: "Ghostties Light"),
        chrome: NSColor(red: 0xF0 / 255.0, green: 0xE9 / 255.0, blue: 0xE6 / 255.0, alpha: 1),
        ink: .black,
        inkSecondary: NSColor(srgbRed: 0x5E / 255.0, green: 0x5E / 255.0, blue: 0x5E / 255.0, alpha: 1),
        shadow: NSColor(red: 0x0F / 255.0, green: 0x0F / 255.0, blue: 0x0F / 255.0, alpha: 1),
        tileInk: NSColor(srgbRed: 0x23 / 255.0, green: 0x21 / 255.0, blue: 0x20 / 255.0, alpha: 1),
        tileFillBase: NSColor(srgbRed: 40 / 255.0, green: 34 / 255.0, blue: 30 / 255.0, alpha: 1)
    )

    private static let ghosttiesDark = ChromeTheme(
        polarity: .dark,
        canvas: ThemeFile.background(named: "Ghostties Dark"),
        chrome: NSColor(white: 0.14, alpha: 1),
        ink: .white,
        inkSecondary: NSColor(srgbRed: 0xA6 / 255.0, green: 0xA6 / 255.0, blue: 0xA6 / 255.0, alpha: 1),
        shadow: NSColor(red: 1, green: 1, blue: 1, alpha: 1),
        tileInk: NSColor(srgbRed: 0xF0 / 255.0, green: 0xEF / 255.0, blue: 0xED / 255.0, alpha: 1),
        tileFillBase: .white
    )

    // MARK: Derived

    /// `inkSecondary` as a SwiftUI colour: section and group headers, empty
    /// states, captions, and every other muted label.
    var inkSecondaryColor: Color { Color(inkSecondary) }

    /// `ink` at one of the named steps.
    func ink(_ step: Step) -> Color {
        Color(ink).opacity(step.opacity(polarity))
    }

    /// The chrome lifted toward white by `lift`, flattened to one opaque colour.
    func lifted(_ lift: Lift) -> NSColor {
        let base = chrome.usingColorSpace(.sRGB) ?? chrome
        let f = CGFloat(lift.fraction(polarity))
        func up(_ v: CGFloat) -> CGFloat { v + (1 - v) * f }
        return NSColor(srgbRed: up(base.redComponent), green: up(base.greenComponent), blue: up(base.blueComponent), alpha: 1)
    }
}

/// The key = value lines of a bundled Ghostty theme file. The canvas colour
/// is read from here rather than copied into Swift.
enum ThemeFile {
    /// `name`'s `background`, from the bundled `ghostty/themes` directory.
    /// The file ships in every build (`GhosttiesDefaultThemeTests`); the
    /// system window colour is only the answer if the bundle is broken.
    static func background(named name: String) -> NSColor {
        color("background", named: name) ?? .windowBackgroundColor
    }

    /// `name`'s `foreground`, or nil if the bundle is broken.
    static func foreground(named name: String) -> NSColor? {
        color("foreground", named: name)
    }

    static func background(in text: String) -> NSColor? {
        color("background", in: text)
    }

    private static func color(_ key: String, named name: String) -> NSColor? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ghostty/themes/\(name)"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return color(key, in: text)
    }

    private static func color(_ key: String, in text: String) -> NSColor? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == key else { continue }
            var hex = parts[1]
            if hex.hasPrefix("#") { hex.removeFirst() }
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            return NSColor(
                srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1
            )
        }
        return nil
    }
}

// MARK: - Following the terminal theme

extension ChromeTheme {
    /// The catalog's hand-tuned themes, by bundled theme file name. A
    /// terminal whose background and foreground equal one of these files'
    /// gets that pair's `ghostties` values, unchanged.
    private static let catalog: [(name: String, scheme: ColorScheme)] = [
        ("Ghostties Light", .light),
        ("Ghostties Dark", .dark),
    ]

    /// Each catalog theme's (background, foreground), as 8-bit sRGB.
    private static let catalogColors: [(bytes: [Int], scheme: ColorScheme)] = catalog.compactMap { entry in
        guard let fg = ThemeFile.foreground(named: entry.name) else { return nil }
        return (Oklab.bytes(ThemeFile.background(named: entry.name)) + Oklab.bytes(fg), entry.scheme)
    }

    /// The catalog appearance whose theme file is exactly this pair, or nil.
    static func catalogScheme(background: NSColor, foreground: NSColor) -> ColorScheme? {
        let key = Oklab.bytes(background) + Oklab.bytes(foreground)
        return catalogColors.first { $0.bytes == key }?.scheme
    }

    /// The chrome for a terminal drawing `foreground` on `background`.
    static func resolve(background: NSColor, foreground: NSColor) -> ChromeTheme {
        if let scheme = catalogScheme(background: background, foreground: foreground) {
            return ghostties(scheme)
        }
        return derived(background: background, foreground: foreground)
    }

    /// Text floors the derivation holds every derived theme to.
    static let inkFloor = 7.0
    static let inkSecondaryFloor = 4.6

    /// The chrome for a theme with no hand-tuned values (plan: "Derivation
    /// for Custom and third-party themes"). Every value comes from the
    /// theme's two colours and the Ghostties pair's own steps; nothing new is
    /// typed in.
    ///
    /// - polarity: light if the background contrasts more with black.
    /// - canvas: the background.
    /// - chrome: the background moved in OKLab lightness by the Ghostties
    ///   pair's own chrome-from-canvas step for that polarity.
    /// - ink: the foreground, pushed toward black / white until it clears
    ///   `inkFloor` on the canvas, the chrome and the group card.
    /// - inkSecondary: ink mixed toward the chrome as far as it can go and
    ///   still clear `inkSecondaryFloor` on every sidebar text backdrop.
    /// - shadow: the Ghostties pair's, by polarity.
    /// - tileInk, tileFillBase: ink.
    static func derived(background: NSColor, foreground: NSColor) -> ChromeTheme {
        let canvas = Oklab.srgb(background)
        let fg = Oklab.srgb(foreground)
        let isLight = Oklab.contrast(canvas, Oklab.black) > Oklab.contrast(canvas, Oklab.white)
        let scheme: ColorScheme = isLight ? .light : .dark
        let polarity: Polarity = isLight ? .light : .dark
        let pair = ghostties(scheme)

        let step = Oklab(pair.chrome).l - Oklab(pair.canvas).l
        var chromeLab = Oklab(canvas)
        chromeLab.l = min(max(chromeLab.l + step, 0.02), 0.99)
        let chrome = chromeLab.srgb

        // The group card: the same lift `lifted(.container)` applies.
        let f = Lift.container.fraction(polarity)
        let card = chrome.map { $0 + (1 - $0) * f }

        let extreme = isLight ? Oklab.black : Oklab.white
        let inkBackdrops = [canvas, chrome, card]
        let ink = Oklab.search(from: fg, toward: extreme, smallest: true) { candidate in
            inkBackdrops.allSatisfy { Oklab.contrast(candidate, $0) >= inkFloor + Oklab.margin }
        }

        let secondaryBackdrops = [
            chrome, card,
            Oklab.flatten(ink, alpha: Step.row.opacity(polarity), on: chrome),
            Oklab.flatten(ink, alpha: Step.tile.opacity(polarity), on: chrome),
        ]
        let inkSecondary = Oklab.search(from: ink, toward: chrome, smallest: false) { candidate in
            secondaryBackdrops.allSatisfy { Oklab.contrast(candidate, $0) >= inkSecondaryFloor + Oklab.margin }
        }

        let inkColor = Oklab.color(ink)
        return ChromeTheme(
            polarity: polarity,
            canvas: Oklab.color(canvas),
            chrome: Oklab.color(chrome),
            ink: inkColor,
            inkSecondary: Oklab.color(inkSecondary),
            shadow: pair.shadow,
            tileInk: inkColor,
            tileFillBase: inkColor
        )
    }

    /// The theme the chrome draws in `scheme`: the active theme when its
    /// polarity is `scheme` (always, inside the workspace window, whose
    /// appearance is the theme's polarity), else the Ghostties pair. Before a
    /// config has loaded, and in unit tests, it is the Ghostties pair.
    static func active(_ scheme: ColorScheme) -> ChromeTheme {
        let store = ChromeThemeStore.shared
        if let current = store.current, current.polarity == Polarity(scheme) { return current }
        return ghostties(scheme)
    }

    /// Whether `active(scheme)` is the hand-tuned Ghostties pair. DialKit's
    /// colour overrides apply only then.
    static func activeIsGhostties(_ scheme: ColorScheme) -> Bool {
        let store = ChromeThemeStore.shared
        guard let current = store.current, current.polarity == Polarity(scheme) else { return true }
        return store.isGhostties
    }
}

extension ChromeTheme.Polarity {
    init(_ scheme: ColorScheme) { self = scheme == .dark ? .dark : .light }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    /// The AppKit appearance that draws this polarity.
    var appearance: NSAppearance? { NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
}

/// The one active chrome theme, resolved from the app-level Ghostty config.
/// `AppDelegate` feeds it at launch and on every app config change (a
/// reload, or the light/dark flip that re-resolves a `light:…,dark:…`
/// theme) before anything else reacts to that config. SwiftUI readers
/// depend on it through `ChromeScheme`; AppKit readers observe `didChange`.
/// Main thread only.
final class ChromeThemeStore: ObservableObject {
    static let shared = ChromeThemeStore()

    /// Posted after `current` changes (object: the store).
    static let didChange = Notification.Name("GhosttiesChromeThemeDidChange")

    /// nil until a config arrives: readers then draw the Ghostties pair.
    @Published private(set) var current: ChromeTheme?
    /// Whether `current` is the Ghostties pair (so DialKit overrides apply).
    private(set) var isGhostties = true
    private var lastKey: [Int]?

    /// Resolve and publish the theme for the terminal's colours. A no-op
    /// when they haven't changed, so a reload that leaves the colours alone
    /// re-renders nothing.
    func update(background: NSColor, foreground: NSColor) {
        let key = Oklab.bytes(background) + Oklab.bytes(foreground)
        guard key != lastKey else { return }
        lastKey = key
        isGhostties = ChromeTheme.catalogScheme(background: background, foreground: foreground) != nil
        current = ChromeTheme.resolve(background: background, foreground: foreground)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Read the resolved terminal colours off an app-level config.
    func update(config: Ghostty.Config) {
        update(background: NSColor(config.backgroundColor), foreground: NSColor(config.foregroundColor))
    }

    /// Back to "no config yet" (a test that publishes a theme restores this).
    func reset() {
        lastKey = nil
        isGhostties = true
        current = nil
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// `@Environment(\.colorScheme)` for a view that draws chrome tokens: the
/// same value, plus a dependency on `ChromeThemeStore`, so the view redraws
/// when the theme changes without a light/dark flip (one dark theme to
/// another).
@propertyWrapper
struct ChromeScheme: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = ChromeThemeStore.shared

    var wrappedValue: ColorScheme { scheme }
}

/// sRGB <-> OKLab and WCAG contrast, for the derivation.
private struct Oklab {
    var l: Double
    var a: Double
    var b: Double

    typealias RGB = [Double]
    static let black: RGB = [0, 0, 0]
    static let white: RGB = [1, 1, 1]
    /// Searched floors sit this far above the stated floor, so a reader
    /// with a slightly different luminance formula still sees it cleared.
    static let margin = 0.02

    static func srgb(_ color: NSColor) -> RGB {
        let c = color.usingColorSpace(.sRGB) ?? color
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
    }

    static func bytes(_ color: NSColor) -> [Int] {
        srgb(color).map { Int(($0 * 255).rounded()) }
    }

    static func color(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb[0]), green: CGFloat(rgb[1]), blue: CGFloat(rgb[2]), alpha: 1)
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ color: NSColor) { self.init(Oklab.srgb(color)) }

    init(_ rgb: RGB) {
        let r = Oklab.linear(rgb[0]), g = Oklab.linear(rgb[1]), bl = Oklab.linear(rgb[2])
        let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    /// Back to sRGB, clamped into gamut.
    var srgb: RGB {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return [
            Oklab.gamma(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
            Oklab.gamma(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
            Oklab.gamma(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S),
        ]
    }

    /// `from` mixed toward `to` by `t`, in OKLab.
    static func mix(_ from: RGB, _ to: RGB, _ t: Double) -> RGB {
        let p = Oklab(from), q = Oklab(to)
        return Oklab(l: p.l + (q.l - p.l) * t, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t).srgb
    }

    /// `over` at `alpha` flattened onto `base`, in sRGB (how the layers draw).
    static func flatten(_ over: RGB, alpha: Double, on base: RGB) -> RGB {
        zip(over, base).map { $1 + ($0 - $1) * alpha }
    }

    static func luminance(_ c: RGB) -> Double {
        0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
    }

    static func contrast(_ x: RGB, _ y: RGB) -> Double {
        let (lx, ly) = (luminance(x), luminance(y))
        return (max(lx, ly) + 0.05) / (min(lx, ly) + 0.05)
    }

    /// Binary search along `from` -> `to` for a mix that passes: the
    /// smallest passing `t` (`smallest`: move only as far as needed) or the
    /// largest (go as far as allowed). Contrast moves monotonically along
    /// both searches. If no mix passes, the end that does best: `to` when
    /// searching for the smallest, `from` otherwise.
    static func search(from: RGB, toward to: RGB, smallest: Bool, passes: (RGB) -> Bool) -> RGB {
        if smallest {
            if passes(from) { return from }
            if !passes(to) { return to }
            var (lo, hi) = (0.0, 1.0)
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if passes(mix(from, to, mid)) { hi = mid } else { lo = mid }
            }
            return mix(from, to, hi)
        }
        if !passes(from) { return from }
        var (lo, hi) = (0.0, 1.0)
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if passes(mix(from, to, mid)) { lo = mid } else { hi = mid }
        }
        return mix(from, to, lo)
    }
}
