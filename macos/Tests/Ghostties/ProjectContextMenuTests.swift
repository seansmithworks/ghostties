import XCTest
import GhosttiesCore
@testable import Ghostty

/// The project context menu (Settings…, Pin, Remove) and the Settings popover
/// that hosts Templates are defined once, in `ProjectContextMenu.swift`, and
/// applied to every project header. One-view's accordion header lost them
/// because the menu lived inside `ProjectDisclosureRow` alone, so on the
/// default layout nobody could reach Templates.
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

    /// No second copy of the menu or the settings popover anywhere else.
    func testMenuAndSettingsPresentationAreDefinedOnce() throws {
        let files = try FileManager.default
            .contentsOfDirectory(atPath: Self.sourcesDir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var menuDefs: [String] = []
        var popovers: [String] = []
        for file in files {
            let text = try source(file)
            if text.contains("\"Settings\\u{2026}\"") { menuDefs.append(file) }
            if text.contains("ProjectSettingsView(project:") { popovers.append(file) }
        }
        XCTAssertEqual(menuDefs, ["ProjectContextMenu.swift"])
        XCTAssertEqual(popovers, ["ProjectContextMenu.swift"])
    }
}
