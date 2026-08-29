import Foundation
import Testing
import GhosttiesCore
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

    // MARK: - .pending (blocker 2, Slice B review round 2)

    /// The exact bug blocker 2 closes: a typed branch must not resolve
    /// against a cache that describes a DIFFERENT project — even if the
    /// token happens to match one of that OTHER project's worktree
    /// branches. Without the project-id guard this would incorrectly
    /// return `.resolved`, and the caller would launch into the wrong
    /// project's worktree with no error.
    @Test func typedBranchAgainstAMismatchedCacheIsPendingNotResolved() {
        let projectA = UUID()
        let projectB = UUID()
        let worktrees = [makeWorktree(path: "/tmp/A-worktrees/feat-x", branch: "feat-x")]

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "feat-x",
            worktrees: worktrees,
            currentBranchAtProjectRoot: nil,
            cachedProjectId: projectA,
            resolvingForProjectId: projectB
        )
        #expect(resolution == .pending)

        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: "/tmp/A-worktrees/feat-x"
        )
        guard case .failure(let error) = result else {
            Issue.record("expected failure — must not inherit project A's worktree while resolving for project B")
            return
        }
        #expect(!error.message.contains("No worktree found"), "must read as 'not checked yet', not 'genuinely no such branch' (should-fix 4)")
    }

    /// The initial-refresh-window sub-case of should-fix 4: before
    /// `worktreesProjectId` has been populated at all (`nil`), a typed
    /// branch against the CURRENTLY OPEN project (also effectively "no
    /// cached project yet") must still read as pending, not resolved —
    /// there is nothing to distinguish "not fetched yet" from "fetched and
    /// empty" other than the id itself, and `nil != someProjectId`.
    @Test func typedBranchBeforeAnyRefreshHasLandedIsPending() {
        let currentProject = UUID()

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "main",
            worktrees: [],
            currentBranchAtProjectRoot: nil,
            cachedProjectId: nil,
            resolvingForProjectId: currentProject
        )
        #expect(resolution == .pending)
    }

    /// A matching cache (the ordinary case) must still resolve normally —
    /// the project-id guard must not turn EVERY typed branch into
    /// `.pending`, only a genuine mismatch or an unpopulated cache.
    @Test func typedBranchAgainstAMatchingCacheStillResolvesNormally() {
        let projectId = UUID()
        let worktrees = [makeWorktree(path: "/tmp/feat-x", branch: "feat/x")]

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "feat/x",
            worktrees: worktrees,
            currentBranchAtProjectRoot: "main",
            cachedProjectId: projectId,
            resolvingForProjectId: projectId
        )
        #expect(resolution == .resolved(path: "/tmp/feat-x"))
    }

    /// Every EXISTING call site (before blocker 2) never passed either
    /// project-id argument at all — both default to `nil`, and `nil ==
    /// nil` is `true`, so omitting them must behave exactly as before this
    /// fix. This is what keeps the five pre-existing tests above this mark
    /// green unmodified.
    @Test func typedBranchResolutionDefaultsPreserveThePreExistingUnscopedBehavior() {
        let worktrees = [makeWorktree(path: "/tmp/feat-x", branch: "feat/x")]
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: "feat/x",
            worktrees: worktrees,
            currentBranchAtProjectRoot: "main"
        )
        #expect(resolution == .resolved(path: "/tmp/feat-x"))
    }

    // MARK: - Round-6 review, Blocker: proving the PRODUCTION CALL SITE wiring, not just `resolveTypedBranch`

    /// Creates a fresh throwaway repo with one commit on branch "main" under
    /// `NSTemporaryDirectory()`, cleaned up by the caller — same pattern as
    /// `GitWorktreeCreationTests.makeThrowawayRepo()`.
    private static func makeThrowawayRepo() -> String {
        let unresolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-branch-wiring-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: unresolvedPath, withIntermediateDirectories: true)
        let path = realPath(unresolvedPath)

        func run(_ args: [String]) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = args
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }

        run(["git", "-C", path, "init", "-q", "-b", "main"])
        run(["git", "-C", path, "-c", "user.email=test@ghostties.test", "-c", "user.name=Ghostties Test",
             "commit", "-q", "--allow-empty", "-m", "init"])
        return path
    }

    private static func realPath(_ path: String) -> String {
        guard let cPath = realpath(path, nil) else { return path }
        defer { free(cPath) }
        return String(cString: cPath)
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// THE mutant-catching test for the round-6 blocker (`cachedProjectId:`
    /// silently dropped from `SessionComposerPalette.typedBranchResolution`'s
    /// real call). Every OTHER test in this file calls
    /// `SessionComposerCommandParser.resolveTypedBranch` directly with both
    /// `cachedProjectId`/`resolvingForProjectId` hand-passed — none of them
    /// exercises which STORED PROPERTY the palette actually wires into
    /// `cachedProjectId`, which is exactly what broke: the argument had a
    /// `= nil` default, so omitting it compiled clean and silently made
    /// every typed branch permanently `.pending`.
    ///
    /// This test instead drives `SessionComposerPalette.resolveTypedBranch(
    /// branchToken:composerStore:resolvingForProjectId:)` — the `internal
    /// static` seam the palette's real `typedBranchResolution` property
    /// calls verbatim — against a `SessionComposerStore` whose
    /// `worktreesProjectId` is populated the ONLY way production populates
    /// it: a real `refreshWorktrees(for:projectId:)` call against a real
    /// throwaway git repo. `cachedProjectId` is read OFF THE STORE inside
    /// the seam, never passed in by this test, so a future edit that drops
    /// the argument again (or wires the wrong store property) fails this
    /// test rather than just a hand-constructed call.
    ///
    /// Mutation: drop `cachedProjectId: composerStore.worktreesProjectId,`
    /// from `SessionComposerPalette.resolveTypedBranch` (restoring the exact
    /// round-6 bug) — the matching-project assertion below goes red
    /// (`.pending` instead of `.isDefaultBranch`), because the callee's
    /// `cachedProjectId` default (`nil`) no longer equals the non-nil
    /// `resolvingForProjectId` even though the cache genuinely does
    /// describe that project.
    @MainActor
    @Test func typedBranchResolutionWiresComposerStoreWorktreesProjectIdAsCachedProjectId() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let store = SessionComposerStore(isolatedForTesting: ())
        let projectId = UUID()
        await store.refreshWorktrees(for: repo, projectId: projectId)

        // Sanity: production really did populate the cache for this project
        // — if this fails, the test below isn't exercising what it claims to.
        #expect(store.worktreesProjectId == projectId)

        // Matching project: the cache genuinely describes the project being
        // resolved for, so a typed branch matching the repo's default branch
        // must resolve to "no override", not `.pending`.
        let matching = SessionComposerPalette.resolveTypedBranch(
            branchToken: "main",
            composerStore: store,
            resolvingForProjectId: projectId
        )
        #expect(matching == .isDefaultBranch)

        // Mismatched project: same store, same cached branch data, but
        // resolving for a DIFFERENT project's id — must read `.pending`,
        // never silently resolve against the wrong project's cache. Proves
        // `cachedProjectId` is actually wired to `composerStore
        // .worktreesProjectId` rather than some other value that would
        // happen to equal `projectId` by coincidence.
        let mismatched = SessionComposerPalette.resolveTypedBranch(
            branchToken: "main",
            composerStore: store,
            resolvingForProjectId: UUID()
        )
        #expect(mismatched == .pending)
    }

    // MARK: - Finding 9: proving `precommit` actually CALLS `resolveLaunchTemplate`

    /// THE mutant-catching test finding 9 asks for: `resolveLaunchTemplate`
    /// itself was already proven correct above, but nothing proved
    /// `precommit` actually CALLS it — replacing
    /// `SessionComposerStore.swift`'s `resolveLaunchTemplate` switch inside
    /// `precommit` with `launchTemplate = template` left the suite green.
    /// Routes through `dispatchOverrideForTesting` (finding 9 fix) rather
    /// than `coordinator.createQuickSession`, which mutates
    /// `WorkspaceStore.shared` unconditionally even from the `#if DEBUG`
    /// testing-stub coordinator — see that property's doc comment.
    @MainActor
    @Test func precommitAppliesTheWorktreeOverrideBeforeDispatching() {
        let store = SessionComposerStore(isolatedForTesting: ())
        let project = Project(name: "test-project", rootPath: NSTemporaryDirectory())
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let coordinator = SessionCoordinator()

        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        // `NSTemporaryDirectory()` genuinely exists on disk — satisfies
        // `resolveLaunchTemplate`'s `fileExists` check without a throwaway
        // git repo (this test only needs a real PATH, not a real worktree).
        store.selectedWorktreePath = NSTemporaryDirectory()

        var capturedProject: Project?
        var capturedTemplate: AgentTemplate?
        store.dispatchOverrideForTesting = { project, template in
            capturedProject = project
            capturedTemplate = template
        }

        let success = store.precommit(template: makeTemplate(), coordinator: coordinator, workspaceStore: workspaceStore)

        #expect(success)
        #expect(capturedProject?.id == project.id)
        #expect(capturedTemplate?.workingDirectory == NSTemporaryDirectory())
    }
}
