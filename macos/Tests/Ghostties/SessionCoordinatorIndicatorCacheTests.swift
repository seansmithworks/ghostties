// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Regression coverage for the stale-indicator bug: a session whose surface
/// closes with a terminal `SessionStatus` must stop reporting a live
/// indicator, so it leaves the Sessions tab's ACTIVE zone on its own instead
/// of waiting for relaunch or an explicit Remove.
///
/// Drives `closeSession`, which shares the same `setStatus(_:for:)` path as
/// `handleSurfaceClose` — both funnel terminal statuses through the single
/// mutation point that clears the cached indicator state.
@MainActor
final class SessionCoordinatorIndicatorCacheTests: XCTestCase {

    /// Every `SessionCoordinator` here must be pointed at its own
    /// temp-directory `ClaudeStateStore` via `claudeStateStoreForTesting` —
    /// never `.shared`, which reads/writes the real `~/.ghostties/state/`
    /// that live sessions are writing to right now. `closeSession` and
    /// `setStatusForTesting(.exited/.killed, ...)` both reach
    /// `claudeStateStore.removeState(for:)`, and `indicatorState(for:)` on a
    /// `.running` session reaches `claudeStateStore.state(for:)`. Follows
    /// the pattern in `SessionCoordinatorClaudeStateTests.swift`.
    private func makeStore() -> (store: ClaudeStateStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCoordinatorIndicatorCacheTests-\(UUID().uuidString)", isDirectory: true)
        return (ClaudeStateStore(directoryURL: dir), dir)
    }

    /// A `.killed` session's cached indicator state must not survive its own
    /// close: the 1Hz tick only recomputes indicators for sessions where
    /// `status.isAlive`, so once a session goes terminal nothing else will
    /// ever refresh a stale cached value.
    func testClosedSessionIndicatorStateIsInactiveNotStale() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            try? FileManager.default.removeItem(at: dir)
        }

        // Seed a live-looking indicator, mirroring what the 1Hz tick would
        // have written while the session was actually running.
        WorkspaceStore.shared.updateIndicatorState(id: id, state: .processing)
        coordinator.seedEmptySessionTreeForTesting(id: id)

        coordinator.closeSession(id: id)

        let indicatorState = WorkspaceStore.shared.globalIndicatorStates[id] ?? .inactive
        XCTAssertEqual(
            indicatorState,
            .inactive,
            "a closed session's indicator must fall back to .inactive, not the last live value"
        )
        XCTAssertFalse(
            RecentsListView.belongsInActive(indicatorState: indicatorState),
            "a closed session must leave the ACTIVE zone"
        )
    }

    /// `.exited`/`.completed` are the statuses `handleSurfaceClose` actually
    /// reports (as opposed to `closeSession`'s `.killed`, covered above).
    /// Driven via `setStatusForTesting`, the closest reachable seam to
    /// `handleSurfaceClose` without a live GhosttyKit surface.
    func testExitedSessionIndicatorStateIsInactive() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            try? FileManager.default.removeItem(at: dir)
        }

        WorkspaceStore.shared.updateIndicatorState(id: id, state: .processing)

        coordinator.setStatusForTesting(.exited, for: id)

        let indicatorState = WorkspaceStore.shared.globalIndicatorStates[id] ?? .inactive
        XCTAssertEqual(
            indicatorState,
            .inactive,
            "an exited session's indicator must fall back to .inactive, not the last live value"
        )
    }

    /// `.error` must write a distinct `.error` indicator (not silently retain
    /// whatever live value the session held before failing) and the session
    /// must stay in the ACTIVE zone so failed sessions keep nagging until the
    /// user relaunches or Removes them.
    func testErrorSessionIndicatorStateIsErrorAndStaysActive() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            try? FileManager.default.removeItem(at: dir)
        }

        // Seed a live-looking indicator, mirroring what the 1Hz tick would
        // have written while the session was actually running.
        WorkspaceStore.shared.updateIndicatorState(id: id, state: .processing)

        coordinator.setStatusForTesting(.error(exitCode: 1), for: id)

        let indicatorState = WorkspaceStore.shared.globalIndicatorStates[id] ?? .inactive
        XCTAssertEqual(
            indicatorState,
            .error,
            "an errored session's indicator must become .error, not keep its last live value"
        )
        XCTAssertTrue(
            RecentsListView.belongsInActive(indicatorState: indicatorState),
            "an errored session must stay in the ACTIVE zone until relaunched or removed"
        )
    }

    /// Regression test for the `.error` mirror of the relaunch bug: an
    /// errored session must also clear its way out of
    /// `SessionCoordinator`'s own `cachedIndicatorStates`, not just get
    /// written into the store. If `cachedIndicatorStates?[id] = .error` is
    /// missing, the cache stays on the session's pre-error value
    /// (`.processing`, seeded here by the first tick). On relaunch, the next
    /// tick recomputes that same `.processing` value, `Perf.publishIfChanged`
    /// sees no change against the stale cache, and the publish (and store
    /// write) is suppressed — leaving the store stuck showing `.error` for a
    /// session that is actually running again.
    ///
    /// This test fails without the `cachedIndicatorStates?[id] = .error`
    /// line in `setStatus(_:for:)` and passes with it.
    func testRelaunchedSessionPublishesIndicatorAfterError() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            try? FileManager.default.removeItem(at: dir)
        }

        // 1. Session starts running and producing output; the tick populates
        //    both the store and the coordinator's own comparator cache with
        //    .processing.
        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()
        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)

        // 2. The session exits non-zero.
        coordinator.setStatusForTesting(.error(exitCode: 1), for: id)
        XCTAssertEqual(
            WorkspaceStore.shared.globalIndicatorStates[id],
            .error,
            "an errored session's indicator must become .error"
        )

        // 3. The same session id is relaunched and starts producing output
        //    again before the next tick.
        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(
            WorkspaceStore.shared.globalIndicatorStates[id],
            .processing,
            "a relaunched session must publish its live indicator again, not stay stuck on .error"
        )
    }

    /// Regression test for the relaunch bug: closing a session must also
    /// clear `SessionCoordinator`'s own `cachedIndicatorStates` entry, not
    /// just the store's. If it doesn't, relaunching the same session id and
    /// running the next 1Hz tick recomputes the identical pre-death state,
    /// `Perf.publishIfChanged` sees no change against the stale cache, and
    /// the store write is suppressed — leaving a live, running session with
    /// no indicator entry at all.
    ///
    /// This test fails without the `cachedIndicatorStates?.removeValue`
    /// line in `setStatus(_:for:)` and passes with it.
    func testRelaunchedSessionPublishesIndicatorAfterClose() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            try? FileManager.default.removeItem(at: dir)
        }

        // 1. Session starts running and producing output; the tick populates
        //    both the store and the coordinator's own comparator cache.
        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()
        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)

        // 2. The session is closed (terminal status).
        coordinator.setStatusForTesting(.killed, for: id)
        XCTAssertNil(
            WorkspaceStore.shared.globalIndicatorStates[id],
            "closing must clear the store entry"
        )

        // 3. The same session id is relaunched (production reuses ids on
        //    relaunch) and starts producing output again before the next tick.
        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(
            WorkspaceStore.shared.globalIndicatorStates[id],
            .processing,
            "a relaunched session must get a live indicator entry again, not stay empty"
        )
    }
}
