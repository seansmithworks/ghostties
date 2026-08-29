import Foundation
import Testing
import GhosttiesCore
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

    // MARK: - Freeze-snapshot no-op (the actual duplicate-path fix)
    //
    // `isPinned == true` alone doesn't discriminate old vs. new behavior on
    // the re-add-existing branch: the OLD code also force-set `isPinned =
    // true` on an already-pinned project, so that assertion passes either
    // way. What Phase 5 actually changes is whether the early-return path
    // calls `releaseSnapshot()` + `persist()` at all.
    //
    // `sectionSignature` alone is NOT a reliable witness here: a pinned
    // project's section membership never changes regardless of activity
    // (see `computeSectionedProjects` — `isPinned` short-circuits straight
    // to `.pinned`), so releasing-vs-not-releasing the snapshot can produce
    // an identical signature even when release genuinely happened. The real
    // witness is `persistCallCount` (`#if DEBUG`, exists precisely to let
    // tests assert "this path never even attempted to persist" — see the
    // doc comment on the property). Both assertions are kept for belt and
    // suspenders, but `persistCallCount` is the one that actually
    // discriminates: verified by temporarily relaxing the production guard
    // from `guard pinned, !projects[index].isPinned else { return }` to
    // `guard pinned else { return }` and re-running this file — the relaxed
    // guard makes `reAddingAlreadyPinnedProjectWithPinnedTrueIsAPureNoOp`
    // fail (persistCallCount increments) while `sectionSignature` alone
    // stayed equal and would have missed the regression.

    @Test func reAddingUnpinnedProjectWithDefaultArgsIsAPureNoOp() {
        let url = tmpURL("noop-unpinned")
        let path = url.standardizedFileURL.path
        let existing = Project(name: "NoopUnpinned", rootPath: path, isPinned: false)
        let store = WorkspaceStore(testingProjects: [existing], testingSessions: [])

        store.freezeSnapshot()
        let frozenSignature = store.sectionSignature
        let persistCountBefore = store.persistCallCount

        // Auto-registration rediscovering an unpinned project. Must not
        // release the snapshot or persist — nothing structurally changed.
        store.addProject(at: url)

        #expect(store.sectionSignature == frozenSignature)
        #expect(store.persistCallCount == persistCountBefore)
    }

    @Test func reAddingAlreadyPinnedProjectWithPinnedTrueIsAPureNoOp() {
        let url = tmpURL("noop-pinned")
        let path = url.standardizedFileURL.path
        let existing = Project(name: "NoopPinned", rootPath: path, isPinned: true)
        let store = WorkspaceStore(testingProjects: [existing], testingSessions: [])

        store.freezeSnapshot()
        let frozenSignature = store.sectionSignature
        let persistCountBefore = store.persistCallCount

        // Explicit re-add of an already-pinned project (e.g. picking the same
        // folder twice). No pin-state change, so this must also be a no-op —
        // it must NOT call releaseSnapshot()/persist() just because `pinned`
        // was passed as true.
        store.addProject(at: url, pinned: true)

        #expect(store.sectionSignature == frozenSignature)
        #expect(store.persistCallCount == persistCountBefore)
    }

    @Test func addingNewUnpinnedProjectStillReleasesFrozenSnapshot() {
        // The auto-register path (default args) creating a genuinely NEW
        // project is a structural change and must still drop the snapshot,
        // same as the existing pinned-picker-add coverage in
        // WorkspaceStoreFreezeTests.
        let existing = Project(name: "Existing", rootPath: "/tmp/Existing", isPinned: true)
        let store = WorkspaceStore(testingProjects: [existing], testingSessions: [])

        store.freezeSnapshot()
        let frozenSignature = store.sectionSignature

        let url = tmpURL("new-unpinned")
        store.addProject(at: url)

        #expect(store.sectionSignature != frozenSignature)
    }
}
