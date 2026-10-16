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
/// Today only the Ghostties pair exists (`ChromeTheme.ghostties`); the
/// appearance still picks it, a theme chosen by the terminal is slice 2.
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
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("ghostty/themes/\(name)"),
              let text = try? String(contentsOf: dir, encoding: .utf8),
              let color = background(in: text)
        else { return .windowBackgroundColor }
        return color
    }

    static func background(in text: String) -> NSColor? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "background" else { continue }
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
