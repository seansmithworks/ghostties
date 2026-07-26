import XCTest
@testable import Ghostty

/// Tests for the recents-list ordering + section-membership logic in RecentsListView.
///
/// Exercises the static `sorted(sessions:)` and `belongsInActive(...)` helpers plus
/// `relativeLabel(_:)` — all are pure functions with no SwiftUI or AppKit dependencies.
final class RecentsListViewTests: XCTestCase {

    // MARK: - Helpers

    private func session(
        name: String,
        lastActiveAt: Date? = nil,
        sortOrder: Int? = nil
    ) -> AgentSession {
        AgentSession(
            name: name,
            templateId: UUID(),
            projectId: UUID(),
            sortOrder: sortOrder,
            lastActiveAt: lastActiveAt
        )
    }

    // MARK: - Sorting (stable order — NOT recency-based)

    /// Recency (`lastActiveAt`) must NOT affect order — that was the bug (rows
    /// reshuffling under the cursor as `recordActivity` bumps the timestamp
    /// every ~5s during streaming). Position/creation order should win instead.
    func testLastActiveAtDoesNotAffectOrder() {
        let early = session(name: "early", lastActiveAt: Date(timeIntervalSinceNow: -3600))
        let middle = session(name: "middle", lastActiveAt: Date(timeIntervalSinceNow: -1800))
        let recent = session(name: "recent", lastActiveAt: Date(timeIntervalSinceNow: -60))

        // Passed in append/creation order: early, middle, recent.
        let sorted = RecentsListView.sorted(sessions: [early, middle, recent])

        XCTAssertEqual(sorted.map(\.name), ["early", "middle", "recent"])
    }

    func testExplicitSortOrderWins() {
        let a = session(name: "a", sortOrder: 2)
        let b = session(name: "b", sortOrder: 0)
        let c = session(name: "c", sortOrder: 1)

        let sorted = RecentsListView.sorted(sessions: [a, b, c])

        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func testSessionsWithSortOrderComeBeforeNilSortOrder() {
        let noOrder = session(name: "noOrder", sortOrder: nil)
        let ordered = session(name: "ordered", sortOrder: 0)

        let sorted = RecentsListView.sorted(sessions: [noOrder, ordered])

        XCTAssertEqual(sorted.map(\.name), ["ordered", "noOrder"])
    }

    /// Nil `sortOrder` falls back to append/creation position (index in the
    /// passed-in array), not any other ordering.
    func testNilSortOrderFallsBackToAppendPosition() {
        let first = session(name: "first", sortOrder: nil)
        let second = session(name: "second", sortOrder: nil)
        let third = session(name: "third", sortOrder: nil)

        let sorted = RecentsListView.sorted(sessions: [first, second, third])

        XCTAssertEqual(sorted.map(\.name), ["first", "second", "third"])
    }

    func testEmptySessionListReturnsEmpty() {
        let sorted = RecentsListView.sorted(sessions: [])
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSingleSessionReturnedUnchanged() {
        let s = session(name: "only", lastActiveAt: Date())
        let sorted = RecentsListView.sorted(sessions: [s])
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.name, "only")
    }

    func testAllNilSortOrdersPreservesCount() {
        let sessions = (0..<5).map { session(name: "s\($0)", sortOrder: nil) }
        let sorted = RecentsListView.sorted(sessions: sessions)
        XCTAssertEqual(sorted.count, 5)
    }

    // MARK: - Section Membership (selected-session guard)

    func testInactiveSessionBelongsInArchiveByDefault() {
        let id = UUID()
        XCTAssertFalse(RecentsListView.belongsInActive(
            indicatorState: .inactive,
            sessionId: id,
            selectedSessionId: nil
        ))
    }

    func testLiveIndicatorStateBelongsInActive() {
        let id = UUID()
        XCTAssertTrue(RecentsListView.belongsInActive(
            indicatorState: .processing,
            sessionId: id,
            selectedSessionId: nil
        ))
    }

    /// The critical guard: a selected session with an `.inactive` indicator must
    /// still stay in Active — it must not vanish into a collapsed Archive the
    /// instant the agent goes quiet while the user is looking at it.
    func testSelectedInactiveSessionStaysInActive() {
        let id = UUID()
        XCTAssertTrue(RecentsListView.belongsInActive(
            indicatorState: .inactive,
            sessionId: id,
            selectedSessionId: id
        ))
    }

    func testDeselectedInactiveSessionFallsToArchive() {
        let sessionId = UUID()
        let otherSelectedId = UUID()
        XCTAssertFalse(RecentsListView.belongsInActive(
            indicatorState: .inactive,
            sessionId: sessionId,
            selectedSessionId: otherSelectedId
        ))
    }

    // MARK: - Relative Time Labels

    func testRelativeLabelJustNow() {
        let date = Date(timeIntervalSinceNow: -10)
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "just now")
    }

    func testRelativeLabelMinutes() {
        let date = Date(timeIntervalSinceNow: -120) // 2 minutes ago
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "2m")
    }

    func testRelativeLabelHours() {
        let date = Date(timeIntervalSinceNow: -7200) // 2 hours ago
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "2h")
    }

    func testRelativeLabelDayAbbreviation() {
        // 2 days ago — formatter uses en_US_POSIX locale so output is always 3-char English
        let date = Date(timeIntervalSinceNow: -172800)
        let label = RecentsRowView.relativeLabel(date)
        let validAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        XCTAssertTrue(validAbbreviations.contains(label),
            "Day abbreviation '\(label)' should be an English 3-char weekday")
    }

    func testRelativeLabelOldDate() {
        // 10 days ago — should use "MMM d" format (en_US_POSIX, e.g. "May 1")
        let date = Date(timeIntervalSinceNow: -864000)
        let label = RecentsRowView.relativeLabel(date)
        // Contains a space between month abbreviation and day number
        XCTAssertTrue(label.contains(" "), "Old date label '\(label)' should be 'MMM d' format")
    }
}
