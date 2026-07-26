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

    /// THE regression this whole rewrite exists to fix: the deleted
    /// `TrailingEdgeDebouncer` starved completely under a sustained,
    /// unchanging signal (110 identical-title signals at the true 250ms
    /// production ratio against a 5s debounce → zero fires). Drives the real
    /// `subscribeNameSync` pipeline with a burst of IDENTICAL titles sent
    /// faster than the throttle interval, and asserts an update lands during
    /// that sustained burst — not only after signals stop.
    ///
    /// `removeDuplicates()` is what makes this possible: it collapses the
    /// repeated-identical-title signal down to a single change event, so
    /// `throttle(latest: true)` sees its leading edge immediately rather than
    /// waiting for the burst to end.
    func testSustainedIdenticalTitlesFireDuringActivityNotOnlyAfterQuiet() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let coordinator = SessionCoordinator()

        let titleSubject = PassthroughSubject<String, Never>()
        // Interval is longer than the whole burst below, on purpose: the old
        // debounce would never fire in this scenario because the signal
        // never actually goes quiet within the window.
        coordinator.subscribeNameSync(sessionId: session.id, titlePublisher: titleSubject, interval: 1.0, store: store)

        let burstStarted = Date()
        let burstFinished = expectation(description: "sustained identical-title burst delivered")
        var sent = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { t in
            // Every emission is the SAME string — mirrors Claude Code
            // re-emitting an identical OSC 2 title on every render frame.
            titleSubject.send("Compacting conversation 45%")
            sent += 1
            if sent >= 30 {
                t.invalidate()
                burstFinished.fulfill()
            }
        }
        wait(for: [burstFinished], timeout: 2.0)
        let burstElapsed = Date().timeIntervalSince(burstStarted)

        XCTAssertLessThan(burstElapsed, 1.0, "sanity: the whole burst must complete inside the 1s throttle window")
        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "Compacting conversation 45%",
            "an update must land DURING the sustained-but-identical burst — the deleted TrailingEdgeDebouncer produced zero fires in exactly this scenario"
        )
    }

    /// Distinct titles arriving faster than the throttle window must still
    /// collapse to at most one write per interval, with the LAST value of the
    /// burst winning (trailing edge) — mirroring Claude Code's real streaming
    /// tool-call titles, which do actually change from call to call.
    func testDistinctTitlesThrottleToAtMostOneWritePerIntervalWithLatestWinning() {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: UUID(), projectId: project.id)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let coordinator = SessionCoordinator()

        let titleSubject = PassthroughSubject<String, Never>()
        coordinator.subscribeNameSync(sessionId: session.id, titlePublisher: titleSubject, interval: 0.3, store: store)

        var writeCount = 0
        let cancellable = store.objectWillChange.sink { writeCount += 1 }
        defer { cancellable.cancel() }

        let titles = ["Reading files", "Editing auth.swift", "Running tests"]
        for title in titles {
            titleSubject.send(title)
        }

        let trailingEdgeFired = expectation(description: "trailing-edge write applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { trailingEdgeFired.fulfill() }
        wait(for: [trailingEdgeFired], timeout: 2.0)

        XCTAssertEqual(
            store.sessions(for: project.id).first?.name,
            "Running tests",
            "the latest title in the burst must win"
        )
        XCTAssertLessThanOrEqual(writeCount, 2, "at most one write per throttle interval — leading edge plus trailing edge, never one per signal")
    }
}
