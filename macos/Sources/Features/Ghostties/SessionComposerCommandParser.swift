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

    /// The fixed identity of the composer's synthesized "Create worktree
    /// for <branch>" row — Sean's decision 1: a typed branch that matches a
    /// known branch with no worktree gets an offered row to create it,
    /// mirroring `runRowId`'s stable-sentinel reasoning above (the label
    /// changes on every keystroke; the id must not).
    static let createWorktreeRowId = UUID(uuidString: "89FA0000-0000-0000-0000-000000000002")!

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
        /// Round-3 review, Blocker 1: the template a chevron/space-terminated
        /// operator token resolved to (`Segment.Resolution.template`),
        /// carried through so callers can rank/launch it directly instead of
        /// re-deriving it from `remainderText` — which is EMPTY once an
        /// operator resolves to a template (the open run past it becomes a
        /// thread run, and `parse`'s own remainder-selection logic never
        /// reports thread text as the remainder; see the comment above
        /// `remainderRange` in `parse(query:...)`). Without this, a resolved
        /// operator's empty remainder unranks the template list entirely,
        /// letting Return launch whatever the ranking's tie-break (section
        /// order) happens to put first — not the template the user just
        /// named. `nil` for every slice-1/Slice-B shape and whenever no
        /// operator segment resolved to a real template — explicit default
        /// keeps every existing construction site byte-identical.
        let resolvedTemplateId: UUID?

        init(projectId: UUID?, remainderTokens: [String], branchToken: String? = nil, resolvedTemplateId: UUID? = nil) {
            self.projectId = projectId
            self.remainderTokens = remainderTokens
            self.branchToken = branchToken
            self.resolvedTemplateId = resolvedTemplateId
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

    // MARK: - Path grammar (greedy, terminated-token walk)
    //
    // Replaces the old two-fixed-position `<project> [> <branch>]
    // <remainder...>` grammar above. See
    // `docs/plans` composer path-grammar plan (2026-08-23) for the full
    // derivation; the load-bearing rules, restated here since they're easy
    // to get backwards:
    //
    // 1. Only a TERMINATED token (followed by whitespace or `>`) can ever
    //    resolve to a segment. The trailing, still-being-typed token is a
    //    search term — it filters, it never resolves. This is what keeps
    //    a single bare word (`"ghostties"`, `"bru"`) from ever claiming a
    //    project: there is no terminator yet, so nothing has finished.
    // 2. Matching walks terminated tokens left to right, trying each
    //    against the first STILL-UNFILLED type among project → branch →
    //    operator (template names), in that fixed order. First exact,
    //    case-insensitive match claims the token and removes that type — a
    //    filled type is never retried.
    // 3. The first terminated token that matches nothing ends matching for
    //    good. Everything from there on is free text: a thread name if an
    //    operator already resolved, otherwise an ad-hoc command (D13) —
    //    this is what keeps `ghostties npm run dev` producing ad-hoc
    //    `["npm","run","dev"]`, unchanged from slice 1 (PR #136).
    // 4. `>` closes whatever free-text run is currently open and advances
    //    to the next free-text position (operator → thread). Hit while
    //    still matching (no run open yet), it forces matching to stop and
    //    opens a run at the next position instead. Hit while a thread run
    //    is already open, it's swallowed as a literal character — thread
    //    is the last position, there's nothing further to advance to.

    /// The four segment positions the grammar can fill, in walk order.
    /// `operation` because `operator` is a Swift keyword — the grammar's
    /// word for it is still "operator" everywhere it's user-facing.
    enum SegmentKind: Int, Comparable, CaseIterable {
        case project = 0, branch = 1, operation = 2, thread = 3
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }

    /// A single resolved (settled) segment of a `PathParse`.
    struct Segment: Equatable {
        let kind: SegmentKind
        /// UTF-16 offsets into `PathParse.source` — never a `Range<String.Index>`:
        /// an index from a different string is undefined behavior, whereas a
        /// stale `NSRange` is merely out of bounds and guardable.
        let range: NSRange
        let resolved: Resolution

        enum Resolution: Equatable {
            case project(UUID)
            case branch(String)      // token only; worktree lookup stays in the view
            case template(UUID)      // operator matched a known template
            case adHoc                // operator is unmatched free text, closed by `>`
            case thread
            case unresolved
        }

        /// The ONLY way a caller obtains this segment's display string.
        ///
        /// `Range(range, in: source)` only fails (returning `""` here) when
        /// `range` doesn't land on a UTF-16 scalar boundary in `source` at
        /// all — a genuinely different string, or one shorter than the
        /// range implies. A STALE range that's still in-bounds for a
        /// DIFFERENT-but-similar `source` (e.g. one more keystroke) does
        /// NOT fail this guard — it silently returns whatever text happens
        /// to sit at those offsets now, which is wrong but not obviously
        /// so. Always call this with the exact `source` the range was
        /// produced against (`PathParse.source`, verbatim) — this matters
        /// more once D11 hands these same ranges to `NSTextStorage`, where
        /// the same silent-wrong-text failure mode applies.
        func text(in source: String) -> String {
            guard let r = Range(range, in: source) else { return "" }
            return String(source[r])
        }
    }

    /// The result of `parsePath` — a greedy walk of `rawQuery` against the
    /// four-segment grammar above. Every settled segment (project, branch,
    /// a template match, or an ad-hoc run explicitly closed by `>`) lands
    /// in `segments`. The trailing run that is STILL OPEN when the walk
    /// ends — still absorbing keystrokes, not yet closed by a `>` — is
    /// exposed separately via `remainderRange`/`activeKind` rather than
    /// added to `segments`, since it isn't a settled fact yet.
    struct PathParse: Equatable {
        /// The exact RAW string every `Segment.range` indexes — never trimmed.
        let source: String
        let segments: [Segment]
        /// The still-being-typed tail: not terminated, never resolved. `nil`
        /// once a free-text run has been opened (its content, terminated or
        /// not, belongs to the run instead — see rule 1) or when the query
        /// ends in a terminator or is empty.
        let trailingTermRange: NSRange?
        /// The type the trailing term (or the next keystroke) would be
        /// tried against — the first unfilled type, or `.operation`/
        /// `.thread` once matching has stopped.
        let activeKind: SegmentKind?
        /// The currently-open, not-yet-closed free-text run, if any.
        let remainderRange: NSRange?
        let projectId: UUID?
        /// Whether the currently-open run (`remainderRange`, if non-nil) is
        /// genuinely a THREAD run — set directly from `openRunKind` at the
        /// point the walk ends, never derived from `activeKind`. `activeKind`
        /// is a different, deliberately decoupled concept (what the
        /// completion/suggestion UI should offer while a token is still
        /// being typed — see `openedByFinalUnterminatedToken` in
        /// `parsePath`) and can report `.branch`/`.project` even while the
        /// open run underneath it is truly a thread run (e.g.
        /// `"ghostties orchestrator te"` with a real `orchestrator`
        /// template: the operator resolves via the template match, leaving
        /// `.branch` as the first unfilled type `activeKind` reports, while
        /// the run opened by the trailing `"te"` is genuinely `.thread`).
        /// Fix 2 (round-2 review): this field is what callers needing "is
        /// the open run a thread run" must read instead.
        let openRunIsThreadRun: Bool

        static let none = PathParse(source: "", segments: [], trailingTermRange: nil,
                                    activeKind: nil, remainderRange: nil, projectId: nil,
                                    openRunIsThreadRun: false)
    }

    /// One raw token from a quote-aware, `>`-aware scan of `rawQuery`: a
    /// word (quote-aware, whitespace/`>`-delimited) or an explicit `>`
    /// control character. `matchText` is the dequoted comparison value
    /// (mirrors what `tokenize` would produce); `range` is the VERBATIM
    /// span into `rawQuery`, quotes and all — what every `Segment.range`
    /// and `remainderRange`/`trailingTermRange` are built from.
    private enum RawToken {
        case word(range: NSRange, matchText: String, terminated: Bool)
        case chevron(range: NSRange)
    }

    /// Scans `rawQuery` into a sequence of words and `>` controls. A word is
    /// `terminated` when it is followed immediately by whitespace or `>`;
    /// the LAST word in the scan is unterminated when it instead runs to the
    /// end of the string with nothing following it — the "still being
    /// typed" signal rule 1 depends on. Mirrors `tokenize`'s quote-handling
    /// exactly (straight and curly quotes, `>` literal inside quotes) so the
    /// two scans always agree on where a boundary is.
    private static func scanRawTokens(_ rawQuery: String) -> [RawToken] {
        var tokens: [RawToken] = []
        var index = rawQuery.startIndex
        let end = rawQuery.endIndex

        while index < end {
            while index < end, rawQuery[index].isWhitespace {
                index = rawQuery.index(after: index)
            }
            guard index < end else { break }

            if rawQuery[index] == ">" {
                let start = index
                index = rawQuery.index(after: index)
                tokens.append(.chevron(range: NSRange(start..<index, in: rawQuery)))
                continue
            }

            let start = index
            var matchText = ""
            var inQuotes = false
            while index < end {
                let char = rawQuery[index]
                if quoteCharacters.contains(char) {
                    inQuotes.toggle()
                    index = rawQuery.index(after: index)
                    continue
                }
                if !inQuotes, char.isWhitespace || char == ">" { break }
                matchText.append(char)
                index = rawQuery.index(after: index)
            }
            // `index < end` means the scan stopped because it hit a
            // terminator character (whitespace or `>`), not because it ran
            // out of string — that's exactly "terminated".
            let terminated = index < end
            tokens.append(.word(range: NSRange(start..<index, in: rawQuery), matchText: matchText, terminated: terminated))
        }
        return tokens
    }

    private static func matchesTemplate(_ template: AgentTemplate, token: String) -> Bool {
        template.name.caseInsensitiveCompare(token) == .orderedSame
    }

    /// Parses `rawQuery` for the four-segment path grammar (project ›
    /// branch › operator › thread), greedy and type-matched, per the rules
    /// at the top of this section. `rawQuery` must be the RAW, untrimmed
    /// search text — trimming erases the trailing-whitespace signal
    /// termination depends on (mirrors why `stickyChipProjectId` below also
    /// takes a raw query). `parse(query:...)` below is the one caller that
    /// still passes a pre-trimmed string — deliberately, see its own doc
    /// comment for why that's safe for its specific, narrower contract
    /// rather than a violation of this one.
    ///
    /// `templates`/`knownBranchNames` are caller-supplied so this stays
    /// pure and disk-free — the parser never looks anything up itself.
    /// - `preResolvedProject` (Fix 3/Fix 4, round-2 review): a project whose
    ///   identity is supplied from OUTSIDE the typed text rather than
    ///   matched from it — the locked-composer case (the binding already
    ///   fixes the project; there's nothing to match) and the Palette's
    ///   no-project-typed fallback (a sticky/selected project is already
    ///   showing; the whole query should resolve branch/operator/thread
    ///   against ITS context) share this exact shape. When set (or when
    ///   `isLocked` is true with no project genuinely typeable), the walk
    ///   skips project-name matching entirely and starts with `.project`
    ///   already filled — AND treats the very first raw token as if it
    ///   followed an already-terminated project token (see
    ///   `hasProcessedAnyToken` below), so a single still-being-typed token
    ///   (`"cco"`, no trailing space) can still open a run immediately
    ///   instead of being withheld by rule 1's bare-first-token exception,
    ///   which exists only to protect an as-yet-unresolved PROJECT name.
    static func parsePath(
        rawQuery: String,
        projects: [Project],
        templates: [AgentTemplate],
        knownBranchNames: [String] = [],
        isLocked: Bool,
        preResolvedProject: Project? = nil
    ) -> PathParse {
        guard !rawQuery.isEmpty else { return .none }

        let rawTokens = scanRawTokens(rawQuery)
        guard !rawTokens.isEmpty else { return .none }

        let projectPositionIsFixed = isLocked || preResolvedProject != nil

        var filled = Set<SegmentKind>()
        var segments: [Segment] = []
        var projectId: UUID? = preResolvedProject?.id
        var trailingTermRange: NSRange?
        if projectPositionIsFixed {
            filled.insert(.project)
        }

        // The currently-open free-text run, if any. `openRunKind == nil`
        // means matching is still "live" — every terminated token so far
        // has claimed a type. Once a run opens it (almost) never reverts to
        // `nil`; the one exception is the Fix 5 branch below (a chevron-
        // opened operator run whose first token resolves against the known
        // template list) — round-3 review defect fix: THAT case reverts to
        // `nil` deliberately, mirroring the ordinary matching-live template
        // match exactly, so the next `>` is treated as the separator that
        // advances operator → thread (rule 4's live-matching branch) rather
        // than being swallowed as a literal character inside an
        // already-open thread run (rule 4's inside-a-thread-run branch).
        // Every OTHER path that opens a run still never reverts it; only
        // `>` (case: operation run open) closes and re-opens it as a
        // thread run.
        var openRunKind: SegmentKind?
        var openRunStart: Int?
        var openRunEnd: Int?
        // Whether any token (word or `>`) has been processed yet. Rule 1's
        // "never resolves" carve-out for an unterminated tail applies ONLY
        // to the very first token in the scan — before anything has
        // resolved, there is nothing to fall back to except pure search
        // filtering (this is what protects a bare single word like `bru`
        // or `ghostties`). Once matching has moved past that (a project has
        // resolved, say), an unterminated LATER token can never claim a
        // KNOWN value (project/branch/template — that's still off limits),
        // but it legitimately IS free text in progress — the whole point of
        // D4's ad-hoc operator / thread name — so it falls straight through
        // to rule 3 (open/extend a run) instead of being withheld. Every
        // unterminated token is by construction the LAST token in the scan
        // (nothing can follow it), so this only ever matters once, here.
        // Fix 3/Fix 4 (round-2 review): when the project position is
        // externally fixed, the walk proceeds "as if that project's name
        // had already been typed and terminated" (Fix 3's own wording) —
        // i.e. as if a prior token had already been processed — so the
        // bare-first-token exception below never withholds the very first
        // REAL token from opening a run just because it happens to be first
        // in this particular scan.
        var hasProcessedAnyToken = projectPositionIsFixed
        // B1 (round-1 review): set true only when THIS unterminated word is
        // what opened the run below — i.e. the token the user is still
        // typing is itself the reason matching gave up. In that one case,
        // `activeKind` must report the type that was STILL BEING TRIED
        // against it (first unfilled among project/branch/operation), not
        // the run's own classification — the suggestion list should keep
        // offering branch/project candidates for a token the user hasn't
        // finished, even though a fallback ad-hoc/thread run opens
        // underneath it for D13's "what if they hit Return right now"
        // remainder. A run opened by an EARLIER token (ordinary rule 3, or
        // a `>`) leaves this false, and `activeKind` follows `openRunKind`
        // as before — this is what keeps `ghostties cco -n te` reporting
        // `.operation` (its run opened at "cco", a different, already-
        // terminated token).
        var openedByFinalUnterminatedToken = false

        // Bug fix (shipped-parser defect, 2026-08-26): `>` used to be able
        // to advance PAST an unfilled `.branch` position straight to
        // `.operation`/`.thread` (`nextFreeTextKind()` only ever returns
        // those two) — a `>` typed right after the project could never
        // land on branch, so `ghostties > mybranch` fell through to the
        // ad-hoc/thread free-text path and got exec'd as a shell command.
        // `branchArmed` makes the FIRST `>` seen while matching is still
        // live (rule 4, case 1) claim the branch position instead of
        // skipping it: it opens no run, just arms the very next word token
        // to resolve (or fail) as the branch, unconditionally. A SECOND
        // `>` (branch already armed, or already filled) falls through to
        // the pre-existing behavior — Sean's decision 2: a double chevron
        // lands on operator (`ghostties > > do the thing` now offers
        // `Run "do the thing"`, where before it offered nothing).
        var branchArmed = false

        func nextFreeTextKind() -> SegmentKind {
            filled.contains(.operation) ? .thread : .operation
        }

        for token in rawTokens {
            let isFirstToken = !hasProcessedAnyToken
            hasProcessedAnyToken = true
            switch token {
            case .word(let range, let matchText, let terminated):
                if openRunKind == nil {
                    if branchArmed {
                        // An explicit `>` armed the branch position (rule
                        // 4, case 1 below) — this token resolves (or
                        // fails) as the branch UNCONDITIONALLY, regardless
                        // of `terminated`. It must never fall through to
                        // rule 3 and become ad-hoc/thread content: that's
                        // the exact defect this fix closes (a typed branch
                        // silently exec'd as a shell command).
                        branchArmed = false
                        if let canonical = knownBranchNames.first(where: { $0.caseInsensitiveCompare(matchText) == .orderedSame }) {
                            segments.append(Segment(kind: .branch, range: range, resolved: .branch(canonical)))
                        } else {
                            segments.append(Segment(kind: .branch, range: range, resolved: .unresolved))
                        }
                        filled.insert(.branch)
                        continue
                    }
                    if !terminated {
                        // B1 fix: this must be set regardless of whether we
                        // continue below without opening a run (the bare
                        // first-token case, still a valid Tab-complete
                        // target) or fall through to open one — the run
                        // opening is a D13 fallback, not evidence that
                        // completion no longer applies to this token.
                        trailingTermRange = range
                        if isFirstToken {
                            continue
                        }
                        // Not the first token, and not terminated: skip
                        // straight to rule 3 below (no type-matching
                        // attempted — an in-progress token can't claim a
                        // known value either way).
                        openRunKind = nextFreeTextKind()
                        openRunStart = range.location
                        openRunEnd = range.location + range.length
                        openedByFinalUnterminatedToken = true
                        continue
                    }
                    if !filled.contains(.project),
                       let project = projects.first(where: { matches($0, token: matchText) }) {
                        segments.append(Segment(kind: .project, range: range, resolved: .project(project.id)))
                        filled.insert(.project)
                        projectId = project.id
                        continue
                    }
                    if !filled.contains(.branch),
                       let canonical = knownBranchNames.first(where: { $0.caseInsensitiveCompare(matchText) == .orderedSame }) {
                        // Store the CANONICAL repo casing, not whatever
                        // case the user typed — `resolveTypedBranch`
                        // compares this token EXACTLY against
                        // `worktrees`/`currentBranchAtProjectRoot`, so a
                        // case-insensitive match here that kept the typed
                        // casing (`matchText`) produced a wrong "No
                        // worktree found" message for e.g. `Main`.
                        segments.append(Segment(kind: .branch, range: range, resolved: .branch(canonical)))
                        filled.insert(.branch)
                        continue
                    }
                    if !filled.contains(.operation),
                       let template = templates.first(where: { matchesTemplate($0, token: matchText) }) {
                        segments.append(Segment(kind: .operation, range: range, resolved: .template(template.id)))
                        filled.insert(.operation)
                        continue
                    }
                    // Rule 3: nothing matched — matching stops here for
                    // good. Open a free-text run starting at this token.
                    openRunKind = nextFreeTextKind()
                    openRunStart = range.location
                    openRunEnd = range.location + range.length
                } else if openRunKind == .operation, !filled.contains(.operation),
                          openRunStart == nil, terminated,
                          let template = templates.first(where: { matchesTemplate($0, token: matchText) }) {
                    // Fix 5 (round-2 review): the FIRST content token of an
                    // operator-position run still gets one shot against the
                    // known template list before becoming ad-hoc content —
                    // however that run opened. The ordinary matching-live
                    // path above already tries this for a run that opens
                    // because "nothing matched"; this covers the run opened
                    // by an explicit `>` (rule 4, case 1), which otherwise
                    // bypassed the template check entirely and let
                    // `ghostties > orchestrator` report an ad-hoc/thread
                    // segment instead of resolving the Orchestrator
                    // template (D4). A match resolves the operator exactly
                    // like the ordinary path does — round-3 review defect
                    // fix: that means returning matching to LIVE (`nil`),
                    // mirroring the ordinary path exactly, NOT jumping
                    // straight to an open thread run. Hard-setting
                    // `openRunKind = .thread` here used to make the run's
                    // own start lazy again but left `openRunKind` non-nil,
                    // so the very NEXT `>` (rule 4's `else` branch, "inside a
                    // thread run `>` is literal") swallowed it as a literal
                    // character into the thread name instead of treating it
                    // as the separator that advances from operator to
                    // thread (rule 4's `nil` branch) — `ghostties >
                    // orchestrator > mythread` yielded thread name
                    // "> mythread" instead of "mythread". Reverting to live
                    // matching here means that next `>` goes through the
                    // SAME rule-4-case-1 path the no-leading-chevron shape
                    // (`ghostties orchestrator > mythread`) already used
                    // correctly, so both shapes now resolve identically.
                    segments.append(Segment(kind: .operation, range: range, resolved: .template(template.id)))
                    filled.insert(.operation)
                    openRunKind = nil
                    openRunStart = nil
                    openRunEnd = nil
                } else {
                    // Rule 1 (second half): inside an open run, even an
                    // unterminated trailing token is legitimate content —
                    // it's free text being typed, not a segment lookup.
                    // `openRunStart` is set lazily (nil until the run's
                    // first real character arrives) so a run opened by `>`
                    // doesn't swallow the separating whitespace that
                    // preceded this word — see the chevron case below.
                    if openRunStart == nil { openRunStart = range.location }
                    openRunEnd = range.location + range.length
                }

            case .chevron(let range):
                if let kind = openRunKind {
                    if kind == .operation {
                        // Rule 4, case 2: close the ad-hoc run, advance to
                        // thread. B3 fix (round-1 review): only mark
                        // `.operation` filled (and only emit a segment) when
                        // the run actually had content — `ghostties > >
                        // refactor the parser` (Sean's skip-a-level shape,
                        // BACKLOG D6) closes an EMPTY operator run here.
                        // Marking `.operation` filled with nothing behind it
                        // was a lie the surrounding code never told anyone
                        // about, but it's still wrong state to carry even
                        // though nothing currently re-reads `filled` after a
                        // run has opened (a run, once open, never reverts to
                        // matching-live) — see the adapter fix below for the
                        // part of this bug that WAS observable.
                        if let start = openRunStart, let stop = openRunEnd, stop > start {
                            segments.append(Segment(
                                kind: .operation,
                                range: NSRange(location: start, length: stop - start),
                                resolved: .adHoc
                            ))
                            filled.insert(.operation)
                        }
                        openRunKind = .thread
                        openRunStart = nil
                        openRunEnd = nil
                    } else {
                        // Rule 4, case 3: inside a thread run, `>` is
                        // literal — extend the run through it (including
                        // the `>` character itself) rather than closing
                        // anything. If the thread run has no content yet
                        // (e.g. `ghostties cco > > name`), this `>` becomes
                        // its first character.
                        if openRunStart == nil { openRunStart = range.location }
                        openRunEnd = range.location + range.length
                    }
                } else if !filled.contains(.branch), !filled.contains(.operation), !branchArmed {
                    // Rule 4, case 1, branch fix: the FIRST `>` seen while
                    // matching is still live and branch is still reachable
                    // arms the branch position instead of skipping past it
                    // — opens no run. The next word token resolves (or
                    // fails) as the branch, see the `branchArmed` handling
                    // in the word case above.
                    //
                    // The `!filled.contains(.operation)` guard matters:
                    // branch can be legitimately BYPASSED without ever
                    // being filled — rule 2 tries each terminated word
                    // against every still-unfilled type in order, so
                    // `ghostties cco` (a known TEMPLATE name, not a
                    // branch) tries "cco" against branch first (fails),
                    // then operation (matches), leaving branch permanently
                    // unfilled but no longer reachable. Without this
                    // guard, a `>` after that point wrongly re-armed
                    // branch and swallowed the NEXT word as an unresolved
                    // branch instead of opening the thread run rule 4
                    // otherwise would.
                    branchArmed = true
                } else {
                    // Rule 4, case 1: matching was still live (branch
                    // already filled, or a second `>` with branch still
                    // armed but no word claimed it yet — decision 2, a
                    // double chevron lands on operator) — stop it for
                    // good and open a run at the next free-text position.
                    // No content yet (lazy start, as above).
                    branchArmed = false
                    openRunKind = nextFreeTextKind()
                    openRunStart = nil
                    openRunEnd = nil
                }
            }
        }

        var remainderRange: NSRange?
        if openRunKind != nil, let start = openRunStart, let stop = openRunEnd, stop > start {
            remainderRange = NSRange(location: start, length: stop - start)
        }

        // B1 fix: when the run was opened by the very last, still-typing
        // token (not an earlier one), report the type STILL BEING TRIED
        // against that token — not the run's own fallback classification —
        // so the suggestion list keeps offering the right candidates while
        // the user is mid-word. See `openedByFinalUnterminatedToken`'s
        // declaration above for the full reasoning and why this never
        // disagrees with `openRunKind` when the true answer is `.thread`.
        let firstUnfilledKind = [SegmentKind.project, .branch, .operation].first(where: { !filled.contains($0) })
        let activeKind: SegmentKind = openedByFinalUnterminatedToken
            ? (firstUnfilledKind ?? .thread)
            : (openRunKind ?? firstUnfilledKind ?? .thread)

        return PathParse(
            source: rawQuery,
            segments: segments,
            trailingTermRange: trailingTermRange,
            activeKind: activeKind,
            remainderRange: remainderRange,
            projectId: projectId,
            openRunIsThreadRun: openRunKind == .thread
        )
    }

    /// Splices `value` over `parse.trailingTermRange` in `parse.source` and
    /// appends a single trailing space. The space is deliberate, not
    /// cosmetic: it's the terminator, so accepting a completion is what
    /// resolves the segment — completion and termination are the same act.
    /// Splicing (rather than rejoining tokens) preserves everything after
    /// the term verbatim; a token-rejoin version would silently normalize
    /// the tail. Returns `parse.source` unchanged if there is no trailing
    /// term to complete.
    static func completing(parse: PathParse, with value: String) -> String {
        guard let range = parse.trailingTermRange, let bounds = Range(range, in: parse.source) else {
            return parse.source
        }
        var result = parse.source
        result.replaceSubrange(bounds, with: value + " ")
        return result
    }

    /// Parse `query` for the `<project> <remainder...>` shape — a thin
    /// adapter over `parsePath` (path grammar, above). `branchToken` is
    /// non-nil whenever a caller passes a `knownBranchNames` list that a
    /// typed token actually matches — Fix 1 (round-2 review) wired the
    /// production caller (`SessionComposerPalette.commandParse`) to pass
    /// the real per-project branch and template lists; a caller with no
    /// project context yet (none currently exist) is expected to pass `[]`
    /// for both explicitly, with a comment saying why, rather than silently
    /// defaulting.
    ///
    /// `query` is the caller's already-TRIMMED search text (its existing
    /// contract, unchanged by this rewrite) — NOT the raw `rawQuery`
    /// `parsePath` otherwise requires. This is safe here specifically
    /// because every one of `parse`'s test literals is either a single bare
    /// token (whose termination is unaffected by trimming — there was
    /// nothing trailing to trim) or already ends mid-word with no
    /// meaningful trailing whitespace of its own. A caller that DOES need
    /// the trailing-space/`>` termination signal (D2 completion, D12
    /// suggestion scoping) must call `parsePath` directly with the raw
    /// `searchText`, not through this adapter.
    ///
    /// Behavior note: as of the path-grammar rewrite, `>` no longer
    /// introduces a branch segment through this adapter — it closes
    /// whatever free-text run is open and advances (rule 4). A bare
    /// `ghostties > main` now resolves project `ghostties` with ad-hoc
    /// remainder `main`, not a branch.
    ///
    /// Redirect-truncation note (round-1 review, B2): the flat,
    /// no-leading-chevron shape (`ghostties npm run build > log.txt`, no
    /// space/`>` between project and the command) now truncates the
    /// remainder AT the first unquoted `>` — `["npm","run","build"]`, NOT
    /// `["npm","run","build",">","log.txt"]`. This is an intentional
    /// consequence of the greedy rewrite, not a bug: `>` is grammar now,
    /// not shell syntax, so an unquoted redirect inside an ad-hoc command
    /// needs quoting (`testParseKeepsQuotedChevronLiteralInAdHocRemainder`
    /// covers the quoted form; `testFlatFormRedirectTruncatesAtChevron`
    /// pins the unquoted truncation itself so a later "fix" can't silently
    /// walk it back).
    static func parse(
        query: String,
        projects: [Project],
        knownBranchNames: [String] = [],
        templates: [AgentTemplate] = [],
        isLocked: Bool,
        preResolvedProject: Project? = nil
    ) -> ParseResult {
        let path = parsePath(
            rawQuery: query,
            projects: projects,
            templates: templates,
            knownBranchNames: knownBranchNames,
            isLocked: isLocked,
            preResolvedProject: preResolvedProject
        )
        guard let projectId = path.projectId else { return .none }

        // Also surface a `.branch`-kind segment that resolved `.unresolved`
        // (an armed `>` whose word didn't match any known branch) — this is
        // what lets `statusStripMessage`/the commit-time reject in
        // `SessionComposerPalette` see and reject a typed-but-nonexistent
        // branch, instead of it silently vanishing because only the
        // `.branch(token)` case above used to be read.
        let branchToken: String? = path.segments.lazy.compactMap { segment -> String? in
            switch segment.resolved {
            case .branch(let token): return token
            case .unresolved where segment.kind == .branch: return segment.text(in: path.source)
            default: return nil
            }
        }.first

        // The remainder this adapter reports is "the command." Two sources,
        // tried in order:
        //
        // 1. A CLOSED ad-hoc operator segment — settled by an explicit `>`
        //    (`ghostties main cco > refactor the parser` closes ad-hoc
        //    "main cco" before the thread name even starts). Safe to report
        //    unconditionally: it's already a fact, regardless of what comes
        //    after it in the query, and `parse`'s flat `ParseResult` has no
        //    way to also report the thread name past it anyway (dropped,
        //    matching pre-rewrite behavior of only ever reporting one
        //    remainder).
        // 2. The STILL-OPEN run (`path.remainderRange`) — but ONLY when it's
        //    still classified as the operator, not a thread. B3 fix (round-1
        //    review): without this guard, `ghostties > > refactor the
        //    parser` (Sean's skip-a-level shape, BACKLOG D6) — an explicit
        //    `>` closing an EMPTY operator run, then a second `>` opening
        //    a thread run with no operator ever having resolved — fell
        //    through to `path.remainderRange`, which by then holds the
        //    THREAD text, and reported "refactor the parser" as the ad-hoc
        //    command. Fix 2 (round-2 review): this used to gate on
        //    `path.activeKind == .thread`, on the false premise that
        //    `activeKind` never reports anything other than `.thread` when
        //    the run truly is a thread run. It can: `activeKind` is a
        //    DIFFERENT signal (what the completion/suggestion UI should
        //    offer for a still-being-typed token — see
        //    `openedByFinalUnterminatedToken` in `parsePath`), and reports
        //    the first unfilled type among project/branch/operation even
        //    while the actually-open run underneath is genuinely a thread
        //    run (`"ghostties orchestrator te"` with a real `orchestrator`
        //    template: the operator resolves via the template match, branch
        //    is still unfilled, so `activeKind` reports `.branch` — but the
        //    run opened by "te" is genuinely `.thread`). `path.openRunIsThreadRun`
        //    is set directly from the run's own classification and is the
        //    correct signal here.
        let closedAdHocRange = path.segments.first(where: { $0.kind == .operation && $0.resolved == .adHoc })?.range
        let remainderRange: NSRange? = closedAdHocRange ?? (path.openRunIsThreadRun ? nil : path.remainderRange)

        // Blocker 1 (round-3 review): surface a resolved operator template
        // regardless of what's left in the remainder — see
        // `ParseResult.resolvedTemplateId`'s doc comment for why the
        // remainder alone can't stand in for this (it's empty the moment an
        // operator resolves to a template).
        let resolvedTemplateId: UUID? = path.segments.lazy.compactMap { segment -> UUID? in
            guard segment.kind == .operation, case .template(let id) = segment.resolved else { return nil }
            return id
        }.first

        guard let range = remainderRange, let bounds = Range(range, in: query) else {
            return ParseResult(projectId: projectId, remainderTokens: [], branchToken: branchToken, resolvedTemplateId: resolvedTemplateId)
        }
        let remainderTokens = tokenize(String(query[bounds]), separatorsIncludeChevron: false)
        return ParseResult(projectId: projectId, remainderTokens: remainderTokens, branchToken: branchToken, resolvedTemplateId: resolvedTemplateId)
    }

    /// The single parse of record for every caller that needs to resolve
    /// branch/operator/thread segments when no project token was typed at
    /// all but one is already implied (the sticky chip, or an
    /// already-selected project from the dropdown) — round-3 review,
    /// Blockers 2 and 3.
    ///
    /// `directParse` is whatever `parse(query:...)` already returned for the
    /// raw, as-typed query (trimmed or not — this function never re-derives
    /// it). When `directParse` resolved a project on its own, it's returned
    /// UNCHANGED: a project token was genuinely typed, so there is nothing
    /// to imply. Otherwise, if `impliedProject` is set, this re-parses
    /// against that project's context — this is the ONE seam every caller
    /// needing branch/operator/thread resolution against an implied project
    /// must go through, so two different callers (one reading `remainderText`
    /// for filtering, another reading `branchToken` for commit-time
    /// resolution) can never diverge by construction — a divergence that
    /// shipped as Blocker 3 (a typed branch consumed into the filter/options
    /// parse but never seen by `typedBranchResolution`, which still read the
    /// un-implied `directParse`, silently inheriting the picker's last pick).
    ///
    /// Blocker 2: `rawQuery` must be passed RAW (untrimmed) — trailing
    /// whitespace is `parsePath`'s only termination signal, and trimming it
    /// away before this re-parse is exactly what broke the sticky-chip
    /// case (`"ghostties "`, project typed + space, no remainder yet): with
    /// the project's own name still present in the text and no trailing
    /// terminator to distinguish it from content, the re-parse (which skips
    /// project MATCHING but not project TEXT — see `preResolvedProject`'s
    /// doc comment) swallowed "ghostties" itself as ad-hoc operator content,
    /// filtering out every real template and offering a bogus `Run
    /// "ghostties"` row. Detected via `stickyChipProjectId` (the same
    /// function that resolved `impliedProject` via the sticky chip in the
    /// first place): when it names the SAME project, the project's own text
    /// has already been fully accounted for by that resolution and
    /// contributes nothing further — the re-parse runs against an EMPTY
    /// remainder instead of the raw text verbatim. When it doesn't (no
    /// project token was typed at all — `impliedProject` came from the
    /// already-selected project, not from typed text, e.g. a typed branch
    /// like `"main cco -n test"` with a project already chosen via the
    /// picker), the raw text is used as-is: there is no project-name text to
    /// strip out of it.
    ///
    /// Round-6 review, Minor 1: the sticky-empty-remainder branch below
    /// (`remainderRawQuery.isEmpty`) is currently UNREACHABLE from
    /// production. Production always passes the SAME raw string to both
    /// `directParse` (via `SessionComposerPalette.commandParse`) and this
    /// function's `rawQuery:` (both read `composerStore.searchText`), so any
    /// shape `stickyChipProjectId` accepts — a terminated project token like
    /// `"ghostties "` — is already resolved by `directParse` itself, and the
    /// `directParse.projectId == nil` guard above short-circuits first.
    /// Left in place deliberately: correct behavior if the raw/trimmed
    /// contract at that call site ever changes back, not dead code to
    /// delete.
    static func effectiveParse(
        rawQuery: String,
        directParse: ParseResult,
        impliedProject: Project?,
        projects: [Project],
        knownBranchNames: [String],
        templates: [AgentTemplate],
        isLocked: Bool
    ) -> ParseResult {
        guard directParse.projectId == nil, let project = impliedProject else { return directParse }
        let stickyProjectId = stickyChipProjectId(rawQuery: rawQuery, projects: projects, isLocked: isLocked)
        let remainderRawQuery = (stickyProjectId == project.id) ? "" : rawQuery
        // Round-4 review, minor: an empty `remainderRawQuery` sends `parse()`
        // through `parsePath`'s `guard !rawQuery.isEmpty else { return .none }`
        // — `.none` has `projectId: nil`, even though a project IS
        // definitively resolved here (that's the whole point of the sticky
        // branch above). No current caller reads `effectiveCommandParse
        // .projectId`, so this was inert, but the doc comment above calls
        // this "the ONE parse of record" — return the resolved project
        // directly instead of routing an empty string through `parse()`.
        guard !remainderRawQuery.isEmpty else {
            return ParseResult(projectId: project.id, remainderTokens: [])
        }
        return parse(
            query: remainderRawQuery,
            projects: projects,
            knownBranchNames: knownBranchNames,
            templates: templates,
            isLocked: isLocked,
            preResolvedProject: project
        )
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

    // MARK: - Worktree-launch ruling (review round 2, finding 3)

    /// What "the composer field already resolves to something launchable"
    /// means for worktree-creation launch — pure, no `View`/`Store` needed,
    /// specifically so this can be unit-tested directly (the prior shape
    /// lived as a private `SessionComposerPalette` computed property with
    /// zero coverage; a reviewer found two real defects it could not have
    /// caught).
    ///
    /// Tried in order:
    /// 1. `resolvedTemplateId` — a TERMINATED operator segment the grammar
    ///    already matched by exact name (`matchesTemplate`, above).
    /// 2. The remainder's first token matched by exact name against
    ///    `templates` — finding 3's fix. An UNTERMINATED template name
    ///    (`ghostties feat-x cco`, no trailing separator) never reaches
    ///    `resolvedTemplateId`: the grammar treats "cco" as still being
    ///    typed, so it fell straight to `makeAdHocTemplate` below and
    ///    synthesized a shell template whose `command` is the literal
    ///    string `"cco"` — a zsh FUNCTION, not a binary, which fails
    ///    silently in a detached `Task` after the composer has already
    ///    closed. Checking the first remainder token against real template
    ///    names first mirrors what the TERMINATED case (`ghostties feat-x
    ///    cco ` or `ghostties feat-x cco >`) already does via
    ///    `matchesTemplate` — not a new ambiguity, just extending the same
    ///    rule to the unterminated case the ranking-based selection
    ///    (`SessionComposerRanking.bestMatchIndex`) already resolves the
    ///    same way for the NON-worktree-creation Return path.
    /// 3. `makeAdHocTemplate` — a genuine shell command with no matching
    ///    template name.
    /// `nil` when none of the three apply (nothing typed).
    static func resolveWorktreeCreationLaunchTemplate(
        resolvedTemplateId: UUID?,
        remainderTokens: [String],
        templates: [AgentTemplate]
    ) -> AgentTemplate? {
        if let resolvedTemplateId,
           let template = templates.first(where: { $0.id == resolvedTemplateId }) {
            return template
        }
        if let firstRemainderToken = remainderTokens.first,
           let matched = templates.first(where: { matchesTemplate($0, token: firstRemainderToken) }) {
            return matched
        }
        return makeAdHocTemplate(remainderTokens: remainderTokens)
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

    // MARK: - Resolution segments (model A rebuild — replaces the breadcrumb
    // chips' label logic; the resolution LINE itself was deleted in the
    // Composer UI 11 rebuild, plan §3 Step 5 — this struct and the function
    // below it are load-bearing under D-B: the ghost placeholder's genuine
    // source, not preserved for their tests)

    /// What the deleted resolution line's three segments used to show,
    /// computed from the same inputs the deleted chips read
    /// (`SessionComposerPalette`'s `currentProject`/`typedBranchResolution`/
    /// `currentBranchLabel`/`selectedOption`) — pure and testable, unlike
    /// those (private computed properties on a SwiftUI `View`, this repo's
    /// usual view-test-harness gap). Now consumed by
    /// `SessionComposerPalette.ghostPlaceholder` (Step 3) and
    /// `trailingControlVisibility` (Step 5) instead of a rendered line.
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

    // MARK: - Ghost placeholder (Composer UI 11 plan §3 Step 3, model A)

    /// The literal fallback strings `resolutionLineSegments` above renders
    /// when nothing real resolved — shared here so `ghostPlaceholder` can
    /// tell "a real project name" apart from "the unresolved fallback text"
    /// without a second source of truth. `resolutionLineSegments` is the
    /// only producer of `ResolutionLineSegments.projectLabel`; these two
    /// constants are that function's own literals, not a guess.
    private static let unlockedNoProjectLabel = "Select project"
    private static let lockedUnresolvableProjectLabel = "Project unavailable"

    /// The 11.1 rest-state ghost placeholder — a pure function over
    /// `ResolutionLineSegments`, D-B: the SAME values `resolutionLine` (now
    /// the trailing controls, Step 5) renders and `selectedOption` carries
    /// into a Return commit, so the placeholder can never state a
    /// destination Return would not launch — nothing here is computed
    /// independently. `SessionComposerPalette` gates every call to
    /// `.centered` only (G-F28: `.anchored` is 11pt/30pt at sidebar width
    /// and cannot fit the path).
    ///
    /// Four rules, checked in this order (plan §3 Step 3):
    /// 1. A real project resolved (`segments.projectLabel` isn't one of the
    ///    two fallback strings above) AND `hasSelection` — render the exact
    ///    path Return would commit: `"<project> > <branch> > <template>"`,
    ///    branch segment omitted when `segments.branchLabel == nil`
    ///    (`!isBranchSegmentEligible`).
    /// 2. Locked and unresolvable — a status, not a destination.
    /// 3. `!projectsExist` — the zero-project first-run lifeline (G-F7).
    /// 4. Otherwise — the field never states a destination Return will not
    ///    go to.
    static func ghostPlaceholder(
        segments: ResolutionLineSegments,
        hasSelection: Bool,
        projectsExist: Bool
    ) -> String {
        if hasSelection,
           segments.projectLabel != unlockedNoProjectLabel,
           segments.projectLabel != lockedUnresolvableProjectLabel {
            if let branchLabel = segments.branchLabel {
                return "\(segments.projectLabel) > \(branchLabel) > \(segments.templateLabel)"
            }
            return "\(segments.projectLabel) > \(segments.templateLabel)"
        }

        if !segments.isProjectClickable, segments.projectLabel == lockedUnresolvableProjectLabel {
            return "Project unavailable"
        }

        if !projectsExist {
            return "Add a project to begin"
        }

        return "Type a project, branch, and command…"
    }

    // MARK: - Status strip + empty state (Composer UI 11 plan §3 Step 4)

    /// The status strip's single occupant, if any — the `writeError` strip
    /// generalized (plan §3 Step 4). `writeError` (a failed Return,
    /// post-commit, unchanged) always beats a pre-Return typed-branch-not-
    /// found message (`TypedBranchResolution.unresolved`, plan §4 row 5);
    /// `nil` renders nothing, so the happy-path card matches the board
    /// exactly with no strip at all.
    static func statusStripMessage(
        writeError: String?,
        typedBranchResolution: TypedBranchResolution
    ) -> String? {
        if let writeError { return writeError }
        if case .unresolved(let token) = typedBranchResolution {
            return "branch \"\(token)\" not found"
        }
        return nil
    }

    /// What the results area's single empty-state row shows when nothing
    /// matches. Zero projects is the first-run lifeline (G-F7) — the
    /// composer must never render a dead-end "No matches" against an empty
    /// project list; the caller pairs this copy with a clickable row when
    /// `isProjectsEmpty` is true, plain text otherwise.
    static func emptyResultsCopy(isProjectsEmpty: Bool) -> String {
        isProjectsEmpty ? "Add project…" : "No matches"
    }

    // MARK: - Trailing picker controls (Composer UI 11 plan §3 Step 5)

    /// The two trailing controls' visibility + content, replacing the
    /// deleted resolution line's mouse route into the pickers (plan §4
    /// table, rows "mouse route into project/branch picker"). A single
    /// pure function so the view and this test suite read the exact same
    /// decision — never two independently-written copies that can diverge.
    struct TrailingControlVisibility: Equatable {
        /// `isBranchSegmentEligible` — a non-git project shows no branch
        /// control at all, not a disabled one (mirrors the deleted branch
        /// segment's own rule).
        let showBranchControl: Bool
        /// `nil` means "no news": default branch. The word "Default" is
        /// never restated outside the rest-state ghost path. Always `nil`
        /// when `showBranchControl` is `false`.
        let branchControlLabel: String?
        /// Hidden (not disabled) when the project is `.locked` — the
        /// locked rule survives verbatim (DESIGN.md: a locked composer
        /// must never expose a live picker affordance).
        let showProjectControl: Bool
    }

    static func trailingControlVisibility(
        isProjectLocked: Bool,
        isBranchSegmentEligible: Bool,
        isCreatingWorktree: Bool,
        currentBranchLabel: String?
    ) -> TrailingControlVisibility {
        TrailingControlVisibility(
            showBranchControl: isBranchSegmentEligible,
            branchControlLabel: isBranchSegmentEligible
                ? (isCreatingWorktree ? "Creating…" : currentBranchLabel)
                : nil,
            showProjectControl: !isProjectLocked
        )
    }
}
