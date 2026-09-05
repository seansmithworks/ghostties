import XCTest

/// Visual & usage pass — captures the app's main surfaces across 18 states in
/// fixture mode, for the 2026-09-05 audit. Modeled on `MarketingCaptureUITests`:
/// same launch environment, same fixture assertion, same sandboxed temp-dir
/// output with `CAPTURE_OUTPUT: <path>` lines. NOT gated behind
/// `IDE_DISABLED_OS_ACTIVITY_DT_MODE` — must run from a plain `xcodebuild test`
/// CLI invocation.
///
/// Each test method is independent (fresh launch) and captures exactly one
/// state. Where a state cannot be reached with element queries, the test
/// prints `CAPTURE_UNREACHABLE: <state> — <reason>` and passes — an
/// unreachable state is a finding, not a failure.
///
/// The fork's own views declare no accessibility identifiers, so every query
/// below is by static text or menu title. Places that had to guess are
/// annotated inline.
final class VisualPassUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var outputDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-visual-pass", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Launch helper

    /// Launches a fresh instance in fixture mode and asserts the fixture
    /// assertion from the brief: `switchboard` exists, none of the real
    /// project names do. On failure, terminates the app, deletes any PNG
    /// already written for `state`, and re-throws so the whole run stops
    /// (XCTest fails fast via `continueAfterFailure = false`).
    @discardableResult
    private func launchFixtureApp(
        state: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        app.launchEnvironment["GHOSTTIES_CAPTURE_FIXTURE"] = "1"
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window should exist after launch"
        )
        Thread.sleep(forTimeInterval: 1.0)

        let hasFixtureMarker = app.staticTexts["switchboard"].firstMatch.waitForExistence(timeout: 5)
        let leakedRealNames = ["ghostties", "brukas", "Career-ops", "seansmithdesign"].contains {
            app.staticTexts[$0].firstMatch.exists
        }

        guard hasFixtureMarker, !leakedRealNames else {
            app.terminate()
            let path = outputDir.appendingPathComponent("\(state).png")
            try? FileManager.default.removeItem(at: path)
            XCTFail("FIXTURE ASSERTION FAILED for state \(state): hasFixtureMarker=\(hasFixtureMarker) leakedRealNames=\(leakedRealNames) — stopping run")
            throw XCTSkip("fixture assertion failed")
        }

        return app
    }

    private func capture(_ element: XCUIElement, state: String) throws {
        let shot = element.screenshot()
        let path = outputDir.appendingPathComponent("\(state).png")
        try shot.pngRepresentation.write(to: path)
        print("CAPTURE_OUTPUT: \(path.path)")
    }

    private func unreachable(_ state: String, _ reason: String) {
        print("CAPTURE_UNREACHABLE: \(state) — \(reason)")
    }

    // MARK: - 1-2. Projects tab

    func testProjectsLaunch() throws {
        let app = try launchFixtureApp(state: "projects-launch")
        try capture(app.windows.firstMatch, state: "projects-launch")
        app.terminate()
    }

    func testProjectsExpanded() throws {
        let app = try launchFixtureApp(state: "projects-expanded")
        let projectRow = app.staticTexts["switchboard"].firstMatch
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.click()
            Thread.sleep(forTimeInterval: 0.4)
        }
        try capture(app.windows.firstMatch, state: "projects-expanded")
        app.terminate()
    }

    // MARK: - 3. Projects tab, other appearance

    func testProjectsExpandedAlt() throws {
        let app = try launchFixtureApp(state: "projects-expanded-alt")
        let originalAppearance = XCUIDevice.shared.appearance
        let projectRow = app.staticTexts["switchboard"].firstMatch
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.click()
            Thread.sleep(forTimeInterval: 0.4)
        }
        let altAppearance: XCUIDevice.Appearance = originalAppearance == .dark ? .light : .dark
        XCUIDevice.shared.appearance = altAppearance
        Thread.sleep(forTimeInterval: 0.6)
        try capture(app.windows.firstMatch, state: "projects-expanded-alt")
        XCUIDevice.shared.appearance = originalAppearance
        app.terminate()
    }

    // MARK: - 4-5. Sessions tab

    func testSessions() throws {
        let app = try launchFixtureApp(state: "sessions")
        app.typeKey("2", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        try capture(app.windows.firstMatch, state: "sessions")
        app.terminate()
    }

    func testSessionsAlt() throws {
        let app = try launchFixtureApp(state: "sessions-alt")
        let originalAppearance = XCUIDevice.shared.appearance
        app.typeKey("2", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        let altAppearance: XCUIDevice.Appearance = originalAppearance == .dark ? .light : .dark
        XCUIDevice.shared.appearance = altAppearance
        Thread.sleep(forTimeInterval: 0.6)
        try capture(app.windows.firstMatch, state: "sessions-alt")
        XCUIDevice.shared.appearance = originalAppearance
        app.terminate()
    }

    // MARK: - 6. Session context menu

    func testSessionContextMenu() throws {
        let app = try launchFixtureApp(state: "session-context-menu")
        app.typeKey("2", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        let sessionRow = app.staticTexts["Claude Code 4"].firstMatch
        guard sessionRow.waitForExistence(timeout: 5) else {
            unreachable("session-context-menu", "'Claude Code 4' row not found on Sessions tab")
            app.terminate()
            return
        }
        sessionRow.rightClick()
        Thread.sleep(forTimeInterval: 0.4)
        // Guess: the context menu surfaces as a standard NSMenu; query the
        // first menu element rather than a specific item, since item titles
        // aren't documented for this row.
        let menu = app.menus.firstMatch
        if menu.waitForExistence(timeout: 2) {
            try capture(menu, state: "session-context-menu-menu")
        } else {
            unreachable("session-context-menu-menu", "no menu element found after right-click")
        }
        try capture(app.windows.firstMatch, state: "session-context-menu")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    // MARK: - 7-10. Composer

    func testComposerEmpty() throws {
        let app = try launchFixtureApp(state: "composer-empty")
        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.5)
        try capture(app.windows.firstMatch, state: "composer-empty")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testComposerTyped() throws {
        let app = try launchFixtureApp(state: "composer-typed")
        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.3)
        app.typeText("swi")
        Thread.sleep(forTimeInterval: 0.5)
        try capture(app.windows.firstMatch, state: "composer-typed")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testComposerChevron() throws {
        let app = try launchFixtureApp(state: "composer-chevron")
        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.3)
        app.typeText("switchboard > feat/demo")
        Thread.sleep(forTimeInterval: 0.5)
        try capture(app.windows.firstMatch, state: "composer-chevron")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testComposerTab() throws {
        let app = try launchFixtureApp(state: "composer-tab")
        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.3)
        app.typeText("swi")
        app.typeKey(.tab, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        try capture(app.windows.firstMatch, state: "composer-tab")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    // MARK: - 11. New template

    func testNewTemplate() throws {
        let app = try launchFixtureApp(state: "new-template")
        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.5)
        // Guess: "New template" is an in-list row (no ellipsis per
        // SessionComposerPalette.swift), so query it as static text within
        // the composer's idle list.
        let newTemplateRow = app.staticTexts["New template"].firstMatch
        guard newTemplateRow.waitForExistence(timeout: 3) else {
            unreachable("new-template", "'New template' row not found in composer idle list")
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
            return
        }
        newTemplateRow.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Guess: a sheet, if presented, is queryable as app.sheets.firstMatch.
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 2) {
            try capture(sheet, state: "new-template")
        } else {
            try capture(app.windows.firstMatch, state: "new-template")
        }
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    // MARK: - 12-13. Sidebar closed / overlay

    func testSidebarClosed() throws {
        let app = try launchFixtureApp(state: "sidebar-closed")
        app.typeKey("e", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.6)
        try capture(app.windows.firstMatch, state: "sidebar-closed")
        app.terminate()
    }

    func testSidebarOverlay() throws {
        let app = try launchFixtureApp(state: "sidebar-overlay")
        app.typeKey("e", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        let edgeCoordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edgeCoordinate.hover()
        Thread.sleep(forTimeInterval: 0.6)
        try capture(window, state: "sidebar-overlay")
        app.terminate()
    }

    // MARK: - 14. Task-first

    func testTaskFirst() throws {
        let taskDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-visual-pass-tasks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: taskDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        let fixtures: [(String, String)] = [
            ("task-1", "status: inbox"),
            ("task-2", "status: backlog"),
            ("task-3", "status: running"),
            ("task-4", "status: needs-you"),
        ]
        for (name, statusLine) in fixtures {
            let content = """
            ---
            title: \(name) fixture
            \(statusLine)
            created: \(now)
            project: switchboard
            source: unknown
            ---
            ## Goal

            Visual-pass fixture task.
            """
            try? content.write(
                to: taskDir.appendingPathComponent("\(name).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let defaultsDomain = "com.seansmithdesign.ghostties.dev"
        let setResult = Process()
        setResult.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        setResult.arguments = ["write", defaultsDomain, "ghostties.sidebarViewMode", "taskFirst"]
        try? setResult.run()
        setResult.waitUntilExit()

        defer {
            let deleteResult = Process()
            deleteResult.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            deleteResult.arguments = ["delete", defaultsDomain, "ghostties.sidebarViewMode"]
            try? deleteResult.run()
            deleteResult.waitUntilExit()
        }

        let app = try launchFixtureApp(
            state: "task-first",
            extraEnvironment: ["GHOSTTIES_TASKS_DIR": taskDir.path]
        )
        Thread.sleep(forTimeInterval: 0.5)
        try capture(app.windows.firstMatch, state: "task-first")
        app.terminate()
    }

    // MARK: - 15. Browser

    func testBrowser() throws {
        let cefDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-visual-pass-cef-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cefDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cefDir) }

        let app = try launchFixtureApp(
            state: "browser",
            extraEnvironment: [
                "GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER": "1",
                "GHOSTTIES_CEF_APP_SUPPORT_DIR": cefDir.path,
            ]
        )
        Thread.sleep(forTimeInterval: 4.0)

        guard app.state == .runningForeground else {
            unreachable("browser", "app died or backgrounded after auto-open-browser; state=\(app.state.rawValue)")
            return
        }
        try capture(app.windows.firstMatch, state: "browser")
        app.terminate()
    }

    // MARK: - 16. Menu bar

    func testMenuBar() throws {
        let app = try launchFixtureApp(state: "menu-bar")
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 3) else {
            unreachable("menu-bar", "no status item queryable via app.statusItems")
            app.terminate()
            return
        }
        statusItem.click()
        Thread.sleep(forTimeInterval: 0.5)
        let popover = app.popovers.firstMatch
        if popover.waitForExistence(timeout: 2) {
            try capture(popover, state: "menu-bar")
        } else {
            unreachable("menu-bar", "status item clicked but no popover element found")
        }
        app.terminate()
    }

    // MARK: - 17. Onboarding

    func testOnboarding() throws {
        // OnboardingSheet is presented from `WorkspaceSidebarView` based on a
        // persisted `hasSeenOnboarding` flag, not from any AppDelegate menu
        // item — grep of AppDelegate found no onboarding reference.
        unreachable("onboarding", "not reachable from a menu item; gated by a persisted hasSeenOnboarding flag with no menu trigger")
    }

    // MARK: - 18. Window min width

    func testWindowMinWidth() throws {
        let app = try launchFixtureApp(state: "window-min-width")
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        // Guess: drag the bottom-right corner toward the top-left to force
        // the window to its minimum width, using normalized coordinates.
        let bottomRight = window.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.999))
        let target = window.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.999))
        bottomRight.press(forDuration: 0.1, thenDragTo: target)
        Thread.sleep(forTimeInterval: 0.5)
        let newFrame = window.frame
        guard newFrame.width < originalFrame.width else {
            unreachable("window-min-width", "drag-resize did not reduce window width (before=\(originalFrame.width), after=\(newFrame.width))")
            app.terminate()
            return
        }
        try capture(window, state: "window-min-width")
        app.terminate()
    }
}
