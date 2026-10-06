import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Composer contract, beta.26: the offscreen ("O") flow rows.
///
/// Every test mounts the REAL `SessionComposerPalette` in an offscreen window
/// against an isolated `SessionComposerStore`, types with real key events sent
/// through `NSWindow.sendEvent`, and reads the result at
/// `dispatchOverrideForTesting` (the seam that replaces
/// `coordinator.createQuickSession`). Nothing here touches
/// `SessionComposerStore.shared`, `WorkspaceStore.shared`, or the Dev defaults
/// domain, except `x2_...` (see its note).
///
/// Row IDs match `composer-contract.md`. Each test names its row; the mutation
/// that turns it red is recorded in the harness report, not here (a comment
/// can't prove a run happened).
///
/// Not here, and why: E1 and X7 (and X1's terminal refocus and overlay-removal
/// half) live in `WorkspaceViewContainer`, which can only be built with a live
/// `Ghostty.App` and which reaches `WorkspaceStore.shared` and
/// `SessionComposerStore.shared` (the Dev domain) with no injection seam.
@MainActor
struct ComposerFlowTests {

    // MARK: - Shared helpers

    private static func sendKey(to window: NSWindow, type: NSEvent.EventType, chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: code
        ) else {
            Issue.record("could not build key event for \(chars.debugDescription)")
            return
        }
        window.sendEvent(event)
    }

    private static func press(_ chars: String, code: UInt16 = 0, in window: NSWindow) {
        sendKey(to: window, type: .keyDown, chars: chars, code: code)
        sendKey(to: window, type: .keyUp, chars: chars, code: code)
    }

    /// A shortcut key the way the app delivers it: `NSApplication.sendEvent`
    /// offers a keyDown to the key window's `performKeyEquivalent` first (that
    /// is what fires a SwiftUI `.keyboardShortcut` button), and only then to
    /// the first responder. Plain `NSWindow.sendEvent` skips that step, so on a
    /// sheet Esc would reach AppKit's default `cancelOperation:`, which closes
    /// the sheet window behind SwiftUI's back (no `dismiss()`, no
    /// `.onDisappear`), a path no user can take.
    @discardableResult
    private static func pressShortcut(_ chars: String, code: UInt16, in window: NSWindow) -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: code
        ) else {
            Issue.record("could not build key event for \(chars.debugDescription)")
            return false
        }
        if window.performKeyEquivalent(with: event) { return true }
        window.sendEvent(event)
        return false
    }

    private static func type(_ text: String, in window: NSWindow) {
        for character in text {
            press(String(character), code: character == " " ? 49 : 0, in: window)
        }
    }

    /// Polls on the main actor (so SwiftUI, sheets and detached work can run)
    /// until `condition` holds or `timeout` elapses.
    private static func poll(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            try? await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    private static func descendants<V: NSView>(of root: NSView, as type: V.Type) -> [V] {
        var found: [V] = []
        func walk(_ view: NSView) {
            if let match = view as? V { found.append(match) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    // MARK: - Rig

    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private final class ClickThroughHost: TransparentHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// A borderless window can't become key by default; the palette's text view
    /// only needs a window to deliver events through, but key status keeps
    /// first-responder behaviour identical to the app.
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private struct Dispatched {
        let project: Project
        let template: AgentTemplate
        /// What `SessionCoordinator.createQuickSession` resolves as the cwd.
        var cwd: String { template.workingDirectory ?? project.rootPath }
    }

    /// One mounted composer: palette + isolated stores + offscreen window.
    @MainActor
    private final class Rig {
        let workspace: WorkspaceStore
        let composer = SessionComposerStore(isolatedForTesting: ())
        let window: KeyableWindow
        let hosting: NSHostingView<AnyView>
        private let log = Box<[Dispatched]>([])
        var dispatched: [Dispatched] { log.value }

        init(projects: [Project], binding: SessionComposerRequest.ProjectBinding = .open) {
            workspace = WorkspaceStore(testingProjects: projects, testingSessions: [])
            let log = self.log
            composer.dispatchOverrideForTesting = { project, template in
                log.value.append(Dispatched(project: project, template: template))
            }

            // Same sequence `WorkspaceViewContainer.presentComposerOverlay`
            // runs: open the store, THEN mount, so the palette's own
            // `onAppear` open() sees `wasOpen` and raises the focus trigger.
            composer.open(projectBinding: binding, workspaceStore: workspace)

            let composer = self.composer
            // Mirrors `SessionComposerOverlay.isPresented`: closing = cancel().
            let isPresented = Binding<Bool>(
                get: { composer.isOpen },
                set: { if !$0 { composer.cancel() } }
            )
            let palette = SessionComposerPalette(
                isPresented: isPresented,
                request: SessionComposerRequest(projectBinding: binding),
                composerStore: composer
            )
            .environmentObject(workspace)
            .environmentObject(SessionCoordinator())

            let size = NSSize(width: 900, height: 600)
            window = KeyableWindow(
                contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            hosting = NSHostingView(rootView: AnyView(palette.frame(width: size.width, height: size.height)))
            hosting.frame = NSRect(origin: .zero, size: size)
            window.contentView = hosting
            window.orderFrontRegardless()
            window.makeKey()
            hosting.layoutSubtreeIfNeeded()
        }

        deinit {
            let window = self.window
            MainActor.assumeIsolated { window.orderOut(nil) }
        }

        // MARK: Events

        func press(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
            ComposerFlowTests.sendKey(to: window, type: .keyDown, chars: chars, code: code, flags: flags)
            ComposerFlowTests.sendKey(to: window, type: .keyUp, chars: chars, code: code, flags: flags)
        }

        func type(_ text: String) {
            ComposerFlowTests.type(text, in: window)
        }

        /// The palette's field, found in the view tree.
        var field: ComposerGhostNSTextView? {
            func find(_ view: NSView) -> ComposerGhostNSTextView? {
                if let match = view as? ComposerGhostNSTextView { return match }
                for sub in view.subviews { if let match = find(sub) { return match } }
                return nil
            }
            return find(hosting)
        }

        func pressReturn() { press("\r", code: 36) }
        func pressEscape() { press("\u{1B}", code: 53) }

        // MARK: Waiting

        /// Polls on the main actor (so SwiftUI and the detached dispatch can
        /// run) until `condition` holds or `timeout` elapses. Never longer
        /// than the contract's 2s settle unless a row needs git.
        func settle(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
            await ComposerFlowTests.poll(timeout: timeout, condition)
        }

        /// Lets pending main-actor work run for `seconds` (used to prove a
        /// second dispatch does NOT arrive, which no condition can wait for).
        func idle(_ seconds: TimeInterval) async {
            try? await _Concurrency.Task.sleep(for: .seconds(seconds))
        }

        /// The palette raises first responder on the next runloop turn after
        /// mount (`ComposerGhostTextField.updateNSView`); typing before that
        /// goes to the hosting view and is silently lost.
        func waitForFocus() async {
            let focused = await settle { window.firstResponder === field }
            #expect(focused, "composer field never became first responder")
        }

        /// Types `text` and waits until the field and the store agree, which
        /// is also the point the palette has re-ranked and re-selected.
        func typeAndSettle(_ text: String) async {
            await waitForFocus()
            type(text)
            _ = await settle { composer.searchText == text }
            // One more turn so `onChange(of: query)` reseeds `selectedIndex`.
            await idle(0.1)
        }
    }

    // MARK: - Fixtures

    private nonisolated static func makeRoot(_ name: String) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("ghostties-flow-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `switchboard` is the contract's fixture project. `atlas` is more
    /// recently active, so the default cascade picks it: any test that lands
    /// in `switchboard` got there by what it typed, not by the default.
    private struct Fixture {
        let switchboardRoot = ComposerFlowTests.makeRoot("sb")
        let atlasRoot = ComposerFlowTests.makeRoot("atlas")
        let switchboard: Project
        let atlas: Project

        init() {
            switchboard = Project(name: "switchboard", rootPath: switchboardRoot, lastActiveAt: Date(timeIntervalSince1970: 100))
            atlas = Project(name: "atlas", rootPath: atlasRoot, lastActiveAt: Date(timeIntervalSince1970: 200))
        }

        var projects: [Project] { [switchboard, atlas] }

        func cleanup() {
            try? FileManager.default.removeItem(atPath: switchboardRoot)
            try? FileManager.default.removeItem(atPath: atlasRoot)
        }
    }

    // MARK: - P: typed commands

    /// P2. `switchboard ccp` + Return: command `ccp`, cwd the project root.
    @Test func p2_switchboardCcpSpawnsCcpInTheProjectRoot() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects)

        await rig.typeAndSettle("switchboard ccp")
        rig.pressReturn()

        #expect(await rig.settle { rig.dispatched.count >= 1 })
        #expect(rig.dispatched.count == 1)
        #expect(rig.dispatched.first?.project.id == fixture.switchboard.id)
        #expect(rig.dispatched.first?.template.buildCommand() == "'ccp'")
        #expect(rig.dispatched.first?.cwd == fixture.switchboardRoot)
    }

    /// P1. The contract's idiom: the quoted thread name must survive as ONE
    /// argv word. Asserted on the exact launch string `buildCommand()` makes.
    @Test func p1_switchboardCcoNamedThreadKeepsTheQuotedNameAsOneWord() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects)

        await rig.typeAndSettle(#"switchboard cco -n "smoke thread""#)
        rig.pressReturn()

        #expect(await rig.settle { rig.dispatched.count >= 1 })
        #expect(rig.dispatched.count == 1)
        #expect(rig.dispatched.first?.project.id == fixture.switchboard.id)
        #expect(rig.dispatched.first?.template.buildCommand() == "'cco' '-n' 'smoke thread'")
        #expect(rig.dispatched.first?.cwd == fixture.switchboardRoot)
    }

    /// P7. Characterised, then locked: a first word that names no project is
    /// NOT a project. It must never create one; what runs is the whole line,
    /// as a command, in the project the composer already had.
    @Test func p7_unknownRepoRunsTheWholeLineInTheDefaultProjectAndCreatesNoProject() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects)
        let before = rig.workspace.projects.map(\.id)

        await rig.typeAndSettle("nosuchrepo cco")
        rig.pressReturn()

        #expect(await rig.settle { rig.dispatched.count >= 1 })
        #expect(rig.dispatched.count == 1)
        #expect(rig.dispatched.first?.project.id == fixture.atlas.id)
        #expect(rig.dispatched.first?.template.buildCommand() == "'nosuchrepo' 'cco'")
        #expect(rig.dispatched.first?.cwd == fixture.atlasRoot)
        #expect(rig.workspace.projects.map(\.id) == before)
        #expect(!rig.workspace.projects.contains { $0.name == "nosuchrepo" })
    }

    // MARK: - X: exits and refusals

    /// X1 (store half). Esc closes, clears the query, spawns nothing. The
    /// terminal refocus and the 0.2s overlay removal live in
    /// `WorkspaceViewContainer`, which needs a live `Ghostty.App`; not covered.
    @Test func x1_escapeClosesWithoutSpawning() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects)

        await rig.typeAndSettle("swi")
        #expect(rig.composer.isOpen)
        rig.pressEscape()

        #expect(await rig.settle { !rig.composer.isOpen })
        #expect(rig.composer.searchText == "")
        await rig.idle(0.3)
        #expect(rig.dispatched.isEmpty)
    }

    /// X3. Return with nothing to pick shakes and stays: no spawn, still open,
    /// text kept. With any project present the composer always has a row (the
    /// Run row takes any text), so "no match" is only reachable with no
    /// projects; that is the state used here.
    @Test func x3_returnWithNoMatchSpawnsNothingAndStaysOpen() async {
        let rig = Rig(projects: [])

        await rig.typeAndSettle("ccp")
        rig.pressReturn()

        await rig.idle(0.5)
        #expect(rig.dispatched.isEmpty)
        #expect(rig.composer.isOpen)
        #expect(rig.composer.searchText == "ccp")
    }

    /// X4. Two Returns in the same turn spawn exactly one session. The count
    /// is 1, not "at most 1": a swallowed first Return must fail too.
    @Test func x4_doubleReturnSpawnsOnce() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects)

        await rig.typeAndSettle("switchboard ccp")
        rig.pressReturn()
        rig.pressReturn()

        #expect(await rig.settle { rig.dispatched.count >= 1 })
        await rig.idle(0.5)
        #expect(rig.dispatched.count == 1)
        #expect(rig.dispatched.first?.project.id == fixture.switchboard.id)
    }

    /// X5. No projects: Return on an empty field spawns nothing, the composer
    /// stays open with no project selected and no error, and the empty-state
    /// copy is the first-run lifeline. (`emptyResultsCopy` is asserted as the
    /// copy function; the palette does not render it today, so the on-screen
    /// text is not covered here.)
    @Test func x5_noProjectsSpawnsNothing() async {
        let rig = Rig(projects: [])

        await rig.waitForFocus()
        rig.pressReturn()

        await rig.idle(0.5)
        #expect(rig.dispatched.isEmpty)
        #expect(rig.composer.isOpen)
        #expect(rig.composer.selectedProjectId == nil)
        #expect(rig.composer.writeError == nil)
        #expect(SessionComposerCommandParser.emptyResultsCopy(isProjectsEmpty: true) == "Add project…")
    }

    /// X6. A worktree pick whose directory is gone is refused at commit: an
    /// error on screen, nothing spawned, composer still open.
    @Test func x6_staleWorktreePickIsRefused() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let rig = Rig(projects: fixture.projects, binding: .prefilled(fixture.switchboard))
        let gone = fixture.switchboardRoot + "-deleted-worktree"

        await rig.waitForFocus()
        rig.composer.selectedWorktreePath = gone
        await rig.typeAndSettle("ccp")
        #expect(rig.composer.selectedWorktreePath == gone)
        rig.pressReturn()

        #expect(await rig.settle { rig.composer.writeError != nil })
        #expect(rig.composer.writeError?.contains(gone) == true)
        await rig.idle(0.3)
        #expect(rig.dispatched.isEmpty)
        #expect(rig.composer.isOpen)
    }

    // MARK: - P5 (real git)

    private static func git(_ args: [String], in dir: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", dir,
                          "-c", "user.email=test@ghostties.test", "-c", "user.name=Ghostties Test"] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// P5. An unknown branch after `>` offers "Create branch"; Return on that
    /// row makes the worktree and spawns the typed command INSIDE it.
    @Test func p5_unknownBranchCreatesTheWorktreeAndSpawnsThere() async {
        let parent = Self.makeRoot("p5")
        defer { try? FileManager.default.removeItem(atPath: parent) }
        let repo = (parent as NSString).appendingPathComponent("switchboard")
        try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = Self.git(["init", "-q", "-b", "main"], in: repo)
        _ = Self.git(["commit", "-q", "--allow-empty", "-m", "init"], in: repo)

        let project = Project(name: "switchboard", rootPath: repo)
        let rig = Rig(projects: [project], binding: .prefilled(project))
        await rig.waitForFocus()
        // The branch list loads from git asynchronously; an unknown branch
        // reads as `.pending` (rejected) until it has.
        let loaded = await rig.settle(timeout: 12) { rig.composer.isGitRepo && rig.composer.worktreesProjectId == project.id }
        #expect(loaded, "worktree list never loaded")
        let before = Self.git(["worktree", "list", "--porcelain"], in: repo)
        #expect(!before.contains("feat-x"))

        await rig.typeAndSettle("switchboard > feat-x > ccp")
        rig.pressReturn()

        // The FIRST Return must create the worktree and spawn in it — no retry.
        let spawned = await rig.settle(timeout: 12) { rig.dispatched.count >= 1 }
        #expect(spawned, "no spawn; writeError=\(rig.composer.writeError ?? "nil") creating=\(rig.composer.isCreatingWorktree) text=\(rig.composer.searchText.debugDescription)")
        let after = Self.git(["worktree", "list", "--porcelain"], in: repo)
        #expect(after.contains("branch refs/heads/feat-x"))
        let worktreePath = after.components(separatedBy: "\n")
            .reduce(into: (current: "", match: "")) { acc, line in
                if line.hasPrefix("worktree ") { acc.current = String(line.dropFirst("worktree ".count)) }
                if line == "branch refs/heads/feat-x" { acc.match = acc.current }
            }.match
        #expect(!worktreePath.isEmpty)
        #expect(rig.dispatched.count == 1)
        #expect(rig.dispatched.first?.template.buildCommand() == "'ccp'")
        #expect(rig.dispatched.first?.cwd == worktreePath)
        #expect(rig.dispatched.first?.cwd != repo)
    }

    // MARK: - Templates rig (project settings > Templates)

    /// The real `ProjectTemplatesSection` in an offscreen titled window (sheets
    /// need one). Rows are reached the way the app reaches them: the context
    /// menu SwiftUI builds for a row (`NSView.menu(for:)`), then the menu item's
    /// own action, which runs the section's real `perform(_:on:)`.
    @MainActor
    private final class TemplatesRig {
        let workspace = WorkspaceStore(testingProjects: [], testingSessions: [])
        let composer = SessionComposerStore(isolatedForTesting: ())
        let window: KeyableWindow
        let hosting: NSHostingView<AnyView>

        init() {
            let view = ProjectTemplatesSection(composerStore: composer).environmentObject(workspace)
            hosting = NSHostingView(rootView: AnyView(view))
            let size = hosting.fittingSize
            window = KeyableWindow(
                contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            hosting.frame = NSRect(origin: .zero, size: size)
            window.contentView = hosting
            window.orderFrontRegardless()
            window.makeKey()
            hosting.layoutSubtreeIfNeeded()
        }

        deinit {
            let window = self.window
            MainActor.assumeIsolated { window.orderOut(nil) }
        }

        private func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: hosting.convert(point, to: nil),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }

        /// Scans the rows bottom to top for a context menu offering `title`.
        func rowMenu(offering title: String) -> NSMenu? {
            var y: CGFloat = 0
            while y < hosting.bounds.height {
                if let menu = hosting.menu(for: event(.rightMouseDown, at: NSPoint(x: 60, y: y))),
                   menu.items.contains(where: { $0.title == title }) {
                    return menu
                }
                y += 6
            }
            return nil
        }

        /// `rowMenu`, polled: a row added a moment ago needs a layout turn first.
        func waitForRowMenu(offering title: String) async -> NSMenu? {
            _ = await ComposerFlowTests.poll { self.rowMenu(offering: title) != nil }
            return rowMenu(offering: title)
        }

        /// Runs the menu item named `title` (the section's real action).
        func choose(_ title: String, from menu: NSMenu) {
            guard let index = menu.items.firstIndex(where: { $0.title == title }) else {
                Issue.record("menu has no \(title.debugDescription): \(menu.items.map(\.title))")
                return
            }
            menu.performActionForItem(at: index)
        }

        func nameField() -> NSTextField? {
            ComposerFlowTests.descendants(of: hosting, as: NSTextField.self)
                .first { $0.placeholderString == "Template name" }
        }

        /// Clicks up the left edge until the "New template" button turns into
        /// its name field. Left clicks on the rows and labels do nothing.
        func clickNewTemplate() async -> Bool {
            var y: CGFloat = 2
            while y < hosting.bounds.height {
                let point = NSPoint(x: 40, y: y)
                window.sendEvent(event(.leftMouseDown, at: point))
                window.sendEvent(event(.leftMouseUp, at: point))
                if await ComposerFlowTests.poll(timeout: 0.1, { self.nameField() != nil }) { return true }
                y += 8
            }
            return false
        }

        func sheet() async -> NSWindow? {
            _ = await ComposerFlowTests.poll { self.window.attachedSheet != nil }
            return window.attachedSheet
        }

        func sheetClosed() async -> Bool {
            await ComposerFlowTests.poll { self.window.attachedSheet == nil }
        }
    }

    // MARK: - T: templates

    /// T1. A new template is added the moment its name is submitted, then
    /// configured in the edit sheet; Cancel must take it back out.
    @Test func t1_newTemplateCancelDiscardsIt() async {
        let rig = TemplatesRig()
        let before = rig.workspace.templates.count

        #expect(await rig.clickNewTemplate(), "New template never turned into its name field")
        guard let field = rig.nameField() else { return }
        rig.window.makeFirstResponder(field)
        ComposerFlowTests.type("Scratch", in: rig.window)
        ComposerFlowTests.press("\r", code: 36, in: rig.window)

        guard let sheet = await rig.sheet() else {
            Issue.record("edit sheet never opened")
            return
        }
        #expect(rig.workspace.templates.count == before + 1)

        let handled = ComposerFlowTests.pressShortcut("\u{1B}", code: 53, in: sheet)
        #expect(handled, "Esc did not reach the sheet's Cancel button")
        #expect(await rig.sheetClosed())

        // In this host SwiftUI never finishes a sheet's dismissal (measured:
        // even a bare sheet's `.onDisappear` stays silent after `dismiss()`),
        // so the form is still alive. Dropping the sheet window's content view
        // is the removal that fires `.onDisappear`, which is what takes an
        // abandoned template out of the store. The Cancel press and the
        // section's "this one is fresh" wiring above are real; only the
        // removal itself is standing in for the animation's completion.
        sheet.contentView = nil
        #expect(await ComposerFlowTests.poll { rig.workspace.templates.count == before })
        #expect(!rig.workspace.templates.contains { $0.name == "Scratch" })
    }

    /// T2. Edit a user template, type a command, Save: the store holds it and
    /// so does what a relaunch would read back. (Persistence is exercised as
    /// the same Codable round trip `WorkspacePersistence` writes and reads;
    /// the debounced disk write itself is off in the testing store.)
    @Test func t2_editAndSavePersistsTheCommand() async throws {
        let rig = TemplatesRig()
        let created = rig.workspace.addTemplate(AgentTemplate(name: "Mine", kind: .custom))
        #expect(created.command == nil)

        guard let menu = await rig.waitForRowMenu(offering: "Edit...") else {
            Issue.record("no row offered Edit...")
            return
        }
        rig.choose("Edit...", from: menu)
        guard let sheet = await rig.sheet(), let content = sheet.contentView else {
            Issue.record("edit sheet never opened")
            return
        }
        guard let command = ComposerFlowTests.descendants(of: content, as: NSTextField.self)
            .first(where: { $0.placeholderString == "e.g. claude, python3" }) else {
            Issue.record("no command field in the sheet")
            return
        }
        sheet.makeFirstResponder(command)
        ComposerFlowTests.type("codex", in: sheet)
        sheet.makeFirstResponder(nil)
        ComposerFlowTests.pressShortcut("\r", code: 36, in: sheet)

        #expect(await rig.sheetClosed())
        let saved = rig.workspace.templates.first { $0.id == created.id }
        #expect(saved?.command == "codex")

        let state = WorkspacePersistence.State(templates: rig.workspace.templates.filter { !$0.isDefault })
        let reloaded = try JSONDecoder().decode(
            WorkspacePersistence.State.self,
            from: JSONEncoder().encode(state)
        )
        #expect(reloaded.templates.first { $0.id == created.id }?.command == "codex")
    }

    /// T4 (Sean's D4 = keep). "Duplicate and Edit..." on a built-in adds the
    /// copy at once; Cancel on its sheet KEEPS the copy, because a duplicate
    /// carries its source's real command and is already configured.
    @Test func t4_duplicateAndEditThenCancelKeepsTheCopy() async {
        let rig = TemplatesRig()
        let before = rig.workspace.templates.count

        guard let menu = await rig.waitForRowMenu(offering: "Duplicate and Edit...") else {
            Issue.record("no row offered Duplicate and Edit...")
            return
        }
        rig.choose("Duplicate and Edit...", from: menu)
        guard let sheet = await rig.sheet() else {
            Issue.record("edit sheet never opened")
            return
        }
        #expect(rig.workspace.templates.count == before + 1)
        let copy = rig.workspace.templates.last
        #expect(copy?.name.hasPrefix("Copy of ") == true)

        ComposerFlowTests.pressShortcut("\u{1B}", code: 53, in: sheet)

        #expect(await rig.sheetClosed())
        // Same stand-in as T1 for the dismissal animation: removing the sheet's
        // content fires `.onDisappear`, the one place a discard would happen.
        sheet.contentView = nil
        try? await _Concurrency.Task.sleep(for: .milliseconds(300))
        #expect(rig.workspace.templates.count == before + 1)
        #expect(rig.workspace.templates.contains { $0.id == copy?.id })
    }

    // MARK: - X2 (click outside)

    /// X2. The composer overlay's dismiss layer: a click on the terminal area
    /// closes the composer; a click in the titlebar band (traffic lights and
    /// drag region) does not, so the window can still be dragged.
    ///
    /// `SessionComposerOverlay` is hard-wired to `SessionComposerStore.shared`,
    /// which in a hosted run reads the Dev defaults domain. This test only
    /// opens and cancels it (neither writes), keeps pruning from writing by
    /// giving the throwaway workspace every template id the Dev domain has
    /// pinned, and asserts the composer's keys in `.standard` are untouched.
    @Test func x2_clickOutsideClosesButTheTitlebarBandDoesNot() async {
        await withSharedComposerStore {
            let shared = SessionComposerStore.shared
            let standard = UserDefaults.standard
            func composerKeys() -> [String: String] {
                Dictionary(uniqueKeysWithValues: standard.dictionaryRepresentation()
                    .filter { $0.key.lowercased().contains("composer") }
                    .map { ($0.key, String(describing: $0.value)) })
            }
            let defaultsBefore = composerKeys()
            defer {
                shared.cancel()
                #expect(composerKeys() == defaultsBefore, "x2 changed the Dev domain's composer keys")
            }
            #expect(!shared.isOpen, "shared composer was already open")

            let project = Project(name: "switchboard", rootPath: Self.makeRoot("x2"))
            defer { try? FileManager.default.removeItem(atPath: project.rootPath) }
            let workspace = WorkspaceStore(testingProjects: [project], testingSessions: [])
            for (index, id) in shared.pinnedTemplateIds.enumerated()
            where !workspace.templates.contains(where: { $0.id == id }) {
                workspace.addTemplate(AgentTemplate(id: id, name: "pinned-guard-\(index)", kind: .custom))
            }

            let size = NSSize(width: 900, height: 600)
            let overlay = SessionComposerOverlay(
                request: SessionComposerRequest(projectBinding: .open),
                centeringModel: ComposerCenteringModel()
            )
            .environmentObject(workspace)
            .environmentObject(SessionCoordinator())
            // The container's `composerOverlayHostingView` class. The app is not
            // active in a test run, so this window can't be key; in the app it is,
            // where a click is never a "first mouse". Accepting it here is that.
            let hosting = ClickThroughHost(rootView: AnyView(overlay))
            hosting.sizingOptions = []
            let window = KeyableWindow(
                contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            hosting.frame = NSRect(origin: .zero, size: size)
            window.contentView = hosting
            window.orderFrontRegardless()
            window.makeKey()
            hosting.layoutSubtreeIfNeeded()
            defer { window.orderOut(nil) }

            #expect(await Self.poll { shared.isOpen }, "overlay never opened the composer")
            _ = await Self.poll(timeout: 0.5) { false }  // let layout settle

            func click(at point: NSPoint) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(
                        with: type,
                        location: point,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 1
                    ) else { Issue.record("could not build mouse event"); return }
                    window.sendEvent(event)
                }
            }

            // Window coordinates are bottom-left origin: y near `size.height` is
            // the top, inside the 28pt band.
            click(at: NSPoint(x: 30, y: size.height - 10))
            _ = await Self.poll(timeout: 0.5) { false }
            #expect(shared.isOpen, "a click in the titlebar band closed the composer")

            click(at: NSPoint(x: 30, y: 30))
            #expect(await Self.poll { !shared.isOpen }, "a click on the terminal area did not close the composer")
        }
    }
}
