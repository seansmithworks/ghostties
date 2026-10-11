import AppKit
import SwiftUI
import XCTest
import GhosttyKit
@testable import Ghostty

/// Regression coverage for "Ghostties only refreshes some of the threads"
/// (2026-10-06): with `theme = light:…,dark:…`, a system light/dark switch
/// re-themed the session on screen but left the sessions the sidebar holds
/// off-window on the old scheme. Switching to one of them later didn't fix
/// it either, because `BaseTerminalController.updateColorSchemeForSurfaceTree`
/// caches the last scheme it applied per controller, while the sidebar swaps
/// different sessions' trees through that one controller.
///
/// The test runs the production pieces with real libghostty surfaces:
/// - its own `Ghostty.App` with a conditional light/dark theme, so a surface's
///   scheme is observable as its config background;
/// - one controller showing session A, with B and C held off-window the way
///   `SessionCoordinator.sessionTrees` holds them;
/// - the appearance change driven the way production delivers it: the
///   AppDelegate observer's broadcast, then the shown window's
///   `syncAppearance` → `updateColorSchemeForSurfaceTree()`;
/// - a sidebar switch to B the way `SessionCoordinator.showSession` does it
///   (`replaceSurfaceTree`, then the focus change re-syncs appearance).
///
/// It never changes `NSApp.appearance` or calls `ghostty_app_set_color_scheme`:
/// both would feed back through `AppDelegate.syncAppearance(config:)` and flip
/// the whole shared test host's appearance, which other suites depend on. The
/// target scheme is the host's current one, since that is what
/// `updateColorSchemeForSurfaceTree()` reads, so the test holds at any time of day.
@MainActor
final class ColorSchemeReachesAllSessionsTests: XCTestCase {
    /// Kept alive for the life of the test process: a surface must never
    /// outlive the `ghostty_app_t` it was created from.
    private static var apps: [Ghostty.App] = []

    private static let lightBackground = "f0f0f0"
    private static let darkBackground = "101010"

    func testAppearanceChangeReachesEverySessionNotJustTheShownOne() async throws {
        let app = try makeConditionalThemeApp()
        guard let cApp = app.app else { return XCTFail("test app failed to load") }

        let hostIsDark = NSApplication.shared.effectiveAppearance.isDark
        let newScheme = hostIsDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        let oldScheme = hostIsDark ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
        let newBackground = hostIsDark ? Self.darkBackground : Self.lightBackground
        let oldBackground = hostIsDark ? Self.lightBackground : Self.darkBackground

        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        config.workingDirectory = NSTemporaryDirectory()

        let sessionA = Ghostty.SurfaceView(cApp, baseConfig: config)
        let sessionB = Ghostty.SurfaceView(cApp, baseConfig: config)
        let sessionC = Ghostty.SurfaceView(cApp, baseConfig: config)
        let sessions = ["A (shown during the switch)": sessionA,
                        "B (switched to after it)": sessionB,
                        "C (never shown)": sessionC]

        // Before the switch: every session is on the old scheme.
        for surfaceView in sessions.values {
            let surface = try XCTUnwrap(surfaceView.surface)
            ghostty_surface_set_color_scheme(surface, oldScheme)
            app.reloadConfig(surface: surface, soft: true)
        }
        for (name, surfaceView) in sessions {
            let reached = await waitUntil { Self.hex(of: surfaceView) == oldBackground }
            XCTAssertTrue(reached, "setup: session \(name) never reached the old scheme")
        }

        let controller = BaseTerminalController(app, surfaceTree: SplitTree(view: sessionA))

        // The system appearance changes while session A is on screen.
        NotificationCenter.default.post(
            name: .ghosttyColorSchemeDidChange,
            object: app,
            userInfo: [Notification.Name.GhosttyColorSchemeKey: newScheme]
        )
        controller.updateColorSchemeForSurfaceTree()

        // The user then clicks session B in the sidebar.
        controller.replaceSurfaceTree(
            SplitTree(view: sessionB),
            moveFocusTo: nil,
            moveFocusFrom: nil
        )
        controller.updateColorSchemeForSurfaceTree()

        for (name, surfaceView) in sessions.sorted(by: { $0.key < $1.key }) {
            let reached = await waitUntil { Self.hex(of: surfaceView) == newBackground }
            XCTAssertTrue(
                reached,
                "session \(name) kept background #\(Self.hex(of: surfaceView)) after the "
                    + "appearance change; expected #\(newBackground)"
            )
        }

        withExtendedLifetime(controller) {}
    }

    /// View > Refresh Appearance: when a controller's cached scheme says
    /// "already applied" but the surface has drifted, only `force` repairs it.
    /// The controller is never put in a window, so this also covers the
    /// hidden-window case.
    func testForcedUpdateBypassesStaleAppliedSchemeGuard() async throws {
        let app = try makeConditionalThemeApp()
        let hostIsDark = NSApplication.shared.effectiveAppearance.isDark
        let oldScheme = hostIsDark ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
        let newBackground = hostIsDark ? Self.darkBackground : Self.lightBackground
        let oldBackground = hostIsDark ? Self.lightBackground : Self.darkBackground

        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        config.workingDirectory = NSTemporaryDirectory()
        let view = Ghostty.SurfaceView(try XCTUnwrap(app.app), baseConfig: config)
        let surface = try XCTUnwrap(view.surface)
        let controller = BaseTerminalController(app, surfaceTree: SplitTree(view: view))

        // The controller records the host's scheme as applied.
        controller.updateColorSchemeForSurfaceTree()
        app.reloadConfig(surface: surface, soft: true)
        let applied = await waitUntil { Self.hex(of: view) == newBackground }
        XCTAssertTrue(applied, "setup: controller never applied the host scheme")

        // The surface drifts behind the controller's back.
        ghostty_surface_set_color_scheme(surface, oldScheme)
        app.reloadConfig(surface: surface, soft: true)
        let drifted = await waitUntil { Self.hex(of: view) == oldBackground }
        XCTAssertTrue(drifted, "setup: surface never drifted")

        // The guard thinks it is current, so a plain update does nothing.
        controller.updateColorSchemeForSurfaceTree()
        app.reloadConfig(surface: surface, soft: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(Self.hex(of: view), oldBackground, "plain update should hit the stale guard")

        controller.updateColorSchemeForSurfaceTree(force: true)
        app.reloadConfig(surface: surface, soft: true)
        let repaired = await waitUntil { Self.hex(of: view) == newBackground }
        XCTAssertTrue(repaired, "forced update did not re-push the scheme")

        withExtendedLifetime(controller) {}
    }

    // MARK: - AppDelegate.applyAppearanceToAllSurfaces

    /// The single path the `effectiveAppearance` observer and View > Refresh
    /// Appearance both call. A real `TerminalController` whose window is loaded
    /// but never shown must still be re-themed by an ordinary (non-forced) call.
    func testAppDelegateHelperReachesControllerWithHiddenWindow() async throws {
        let app = try makeConditionalThemeApp()
        let delegate = try appDelegate()
        let hostIsDark = NSApplication.shared.effectiveAppearance.isDark
        let oldScheme = hostIsDark ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
        let newBackground = hostIsDark ? Self.darkBackground : Self.lightBackground
        let oldBackground = hostIsDark ? Self.lightBackground : Self.darkBackground

        let (controller, view) = try makeHiddenWindowController(app)
        let surface = try XCTUnwrap(view.surface)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible, "setup: window must be hidden")
        XCTAssertTrue(
            delegate.allSurfaceControllers.contains { $0 === controller },
            "setup: hidden controller is not reachable through allSurfaceControllers"
        )

        ghostty_surface_set_color_scheme(surface, oldScheme)
        app.reloadConfig(surface: surface, soft: true)
        let old = await waitUntil { Self.hex(of: view) == oldBackground }
        XCTAssertTrue(old, "setup: surface never reached the old scheme")

        delegate.applyAppearanceToAllSurfaces(force: false)
        app.reloadConfig(surface: surface, soft: true)

        let reached = await waitUntil { Self.hex(of: view) == newBackground }
        XCTAssertTrue(
            reached,
            "hidden-window controller kept #\(Self.hex(of: view)); expected #\(newBackground)"
        )
    }

    /// View > Refresh Appearance: `force: true` through the AppDelegate helper
    /// must repair a surface whose controller already recorded the scheme.
    func testAppDelegateHelperForceRepairsStaleSurface() async throws {
        let app = try makeConditionalThemeApp()
        let delegate = try appDelegate()
        let hostIsDark = NSApplication.shared.effectiveAppearance.isDark
        let oldScheme = hostIsDark ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
        let newBackground = hostIsDark ? Self.darkBackground : Self.lightBackground
        let oldBackground = hostIsDark ? Self.lightBackground : Self.darkBackground

        let (controller, view) = try makeHiddenWindowController(app)
        let surface = try XCTUnwrap(view.surface)

        // The controller records the host scheme as applied.
        controller.updateColorSchemeForSurfaceTree()
        app.reloadConfig(surface: surface, soft: true)
        let applied = await waitUntil { Self.hex(of: view) == newBackground }
        XCTAssertTrue(applied, "setup: controller never applied the host scheme")

        // The surface drifts behind the controller's back.
        ghostty_surface_set_color_scheme(surface, oldScheme)
        app.reloadConfig(surface: surface, soft: true)
        let drifted = await waitUntil { Self.hex(of: view) == oldBackground }
        XCTAssertTrue(drifted, "setup: surface never drifted")

        // Non-forced: the controller's guard says "current", nothing changes.
        delegate.applyAppearanceToAllSurfaces(force: false)
        app.reloadConfig(surface: surface, soft: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(Self.hex(of: view), oldBackground, "non-forced call should hit the stale guard")

        delegate.applyAppearanceToAllSurfaces(force: true)
        app.reloadConfig(surface: surface, soft: true)
        let repaired = await waitUntil { Self.hex(of: view) == newBackground }
        XCTAssertTrue(repaired, "force: true through the AppDelegate helper did not re-push the scheme")
    }

    // MARK: - Helpers

    private func appDelegate() throws -> AppDelegate {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate, "test host has no AppDelegate")
        try XCTSkipIf(delegate.ghostty.app == nil, "host AppDelegate has no libghostty app")
        return delegate
    }

    /// A real `TerminalController` with its window loaded (so it is in
    /// `NSApp.windows` and therefore `TerminalController.all`) but never shown.
    /// Detached from its window on teardown so other suites don't see it.
    private func makeHiddenWindowController(
        _ app: Ghostty.App
    ) throws -> (TerminalController, Ghostty.SurfaceView) {
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        config.workingDirectory = NSTemporaryDirectory()
        let view = Ghostty.SurfaceView(try XCTUnwrap(app.app), baseConfig: config)
        let controller = TerminalController(app, withSurfaceTree: SplitTree(view: view))
        _ = controller.window
        addTeardownBlock { @MainActor in
            controller.window?.orderOut(nil)
            controller.window?.windowController = nil
        }
        return (controller, view)
    }


    private func makeConditionalThemeApp() throws -> Ghostty.App {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColorSchemeReachesAllSessionsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let light = dir.appendingPathComponent("light-theme")
        let dark = dir.appendingPathComponent("dark-theme")
        try "background = #\(Self.lightBackground)\nforeground = #101010\n"
            .write(to: light, atomically: true, encoding: .utf8)
        try "background = #\(Self.darkBackground)\nforeground = #f0f0f0\n"
            .write(to: dark, atomically: true, encoding: .utf8)

        let configURL = dir.appendingPathComponent("config.ghostty")
        try "theme = light:\(light.path),dark:\(dark.path)\nconfirm-close-surface = false\n"
            .write(to: configURL, atomically: true, encoding: .utf8)

        let app = Ghostty.App(configPath: configURL.path)
        Self.apps.append(app)
        return app
    }

    private static func hex(of surfaceView: Ghostty.SurfaceView) -> String {
        let color = NSColor(surfaceView.derivedConfig.backgroundColor)
        guard let rgb = color.usingColorSpace(.sRGB) else { return "?" }
        return String(
            format: "%02x%02x%02x",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
