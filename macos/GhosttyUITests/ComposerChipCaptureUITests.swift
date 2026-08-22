import XCTest

/// Scratch capture rig for the composer breadcrumb chip (Slice A review,
/// 2026-08-22) — produces PNGs of the six chip states requested for Sean's
/// phone review. NOT part of the permanent suite: this file, and the
/// `GHOSTTIES_COMPOSER_CHIP_CAPTURE(_EMPTY)` fixture hook it depends on in
/// `WorkspaceStore.swift`, exist only on this scratch worktree/branch and
/// are not meant to be committed.
///
/// Deliberately NOT gated behind `IDE_DISABLED_OS_ACTIVITY_DT_MODE` (see
/// `MarketingCaptureUITests` for the same reasoning) — this must run from a
/// plain `xcodebuild test-without-building` CLI invocation.
///
/// Fixture, never real data: every launch sets
/// `GHOSTTIES_COMPOSER_CHIP_CAPTURE=1` (or `_EMPTY=1`) in the launch
/// ENVIRONMENT, never argv — an unrecognized argv token pops Ghostty's core
/// CLI parser's "Configuration Errors" dialog (verified the hard way by an
/// earlier capture rig). The fixture project cast (`atlas-api`, `fieldwork`,
/// `ghostties-website-redesign`) is invented; nothing here reads or writes
/// Sean's real `workspace.json`.
final class ComposerChipCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var outputDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-composer-chip-capture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private enum Fixture {
        case normal
        case empty
        case longNameOnly
    }

    private func makeApp(_ fixture: Fixture = .normal) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-ApplePersistenceIgnoreState", "YES",
            "-ghostties.sidebarViewMode", "projectFirst",
            "-ghostties.sidebarTab", "projects",
        ])
        let key: String
        switch fixture {
        case .normal: key = "GHOSTTIES_COMPOSER_CHIP_CAPTURE"
        case .empty: key = "GHOSTTIES_COMPOSER_CHIP_CAPTURE_EMPTY"
        case .longNameOnly: key = "GHOSTTIES_COMPOSER_CHIP_CAPTURE_LONGNAME"
        }
        app.launchEnvironment[key] = "1"
        return app
    }

    private func save(_ shot: XCUIScreenshot, name: String) throws {
        let path = outputDir.appendingPathComponent("\(name).png")
        try shot.pngRepresentation.write(to: path)
        print("CAPTURE_OUTPUT: \(path.path)")
    }

    // MARK: - 1. .anchored, resolved chip + remainder text

    func testAnchoredResolvedChip() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        let projectRow = app.buttons["atlas-api project, collapsed"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "atlas-api project row should exist")
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.3)

        let newSessionButton = app.buttons["New Session"].firstMatch
        XCTAssertTrue(newSessionButton.waitForExistence(timeout: 5), "New Session button should appear once expanded")
        newSessionButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        app.typeText("deploy pipeline")
        Thread.sleep(forTimeInterval: 0.3)

        try save(app.windows.firstMatch.screenshot(), name: "anchored-chip")
        app.terminate()
    }

    // MARK: - 2. .centered, resolved chip + remainder text

    func testCenteredResolvedChip() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.6)

        app.typeText("add tests")
        Thread.sleep(forTimeInterval: 0.3)

        try save(app.windows.firstMatch.screenshot(), name: "centered-chip")
        app.terminate()
    }

    // MARK: - 3. Unresolved chip ("Select project")

    func testUnresolvedChip() throws {
        let app = makeApp(.empty)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.6)

        try save(app.windows.firstMatch.screenshot(), name: "unresolved-chip")
        app.terminate()
    }

    // MARK: - 4. Inline project picker open

    func testInlinePickerOpen() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        app.typeKey("t", modifierFlags: [.command])
        Thread.sleep(forTimeInterval: 0.6)

        let chipButtons = app.buttons.matching(NSPredicate(format: "label == %@", "atlas-api"))
        XCTAssertTrue(chipButtons.firstMatch.waitForExistence(timeout: 5), "chip button should exist in the centered composer")
        // The chip button most likely to be the composer's (not the sidebar
        // row, which isn't a `Button`) is whichever exists — click all
        // matches defensively, the sidebar row is inert to a click here
        // since it's not a Button.
        chipButtons.allElementsBoundByIndex.forEach { $0.click() }
        Thread.sleep(forTimeInterval: 0.4)

        try save(app.windows.firstMatch.screenshot(), name: "inline-picker-open")
        app.terminate()
    }

    // MARK: - 5. .locked (no pill, plain secondary text + `›`)

    func testLockedChip() throws {
        let tempProjectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-project-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempProjectDir, withIntermediateDirectories: true)

        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        let newProjectButton = app.buttons["New Project"].firstMatch
        guard newProjectButton.waitForExistence(timeout: 5) else {
            app.terminate()
            throw XCTSkip("New Project toolbar button not reachable — could not drive the folder picker")
        }
        newProjectButton.click()
        Thread.sleep(forTimeInterval: 0.8)

        // "Go to Folder" sheet inside the NSOpenPanel — types an absolute
        // path directly rather than navigating Finder-style, so this stays
        // deterministic regardless of what's actually on disk.
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText(tempProjectDir.path)
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        let addProjectButton = app.buttons["Add Project"].firstMatch
        guard addProjectButton.waitForExistence(timeout: 5) else {
            app.terminate()
            throw XCTSkip("Add Project panel button not reachable — NSOpenPanel automation blocked")
        }
        // Neither `.click()` nor a synthesized coordinate click work here —
        // Xcode's automation classifies this NSOpenPanel confirm button as a
        // Touch Bar element and refuses both ("cannot be called with Touch
        // Bar elements"). It is also the panel's default button, so a
        // keyboard Return reaches it without touching the element at all.
        XCTAssertTrue(addProjectButton.isHittable, "Add Project button should be focused/default")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)

        try save(app.windows.firstMatch.screenshot(), name: "locked-chip")
        app.terminate()
    }

    // MARK: - 6. Long project name in `.anchored` — chip truncates, not the field

    func testAnchoredLongProjectName() throws {
        let app = makeApp(.longNameOnly)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)

        let projectRow = app.buttons["ghostties-website-redesign project, collapsed"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "long-name project row should exist")
        projectRow.click()
        // Longer settle than the other rows: this is the third/off-screen
        // project, so the sidebar has to scroll it into view before it
        // expands. Screenshotting before that settles anchors the popover to
        // a stale (pre-scroll) row position.
        Thread.sleep(forTimeInterval: 1.0)

        let newSessionButton = app.buttons["New Session"].firstMatch
        XCTAssertTrue(newSessionButton.waitForExistence(timeout: 5))
        newSessionButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        try save(app.windows.firstMatch.screenshot(), name: "anchored-chip-long-name")
        app.terminate()
    }
}
