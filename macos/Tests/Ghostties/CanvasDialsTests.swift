#if DEBUG
import XCTest
import SwiftUI
import DialkitmacOS
@testable import Ghostty

/// The "Canvas" DialKit panel (beta.27, DEBUG only): untouched it reads
/// exactly the shipped canvas fill and card shadow in both appearances, a
/// dial reaches only its own appearance, and its keys are cleared by its
/// Reset and "Reset all panels". Private suites only.
@MainActor
final class CanvasDialsTests: XCTestCase {
    private func suite(_ tag: String) -> UserDefaults {
        let name = "com.seansmithdesign.ghostties.tests.canvas-dials.\(tag)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    /// An empty store reads the shipped expressions themselves, so an
    /// untouched panel (and Release, which never reads a key) draws today's
    /// canvas.
    func testEmptyStoreReadsTheShippedCanvas() {
        let d = suite("empty")
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(CanvasStyle.background(scheme, defaults: d),
                           scheme == .dark ? ChromeTheme.ghostties(.dark).canvas : ChromeTheme.ghostties(.light).canvas)
            XCTAssertEqual(CanvasStyle.shadowColor(scheme, defaults: d),
                           scheme == .dark ? ChromeTheme.ghostties(.dark).shadow.cgColor : ChromeTheme.ghostties(.light).shadow.cgColor)
            XCTAssertEqual(CanvasStyle.shadowOpacity(scheme, defaults: d), WorkspaceLayout.canvasShadowOpacity)
            XCTAssertEqual(CanvasStyle.shadowRadius(scheme, defaults: d), WorkspaceLayout.canvasShadowRadius)
            XCTAssertEqual(CanvasStyle.shadowOffset(scheme, defaults: d), WorkspaceLayout.canvasShadowOffset)
        }
    }

    /// What each dial shows unset: the shipped values (beta.27, Sean's
    /// DialKit tune), which Release reads too. Reading writes nothing.
    func testPanelShowsTheShippedValues() {
        let d = suite("panel-defaults")
        let model = CanvasDialPanel.read(d)
        XCTAssertEqual(model.light.background, "#FAF7F3")
        XCTAssertEqual(model.dark.background, "#141413")
        XCTAssertEqual(model.light.shadowColor, "#0F0F0F")
        XCTAssertEqual(model.dark.shadowColor, "#FFFFFF")
        for a in [model.light, model.dark] {
            // Exact: no Float noise reaches the readout (was 0.15000000596046448).
            XCTAssertEqual(a.shadowOpacity, 0.06)
            XCTAssertEqual(a.shadowRadius, 16)
            XCTAssertEqual(a.shadowOffsetY, -2)
        }
        for key in CanvasTuning.allKeys { XCTAssertNil(d.object(forKey: key), key) }
    }

    /// A panel edit persists only the moved field, for its own appearance.
    func testPanelWritesOnlyTheMovedField() {
        let d = suite("diff-write")
        let before = CanvasDialPanel.read(d)
        var after = before
        after.dark.shadowOpacity = 0.4
        CanvasDialPanel.write(d, from: before, to: after)
        XCTAssertEqual(CanvasTuning.allKeys.filter { d.object(forKey: $0) != nil },
                       [CanvasTuning.key(.shadowOpacity, .dark)])
        XCTAssertEqual(CanvasStyle.shadowOpacity(.dark, defaults: d), 0.4)
        XCTAssertEqual(CanvasStyle.shadowOpacity(.light, defaults: d), WorkspaceLayout.canvasShadowOpacity)
    }

    /// The keys belong to no other panel, and both resets clear them.
    func testResetAndResetAllClearTheCanvasKeys() {
        XCTAssertTrue(Set(CanvasTuning.allKeys).isSubset(of: SidebarDialTuning.allKeys))
        XCTAssertTrue(Set(CanvasTuning.allKeys).isDisjoint(with: SidebarColorTuning.allKeys))
        XCTAssertEqual(Set(CanvasTuning.allKeys).count, CanvasTuning.allKeys.count, "no duplicate keys")

        let d = suite("reset")
        let coordinator = FocusedDialKitCoordinator<CanvasDialPanel>(defaults: d, onChange: {})
        for key in CanvasTuning.allKeys { d.set(key.hasSuffix("Color") || key.hasSuffix("background") ? "#123456" : 3.0, forKey: key) }
        coordinator.handleAction("reset")
        for key in CanvasTuning.allKeys { XCTAssertNil(d.object(forKey: key), key) }
        XCTAssertEqual(coordinator.state.values, CanvasDialPanel.read(suite("reset-empty")))

        let all = suite("reset-all")
        let glass = SidebarDialKitCoordinator(defaults: all, onChange: {})
        for key in CanvasTuning.allKeys { all.set(3.0, forKey: key) }
        glass.handleAction("resetSidebar")
        for key in CanvasTuning.allKeys { XCTAssertNil(all.object(forKey: key), key) }
    }
}
#endif
