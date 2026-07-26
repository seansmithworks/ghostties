// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Tests for `TrailingEdgeDebouncer` — the mechanism `SessionCoordinator` uses
/// to guard the Claude Code → sidebar name sync against the title-change
/// storm documented in `project_perf-activity-invalidation-storm.md`. This is
/// the single riskiest piece of that fix, so it's tested directly and in
/// isolation (no `WorkspaceStore`/GhosttyKit involved) with a tiny interval
/// rather than the real 5s, so the suite stays fast.
final class TrailingEdgeDebouncerTests: XCTestCase {

    private let testInterval: TimeInterval = 0.05

    func testRapidSignalsCollapseIntoOneFireWithTheLatestAction() {
        let debouncer = TrailingEdgeDebouncer(interval: testInterval, queue: .main)
        var fireCount = 0
        var lastValue = -1
        let expectation = expectation(description: "single trailing-edge fire")

        // Simulate a burst of 5 output signals arriving faster than the
        // debounce interval — exactly the "Claude Code updates the title
        // constantly while streaming" scenario from the storm incident.
        for i in 0..<5 {
            debouncer.signal {
                fireCount += 1
                lastValue = i
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(fireCount, 1, "a burst of rapid signals must collapse into exactly one fire")
        XCTAssertEqual(lastValue, 4, "the fire must reflect the LATEST signal, never a stale intermediate one")
    }

    func testSignalAfterAFreshQuietPeriodFiresAgain() {
        let debouncer = TrailingEdgeDebouncer(interval: testInterval, queue: .main)
        var fireCount = 0

        let first = expectation(description: "first fire")
        debouncer.signal { fireCount += 1; first.fulfill() }
        wait(for: [first], timeout: 1.0)

        let second = expectation(description: "second fire")
        debouncer.signal { fireCount += 1; second.fulfill() }
        wait(for: [second], timeout: 1.0)

        XCTAssertEqual(fireCount, 2, "a session that goes quiet and then produces new output again must still sync eventually — not be starved forever")
    }

    func testCancelPreventsAPendingFire() {
        let debouncer = TrailingEdgeDebouncer(interval: testInterval, queue: .main)
        var fired = false
        debouncer.signal { fired = true }
        debouncer.cancel()

        let notFired = expectation(description: "quiet period elapsed with no fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + testInterval * 3) {
            notFired.fulfill()
        }
        wait(for: [notFired], timeout: 1.0)

        XCTAssertFalse(fired, "cancel() must prevent a pending fire — SessionCoordinator.clearRuntime relies on this")
    }
}
