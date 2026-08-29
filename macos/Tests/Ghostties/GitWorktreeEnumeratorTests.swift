import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Coverage for `GitWorktreeEnumerator.parsePorcelain` (composer breadcrumb
/// spec, Slice B — B1). Pure-function tests only: `Process`-backed
/// `.list(repoPath:)` is exercised manually against the real repo (see task
/// report), not here, since a unit test shelling out to `git` would be flaky
/// under CI/sandbox conditions.
struct GitWorktreeEnumeratorTests {

    /// Hand-written `git worktree list --porcelain` fixture with one of
    /// each stanza kind this parser must discriminate: two normal
    /// (non-bare, non-detached) worktrees, one locked, one detached, one
    /// bare, and one prunable.
    private static let fixture = """
    worktree /repo/main
    HEAD abcdef0123456789abcdef0123456789abcdef01
    branch refs/heads/main

    worktree /repo/.worktrees/feature-x
    HEAD 1111111111111111111111111111111111111111
    branch refs/heads/feature-x
    locked custom lock reason

    worktree /repo/.worktrees/detached-preview
    HEAD 2222222222222222222222222222222222222222
    detached

    worktree /repo/.bare
    bare

    worktree /repo/.worktrees/stale-branch
    HEAD 3333333333333333333333333333333333333333
    branch refs/heads/stale-branch
    prunable gitdir file points to non-existent location

    """

    // MARK: - Core discrimination

    @Test func parsePorcelainKeepsNormalAndLockedWorktrees() {
        let result = GitWorktreeEnumerator.parsePorcelain(Self.fixture)
        let paths = Set(result.map(\.path))

        #expect(paths.contains("/repo/main"))
        #expect(paths.contains("/repo/.worktrees/feature-x"))
    }

    @Test func parsePorcelainDropsBareDetachedAndPrunableStanzas() {
        let result = GitWorktreeEnumerator.parsePorcelain(Self.fixture)
        let paths = Set(result.map(\.path))

        #expect(!paths.contains("/repo/.bare"))
        #expect(!paths.contains("/repo/.worktrees/detached-preview"))
        #expect(!paths.contains("/repo/.worktrees/stale-branch"))
        #expect(result.count == 2)
    }

    @Test func parsePorcelainMarksLockedStanzaAsLocked() {
        let result = GitWorktreeEnumerator.parsePorcelain(Self.fixture)
        let feature = result.first { $0.path == "/repo/.worktrees/feature-x" }

        #expect(feature?.isLocked == true)
        #expect(feature?.branch == "feature-x")
    }

    @Test func parsePorcelainLeavesUnlockedNormalWorktreeUnlocked() {
        let result = GitWorktreeEnumerator.parsePorcelain(Self.fixture)
        let main = result.first { $0.path == "/repo/main" }

        #expect(main?.isLocked == false)
        #expect(main?.branch == "main")
    }

    @Test func parsePorcelainReturnsEmptyForEmptyInput() {
        let result = GitWorktreeEnumerator.parsePorcelain("")
        #expect(result.isEmpty)
    }

    // MARK: - Real-world `list(repoPath:)` behavior

    @Test func listOnNonGitPathReturnsEmptyWithoutThrowing() {
        let result = GitWorktreeEnumerator.list(repoPath: "/tmp/definitely-not-a-git-repo-\(UUID().uuidString)")
        #expect(result.isEmpty)
    }
}
