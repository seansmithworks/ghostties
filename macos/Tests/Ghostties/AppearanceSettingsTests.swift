import AppKit
import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// GATE for appearance-themes slice 3: the Settings > Appearance pane model.
/// Every resolution case loads a real config through
/// `Ghostty.Config.loadConfig`; persistence uses an injected `UserDefaults`
/// suite (never the real domain, never setenv).
///
/// API the builder must add (names are the contract):
///
///     struct GhosttiesThemePicks: Equatable {
///         var light: String?          // theme name, nil = no pick for that side
///         var dark: String?
///         init(light: String? = nil, dark: String? = nil)
///         init(pair: GhosttiesThemeCatalog.Pair)       // a pair card sets both
///         static let none: GhosttiesThemePicks
///         var isEmpty: Bool
///         static let lightKey = "ghostties.theme.light"
///         static let darkKey = "ghostties.theme.dark"
///         static func stored(in: UserDefaults) -> GhosttiesThemePicks
///         func save(to: UserDefaults)  // nil side removes its key
///         static func clear(in: UserDefaults)
///     }
///     enum GhosttiesThemeCatalog {
///         struct Pair: Equatable { let name, light, dark: String }
///         static let ghostties: Pair   // "Ghostties" / "Ghostties Light" / "Ghostties Dark"
///     }
///     // GhosttiesConfigDefaults (existing `contents` / `fileURL()` unchanged)
///     static func overrideContents(picks: GhosttiesThemePicks) -> String?
///         // nil when picks.isEmpty, else exactly `theme = light:<L>,dark:<D>`;
///         // an unpicked side falls back to the Ghostties theme for that side.
///     static func overrideFileURL(picks: GhosttiesThemePicks) -> URL?
///     // Ghostty.Config.loadConfig(at:finalize:picks:) — new defaulted param
///     // `picks: GhosttiesThemePicks = .none`. When non-empty, the override
///     // file loads AFTER the user's config files / CLI args / includes and
///     // BEFORE finalize. App call sites pass `.stored(in: <app suite>)`.
///     enum GhosttiesThemeProbe {
///         enum Kind { case none, themeOnly, explicitColors }
///         struct Result: Equatable { let kind: Kind; let themeName: String? }
///         static func probe(configPath: String?) -> Result
///             // nil path = default user files. explicitColors = any explicit
///             // `background`, `foreground` or `palette` line; themeOnly = a
///             // `theme =` line and none of those; themeName is the line's
///             // value verbatim (display only).
///     }
///     enum GhosttiesAppearanceState: Equatable {
///         case ghostties                              // no pick, no user theme
///         case custom(themeName: String)              // no pick, user theme
///         case picked(light: String, dark: String)    // pick set (unpicked side = Ghostties)
///         case setByConfig                            // explicit colour keys; beats any pick
///         static func resolve(configPath: String?, picks: GhosttiesThemePicks) -> GhosttiesAppearanceState
///     }
struct AppearanceSettingsTests {
    // MARK: - Helpers

    /// Same shape as `TemporaryConfig`, but loads with picks.
    private final class PickedConfig: Ghostty.Config {
        let file: URL
        init(_ text: String, picks: GhosttiesThemePicks) throws {
            file = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("ghostty")
            try text.write(to: file, atomically: true, encoding: .utf8)
            super.init(config: Self.loadConfig(at: file.path(), finalize: true, picks: picks))
        }
        deinit { try? FileManager.default.removeItem(at: file) }
    }

    private func configFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("ghostty")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func background(of config: Ghostty.Config) throws -> [Int] {
        let cfg = try #require(config.config)
        var c = ghostty_config_color_s()
        let key = "background"
        #expect(ghostty_config_get(cfg, &c, key, UInt(key.lengthOfBytes(using: .utf8))))
        return [Int(c.r), Int(c.g), Int(c.b)]
    }

    private func bytes(_ ns: NSColor) -> [Int] {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func themeBackground(_ name: String) -> [Int] { bytes(ThemeFile.background(named: name)) }

    private func suite() -> (UserDefaults, () -> Void) {
        let name = "ghostties.tests.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private let latteGruvbox = GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Gruvbox Dark")

    // MARK: - 1. Default = Ghostties pair

    @Test func noPickLoadsNoOverrideLayer() {
        #expect(GhosttiesConfigDefaults.overrideContents(picks: .none) == nil)
        #expect(GhosttiesThemePicks.none.isEmpty)
    }

    @Test func defaultStateIsTheGhosttiesPair() throws {
        let path = try configFile("").path
        #expect(GhosttiesAppearanceState.resolve(configPath: path, picks: .none) == .ghostties)
        let config = try PickedConfig("", picks: .none)
        #expect(config.errors.isEmpty, "\(config.errors)")
        #expect(try background(of: config) == themeBackground("Ghostties Light"))
        #expect(GhosttiesConfigDefaults.contents.contains("theme = light:Ghostties Light,dark:Ghostties Dark"))
    }

    // MARK: - 2. Custom adoption

    @Test func userThemeWithNoPickIsCustomAndKeepsTheirBackground() throws {
        let text = "theme = Dracula"
        let state = GhosttiesAppearanceState.resolve(configPath: try configFile(text).path, picks: .none)
        #expect(state == .custom(themeName: "Dracula"))
        let config = try PickedConfig(text, picks: .none)
        #expect(try background(of: config) == themeBackground("Dracula"))
    }

    // MARK: - 3. A pick beats the user's theme line

    @Test func pickBeatsUserThemeLine() throws {
        let text = "theme = Dracula"
        let config = try PickedConfig(text, picks: latteGruvbox)
        #expect(config.errors.isEmpty, "\(config.errors)")
        // Default conditional state is light: the light pick shows.
        #expect(try background(of: config) == themeBackground("Catppuccin Latte"))
        #expect(try background(of: config) != themeBackground("Dracula"))
        #expect(GhosttiesAppearanceState.resolve(configPath: try configFile(text).path, picks: latteGruvbox)
            == .picked(light: "Catppuccin Latte", dark: "Gruvbox Dark"))
    }

    @Test func overrideLayerIsAThemePairLine() {
        #expect(GhosttiesConfigDefaults.overrideContents(picks: latteGruvbox)
            == "theme = light:Catppuccin Latte,dark:Gruvbox Dark")
    }

    /// The dark slot of the pick resolves against the bundled themes dir.
    @Test func darkPickNameResolvesThroughTheLoader() throws {
        let config = try PickedConfig("theme = Gruvbox Dark", picks: .none)
        #expect(config.errors.isEmpty, "\(config.errors)")
        #expect(try background(of: config) == themeBackground("Gruvbox Dark"))
    }

    @Test func lightAndDarkPicksAreIndependent() throws {
        let lightOnly = GhosttiesThemePicks(light: "Catppuccin Latte")
        #expect(GhosttiesConfigDefaults.overrideContents(picks: lightOnly)
            == "theme = light:Catppuccin Latte,dark:Ghostties Dark")
        let darkOnly = GhosttiesThemePicks(dark: "Gruvbox Dark")
        #expect(GhosttiesConfigDefaults.overrideContents(picks: darkOnly)
            == "theme = light:Ghostties Light,dark:Gruvbox Dark")
        #expect(GhosttiesAppearanceState.resolve(configPath: try configFile("").path, picks: darkOnly)
            == .picked(light: "Ghostties Light", dark: "Gruvbox Dark"))
    }

    @Test func pickingAPairCardSetsBoth() {
        let picks = GhosttiesThemePicks(pair: GhosttiesThemeCatalog.ghostties)
        #expect(picks == GhosttiesThemePicks(light: "Ghostties Light", dark: "Ghostties Dark"))
        #expect(GhosttiesThemeCatalog.ghostties.name == "Ghostties")
    }

    // MARK: - 4. Explicit colours cannot be overridden

    @Test(arguments: ["background = #102030", "foreground = #eeeeee", "palette = 1=#ff0000"])
    func explicitColourLinesReportSetByConfig(line: String) throws {
        let path = try configFile(line).path
        #expect(GhosttiesAppearanceState.resolve(configPath: path, picks: latteGruvbox) == .setByConfig)
        #expect(GhosttiesAppearanceState.resolve(configPath: path, picks: .none) == .setByConfig)
        #expect(GhosttiesThemeProbe.probe(configPath: path).kind == .explicitColors)
    }

    @Test func explicitBackgroundSurvivesAPick() throws {
        let config = try PickedConfig("background = #102030", picks: latteGruvbox)
        #expect(try background(of: config) == [0x10, 0x20, 0x30])
    }

    @Test func explicitBackgroundBeatsAThemeLineInTheState() throws {
        let path = try configFile("theme = Dracula\nbackground = #102030").path
        #expect(GhosttiesAppearanceState.resolve(configPath: path, picks: .none) == .setByConfig)
    }

    // MARK: - Probe

    @Test func probeClassifiesFixtureConfigs() throws {
        #expect(GhosttiesThemeProbe.probe(configPath: try configFile("font-size = 14").path)
            == .init(kind: .none, themeName: nil))
        #expect(GhosttiesThemeProbe.probe(configPath: try configFile("theme = Dracula").path)
            == .init(kind: .themeOnly, themeName: "Dracula"))
    }

    // MARK: - 5. Clearing returns to Custom / Ghostties

    @Test func clearingThePickReturnsToCustomOrGhostties() throws {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let custom = try configFile("theme = Dracula").path
        let plain = try configFile("").path
        latteGruvbox.save(to: defaults)
        #expect(GhosttiesAppearanceState.resolve(configPath: custom, picks: .stored(in: defaults)) != .custom(themeName: "Dracula"))
        GhosttiesThemePicks.clear(in: defaults)
        #expect(GhosttiesAppearanceState.resolve(configPath: custom, picks: .stored(in: defaults)) == .custom(themeName: "Dracula"))
        #expect(GhosttiesAppearanceState.resolve(configPath: plain, picks: .stored(in: defaults)) == .ghostties)
        // And the user's theme wins again in the resolved config.
        let config = try PickedConfig("theme = Dracula", picks: .stored(in: defaults))
        #expect(try background(of: config) == themeBackground("Dracula"))
    }

    // MARK: - 6. Persistence round-trip (injected suite)

    @Test func picksRoundTripThroughInjectedDefaults() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        #expect(GhosttiesThemePicks.stored(in: defaults) == .none)
        latteGruvbox.save(to: defaults)
        #expect(GhosttiesThemePicks.stored(in: defaults) == latteGruvbox)
        #expect(defaults.string(forKey: "ghostties.theme.light") == "Catppuccin Latte")
        #expect(defaults.string(forKey: "ghostties.theme.dark") == "Gruvbox Dark")
        GhosttiesThemePicks(light: "Catppuccin Latte").save(to: defaults)
        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Catppuccin Latte"))
        #expect(defaults.object(forKey: "ghostties.theme.dark") == nil)
        GhosttiesThemePicks.clear(in: defaults)
        #expect(GhosttiesThemePicks.stored(in: defaults) == .none)
    }

    @Test func savingNeverTouchesTheStandardDomain() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let before = UserDefaults.standard.string(forKey: "ghostties.theme.light")
        latteGruvbox.save(to: defaults)
        #expect(UserDefaults.standard.string(forKey: "ghostties.theme.light") == before)
    }

    // MARK: - The user's file is never edited

    @Test func resolvingAndLoadingNeverRewritesTheUsersConfig() throws {
        let url = try configFile("theme = Dracula\n")
        let before = try Data(contentsOf: url)
        _ = GhosttiesAppearanceState.resolve(configPath: url.path, picks: latteGruvbox)
        _ = Ghostty.Config.loadConfig(at: url.path, finalize: true, picks: latteGruvbox)
        #expect(try Data(contentsOf: url) == before)
    }
}
