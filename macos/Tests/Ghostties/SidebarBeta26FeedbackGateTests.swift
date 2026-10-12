import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Gate for Sean's two beta.26 Demo-check changes. Written red, before the
/// fixes: a builder makes them pass without editing this file.
///
/// A. The closed-sidebar hover bar (overlay mode, `sidebarOverlayBackground`)
///    sits on the sidebar's own chrome, not the near-white terminal/canvas
///    card, and casts the canvas card's shadow onto the terminal.
/// B. An empty project's header (name, count) and tile glyph clear WCAG AA
///    (4.5:1), not the tertiary-label tier.
@MainActor
struct SidebarBeta26FeedbackGateTests {
    private typealias RGB = (r: Double, g: Double, b: Double)

    private func rgba(_ color: NSColor) throws -> (rgb: RGB, alpha: Double) {
        let c = try #require(color.usingColorSpace(.sRGB))
        return ((Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)), Double(c.alphaComponent))
    }

    /// A dynamic colour resolved under the named appearance.
    private func resolved(_ color: NSColor, _ scheme: ColorScheme) throws -> (rgb: RGB, alpha: Double) {
        let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        var out: (rgb: RGB, alpha: Double)?
        appearance.performAsCurrentDrawingAppearance { out = try? rgba(color) }
        return try #require(out)
    }

    private func over(_ top: (rgb: RGB, alpha: Double), _ base: RGB) -> RGB {
        (top.rgb.r * top.alpha + base.r * (1 - top.alpha),
         top.rgb.g * top.alpha + base.g * (1 - top.alpha),
         top.rgb.b * top.alpha + base.b * (1 - top.alpha))
    }

    private func luminance(_ c: RGB) -> Double {
        let lin = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func chrome(_ scheme: ColorScheme) -> NSColor {
        scheme == .dark ? WorkspaceLayout.chromeBackgroundDark : WorkspaceLayout.chromeBackgroundLight
    }

    // MARK: A. Hover bar

    /// The fill is the pinned sidebar's chrome (light `#F0E9E6`, dark
    /// `chromeBackgroundDark`), not the canvas card (`#FAF7F3`) or the
    /// terminal's own background it follows today.
    // GATE: builder adds `WorkspaceLayout.hoverBarFill(isDark:) -> NSColor`,
    // used by `sidebarOverlayBackground` in both mode and `applyChromeColor`.
    @Test(arguments: [ColorScheme.light, .dark])
    func hoverBarFillIsTheSidebarChrome(_ scheme: ColorScheme) throws {
        let fill = try rgba(WorkspaceLayout.hoverBarFill(isDark: scheme == .dark))
        let want = try rgba(chrome(scheme))
        #expect(fill.alpha == 1, "hover bar fill must be opaque, \(scheme)")
        #expect(abs(fill.rgb.r - want.rgb.r) < 0.002 && abs(fill.rgb.g - want.rgb.g) < 0.002 && abs(fill.rgb.b - want.rgb.b) < 0.002,
                "hover bar fill \(fill.rgb) is not the pinned sidebar chrome \(want.rgb), \(scheme)")
    }

    /// The shadow is the canvas card's shadow (colour, blur, opacity), live
    /// and visible: it floats above the terminal.
    // GATE: builder adds `WorkspaceLayout.hoverBarShadowColor: CGColor`,
    // `.hoverBarShadowRadius: CGFloat`, `.hoverBarShadowOpacity: Float`, each
    // defined as the matching `canvasShadow*` token and applied to the
    // overlay's shadow host (offset stays a rightward cast).
    @Test func hoverBarShadowIsTheCanvasCardShadow() {
        #expect(WorkspaceLayout.hoverBarShadowRadius > 0)
        #expect(WorkspaceLayout.hoverBarShadowOpacity > 0)
        #expect(WorkspaceLayout.hoverBarShadowRadius == WorkspaceLayout.canvasShadowRadius,
                "hover bar blur \(WorkspaceLayout.hoverBarShadowRadius) vs canvas \(WorkspaceLayout.canvasShadowRadius)")
        #expect(WorkspaceLayout.hoverBarShadowOpacity == WorkspaceLayout.canvasShadowOpacity,
                "hover bar opacity \(WorkspaceLayout.hoverBarShadowOpacity) vs canvas \(WorkspaceLayout.canvasShadowOpacity)")
        #expect(WorkspaceLayout.hoverBarShadowColor == WorkspaceLayout.canvasShadowColor)
    }

    // MARK: B. Empty projects

    /// Header name, count and chevron ink (`emptyProjectForeground`) over the
    /// chrome and over the group card on it.
    @Test(arguments: [ColorScheme.light, .dark])
    func emptyProjectHeaderTextClearsAA(_ scheme: ColorScheme) throws {
        try withDials {
            let ink = try resolved(NSColor(WorkspaceLayout.emptyProjectForeground), scheme)
            let chromeRGB = try rgba(chrome(scheme)).rgb
            let card = over(try rgba(NSColor(RailProjectColumn.columnFill(scheme))), chromeRGB)
            for (name, base) in [("chrome", chromeRGB), ("group card", card)] {
                // Text alpha is composited over its surface before measuring.
                let text = over(ink, base)
                let ratio = contrast(text, base)
                #expect(ratio >= 4.5, "empty project name/count on \(name) \(scheme): \(ratio)")
            }
        }
    }

    /// The tile's letter (`emptyProjectForeground`) against the tile's own
    /// tint fill, which sits on the chrome or the group card.
    @Test(arguments: [ColorScheme.light, .dark])
    func emptyProjectTileGlyphClearsAA(_ scheme: ColorScheme) throws {
        try withDials {
            let ink = try resolved(NSColor(WorkspaceLayout.emptyProjectForeground), scheme)
            let chromeRGB = try rgba(chrome(scheme)).rgb
            let card = over(try rgba(NSColor(RailProjectColumn.columnFill(scheme))), chromeRGB)
            // `ProjectMonogramTileFace.tint`, unselected: white 7% dark,
            // (40,34,30) at `RailProjectTile.tintOpacity` light.
            let tintColor = scheme == .dark
                ? Color.white.opacity(0.07)
                : Color(red: 40 / 255, green: 34 / 255, blue: 30 / 255).opacity(RailProjectTile.tintOpacity)
            let tint = try rgba(NSColor(tintColor))
            for (name, base) in [("chrome", chromeRGB), ("group card", card)] {
                let tile = over(tint, base)
                let glyph = over(ink, tile)
                let ratio = contrast(glyph, tile)
                #expect(ratio >= 4.5, "empty project tile glyph on tile over \(name) \(scheme): \(ratio)")
            }
        }
    }
}
