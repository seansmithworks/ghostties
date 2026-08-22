import Foundation
import Testing
@testable import Ghostty

/// Coverage for the breadcrumb chip's cascade + undo logic (composer
/// breadcrumb spec, Slice A — A3/A4), which lives on `SessionComposerStore`
/// specifically so it's testable without constructing `SessionComposerPalette`
/// (a View with private `@State`). Mirrors `SessionComposerPhase3ReviewTests`'
/// pattern: `SessionComposerStore(isolatedForTesting: ())` against a private
/// `UserDefaults` suite, no singleton side effects.
@MainActor
struct SessionComposerBreadcrumbChipTests {

    private func makeProject(name: String) -> Project {
        Project(name: name, rootPath: "/tmp/\(name)-\(UUID().uuidString)")
    }

    // MARK: - A3: cascade rule

    /// Changing the chip to a genuinely different project cascades: it
    /// clears the typed remainder (`searchText`), per the spec's decision
    /// #2 ("a different project invalidates the command").
    @Test func changeProjectChipToADifferentProjectClearsSearchTextAndCascades() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        let result = store.changeProjectChip(to: projectB.id, currentlyShown: projectA.id)

        #expect(result == .changed)
        #expect(store.selectedProjectId == projectB.id)
        #expect(store.searchText == "")
    }

    /// Re-picking the value already shown must be a no-op, not a clear —
    /// clicking the chip and choosing the project already selected must not
    /// wipe what was typed (locked decision #2).
    @Test func changeProjectChipToTheSameProjectIsANoOpAndPreservesSearchText() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        let result = store.changeProjectChip(to: projectA.id, currentlyShown: projectA.id)

        #expect(result == .noOp)
        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "cco -n test")
    }

    /// `currentlyShown` — not the raw `selectedProjectId` — is what "the
    /// value already selected" means. A typed command can resolve a
    /// DIFFERENT project than `selectedProjectId` still reads (A6); picking
    /// that same resolved project via the chip must still be recognized as
    /// a no-op, and picking a project that MATCHES the stale
    /// `selectedProjectId` but NOT what's actually shown must still cascade.
    ///
    /// Replaces `changeProjectChipComparesAgainstCurrentlyShownNotRawSelectedProjectId`
    /// (breadcrumb chip review, inert-test finding): that test passed
    /// `to: projectB.id, currentlyShown: projectB.id` — structurally
    /// identical to the no-op test above it (equal `to`/`currentlyShown`,
    /// full stop) regardless of what `selectedProjectId` was set to, since
    /// `changeProjectChip`'s own guard never reads `selectedProjectId` at
    /// all. It could not discriminate the STORE's `currentlyShown` param
    /// from the STORE's own `selectedProjectId` property because the two
    /// scenarios it exercised never diverged in a way the guard's single
    /// `projectId != currentlyShown` comparison could tell apart.
    ///
    /// This version picks `to: projectA.id` (which equals the STALE
    /// `selectedProjectId`) while `currentlyShown: projectB.id` (the
    /// actually-displayed, command-resolved project) — the two diverge on
    /// purpose. Mutant-verified: swapping the guard to compare against
    /// `self.selectedProjectId` instead of the `currentlyShown` parameter
    /// turns this from `.noOp`/unchanged into `.changed`/cleared, so this
    /// test goes red under that mutation where the old one did not (see
    /// task report for the captured red output).
    ///
    /// Caveat this test does NOT close: the review's actual finding was
    /// about `SessionComposerPalette.changeProjectChip(to:)`'s CALL SITE
    /// (`SessionComposerPalette.swift`) silently reverting to pass
    /// `composerStore.selectedProjectId` instead of the resolved
    /// "currently shown" id — that call site now routes through
    /// `SessionComposerCommandParser.resolveCommitProjectId` (tested in
    /// `SessionComposerCommandParserTests`) rather than re-deriving the
    /// value inline, but neither that test file nor this one can observe
    /// the CALL SITE itself reverting to skip that function outright — this
    /// repo has no SwiftUI view-test harness, the same accepted gap
    /// `resolveCommitProjectId`'s own doc comment already documents.
    @Test func changeProjectChipDiscriminatesCurrentlyShownFromStaleSelectedProjectId() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        store.selectedProjectId = projectA.id
        store.searchText = "b cco"

        // Picking projectA (== the stale `selectedProjectId`) while the chip
        // ACTUALLY shows projectB must still cascade — it is NOT a re-pick
        // of what's displayed.
        let result = store.changeProjectChip(to: projectA.id, currentlyShown: projectB.id)

        #expect(result == .changed)
        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "")
    }

    // MARK: - A4: ⌘Z undo, one step

    /// ⌘Z restores BOTH the cleared project id and the cleared search text
    /// in one call — "one undo step" per the spec.
    @Test func undoProjectChipChangeRestoresClearedSegmentAsOneStep() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        store.changeProjectChip(to: projectB.id, currentlyShown: projectA.id)
        #expect(store.selectedProjectId == projectB.id)
        #expect(store.searchText == "")

        store.undoProjectChipChange()

        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "cco -n test")
    }

    /// A second ⌘Z with nothing pending (already restored once, or no chip
    /// change ever happened) is a no-op — it must not touch current state.
    @Test func undoProjectChipChangeIsANoOpWithNothingPending() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        store.selectedProjectId = projectA.id
        store.searchText = "cco"

        store.undoProjectChipChange()

        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "cco")
    }

    /// A no-op chip change (re-picking the same project) must not leave
    /// anything for ⌘Z to restore — there was nothing cleared.
    @Test func noOpChipChangeDoesNotArmUndo() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        store.changeProjectChip(to: projectA.id, currentlyShown: projectA.id)
        store.undoProjectChipChange()

        // Undo had nothing pending, so state is exactly as it was — this
        // would only fail if a no-op change incorrectly armed the undo
        // stack with (projectA, "cco -n test"), in which case this second
        // call would be a harmless identity restore rather than a true
        // no-op; searchText/selectedProjectId can't distinguish the two,
        // so `pendingChipUndo` itself is asserted directly.
        #expect(store.pendingChipUndo == nil)
        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "cco -n test")
    }

    // MARK: - F8 (round-2 review): popChipToText / noteSearchTextEditedByTyping

    /// `popChipToText(projectName:)` is the single write path for the A5
    /// "backspace the chip back to raw text" gesture: it must clear
    /// `selectedProjectId` (the chip has nothing selected anymore) AND set
    /// `searchText` to the popped project's name (not clear it, unlike
    /// `selectProject(_:)`, which this deliberately does NOT reuse).
    @Test func popChipToTextClearsSelectionAndSetsSearchTextToProjectName() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        store.popChipToText(projectName: "A")

        #expect(store.selectedProjectId == nil)
        #expect(store.searchText == "A")
    }

    /// D4: typing by hand must disarm a pending chip-undo. Without this, ⌘Z
    /// after typing past a chip change would discard the typed keystrokes
    /// with no way back — AppKit's own text-undo never sees them, since this
    /// binding writes `searchText` directly, bypassing the field editor's
    /// undo manager.
    @Test func noteSearchTextEditedByTypingDisarmsPendingChipUndo() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        store.selectedProjectId = projectA.id
        store.searchText = "cco -n test"

        store.changeProjectChip(to: projectB.id, currentlyShown: projectA.id)
        #expect(store.pendingChipUndo != nil)

        store.noteSearchTextEditedByTyping()

        #expect(store.pendingChipUndo == nil)
    }

    /// A no-op call (nothing pending yet) must not somehow arm or otherwise
    /// mutate state — it only ever clears.
    @Test func noteSearchTextEditedByTypingIsANoOpWithNothingPending() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        store.selectedProjectId = projectA.id
        store.searchText = "cco"

        store.noteSearchTextEditedByTyping()

        #expect(store.pendingChipUndo == nil)
        #expect(store.selectedProjectId == projectA.id)
        #expect(store.searchText == "cco")
    }
}
