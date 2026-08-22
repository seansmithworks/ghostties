import XCTest

/// Produces the four 2x window PNGs the ghostties.org app section ships:
/// Sessions tab (light/dark) and Projects tab (light/dark). Driven by
/// `scripts/capture-marketing.sh` — see that script for the build +
/// convert-to-WebP pipeline this test's output feeds into.
///
/// Deliberately NOT gated behind the `IDE_DISABLED_OS_ACTIVITY_DT_MODE`
/// guard other UI tests in this file use — same reasoning as
/// `MarketingCaptureSpikeUITests`: this must run from a plain `xcodebuild
/// test` CLI invocation, which is exactly how the capture script drives it.
///
/// Every launch sets `GHOSTTIES_CAPTURE_FIXTURE=1` in the launch
/// environment (see `CaptureFixture`), so the captured window shows an
/// invented project/session cast and a canned terminal transcript — never
/// Sean's real workspace. See `BACKLOG.md` @ 2026-08-21 for why this
/// replaced the HTML replica.
final class MarketingCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureSessionsLight() throws {
        try capture(tab: "sessions", appearance: .light, name: "sessions-light")
    }

    func testCaptureSessionsDark() throws {
        try capture(tab: "sessions", appearance: .dark, name: "sessions-dark")
    }

    func testCaptureProjectsLight() throws {
        try capture(tab: "projects", appearance: .light, name: "projects-light")
    }

    func testCaptureProjectsDark() throws {
        try capture(tab: "projects", appearance: .dark, name: "projects-dark")
    }

    private func capture(tab: String, appearance: XCUIDevice.Appearance, name: String) throws {
        // Sandboxed runner — write inside its own temp container, print the
        // resolved path so `capture-marketing.sh` can copy it out.
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-marketing-capture", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let app = XCUIApplication()
        // Only drive our own freshly-launched instance — never attach to an
        // already-running Ghostty/Ghostties process.
        //
        // `GHOSTTIES_CAPTURE_FIXTURE` is passed as an environment variable,
        // not a `-key value` launch argument: Ghostty's own core CLI parser
        // scans argv for config directives and pops a user-facing
        // "Configuration Errors" dialog on any token it doesn't recognize —
        // verified by hand against `-GhosttiesCaptureFixture 1` (6 errors,
        // one per unrecognized argv token). See `CaptureFixture.isActive`.
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        app.launchEnvironment["GHOSTTIES_CAPTURE_FIXTURE"] = "1"
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window should exist after launch"
        )
        Thread.sleep(forTimeInterval: 1.5)

        // Set appearance after launch, not before — `XCUIDevice.shared.appearance`
        // drives a real system-wide dark/light switch, and setting it before
        // `app.launch()` was observed to make accessibility loading far less
        // reliable during manual verification of this test.
        XCUIDevice.shared.appearance = appearance
        Thread.sleep(forTimeInterval: 0.5)

        // Switch sidebar tab via the real keyboard shortcuts
        // (Cmd+Shift+1 = Projects, Cmd+Shift+2 = Sessions — see
        // `AppDelegate`'s "Sidebar View" submenu) rather than a launch
        // argument, for the same argv reason as above.
        if tab == "projects" {
            app.typeKey("1", modifierFlags: [.command, .shift])
        } else {
            app.typeKey("2", modifierFlags: [.command, .shift])
        }
        Thread.sleep(forTimeInterval: 0.5)

        // Projects tab: the fixture's `switchboard` project starts collapsed
        // (matches real launch behavior — nothing auto-expands), so expand it
        // first to reveal its session rows.
        if tab == "projects" {
            let projectRow = app.staticTexts["switchboard"].firstMatch
            if projectRow.waitForExistence(timeout: 5) {
                projectRow.click()
                Thread.sleep(forTimeInterval: 0.4)
            }
        }

        // Spawn a live session so the terminal pane shows the canned
        // transcript instead of an empty state — right-click the fixture's
        // "processing" session and choose Relaunch, the same path a real
        // user takes to resume a session that shows as exited after
        // restart (persisted sessions never carry a live runtime across
        // launches — see `AgentSession`'s doc comment).
        let sessionRow = app.staticTexts["Claude Code 4"].firstMatch
        if sessionRow.waitForExistence(timeout: 5) {
            sessionRow.rightClick()
            let relaunch = app.menuItems["Relaunch"].firstMatch
            if relaunch.waitForExistence(timeout: 2) {
                relaunch.click()
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
        }
        // Let the transcript script render and the terminal settle.
        Thread.sleep(forTimeInterval: 2.0)

        let window = app.windows.firstMatch
        let windowShot = window.screenshot()
        let outputPath = outputDir.appendingPathComponent("\(name).png")
        try windowShot.pngRepresentation.write(to: outputPath)
        print("CAPTURE_OUTPUT: \(outputPath.path)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path))

        app.terminate()
    }
}
