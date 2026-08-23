import Foundation
import Testing
@testable import Ghostty

/// Coverage for finding 18 (Slice B review round 1): "the feature itself has
/// no coverage — nothing references `precommit`, `workingDirectory`, or
/// `resolveCommitWorktreePath`. Every B3 test asserts store state and stops,
/// so the one line that makes a branch change the launch directory could be
/// deleted and the suite stays green."
///
/// `SessionComposerStore.precommit(template:coordinator:workspaceStore:)`
/// itself is NOT exercised end-to-end here — its only other effect is
/// dispatching `coordinator.createQuickSession`, which calls
/// `WorkspaceStore.shared.addSession(...)` UNCONDITIONALLY, before it ever
/// checks whether `ghostty` is nil — even the `#if DEBUG` testing-stub
/// `SessionCoordinator()` would still mutate the real, persisted
/// `WorkspaceStore.shared` singleton. `SessionComposerStore.resolveLaunchTemplate`
/// is the pure extraction that makes the actual override logic testable
/// without that side effect — see its doc comment on `SessionComposerStore`.
@MainActor
struct SessionComposerBranchLaunchTests {

    private func makeTemplate() -> AgentTemplate {
        AgentTemplate.shell
    }

    // MARK: - resolveLaunchTemplate (the seam finding 18 exists for)

    @Test func resolveLaunchTemplateLeavesWorkingDirectoryUntouchedWithNoWorktreePick() {
        let template = makeTemplate()
        #expect(template.workingDirectory == nil)

        let result = SessionComposerStore.resolveLaunchTemplate(
            template: template,
            selectedWorktreePath: nil
        )

        guard case .success(let launchTemplate) = result else {
            Issue.record("expected success with no worktree pick")
            return
        }
        #expect(launchTemplate.workingDirectory == nil)
    }

    /// THE mutant-catching test: proves `resolveLaunchTemplate` actually
    /// applies the branch chip's pick as `workingDirectory` — delete
    /// `launchTemplate.workingDirectory = worktreePath` from
    /// `resolveLaunchTemplate` (the same effect as deleting
    /// `SessionComposerStore.swift`'s former line 440 inside `precommit`,
    /// now hoisted here) and this goes red: `launchTemplate.workingDirectory`
    /// would read `nil` instead of the worktree path.
    @Test func resolveLaunchTemplateOverridesWorkingDirectoryWithTheWorktreePick() {
        let template = makeTemplate()
        let worktreePath = "/tmp/some-worktree-path-that-exists"

        let result = SessionComposerStore.resolveLaunchTemplate(
            template: template,
            selectedWorktreePath: worktreePath,
            fileExists: { $0 == worktreePath }
        )

        guard case .success(let launchTemplate) = result else {
            Issue.record("expected success when the worktree path exists")
            return
        }
        #expect(launchTemplate.workingDirectory == worktreePath)
        // The ORIGINAL template must be untouched — `resolveLaunchTemplate`
        // returns a modified COPY, never mutates its argument (`AgentTemplate`
        // is a struct, but this proves the call site actually reads the
        // returned value rather than assuming in-place mutation).
        #expect(template.workingDirectory == nil)
    }

    @Test func resolveLaunchTemplateFailsWhenTheWorktreeNoLongerExists() {
        let template = makeTemplate()
        let worktreePath = "/tmp/a-worktree-that-was-deleted"

        let result = SessionComposerStore.resolveLaunchTemplate(
            template: template,
            selectedWorktreePath: worktreePath,
            fileExists: { _ in false }
        )

        guard case .failure(let error) = result else {
            Issue.record("expected failure when the worktree path is missing")
            return
        }
        #expect(error.message.contains(worktreePath))
    }

    // MARK: - resolveTypedBranch / resolveCommitWorktreePathForCommit (blocker 2)

    private func makeWorktree(path: String, branch: String) -> GitWorktreeEnumerator.Worktree {
        GitWorktreeEnumerator.Worktree(path: path, branch: branch, isLocked: false)
    }

    @Test func typedBranchNotTypedFallsThroughToWhateverIsAlreadySelected() {
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: nil,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        #expect(resolution == .notTyped)

        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: "/tmp/prior-pick"
        )
        guard case .success(let path) = result else {
            Issue.record("expected success for .notTyped")
            return
        }
        #expect(path == "/tmp/prior-pick")
    }

    @Test func typedBranchResolvesToACachedWorktreeAndWinsOverThePriorPick() {
        let worktrees = [makeWorktree(path: "/tmp/feat-x", branch: "feat/x")]
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "feat/x",
            worktrees: worktrees,
            currentBranchAtProjectRoot: "main"
        )
        #expect(resolution == .resolved(path: "/tmp/feat-x"))

        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: "/tmp/some-other-prior-pick"
        )
        guard case .success(let path) = result else {
            Issue.record("expected success for a resolved typed branch")
            return
        }
        #expect(path == "/tmp/feat-x")
    }

    /// The specific sub-case blocker 2 calls out: `worktrees` never contains
    /// the project's own root (the store filters it out), so typing the
    /// DEFAULT branch's own name can never match `.resolved` — this proves
    /// it still resolves correctly, to "no override", rather than falling
    /// through to `.unresolved`.
    @Test func typedBranchMatchingTheProjectRootBranchResolvesToDefaultNotUnresolved() {
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "main",
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        #expect(resolution == .isDefaultBranch)

        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: "/tmp/some-prior-pick"
        )
        guard case .success(let path) = result else {
            Issue.record("expected success for the default branch")
            return
        }
        #expect(path == nil)
    }

    /// Blocker 2's core fix: an unresolvable typed branch must FAIL, never
    /// silently inherit whatever the picker had selected before typing
    /// started — this is the exact "chip reads main, session launches in
    /// feat/x" bug.
    @Test func typedBranchThatResolvesToNothingFailsInsteadOfInheritingThePriorPick() {
        let worktrees = [makeWorktree(path: "/tmp/feat-x", branch: "feat/x")]
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "nonexistent-branch",
            worktrees: worktrees,
            currentBranchAtProjectRoot: "main"
        )
        #expect(resolution == .unresolved(token: "nonexistent-branch"))

        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: "/tmp/feat-x"
        )
        guard case .failure(let error) = result else {
            Issue.record("expected failure for an unresolvable typed branch — must not inherit /tmp/feat-x")
            return
        }
        #expect(error.message.contains("nonexistent-branch"))
    }
}
