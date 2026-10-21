import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// Gate: Ghostties ships its own terminal theme pair as the out-of-the-box
/// default (`GhosttiesConfigDefaults`), with each theme's background equal
/// to the terminal card's canvas fill (DESIGN.md "Terminal theme"). The
/// configs are loaded through the real `Ghostty.Config.loadConfig`, so a
/// theme name that fails to resolve against the bundled themes dir shows up
/// as a diagnostic and a wrong background here.
struct GhosttiesDefaultThemeTests {
    private static let lightBackground = (r: 0xFA, g: 0xF7, b: 0xF3)
    private static let darkBackground = (r: 0x14, g: 0x14, b: 0x13)

    private func background(of config: Ghostty.Config) -> (r: Int, g: Int, b: Int)? {
        guard let cfg = config.config else { return nil }
        var color = ghostty_config_color_s()
        let key = "background"
        guard ghostty_config_get(cfg, &color, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
        return (Int(color.r), Int(color.g), Int(color.b))
    }

    @Test func defaultsSetTheGhosttiesThemePair() {
        #expect(GhosttiesConfigDefaults.contents.contains("theme = light:Ghostties Light,dark:Ghostties Dark"))
    }

    @Test(arguments: [
        ("Ghostties Light", "#faf7f3"),
        ("Ghostties Dark", "#141413"),
    ])
    func themeFileShipsInTheAppBundle(name: String, expectedBackground: String) throws {
        let url = try #require(Bundle.main.resourceURL)
            .appendingPathComponent("ghostty/themes/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        let backgrounds = text.split(separator: "\n")
            .filter { $0.hasPrefix("background = ") }
            .map { $0.dropFirst("background = ".count).lowercased() }
        #expect(backgrounds == [expectedBackground], "\(url.path)")
    }

    /// No user theme: the defaults' pair resolves from the bundled themes
    /// dir. A freshly loaded config is in the light conditional state.
    @Test func defaultConfigLoadsGhosttiesLight() throws {
        let config = try TemporaryConfig("")
        #expect(config.errors.isEmpty, "\(config.errors)")
        let bg = try #require(background(of: config))
        #expect(bg == Self.lightBackground)
    }

    @Test func darkThemeResolvesByName() throws {
        let config = try TemporaryConfig("theme = Ghostties Dark")
        #expect(config.errors.isEmpty, "\(config.errors)")
        let bg = try #require(background(of: config))
        #expect(bg == Self.darkBackground)
    }

    /// The user's config loads after the defaults, so their `theme =` wins.
    @Test func userThemeLineOverridesTheDefault() throws {
        let config = try TemporaryConfig("theme = Apple System Colors Light")
        #expect(config.errors.isEmpty, "\(config.errors)")
        let bg = try #require(background(of: config))
        #expect(bg == (r: 0xFE, g: 0xFF, b: 0xFF))
    }
}
