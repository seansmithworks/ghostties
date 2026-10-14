import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// One source of truth per chrome colour (appearance-themes plan, slice 1).
/// DESIGN.md's frontmatter, the Swift `ChromeTheme` tokens and the bundled
/// `Ghostties Light` / `Ghostties Dark` theme files must agree, so a retune
/// in one place fails here until the others follow.
struct TokenSyncTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func read(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// `key: "#RRGGBB"` lines of DESIGN.md's YAML frontmatter, lowercased.
    private static func designHex() throws -> [String: String] {
        let text = try read("DESIGN.md")
        let frontmatter = text.components(separatedBy: "\n---\n").first ?? ""
        var out: [String: String] = [:]
        for line in frontmatter.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let open = parts[1].firstIndex(of: "\"") else { continue }
            let rest = parts[1][parts[1].index(after: open)...]
            guard let close = rest.firstIndex(of: "\"") else { continue }
            let value = String(rest[..<close])
            if value.hasPrefix("#"), value.count == 7 { out[parts[0]] = value.lowercased() }
        }
        return out
    }

    private static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    private static func themeBackground(_ name: String) throws -> String {
        let text = try read("macos/Resources/ghostty/themes/\(name)")
        let color = try #require(ThemeFile.background(in: text), "\(name) has no background")
        return hex(color)
    }

    @Test func chromeMatchesDesignMd() throws {
        let design = try Self.designHex()
        #expect(design["chromeBackground"] == Self.hex(ChromeTheme.ghostties(.light).chrome))
        #expect(design["darkChromeBackground"] == Self.hex(ChromeTheme.ghostties(.dark).chrome))
    }

    @Test func secondaryTextAndBorderMatchDesignMd() throws {
        let design = try Self.designHex()
        #expect(design["textSecondary"] == Self.hex(ChromeTheme.ghostties(.light).inkSecondary))
        #expect(design["darkTextSecondary"] == Self.hex(ChromeTheme.ghostties(.dark).inkSecondary))
        #expect(design["darkBorder"] == Self.hex(ChromeTheme.ghostties(.dark).lifted(.border)))
    }

    /// DESIGN.md = the theme file's `background` = the Swift canvas token.
    @Test func canvasMatchesDesignMdAndTheThemeFile() throws {
        let design = try Self.designHex()
        let light = try Self.themeBackground("Ghostties Light")
        let dark = try Self.themeBackground("Ghostties Dark")
        #expect(design["canvasBackground"] == light)
        #expect(design["darkCanvasBackground"] == dark)
        #expect(Self.hex(ChromeTheme.ghostties(.light).canvas) == light)
        #expect(Self.hex(ChromeTheme.ghostties(.dark).canvas) == dark)
    }

    /// Every theme the defaults name exists in the source themes directory
    /// (the bundled copy is guarded by `GhosttiesDefaultThemeTests`).
    @Test func defaultThemeFilesExist() throws {
        let line = try #require(GhosttiesConfigDefaults.contents.split(separator: "\n")
            .first { $0.hasPrefix("theme = ") })
        let names = line.dropFirst("theme = ".count).split(separator: ",")
            .map { $0.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "" }
        #expect(!names.isEmpty)
        for name in names {
            let path = Self.repoRoot.appendingPathComponent("macos/Resources/ghostty/themes/\(name)").path
            #expect(FileManager.default.fileExists(atPath: path), "\(name)")
        }
    }
}
