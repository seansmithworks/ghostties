import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for `PendingLaunchHold` — the pure generation bookkeeping behind
/// `RecentsListView.pendingLaunchGenerations` (BACKLOG I). Covers the two
/// bugs from the independent review of commit 4e3a04419:
///
/// 1. Stop during a relaunch hold must end the hold immediately, not wait
///    out the 5s timeout.
/// 2. A second relaunch of the same session within 5s of the first must
///    survive the first drop's timeout firing.
final class PendingLaunchHoldTests: XCTestCase {

    // MARK: - Stop ends the hold outright

    func testEndClearsTheHoldRegardlessOfGeneration() {
        let id = UUID()
        let started = PendingLaunchHold.begin(id: id, in: [:])
        XCTAssertNotNil(started.generations[id], "hold must exist after begin")

        let afterStop = PendingLaunchHold.end(id: id, in: started.generations)
        XCTAssertNil(afterStop[id], "Stop must clear the hold immediately")
    }

    // MARK: - A timeout only clears the hold it was scheduled for

    func testStaleTimeoutFromAnEarlierDropDoesNotClearANewerHold() {
        let id = UUID()

        // First drop starts generation 1.
        let firstDrop = PendingLaunchHold.begin(id: id, in: [:])
        XCTAssertEqual(firstDrop.token, 1)

        // Second drop (within 5s) starts generation 2, replacing the hold.
        let secondDrop = PendingLaunchHold.begin(id: id, in: firstDrop.generations)
        XCTAssertEqual(secondDrop.token, 2)
        XCTAssertEqual(secondDrop.generations[id], 2)

        // The FIRST drop's timeout fires now, carrying its stale token (1).
        XCTAssertFalse(
            PendingLaunchHold.timeoutShouldClear(id: id, token: firstDrop.token, in: secondDrop.generations),
            "a timeout from an earlier drop must not clear a newer hold"
        )

        // The SECOND drop's timeout, carrying the current token (2), may clear it.
        XCTAssertTrue(
            PendingLaunchHold.timeoutShouldClear(id: id, token: secondDrop.token, in: secondDrop.generations),
            "the timeout scheduled for the current hold must be allowed to clear it"
        )
    }

    func testMatchingTimeoutClearsAnUncontestedHold() {
        let id = UUID()
        let started = PendingLaunchHold.begin(id: id, in: [:])
        XCTAssertTrue(PendingLaunchHold.timeoutShouldClear(id: id, token: started.token, in: started.generations))
    }
}
