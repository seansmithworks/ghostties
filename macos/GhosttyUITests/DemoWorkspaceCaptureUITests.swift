import XCTest

/// Captures marketing assets from the **seeded demo workspace** — 10 real
/// fixture repos staged by `scripts/demo/demo-ready.sh` — instead of the
/// hardcoded in-app cast `MarketingCaptureUITests` uses. Driven end to end by
/// `scripts/demo/demo-capture.sh`; see that script and `scripts/demo/README.md`
/// for the full pipeline this test's output feeds into.
///
/// Additive to `MarketingCaptureUITests`: does NOT replace it, does NOT
/// change its behaviour or output paths, and does NOT set
/// `GHOSTTIES_CAPTURE_FIXTURE` (that flag seeds an in-memory invented cast
/// and would defeat the point of this test).
///
/// Skipped unless `GHOSTTIES_UI_CAPTURE=1` reaches the test runner — same
/// gate as `MarketingCaptureUITests`, so an unfiltered `xcodebuild test`
/// never launches the app. From the CLI pass `TEST_RUNNER_GHOSTTIES_UI_CAPTURE=1`
/// and `TEST_RUNNER_GHOSTTIES_DEMO_STATE_DIR=<path to a throwaway copy of the
/// demo state directory>` to `xcodebuild`, combined with
/// `-only-testing:GhosttyUITests/DemoWorkspaceCaptureUITests`.
///
/// ## Fail-closed contract
///
/// `WorkspacePersistence.directory` falls back to the REAL state directory
/// if `GHOSTTIES_STATE_DIR` is unset, empty, or unusable — by design, so a
/// shipping launch is never affected. That means a bad override path here
/// would silently capture Sean's real workspace and (via `WorkspaceStore`'s
/// prune-on-load) mutate his real session list. This test never trusts that
/// the env var was merely *set* — it asserts an **observable signal** that
/// the app actually loaded from the override before it captures anything:
/// the demo fixture seeds a project named `brukas`, which does not exist in
/// `MarketingCaptureUITests`' invented cast (`switchboard`, `atlas-api`,
/// `fieldwork`, `pendulum`, `silo`, `trove`, `wren`) and is not a project
/// name Sean would plausibly have in his real workspace. If `brukas` is not
/// visible in the sidebar within the timeout, the test fails loudly instead
/// of proceeding to capture.
final class DemoWorkspaceCaptureUITests: XCTestCase {
    /// A project name unique to `examples/demo-workspace/` — present in
    /// every demo capture, absent from `MarketingCaptureUITests`' fixture
    /// cast. Doubles as the "override took effect" proof and the "this
    /// capture came from the demo workspace, not the hardcoded cast" proof.
    static let demoOnlyProjectName = "brukas"

    override class var defaultTestSuite: XCTestSuite {
        if ProcessInfo.processInfo.environment["GHOSTTIES_UI_CAPTURE"] == "1" {
            return XCTestSuite(forTestCaseClass: Self.self)
        } else {
            return XCTestSuite(name: "Skipping \(className()) (set GHOSTTIES_UI_CAPTURE=1 to run)")
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureDemoWorkspaceProjectsLight() throws {
        try capture(appearance: .light, name: "demo-projects-light")
    }

    func testCaptureDemoWorkspaceProjectsDark() throws {
        try capture(appearance: .dark, name: "demo-projects-dark")
    }

    private func capture(appearance: XCUIDevice.Appearance, name: String) throws {
        guard let stateDir = ProcessInfo.processInfo.environment["GHOSTTIES_DEMO_STATE_DIR"],
              !stateDir.isEmpty else {
            XCTFail(
                "GHOSTTIES_DEMO_STATE_DIR must be set (forwarded as " +
                "TEST_RUNNER_GHOSTTIES_DEMO_STATE_DIR) to a throwaway copy of " +
                "the demo state directory — refusing to launch without an " +
                "explicit isolated state dir."
            )
            return
        }

        // Sandboxed runner — write inside its own temp container, print the
        // resolved path so `demo-capture.sh` can copy it out.
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-demo-capture", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let app = XCUIApplication()
        // Only drive our own freshly-launched instance. `GHOSTTIES_STATE_DIR`
        // points the app at the isolated copy — never the live demo state
        // dir, and never the real one. Deliberately does NOT set
        // `GHOSTTIES_CAPTURE_FIXTURE`: this test wants the real
        // `WorkspacePersistence`-backed workspace, not the in-memory cast.
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        app.launchEnvironment["GHOSTTIES_STATE_DIR"] = stateDir
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window should exist after launch"
        )
        Thread.sleep(forTimeInterval: 1.5)

        // Same appearance-after-launch ordering as MarketingCaptureUITests —
        // see that file's comment on why appearance is set post-launch.
        XCUIDevice.shared.appearance = appearance
        Thread.sleep(forTimeInterval: 0.5)

        // Switch to the Projects tab via the real keyboard shortcut
        // (Cmd+Shift+1 — see AppDelegate's "Sidebar View" submenu). Project
        // rows like the fixture-only "brukas" only render on this tab;
        // `ghostties.sidebarTab` is a persisted @AppStorage default that
        // this machine's dev-build UserDefaults may already have set to
        // `.sessions` from real use, and `-ApplePersistenceIgnoreState`
        // does not reset UserDefaults. Same fix MarketingCaptureUITests
        // already applies for the same reason.
        app.typeKey("1", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        // ── Fail-closed assert: prove the override actually took effect ──
        // before capturing anything. Do not trust the env var being set;
        // require the demo-only fixture project to be visibly rendered.
        //
        // `ProjectDisclosureRow` combines its whole header into one
        // accessibility element (`.accessibilityElement(children: .combine)`)
        // exposed as a Button labeled "<name> project, collapsed/expanded" —
        // there is no separate StaticText named exactly the project name.
        // Match on that Button's label instead of `app.staticTexts[...]`.
        let demoProjectRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(Self.demoOnlyProjectName) project")
        ).firstMatch
        guard demoProjectRow.waitForExistence(timeout: 10) else {
            app.terminate()
            XCTFail(
                "GHOSTTIES_STATE_DIR override did not take effect — fixture " +
                "project '\(Self.demoOnlyProjectName)' was never visible in " +
                "the sidebar. Refusing to capture: this would otherwise risk " +
                "silently capturing (and mutating) the real workspace."
            )
            return
        }
        Thread.sleep(forTimeInterval: 0.3)

        let window = app.windows.firstMatch
        let windowShot = window.screenshot()
        let outputPath = outputDir.appendingPathComponent("\(name).png")
        try windowShot.pngRepresentation.write(to: outputPath)
        print("CAPTURE_OUTPUT: \(outputPath.path)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path))

        app.terminate()
    }
}
