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

        guard let demoZdotdir = ProcessInfo.processInfo.environment["GHOSTTIES_DEMO_ZDOTDIR"],
              !demoZdotdir.isEmpty else {
            XCTFail(
                "GHOSTTIES_DEMO_ZDOTDIR must be set (forwarded as " +
                "TEST_RUNNER_GHOSTTIES_DEMO_ZDOTDIR) to a fixture zsh dotdir " +
                "with a user/host-free prompt — refusing to launch without " +
                "it, since the default prompt leaks the real username and " +
                "hostname into marketing captures."
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
        app.launchArguments.append(contentsOf: [
            "-ApplePersistenceIgnoreState", "YES",
            // Hide the dev-build badge in captures — it's an
            // `@AppStorage("ghostties.devBuildInfoBadge.enabled")` flag
            // (see BuildInfoBadgeView.swift); this launch-argument domain
            // override keeps the badge off marketing PNGs without touching
            // production code.
            "-ghostties.devBuildInfoBadge.enabled", "NO",
            // The capture build's own bundle ID means fresh UserDefaults, so
            // the first-launch onboarding sheet (OnboardingSheet.swift,
            // gated by `ghostties.hasSeenOnboarding` in
            // WorkspaceSidebarView.swift:39) would otherwise cover the
            // window for the entire capture. Same launch-argument domain
            // override idiom as the dev badge above.
            "-ghostties.hasSeenOnboarding", "YES",
        ])
        app.launchEnvironment["GHOSTTIES_STATE_DIR"] = stateDir
        // Ghostty's zsh auto-integration (setupZsh in
        // src/termio/shell_integration.zig) round-trips ZDOTDIR through its
        // own resource dir and restores this value before the user's dotfile
        // chain loads (src/shell-integration/zsh/.zshenv:28-33,45) — it does
        // not clobber it. Our fixture dotdir's .zshrc sets a user/host-free
        // PROMPT so the captured terminal panes never show
        // "seansmith@<hostname> ~ %".
        app.launchEnvironment["ZDOTDIR"] = demoZdotdir
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window should exist after launch"
        )
        Thread.sleep(forTimeInterval: 1.5)

        // ── Fail-closed: never click behind an unexpected onboarding sheet ──
        // If the launch-argument override above ever stops working (e.g. the
        // AppStorage key is renamed), OnboardingSheet would silently block
        // every click this test makes on the sidebar underneath it. Fail
        // loudly instead of proceeding.
        let onboardingSheet = app.staticTexts["Welcome to Ghostties"].firstMatch
        let getStartedButton = app.buttons["Get started"].firstMatch
        if onboardingSheet.exists || getStartedButton.exists {
            app.terminate()
            XCTFail(
                "Onboarding sheet is visible after launch despite " +
                "-ghostties.hasSeenOnboarding YES — refusing to click " +
                "behind it. Check WorkspaceSidebarView's " +
                "\"ghostties.hasSeenOnboarding\" AppStorage key."
            )
            return
        }

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

        // ── Expand every project so all staged session rows are visible ──
        // Projects start collapsed on launch, same as a real user's first
        // open; demo-drive.sh spreads staged sessions across every fixture
        // repo, not just the demo-only "brukas" project confirmed above.
        let collapsedProjects = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "project, collapsed")
        )
        var expandAttempts = 0
        while collapsedProjects.count > 0 && expandAttempts < 20 {
            collapsedProjects.element(boundBy: 0).click()
            Thread.sleep(forTimeInterval: 0.3)
            expandAttempts += 1
        }

        // ── Relaunch every staged session so terminal panes show real
        // activity ──
        // Staged sessions restore as "Exited" (see demo-drive.sh's own doc
        // comment) — nothing relaunches them at app launch, and there is no
        // URL scheme to trigger it. Mirror MarketingCaptureUITests' real-UI
        // idiom: right-click each staged row (named with the
        // "Demo Agent — " prefix demo-drive.sh writes) and choose
        // "Relaunch" from its context menu. NOT exercised against a real
        // build — see class doc comment.
        //
        // `SessionRow` (SessionDetailView.swift:9-95) is a plain `HStack`
        // with `.accessibilityElement(children: .combine)` and no `Button`
        // — unlike `ProjectDisclosureRow`'s header, which this file already
        // matches via `app.buttons` for that reason (see the `brukas`
        // assert above). `MarketingCaptureUITests` finds its fixture
        // session ("Claude Code 4") via `app.staticTexts[...]` against that
        // same `SessionRow` view (`CaptureFixture` seeds the real
        // `WorkspaceStore`/`SessionCoordinator`, not a separate view), but
        // there is no test in this repo that proves `.staticTexts` is the
        // right element type for a `.combine`d row rather than an
        // implementation detail of the current SwiftUI/AppKit hosting
        // bridge. Query type-agnostically instead of betting on one
        // `XCUIElementType`.
        let stagedSessionRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Demo Agent — ")
        )
        // `.any` may surface both a row's combined parent element and an
        // inner leaf with an overlapping label, double-counting one visual
        // row. That's harmless here: a second right-click on an
        // already-relaunched row simply finds no "Relaunch" item and falls
        // through to the escape branch below.
        let stagedCount = stagedSessionRows.count
        if stagedCount == 0 {
            XCTFail(
                "No staged sessions found (looked for rows labeled starting " +
                "\"Demo Agent — \"). Run demo-drive.sh to stage sessions " +
                "before capturing, or terminal panes will show an empty/" +
                "exited state."
            )
        } else {
            for i in 0..<stagedCount {
                let row = stagedSessionRows.element(boundBy: i)
                guard row.waitForExistence(timeout: 5) else {
                    XCTFail(
                        "Staged session row at index \(i) of \(stagedCount) " +
                        "disappeared before it could be relaunched."
                    )
                    continue
                }
                row.rightClick()
                let relaunch = app.menuItems["Relaunch"].firstMatch
                if relaunch.waitForExistence(timeout: 2) {
                    relaunch.click()
                } else {
                    // Already running (no Relaunch item in the menu) or the
                    // context menu didn't appear — dismiss and move on
                    // rather than get stuck on one row.
                    app.typeKey(.escape, modifierFlags: [])
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        // ── Wait until a terminal pane actually shows content ──
        // `Ghostty.SurfaceView` declares AX role `.textArea`, which XCUITest
        // surfaces as `XCUIElementType.textView`
        // ("Surface View/SurfaceView_AppKit.swift":2302-2320). Capture run 2
        // found that enumerating `app.descendants(matching: .any)` and
        // reading `.value` on every element is a separate AX round-trip per
        // element (~70ms each) — the log showed 701 "Find the Any" round
        // trips and only 319 resolved elements by the 15s timeout, so the
        // very first predicate evaluation never completed. Scope the query
        // to `.textView` and let a single NSPredicate-driven `firstMatch`
        // evaluate in one AX snapshot instead of enumerating in Swift. To
        // avoid a vacuous pass (almost anything with a long single-line
        // string could otherwise match), still require content that looks
        // like rendered terminal output: a newline, the way a shell prompt +
        // command + output block always has one.
        let terminalWithContent = app.descendants(matching: .textView).matching(
            NSPredicate(format: "value CONTAINS %@", "\n")
        ).firstMatch
        if !terminalWithContent.waitForExistence(timeout: 20) {
            let textViews = app.descendants(matching: .textView).allElementsBoundByIndex
            let lengths = textViews.map { ($0.value as? String)?.count ?? -1 }
            print(
                "DIAGNOSTIC: \(textViews.count) .textView descendant(s) found, " +
                "value lengths: \(lengths)"
            )
            XCTFail(
                "Timed out (20s) waiting for a terminal pane to show content " +
                "after relaunching staged sessions. This wait has not been " +
                "exercised against a real build — if SurfaceView's rendered " +
                "text genuinely never reaches XCUITest as a .textView value, " +
                "that's a finding to fix (or a different signal to poll), " +
                "not a reason to delete this wait or fall back silently to " +
                "a fixed sleep. See the DIAGNOSTIC line above for the actual " +
                ".textView count and value lengths."
            )
        }

        // Anti-vacuous guard: `waitForExistence` only proves *some* value
        // matched "value CONTAINS \n" — a lone newline or a short truncated
        // fragment would satisfy that predicate without being real rendered
        // terminal output. Require a value long enough that it can only be
        // genuine shell prompt + command + output, not a false-positive match.
        let capturedValue = (terminalWithContent.value as? String) ?? ""
        XCTAssertGreaterThan(
            capturedValue.count,
            40,
            "Matched .textView's value is only \(capturedValue.count) " +
            "character(s) — too short to be real rendered terminal output. " +
            "This looks like a vacuous match on the \"\\n\" predicate, not " +
            "genuine content."
        )

        // ── Scroll the sidebar back to the top before capturing ──
        // The expand loop and relaunch loop above both click/right-click
        // rows further down the project list, which leaves the sidebar
        // scrolled past the first project's header (observed: atlas-api's
        // header clipped off the top of a real capture). Scroll the
        // sidebar's own scroll view back up with a scroll-wheel gesture
        // (not `.any` descendant enumeration — see the AX-cost lesson
        // above) rather than a fixed sleep or a guess at row height.
        let sidebarScrollView = app.scrollViews.firstMatch
        guard sidebarScrollView.waitForExistence(timeout: 5) else {
            app.terminate()
            XCTFail(
                "No scroll view found for the sidebar — cannot scroll it " +
                "back to the top before capturing. The screenshot would " +
                "otherwise show whatever scroll position the expand/relaunch " +
                "loops above left it at."
            )
            return
        }
        // A large positive deltaY scrolls content up toward the top; repeat
        // several times since one gesture may not cover the full staged
        // list (10 fixture projects, some with staged sessions expanded).
        for _ in 0..<10 {
            sidebarScrollView.scroll(byDeltaX: 0, deltaY: 2000)
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
