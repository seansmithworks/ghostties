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
    /// a no-op.
    @Test func changeProjectChipComparesAgainstCurrentlyShownNotRawSelectedProjectId() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        store.selectedProjectId = projectA.id
        store.searchText = "b cco"

        // `currentlyShown` here stands in for `currentProject?.id`, which
        // would resolve to projectB via the command parse even though
        // `selectedProjectId` still reads projectA.
        let result = store.changeProjectChip(to: projectB.id, currentlyShown: projectB.id)

        #expect(result == .noOp)
        #expect(store.searchText == "b cco")
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
}
