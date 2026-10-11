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
        // Hands the preview back the host's own appearance as its configured one.
        SidebarAppearancePreview.applyAppAppearance(configured: savedAppearance)
        super.tearDown()
    }

    func testPreviewSetsTheWholeAppsAppearanceAndAutoHandsItBack() {
        XCTAssertEqual(SidebarAppearancePreview.mode, .auto)
        // Seed the config's window-theme explicitly (light), the way
        // `AppDelegate.syncAppearance` does on a config load, so the test
        // doesn't depend on whether the host ever loaded a config.
        SidebarAppearancePreview.applyAppAppearance(configured: NSAppearance(named: .aqua))
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        // The opposite look, so the effective appearance has to change and
        // the terminal observer has to fire.
        let target: SidebarAppearancePreview.Mode = .dark
        let terminalObserverFires = keyValueObservingExpectation(for: NSApp as Any, keyPath: "effectiveAppearance")

        SidebarAppearancePreview.set(target)

        XCTAssertEqual(NSApp.appearance?.name, target == .dark ? .darkAqua : .aqua)
        wait(for: [terminalObserverFires], timeout: 2)
        XCTAssertEqual(NSApp.effectiveAppearance.isDark, target == .dark)

        SidebarAppearancePreview.set(.auto)
        XCTAssertEqual(NSApp.appearance?.name, .aqua, "auto must hand the app back to the config's window-theme")
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
