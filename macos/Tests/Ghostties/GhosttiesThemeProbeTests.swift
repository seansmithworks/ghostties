import AppKit
import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// `GhosttiesThemeProbe` reads the user's config in Ghostty's own load order
/// (`config-file` includes after every top-level line, queued breadth-first),
/// so the Custom card names the theme Ghostty actually applies. Every case
/// also loads the same files through `Ghostty.Config.loadConfig` and checks
/// the resolved background, so the probe can't drift from the real loader.
struct GhosttiesThemeProbeTests {
    /// A throwaway directory of config files, removed with the value.
    private final class ConfigDir {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ghostties-probe-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        @discardableResult
        func write(_ name: String, _ text: String) throws -> String {
            let file = url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private func loadedBackground(_ path: String) throws -> [Int] {
        let config = Ghostty.Config(at: path)
        let cfg = try #require(config.config)
        var c = ghostty_config_color_s()
        let key = "background"
        #expect(ghostty_config_get(cfg, &c, key, UInt(key.lengthOfBytes(using: .utf8))))
        return [Int(c.r), Int(c.g), Int(c.b)]
    }

    private func themeBackground(_ name: String) -> [Int] {
        let ns = ThemeFile.background(named: name)
        let c = ns.usingColorSpace(.sRGB) ?? ns
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    @Test func includeLoadsAfterEveryTopLevelLine() throws {
        let dir = try ConfigDir()
        try dir.write("colors", "theme = Dracula")
        let main = try dir.write("config", "config-file = colors\ntheme = Gruvbox Dark")
        #expect(try loadedBackground(main) == themeBackground("Dracula"))
        #expect(GhosttiesThemeProbe.probe(configPath: main) == .init(kind: .themeOnly, themeName: "Dracula"))
        #expect(GhosttiesAppearanceState.resolve(configPath: main, picks: .none) == .custom(themeName: "Dracula"))
    }

    @Test func optionalPrefixComesOffBeforeTheQuotes() throws {
        let dir = try ConfigDir()
        try dir.write("inc4", "background = #000000")
        let main = try dir.write("config", "config-file = ?\"inc4\"")
        #expect(try loadedBackground(main) == [0, 0, 0])
        #expect(GhosttiesThemeProbe.probe(configPath: main).kind == .explicitColors)
    }

    @Test func nestedIncludesQueueAfterTheirSiblings() throws {
        let dir = try ConfigDir()
        try dir.write("a", "config-file = c")
        try dir.write("b", "theme = Gruvbox Dark")
        try dir.write("c", "theme = Dracula")
        let main = try dir.write("config", "config-file = a\nconfig-file = b")
        // Ghostty's order is a, b, then c (queued by a): c's theme is last.
        #expect(try loadedBackground(main) == themeBackground("Dracula"))
        #expect(GhosttiesThemeProbe.probe(configPath: main).themeName == "Dracula")
    }

    @Test func relativeIncludeResolvesAgainstTheIncludingFile() throws {
        let dir = try ConfigDir()
        try dir.write("sub/a", "config-file = c")
        try dir.write("sub/c", "theme = Dracula")
        let main = try dir.write("config", "config-file = sub/a")
        #expect(try loadedBackground(main) == themeBackground("Dracula"))
        #expect(GhosttiesThemeProbe.probe(configPath: main).themeName == "Dracula")
    }

    @Test func emptyConfigFileClearsQueuedIncludes() throws {
        let dir = try ConfigDir()
        try dir.write("a", "theme = Dracula")
        let main = try dir.write("config", "config-file = a\nconfig-file =")
        #expect(try loadedBackground(main) != themeBackground("Dracula"))
        #expect(GhosttiesThemeProbe.probe(configPath: main) == .init(kind: .none, themeName: nil))
    }

    @Test func includeCycleLoadsEachFileOnce() throws {
        let dir = try ConfigDir()
        try dir.write("a", "config-file = b\ntheme = Dracula")
        try dir.write("b", "config-file = a")
        let main = try dir.write("config", "config-file = a")
        #expect(try loadedBackground(main) == themeBackground("Dracula"))
        #expect(GhosttiesThemeProbe.probe(configPath: main).themeName == "Dracula")
    }
}
