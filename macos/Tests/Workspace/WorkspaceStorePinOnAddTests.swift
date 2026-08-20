import Foundation
import Testing
@testable import Ghostty

/// Tests for Session Composer Phase 5: `WorkspaceStore.addProject(at:pinned:)`
/// must pin only on an explicit request, never as a side effect of
/// auto-registration (e.g. from `SessionCoordinator` spawning a new task).
///
/// Each test calls the real production `addProject(at:pinned:)` and asserts
/// on the real `Project.isPinned`, per the standing rule against vacuous
/// tests (see `feedback_vacuous-tests-pass-green.md`).
@MainActor
struct WorkspaceStorePinOnAddTests {

    private func tmpURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-pin-on-add-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func addProjectWithDefaultArgsRegistersUnpinned() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let url = tmpURL("auto")

        store.addProject(at: url)

        let project = store.projects.first(where: { $0.rootPath == url.standardizedFileURL.path })
        #expect(project != nil)
        #expect(project?.isPinned == false)
    }

    @Test func addProjectWithPinnedTrueRegistersPinned() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let url = tmpURL("explicit")

        store.addProject(at: url, pinned: true)

        let project = store.projects.first(where: { $0.rootPath == url.standardizedFileURL.path })
        #expect(project != nil)
        #expect(project?.isPinned == true)
    }

    @Test func reAddingUnpinnedProjectWithPinnedTruePinsIt() {
        let url = tmpURL("repin")
        let path = url.standardizedFileURL.path
        let existing = Project(name: "Repin", rootPath: path, isPinned: false)
        let store = WorkspaceStore(testingProjects: [existing], testingSessions: [])

        store.addProject(at: url, pinned: true)

        let project = store.projects.first(where: { $0.rootPath == path })
        #expect(project?.isPinned == true)
    }

    @Test func reAddingPinnedProjectWithDefaultArgsDoesNotUnpinIt() {
        let url = tmpURL("keep-pinned")
        let path = url.standardizedFileURL.path
        let existing = Project(name: "KeepPinned", rootPath: path, isPinned: true)
        let store = WorkspaceStore(testingProjects: [existing], testingSessions: [])

        // Simulates auto-registration (e.g. SessionCoordinator) rediscovering
        // an already-pinned project. Must be a pure no-op on pin state.
        store.addProject(at: url)

        let project = store.projects.first(where: { $0.rootPath == path })
        #expect(project?.isPinned == true)
    }
}
