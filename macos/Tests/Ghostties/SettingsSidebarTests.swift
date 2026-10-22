import AppKit
import SwiftUI
import XCTest
import GhosttyKit
import GhosttiesCore
@testable import Ghostty

/// "Settings is your sidebar" (settings-general card 05): Cmd+, opens the
/// app's Settings window on a copy of the sidebar's project list, each
/// project's icon and new-session default are edited there, and the old
/// General + Appearance tabs live one link away as "App Settings".
///
/// Stores are persistence-disabled (`WorkspaceStore(testingProjects:)`) or
/// load from an injected temp dir (`WorkspaceStore(testingStateDirectory:)`);
/// nothing sets `GHOSTTIES_STATE_DIR`. Icon stores use injected temp dirs.
@MainActor
final class SettingsSidebarTests: XCTestCase {
    /// Kept alive for the life of the test process: a surface must never
    /// outlive the `ghostty_app_t` it was created from.
    private static var apps: [Ghostty.App] = []

    private func project(_ name: String, pinned: Bool = false) -> Project {
        Project(name: name, rootPath: "/tmp/ghostties-settings-sidebar/\(name)", isPinned: pinned)
    }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsSidebarTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeController(_ store: WorkspaceStore) throws -> GhosttiesSettingsWindowController {
        let icons = try tempDir("icons")
        let controller = GhosttiesSettingsWindowController(
            store: store,
            iconStore: ProjectIconStore(
                cacheDirectory: icons.appendingPathComponent("cache"),
                supportDirectory: icons.appendingPathComponent("support")
            ),
            refreshesIcons: false
        )
        addTeardownBlock { @MainActor in controller.window?.close() }
        return controller
    }

    // MARK: - Cmd+,

    /// The app menu's Cmd+, item is "Settings…", and the `open_config`
    /// keybind (Cmd+, by default), performed through a real libghostty
    /// surface, opens the Settings window on the projects pane. The config
    /// file is never opened.
    func testCmdCommaOpensSettingsWindowNotConfigFile() async throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate, "test host has no AppDelegate")
        let settingsItem = try XCTUnwrap(
            Self.menuItems(NSApp.mainMenu).first { $0.action == #selector(AppDelegate.openSettings(_:)) },
            "no menu item calls openSettings:"
        )
        XCTAssertEqual(settingsItem.title, "Settings\u{2026}")
        XCTAssertEqual(settingsItem.keyEquivalent, ",")
        XCTAssertTrue(settingsItem.keyEquivalentModifierMask.contains(.command))
        _ = delegate

        var openedConfigFiles: [String] = []
        Ghostty.App.openConfigFileOverrideForTesting = { openedConfigFiles.append($0) }
        defer { Ghostty.App.openConfigFileOverrideForTesting = nil }
        let settings = GhosttiesSettingsWindowController.shared
        settings.window?.close()
        addTeardownBlock { @MainActor in GhosttiesSettingsWindowController.shared.window?.close() }

        let app = try makeApp()
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/cat"
        config.workingDirectory = NSTemporaryDirectory()
        let view = Ghostty.SurfaceView(try XCTUnwrap(app.app), baseConfig: config)
        let surface = try XCTUnwrap(view.surfaceModel)
        XCTAssertTrue(surface.perform(action: "open_config"), "open_config is not a valid binding action")

        let deadline = Date().addingTimeInterval(3)
        while settings.window?.isVisible != true, openedConfigFiles.isEmpty, Date() < deadline {
            app.appTick()
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(openedConfigFiles, [], "open_config opened the config file instead of Settings")
        XCTAssertEqual(settings.window?.isVisible, true, "open_config did not show the Settings window")
        XCTAssertEqual(settings.pane, .projects)
    }

    // MARK: - Projects pane

    /// The Settings list is the sidebar's list, in the sidebar's order:
    /// pinned in manual order, then the rest by name.
    func testSettingsListOrderEqualsSidebarOrder() throws {
        let store = WorkspaceStore(testingProjects: [
            project("kiln"), project("switchboard", pinned: true), project("harbor"),
            project("atlas-api", pinned: true), project("Beacon"),
        ])
        let model = ProjectsSettingsModel(store: store, iconStore: ProjectIconStore(
            cacheDirectory: try tempDir("c"), supportDirectory: try tempDir("s")
        ))
        XCTAssertEqual(model.projects.map(\.id), store.projectsInDisplayOrder().map(\.id))
        XCTAssertEqual(
            model.projects.map(\.name),
            SidebarProjectGroup.make(active: [], projects: store.projects).map(\.name),
            "Settings must list projects in the one-view sidebar's order"
        )
    }

    /// `show(projectId:)` (the project menu's "Settings…") lands on that
    /// project; plain `show()` (Cmd+,) lands on the current one.
    func testShowProjectIdSelectsThatProject() throws {
        let a = project("atlas-api"), b = project("fieldwork")
        let store = WorkspaceStore(testingProjects: [a, b])
        let controller = try makeController(store)

        controller.show(projectId: b.id)
        XCTAssertEqual(controller.pane, .projects)
        XCTAssertEqual(controller.projects.selectedProjectId, b.id)

        controller.show(projectId: a.id)
        XCTAssertEqual(controller.projects.selectedProjectId, a.id)
    }

    // MARK: - App Settings

    /// App Settings is one link from the projects pane, Appearance is
    /// reachable in it with its tab toolbar, and "← Your sidebar" returns.
    func testAppSettingsAppearanceIsReachableAndLinksBack() throws {
        let store = WorkspaceStore(testingProjects: [project("atlas-api")])
        let controller = try makeController(store)

        controller.show()
        XCTAssertEqual(controller.pane, .projects)

        controller.projects.openAppSettings()
        XCTAssertEqual(controller.pane, .app(.general))

        controller.show(tab: .appearance)
        XCTAssertEqual(controller.pane, .app(.appearance))
        let labels = controller.window?.toolbar?.items.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Appearance"), "App Settings lost its tab toolbar: \(labels)")

        controller.backToSidebar()
        XCTAssertEqual(controller.pane, .projects)
        XCTAssertTrue(controller.window?.toolbar?.items.isEmpty ?? true, "the tab toolbar must not show over the projects pane")

        // And there again, after a round trip.
        controller.show(tab: .appearance)
        XCTAssertEqual(controller.pane, .app(.appearance))
        let again = controller.window?.toolbar?.items.map(\.label) ?? []
        XCTAssertTrue(again.contains("Appearance"), "tab toolbar missing after returning: \(again)")
    }

    // MARK: - Old workspace.json

    /// A workspace.json from before these fields loads, keeps its default
    /// template as the new-session default (so nothing changes for the
    /// user), and writes back without the new keys.
    func testOldWorkspaceJSONRoundTripsAndKeepsItsDefaultTemplate() async throws {
        let dir = try tempDir("state")
        let claude = AgentTemplate.claudeCode.id.uuidString
        let old = """
        {"projects":[{"id":"11111111-1111-1111-1111-111111111111","name":"atlas","rootPath":"/tmp/atlas",\
        "isPinned":false,"defaultTemplateId":"\(claude)"},\
        {"id":"22222222-2222-2222-2222-222222222222","name":"wren","rootPath":"/tmp/wren","isPinned":true}],\
        "sessions":[],"templates":[],"sidebarMode":0,"hasShownPinMigrationNotice":true,\
        "hasDismissedPinMigrationNotice":true}
        """
        try Data(old.utf8).write(to: dir.appendingPathComponent("workspace.json"))

        let store = WorkspaceStore(testingStateDirectory: dir)
        let atlas = try XCTUnwrap(store.projects.first { $0.name == "atlas" })
        let wren = try XCTUnwrap(store.projects.first { $0.name == "wren" })
        XCTAssertNil(atlas.newSessionDefault)
        XCTAssertEqual(SessionTemplateResolver.newSessionDefault(for: atlas), .template(AgentTemplate.claudeCode.id))
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: atlas, store: store).id, AgentTemplate.claudeCode.id)
        XCTAssertEqual(SessionTemplateResolver.newSessionDefault(for: wren), .shell)
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: wren, store: store).id, AgentTemplate.shell.id)

        // A write (pin twice: no net change) and a reload.
        store.togglePin(id: atlas.id)
        store.togglePin(id: atlas.id)
        await store.flushPersistenceForTesting()
        let written = try String(contentsOf: dir.appendingPathComponent("workspace.json"), encoding: .utf8)
        XCTAssertFalse(written.contains("newSessionDefault"))
        XCTAssertFalse(written.contains("iconStyle"))
        XCTAssertFalse(written.contains("lastTemplateId"))
        let reloaded = WorkspaceStore(testingStateDirectory: dir)
        XCTAssertEqual(reloaded.projects, store.projects)
    }

    // MARK: - Name

    /// Renaming in Settings updates the store at once (the sidebar reads it)
    /// and survives a reload from workspace.json. A blank name is ignored.
    func testRenameInSettingsPersistsAcrossReload() async throws {
        let dir = try tempDir("rename-state")
        let seed = """
        {"projects":[{"id":"11111111-1111-1111-1111-111111111111","name":"atlas","rootPath":"/tmp/atlas",\
        "isPinned":false}],"sessions":[],"templates":[],"sidebarMode":0,\
        "hasShownPinMigrationNotice":true,"hasDismissedPinMigrationNotice":true}
        """
        try Data(seed.utf8).write(to: dir.appendingPathComponent("workspace.json"))

        let store = WorkspaceStore(testingStateDirectory: dir)
        let id = try XCTUnwrap(store.projects.first?.id)
        let model = ProjectsSettingsModel(store: store, iconStore: ProjectIconStore(
            cacheDirectory: try tempDir("c"), supportDirectory: try tempDir("s")
        ))

        model.rename(id, to: "  harbor  ")
        XCTAssertEqual(model.selectedProject?.name, "harbor")
        XCTAssertEqual(store.projects.first?.name, "harbor")

        model.rename(id, to: "   ")
        XCTAssertEqual(store.projects.first?.name, "harbor", "a blank name is never stored")

        await store.flushPersistenceForTesting()
        XCTAssertEqual(WorkspaceStore(testingStateDirectory: dir).projects.first?.name, "harbor")
    }

    // MARK: - New-session default

    func testNewSessionDefaultShellLastUsedAndTemplate() {
        var p = project("atlas-api")
        let store = WorkspaceStore(testingProjects: [p])
        let claude = AgentTemplate.claudeCode
        let codex = AgentTemplate.codex

        // Nothing set: Shell.
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, AgentTemplate.shell.id)

        // Shell ignores the last-used template.
        p.newSessionDefault = .shell
        p.lastTemplateId = claude.id
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, AgentTemplate.shell.id)

        // Last used follows it, and is Shell before anything was used.
        p.newSessionDefault = .lastUsed
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, claude.id)
        p.lastTemplateId = nil
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, AgentTemplate.shell.id)

        // A specific template, whatever was last used; a deleted one is Shell.
        p.newSessionDefault = .template(codex.id)
        p.lastTemplateId = claude.id
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, codex.id)
        p.newSessionDefault = .template(UUID())
        XCTAssertEqual(SessionTemplateResolver.newSessionTemplate(for: p, store: store).id, AgentTemplate.shell.id)
    }

    /// The Settings control writes the new-session default and keeps
    /// `defaultTemplateId` (task cascade, Option+"+", composer order) in
    /// step: a specific template is the project's default template; Shell
    /// and Last used are "no fixed default".
    func testSettingNewSessionDefaultKeepsDefaultTemplateIdInStep() throws {
        let p = project("atlas-api")
        let store = WorkspaceStore(testingProjects: [p])

        store.setNewSessionDefault(.template(AgentTemplate.claudeCode.id), for: p.id)
        var saved = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(saved.newSessionDefault, .template(AgentTemplate.claudeCode.id))
        XCTAssertEqual(saved.defaultTemplateId, AgentTemplate.claudeCode.id)

        store.setNewSessionDefault(.lastUsed, for: p.id)
        saved = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(saved.newSessionDefault, .lastUsed)
        XCTAssertNil(saved.defaultTemplateId)

        store.setNewSessionDefault(.shell, for: p.id)
        saved = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(saved.newSessionDefault, .shell)
        XCTAssertNil(saved.defaultTemplateId)
    }

    /// Every successful create records the project's last-used template,
    /// except a browser session (#256: the browser never becomes a default
    /// by accident).
    func testLastTemplateRecordExcludesBrowser() throws {
        let p = project("atlas-api")
        let store = WorkspaceStore(testingProjects: [p])

        store.recordSessionCreated(template: .browser, projectId: p.id)
        XCTAssertNil(store.projects.first?.lastTemplateId)

        store.recordSessionCreated(template: .claudeCode, projectId: p.id)
        XCTAssertEqual(store.projects.first?.lastTemplateId, AgentTemplate.claudeCode.id)

        store.recordSessionCreated(template: .browser, projectId: p.id)
        XCTAssertEqual(store.projects.first?.lastTemplateId, AgentTemplate.claudeCode.id, "a browser session overwrote Last used")

        store.recordSessionCreated(template: .shell, projectId: p.id)
        XCTAssertEqual(store.projects.first?.lastTemplateId, AgentTemplate.shell.id)
    }

    // MARK: - Icon editing

    /// Choose Image… sets `iconStyle = .file` before the override lands, so
    /// the refresh that style change sets off runs while the image is still
    /// being normalized. That interleaved refresh must not drop the chosen
    /// image: it ends up copied, shown, and the style stays `.file`.
    func testChooseImageSurvivesAnInterleavedRefresh() async throws {
        let root = try tempDir("root")
        try ProjectIconFixtures.writePNG(root, "public/apple-touch-icon.png", pixels: 64)
        let picked = try ProjectIconFixtures.writePNG(try tempDir("picked"), "mine.png", pixels: 512)
        let support = try tempDir("support")
        let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: support)
        let p = Project(name: "fieldwork", rootPath: root.path)
        let store = WorkspaceStore(testingProjects: [p])
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)

        let choosing = _Concurrency.Task { try await model.chooseImage(from: picked, for: p.id) }
        await _Concurrency.Task.yield()
        // The refresh `ProjectIconRefresh` runs for the style change.
        let current = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(current.iconStyle, .file, "iconStyle must be .file before the override lands")
        await iconStore.refresh(current)
        try await choosing.value

        XCTAssertEqual(store.projects.first?.iconStyle, .file)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: support.appendingPathComponent("\(p.id.uuidString).png").path),
            "the chosen image was never copied into Application Support"
        )
        let shown = try XCTUnwrap(iconStore.image(for: p.id))
        XCTAssertEqual(shown.size.width, 128, "the tile shows the detected 64px icon, not the chosen image")

        // And a later refresh (launch, Settings open) still shows it.
        await iconStore.refresh(try XCTUnwrap(store.projects.first))
        XCTAssertEqual(iconStore.image(for: p.id)?.size.width, 128)
    }

    /// Choose Image…, then Auto or Monogram before the image lands: the
    /// later choice wins. The late image is neither copied nor shown.
    func testLateChosenImageNeverOverwritesALaterAutoOrMonogram() async throws {
        for later in [ProjectIconStyle?.none, .monogram] {
            let root = try tempDir("root")
            let picked = try ProjectIconFixtures.writePNG(try tempDir("picked"), "mine.png", pixels: 512)
            let support = try tempDir("support")
            let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: support)
            let p = Project(name: "fieldwork", rootPath: root.path)
            let store = WorkspaceStore(testingProjects: [p])
            let model = ProjectsSettingsModel(store: store, iconStore: iconStore)

            let choosing = _Concurrency.Task { try await model.chooseImage(from: picked, for: p.id) }
            await _Concurrency.Task.yield()
            let switching = later == .monogram ? model.useMonogram(for: p.id) : model.useAutoIcon(for: p.id)
            try await choosing.value
            await switching.value

            let name = later == nil ? "Auto" : "Monogram"
            XCTAssertEqual(store.projects.first?.iconStyle, later, "\(name): the style changed back")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: support.appendingPathComponent("\(p.id.uuidString).png").path),
                "\(name): the late image was copied into Application Support"
            )
            XCTAssertNil(iconStore.image(for: p.id), "\(name): the late image is showing")
        }
    }

    /// Leaving `.file` deletes the copied image, so it isn't orphaned.
    func testLeavingChosenImageDeletesTheCopy() async throws {
        let picked = try ProjectIconFixtures.writePNG(try tempDir("picked"), "mine.png", pixels: 512)
        let support = try tempDir("support")
        let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: support)
        let p = Project(name: "fieldwork", rootPath: try tempDir("root").path)
        let store = WorkspaceStore(testingProjects: [p])
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)
        let copy = support.appendingPathComponent("\(p.id.uuidString).png")

        try await model.chooseImage(from: picked, for: p.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        await model.useMonogram(for: p.id).value
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "the copied image was orphaned")
    }

    /// Auto re-checks past the negative cache. The sidebar's own refresh
    /// for the same style change (not forced) starts right after; it must
    /// not cancel the re-check and leave the icon hidden by the cache.
    func testForcedRecheckSurvivesASupersedingRefresh() async throws {
        let root = try tempDir("root")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("public"), withIntermediateDirectories: true)
        let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: try tempDir("support"))
        let p = Project(name: "fieldwork", rootPath: root.path)

        await iconStore.refresh(p) // no icon yet: the negative cache records it
        try ProjectIconFixtures.writePNG(root, "public/apple-touch-icon.png", pixels: 64)
        await iconStore.refresh(p)
        XCTAssertNil(iconStore.image(for: p.id), "precondition: the negative cache hides the new icon")

        let forced = _Concurrency.Task { await iconStore.refresh(p, force: true) }
        await _Concurrency.Task.yield()
        await iconStore.refresh(p) // ProjectIconRefresh, for the same change
        await forced.value
        XCTAssertNotNil(iconStore.image(for: p.id), "the forced re-check was dropped; the negative cache won")
    }

    /// A chosen image that turns out unreadable puts the old style back,
    /// but not over a style picked while it was being read.
    func testFailedChooseDoesNotUndoALaterStyleChange() async throws {
        let junk = try ProjectIconFixtures.write(try tempDir("picked"), "junk.png", data: Data("not an image".utf8))
        let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: try tempDir("support"))
        let p = Project(name: "fieldwork", rootPath: try tempDir("root").path)
        let store = WorkspaceStore(testingProjects: [p])
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)

        let choosing = _Concurrency.Task { try await model.chooseImage(from: junk, for: p.id) }
        await _Concurrency.Task.yield()
        model.useMonogram(for: p.id)
        do {
            try await choosing.value
            XCTFail("an unreadable image was accepted")
        } catch {}
        XCTAssertEqual(store.projects.first?.iconStyle, .monogram, "the failed choose undid Monogram")
        XCTAssertNil(model.iconError, "an abandoned choose reported its error")

        // With nothing in between, a failure does put the old style back.
        do {
            try await model.chooseImage(from: junk, for: p.id)
            XCTFail("an unreadable image was accepted")
        } catch {}
        XCTAssertEqual(store.projects.first?.iconStyle, .monogram)
        XCTAssertNotNil(model.iconError)
    }

    /// Two chooses overlapping, the later one unreadable: the failure puts
    /// back the style from before the first choose (Auto), not the `.file`
    /// the first choose set, which would leave a `.file` tile with no file.
    func testOverlappingChoosesWithAFailureRestoreTheStyleFromBeforeBoth() async throws {
        let good = try ProjectIconFixtures.writePNG(try tempDir("picked"), "mine.png", pixels: 512)
        let junk = try ProjectIconFixtures.write(try tempDir("junk"), "junk.png", data: Data("not an image".utf8))
        let support = try tempDir("support")
        let iconStore = ProjectIconStore(cacheDirectory: try tempDir("cache"), supportDirectory: support)
        let p = Project(name: "fieldwork", rootPath: try tempDir("root").path)
        let store = WorkspaceStore(testingProjects: [p])
        let model = ProjectsSettingsModel(store: store, iconStore: iconStore)

        let first = _Concurrency.Task { try await model.chooseImage(from: good, for: p.id) }
        await _Concurrency.Task.yield()
        let second = _Concurrency.Task { try await model.chooseImage(from: junk, for: p.id) }
        try? await first.value
        do {
            try await second.value
            XCTFail("an unreadable image was accepted")
        } catch {}

        let copied = FileManager.default.fileExists(atPath: support.appendingPathComponent("\(p.id.uuidString).png").path)
        XCTAssertFalse(copied, "the superseded first image was copied anyway")
        XCTAssertNil(store.projects.first?.iconStyle, "left at \(String(describing: store.projects.first?.iconStyle)) with no file behind it")
        XCTAssertNotNil(model.iconError)
    }

    // MARK: - Command palette

    /// The palette's config entries run `open_config`, which opens Settings,
    /// so on macOS they are one entry that says so.
    func testCommandPaletteHasOneOpenSettingsEntry() throws {
        let app = try makeApp()
        let entries = app.config.commandPaletteEntries.filter { $0.actionKey == "open_config" }
        XCTAssertEqual(entries.map(\.title), ["Open Settings"])
        XCTAssertEqual(entries.first?.action, "open_config")
        // The palette's shortcut hint looks the entry up by its action.
        let shortcut = try XCTUnwrap(
            app.config.keyboardShortcut(for: try XCTUnwrap(entries.first).action),
            "Open Settings shows no shortcut hint"
        )
        XCTAssertEqual(shortcut.key, KeyEquivalent(","))
        XCTAssertEqual(shortcut.modifiers, .command)
    }

    // MARK: - Helpers

    private static func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        return menu.items.flatMap { [$0] + menuItems($0.submenu) }
    }

    private func makeApp() throws -> Ghostty.App {
        let dir = try tempDir("config")
        let configURL = dir.appendingPathComponent("config.ghostty")
        try "confirm-close-surface = false\n".write(to: configURL, atomically: true, encoding: .utf8)
        let app = Ghostty.App(configPath: configURL.path)
        Self.apps.append(app)
        return app
    }
}
