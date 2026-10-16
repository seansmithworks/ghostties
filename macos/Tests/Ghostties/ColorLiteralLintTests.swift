import Foundation
import Testing

/// Ratchet on colour literals in `macos/Sources` (appearance-themes plan,
/// slice 1). A colour value belongs in `ChromeTheme` as a token or a named
/// step; a new hex, `Color(red:)`, `NSColor(white:)` or
/// `Color.white.opacity(<number>)` anywhere else fails here.
///
/// `legacyAllowlist` is today's hits, per file. It may only shrink: a file
/// over its count fails (a new literal), and a file under its count fails
/// too, so the cleanup is locked in by lowering the number. Doc comments that
/// restate a hex count as hits on purpose.
///
/// A new colour: add it to `ChromeTheme.swift` (exempt) or reuse a token.
/// Never grow the allowlist.
struct ColorLiteralLintTests {
    /// The one file allowed to define colour values.
    static let exempt: Set<String> = ["Features/Ghostties/ChromeTheme.swift"]

    /// File (relative to `macos/Sources`) -> number of literal hits today.
    static let legacyAllowlist: [String: Int] = [
        "Features/Ghostties/ComposerSingleLineStyle.swift": 3,
        "Features/Ghostties/ComposerWitness.swift": 3,
        "Features/Ghostties/ComposerWitnessCast.swift": 11,  // DEBUG-only palette
        "Features/Ghostties/GraveyardRowExpansionView.swift": 6,
        "Features/Ghostties/HistoryBrowserView.swift": 2,
        "Features/Ghostties/InboxZoneView.swift": 1,
        "Features/Ghostties/MenuBar/MenuBarIconRenderer.swift": 3,
        "Features/Ghostties/NewTaskComposerView.swift": 7,
        "Features/Ghostties/SessionDetailView.swift": 1,
        "Features/Ghostties/SessionPopoverCard.swift": 6,
        "Features/Ghostties/SidebarColorDialKit.swift": 2,
        "Features/Ghostties/SidebarProjectColumn.swift": 4,
        "Features/Ghostties/SidebarProjectGroups.swift": 5,
        "Features/Ghostties/SidebarRedlines.swift": 4,  // DEBUG-only
        "Features/Ghostties/SidebarTrayItems.swift": 12,
        "Features/Ghostties/TaskRowView.swift": 6,
        "Features/Ghostties/TaskSidebarView.swift": 1,
        "Features/Ghostties/WorkspaceLayout.swift": 20,  // brand and status colours
        "Features/Ghostties/WorkspaceViewContainer.swift": 1,
        "Ghostty/Ghostty.Action.swift": 1,  // upstream
        "Ghostty/Surface View/SurfaceView.swift": 4,  // upstream
        "Helpers/Extensions/OSColor+Extension.swift": 3,  // upstream
    ]

    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// `#RRGGBB`, `0xRRGGBB`, `Color(red:` / `(white:` / `(srgbRed:` / `(hue:`
    /// (also `NSColor`), and `.white` / `.black` `.opacity(<number>)`.
    private static let pattern = try! NSRegularExpression(
        pattern: #"#[0-9A-Fa-f]{6}\b|\b0x[0-9A-Fa-f]{6}\b|\b(?:NS|UI)?Color\([^)]*?\b(?:srgbRed|red|white|hue):|\.(?:white|black)\.opacity\(\s*[0-9.]+\s*\)"#
    )

    private static func hits() throws -> [String: Int] {
        let root = sourcesRoot
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var counts: [String: Int] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard !exempt.contains(relative) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            var n = 0
            text.enumerateLines { line, _ in
                n += pattern.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line))
            }
            if n > 0 { counts[relative] = n }
        }
        return counts
    }

    @Test func sourcesRootIsReachable() {
        #expect(FileManager.default.fileExists(atPath: Self.sourcesRoot.appendingPathComponent("Features/Ghostties/ChromeTheme.swift").path))
    }

    @Test func noNewColorLiteralOutsideChromeTheme() throws {
        let actual = try Self.hits()
        for (file, n) in actual.sorted(by: { $0.key < $1.key }) {
            let allowed = Self.legacyAllowlist[file] ?? 0
            #expect(n <= allowed, "\(file): \(n) colour literals, allowed \(allowed). Use a ChromeTheme token or step; do not raise the allowlist.")
        }
    }

    /// The ratchet: a cleaned-up file must lower its number.
    @Test func allowlistHasNoSlack() throws {
        let actual = try Self.hits()
        for (file, allowed) in Self.legacyAllowlist.sorted(by: { $0.key < $1.key }) {
            let n = actual[file] ?? 0
            #expect(n >= allowed, "\(file): only \(n) literals left, allowlist says \(allowed). Lower it to \(n)\(n == 0 ? " (delete the entry)" : "").")
        }
    }
}
