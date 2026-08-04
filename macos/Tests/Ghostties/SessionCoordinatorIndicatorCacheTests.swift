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
}
