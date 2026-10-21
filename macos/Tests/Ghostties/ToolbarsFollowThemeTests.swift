import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// GATE for "toolbars follow the theme". Since the theme stack (#244-#248)
/// the canvas, sidebar and terminal follow the active theme, but the floating
/// toolbar pills (the tray's new-session / new-folder pill, the sidebar
/// toggle pill and the hover bar's pills, all drawn by `TrayGlassStyle`)
/// still lay literal `Color.white` in light, so on Gruvbox Light they read as
/// white blocks on cream chrome.
///
/// The contract the builder must add (no new colours: both values reuse
/// existing tokens):
///
///     ChromeTheme.trayFill: NSColor
///
///     TrayGlassStyle.glassTint(_ look: Look, for: ColorScheme, theme: ChromeTheme = .active(scheme)) -> Color?
///     TrayGlassStyle.surfaceFill(_ look: Look, for: ColorScheme, theme: ChromeTheme = .active(scheme)) -> Color
///
/// - `trayFill` is the pill's base fill. Ghostties Light: white (unchanged,
///   frozen by `ChromeColorGoldenTests`). Ghostties Dark: its `chrome`
///   (unchanged). Derived light themes: the theme's `canvas` (the raised
///   surface one step above the chrome, already a token). Derived dark
///   themes: the theme's `chrome`, as the dark pill already is.
/// - `glassTint` / `surfaceFill` lay `trayFill` at `look.tintOpacity` /
///   `look.surfaceOpacity` in both appearances, from the `theme` passed in
///   (the default stays the active theme, so call sites do not change).
///   The explicit parameter keeps these tests pure: no store, no window.
struct ToolbarsFollowThemeTests {
    private func srgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private func bytes(_ c: NSColor) -> [Int] {
        let s = c.usingColorSpace(.sRGB) ?? c
        return [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    /// RGBA bytes of a SwiftUI colour as drawn in `scheme`.
    private func rgba(_ color: Color, _ scheme: ColorScheme) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let s = NSColor(color).usingColorSpace(.sRGB)!
            out = [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent].map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    private func alpha(_ opacity: Double) -> Int { Int((opacity * 255).rounded()) }

    private let gruvboxLight = ChromeTheme.resolve(background: NSColor(srgbRed: 0xFB / 255.0, green: 0xF1 / 255.0, blue: 0xC7 / 255.0, alpha: 1),
                                                   foreground: NSColor(srgbRed: 0x3C / 255.0, green: 0x38 / 255.0, blue: 0x36 / 255.0, alpha: 1))
    private let dracula = ChromeTheme.resolve(background: NSColor(srgbRed: 0x28 / 255.0, green: 0x2A / 255.0, blue: 0x36 / 255.0, alpha: 1),
                                              foreground: NSColor(srgbRed: 0xF8 / 255.0, green: 0xF8 / 255.0, blue: 0xF2 / 255.0, alpha: 1))

    // MARK: Ghostties pair: no visual change

    @Test func ghosttiesLightTrayFillIsWhite() {
        #expect(bytes(ChromeTheme.ghostties(.light).trayFill) == [255, 255, 255])
    }

    @Test func ghosttiesDarkTrayFillIsItsChrome() {
        let dark = ChromeTheme.ghostties(.dark)
        #expect(bytes(dark.trayFill) == bytes(dark.chrome))
    }

    @Test func ghosttiesPairTrayLayersAreTodaysValues() {
        let light = TrayGlassStyle.light, dark = TrayGlassStyle.dark
        let lt = ChromeTheme.ghostties(.light), dt = ChromeTheme.ghostties(.dark)
        #expect(rgba(TrayGlassStyle.surfaceFill(light, for: .light, theme: lt), .light)
                == [255, 255, 255, alpha(light.surfaceOpacity)])
        #expect(TrayGlassStyle.glassTint(light, for: .light, theme: lt).map { rgba($0, .light) }
                == [255, 255, 255, alpha(light.tintOpacity)])
        let chrome = bytes(dt.chrome)
        #expect(rgba(TrayGlassStyle.surfaceFill(dark, for: .dark, theme: dt), .dark)
                == chrome + [alpha(dark.surfaceOpacity)])
        #expect(TrayGlassStyle.glassTint(dark, for: .dark, theme: dt).map { rgba($0, .dark) }
                == chrome + [alpha(dark.tintOpacity)])
    }

    // MARK: Derived themes: from the theme, not white / black

    @Test func gruvboxLightTrayFillIsItsCanvasNotWhite() {
        #expect(gruvboxLight.polarity == .light)
        #expect(bytes(gruvboxLight.trayFill) == bytes(gruvboxLight.canvas))
        #expect(bytes(gruvboxLight.trayFill) == bytes(srgb(0xFBF1C7)))
        #expect(bytes(gruvboxLight.trayFill) != [255, 255, 255])
    }

    @Test func draculaTrayFillIsItsChrome() {
        #expect(dracula.polarity == .dark)
        #expect(bytes(dracula.trayFill) == bytes(dracula.chrome))
    }

    @Test func gruvboxLightPillLayersAreTheCanvasAtTheLooksOpacities() {
        let look = TrayGlassStyle.light
        let canvas = bytes(gruvboxLight.canvas)
        #expect(rgba(TrayGlassStyle.surfaceFill(look, for: .light, theme: gruvboxLight), .light)
                == canvas + [alpha(look.surfaceOpacity)])
        #expect(TrayGlassStyle.glassTint(look, for: .light, theme: gruvboxLight).map { rgba($0, .light) }
                == canvas + [alpha(look.tintOpacity)])
    }

    @Test func draculaPillLayersAreTheChromeAtTheLooksOpacities() {
        let look = TrayGlassStyle.dark
        let chrome = bytes(dracula.chrome)
        #expect(rgba(TrayGlassStyle.surfaceFill(look, for: .dark, theme: dracula), .dark)
                == chrome + [alpha(look.surfaceOpacity)])
        #expect(TrayGlassStyle.glassTint(look, for: .dark, theme: dracula).map { rgba($0, .dark) }
                == chrome + [alpha(look.tintOpacity)])
    }
}
