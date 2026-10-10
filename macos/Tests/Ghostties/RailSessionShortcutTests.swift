import AppKit
import Combine
import Foundation
import GhosttiesCore
import Testing
@testable import Ghostty

/// Cmd+Shift+] / Cmd+Shift+[ / Cmd+1-9 must switch sessions with the sidebar
/// collapsed to the rail, not only when it's pinned.
///
/// Drives a real `WorkspaceViewContainer` launched in `.collapsed` (so the
/// rail is the mounted sidebar tree) and posts the exact notifications the
/// shortcuts produce: `TerminalController.selectNextSession(_:)` /
/// `selectPreviousSession(_:)` post `.workspaceSelectNextSession` /
/// `.workspaceSelectPreviousSession` with the window, and
/// `AppDelegate.setupSessionIndexShortcuts()` posts
/// `.workspaceFocusSessionAtIndex` with the digit. No synthetic key events.
///
/// The container runs on a persistence-disabled `WorkspaceStore`, never
/// `.shared` (which writes the Dev app's real `workspace.json`), and its
/// sessions exist only in that store.
@MainActor
@Suite(.serialized)
struct RailSessionShortcutTests {

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private struct Rig {
        let container: WorkspaceViewContainer
        let window: NSWindow
        let store: WorkspaceStore
        /// What the rail renders, in its order.
        let railOrder: [AgentSession]
        /// The projects in sidebar visual order; the first is selected.
        let projectOrder: [UUID]
        let claudeStateDir: URL

        var coordinator: SessionCoordinator { container.coordinatorForTesting }

        func tearDown() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
            try? FileManager.default.removeItem(at: claudeStateDir)
        }
    }

    /// Three live, running sessions in one project, sidebar on the rail.
    private func makeRailRig() async -> Rig {
        await makeRig(names: ["a", "b", "c"], mode: .collapsed)
    }

    /// Sessions all go in the first project; any further projects are empty.
    private func makeRig(names: [String], mode: SidebarMode, projectCount: Int = 1) async -> Rig {
        let projects = (0..<projectCount).map { Project(name: "p\($0)", rootPath: "~/p\($0)") }
        let project = projects[0]
        let store = WorkspaceStore(testingProjects: projects)
        var sessions: [AgentSession] = []
        for name in names {
            let session = store.addSession(name: name, templateId: UUID(), projectId: project.id)
            store.updateSessionStatus(id: session.id, status: .running)
            sessions.append(session)
        }
        store.updateSidebarMode(mode)
        store.lastSelectedProjectId = store.flatProjectsInVisualOrder.first?.id

        let rig = await mount(store: store, liveSessions: sessions)
        #expect(rig.railOrder.count == names.count, "rig: every session should be a rail row")
        return rig
    }

    /// Hosts a container on `store` in its own window, with live surfaces
    /// for `liveSessions` in that container's coordinator. Several rigs can
    /// share one store, as windows share `WorkspaceStore.shared`.
    private func mount(store: WorkspaceStore, liveSessions sessions: [AgentSession]) async -> Rig {
        let projectOrder = store.flatProjectsInVisualOrder.map(\.id)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        // Closing a session clears its Claude state; keep that off the real
        // `~/.ghostties/state/`.
        let claudeStateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rail-shortcuts-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: claudeStateDir, withIntermediateDirectories: true)
        container.coordinatorForTesting.claudeStateStoreForTesting = ClaudeStateStore(directoryURL: claudeStateDir)
        for session in sessions {
            container.coordinatorForTesting.seedEmptySessionTreeForTesting(id: session.id)
        }
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        container.layoutSubtreeIfNeeded()
        await settle()

        let railOrder = store.railSessions()
        return Rig(
            container: container, window: window, store: store, railOrder: railOrder,
            projectOrder: projectOrder, claudeStateDir: claudeStateDir
        )
    }

    /// Lets the hosting view install its SwiftUI graph and any queued work run.
    private func settle() async {
        for _ in 0..<5 {
            try? await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func railNextSessionFocusesTheNextRailRow() async {
        let rig = await makeRailRig()
        defer { rig.tearDown() }
        rig.coordinator.focusSession(id: rig.railOrder[0].id)

        NotificationCenter.default.post(name: .workspaceSelectNextSession, object: rig.window)
        await settle()

        #expect(rig.coordinator.activeSessionId == rig.railOrder[1].id)
    }

    @Test func railPreviousSessionWrapsToTheLastRailRow() async {
        let rig = await makeRailRig()
        defer { rig.tearDown() }
        rig.coordinator.focusSession(id: rig.railOrder[0].id)

        NotificationCenter.default.post(name: .workspaceSelectPreviousSession, object: rig.window)
        await settle()

        #expect(rig.coordinator.activeSessionId == rig.railOrder[2].id)
    }

    @Test func railCommandTwoFocusesTheSecondRailRow() async {
        let rig = await makeRailRig()
        defer { rig.tearDown() }
        rig.coordinator.focusSession(id: rig.railOrder[0].id)

        NotificationCenter.default.post(
            name: .workspaceFocusSessionAtIndex,
            object: rig.window,
            userInfo: ["index": 2]
        )
        await settle()

        #expect(rig.coordinator.activeSessionId == rig.railOrder[1].id)
    }

    /// Pinned mounts the expanded list. One Cmd+Shift+] must step exactly
    /// once: with two sessions a double fire lands back where it started.
    /// Holds whichever tab or view mode the host's defaults select.
    @Test func pinnedNextSessionStepsExactlyOnce() async {
        let rig = await makeRig(names: ["a", "b"], mode: .pinned)
        defer { rig.tearDown() }
        let start = rig.railOrder[0].id
        rig.coordinator.focusSession(id: start)

        NotificationCenter.default.post(name: .workspaceSelectNextSession, object: rig.window)
        await settle()

        #expect(rig.coordinator.activeSessionId == rig.railOrder[1].id)
    }

    /// Cmd+W (`AppDelegate.setupCloseSessionShortcut()` posts
    /// `.workspaceCloseSession`) closes the focused session on the rail. No
    /// terminal controller in this window, so no confirmation sheet.
    @Test func railCommandWClosesTheFocusedSession() async {
        let rig = await makeRailRig()
        defer { rig.tearDown() }
        let focused = rig.railOrder[1].id
        rig.coordinator.focusSession(id: focused)
        #expect(rig.coordinator.hasLiveSurface(id: focused), "rig: focused session starts live")

        NotificationCenter.default.post(name: .workspaceCloseSession, object: rig.window)
        await settle()

        #expect(!rig.coordinator.hasLiveSurface(id: focused))
        #expect(rig.coordinator.hasLiveSurface(id: rig.railOrder[0].id), "only the focused session closes")
        #expect(rig.coordinator.hasLiveSurface(id: rig.railOrder[2].id), "only the focused session closes")
    }

    /// Next Project (Cmd+Ctrl+], `TerminalController.selectNextProject(_:)`)
    /// moves the selected project on the rail.
    @Test func railNextProjectSelectsTheNextProject() async {
        let rig = await makeRig(names: ["a"], mode: .collapsed, projectCount: 2)
        defer { rig.tearDown() }

        NotificationCenter.default.post(name: .workspaceSelectNextProject, object: rig.window)
        await settle()

        #expect(rig.store.lastSelectedProjectId == rig.projectOrder[1])
    }

    /// Pinned mounts the expanded list, which no longer observes Next
    /// Project itself; the container still moves the selection. (Not a
    /// double-fire guard: the list writes its selection back to the store
    /// on the next render, so a duplicate list handler would read the same
    /// starting project and land on the same target.)
    @Test func pinnedNextProjectSelectsTheNextProject() async {
        let rig = await makeRig(names: ["a"], mode: .pinned, projectCount: 2)
        defer { rig.tearDown() }
        #expect(rig.store.lastSelectedProjectId == rig.projectOrder[0], "rig: first project starts selected")

        NotificationCenter.default.post(name: .workspaceSelectNextProject, object: rig.window)
        await settle()

        #expect(rig.store.lastSelectedProjectId == rig.projectOrder[1])
    }

    // MARK: - Project cycling starts from this window's own project

    /// Three projects with one running session each, on the rail.
    private func makeThreeProjectStore() -> (store: WorkspaceStore, sessionInProject: [UUID: AgentSession]) {
        let projects = (0..<3).map { Project(name: "p\($0)", rootPath: "~/p\($0)") }
        let store = WorkspaceStore(testingProjects: projects)
        var sessionInProject: [UUID: AgentSession] = [:]
        for project in projects {
            let session = store.addSession(name: "s-\(project.name)", templateId: UUID(), projectId: project.id)
            store.updateSessionStatus(id: session.id, status: .running)
            sessionInProject[project.id] = session
        }
        store.updateSidebarMode(.collapsed)
        return (store, sessionInProject)
    }

    /// Each window steps from the project of ITS active session, not the
    /// selection another window last made (the list's selection is
    /// per-window; `WorkspaceStore` is shared). Window A moves the shared
    /// selection to X2; window B, active in Y, must land on Y's neighbour.
    @Test func nextProjectStepsFromThisWindowsActiveProject() async {
        let (store, sessionInProject) = makeThreeProjectStore()
        let order = store.flatProjectsInVisualOrder.map(\.id)
        let x1 = order[0], x2 = order[1], y = order[2]
        store.lastSelectedProjectId = x1

        let a = await mount(store: store, liveSessions: [sessionInProject[x1]!])
        defer { a.tearDown() }
        let b = await mount(store: store, liveSessions: [sessionInProject[y]!])
        defer { b.tearDown() }
        a.coordinator.focusSession(id: sessionInProject[x1]!.id)
        b.coordinator.focusSession(id: sessionInProject[y]!.id)

        NotificationCenter.default.post(name: .workspaceSelectNextProject, object: a.window)
        await settle()
        #expect(store.lastSelectedProjectId == x2, "rig: window A moved the shared selection to X2")

        NotificationCenter.default.post(name: .workspaceSelectNextProject, object: b.window)
        await settle()

        // Y is last in visual order, so its neighbour wraps to the first.
        #expect(store.lastSelectedProjectId == order[0], "B must step from Y, not from A's X2")
    }

    /// Cmd+Shift+] on the rail can land in another project; Next Project
    /// then steps from that session's project.
    @Test func railNextProjectStepsFromTheProjectSessionCyclingReached() async {
        let (store, sessionInProject) = makeThreeProjectStore()
        let order = store.flatProjectsInVisualOrder.map(\.id)
        // The selection starts on the first rail row's project, which
        // session cycling then leaves.
        store.lastSelectedProjectId = store.railSessions()[0].projectId
        let rig = await mount(store: store, liveSessions: Array(sessionInProject.values))
        defer { rig.tearDown() }
        rig.coordinator.focusSession(id: rig.railOrder[0].id)

        NotificationCenter.default.post(name: .workspaceSelectNextSession, object: rig.window)
        await settle()
        let reached = rig.railOrder[1]
        #expect(rig.coordinator.activeSessionId == reached.id, "rig: session cycling moved focus")
        let reachedIndex = order.firstIndex(of: reached.projectId)!

        NotificationCenter.default.post(name: .workspaceSelectNextProject, object: rig.window)
        await settle()

        #expect(store.lastSelectedProjectId == order[(reachedIndex + 1) % order.count])
    }
}
