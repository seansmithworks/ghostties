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
        scheme == .dark ? ChromeTheme.ghostties(.dark).chrome : ChromeTheme.ghostties(.light).chrome
    }

    // MARK: A. Hover bar

    /// The fill is the pinned sidebar's chrome (light `#F0E9E6`, dark
    /// `chromeBackgroundDark`), not the canvas card (`#FAF7F3`) or the
    /// terminal's own background it follows today.
    // GATE: builder adds `WorkspaceLayout.hoverBarFill(isDark:) -> NSColor`,
    // used by `sidebarOverlayBackground` in both mode and `applyChromeColor`.
    @Test(arguments: [ColorScheme.light, .dark])
    func hoverBarFillIsTheSidebarChrome(_ scheme: ColorScheme) throws {
        let fill = try rgba(ChromeTheme.ghostties(scheme).chrome)
        let want = try rgba(chrome(scheme))
        #expect(fill.alpha == 1, "hover bar fill must be opaque, \(scheme)")
        #expect(abs(fill.rgb.r - want.rgb.r) < 0.002 && abs(fill.rgb.g - want.rgb.g) < 0.002 && abs(fill.rgb.b - want.rgb.b) < 0.002,
                "hover bar fill \(fill.rgb) is not the pinned sidebar chrome \(want.rgb), \(scheme)")
    }

    /// Round 2 (Sean, beta.26): the hover bar's shadow is lighter and wider
    /// than the beta.26 canvas card's, on the hover bar only.
    @Test func hoverBarShadowIsLighterAndWiderThanTheCanvasCard() {
        #expect(WorkspaceLayout.hoverBarShadowRadius == 16,
                "hover bar blur \(WorkspaceLayout.hoverBarShadowRadius)")
        #expect(abs(WorkspaceLayout.hoverBarShadowOpacity - 0.1275) < 0.0001,
                "hover bar opacity \(WorkspaceLayout.hoverBarShadowOpacity)")
        // Black, its own constant since the canvas card's shadow went
        // per-appearance in beta.27 (CanvasDialsTests holds those values).
        #expect(WorkspaceLayout.hoverBarShadowColor == NSColor.black.cgColor)
    }

    /// Round 2 (Sean, beta.26): in the hover bar each tray pill keeps 12pt on
    /// three corners; only the corner in the bar's outer corner nests (left
    /// pill bottom-left, right pill bottom-right: 12 - 8 = 4 at the default
    /// margin).
    // GATE: builder adds `TrayGlassStyle.hoverBarPillCorners(side: HorizontalEdge)
    // -> (topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat)`
    // (.leading = Create pill, .trailing = Toggle pill), at the default margin.
    @Test func hoverBarPillsNestOnlyTheOuterCorner() {
        let left = TrayGlassStyle.hoverBarPillCorners(side: .leading)
        #expect(left.topLeading == 12 && left.topTrailing == 12 && left.bottomTrailing == 12,
                "left pill non-outer corners \(left)")
        #expect(left.bottomLeading == 4, "left pill outer corner \(left.bottomLeading)")

        let right = TrayGlassStyle.hoverBarPillCorners(side: .trailing)
        #expect(right.topLeading == 12 && right.topTrailing == 12 && right.bottomLeading == 12,
                "right pill non-outer corners \(right)")
        #expect(right.bottomTrailing == 4, "right pill outer corner \(right.bottomTrailing)")
    }

    /// Pinned and rail (.collapsed) pills keep their uniform radius (window 20 - margin 8).
    /// An isolated defaults suite, so Dev's dial values never leak in.
    @Test func pinnedAndRailPillRadiiAreUnchanged() throws {
        let name = "SidebarBeta26FeedbackGateTests.pillRadii"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SidebarDialTuning.trayCornerRadius(for: .pinned, defaults: defaults) == 12)
        #expect(SidebarDialTuning.trayCornerRadius(for: .collapsed, defaults: defaults) == 12)
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
            // (40,34,30) at `RailProjectTile.emptyTintOpacity` light: an empty
            // project's tile is lighter than a live one's.
            // GATE: builder adds RailProjectTile.emptyTintOpacity
            #expect(RailProjectTile.emptyTintOpacity < RailProjectTile.tintOpacity,
                    "empty tile tint must read quieter than a live project's")
            let tintColor = scheme == .dark
                ? Color.white.opacity(0.07)
                : Color(red: 40 / 255, green: 34 / 255, blue: 30 / 255).opacity(RailProjectTile.emptyTintOpacity)
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
