import Foundation

/// Enumerates `git worktree list --porcelain` output for the branch chip's
/// worktree picker (composer breadcrumb spec, Slice B). Nothing here touches
/// UI — this is the cached data layer only; the picker itself is a later
/// step.
///
/// `nonisolated` because both entry points are meant to run off the main
/// actor (called from a `Task.detached` in `SessionComposerStore`), mirroring
/// `SessionDraftStore.currentGitBranch(atCwd:)`.
nonisolated enum GitWorktreeEnumerator {

    /// One `git worktree list --porcelain` stanza, filtered to the ones the
    /// branch chip can offer: real, non-bare, non-detached worktrees.
    struct Worktree: Equatable {
        let path: String
        let branch: String?
        let isLocked: Bool
    }

    /// Parses `git worktree list --porcelain` output into `Worktree` values.
    /// Pure — no `Process`, no I/O — this is the testable seam.
    ///
    /// Porcelain format is stanzas separated by a blank line, each starting
    /// with a `worktree <path>` line, e.g.:
    ///
    /// ```
    /// worktree /path/to/main
    /// HEAD abcdef0123456789
    /// branch refs/heads/main
    ///
    /// worktree /path/to/linked-worktree
    /// HEAD abcdef0123456789
    /// branch refs/heads/feature
    /// locked
    ///
    /// worktree /path/to/bare-repo
    /// bare
    /// ```
    ///
    /// `bare`, `detached`, and `prunable` stanzas are dropped entirely.
    /// `locked` stanzas are kept with `isLocked = true` (a locked worktree is
    /// still a valid pick, just one Sean has pinned against pruning).
    static func parsePorcelain(_ output: String) -> [Worktree] {
        var results: [Worktree] = []

        var currentPath: String?
        var currentBranch: String?
        var currentIsBare = false
        var currentIsDetached = false
        var currentIsPrunable = false
        var currentIsLocked = false

        func flush() {
            defer {
                currentPath = nil
                currentBranch = nil
                currentIsBare = false
                currentIsDetached = false
                currentIsPrunable = false
                currentIsLocked = false
            }
            guard let path = currentPath else { return }
            guard !currentIsBare, !currentIsDetached, !currentIsPrunable else { return }
            results.append(Worktree(path: path, branch: currentBranch, isLocked: currentIsLocked))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("worktree ") {
                // A new stanza started without a blank-line separator ahead
                // of it (shouldn't happen per the format, but flush
                // defensively so a malformed feed can't merge two stanzas).
                if currentPath != nil {
                    flush()
                }
                currentPath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                // Refs come through as `refs/heads/<name>` — strip the prefix
                // so callers get the plain branch name, matching
                // `SessionDraftStore.currentGitBranch(atCwd:)`'s output shape.
                currentBranch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "bare" {
                currentIsBare = true
            } else if line == "detached" {
                currentIsDetached = true
            } else if line.hasPrefix("prunable") {
                currentIsPrunable = true
            } else if line.hasPrefix("locked") {
                currentIsLocked = true
            }
            // Other keys (HEAD, etc.) are ignored — not needed by the chip.
        }
        flush()

        return results
    }

    /// Runs `git -C <repoPath> worktree list --porcelain` and parses the
    /// result. Never throws: a non-repo path, a deleted path, or any other
    /// git failure (exit 128) returns `[]`.
    ///
    /// Git resolves worktree enumeration from ANY worktree of a repo to the
    /// full set, so `repoPath` does not need to be the repo's primary
    /// checkout — a linked worktree works identically.
    static func list(repoPath: String) -> [Worktree] {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repoPath, "worktree", "list", "--porcelain"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        guard task.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parsePorcelain(output)
    }

    /// Local branches that have NO worktree checked out anywhere (including
    /// `repoPath`'s own primary checkout) — the branch chip picker's second
    /// group (composer breadcrumb spec, Slice B). Runs
    /// `git -C <repoPath> branch --format='%(refname:short)'`, then removes
    /// every branch already claimed by `list(repoPath:)`'s UNFILTERED
    /// result (the caller-side "minus the project's own root" filtering
    /// that `SessionComposerStore.worktrees` applies does NOT apply here —
    /// a branch checked out at the project's own root is still claimed).
    ///
    /// Same `Process` shape and `dispatchPrecondition` as `list(repoPath:)`;
    /// a non-repo path, a deleted path, or any other git failure (exit 128)
    /// returns `[]`, never throws.
    static func branchesWithoutWorktree(repoPath: String) -> [String] {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let claimed = Set(list(repoPath: repoPath).compactMap(\.branch))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repoPath, "branch", "--format=%(refname:short)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        guard task.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let allBranches = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return allBranches.filter { !claimed.contains($0) }
    }
}
