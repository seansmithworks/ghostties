import Foundation
import Testing
@testable import Ghostty

/// Coverage for the worktree-launch ruling (2026-08-27) and its control-flow
/// INVERSION (independent review, round 2): "Typing a branch name in the
/// composer surfaces a 'Create worktree for <branch>' row. Pressing Return
/// creates the worktree — and then nothing else happens." The FIRST
/// implementation launched by calling `precommit` directly from inside
/// `SessionComposerStore.createWorktree`, which duplicated half of
/// `SessionComposerPalette.commit(template:)` and silently dropped the
/// other half (`resolveCommitProjectId`, the `.workspaceDidCreateSessionInProject`
/// post, the `selectedIndex = nil` double-Return guard) — three separate
/// defects. This file now exercises the INVERTED shape:
/// `createWorktree(named:in:onSuccess:)` reports success back to the
/// caller; the store itself launches nothing.
///
/// Exercises `SessionComposerStore.createWorktree` end-to-end against a
/// real throwaway git repo (same fixture pattern as
/// `GitWorktreeCreationTests`/`SessionComposerBranchLaunchTests`), and
/// asserts through `dispatchOverrideForTesting` for anything that reaches
/// `precommit` — never `coordinator.createQuickSession` directly, which
/// mutates the real `WorkspaceStore.shared` singleton even from the `#if
/// DEBUG` testing-stub coordinator (see `SessionComposerStore.precommit`'s
/// own doc comment for why).
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
    /// in this test can `await` it directly.
    private static func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Every poll that waits on `createWorktree` finishing MUST use this.
    /// `SessionComposerStore.createWorktree` races its `git worktree add`
    /// against its OWN internal 10-second timeout (`Self.race(gitTask,
    /// timeoutSeconds: 10)`, production code, never touched here) — a poll
    /// with a shorter budget than that can observe genuine MID-FLIGHT state
    /// (still creating, not yet success/failure) under load and misread it
    /// as a broken fix. Proven in practice: under the full unfiltered
    /// suite's parallel CPU contention, real `git` shell-outs here landed
    /// between 5-10s, comfortably inside production's 10s ceiling but
    /// outside a shorter poll — a false negative in the TEST, not a defect
    /// in `createWorktree`. `12`, strictly above the 10s it's timed
    /// against, not a round number picked for comfort.
    private static let createWorktreeCompletionTimeout: TimeInterval = 12

    /// Any wait bounded by `refreshWorktrees(for:projectId:)`'s own
    /// worst-case latency — not just the plain setup poll it was first
    /// written for, but also the post-creation poll further down that waits
    /// on the SAME call's retry landing (`refreshWorktrees` is invoked
    /// internally there too, just not directly by the test) — needs its
    /// OWN, separately-derived budget from `createWorktreeCompletionTimeout`
    /// above, which is timed against a different, longer-running call
    /// (`createWorktree`'s 10s git-shell-out ceiling). `refreshWorktrees`
    /// races its own 2-second deadline
    /// (`Store.swift`'s `raceAny(listTask, timeoutSeconds: 2)`) and, on a
    /// timeout, self-schedules exactly ONE retry after ANOTHER 2-second
    /// sleep, whose own race can itself take up to 2 more seconds:
    /// worst-case observable latency is 2 (first race) + 2 (retry sleep) +
    /// 2 (retry's own race) = 6 seconds. `8`, the same +2s margin style
    /// `createWorktreeCompletionTimeout` uses over ITS ceiling, applied to
    /// this call's 6s worst case instead of `createWorktree`'s 10s one.
    private static let refreshWorktreesSetupTimeout: TimeInterval = 8

    // MARK: - 1. onSuccess fires exactly once, with the new worktree's path

    /// THE mutant-catching test for the inverted contract: revert
    /// `createWorktree`'s `onSuccess?(path)` call and this goes red.
    @Test func onSuccessFiresExactlyOnceWithTheNewWorktreesPathOnSuccessfulCreation() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let branchName = "feat-onsuccess"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")

        var successCount = 0
        var capturedPath: String?
        store.createWorktree(named: branchName, in: project) { path in
            successCount += 1
            capturedPath = path
        }

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        #expect(successCount == 1, "expected exactly one onSuccess call, got \(successCount)")
        #expect(capturedPath == expectedPath)
        #expect(store.selectedWorktreePath == expectedPath, "the branch chip must resolve to the new worktree regardless of onSuccess")
    }

    /// THE mutant-catching test for round-3 finding 3 (the success branch's
    /// missing `selectionAtStart` guard): remove the `if selectedWorktreePath
    /// == selectionAtStart` check around the success branch's
    /// `selectedWorktreePath = path` write and this goes red. No `await`
    /// separates `createWorktree`'s call from the write below —
    /// `isCreatingWorktree` is set synchronously before `createWorktree`
    /// returns (same ordering guarantee
    /// `doubleReturnDuringCreationProducesExactlyOneGitWorktreeAdd` relies
    /// on), so this deterministically lands the user's pick BEFORE the git
    /// shell-out (on its own detached `Task`) can complete and reach the
    /// success branch.
    @Test func aLegitimateMidFlightSelectionSurvivesASuccessfulCreation() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let branchName = "feat-midflight-pick"
        let userPick = "/tmp/some-other-worktree-the-user-clicked"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")

        var successPath: String?
        store.createWorktree(named: branchName, in: project) { successPath = $0 }
        store.selectedWorktreePath = userPick

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        // Prove creation actually SUCCEEDED before asserting the survival —
        // without this, the assertion below also holds if creation failed or
        // timed out (both branches are guarded by the same `selectionAtStart`
        // check and produce identical state), so it would go green without
        // ever exercising the success branch it claims to guard. Observing
        // `successPath` directly (rather than inferring success from
        // `writeError == nil` alone) closes the guarded-early-return gap:
        // `SessionComposerStore.swift`'s stale-token guards at :1163/:1200
        // return without writing `writeError`, so `writeError == nil` alone
        // cannot distinguish "succeeded" from "silently discarded as stale"
        // — `onSuccess?(path)` at :1206 only fires on the real success path,
        // strictly after the guarded `selectedWorktreePath` write at
        // :1201-1203, so observing it can't perturb the assertion below.
        #expect(store.writeError == nil)
        #expect(successPath == expectedPath, "onSuccess must fire with the new worktree's path on the real success path")

        #expect(store.selectedWorktreePath == userPick, "a deliberate mid-flight pick must survive a successful creation, not be clobbered by the new worktree's path")
    }

    // MARK: - 2. onSuccess is optional — creation still fully resolves without it

    /// Mirrors the branch picker's call site (finding 1: it never launches,
    /// so it passes an `onSuccess` that only refocuses, never one that
    /// inspects the field) — proves creation succeeds and the chip resolves
    /// with `onSuccess` doing nothing launch-related, and that a `nil`
    /// callback (the picker's OWN default in production is a closure, but
    /// the parameter itself defaults to `nil`) never crashes or blocks
    /// completion.
    @Test func creationFullyResolvesWithNoOnSuccessProvided() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let branchName = "feat-no-callback"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")

        store.createWorktree(named: branchName, in: project)

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        #expect(store.selectedWorktreePath == expectedPath)
        #expect(store.writeError == nil)
    }

    // MARK: - 3. The branch no longer appears as a create-offer after a successful creation

    /// THE mutant-catching test for criterion 3 (finding 4, review round
    /// 2). Verified against deleting BOTH `await refreshWorktrees(for:
    /// repoPath, projectId: project.id)` AND the `branchesWithoutWorktree
    /// .removeAll { $0 == branchName }` line together — that combination
    /// goes red. Deleting EITHER ONE ALONE does not turn this specific test
    /// red: against a real throwaway repo, `git worktree add` is
    /// synchronous and `refreshWorktrees`'s own 2-second race virtually
    /// never actually times out, so its ordinary (non-timeout) result
    /// ALREADY excludes the just-created branch — the two mechanisms
    /// backstop each other under fast, reliable git conditions. The
    /// EXPLICIT `removeAll` line exists specifically for the case this test
    /// cannot force deterministically without a production-side
    /// timing-injection seam (out of scope here): `refreshWorktrees`
    /// genuinely racing its 2s deadline and leaving `branchesWithoutWorktree`
    /// stale — the load-induced scenario the bug report actually described
    /// ("the row stays on offer, second Return hits already-exists"). This
    /// is documented, not silently claimed as fully covered — see the PR
    /// report for the same disclosure.
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
        // self-schedules a retry rather than blocking — poll with THIS
        // call's own derived budget rather than trust a single `await` to
        // have landed real data.
        await Self.waitUntil(timeout: Self.refreshWorktreesSetupTimeout) { store.branchesWithoutWorktree.contains(branchName) }

        // Sanity: the offer really is live before creation — if this fails,
        // the test below isn't exercising the bug it claims to.
        #expect(store.branchesWithoutWorktree.contains(branchName), "setup failed: branch must offer a create row before creation")

        store.createWorktree(named: branchName, in: project)

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        // Round 3 deleted the `branchesWithoutWorktree.removeAll` line from
        // production (correctly — it caused a worse bug), which leaves this
        // assertion depending entirely on the post-creation `refreshWorktrees`
        // beating its hardcoded 2s race. Poll it like the setup poll above
        // rather than reading state once. This is NOT racing the success
        // branch's own ordering — `await refreshWorktrees(...)` at
        // `SessionComposerStore.swift:1192` already completes before
        // `isCreatingWorktree = false` at `:1204`, and both the store's Task
        // and this @MainActor test body run on the main actor, so a single
        // read after `!isCreatingWorktree` can never observe the stale
        // pre-refresh list from THAT call. What the poll actually covers:
        // `refreshWorktrees` can lose its own internal
        // `raceAny(listTask, timeoutSeconds: 2)` (`:348`), leaving
        // `branchesWithoutWorktree` untouched and self-scheduling exactly
        // one retry after a 2s sleep (`:389-394`) — this poll's window is
        // what catches that retry landing after `isCreatingWorktree` already
        // flipped false.
        await Self.waitUntil(timeout: Self.refreshWorktreesSetupTimeout) { !store.branchesWithoutWorktree.contains(branchName) }

        #expect(!store.branchesWithoutWorktree.contains(branchName), "the branch must stop offering a create row once the worktree exists")
    }

    // MARK: - 4. Double-Return produces exactly one `git worktree add`

    /// THE mutant-catching test for the double-Return finding: remove
    /// `createWorktree`'s `guard !isCreatingWorktree else { return }` (its
    /// very first line) and this goes red — the SECOND call's own,
    /// wholly-independent `git worktree add` genuinely runs.
    ///
    /// Deliberately uses TWO DIFFERENT branch names, not the same one
    /// twice: an earlier draft of this test called `createWorktree` twice
    /// for the SAME branch and asserted `writeError == nil` /
    /// `successCount == 1` — but with the guard removed, whichever of the
    /// two concurrent `git worktree add` processes for the SAME directory
    /// loses the filesystem race can fail OUTRIGHT (`fatal: ... already
    /// exists`) rather than merely being discarded by the (separate,
    /// already-present) `worktreeCreationToken` blocker-4 guards — and on
    /// SOME runs (observed directly, not hypothetical: one parallel test
    /// worker went red, a SIBLING worker on the SAME mutated build stayed
    /// green) the outer token guard alone happens to mask the second
    /// process's effect, landing `successCount == 1` by coincidence even
    /// with the `!isCreatingWorktree` guard deleted. Two INDEPENDENT branch
    /// names removes that git-level race entirely: the second call names a
    /// directory with no collision to fail against, so if the guard is
    /// missing, its worktree WILL exist on disk, deterministically, no
    /// matter how the filesystem race resolves. The two calls are still
    /// made back-to-back with NO `await` between them —
    /// `isCreatingWorktree = true` is set synchronously by the first call
    /// before it returns, so the second call's guard check itself is
    /// deterministic.
    @Test func doubleReturnDuringCreationProducesExactlyOneGitWorktreeAdd() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let firstBranch = "feat-double-return-first"
        let secondBranch = "feat-double-return-second"
        let secondExpectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(secondBranch)")

        var successCount = 0
        store.createWorktree(named: firstBranch, in: project) { _ in successCount += 1 }
        store.createWorktree(named: secondBranch, in: project) { _ in successCount += 1 }

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }
        // Give a WOULD-BE-BLOCKED second creation the same generous budget
        // to have actually run and finished, if the guard were missing —
        // `isCreatingWorktree` going false only proves the FIRST creation
        // settled; without this, a real second `git worktree add` that
        // started anyway could still be mid-flight when the assertions
        // below run.
        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { successCount >= 1 }

        #expect(successCount == 1, "exactly one creation must proceed, got \(successCount) onSuccess calls")
        #expect(!FileManager.default.fileExists(atPath: secondExpectedPath), "the second call must never even start its own git worktree add — its directory must not exist on disk")
    }

    // MARK: - 5. A superseded creation never leaks into a new context (blocker 4 family)

    /// Guards blocker 4's documented scenario: "create in project A, close,
    /// reopen on B before the refresh returned — still landed A's new
    /// worktree path into B's now-current composer." `cancel()` is called
    /// SYNCHRONOUSLY right after `createWorktree` returns (no `await`
    /// between them) — `store` is `@MainActor` and `createWorktree`'s
    /// internal `Task { ... }` (not `.detached`) inherits that same actor,
    /// so it cannot begin executing ANY of its body while this
    /// `@MainActor` test still holds the actor, i.e. before this test's own
    /// first `await`. That guarantees `worktreeCreationToken` is already
    /// stale before the Task's FIRST line runs.
    ///
    /// Precisely mutation-tested, all four combinations, each rebuilt and
    /// run: BOTH guards present → green (correct). EITHER ONE ALONE
    /// (`Store.swift`'s outer guard right after `await Self.race(...)`, OR
    /// the inner one at the top of `.completed(.success)` right after
    /// `await refreshWorktrees(...)`) → still green — in THIS test's exact
    /// race window (token invalidated before the Task's first line), the
    /// two guards are fully redundant with each other, so deleting one
    /// alone changes nothing observable. BOTH deleted together → red
    /// (`successCount` 0→1, `selectedWorktreePath` nil→the stale path).
    /// This test therefore proves the INVARIANT ("a superseded creation
    /// never leaks") but does NOT independently isolate the SPECIFIC inner
    /// line a reviewer flagged as uncovered — doing that would need a race
    /// that lands the token bump strictly AFTER the outer guard's check and
    /// strictly BEFORE the inner one's, i.e. during `refreshWorktrees`'s own
    /// await specifically. Production has no synchronization seam to force
    /// that narrower window deterministically without adding a test-only
    /// hook, which was out of scope here — reported as a real, remaining
    /// gap rather than claimed as covered.
    @Test func aSupersededCreationNeverFiresOnSuccessIntoTheNewContext() async {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let project = Project(name: "test-project", rootPath: repo)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .locked(project), workspaceStore: workspaceStore)

        let branchName = "feat-superseded"
        let expectedPath = (repo as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")
        var successCount = 0
        store.createWorktree(named: branchName, in: project) { _ in successCount += 1 }
        store.cancel()

        // `cancel()` clears `isCreatingWorktree` synchronously, so polling
        // IT proves nothing here — poll the FILESYSTEM instead: `git
        // worktree add` is a synchronous, durable operation once it exits,
        // so the directory existing is proof the background creation
        // genuinely finished, independent of anything the store's own
        // (now-reset) state says.
        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) {
            FileManager.default.fileExists(atPath: expectedPath)
        }
        // Directory-exists proves `git worktree add` itself finished, NOT
        // that the outer `Task`'s `.completed(.success)` case has run —
        // that case still `await`s a full `refreshWorktrees` (up to its own
        // worst-case 6s chain, see `refreshWorktreesSetupTimeout`'s doc
        // comment) AFTER the directory already exists, before it would ever
        // reach `onSuccess?(path)`. An earlier draft asserted immediately
        // after the file-exists poll and stayed GREEN even with BOTH token
        // guards deleted (`Store.swift:1163`/`1200`) — not because the
        // guards didn't matter, but because the assertion ran before the
        // stale Task could possibly have reached them either way, a false
        // negative in the TEST. Waiting the SAME worst-case budget here,
        // unconditionally, is what makes deleting either guard alone
        // observable.
        try? await Task.sleep(for: .seconds(Self.refreshWorktreesSetupTimeout))

        #expect(successCount == 0, "a creation superseded by cancel() must never fire its onSuccess into the new (reset) context")
        #expect(store.selectedWorktreePath == nil, "cancel()'s reset must not be silently overwritten by the stale creation's own success handler")
    }

    // MARK: - 6. The wrong-project spawn (finding: resolveCommitProjectId skipped)

    /// THE mutant-catching test for the wrong-project finding. Mirrors
    /// `SessionComposerPalette.commit(template:)`'s EXACT production write
    /// — `composerStore.selectedProjectId = SessionComposerCommandParser
    /// .resolveCommitProjectId(commandProjectId:selectedProjectId:)`, called
    /// BEFORE `precommit` — inside this test's `onSuccess` closure, since
    /// `commit(template:)` itself is a `private` `SwiftUI` `View` method
    /// with no test harness (this repo's established, documented gap; see
    /// `SessionComposerBranchLaunchTests`' own doc comments for the same
    /// constraint). This is the closest store-level proxy for "does the
    /// fix's architecture work end-to-end" available without a view-test
    /// harness — it is NOT a test of `commit(template:)`'s body itself.
    ///
    /// `.prefilled`, never `.locked` (the ORIGINAL test file's mistake,
    /// caught by review): `.locked` resolves `precommit`'s target from the
    /// BINDING itself (`SessionComposerStore.swift`, `precommit`'s
    /// `resolvedProjectId`), never from `selectedProjectId` — the
    /// wrong-project bug this test guards against could NEVER reproduce
    /// under `.locked` by construction. Both production entry points
    /// (`SessionComposerOverlay`, `ProjectDisclosureRow`'s popover) use
    /// `.prefilled`/`.open`.
    ///
    /// Mutation: delete this test's own `store.selectedProjectId =
    /// resolveCommitProjectId(...)` line (reproducing the ORIGINAL bug —
    /// launching straight off the stale `selectedProjectId` the way the
    /// first, reverted implementation did) and this goes red —
    /// `capturedProject?.id` reads A (the prefilled selection) instead of B
    /// (the project the worktree was actually created in).
    ///
    /// Deliberately does NOT assert `store.selectedWorktreePath` — while
    /// building this test a SEPARATE, PRE-EXISTING hazard surfaced:
    /// `selectedProjectId`'s `didSet` (`Store.swift:142-146`) cascades on
    /// ANY genuine change (A → B here) and synchronously WIPES `worktrees`/
    /// `worktreesProjectId`/`selectedWorktreePath` before kicking a fresh
    /// async refetch. `commit(template:)`'s real sequence writes
    /// `selectedProjectId` (triggering that wipe) BEFORE its second,
    /// independent read of `typedBranchResolution` (used to re-derive
    /// `selectedWorktreePath`) — and that second read, computed AFTER the
    /// wipe, sees `worktreesProjectId == nil` against `resolvingForProjectId
    /// == B`, which `resolveTypedBranch`'s guard (`SessionComposerCommandParser
    /// .swift`, `guard cachedProjectId == resolvingForProjectId else {
    /// return .pending }`) turns into `.pending` — not the resolved worktree
    /// path. For a typed BRANCH specifically (this feature's entire use
    /// case), `resolveCommitWorktreePathForCommit(.pending, ...)` returns
    /// `.failure`, which `commit(template:)` treats as a loud reject
    /// ("Still checking branches for this project — try again in a
    /// moment."), not a launch. This predates this task's diff — reported,
    /// not fixed, to the coordinator; not attempted here.
    @Test func launchResolvesTheTypedProjectNotTheStalePrefilledSelection() async {
        let repoA = Self.makeThrowawayRepo()
        let repoB = Self.makeThrowawayRepo()
        defer {
            Self.cleanup(repoA)
            Self.cleanup(repoB)
        }

        let projectA = Project(name: "project-a", rootPath: repoA)
        let projectB = Project(name: "project-b", rootPath: repoB)
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])
        let coordinator = SessionCoordinator()
        let store = SessionComposerStore(isolatedForTesting: ())

        store.open(projectBinding: .prefilled(projectA), workspaceStore: workspaceStore)
        #expect(store.selectedProjectId == projectA.id, "setup failed: .prefilled must pre-select A")

        var capturedProject: Project?
        store.dispatchOverrideForTesting = { project, _ in capturedProject = project }

        let branchName = "feat-typed-in-b"

        store.createWorktree(named: branchName, in: projectB) { _ in
            store.selectedProjectId = SessionComposerCommandParser.resolveCommitProjectId(
                commandProjectId: projectB.id,
                selectedProjectId: store.selectedProjectId
            )
            _ = store.precommit(template: AgentTemplate.shell, coordinator: coordinator, workspaceStore: workspaceStore)
        }

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) { !store.isCreatingWorktree }

        #expect(capturedProject?.id == projectB.id, "the session must land in the project the worktree was actually created in (B), not the stale prefilled selection (A)")
    }

    // MARK: - 7. resolveWorktreeCreationLaunchTemplate (findings 1 & 3 — zero coverage before this)

    /// A resolved TERMINATED operator segment (`ghostties feat-x cco `)
    /// wins outright, mirroring `bestSelectionIndex`'s own precedence.
    @Test func launchTemplateResolvesAResolvedOperatorTemplateOutright() {
        let cco = AgentTemplate(id: UUID(), name: "cco", kind: .custom, command: "cco")
        let result = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: cco.id,
            remainderTokens: [],
            templates: [cco]
        )
        #expect(result?.id == cco.id)
    }

    /// THE mutant-catching test for finding 3: an UNTERMINATED template
    /// name (`ghostties feat-x cco`, no trailing separator) never reaches
    /// `resolvedTemplateId` — before this middle tier existed, this fell
    /// straight to `makeAdHocTemplate`, synthesizing a shell template whose
    /// `command` is the literal string `"cco"` — a zsh FUNCTION, not a
    /// binary, which fails silently in a detached `Task` after the
    /// composer has already closed. Delete the middle tier (the `if let
    /// firstRemainderToken ... matchesTemplate` block) from
    /// `resolveWorktreeCreationLaunchTemplate` and this goes red —
    /// `result?.id` no longer equals `cco.id` (it becomes an ad-hoc
    /// template named/commanded "cco" with a DIFFERENT id, `AgentTemplate
    /// .shell.id`, not `cco.id`).
    @Test func launchTemplateResolvesAnUnterminatedTemplateNameByExactMatch() {
        let cco = AgentTemplate(id: UUID(), name: "cco", kind: .custom, command: "cco")
        let result = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: ["cco"],
            templates: [cco]
        )
        #expect(result?.id == cco.id, "must resolve the REAL project template by name, not synthesize an ad-hoc one")
    }

    /// A genuine shell command with no matching template name still
    /// synthesizes an ad-hoc template — finding 3's fix must not swallow
    /// the deliberate ad-hoc path.
    @Test func launchTemplateFallsBackToAdHocWhenNoTemplateNameMatches() {
        let result = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: ["npm", "run", "dev"],
            templates: []
        )
        #expect(result?.command == "npm")
        #expect(result?.agent?.additionalFlags == ["run", "dev"])
    }

    /// Nothing typed at all resolves to `nil` across all three tiers.
    @Test func launchTemplateIsNilWhenNothingIsTyped() {
        let result = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: [],
            templates: []
        )
        #expect(result == nil)
    }

    /// Round-3 finding 2: an unscoped `store.templates` superset lets a
    /// project-B-scoped "cco" template hijack a project-A composer's ad-hoc
    /// `cco -n "thread name"` invocation and silently drop the flag —
    /// `SessionComposerPalette.worktreeCreationLaunchTemplate` must pass the
    /// PROJECT-SCOPED list (`SessionTemplateResolver.templates(for:store:)`,
    /// matching every sibling call site) not the raw `store.templates`
    /// superset. `WorkspaceStore.templates(for:)`'s access control keeps
    /// this from reaching `SessionComposerPalette`'s private call site
    /// directly (Swift's `private` is file-scoped, no `@testable` override),
    /// so this exercises the two real production symbols the fix touches —
    /// `WorkspaceStore.templates`/`addTemplate` and
    /// `resolveWorktreeCreationLaunchTemplate` — with the exact unscoped-vs-
    /// scoped lists the call site chooses between.
    @Test func unscopedTemplatesLeakACrossProjectCcoThatSwallowsTheDashNFlag() {
        let projectA = Project(name: "project-a", rootPath: "/tmp/project-a")
        let projectB = Project(name: "project-b", rootPath: "/tmp/project-b")
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])

        let crossProjectCco = workspaceStore.addTemplate(
            AgentTemplate(name: "cco", kind: .custom, command: "some-other-binary", isGlobal: false, projectId: projectB.id)
        )

        // The bug: feeding the RAW, unscoped superset (what `store.templates`
        // was before the fix) into the resolver lets project B's "cco"
        // hijack project A's remainder and swallow `-n "thread name"`.
        let unscopedResult = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: ["cco", "-n", "thread name"],
            templates: workspaceStore.templates
        )
        #expect(unscopedResult?.id == crossProjectCco.id, "sanity: the unscoped superset really does let the wrong project's template hijack the match")

        // The fix: scoping to project A first (mirroring every other call
        // site's `SessionTemplateResolver.templates(for:store:)`) excludes
        // project B's "cco" entirely, so the ad-hoc path preserves the flag.
        let scopedResult = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: ["cco", "-n", "thread name"],
            templates: SessionTemplateResolver.templates(for: projectA, store: workspaceStore)
        )
        #expect(scopedResult?.id != crossProjectCco.id, "project A's launch must never resolve to project B's template")
        #expect(scopedResult?.command == "cco")
        #expect(scopedResult?.agent?.additionalFlags == ["-n", "thread name"], "the composer must never claim -n — it's cco's own flag")
    }

    /// Sean's 95% real-usage idiom (`ghostties feat-x cco -n "thread name"`):
    /// a flagged, quoted `cco` invocation with no matching template must
    /// fall through to the ad-hoc path with the flag and quoted argument
    /// intact, not get swallowed into a bare template match that discards
    /// `-n "thread name"` (the composer must never claim `-n` — it's `cco`'s
    /// own flag).
    @Test func launchTemplateFallsBackToAdHocPreservingFlagsForCcoIdiom() {
        let result = SessionComposerCommandParser.resolveWorktreeCreationLaunchTemplate(
            resolvedTemplateId: nil,
            remainderTokens: ["cco", "-n", "thread name"],
            templates: []
        )
        #expect(result?.command == "cco")
        #expect(result?.agent?.additionalFlags == ["-n", "thread name"])
    }

    /// Round-4 review, item 3: `SessionComposerPalette.worktreeCreationLaunchTemplate`
    /// used to be a private computed property with no testable seam — the
    /// prior review's "no testable seam" claim was wrong; the same pattern
    /// (`typedBranchResolution`/`resolveTypedBranch`) already had one in
    /// this same file. This exercises the extracted `internal static func`
    /// directly against a REAL project + store, proving the scoping the
    /// round-3 fix introduced: a template belonging to a DIFFERENT project
    /// must never be reachable. Mirrors
    /// `unscopedTemplatesLeakACrossProjectCcoThatSwallowsTheDashNFlag`'s
    /// setup above, but through the actual `SessionComposerPalette` seam
    /// rather than the pure resolver alone.
    ///
    /// Mutation: swap the static func's `templates:` argument back to the
    /// unscoped `store.templates` superset (the pre-round-3 bug) and this
    /// goes red — `result?.id` resolves to project B's "cco".
    ///
    /// Finding 1 (review round 5): the original version of this test only
    /// asserted the negative half of scoping (`id != crossProjectCco.id`)
    /// against `WorkspaceStore(testingProjects:testingSessions:)`'s SEEDED
    /// global templates (Shell / Claude Code / Codex / Orchestrator /
    /// Browser — all `isGlobal: true`, none named "cco"). Against that
    /// fixture, project A's correctly-scoped list and an EMPTY list are
    /// behaviorally identical for the token "cco": both fall through to the
    /// ad-hoc path, both produce `command == "cco"`, both preserve the
    /// flags, and neither can equal `crossProjectCco.id`. Mutating
    /// production to `templates: []` (dropping the project argument
    /// entirely) passed every assertion here. A project-A-scoped "cco"
    /// template closes that gap: now the correct list must resolve to IT,
    /// not fall through — discriminating "scoped correctly" from "scoped to
    /// nothing" and from "scoped to everything" (project B's "cco" would win
    /// `first(where:)` on insertion order if the raw superset were passed).
    @Test func staticWorktreeCreationLaunchTemplateNeverResolvesAnotherProjectsTemplate() {
        let projectA = Project(name: "project-a", rootPath: "/tmp/project-a")
        let projectB = Project(name: "project-b", rootPath: "/tmp/project-b")
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])

        // Cross-project template inserted FIRST so an unscoped `store.templates`
        // superset's `first(where:)` would land on IT before project A's own
        // "cco" — insertion order alone must not be what makes this test
        // pass; only correct scoping can. Named "CCO" (not "cco") so
        // `WorkspaceStore.addTemplate`'s exact-string dedupe (`uniqueName`,
        // case-SENSITIVE) doesn't rename it out from under
        // `matchesTemplate`'s case-INSENSITIVE lookup — both names must
        // still match the typed token "cco" identically, just not collide
        // in the store's own bookkeeping.
        let crossProjectCco = workspaceStore.addTemplate(
            AgentTemplate(name: "CCO", kind: .custom, command: "some-other-binary", isGlobal: false, projectId: projectB.id)
        )
        let projectACco = workspaceStore.addTemplate(
            AgentTemplate(name: "cco", kind: .custom, command: "cco", isGlobal: false, projectId: projectA.id)
        )

        let parse = SessionComposerCommandParser.ParseResult(
            projectId: projectA.id,
            remainderTokens: ["cco", "-n", "thread name"]
        )

        let result = SessionComposerPalette.worktreeCreationLaunchTemplate(
            project: projectA,
            store: workspaceStore,
            parse: parse
        )

        #expect(result?.id == projectACco.id, "project A's own \"cco\" template must resolve, not fall through to the ad-hoc path")
        #expect(result?.id != crossProjectCco.id, "project A's launch must never resolve to project B's template")

        // Pins `resolvedTemplateId` through the same seam: a hardcoded `nil`
        // in `worktreeCreationLaunchTemplate` would stay green against the
        // first `parse` above (whose `resolvedTemplateId` really is `nil`),
        // so a second parse carrying a real id proves the argument is wired
        // through, not ignored.
        let terminatedParse = SessionComposerCommandParser.ParseResult(
            projectId: projectA.id,
            remainderTokens: [],
            resolvedTemplateId: projectACco.id
        )
        let terminatedResult = SessionComposerPalette.worktreeCreationLaunchTemplate(
            project: projectA,
            store: workspaceStore,
            parse: terminatedParse
        )
        #expect(terminatedResult?.id == projectACco.id, "a resolvedTemplateId in the scoped list must resolve directly, proving the argument reaches the resolver")
    }

    // MARK: - 8. cascadeProjectChange must invalidate an in-flight creation (finding 2)

    /// THE mutant-catching test for finding 2: `cascadeProjectChange`
    /// (`Store.swift`, triggered by `selectedProjectId`'s `didSet` on a
    /// genuine value change) used to bump ONLY `worktreeRefreshToken`, not
    /// `worktreeCreationToken` — blocker 4's guards stayed valid across a
    /// project switch mid-creation, so a stale creation's success handler
    /// still ran against the NEW project's now-current composer. Delete
    /// this fix's `worktreeCreationToken += 1` line from
    /// `cascadeProjectChange` and this goes red.
    ///
    /// Same synchronous-race guarantee as test 5 above: `selectedProjectId`'s
    /// write happens right after `createWorktree` returns, no `await`
    /// between them, so the Task cannot have started before the cascade
    /// runs — same 8s settle budget for the same reason (see that test's
    /// doc comment for why a shorter wait produced a false negative here
    /// during this file's own review).
    @Test func projectSwitchMidCreationInvalidatesTheStaleCreation() async {
        let repoA = Self.makeThrowawayRepo()
        let repoB = Self.makeThrowawayRepo()
        defer {
            Self.cleanup(repoA)
            Self.cleanup(repoB)
        }

        let projectA = Project(name: "project-a", rootPath: repoA)
        let projectB = Project(name: "project-b", rootPath: repoB)
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])
        let store = SessionComposerStore(isolatedForTesting: ())
        store.open(projectBinding: .prefilled(projectA), workspaceStore: workspaceStore)

        let branchName = "feat-project-switch-mid-creation"
        let expectedPath = (repoA as NSString).appendingPathComponent(".claude/worktrees/\(branchName)")
        var successCount = 0
        store.createWorktree(named: branchName, in: projectA) { _ in successCount += 1 }
        // A project switch, not `cancel()` — this is finding 2's EXACT
        // scenario, distinct from test 5's `cancel()` path.
        store.selectedProjectId = projectB.id

        await Self.waitUntil(timeout: Self.createWorktreeCompletionTimeout) {
            FileManager.default.fileExists(atPath: expectedPath)
        }
        try? await Task.sleep(for: .seconds(Self.refreshWorktreesSetupTimeout))

        #expect(successCount == 0, "a creation superseded by a project switch must never fire its onSuccess into the new project's context")
        #expect(store.selectedWorktreePath == nil, "the project switch's reset must not be silently overwritten by the stale creation's own success handler")
    }
}
