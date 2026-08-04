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

    /// A `.killed` session's cached indicator state must not survive its own
    /// close: the 1Hz tick only recomputes indicators for sessions where
    /// `status.isAlive`, so once a session goes terminal nothing else will
    /// ever refresh a stale cached value.
    func testClosedSessionIndicatorStateIsInactiveNotStale() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
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
        let coordinator = SessionCoordinator()
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
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
        let coordinator = SessionCoordinator()
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
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
