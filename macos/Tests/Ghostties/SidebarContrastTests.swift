import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Sidebar secondary text clears WCAG AA (4.5:1) on the surfaces it sits on,
/// in light and dark (beta.26, sidebar contrast option 2). Every colour comes
/// from the shipped tokens: `textSecondary`, the chrome, and the project
/// group card's fill (`RailProjectColumn.columnFill`) composited over the
/// chrome at its own alpha.
@MainActor
struct SidebarContrastTests {
    private typealias RGB = (r: Double, g: Double, b: Double)

    private func rgba(_ color: NSColor) throws -> (rgb: RGB, alpha: Double) {
        let c = try #require(color.usingColorSpace(.sRGB))
        return ((Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)), Double(c.alphaComponent))
    }

    /// `fill` at its own alpha over the opaque `base`, flattened.
    private func composite(_ fill: Color, over base: NSColor) throws -> RGB {
        let (f, a) = try rgba(NSColor(fill))
        let (b, _) = try rgba(base)
        return (f.r * a + b.r * (1 - a), f.g * a + b.g * (1 - a), f.b * a + b.b * (1 - a))
    }

    private func luminance(_ c: RGB) -> Double {
        let lin = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The approved option's ratios (light / dark), rounded down: secondary
    /// on the card 5.88 / 5.66, on the chrome 5.40 / 6.38, the status glyph
    /// on the selected chip 4.71 / 4.13 (4.69 / 4.16 composited unrounded,
    /// as here). AA (4.5) is the hard floor; these hold the margin Sean
    /// picked, so a token drifting back toward the pre-beta.26 values fails
    /// here even while it still clears AA.
    private func floors(_ scheme: ColorScheme) -> (card: Double, chrome: Double, chip: Double) {
        scheme == .dark ? (5.6, 6.3, 4.1) : (5.8, 5.35, 4.65)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func secondaryTextClearsAAOnCardAndChrome(_ scheme: ColorScheme) throws {
        try withDials {
            let chrome = scheme == .dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight
            let secondary = scheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
            let text = try rgba(NSColor(secondary)).rgb
            let card = try composite(RailProjectColumn.columnFill(scheme), over: chrome)
            let cardColor = NSColor(srgbRed: card.r, green: card.g, blue: card.b, alpha: 1)
            let chipInk = RailProjectColumn.tintInk(scheme).opacity(RailProjectColumn.selectedChipTintOpacity)
            let chip = try composite(chipInk, over: cardColor)
            let onCard = contrast(text, card)
            let onChrome = contrast(text, try rgba(chrome).rgb)
            let onChip = contrast(text, chip)
            let floor = floors(scheme)
            #expect(onCard >= 4.5, "secondary on group card \(scheme): \(onCard)")
            #expect(onChrome >= 4.5, "secondary on chrome \(scheme): \(onChrome)")
            #expect(onCard >= floor.card, "secondary on group card \(scheme): \(onCard), approved \(floor.card)")
            #expect(onChrome >= floor.chrome, "secondary on chrome \(scheme): \(onChrome), approved \(floor.chrome)")
            #expect(onChip >= floor.chip, "status glyph on selected chip \(scheme): \(onChip), approved \(floor.chip)")
        }
    }
}
