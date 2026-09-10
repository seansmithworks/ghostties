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

    // MARK: - Fix 2: pin toggle reseeds selection by id, not stale index

    /// `SessionComposerPalette.reselectedIndex(preserving:in:)` is the pure
    /// seam behind the pin-toggle reseed fix. A row highlighted BELOW the
    /// pin toggle moves UP a lane when it's pinned — the option at the old
    /// index is now a DIFFERENT template, so re-finding by id (not reusing
    /// the old index) is the whole point of the fix.
    ///
    /// Mutant-verified directly against the production symbol: with
    /// `reselectedIndex`'s body temporarily replaced with
    /// `optionId.map { _ in 2 }` (the STALE index the row held before the
    /// reorder — the exact bug this fix closes), this test failed with
    /// `newIndex : 2` vs. expected `newIndex : 0` — the mutation resolved to
    /// whatever template now sits at the old position instead of the one
    /// actually highlighted. The mutation was then reverted; production
    /// `reselectedIndex` is unchanged from what's committed here.
    @Test func reselectedIndexFindsTheHighlightedOptionAfterAPinReordersTheLanes() {
        let recentA = makeOption(name: "Recent A")
        let recentB = makeOption(name: "Recent B")
        // The row the user had highlighted before pinning it — at index 2,
        // the bottom of a 3-row lane.
        let highlighted = makeOption(name: "Highlighted Recent")
        let before = [recentA, recentB, highlighted]

        // Pinning `highlighted` moves it to the front of lane 1 — the old
        // index 2 now points at whatever recent is left there instead.
        let after = SessionComposerPalette.composeLane1(
            pinned: [highlighted],
            recent: [recentA, recentB, highlighted]
        )
        #expect(before[2].id == highlighted.id)
        #expect(after[2].id != highlighted.id)

        let newIndex = SessionComposerPalette.reselectedIndex(preserving: highlighted.id, in: after)

        #expect(newIndex == 0)
    }

    /// A `nil` preserved id (nothing was highlighted before the toggle)
    /// falls back to "no index found" so the caller reseeds via
    /// `reselectBestMatch()` instead.
    @Test func reselectedIndexReturnsNilWhenNothingWasPreviouslySelected() {
        let option = makeOption(name: "Some Option")

        let newIndex = SessionComposerPalette.reselectedIndex(preserving: nil, in: [option])

        #expect(newIndex == nil)
    }

    // MARK: - Composer variant G: rest-state lane cap

    /// Blank query caps a lane at `restStateLaneCap` (3), keeping the FIRST
    /// three of whatever ordering the caller already applied — proof this
    /// caps AFTER ordering, not before, since `applyRestStateCap` never
    /// reorders its input.
    ///
    /// Mutant-verified directly against the production symbol: with
    /// `applyRestStateCap`'s body temporarily replaced with `return
    /// options` (the cap deleted), `#expect(capped.count == 3)` failed —
    /// the uncapped 6-option array passed through untouched. The mutation
    /// was then reverted; production `applyRestStateCap` is unchanged from
    /// what's committed here.
    @Test func applyRestStateCapKeepsOnlyTheFirstThreeAtBlankQuery() {
        let options = (0..<6).map { makeOption(name: "Option \($0)") }

        let capped = SessionComposerPalette.applyRestStateCap(to: options, query: "")

        #expect(capped.count == 3)
        #expect(capped.map(\.id) == Array(options.prefix(3)).map(\.id))
    }

    /// A non-blank query is never capped — hiding a filtered match would
    /// defeat the point of searching for it. Proves a 4th+ match still
    /// appears once the user types.
    @Test func applyRestStateCapPassesThroughUnchangedWhenQueryIsNonBlank() {
        let options = (0..<6).map { makeOption(name: "Option \($0)") }

        let uncapped = SessionComposerPalette.applyRestStateCap(to: options, query: "opt")

        #expect(uncapped.count == 6)
        #expect(uncapped.map(\.id) == options.map(\.id))
    }
}
