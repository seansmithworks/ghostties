import Foundation
import Testing
@testable import Ghostty

/// Coverage for the worktree-launch ruling (2026-08-27): "Typing a branch
/// name in the composer surfaces a 'Create worktree for <branch>' row.
/// Pressing Return creates the worktree — and then nothing else happens.
/// No session launches, the composer stays open, the row stays on offer,
/// and a second Return surfaces git's raw `fatal: ... already exists`."
///
/// Exercises `SessionComposerStore.createWorktree(named:in:launchTemplate:
/// coordinator:workspaceStore:)` end-to-end against a real throwaway git
/// repo (same fixture pattern as `GitWorktreeCreationTests`/
/// `SessionComposerBranchLaunchTests`), and asserts through
/// `dispatchOverrideForTesting` — never `coordinator.createQuickSession`
/// directly, which mutates the real `WorkspaceStore.shared` singleton even
/// from the `#if DEBUG` testing-stub coordinator (see
/// `SessionComposerStore.precommit`'s own doc comment for why).
@MainActor
struct SessionComposerWorktreeLaunchTests {

    // MARK: - Fixture (same shape as GitWorktreeCreationTests.makeThrowawayRepo)

    private static func makeThrowawayRepo() -> String {
        let unresolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-worktree-launch-test-\(UUID().uuidString)")
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

    /// Creates `branchName` as a plain local branch with NO worktree — the
    /// exact precondition `branchesWithoutWorktree` requires to offer it as
    /// a create row in the first place (a brand-new, never-before-seen
    /// branch name is never a member of that list, since it isn't a ref
    /// yet — only a pre-existing branch missing a worktree is).
    private static func makeBranchWithNoWorktree(_ branchName: String, in repo: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repo, "branch", branchName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private static func realPath(_ path: String) -> String {
        guard let cPath = realpath(path, nil) else { return path }
        defer { free(cPath) }
        return String(cString: cPath)
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Polls a MainActor condition instead of a fixed sleep — `createWorktree`
    /// dispatches its git shell-out from an unstructured `Task`, so nothing
    /// in this test can `await` it directly; the fixed 10s internal timeout
    /// is far longer than a throwaway single-commit repo's real `git
    /// worktree add` ever takes.
    private static func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Every poll below that waits on `createWorktree` finishing MUST use
    /// this, not the 5s default above. `SessionComposerStore.createWorktree`
    /// races its `git worktree add` against its OWN internal 10-second
    /// timeout (`Self.race(gitTask, timeoutSeconds: 10)`, production code,
    /// never touched here) — a poll with a shorter budget than that can
    /// observe genuine MID-FLIGHT state (still creating, not yet
    /// success/failure) under load and misread it as a broken fix. Proven
    /// in practice: under the full 975-test unfiltered suite's parallel
    /// CPU contention, real `git` shell-outs here landed between 5-10s,
    /// comfortably inside production's 10s ceiling but outside a 5s or 8s
    /// poll — a false negative in the TEST, not a defect in `createWorktree`
    /// (all three tests below pass 100% reliably run in isolation). `12`,
    /// strictly above the 10s it's timed against, not a round number picked
    /// for comfort.
    private static let createWorktreeCompletionTimeout: TimeInterval = 12

    // MARK: - 1. Launch-on-create fires exactly once when the field is launchable

    /// THE mutant-catching test for item 1 of the ruling: revert
    /// `createWorktree`'s `if let launchTemplate, let coordinator, let
    /// workspaceStore { _ = precommit(...) }` block and this goes red —
    /// `launchCount` stays 0 instead of reaching 1, because nothing
    /// dispatches the launch on a successful creation.
    @Test func launchOnCreateFiresExactlyOnceWhenFieldIsLaunchable() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let coordinator = SessionCoordinator()
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        var launchCount = 0
        var capturedProject: Project?
        var capturedTemplate: AgentTemplate?
        store.dispatchOverrideForTesting = { project, template in
            launchCount += 1
            capturedProject = project
            capturedTemplate = template
        }

        let branchName = "feat-launchable"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")

        store.createWorktree(
            named: branchName,
            in: project,
            launchTemplate: AgentTemplate.shell,
            coordinator: coordinator,
            workspaceStore: workspaceStore
        )

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        #expect(launchCount == 1, "expected exactly one launch, got \(launchCount)")
        #expect(capturedProject?.id == project.id)
        #expect(capturedTemplate?.workingDirectory == expectedPath, "launch must target the NEW worktree, not the project root")
        #expect(store.selectedWorktreePath == expectedPath)
    }

    // MARK: - 2. Launch does NOT fire when the field is empty; branch chip resolves instead

    /// THE mutant-catching test for item 2: relax the production guard from
    /// `if let launchTemplate, let coordinator, let workspaceStore` to `if
    /// let coordinator, let workspaceStore` (falling back to a default
    /// template when `launchTemplate` is `nil`) and this goes red —
    /// `launchCount` becomes 1 when it must stay 0. `coordinator`/
    /// `workspaceStore` are deliberately passed here (non-nil) so the only
    /// thing gating the launch is `launchTemplate` itself, not an
    /// incidental nil elsewhere in the call.
    @Test func launchDoesNotFireWhenTheFieldIsEmptyAndTheBranchChipResolvesInstead() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let coordinator = SessionCoordinator()
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        var launchCount = 0
        store.dispatchOverrideForTesting = { _, _ in launchCount += 1 }

        let branchName = "feat-not-launchable"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")

        store.createWorktree(
            named: branchName,
            in: project,
            launchTemplate: nil,
            coordinator: coordinator,
            workspaceStore: workspaceStore
        )

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        #expect(launchCount == 0, "must not launch when nothing launchable was typed")
        #expect(store.selectedWorktreePath == expectedPath, "the branch chip must still resolve to the new worktree")
    }

    // MARK: - 3. The branch no longer appears as a create-offer after a successful creation

    /// THE mutant-catching test for item 3: comment out `await
    /// refreshWorktrees(for: repoPath, projectId: project.id)` from
    /// `createWorktree`'s success case and this goes red — `store
    /// .branchesWithoutWorktree` keeps stale pre-creation data forever, so
    /// `branchName` never drops out of it, which is exactly the "row stays
    /// on offer, second Return hits git's raw already-exists" bug this test
    /// exists to close off.
    @Test func branchNoLongerAppearsAsACreateOfferAfterASuccessfulCreation() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let branchName = "feat-offer-then-created"
        Self.makeBranchWithNoWorktree(branchName, in: repo)

        await store.refreshWorktrees(for: repo, projectId: project.id)
        // `refreshWorktrees` has its own internal 2s race timeout (a
        // parallel-testing machine under load can occasionally trip it),
        // in which case it leaves `branchesWithoutWorktree` untouched and
        // self-schedules a retry rather than blocking — poll rather than
        // trust a single `await` to have landed real data.
        await Self.waitUntil { store.branchesWithoutWorktree.contains(branchName) }

        // Sanity: the offer really is live before creation — if this fails,
        // the test below isn't exercising the bug it claims to.
        #expect(store.branchesWithoutWorktree.contains(branchName), "setup failed: branch must offer a create row before creation")

        store.createWorktree(named: branchName, in: project)

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }
        // Same rationale as the setup poll above: the refresh this success
        // path awaits internally can itself hit its 2s race timeout under
        // load, in which case `isCreatingWorktree` already flips `false`
        // before the self-scheduled retry lands the real data — poll
        // rather than assert on the very next runloop tick.
        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.branchesWithoutWorktree.contains(branchName) }

        #expect(!store.branchesWithoutWorktree.contains(branchName), "the branch must stop offering a create row once the worktree exists")
    }
}
