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

    // MARK: - Creation (Slice B, B4)

    /// Whether `name` is a real local branch in `repoPath` —
    /// `git show-ref --verify --quiet refs/heads/<name>`. Explicit rather
    /// than inferred from `branchesWithoutWorktree`/`list` output, because
    /// `add(branch:directory:repoPath:)` needs a definitive answer to pick
    /// between `worktree add <dir> <name>` (existing branch) and
    /// `worktree add -b <name> <dir>` (new branch) — trusting git's own
    /// basename DWIM instead would silently do the wrong thing for a slash
    /// name like `feat/foo`, which is the entire reason this check exists.
    /// Wraps a plain message so `add(branch:directory:repoPath:)` can return
    /// `Result<String, GitWorktreeCreationError>` — `String` itself doesn't
    /// conform to `Error`. `.message` is git's stderr first line, verbatim;
    /// nothing paraphrases it between here and `SessionComposerStore.writeError`.
    struct GitWorktreeCreationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func branchExists(_ name: String, repoPath: String) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "-C", repoPath, "show-ref", "--verify", "--quiet", "refs/heads/\(name)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0
    }

    /// Creates a worktree for `branch` at `directory`, resolving from
    /// `repoPath` (any worktree of the repo, per `list(repoPath:)`'s doc
    /// comment — a linked worktree works identically to the main one for
    /// this purpose, and a new branch is created from `-C repoPath`'s HEAD,
    /// same as any other `git` invocation scoped to that path).
    ///
    /// Explicitly branches on `branchExists`, never on git's own basename
    /// DWIM (`git worktree add <dir>` alone infers a branch name from
    /// `<dir>`'s basename, which is wrong the moment the caller's path
    /// slug differs from the branch name — e.g. `feat/foo` slugged to
    /// `feat-foo`):
    /// - branch exists  -> `git -C <repoPath> worktree add <directory> <branch>`
    /// - branch is new   -> `git -C <repoPath> worktree add -b <branch> <directory>`
    ///
    /// Never `git checkout` — `worktree add` is the only mutation this
    /// type is allowed to perform.
    ///
    /// On success, returns the created `directory`. On failure, returns
    /// git's own `fatal: ...` line verbatim (see
    /// `firstMeaningfulLine(ofStderr:)` for why that is NOT simply "the
    /// first line of stderr") — this is what surfaces into
    /// `SessionComposerStore.writeError` unmodified, so whatever git says
    /// (branch already checked out elsewhere, destination exists and is
    /// non-empty, invalid ref name, unwritable destination) reaches the
    /// user without a paraphrase in between.
    static func add(branch: String, directory: String, repoPath: String) -> Result<String, GitWorktreeCreationError> {
        dispatchPrecondition(condition: .notOnQueue(.main))

        let exists = branchExists(branch, repoPath: repoPath)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = exists
            ? ["git", "-C", repoPath, "worktree", "add", directory, branch]
            : ["git", "-C", repoPath, "worktree", "add", "-b", branch, directory]

        let stderrPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .failure(GitWorktreeCreationError(message: "Failed to launch git: \(error.localizedDescription)"))
        }

        guard task.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: data, encoding: .utf8) ?? ""
            return .failure(GitWorktreeCreationError(message: Self.firstMeaningfulLine(ofStderr: stderrText)))
        }

        return .success(directory)
    }

    /// `git worktree add`'s stderr is NOT "the message on line 1" — every
    /// failure mode observed against a real throwaway repo (branch already
    /// checked out elsewhere, non-empty destination, invalid ref name,
    /// unwritable destination) printed a `Preparing worktree (...)` progress
    /// line FIRST, with the actual `fatal: ...` line second. Taking the
    /// literal first line (the brief's original wording) would have
    /// surfaced "Preparing worktree (new branch 'bad ref name')" as
    /// `writeError` for every single failure, never the real reason —
    /// caught only by running the four failure modes against real git
    /// rather than trusting the spec's phrasing. This picks the first line
    /// starting with `fatal:` and falls back to the literal first line only
    /// if git's output ever omits one (a case not observed, but not worth
    /// returning nothing over).
    static func firstMeaningfulLine(ofStderr stderrText: String) -> String {
        let lines = stderrText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if let fatalLine = lines.first(where: { $0.hasPrefix("fatal:") }) {
            return fatalLine
        }
        return lines.first ?? "git worktree add failed with no output."
    }
}
