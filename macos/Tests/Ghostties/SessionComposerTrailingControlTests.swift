import Testing
import GhosttiesCore
@testable import Ghostty

/// Step 5 (Composer UI 11 plan §3): `trailingControlVisibility`'s matrix —
/// the pure decision the view reads for `projectControl`/`branchControl`
/// visibility and the branch control's label, tested directly.
struct SessionComposerTrailingControlTests {
    private typealias Visibility = SessionComposerCommandParser.TrailingControlVisibility

    // MARK: - Hidden when locked

    @Test func projectControlHiddenWhenLocked() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: true,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            currentBranchLabel: nil
        )
        #expect(result.showProjectControl == false)
    }

    @Test func projectControlVisibleWhenUnlocked() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            currentBranchLabel: nil
        )
        #expect(result.showProjectControl == true)
    }

    // MARK: - Branch control absent when non-git

    @Test func branchControlAbsentWhenNonGit() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            currentBranchLabel: "feature-x"
        )
        #expect(result.showBranchControl == false)
        #expect(result.branchControlLabel == nil)
    }

    @Test func branchControlVisibleWhenGitEligible() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            currentBranchLabel: nil
        )
        #expect(result.showBranchControl == true)
    }

    // MARK: - "Creating…" label while isCreatingWorktree

    @Test func branchControlShowsCreatingLabelWhileCreatingWorktree() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: true,
            currentBranchLabel: nil
        )
        #expect(result.branchControlLabel == "Creating…")
    }

    @Test func branchControlShowsOverrideBranchNameWhenNotCreating() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            currentBranchLabel: "feature-x"
        )
        #expect(result.branchControlLabel == "feature-x")
    }

    @Test func branchControlShowsNoLabelForDefaultBranch() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            currentBranchLabel: nil
        )
        #expect(result.branchControlLabel == nil)
    }

    // MARK: - Both hidden together (locked + non-git project)

    @Test func bothControlsHiddenWhenLockedAndNonGit() {
        let result = SessionComposerCommandParser.trailingControlVisibility(
            isProjectLocked: true,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            currentBranchLabel: nil
        )
        #expect(result.showProjectControl == false)
        #expect(result.showBranchControl == false)
    }
}
