#if DEBUG
import DialkitmacOS
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The tray glass's blur and palette dials, set the way the inspector sets
/// them (through the "Glass & Layout" panel's values), persist their own
/// key per appearance and reach `SidebarDialTuning.trayGlass(for:)`.
@MainActor
struct TrayGlassDialsTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let scheme: ColorScheme
        let key: String
        let set: (inout SidebarDialKitTuningModel) -> Void
        let read: (TrayGlassStyle.Look) -> AnyHashable
        let expected: AnyHashable
        var testDescription: String { "\(name) (\(scheme == .dark ? "dark" : "light"))" }
    }

    private static let cases: [Case] = [
        Case(name: "Backdrop material", scheme: .light, key: "ghostties.sidebarDial.trayGlass.backdropMaterial",
             set: { $0.glassLight.backdropMaterial = "thick" }, read: { $0.backdropMaterial }, expected: TrayGlassStyle.BackdropMaterial.thick),
        Case(name: "Backdrop opacity", scheme: .light, key: "ghostties.sidebarDial.trayGlass.backdropOpacity",
             set: { $0.glassLight.backdropOpacity = 0.55 }, read: { $0.backdropOpacity }, expected: 0.55),
        Case(name: "Surface blur", scheme: .light, key: "ghostties.sidebarDial.trayGlass.surfaceBlur",
             set: { $0.glassLight.surfaceBlur = 6.5 }, read: { $0.surfaceBlur }, expected: CGFloat(6.5)),
        Case(name: "Backdrop material", scheme: .dark, key: "ghostties.sidebarDial.trayGlass.dark.backdropMaterial",
             set: { $0.glassDark.backdropMaterial = "ultraThin" }, read: { $0.backdropMaterial }, expected: TrayGlassStyle.BackdropMaterial.ultraThin),
        Case(name: "Backdrop opacity", scheme: .dark, key: "ghostties.sidebarDial.trayGlass.dark.backdropOpacity",
             set: { $0.glassDark.backdropOpacity = 0.3 }, read: { $0.backdropOpacity }, expected: 0.3),
        Case(name: "Surface blur", scheme: .dark, key: "ghostties.sidebarDial.trayGlass.dark.surfaceBlur",
             set: { $0.glassDark.surfaceBlur = 3 }, read: { $0.surfaceBlur }, expected: CGFloat(3)),
    // Every palette but the default (both appearances default to `signal`
    // since the 2026-10-11 bake), so each case is a real change.
    ] + TrayGlassStyle.ChromaticPalette.allCases.filter {
        $0 != TrayGlassStyle.light.chromaticPalette && $0 != TrayGlassStyle.dark.chromaticPalette
    }.flatMap { palette in [
        Case(name: "Palette \(palette.rawValue)", scheme: .light, key: "ghostties.sidebarDial.trayGlass.chromaticPalette",
             set: { $0.glassLight.chromaticPalette = palette.rawValue }, read: { $0.chromaticPalette }, expected: palette),
        Case(name: "Palette \(palette.rawValue)", scheme: .dark, key: "ghostties.sidebarDial.trayGlass.dark.chromaticPalette",
             set: { $0.glassDark.chromaticPalette = palette.rawValue }, read: { $0.chromaticPalette }, expected: palette),
    ] }

    @Test(arguments: cases)
    func dialRoundTripsThroughItsReader(_ c: Case) {
        withDials({ _ in }) {
            let defaults = SidebarDialTuning.store
            let other: ColorScheme = c.scheme == .dark ? .light : .dark
            let otherBefore = SidebarDialTuning.trayGlass(for: other, defaults: defaults)
            let coordinator = SidebarDialKitCoordinator(defaults: defaults, onChange: {})
            #expect(defaults.object(forKey: c.key) == nil)
            #expect(c.read(SidebarDialTuning.trayGlass(for: c.scheme, defaults: defaults)) != c.expected)

            c.set(&coordinator.state.values)

            #expect(defaults.object(forKey: c.key) != nil, "\(c.name) persisted no key")
            #expect(c.read(SidebarDialTuning.trayGlass(for: c.scheme, defaults: defaults)) == c.expected)
            // Light and dark are separate dials.
            #expect(SidebarDialTuning.trayGlass(for: other, defaults: defaults) == otherBefore)
        }
    }

    /// Launch arguments (`-<key> <value>`) arrive as strings; the reader
    /// takes them as numbers and choices too.
    @Test func launchArgumentStringsRead() {
        withDials({
            $0.set("regular", forKey: SidebarDialTuning.lightGlassKeys.backdropMaterial)
            $0.set("0.4", forKey: SidebarDialTuning.lightGlassKeys.backdropOpacity)
            $0.set("8", forKey: SidebarDialTuning.lightGlassKeys.surfaceBlur)
        }) {
            let look = SidebarDialTuning.trayGlass(for: .light)
            #expect(look.backdropMaterial == .regular)
            #expect(look.backdropOpacity == 0.4)
            #expect(look.surfaceBlur == 8)
        }
    }

    /// "Reset all panels" clears the new keys with the rest.
    @Test func newKeysAreInTheResetSet() {
        for keys in [SidebarDialTuning.lightGlassKeys, SidebarDialTuning.darkGlassKeys] {
            for key in [keys.backdropMaterial, keys.backdropOpacity, keys.surfaceBlur] {
                #expect(SidebarDialTuning.allKeys.contains(key))
            }
        }
    }

    /// Every token palette resolves in both appearances; in dark its
    /// neutral stops are the dark chrome/canvas greys, never the light creams.
    @Test(arguments: [TrayGlassStyle.ChromaticPalette.ember, .chrome, .signal])
    func darkPalettesUseDarkNeutrals(_ palette: TrayGlassStyle.ChromaticPalette) {
        let light = TrayGlassStyle.chromaticColors(palette, for: .light)
        let dark = TrayGlassStyle.chromaticColors(palette, for: .dark)
        #expect(!light.isEmpty && !dark.isEmpty)
        #expect(!dark.contains(Color(WorkspaceLayout.chromeBackgroundLight)))
        #expect(!dark.contains(Color(WorkspaceLayout.canvasBackgroundLight)))
    }
}
#endif
