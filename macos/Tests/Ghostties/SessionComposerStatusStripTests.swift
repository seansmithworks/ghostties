import Testing
@testable import Ghostty

/// Step 4 (Composer UI 11 plan §3): status strip priority and the
/// zero-project empty-state copy — both pure functions on
/// `SessionComposerCommandParser`, tested directly (repo's usual
/// view-test-harness gap).
struct SessionComposerStatusStripTests {

    // MARK: - Strip priority ordering

    @Test func writeErrorWinsOverTypedBranchNotFound() {
        let result = SessionComposerCommandParser.statusStripMessage(
            writeError: "Could not create session",
            typedBranchResolution: .unresolved(token: "feature-x")
        )
        #expect(result == "Could not create session")
    }

    @Test func typedBranchNotFoundRendersWhenNoWriteError() {
        let result = SessionComposerCommandParser.statusStripMessage(
            writeError: nil,
            typedBranchResolution: .unresolved(token: "feature-x")
        )
        #expect(result == "branch \"feature-x\" not found")
    }

    @Test func nilWhenNeitherApplies() {
        let result = SessionComposerCommandParser.statusStripMessage(
            writeError: nil,
            typedBranchResolution: .notTyped
        )
        #expect(result == nil)
    }

    @Test func nilWhenBranchResolvedAndNoWriteError() {
        let result = SessionComposerCommandParser.statusStripMessage(
            writeError: nil,
            typedBranchResolution: .resolved(path: "/tmp/worktree")
        )
        #expect(result == nil)
    }

    // MARK: - Empty-state copy

    @Test func emptyResultsCopyIsAddProjectWhenProjectsAreEmpty() {
        #expect(SessionComposerCommandParser.emptyResultsCopy(isProjectsEmpty: true) == "Add project…")
    }

    @Test func emptyResultsCopyIsNoMatchesOtherwise() {
        #expect(SessionComposerCommandParser.emptyResultsCopy(isProjectsEmpty: false) == "No matches")
    }
}
