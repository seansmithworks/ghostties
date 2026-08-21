import XCTest

/// SPIKE (throwaway) — proves whether XCUITest can produce marketing-grade
/// screenshots of the Ghostties window before any capture rig gets built.
///
/// Answers three questions, each written to disk as evidence:
/// 1. Does screenshotting work without Screen Recording (TCC) permission?
/// 2. What resolution comes out — 1x or 2x (Retina)?
/// 3. Does `XCUIElement.screenshot()` (window-scoped) or `XCUIScreen.main.screenshot()`
///    (display-scoped) preserve the window's drop shadow / rounded corners?
///
/// Deliberately NOT gated behind the `IDE_DISABLED_OS_ACTIVITY_DT_MODE` guard
/// used elsewhere in this suite — this spike must actually run from a plain
/// `xcodebuild test` CLI invocation to answer the question honestly.
final class MarketingCaptureSpikeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureSpike() throws {
        // The GhosttyUITests-Runner process runs under the App Sandbox and
        // cannot write to arbitrary paths like /tmp — write inside the
        // sandbox's own temp container instead, and print the resolved path
        // so it can be copied out for inspection after the run.
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-capture-spike", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        print("SPIKE_OUTPUT_DIR: \(outputDir.path)")

        let app = XCUIApplication()
        // Only drive our own freshly-launched instance — never attach to an
        // already-running Ghostty/Ghostties process.
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window should exist after launch"
        )

        // Let the workspace sidebar finish rendering before capturing.
        Thread.sleep(forTimeInterval: 1.5)

        let window = app.windows.firstMatch
        let pointFrame = window.frame

        // Path A: window-scoped screenshot via XCUIElement.
        let windowShot = window.screenshot()
        try windowShot.pngRepresentation.write(
            to: outputDir.appendingPathComponent("window-element.png")
        )

        // Path B: full-display screenshot via XCUIScreen.
        let screenShot = XCUIScreen.main.screenshot()
        try screenShot.pngRepresentation.write(
            to: outputDir.appendingPathComponent("full-screen.png")
        )

        // Record the point-size frame we captured against, so pixel math can
        // be checked by hand against the saved PNGs (sips -g pixelWidth/Height).
        let manifest = """
        window point frame: \(pointFrame)
        window image.size (points): \(windowShot.image.size)
        screen image.size (points): \(screenShot.image.size)
        """
        try manifest.write(
            to: outputDir.appendingPathComponent("manifest.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("window-element.png").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("full-screen.png").path)
        )
    }
}
