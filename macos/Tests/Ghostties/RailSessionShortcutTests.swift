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

        var coordinator: SessionCoordinator { container.coordinatorForTesting }

        func tearDown() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    /// Three live, running sessions in one project, sidebar on the rail.
    private func makeRailRig() async -> Rig {
        await makeRig(names: ["a", "b", "c"], mode: .collapsed)
    }

    private func makeRig(names: [String], mode: SidebarMode) async -> Rig {
        let project = Project(name: "p", rootPath: "~/p")
        let store = WorkspaceStore(testingProjects: [project])
        var sessions: [AgentSession] = []
        for name in names {
            let session = store.addSession(name: name, templateId: UUID(), projectId: project.id)
            store.updateSessionStatus(id: session.id, status: .running)
            sessions.append(session)
        }
        store.updateSidebarMode(mode)

        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
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
        #expect(railOrder.count == names.count, "rig: every session should be a rail row")
        return Rig(container: container, window: window, store: store, railOrder: railOrder)
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
}
