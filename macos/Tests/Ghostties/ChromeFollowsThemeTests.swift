import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// GATE for appearance-themes slice 2: the chrome follows the terminal theme.
///
/// Every case loads a real config through `Ghostty.Config.loadConfig`
/// (`TemporaryConfig`), reads the resolved `background` / `foreground`, and
/// hands them to the API the builder must add:
///
///     ChromeTheme.resolve(background: NSColor, foreground: NSColor) -> ChromeTheme
///     ChromeTheme.derived(background: NSColor, foreground: NSColor) -> ChromeTheme
///
/// - `resolve`: if (background, foreground) equals a Ghostties catalog theme
///   file's pair (today Ghostties Light / Dark), return `ChromeTheme.ghostties`
///   for that polarity unchanged; otherwise return `derived`.
/// - `derived`: plan "Derivation for Custom and third-party themes".
///   canvas = background; polarity by contrast against black vs white;
///   chrome, ink, inkSecondary and shadow derived; tileInk / tileFillBase
///   follow ink. No new `ChromeTheme` fields.
///
/// Floors: `inkSecondary` >= 4.6:1 on chrome, the group card
/// (`lifted(.container)`) and chrome under ink at `.row` / `.tile`; `ink`
/// >= 7:1 on canvas, chrome and the group card. The Ghostties values are
/// referenced from `ChromeTheme.ghostties` (frozen by `ChromeColorGoldenTests`),
/// never restated here.
struct ChromeFollowsThemeTests {
    // MARK: - Helpers

    private func color(_ key: String, of config: Ghostty.Config) throws -> NSColor {
        let cfg = try #require(config.config)
        var c = ghostty_config_color_s()
        #expect(ghostty_config_get(cfg, &c, key, UInt(key.lengthOfBytes(using: .utf8))), "\(key)")
        return NSColor(
            srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1
        )
    }

    /// Load `text` through the real loader and resolve the chrome from the
    /// terminal's resulting background and foreground.
    private func resolved(_ text: String) throws -> (theme: ChromeTheme, background: NSColor) {
        let config = try TemporaryConfig(text)
        #expect(config.errors.isEmpty, "\(config.errors)")
        let bg = try color("background", of: config)
        let fg = try color("foreground", of: config)
        return (ChromeTheme.resolve(background: bg, foreground: fg), bg)
    }

    private func rgb(_ ns: NSColor) -> [Double] {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Double($0) }
    }

    private func sameColor(_ a: NSColor, _ b: NSColor, tolerance: Double = 0.5 / 255) -> Bool {
        zip(rgb(a), rgb(b)).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private func luminance(_ ns: NSColor) -> Double {
        let l = rgb(ns).map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// `over` flattened onto `base` at `alpha`.
    private func flatten(_ over: NSColor, alpha: Double, on base: NSColor) -> NSColor {
        let o = rgb(over), b = rgb(base)
        return NSColor(
            srgbRed: CGFloat(b[0] + (o[0] - b[0]) * alpha),
            green: CGFloat(b[1] + (o[1] - b[1]) * alpha),
            blue: CGFloat(b[2] + (o[2] - b[2]) * alpha),
            alpha: 1
        )
    }

    /// The sidebar's text backdrops: the chrome, the expanded group card, and
    /// the chrome under a row / tile ink wash.
    private func backdrops(_ t: ChromeTheme) -> [(String, NSColor)] {
        [
            ("chrome", t.chrome),
            ("group card", t.lifted(.container)),
            ("row", flatten(t.ink, alpha: ChromeTheme.Step.row.opacity(t.polarity), on: t.chrome)),
            ("tile", flatten(t.ink, alpha: ChromeTheme.Step.tile.opacity(t.polarity), on: t.chrome)),
        ]
    }

    private func expectFollows(_ theme: ChromeTheme, canvas: NSColor, polarity: ChromeTheme.Polarity) {
        #expect(theme.polarity == polarity)
        #expect(sameColor(theme.canvas, canvas), "canvas \(rgb(theme.canvas)) != terminal bg \(rgb(canvas))")
        // Derived from the canvas, not equal to it: chrome sits one step off.
        #expect(!sameColor(theme.chrome, theme.canvas))
        if polarity == .dark {
            #expect(luminance(theme.chrome) > luminance(theme.canvas), "dark chrome lifts off the canvas")
        } else {
            #expect(luminance(theme.chrome) < luminance(theme.canvas), "light chrome sinks below the canvas")
        }
        for (name, backdrop) in backdrops(theme) {
            #expect(contrast(theme.inkSecondary, backdrop) >= 4.6, "inkSecondary on \(name)")
        }
        for (name, backdrop) in [("canvas", theme.canvas), ("chrome", theme.chrome), ("group card", theme.lifted(.container))] {
            #expect(contrast(theme.ink, backdrop) >= 7, "ink on \(name)")
        }
    }

    // MARK: - 1. Default

    /// No user theme: the Ghostties pair, field for field.
    @Test func defaultConfigResolvesToTheShippedGhosttiesTheme() throws {
        let (theme, _) = try resolved("")
        let want = ChromeTheme.ghostties(.light)
        #expect(theme.polarity == want.polarity)
        for (name, got, expected) in [
            ("canvas", theme.canvas, want.canvas), ("chrome", theme.chrome, want.chrome),
            ("ink", theme.ink, want.ink), ("inkSecondary", theme.inkSecondary, want.inkSecondary),
            ("shadow", theme.shadow, want.shadow), ("tileInk", theme.tileInk, want.tileInk),
            ("tileFillBase", theme.tileFillBase, want.tileFillBase),
        ] {
            #expect(sameColor(got, expected, tolerance: 0.0005), "\(name)")
        }
    }

    @Test func ghosttiesDarkConfigResolvesToTheShippedDarkTheme() throws {
        let (theme, _) = try resolved("theme = Ghostties Dark")
        let want = ChromeTheme.ghostties(.dark)
        #expect(theme.polarity == .dark)
        #expect(sameColor(theme.chrome, want.chrome, tolerance: 0.0005))
        #expect(sameColor(theme.canvas, want.canvas, tolerance: 0.0005))
        #expect(sameColor(theme.inkSecondary, want.inkSecondary, tolerance: 0.0005))
        #expect(sameColor(theme.shadow, want.shadow, tolerance: 0.0005))
    }

    // MARK: - 2/3. Bundled third-party themes

    @Test func draculaMakesDarkChromeFromItsBackground() throws {
        let (theme, bg) = try resolved("theme = Dracula")
        expectFollows(theme, canvas: bg, polarity: .dark)
    }

    @Test func catppuccinLatteMakesLightChromeFromItsBackground() throws {
        let (theme, bg) = try resolved("theme = Catppuccin Latte")
        expectFollows(theme, canvas: bg, polarity: .light)
    }

    /// Polarity is the theme's, not the Mac's: each theme loads with no
    /// appearance input at all and still lands on its own side.
    @Test(arguments: [
        ("Dracula", ChromeTheme.Polarity.dark),
        ("Catppuccin Mocha", .dark),
        ("Catppuccin Latte", .light),
        ("Gruvbox Light", .light),
    ])
    func bundledThemePolarityFollowsTheBackground(name: String, polarity: ChromeTheme.Polarity) throws {
        let (theme, bg) = try resolved("theme = \(name)")
        expectFollows(theme, canvas: bg, polarity: polarity)
    }

    // MARK: - 4. Explicit background

    /// Only `background =` set; the foreground stays the default theme's
    /// dark-on-light text, so the derivation must still reach the ink floor.
    @Test func explicitDarkBackgroundMovesTheCanvas() throws {
        let (theme, bg) = try resolved("background = #102030")
        expectFollows(theme, canvas: bg, polarity: .dark)
        #expect(sameColor(theme.canvas, NSColor(srgbRed: 0x10 / 255, green: 0x20 / 255, blue: 0x30 / 255, alpha: 1)))
    }

    @Test func explicitLightBackgroundMovesTheCanvas() throws {
        let (theme, bg) = try resolved("background = #e8f0ff")
        expectFollows(theme, canvas: bg, polarity: .light)
    }

    // MARK: - 5. No new tokens

    @Test func derivedThemeExposesOnlyTheExistingFields() throws {
        let (theme, _) = try resolved("theme = Dracula")
        let fields = Set(Mirror(reflecting: theme).children.compactMap(\.label))
        #expect(fields == [
            "polarity", "canvas", "chrome", "ink", "inkSecondary", "shadow", "tileInk", "tileFillBase",
        ])
    }
}
