import Foundation
import Testing
@testable import Ghostty

/// Coverage for `GitWorktreeEnumerator.branchExists`/`add(branch:directory:repoPath:)`
/// (composer breadcrumb spec, Slice B — B4) and `SessionComposerStore.race(_:timeoutSeconds:)`.
///
/// Unlike `GitWorktreeEnumeratorTests`'s doc comment (which avoids
/// `Process`-backed calls as flaky under CI/sandbox conditions), these DO
/// shell out to real `git` — against a throwaway repo created fresh under
/// `NSTemporaryDirectory()` per test and torn down in `deinit`, never the
/// Ghostties repo itself. This is what caught a real bug: git's own stderr
/// for `worktree add` failures prints a `Preparing worktree (...)` progress
/// line BEFORE the `fatal: ...` line, so a naive "first line of stderr"
/// implementation (the brief's original wording) would have surfaced the
/// progress line, never the actual reason, for every single failure.
struct GitWorktreeCreationTests {

    /// Creates a fresh throwaway repo with one commit under
    /// `NSTemporaryDirectory()`, cleaned up by the caller.
    private static func makeThrowawayRepo() -> String {
        // `NSTemporaryDirectory()` is under `/var`, which is a symlink to
        // `/private/var` — `git worktree list --porcelain` reports the
        // resolved (`/private/var/...`) path, so building `directory`
        // strings from the UNresolved one would make a path comparison
        // fail for a reason that has nothing to do with the production
        // code under test. `URL.resolvingSymlinksInPath()` did NOT resolve
        // this inside the xctest host process (see `realPath(_:)`'s doc
        // comment) — POSIX `realpath(3)` does.
        let unresolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-b4-test-\(UUID().uuidString)")
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

        run(["git", "-C", path, "init", "-q"])
        run(["git", "-C", path, "-c", "user.email=test@ghostties.test", "-c", "user.name=Ghostties Test",
             "commit", "-q", "--allow-empty", "-m", "init"])
        return path
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// POSIX `realpath(3)` canonicalization — `URL.resolvingSymlinksInPath()`
    /// did NOT resolve `/var` -> `/private/var` inside the xctest host
    /// process in this environment (unlike a plain CLI process), so
    /// comparing a path built from the unresolved repo string against
    /// `GitWorktreeEnumerator.list`'s output (which always reflects what
    /// `git` itself reports, canonicalized) needs the genuine POSIX call,
    /// not the URL API's best-effort version. Requires the path to exist.
    private static func realPath(_ path: String) -> String {
        guard let cPath = realpath(path, nil) else { return path }
        defer { free(cPath) }
        return String(cString: cPath)
    }

    // MARK: - branchExists

    @Test func branchExistsIsTrueForARealLocalBranch() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repo, "branch", "feat/foo"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        #expect(GitWorktreeEnumerator.branchExists("feat/foo", repoPath: repo) == true)
    }

    @Test func branchExistsIsFalseForANameThatIsNotABranch() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        #expect(GitWorktreeEnumerator.branchExists("nope-not-a-branch", repoPath: repo) == false)
    }

    // MARK: - add: the slug-vs-branch-name distinction (criterion 3)

    /// A branch named `feat/foo` must produce directory slug `feat-foo`
    /// while the branch itself stays `feat/foo` — this is the entire reason
    /// `add` is told the branch name explicitly rather than letting git
    /// infer it from the destination's basename.
    @Test func addForExistingBranchWithSlashUsesExplicitBranchNotDirectoryBasename() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repo, "branch", "feat/foo"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let directory = (repo as NSString).appendingPathComponent(".claude/worktrees/feat-foo")
        let result = GitWorktreeEnumerator.add(branch: "feat/foo", directory: directory, repoPath: repo)

        switch result {
        case .success(let path):
            #expect(path == directory)
        case .failure(let error):
            Issue.record("expected success, got failure: \(error.message)")
        }

        // `repo` is already canonicalized (`makeThrowawayRepo`'s `realPath`
        // call), so `directory` built from it is already comparable to
        // `list`'s output directly — no second resolve needed.
        let worktrees = GitWorktreeEnumerator.list(repoPath: repo)
        let created = worktrees.first { $0.path == directory }
        #expect(created?.branch == "feat/foo")
    }

    @Test func addForNewBranchNameCreatesTheBranch() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        #expect(GitWorktreeEnumerator.branchExists("brand-new", repoPath: repo) == false)

        let directory = (repo as NSString).appendingPathComponent(".claude/worktrees/brand-new")
        let result = GitWorktreeEnumerator.add(branch: "brand-new", directory: directory, repoPath: repo)

        switch result {
        case .success(let path):
            #expect(path == directory)
        case .failure(let error):
            Issue.record("expected success, got failure: \(error.message)")
        }

        #expect(GitWorktreeEnumerator.branchExists("brand-new", repoPath: repo) == true)
    }

    // MARK: - The four failure modes (acceptance criterion 1)

    @Test func addFailsWithGitsRealMessageWhenBranchAlreadyCheckedOutElsewhere() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let branchTask = Process()
        branchTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        branchTask.arguments = ["git", "-C", repo, "branch", "already-checked-out"]
        branchTask.standardOutput = FileHandle.nullDevice
        branchTask.standardError = FileHandle.nullDevice
        try? branchTask.run()
        branchTask.waitUntilExit()

        let firstDir = (repo as NSString).appendingPathComponent(".claude/worktrees/already-checked-out")
        let first = GitWorktreeEnumerator.add(branch: "already-checked-out", directory: firstDir, repoPath: repo)
        guard case .success = first else {
            Issue.record("setup failed: first worktree add did not succeed")
            return
        }

        let secondDir = (repo as NSString).appendingPathComponent(".claude/worktrees/dup")
        let second = GitWorktreeEnumerator.add(branch: "already-checked-out", directory: secondDir, repoPath: repo)

        switch second {
        case .success:
            Issue.record("expected failure: branch is already checked out elsewhere")
        case .failure(let error):
            #expect(error.message.hasPrefix("fatal:"))
            #expect(error.message.contains("already used by worktree"))
        }
    }

    @Test func addFailsWithGitsRealMessageWhenDestinationExistsAndIsNonEmpty() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let branchTask = Process()
        branchTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        branchTask.arguments = ["git", "-C", repo, "branch", "mode2branch"]
        branchTask.standardOutput = FileHandle.nullDevice
        branchTask.standardError = FileHandle.nullDevice
        try? branchTask.run()
        branchTask.waitUntilExit()

        let directory = (repo as NSString).appendingPathComponent(".claude/worktrees/nonempty")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: (directory as NSString).appendingPathComponent("file.txt"), contents: nil)

        let result = GitWorktreeEnumerator.add(branch: "mode2branch", directory: directory, repoPath: repo)

        switch result {
        case .success:
            Issue.record("expected failure: destination exists and is non-empty")
        case .failure(let error):
            #expect(error.message.hasPrefix("fatal:"))
            #expect(error.message.contains("already exists"))
        }
    }

    @Test func addFailsWithGitsRealMessageForAnInvalidRefName() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let directory = (repo as NSString).appendingPathComponent(".claude/worktrees/badref")
        let result = GitWorktreeEnumerator.add(branch: "bad ref name", directory: directory, repoPath: repo)

        switch result {
        case .success:
            Issue.record("expected failure: \"bad ref name\" is not a valid branch name")
        case .failure(let error):
            #expect(error.message.hasPrefix("fatal:"))
            #expect(error.message.contains("not a valid branch name"))
        }
    }

    @Test func addFailsWithGitsRealMessageWhenDestinationParentIsUnwritable() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let branchTask = Process()
        branchTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        branchTask.arguments = ["git", "-C", repo, "branch", "mode4branch"]
        branchTask.standardOutput = FileHandle.nullDevice
        branchTask.standardError = FileHandle.nullDevice
        try? branchTask.run()
        branchTask.waitUntilExit()

        let lockedDir = (repo as NSString).appendingPathComponent(".claude/worktrees/lockeddir")
        try? FileManager.default.createDirectory(atPath: lockedDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir) }

        let directory = (lockedDir as NSString).appendingPathComponent("sub")
        let result = GitWorktreeEnumerator.add(branch: "mode4branch", directory: directory, repoPath: repo)

        switch result {
        case .success:
            Issue.record("expected failure: destination parent is not writable")
        case .failure(let error):
            #expect(error.message.hasPrefix("fatal:"))
            #expect(error.message.lowercased().contains("permission denied"))
        }
    }

    // MARK: - firstMeaningfulLine (the bug this file exists to prove)

    @Test func firstMeaningfulLinePicksTheFatalLineNotTheProgressLine() {
        let stderrText = """
        Preparing worktree (new branch 'bad ref name')
        fatal: 'bad ref name' is not a valid branch name
        hint: See 'git help check-ref-format'
        """
        let message = GitWorktreeEnumerator.firstMeaningfulLine(ofStderr: stderrText)
        #expect(message == "fatal: 'bad ref name' is not a valid branch name")
        #expect(!message.hasPrefix("Preparing worktree"))
    }

    @Test func firstMeaningfulLineFallsBackToFirstLineWhenNoFatalLinePresent() {
        let message = GitWorktreeEnumerator.firstMeaningfulLine(ofStderr: "something went wrong\nmore detail\n")
        #expect(message == "something went wrong")
    }

    // MARK: - SessionComposerStore.race timeout (acceptance criterion 4)

    /// Proves the timeout race actually returns at the deadline rather than
    /// blocking on the loser — a task that NEVER completes (an infinite
    /// sleep) must still make `race` return `.timedOut` promptly. This is
    /// the mutant-catching half: an implementation that awaited
    /// `task.value` directly (no independent race) would hang this test
    /// instead of failing it fast.
    @Test func raceReturnsTimedOutWhenTheUnderlyingTaskNeverCompletes() async {
        let neverFinishes: Task<Result<String, GitWorktreeEnumerator.GitWorktreeCreationError>, Never> = Task {
            try? await Task.sleep(for: .seconds(3600))
            return .success("unreachable")
        }
        defer { neverFinishes.cancel() }

        let start = Date()
        let outcome = await SessionComposerStore.race(neverFinishes, timeoutSeconds: 0.2)
        let elapsed = Date().timeIntervalSince(start)

        guard case .timedOut = outcome else {
            Issue.record("expected .timedOut, got \(outcome)")
            return
        }
        #expect(elapsed < 2.0)
    }

    // MARK: - canonicalPath / mainWorktreePath / isInsideWorkTree (should-fix 10)
    //
    // Neither had any coverage before this pass — both are called from
    // `SessionComposerStore.refreshWorktrees`'s detached task and
    // `createWorktree`'s, but nothing in this file (which otherwise covers
    // every OTHER `GitWorktreeEnumerator` entry point against a real repo)
    // exercised them.

    @Test func canonicalPathResolvesASymlinkedDirectoryToItsRealPath() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let symlinkPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-b4-symlink-\(UUID().uuidString)")
        try? FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: repo)
        defer { try? FileManager.default.removeItem(atPath: symlinkPath) }

        #expect(GitWorktreeEnumerator.canonicalPath(symlinkPath) == repo)
    }

    @Test func canonicalPathReturnsInputUnchangedForANonexistentPath() {
        let missing = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-does-not-exist-\(UUID().uuidString)")
        #expect(GitWorktreeEnumerator.canonicalPath(missing) == missing)
    }

    @Test func mainWorktreePathResolvesToTheRepoRootFromTheMainCheckoutItself() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        #expect(GitWorktreeEnumerator.mainWorktreePath(repoPath: repo) == repo)
    }

    /// Should-fix 13's core claim: resolving the main worktree from a
    /// LINKED worktree (not the main checkout) must still return the MAIN
    /// worktree's path, not the linked one — this is the entire reason
    /// `createWorktree` calls this instead of assuming `list(repoPath:)`'s
    /// first element (blocker 17).
    @Test func mainWorktreePathResolvesToTheRepoRootFromALinkedWorktreeToo() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        let branchTask = Process()
        branchTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        branchTask.arguments = ["git", "-C", repo, "branch", "linked-branch"]
        branchTask.standardOutput = FileHandle.nullDevice
        branchTask.standardError = FileHandle.nullDevice
        try? branchTask.run()
        branchTask.waitUntilExit()

        let linkedDir = (repo as NSString).appendingPathComponent(".claude/worktrees/linked-branch")
        let addResult = GitWorktreeEnumerator.add(branch: "linked-branch", directory: linkedDir, repoPath: repo)
        guard case .success = addResult else {
            Issue.record("setup failed: could not create the linked worktree")
            return
        }

        // Resolved FROM the linked worktree's own path — must still report
        // the MAIN repo root, not `linkedDir` itself.
        #expect(GitWorktreeEnumerator.mainWorktreePath(repoPath: linkedDir) == repo)
    }

    @Test func mainWorktreePathReturnsNilForANonRepoPath() {
        let result = GitWorktreeEnumerator.mainWorktreePath(repoPath: "/tmp/definitely-not-a-git-repo-\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test func isInsideWorkTreeIsTrueForAnOrdinaryRepo() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        #expect(GitWorktreeEnumerator.isInsideWorkTree(repoPath: repo) == true)
    }

    /// The should-fix 7 case this function exists to fix: `list(repoPath:)`
    /// (via `parsePorcelain`) drops the `detached` stanza entirely, so a
    /// repo whose only worktree is at DETACHED HEAD reports an EMPTY
    /// `list(repoPath:)` result — a perfectly real repo that the old
    /// `!rawList.isEmpty` derivation would have misread as "not a repo".
    /// `isInsideWorkTree` must say `true` regardless.
    @Test func isInsideWorkTreeIsTrueEvenAtDetachedHead() {
        let repo = Self.makeThrowawayRepo()
        defer { Self.cleanup(repo) }

        // Detaches HEAD WITHOUT `git checkout` (hard constraint: never run
        // `git checkout`, ever) — `rev-parse HEAD` reads the current
        // commit's sha, then `update-ref --no-deref HEAD <sha>` rewrites
        // `HEAD` as a direct sha reference instead of a symbolic ref to a
        // branch, which is exactly what a detached HEAD state IS.
        let shaTask = Process()
        shaTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        shaTask.arguments = ["git", "-C", repo, "rev-parse", "HEAD"]
        let shaPipe = Pipe()
        shaTask.standardOutput = shaPipe
        shaTask.standardError = FileHandle.nullDevice
        try? shaTask.run()
        let shaData = shaPipe.fileHandleForReading.readDataToEndOfFile()
        shaTask.waitUntilExit()
        let sha = String(data: shaData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let detachTask = Process()
        detachTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        detachTask.arguments = ["git", "-C", repo, "update-ref", "--no-deref", "HEAD", sha]
        detachTask.standardOutput = FileHandle.nullDevice
        detachTask.standardError = FileHandle.nullDevice
        try? detachTask.run()
        detachTask.waitUntilExit()

        // Confirms the premise: `list(repoPath:)` really does report empty
        // at detached HEAD in a single-worktree repo — this is the bug,
        // not an assumption.
        #expect(GitWorktreeEnumerator.list(repoPath: repo).isEmpty)
        #expect(GitWorktreeEnumerator.isInsideWorkTree(repoPath: repo) == true)
    }

    @Test func isInsideWorkTreeIsFalseForANonRepoPath() {
        let result = GitWorktreeEnumerator.isInsideWorkTree(repoPath: "/tmp/definitely-not-a-git-repo-\(UUID().uuidString)")
        #expect(result == false)
    }

    @Test func raceReturnsCompletedWhenTheUnderlyingTaskFinishesBeforeTheDeadline() async {
        let fastTask: Task<Result<String, GitWorktreeEnumerator.GitWorktreeCreationError>, Never> = Task {
            .success("/fast/path")
        }

        let outcome = await SessionComposerStore.race(fastTask, timeoutSeconds: 5)

        guard case .completed(.success(let path)) = outcome else {
            Issue.record("expected .completed(.success), got \(outcome)")
            return
        }
        #expect(path == "/fast/path")
    }
}

extension SessionComposerStore.WorktreeCreationOutcome: CustomStringConvertible {
    public var description: String {
        switch self {
        case .timedOut: return ".timedOut"
        case .completed(.success(let path)): return ".completed(.success(\(path)))"
        case .completed(.failure(let error)): return ".completed(.failure(\(error.message)))"
        }
    }
}
