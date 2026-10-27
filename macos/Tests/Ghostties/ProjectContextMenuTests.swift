import XCTest
import GhosttiesCore
@testable import Ghostty

/// The project context menu (Settings…, Pin, Remove) is defined once, in
/// `ProjectContextMenu.swift`, and applied to every project header. Name and
/// Templates are edited in Settings, so the menu has no "Name & Templates…".
final class ProjectContextMenuTests: XCTestCase {
    private static var sourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Ghostties")
    }

    private func source(_ file: String) throws -> String {
        try String(contentsOf: Self.sourcesDir.appendingPathComponent(file), encoding: .utf8)
    }

    /// The tabs row and the one-view accordion header (which the rail's
    /// project tile is, morphed) both carry the shared menu.
    func testTabsRowAndOneViewHeaderBothApplyTheSharedMenu() throws {
        for file in ["ProjectDisclosureRow.swift", "RecentsListView.swift"] {
            XCTAssertTrue(
                try source(file).contains(".projectContextMenu("),
                "\(file) must apply .projectContextMenu(...) to its project header"
            )
        }
    }

    /// No second copy of the menu anywhere else, and no "Name & Templates…" item.
    func testMenuAndSettingsPresentationAreDefinedOnce() throws {
        let files = try FileManager.default
            .contentsOfDirectory(atPath: Self.sourcesDir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var menuDefs: [String] = []
        for file in files {
            let text = try source(file)
            if text.contains("\"Settings\\u{2026}\"") { menuDefs.append(file) }
        }
        // Anywhere under macos/Sources, not just this folder.
        let root = Self.sourcesDir.deletingLastPathComponent().deletingLastPathComponent()
        var legacy: [String] = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            if try String(contentsOf: url, encoding: .utf8).contains("Name & Templates") {
                legacy.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(menuDefs, ["ProjectContextMenu.swift"])
        XCTAssertEqual(legacy, [], "the menu's Name & Templates… item is gone; Settings… covers it")
    }
}
