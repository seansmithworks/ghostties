import XCTest
@testable import Ghostty

/// Tests for the two pure, testable pieces of the session composer's
/// behavior (Phase 2): prefix-first relevance ranking (ship gate 3) and the
/// three-tier project dropdown ordering (ship gate 4). Neither type touches
/// SwiftUI or `@MainActor` state.
final class SessionComposerRankingTests: XCTestCase {

    // MARK: - matchTier

    func testMatchTierExactPrefixOutranksSubstring() {
        XCTAssertEqual(SessionComposerRanking.matchTier(title: "Claude Code", query: "cl"), .exactPrefix)
        XCTAssertEqual(SessionComposerRanking.matchTier(title: "Reclaude", query: "cl"), .substring)
    }

    func testMatchTierSubstringOutranksInitials() {
        // "cc" is not a substring of "Claude Code" but matches its initials.
        XCTAssertEqual(SessionComposerRanking.matchTier(title: "Claude Code", query: "cc"), .initials)
        // "cc" is a substring of "accumulate" without being a prefix.
        XCTAssertEqual(SessionComposerRanking.matchTier(title: "accumulate", query: "cc"), .substring)
    }

    func testMatchTierIsCaseInsensitive() {
        XCTAssertEqual(SessionComposerRanking.matchTier(title: "Claude Code", query: "CL"), .exactPrefix)
    }

    func testMatchTierNilWhenNoMatch() {
        XCTAssertNil(SessionComposerRanking.matchTier(title: "Claude Code", query: "zzz"))
    }

    func testMatchTierNilForBlankQuery() {
        XCTAssertNil(SessionComposerRanking.matchTier(title: "Claude Code", query: "   "))
    }

    // MARK: - sorted(_:query:title:) — the "type a prefix, Return always starts that session" gate

    func testSortedRanksExactPrefixFirstRegardlessOfInputOrder() {
        // "blue" must not surface rows by dot color (the defect this
        // replaces) — none of these have any color association at all,
        // and the exact-prefix match must still win.
        let items = ["Background Worker", "Blueprint", "Blue Ghost Shell"]
        let result = SessionComposerRanking.sorted(items, query: "blue", title: { $0 })
        XCTAssertEqual(result.first, "Blueprint")
    }

    func testSortedPreservesOriginalOrderWithinATier() {
        let items = ["Bravo", "Beta", "Bango"]
        let result = SessionComposerRanking.sorted(items, query: "b", title: { $0 })
        // All three are exact-prefix matches on "b" — original order
        // (stable partition, not a re-sort) must be preserved.
        XCTAssertEqual(result, ["Bravo", "Beta", "Bango"])
    }

    func testSortedDropsNonMatches() {
        let items = ["Claude Code", "Shell", "Browser"]
        let result = SessionComposerRanking.sorted(items, query: "claude", title: { $0 })
        XCTAssertEqual(result, ["Claude Code"])
    }

    func testSortedReturnsInputUnchangedForBlankQuery() {
        let items = ["Zed", "Alpha", "Middle"]
        XCTAssertEqual(SessionComposerRanking.sorted(items, query: "", title: { $0 }), items)
    }

    /// The regression `testSortedRanksExactPrefixFirstRegardlessOfInputOrder`
    /// was named for but didn't exercise: the loser there is dropped as a
    /// non-match, so the comparator's `lhs.tier != rhs.tier` branch never
    /// runs. Here both items match, a substring match precedes a prefix
    /// match in input order, and the tier must still win.
    func testSortedRanksExactPrefixBeforeSubstringWhenSubstringComesFirstInInputOrder() {
        let items = ["Reclaude", "Claude Code"]
        let result = SessionComposerRanking.sorted(items, query: "cl", title: { $0 })
        XCTAssertEqual(result, ["Claude Code", "Reclaude"])
    }

    /// Same tier-reordering gate, one level down: a substring match must
    /// outrank an initials match even when the initials match comes first
    /// in input order.
    func testSortedRanksSubstringBeforeInitialsWhenInitialsComesFirstInInputOrder() {
        let items = ["Claude Code", "accumulate"]
        let result = SessionComposerRanking.sorted(items, query: "cc", title: { $0 })
        XCTAssertEqual(result, ["accumulate", "Claude Code"])
    }

    // MARK: - SessionComposerProjectOrdering — the three-tier gate

    func testOrderPutsCascadePickFirst() {
        let a = Project(name: "Alpha", rootPath: "/a")
        let b = Project(name: "Beta", rootPath: "/b")
        let c = Project(name: "Gamma", rootPath: "/c")

        let result = SessionComposerProjectOrdering.order(
            projects: [a, b, c],
            cascadePick: c.id,
            recentProjectIds: []
        )

        XCTAssertEqual(result.map(\.id), [c.id, a.id, b.id])
    }

    func testOrderPutsRecentlyUsedBeforeAlphabeticalTail() {
        let a = Project(name: "Alpha", rootPath: "/a")
        let b = Project(name: "Beta", rootPath: "/b")
        let c = Project(name: "Gamma", rootPath: "/c")

        // No cascade pick. Beta was used most recently, then Gamma.
        // Alpha (alphabetically first) must still fall to the tail.
        let result = SessionComposerProjectOrdering.order(
            projects: [a, b, c],
            cascadePick: nil,
            recentProjectIds: [b.id, c.id]
        )

        XCTAssertEqual(result.map(\.id), [b.id, c.id, a.id])
    }

    func testOrderTailIsAlphabeticalOnceCascadeAndRecentAreExcluded() {
        let a = Project(name: "Zebra", rootPath: "/z")
        let b = Project(name: "Alpha", rootPath: "/a")
        let c = Project(name: "Mango", rootPath: "/m")

        let result = SessionComposerProjectOrdering.order(
            projects: [a, b, c],
            cascadePick: nil,
            recentProjectIds: []
        )

        XCTAssertEqual(result.map(\.name), ["Alpha", "Mango", "Zebra"])
    }

    func testOrderDoesNotDuplicateACascadePickThatIsAlsoRecent() {
        let a = Project(name: "Alpha", rootPath: "/a")
        let b = Project(name: "Beta", rootPath: "/b")

        let result = SessionComposerProjectOrdering.order(
            projects: [a, b],
            cascadePick: a.id,
            recentProjectIds: [a.id, b.id]
        )

        XCTAssertEqual(result.map(\.id), [a.id, b.id])
    }

    func testOrderIgnoresRecentIdsNotInTheProjectList() {
        let a = Project(name: "Alpha", rootPath: "/a")
        let staleId = UUID()

        let result = SessionComposerProjectOrdering.order(
            projects: [a],
            cascadePick: nil,
            recentProjectIds: [staleId]
        )

        XCTAssertEqual(result.map(\.id), [a.id])
    }
}
