import Foundation

/// A plain string-message error — `Result`'s `Failure` must conform to
/// `Error`, and a bare `String` doesn't. Shared by
/// `SessionComposerCommandParser.resolveCommitWorktreePathForCommit` and
/// `SessionComposerStore.resolveLaunchTemplate`, so both commit-time
/// validation seams return the same shape instead of each inventing one.
struct SessionComposerCommitError: Error, CustomStringConvertible, Equatable {
    let message: String
    var description: String { message }
}

/// Pure, testable command-grammar parsing for the session composer's
/// text-forward command entry (command grammar slice 1). Neither type here
/// touches SwiftUI or `@MainActor` state — see `SessionComposerRanking.swift`
/// for the same discipline applied to relevance ranking.
///
/// Target: typing `ghostties cco -n "test"` resolves project=ghostties,
/// tokenizes the remainder `cco -n test`, and offers a `Run "cco -n test"`
/// row that spawns a real session running that command — without ever
/// blanket-executing the remainder as a shell command (that would break
/// `ghostties orchestrator`, which must still reach the Orchestrator
/// template via the ordinary template-matching path).
enum SessionComposerCommandParser {

    /// The fixed identity of the composer's synthesized "Run" row.
    /// `ComposerOption.id` is injectable specifically to avoid UUID churn on
    /// every keystroke (see `SessionComposerPalette.ComposerOption`) — this
    /// row's underlying command changes on every keystroke by design, so a
    /// stable sentinel id (rather than deriving one from the command text)
    /// is what keeps hover/scroll state settled while the label updates.
    static let runRowId = UUID(uuidString: "89FA0000-0000-0000-0000-000000000001")!

    /// Result of tokenizing a composer query against the known project
    /// list. `projectId == nil` means "no command was recognized" — every
    /// caller must fall through to the existing whole-string filter,
    /// byte-identical, in that case.
    struct ParseResult: Equatable {
        let projectId: UUID?
        let remainderTokens: [String]
        /// Slice B (composer breadcrumb spec): the branch segment's raw
        /// token, present only when an explicit `>` introduced it (see
        /// the disambiguation rule on `parse(query:)`). `nil` for every
        /// slice-1 shape — explicit default keeps every existing
        /// construction site (including `.none` below) byte-identical.
        let branchToken: String?

        init(projectId: UUID?, remainderTokens: [String], branchToken: String? = nil) {
            self.projectId = projectId
            self.remainderTokens = remainderTokens
            self.branchToken = branchToken
        }

        /// The remainder tokens rejoined with single spaces, for display
        /// (`Run "<remainderText>"`) and for scoping the project's own
        /// template filter. Quote marks used only to keep a multi-word
        /// argument as one token are not reconstructed — display never
        /// needs to round-trip back into a query string.
        var remainderText: String {
            remainderTokens.joined(separator: " ")
        }

        static let none = ParseResult(projectId: nil, remainderTokens: [])
    }

    /// Straight `"` plus the curly quotes macOS's "Use smart quotes and
    /// dashes" substitutes it with by default (FB, round-2 review) — a
    /// pasted or typed `"` can arrive as U+201C/U+201D by the time it lands
    /// in `searchText`, and without this both `tokenize` and
    /// `splitOnFirstToken` would silently fail to recognize it as a quote
    /// boundary at all.
    private static let quoteCharacters: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]

    /// Whether `c` is a segment separator: always whitespace, plus `>`
    /// when `separatorsIncludeChevron` is set. Shared by `tokenize` and
    /// `splitOnFirstToken` so the two scans agree on where a boundary is —
    /// Slice B's typable `>` (composer breadcrumb spec, decision #3).
    private static func isSegmentSeparator(_ c: Character, separatorsIncludeChevron: Bool) -> Bool {
        c.isWhitespace || (separatorsIncludeChevron && c == ">")
    }

    /// Split `input` on whitespace (and, when `separatorsIncludeChevron` is
    /// true, `>` as well), honoring double quotes (straight or curly, see
    /// `quoteCharacters`) so a quoted argument (`"ghostties website"`)
    /// survives as a single token instead of splitting on its internal
    /// space. Quote characters themselves are stripped from the resulting
    /// tokens; so is a `>` acting as a separator. `separatorsIncludeChevron`
    /// defaults to `false` so every existing caller stays byte-identical —
    /// `>` is only ever a separator where a caller opts in.
    static func tokenize(_ input: String, separatorsIncludeChevron: Bool = false) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var inQuotes = false

        for char in input {
            if quoteCharacters.contains(char) {
                inQuotes.toggle()
                hasCurrent = true
                continue
            }
            if isSegmentSeparator(char, separatorsIncludeChevron: separatorsIncludeChevron), !inQuotes {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
                continue
            }
            current.append(char)
            hasCurrent = true
        }
        if hasCurrent {
            tokens.append(current)
        }
        return tokens
    }

    /// Parse `query` for the `<project> [> <branch>] <remainder...>` command
    /// grammar (Slice B, composer breadcrumb spec adds the optional branch
    /// segment on top of slice 1's `<project> <remainder...>`).
    ///
    /// Tokenizes ONLY when ALL of: there is a project segment AND something
    /// after it, that first segment exactly matches a project `name` or
    /// folder basename (case-insensitive), and `isLocked` is false. Any
    /// other case returns `.none` — the caller must treat that as "no
    /// command", not as an error, and keep filtering the raw query exactly
    /// as it did before this parser existed.
    ///
    /// Disambiguation rule (load-bearing): token 2 is a branch ONLY when an
    /// explicit `>` introduced it. A branch name and a template name are
    /// both bare words, and this parser never consults disk — so
    /// `ghostties cco` stays a template (unchanged from slice 1),
    /// `ghostties > main > cco` resolves branch `main` with remainder
    /// `cco`, and `ghostties main cco` is remainder `main cco`, not a
    /// branch, because no `>` ever appeared.
    static func parse(query: String, projects: [Project], isLocked: Bool) -> ParseResult {
        guard !isLocked else { return .none }

        // Segment-aware split for the project: `>` counts as a separator
        // here so `ghostties>main` and `ghostties > main` both find the
        // project boundary correctly.
        guard let projectSplit = splitOnFirstToken(query, separatorsIncludeChevron: true) else {
            return .none
        }
        guard !projectSplit.remainder.isEmpty else { return .none }

        guard let projectToken = tokenize(projectSplit.prefix, separatorsIncludeChevron: true).first else {
            return .none
        }
        guard let project = projects.first(where: { matches($0, token: projectToken) }) else {
            return .none
        }

        // A `>` was consumed as part of the separator between the project
        // token and the remainder if and only if the prefix (token +
        // separator run) contains one. NOTE (nit fix, Slice B review round
        // 1): this is NOT "the token itself can never contain a bare `>`" —
        // a QUOTED token can (`"a>b"` survives `tokenize` with the `>`
        // intact, since `>` inside quotes is never treated as a separator).
        // `projectToken` itself is never re-inspected for a literal `>`
        // here, so a quoted project name containing one doesn't change this
        // check's correctness — it only means the claim in the old wording
        // was wrong, not that the code was.
        let branchIntroducedByChevron = projectSplit.prefix.contains(">")

        guard branchIntroducedByChevron else {
            // No explicit `>` after the project: the whole remainder is
            // the command, tokenized on whitespace ONLY — so a `>` further
            // inside (a shell redirect argument) stays a literal argv word
            // instead of being treated as a segment separator.
            let remainderTokens = tokenize(projectSplit.remainder, separatorsIncludeChevron: false)
            return ParseResult(projectId: project.id, remainderTokens: remainderTokens)
        }

        // Segment-aware split again for the branch. Defensive only (nit fix,
        // Slice B review round 1): the guard above already returned `.none`
        // if `projectSplit.remainder` were empty, and `splitOnFirstToken`
        // always leaves `remainder` either empty or starting on a
        // non-separator character — so a non-empty `projectSplit.remainder`
        // can never fail to yield a first token here. This branch is
        // believed unreachable in practice; kept rather than force-unwrapped
        // so a future change to `splitOnFirstToken`'s invariant fails safe
        // instead of crashing.
        guard let branchSplit = splitOnFirstToken(projectSplit.remainder, separatorsIncludeChevron: true) else {
            return ParseResult(projectId: project.id, remainderTokens: [])
        }
        guard let branchToken = tokenize(branchSplit.prefix, separatorsIncludeChevron: true).first else {
            return ParseResult(projectId: project.id, remainderTokens: [])
        }

        // Final remainder: whitespace-only tokenize, so any further `>`
        // (e.g. a shell redirect) survives as a literal argv word.
        let remainderTokens = tokenize(branchSplit.remainder, separatorsIncludeChevron: false)
        return ParseResult(projectId: project.id, remainderTokens: remainderTokens, branchToken: branchToken)
    }

    /// Splits `rawQuery` into `(prefix, remainder)` on the boundary token 1
    /// occupies — quote-aware, mirrors `tokenize`'s scanning rules exactly so
    /// it agrees with what `tokenize` calls token 1. `prefix` is everything
    /// up to and including token 1 and the whitespace run separating it from
    /// the remainder; `remainder` is everything after that. BOTH are taken
    /// VERBATIM from `rawQuery` — no re-tokenizing, no rejoining. `nil` when
    /// `rawQuery` has no separable first token (blank/whitespace-only).
    ///
    /// Originally added so the (since-deleted) breadcrumb chip's editable
    /// text could be lossless (B1, composer breadcrumb spec review) — that
    /// binding used to reconstruct the remainder from `remainderText` —
    /// `remainderTokens.joined(separator: " ")` — which silently drops
    /// trailing whitespace and un-quotes a quoted argument, and SwiftUI
    /// wrote that lossy reconstruction back into the field on the very next
    /// update pass. The model A rebuild deleted the chip and its
    /// prefix-consuming field binding entirely (the field now holds
    /// `searchText` verbatim, no split needed for display), but this
    /// function stays: `stickyChipProjectId` below still calls it to find
    /// the project-token boundary, engine-side, unrelated to how the field
    /// renders.
    static func splitOnFirstToken(
        _ rawQuery: String,
        separatorsIncludeChevron: Bool = false
    ) -> (prefix: String, remainder: String)? {
        var index = rawQuery.startIndex
        var inQuotes = false
        var sawFirstToken = false

        // Skip leading separators before token 1 (mirrors `tokenize`, which
        // never emits a leading empty token).
        while index < rawQuery.endIndex,
              isSegmentSeparator(rawQuery[index], separatorsIncludeChevron: separatorsIncludeChevron) {
            index = rawQuery.index(after: index)
        }

        // Skip token 1 itself, honoring quotes exactly as `tokenize` does.
        while index < rawQuery.endIndex {
            let char = rawQuery[index]
            if quoteCharacters.contains(char) {
                inQuotes.toggle()
                sawFirstToken = true
                index = rawQuery.index(after: index)
                continue
            }
            if isSegmentSeparator(char, separatorsIncludeChevron: separatorsIncludeChevron), !inQuotes { break }
            sawFirstToken = true
            index = rawQuery.index(after: index)
        }
        guard sawFirstToken else { return nil }

        // Skip the separator run between token 1 and the remainder — NOT
        // included in `remainder`, but IS included in `prefix` (it's
        // re-prepended verbatim on every edit).
        while index < rawQuery.endIndex,
              isSegmentSeparator(rawQuery[index], separatorsIncludeChevron: separatorsIncludeChevron) {
            index = rawQuery.index(after: index)
        }

        return (
            prefix: String(rawQuery[rawQuery.startIndex..<index]),
            remainder: String(rawQuery[index...])
        )
    }

    /// Whether `rawQuery` is "mid-command with an empty remainder": a single
    /// token that exactly matches a project, followed by at least one real
    /// whitespace character and nothing else (`"ghostties "`,
    /// `"ghostties  "`). `parse(query:)` can't express this — it's fed the
    /// TRIMMED search text, and trimming is exactly what erases the
    /// trailing-whitespace signal checked here.
    ///
    /// Exists to fix D3 (composer breadcrumb spec review): without it, the
    /// chip is driven purely by `parse(query:)`, which requires ≥2 tokens —
    /// so backspacing a command's remainder down to nothing drops the token
    /// count to 1, `commandProject` goes `nil`, and the chip falls back
    /// silently to whatever `selectedProjectId` still reads (a DIFFERENT,
    /// previously-selected project). The typed project name is lost with
    /// it, and retyping doesn't recover it — the caret is at the end of
    /// whatever text remains, so `ghostties` + `c` becomes `ghossttiesc`,
    /// one token, no command. Keeping the chip resolved through the
    /// empty-remainder state (this function) means backspacing to nothing
    /// and retyping stays inside the same two-token shape the whole time.
    static func stickyChipProjectId(rawQuery: String, projects: [Project], isLocked: Bool) -> UUID? {
        guard !isLocked else { return nil }
        // Chevron-aware so `ghostties>` (Slice B's typable `>`) triggers
        // the sticky chip exactly like `ghostties ` already does — `>` is a
        // synonym for space here, not a different grammar.
        guard let split = splitOnFirstToken(rawQuery, separatorsIncludeChevron: true), split.remainder.isEmpty else {
            return nil
        }
        // `splitOnFirstToken("bru")` ALSO returns an empty remainder when
        // there was never a separator at all (end of string reached mid
        // token) — that's the ordinary single-token project-search case
        // (`testParseSingleTokenReturnsNilEvenWhenItMatchesAProjectName`)
        // and must NOT count as sticky. A genuine separator was consumed
        // only when `prefix` itself ends in a separator character.
        guard split.prefix.last?.isWhitespace == true || split.prefix.last == ">" else { return nil }
        // F2 fix (round-2 review): `trimmingCharacters(in: .whitespaces)`
        // only strips whitespace — `tokenize` also strips quote characters,
        // so a quoted multi-word name (`"ghostties web" `) produced a token
        // of `"\"ghostties web\""`, quotes still attached, which never
        // matched `matches(_:token:)` against the bare project name. That
        // silently defeated the sticky chip for every multi-word or quoted
        // project name — exactly the D3 dead end this function exists to
        // close. `tokenize(split.prefix).first` runs the SAME quote-aware
        // scan `splitOnFirstToken` above already mirrors, so it agrees with
        // what `tokenize` calls token 1 for both plain and quoted names.
        guard let token = tokenize(split.prefix, separatorsIncludeChevron: true).first else { return nil }
        guard let project = projects.first(where: { matches($0, token: token) }) else { return nil }
        return project.id
    }

    private static func matches(_ project: Project, token: String) -> Bool {
        if project.name.caseInsensitiveCompare(token) == .orderedSame { return true }
        let basename = (project.rootPath as NSString).lastPathComponent
        return basename.caseInsensitiveCompare(token) == .orderedSame
    }

    /// Synthesize the ad-hoc template for a resolved command's remainder.
    ///
    /// Reuses `AgentTemplate.shell.id` (never mints a fresh UUID) so
    /// `WorkspacePersistence.validate` doesn't delete the session on
    /// relaunch — relaunching an ad-hoc session relaunches plain Shell,
    /// an accepted degradation. `agent:` is set purely to buy the
    /// login-shell wrapper `SessionCoordinator.createSession` writes
    /// whenever `template.launchBanner != nil` (i.e. `agent != nil`) —
    /// `exec` inside that `#!/bin/zsh -l` wrapper resolves zsh functions
    /// like `cco`, which a bare `/bin/sh -c` spawn never would.
    ///
    /// The remainder's first token becomes `command` (the only
    /// single-quoted-whole carrier, `AgentTemplate.shellEscape`); every
    /// token after it becomes `agent.additionalFlags`, the only
    /// per-token-escaped carrier — splitting this way is what keeps
    /// `cco -n test` from collapsing into one unrunnable argv word.
    static func makeAdHocTemplate(remainderTokens: [String]) -> AgentTemplate? {
        guard let first = remainderTokens.first else { return nil }
        let rest = Array(remainderTokens.dropFirst())

        // Blocker fix: a quoted first remainder token (`ghostties "npm run
        // dev"`) survives `tokenize` as one token containing internal
        // whitespace. Putting that whole into `command` reintroduces the
        // `shellEscape` blocker verbatim — `buildCommand()` would quote it
        // as a single argv word (`'npm run dev'`), which the shell can't
        // resolve. Re-split the first token on whitespace: only its first
        // word becomes `command`; every word after it flows into
        // `additionalFlags` ahead of the rest of the remainder. This also
        // covers an unbalanced-quote remainder (`ghostties "` tokenizes to
        // `["ghostties", ""]`) — an empty or whitespace-only first token
        // splits to zero words, so `command` guards below and this
        // returns `nil` instead of committing a live `Run ""` row.
        let firstWords = first.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let command = firstWords.first else { return nil }
        let flags = Array(firstWords.dropFirst()) + rest

        return AgentTemplate(
            id: AgentTemplate.shell.id,
            name: command,
            kind: .custom,
            command: command,
            agent: AgentTemplate.AgentConfig(additionalFlags: flags)
        )
    }

    /// Resolves which project a commit should land in: a resolved command
    /// project (typed `<project> <remainder>`) takes precedence over
    /// whatever project is currently selected in the dropdown. Pure/testable
    /// extraction of the write-path polarity fixed by the "scopes list to
    /// project A, commits into project B" blocker — `SessionComposerPalette`
    /// itself has no testable seam for this (a SwiftUI `View` reading
    /// `@EnvironmentObject` state), so this is the seam.
    static func resolveCommitProjectId(commandProjectId: UUID?, selectedProjectId: UUID?) -> UUID? {
        commandProjectId ?? selectedProjectId
    }

    // `resolvedFieldSplit` used to live here — it computed the verbatim
    // `(prefix, remainder)` split the deleted breadcrumb chips' field
    // binding consumed into a hidden, non-editable prefix. Deleted with the
    // chips themselves (model A rebuild): the field now holds `searchText`
    // verbatim, with no split needed for display — see
    // `SessionComposerPalette.searchTextBinding`. Its test coverage
    // (`SessionComposerCommandParserTests`'s `resolvedFieldSplit` sections)
    // was deleted alongside it, since it tested a transform that no longer
    // exists.

    /// Resolves which worktree path a commit should launch into: mirrors
    /// `resolveCommitProjectId`'s precedence idiom exactly — a resolved
    /// TYPED branch (`> main > cco`) wins over whatever the branch chip's
    /// PICKER currently has selected. `nil` means "no override" — the
    /// caller falls through to `template.workingDirectory ?? project.rootPath`
    /// unchanged.
    ///
    /// Pure — this type never touches disk. The caller (the view) is
    /// responsible for resolving `typedWorktreePath` by looking up
    /// `ParseResult.branchToken` against the cached worktree list; this
    /// function only expresses the precedence, the same seam
    /// `resolveCommitProjectId` provides for the project segment.
    static func resolveCommitWorktreePath(typedWorktreePath: String?, selectedWorktreePath: String?) -> String? {
        typedWorktreePath ?? selectedWorktreePath
    }

    // MARK: - Typed branch resolution (Slice B review round 1, blocker 2)

    /// What a typed branch TOKEN (`commandParse.branchToken`) resolves to
    /// against the cached worktree list. `typedWorktreePath`'s old shape
    /// collapsed "nothing typed" and "typed but unresolvable" to the same
    /// `nil`, which let `resolveCommitWorktreePath` silently fall through to
    /// whatever the PICKER had selected before the user started typing — a
    /// typed branch that resolves to nothing must fail loudly instead
    /// (blocker 2). This type is what makes the three real cases
    /// distinguishable at the call site.
    enum TypedBranchResolution: Equatable {
        /// No branch segment was typed (`commandParse.branchToken == nil`) —
        /// defers entirely to the picker's own pick.
        case notTyped
        /// The token matched a cached worktree's branch.
        case resolved(path: String)
        /// The token matched the branch already checked out at the
        /// project's own root. `worktrees` never contains the project root
        /// (the store filters it out — see
        /// `SessionComposerStore.refreshWorktrees`'s doc comment), so this
        /// case can NEVER be reached via `.resolved` above — typing the
        /// default branch's own name is exactly the sub-case blocker 2
        /// calls out as otherwise unresolvable. Resolves to "no override",
        /// the same as the picker's own "Default" row.
        case isDefaultBranch
        /// The token matches neither a cached worktree nor the project's
        /// default branch. Decision (blocker 2, documented here since this
        /// is the one place that decision is made): an unresolvable typed
        /// branch must fail the commit with a visible error, never silently
        /// inherit the picker's last pick — inheriting is exactly the
        /// "session launches under project B's worktree with no error"
        /// class of bug this type exists to close.
        case unresolved(token: String)
        /// The worktree cache backing this resolution doesn't (yet) describe
        /// the project being resolved for — blocker 2 fix (Slice B review
        /// round 2). Either the initial `refreshWorktrees` hasn't landed yet
        /// (a fast typist can reach `commit(template:)` inside that ~2s
        /// window), or a typed `<project>` segment resolved a DIFFERENT
        /// project than whatever the composer's cache currently holds — the
        /// bug this closes: composer opens on project A (cache holds A's
        /// worktrees), typing `<project B> > <A's branch name> <remainder>`
        /// matched A's stale cache under B's name and launched a session in
        /// B with cwd silently pointed at one of A's worktrees. Distinct
        /// from `.unresolved` (should-fix 4): a typed branch that genuinely
        /// doesn't exist must fail with "no worktree found"; a typed branch
        /// this store simply hasn't checked FOR THIS PROJECT yet must fail
        /// with a message that says so, not a confident-sounding wrong
        /// answer.
        case pending
    }

    /// Resolves a typed branch token (if any) against the cached worktree
    /// list and the project's own root branch. Pure — no disk access; the
    /// caller passes in the already-fetched `worktrees`/
    /// `currentBranchAtProjectRoot` from `SessionComposerStore`.
    ///
    /// `cachedProjectId`/`resolvingForProjectId` (blocker 2 fix, Slice B
    /// review round 2): default to `nil` so every pre-existing call/test
    /// site (which never scoped this at all) stays byte-identical — `nil ==
    /// nil` is `true`, so passing neither argument behaves exactly as
    /// before. A caller that DOES pass both must have them agree, or this
    /// returns `.pending` rather than trusting `worktrees`/
    /// `currentBranchAtProjectRoot` against a project they were never
    /// fetched for.
    static func resolveTypedBranch(
        branchToken: String?,
        worktrees: [GitWorktreeEnumerator.Worktree],
        currentBranchAtProjectRoot: String?,
        cachedProjectId: UUID? = nil,
        resolvingForProjectId: UUID? = nil
    ) -> TypedBranchResolution {
        guard let token = branchToken else { return .notTyped }
        guard cachedProjectId == resolvingForProjectId else { return .pending }
        if let path = worktrees.first(where: { $0.branch == token })?.path {
            return .resolved(path: path)
        }
        if let rootBranch = currentBranchAtProjectRoot, rootBranch == token {
            return .isDefaultBranch
        }
        return .unresolved(token: token)
    }

    /// The COMMIT-time counterpart to `resolveCommitWorktreePath` above —
    /// used ONLY at the write path (`SessionComposerPalette.commit(template:)`),
    /// never for the "is this chip value already shown" comparison
    /// `resolveCommitWorktreePath` still serves unchanged. `.unresolved`
    /// returns `.failure` with a message meant for `writeError` directly;
    /// every other case resolves the same way `resolveCommitWorktreePath`
    /// already did.
    static func resolveCommitWorktreePathForCommit(
        typedBranch: TypedBranchResolution,
        selectedWorktreePath: String?
    ) -> Result<String?, SessionComposerCommitError> {
        switch typedBranch {
        case .notTyped:
            return .success(selectedWorktreePath)
        case .resolved(let path):
            return .success(path)
        case .isDefaultBranch:
            return .success(nil)
        case .unresolved(let token):
            return .failure(SessionComposerCommitError(message: "No worktree found for branch \"\(token)\". Pick one from the branch picker or clear the typed branch."))
        case .pending:
            return .failure(SessionComposerCommitError(message: "Still checking branches for this project — try again in a moment."))
        }
    }

    // MARK: - Resolution line (model A rebuild — replaces the breadcrumb
    // chips' label logic)

    /// What the resolution line's three segments show, computed from the
    /// same inputs the deleted chips read (`SessionComposerPalette`'s
    /// `currentProject`/`typedBranchResolution`/`currentBranchLabel`/
    /// `selectedOption`) — pure and testable, unlike those (private
    /// computed properties on a SwiftUI `View`, this repo's usual
    /// view-test-harness gap). `SessionComposerPalette.resolutionLine`
    /// calls this once and renders the result; it does not re-derive any of
    /// this logic inline.
    struct ResolutionLineSegments: Equatable {
        let projectLabel: String
        let isProjectClickable: Bool
        /// `nil` when the branch segment shouldn't render at all — a
        /// non-git project (mirrors the deleted branch chip's own
        /// "no chip, not a disabled one" rule).
        let branchLabel: String?
        /// Whether `branchLabel` should render in the error color — a
        /// typed branch that doesn't resolve to anything. Always `false`
        /// when `branchLabel == nil`.
        let branchIsError: Bool
        let templateLabel: String
    }

    /// Computes `ResolutionLineSegments` from the composer's current
    /// resolved state.
    ///
    /// - `projectName`: `currentProject?.name` — `nil` means no project
    ///   resolved/selected yet.
    /// - `isProjectLocked`: whether the composer's project binding is
    ///   `.locked` — the project segment renders non-clickable either way,
    ///   but the empty-state fallback text differs ("Project unavailable"
    ///   vs "Select project"), matching the deleted chip's own split.
    /// - `isBranchSegmentEligible`: `SessionComposerStore.isGitRepo` — governs
    ///   whether a branch segment renders at all.
    /// - `templateTitle`: the currently-selected result row's title
    ///   (`selectedOption?.title`), or `nil` if nothing is selected (an
    ///   empty results list).
    static func resolutionLineSegments(
        projectName: String?,
        isProjectLocked: Bool,
        isBranchSegmentEligible: Bool,
        isCreatingWorktree: Bool,
        typedBranchResolution: TypedBranchResolution,
        currentBranchLabel: String?,
        templateTitle: String?
    ) -> ResolutionLineSegments {
        let projectLabel = isProjectLocked
            ? (projectName ?? "Project unavailable")
            : (projectName ?? "Select project")

        var branchLabel: String?
        var branchIsError = false
        if isBranchSegmentEligible {
            if isCreatingWorktree {
                branchLabel = "Creating…"
            } else if case .unresolved(let token) = typedBranchResolution {
                branchLabel = "branch \"\(token)\" not found"
                branchIsError = true
            } else {
                branchLabel = currentBranchLabel ?? "Default"
            }
        }

        return ResolutionLineSegments(
            projectLabel: projectLabel,
            isProjectClickable: !isProjectLocked,
            branchLabel: branchLabel,
            branchIsError: branchIsError,
            templateLabel: templateTitle ?? "No match"
        )
    }
}
