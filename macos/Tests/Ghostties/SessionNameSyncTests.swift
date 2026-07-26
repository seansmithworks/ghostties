// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import Combine
import XCTest
@testable import Ghostty

/// Tests for `WorkspaceStore.syncSessionNameFromTitle` / `renameSession` /
/// `resetNamePin` — the Claude Code → sidebar name-sync direction and its pin
/// semantics.
@MainActor
final class SessionNameSyncTests: XCTestCase {

    private func makeProject() -> Project {
        Project(name: "ghostties", rootPath: "/Users/sean/Code/ghostties", isPinned: true)
    }

    private func makeStore(session: AgentSession, project: Project) -> WorkspaceStore {
        WorkspaceStore(testingProjects: [project], testingSessions: [session])
    }

    func testSyncUpdatesUnpinnedSessionName() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")

        XCTAssertEqual(store.sessions(for: project.id).first?.name, "Refactoring the auth module")
    }

    func testManualRenamePinsTheName() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")

        XCTAssertTrue(store.sessions(for: project.id).first?.isNamePinned ?? false)
        XCTAssertEqual(store.sessions(for: project.id).first?.name, "My Custom Name")
    }

    func testPinnedSessionIgnoresIncomingTitles() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")
        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")

        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "My Custom Name",
            "A pinned session must ignore incoming agent title updates"
        )
    }

    func testResetNamePinResumesAutomaticSync() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.renameSession(id: session.id, name: "My Custom Name")
        store.resetNamePin(id: session.id)

        XCTAssertFalse(store.sessions(for: project.id).first?.isNamePinned ?? true)

        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")
        XCTAssertEqual(store.sessions(for: project.id).first?.name, "Refactoring the auth module")
    }

    /// The single most important regression guard in this file: an unchanged
    /// name must fire neither `objectWillChange` nor `persist()`. This is
    /// exactly the assertion that would have caught the original
    /// `project_perf-activity-invalidation-storm.md` incident — "the
    /// publisher did not fire" — rather than merely checking the resulting
    /// value.
    func testNoOpSyncFiresNoPublishAndNoPersist() {
        let project = makeProject()
        let session = AgentSession(name: "Refactoring the auth module", templateId: UUID(), projectId: project.id)
        let store = makeStore(session: session, project: project)

        var willChangeCount = 0
        let cancellable = store.objectWillChange.sink { willChangeCount += 1 }
        defer { cancellable.cancel() }

        let persistCountBefore = store.persistCallCount
        store.syncSessionNameFromTitle(id: session.id, title: "Refactoring the auth module")

        XCTAssertEqual(willChangeCount, 0, "an unchanged name must not fire objectWillChange")
        XCTAssertEqual(store.persistCallCount, persistCountBefore, "an unchanged name must not call persist()")
    }

    /// FIX 4: `SessionCoordinator.performNameSync` must check the pin before
    /// doing any lookup work, but functionally the observable behavior is the
    /// same either way — a pinned session's name never changes. This exercises
    /// that through the actual coordinator entry point (not just
    /// `WorkspaceStore.syncSessionNameFromTitle` directly, as the tests above
    /// do) using an isolated test `WorkspaceStore` so it never touches the
    /// real `workspace.json`.
    func testCoordinatorPerformNameSyncSkipsPinnedSessionEntirely() {
        let project = makeProject()
        var session = AgentSession(name: "My Custom Name", templateId: UUID(), projectId: project.id)
        session.isNamePinned = true
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let coordinator = SessionCoordinator()

        coordinator.performNameSync(sessionId: session.id, title: "Refactoring the auth module", store: store)

        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "My Custom Name",
            "a pinned session's name must be untouched by performNameSync"
        )
    }

    /// FIX 1: the debounce (via `TrailingEdgeDebouncer`, tested in isolation in
    /// `TrailingEdgeDebouncerTests`) must, at fire time, read the title
    /// supplied by the LATEST `scheduleNameSync` call — never a value sampled
    /// earlier. This proves that end-to-end through the actual coordinator
    /// entry point using a fast test interval instead of the real 5s.
    func testScheduleNameSyncAppliesTheLatestTitleAtFireTime() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let coordinator = SessionCoordinator()

        // Simulate a burst: the title keeps changing right up until the last
        // signal, mirroring Claude Code streaming tool-call titles.
        let titles = ["Reading files", "Editing auth.swift", "Running tests"]
        for title in titles {
            coordinator.scheduleNameSync(
                sessionId: session.id,
                titleProvider: { title },
                interval: 0.05,
                store: store
            )
        }

        let expectation = expectation(description: "debounced sync applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "Running tests",
            "the debounce must apply the title from the LAST signal, never a stale earlier one"
        )
    }
}
