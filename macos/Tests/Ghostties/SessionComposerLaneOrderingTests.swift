import Foundation
import Testing
@testable import Ghostty

/// Coverage for `SessionComposerPalette.composeLane1(pinned:recent:)` —
/// the pure seam extracted from the (otherwise private, `@State`-driven)
/// lane-1 composition so it's testable without a SwiftUI view-test harness
/// (this repo has none). `flattenedOptions`'s first element — what
/// `onAppear` seeds `selectedIndex` to on a blank query — is exactly
/// `composeLane1`'s first element, so these tests are direct proof of what
/// first-open Return will commit.
@MainActor
struct SessionComposerLaneOrderingTests {

    private func makeOption(name: String) -> ComposerOption {
        ComposerOption(id: UUID(), title: name, subtitle: nil, leadingIcon: nil, action: {})
    }

    // MARK: - G-F8: pinned-ahead-of-recents moves index 0

    /// Pinned options render first, so `composeLane1`'s (and therefore
    /// `flattenedOptions`'s) index 0 is the top PINNED template whenever any
    /// pin exists — not the most recent one. First-open Return (S5's
    /// `selectedIndex = bestSelectionIndex(in: flattenedOptions)`, blank
    /// query, index 0) now commits that pinned template.
    ///
    /// Mutant-verified directly against the PRODUCTION symbol: with
    /// `composeLane1`'s `return pinned + recentMinusPinned` temporarily
    /// swapped to `return recentMinusPinned + pinned` and this test run in
    /// isolation, it failed with:
    /// `lane1.first?.id : 27F808AD-47AE-43E0-BFA9-F45F4FADA362` (the RECENT
    /// option's id) vs. expected `pinnedHead.id :
    /// 65B9EC39-1C15-4038-84C8-7722F3BF8804` (the PINNED option's id) — i.e.
    /// the mutation flipped index 0 from pinned to recent and this
    /// assertion caught it. The mutation was then reverted; production
    /// `composeLane1` is unchanged from what's committed here.
    @Test func composeLane1PutsThePinnedHeadAtIndexZero() {
        let pinnedHead = makeOption(name: "Pinned Template")
        let mostRecent = makeOption(name: "Most Recent Template")

        let lane1 = SessionComposerPalette.composeLane1(pinned: [pinnedHead], recent: [mostRecent])

        #expect(lane1.first?.id == pinnedHead.id)
    }

    // MARK: - Dedupe: pinned-and-recent renders once, in the pinned block

    /// A template that's both pinned AND recent must not appear twice —
    /// 11.1 backlog strawman, adapted: it renders once, in the pinned
    /// block, with the recent copy dropped.
    @Test func composeLane1DropsARecentDuplicateOfAPinnedOption() {
        let shared = makeOption(name: "Both Pinned And Recent")
        let onlyRecent = makeOption(name: "Only Recent")

        let lane1 = SessionComposerPalette.composeLane1(pinned: [shared], recent: [shared, onlyRecent])

        #expect(lane1.map(\.id) == [shared.id, onlyRecent.id])
    }
}
