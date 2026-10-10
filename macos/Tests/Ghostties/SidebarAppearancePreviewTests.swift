import AppKit
import XCTest
@testable import Ghostty

/// The inspector's "Preview appearance" (DEBUG) switches the whole app, not
/// just the sidebar: it sets `NSApp.appearance`, which moves
/// `NSApp.effectiveAppearance` — the property AppDelegate observes to
/// re-theme every terminal (`applyAppearanceToAllSurfaces`). `auto` hands the
/// app back to the config's `window-theme` (nil follows the system).
///
/// This flips the shared test host's appearance for the length of one test,
/// so tearDown always puts it back.
@MainActor
final class SidebarAppearancePreviewTests: XCTestCase {
    private var savedAppearance: NSAppearance?

    override func setUp() {
        super.setUp()
        savedAppearance = NSApp.appearance
    }

    override func tearDown() {
        SidebarAppearancePreview.set(.auto)
        NSApp.appearance = savedAppearance
        super.tearDown()
    }

    func testPreviewSetsTheWholeAppsAppearanceAndAutoHandsItBack() {
        XCTAssertEqual(SidebarAppearancePreview.mode, .auto)
        let configured = NSApp.appearance?.name
        // The opposite of the host's current look, so the effective
        // appearance has to change and the terminal observer has to fire.
        let target: SidebarAppearancePreview.Mode = NSApp.effectiveAppearance.isDark ? .light : .dark
        let terminalObserverFires = keyValueObservingExpectation(for: NSApp as Any, keyPath: "effectiveAppearance")

        SidebarAppearancePreview.set(target)

        XCTAssertEqual(NSApp.appearance?.name, target == .dark ? .darkAqua : .aqua)
        wait(for: [terminalObserverFires], timeout: 2)
        XCTAssertEqual(NSApp.effectiveAppearance.isDark, target == .dark)

        SidebarAppearancePreview.set(.auto)
        XCTAssertEqual(NSApp.appearance?.name, configured, "auto must hand the app back to the config's window-theme")
    }

    /// The preview outranks the config's `window-theme`; `auto` passes it through.
    func testForcedPreviewOutranksTheConfiguredAppearance() {
        let configured = NSAppearance(named: .aqua)
        XCTAssertEqual(SidebarAppearancePreview.appAppearance(configured: configured)?.name, .aqua)
        XCTAssertNil(SidebarAppearancePreview.appAppearance(configured: nil))
        SidebarAppearancePreview.set(.dark)
        XCTAssertEqual(SidebarAppearancePreview.appAppearance(configured: configured)?.name, .darkAqua)
    }
}
