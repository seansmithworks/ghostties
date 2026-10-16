import AppKit
import Foundation
import Testing
@testable import Ghostty

/// GATE for the Settings > Appearance System / Light / Dark switch.
/// Pure and model tests only: an injected `UserDefaults` suite, no window,
/// no NSApp mutation, no real config.
///
/// API the builder must add (names are the contract):
///
///     enum GhosttiesAppearanceMode: String, CaseIterable {
///         case system, light, dark
///         static let key = "ghostties.appearance.mode"
///         static func stored(in: UserDefaults) -> GhosttiesAppearanceMode
///             // missing or unknown value reads as .system
///         func store(in: UserDefaults)    // writes rawValue under `key`
///         static func resolvedAppearanceName(
///             configWindowTheme: String?, mode: GhosttiesAppearanceMode
///         ) -> NSAppearance.Name?
///             // config light/dark win; ghostty -> nil (caller keeps existing
///             // Ghostty behaviour); nil/auto/system -> the mode decides
///             // (.system nil, .light .aqua, .dark .darkAqua).
///     }
///     // AppearanceSettingsModel gains, and init gets a defaulted seam for
///     // the config's window-theme (production default reads the running
///     // app's config, as refresh() does today):
///     init(defaults: UserDefaults = ..., windowTheme: @escaping () -> String? = { ... })
///     var mode: GhosttiesAppearanceMode { get set }  // backed by `defaults`
///     var modeLockedByConfig: Bool { get }           // window-theme light/dark/ghostty
struct AppearanceModeSwitchTests {
    private func suite() -> (UserDefaults, () -> Void) {
        let name = "ghostties.tests.appearance-mode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: - Storage

    @Test func keyIsStable() {
        #expect(GhosttiesAppearanceMode.key == "ghostties.appearance.mode")
    }

    @Test func missingValueReadsSystem() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        #expect(GhosttiesAppearanceMode.stored(in: defaults) == .system)
    }

    @Test func unknownValueReadsSystem() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        defaults.set("sepia", forKey: "ghostties.appearance.mode")
        #expect(GhosttiesAppearanceMode.stored(in: defaults) == .system)
    }

    @Test(arguments: [GhosttiesAppearanceMode.system, .light, .dark])
    func storeRoundTrips(_ mode: GhosttiesAppearanceMode) {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        mode.store(in: defaults)
        #expect(GhosttiesAppearanceMode.stored(in: defaults) == mode)
        #expect(defaults.string(forKey: "ghostties.appearance.mode") == mode.rawValue)
    }

    // MARK: - Resolver

    @Test(arguments: [GhosttiesAppearanceMode.system, .light, .dark])
    func configLightWinsOverEveryMode(_ mode: GhosttiesAppearanceMode) {
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: "light", mode: mode) == .aqua)
    }

    @Test(arguments: [GhosttiesAppearanceMode.system, .light, .dark])
    func configDarkWinsOverEveryMode(_ mode: GhosttiesAppearanceMode) {
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: "dark", mode: mode) == .darkAqua)
    }

    @Test(arguments: [GhosttiesAppearanceMode.system, .light, .dark])
    func configGhosttyLeavesItToGhostty(_ mode: GhosttiesAppearanceMode) {
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: "ghostty", mode: mode) == nil)
    }

    @Test(arguments: [nil, "auto", "system"] as [String?])
    func modeDecidesWhenConfigDoesNot(_ theme: String?) {
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: theme, mode: .system) == nil)
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: theme, mode: .light) == .aqua)
        #expect(GhosttiesAppearanceMode.resolvedAppearanceName(configWindowTheme: theme, mode: .dark) == .darkAqua)
    }

    // MARK: - Model

    @MainActor
    @Test func modelDefaultsToSystem() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = AppearanceSettingsModel(defaults: defaults, windowTheme: { nil })
        #expect(model.mode == .system)
    }

    @MainActor
    @Test func modelModeReadsStoredValue() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        GhosttiesAppearanceMode.dark.store(in: defaults)
        let model = AppearanceSettingsModel(defaults: defaults, windowTheme: { nil })
        #expect(model.mode == .dark)
    }

    @MainActor
    @Test func modelModeSetPersistsToInjectedSuite() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let standardBefore = UserDefaults.standard.string(forKey: "ghostties.appearance.mode")
        let model = AppearanceSettingsModel(defaults: defaults, windowTheme: { nil })
        model.mode = .light
        #expect(model.mode == .light)
        #expect(GhosttiesAppearanceMode.stored(in: defaults) == .light)
        #expect(UserDefaults.standard.string(forKey: "ghostties.appearance.mode") == standardBefore)
    }

    @MainActor
    @Test(arguments: ["light", "dark", "ghostty"])
    func modeLockedWhenConfigSetsWindowTheme(_ theme: String) {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = AppearanceSettingsModel(defaults: defaults, windowTheme: { theme })
        #expect(model.modeLockedByConfig)
    }

    @MainActor
    @Test(arguments: [nil, "auto", "system"] as [String?])
    func modeUnlockedOtherwise(_ theme: String?) {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = AppearanceSettingsModel(defaults: defaults, windowTheme: { theme })
        #expect(!model.modeLockedByConfig)
    }
}
