// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Regression coverage for the dead-⌘W bug: `closeCurrentSessionWithConfirmation()`
/// used to `return` immediately whenever `activeSessionId` was `nil`, which the
/// AppDelegate ⌘W local monitor always reaches for (it unconditionally swallows
/// the keystroke after posting `.workspaceCloseSession`). A freshly launched
/// project-first window with no session started yet, or a window that just ran
/// out of running sessions via `switchToNextSession()`, made ⌘W do nothing at all.
///
/// `terminalController` resolves through `containerView?.window`, which isn't
/// available without a live AppKit window in this test target, so these tests
/// can't observe the window actually closing. What they do prove: the new
/// no-active-session branch is reachable and doesn't crash or mutate coordinator
/// state it shouldn't touch, for both outcomes of the `sessionTrees.isEmpty &&
/// browserManagers.isEmpty` check the fix added.
@MainActor
final class SessionCoordinatorCloseWithoutActiveSessionTests: XCTestCase {

    /// Nothing active, nothing live left in the window — the branch this bug
    /// fix exists for. Must not crash even though `terminalController` (and so
    /// its `window`) is nil in this test target.
    func testCloseWithNoActiveSessionAndNoLiveSessionsDoesNotCrash() {
        let coordinator = SessionCoordinator()

        XCTAssertNil(coordinator.activeSessionId)

        coordinator.closeCurrentSessionWithConfirmation()

        XCTAssertNil(
            coordinator.activeSessionId,
            "closing with nothing active must not leave activeSessionId in some other state"
        )
    }

    /// Nothing active, but a live session still exists in this window — must
    /// stay a no-op rather than closing the window out from under it.
    func testCloseWithNoActiveSessionButLiveSessionIsANoOp() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
        }

        coordinator.seedEmptySessionTreeForTesting(id: id)
        XCTAssertNil(coordinator.activeSessionId)

        coordinator.closeCurrentSessionWithConfirmation()

        XCTAssertNotNil(
            coordinator.sessionTrees[id],
            "a live session must survive a ⌘W with nothing active"
        )
    }
}
