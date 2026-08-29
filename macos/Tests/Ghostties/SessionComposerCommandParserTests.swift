import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for the composer's text-forward command grammar (slice 1). Pure
/// value-type parsing — no SwiftUI, no `@MainActor` state.
final class SessionComposerCommandParserTests: XCTestCase {

    private func makeProject(name: String, rootPath: String = "/Users/sean/Code/ghostties") -> Project {
        Project(name: name, rootPath: rootPath)
    }

    private func makeTemplate(name: String) -> AgentTemplate {
        AgentTemplate(id: UUID(), name: name, kind: .custom, command: name)
    }

    /// Test-local text extraction from an `NSRange` — mirrors what
    /// `Segment.text(in:)` does internally, but usable on `PathParse`'s bare
    /// `remainderRange`/`trailingTermRange` fields, which have no `text(in:)`
    /// of their own.
    private func text(_ range: NSRange?, in source: String) -> String? {
        guard let range, let bounds = Range(range, in: source) else { return nil }
        return String(source[bounds])
    }

    // MARK: - Tokenization (acceptance #3 — quoted argument survives intact)

    func testTokenizeSplitsOnWhitespace() {
        XCTAssertEqual(
            SessionComposerCommandParser.tokenize("ghostties cco -n test"),
            ["ghostties", "cco", "-n", "test"]
        )
    }

    func testTokenizeKeepsQuotedArgumentAsOneToken() {
        // The load-bearing case: a quoted multi-word argument must not be
        // split on its internal space.
        XCTAssertEqual(
            SessionComposerCommandParser.tokenize(#"ghostties cco -n "ghostties website""#),
            ["ghostties", "cco", "-n", "ghostties website"]
        )
    }

    // MARK: - parse — acceptance #2 (single-token parse returns projectId == nil)

    func testParseSingleTokenReturnsNilProjectId() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties", projects: [project], isLocked: false)
        XCTAssertNil(result.projectId)
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    func testParseSingleTokenReturnsNilEvenWhenItMatchesAProjectName() {
        // Protects the fast path: "bru" alone (a single token that matches
        // a project) must never tokenize — the whole-string filter is the
        // only thing that runs for a single token, byte-identical to today.
        let project = makeProject(name: "bru")
        let result = SessionComposerCommandParser.parse(query: "bru", projects: [project], isLocked: false)
        XCTAssertNil(result.projectId)
    }

    func testParseResolvesProjectByExactNameCaseInsensitive() {
        let project = makeProject(name: "Ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties cco -n test", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["cco", "-n", "test"])
    }

    func testParseResolvesProjectByFolderBasename() {
        let project = makeProject(name: "My Ghostties Fork", rootPath: "/Users/sean/Code/ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties shell", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
    }

    func testParseReturnsNilProjectIdWhenFirstTokenMatchesNoProject() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "unknown shell", projects: [project], isLocked: false)
        XCTAssertNil(result.projectId)
    }

    func testParseNeverTokenizesWhenLocked() {
        // The binding's `.locked` guard — a command must never re-scope a
        // project the composer already has fixed.
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties cco -n test", projects: [project], isLocked: true)
        XCTAssertNil(result.projectId)
    }

    func testParseQuotedArgumentSurvivesIntoRemainderTokens() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: #"ghostties cco -n "ghostties website""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.remainderTokens, ["cco", "-n", "ghostties website"])
    }

    func testRemainderTextJoinsTokensWithSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties cco -n test", projects: [project], isLocked: false)
        XCTAssertEqual(result.remainderText, "cco -n test")
    }

    // MARK: - makeAdHocTemplate — acceptance #4 (synthesized id == AgentTemplate.shell.id)

    func testMakeAdHocTemplateReusesShellTemplateId() {
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["cco", "-n", "test"])
        XCTAssertEqual(template?.id, AgentTemplate.shell.id)
    }

    func testMakeAdHocTemplateSplitsFirstTokenIntoCommandAndRestIntoAdditionalFlags() {
        // The two-blocker fix: `command` cannot hold a multi-word string
        // (shellEscape quotes it whole), so only the first token goes
        // there — everything else must land in `agent.additionalFlags`,
        // the per-token-escaped carrier.
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["cco", "-n", "test"])
        XCTAssertEqual(template?.command, "cco")
        XCTAssertEqual(template?.agent?.additionalFlags, ["-n", "test"])
        XCTAssertEqual(template?.name, "cco")
        XCTAssertEqual(template?.kind, .custom)
    }

    func testMakeAdHocTemplateSetsAgentEvenWithNoExtraFlags() {
        // `agent` must be non-nil regardless of remainder length — it's
        // what buys the login-shell wrapper in SessionCoordinator, not an
        // actual agent configuration.
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["cco"])
        XCTAssertNotNil(template?.agent)
        XCTAssertEqual(template?.agent?.additionalFlags, [])
    }

    func testMakeAdHocTemplateReturnsNilForEmptyRemainder() {
        XCTAssertNil(SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: []))
    }

    /// Blocker fix: `tokenize("ghostties \"")` (an unbalanced trailing
    /// quote) flushes an empty token, yielding `remainderTokens == [""]` —
    /// `makeAdHocTemplate` used to guard only `.isEmpty` on the ARRAY, not
    /// on the first token's content, so this produced a live `Run ""` row
    /// that committed `exec ''` on Return.
    func testMakeAdHocTemplateReturnsNilForBlankFirstToken() {
        XCTAssertNil(SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: [""]))
        XCTAssertNil(SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["   "]))
    }

    /// Blocker fix: a quoted first remainder token survives `tokenize` as
    /// one token containing internal whitespace (`ghostties "npm run
    /// dev"` -> `remainderTokens == ["npm run dev"]`). Putting that whole
    /// string into `command` reintroduces the `shellEscape` blocker
    /// verbatim — `buildCommand()` quotes it as ONE argv word
    /// (`'npm run dev'`), which the shell can't resolve and the session
    /// dies not-found, silently. This test calls the REAL production
    /// `buildCommand()` / `shellEscape`, not a re-declared copy, and fails
    /// without the fix (it asserted `command == "npm run dev"` and
    /// `buildCommand() == "'npm run dev'"` before the fix).
    func testMakeAdHocTemplateReSplitsQuotedFirstTokenIntoPerWordArgv() {
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["npm run dev"])
        XCTAssertEqual(template?.command, "npm")
        XCTAssertEqual(template?.agent?.additionalFlags, ["run", "dev"])
        XCTAssertEqual(template?.buildCommand(), "'npm' 'run' 'dev'")
    }

    /// The re-split first token's extra words must land BEFORE the rest of
    /// the remainder, preserving argument order end to end.
    func testMakeAdHocTemplateReSplitFirstTokenPrecedesRestOfRemainder() {
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["npm run", "--watch"])
        XCTAssertEqual(template?.command, "npm")
        XCTAssertEqual(template?.agent?.additionalFlags, ["run", "--watch"])
    }

    /// Static evidence for acceptance #1 (the repro must spawn a session
    /// running `cco -n test`), calling the REAL `AgentTemplate.buildCommand()`
    /// / `shellEscape` — not a re-declared copy. `SessionCoordinator.createSession`
    /// composes its wrapper script's exec line as exactly `"exec \(cmd)"`
    /// where `cmd` is this string (after PATH resolution, which leaves an
    /// unresolvable zsh function like `cco` untouched) — so a correct
    /// `buildCommand()` output here is what makes that exec line become
    /// `exec 'cco' '-n' 'test'`. This does NOT substitute for reading the
    /// actual on-disk wrapper script; see the PR description for why that
    /// couldn't be produced in this pass.
    func testMakeAdHocTemplateBuildCommandProducesPerTokenEscapedArgv() {
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["cco", "-n", "test"])
        XCTAssertEqual(template?.buildCommand(), "'cco' '-n' 'test'")
        // The launchBanner branch (agent != nil) is what makes
        // SessionCoordinator.createSession write the #!/bin/zsh -l wrapper
        // at all — without it, the ad-hoc command would spawn under a bare
        // /bin/sh -c and "cco: not found" (blocker 2).
        XCTAssertNotNil(template?.launchBanner)
    }

    /// Mutant-verification for acceptance #4, per this repo's
    /// `feedback_vacuous-tests-pass-green` lesson: a test that only checks
    /// a locally-declared literal proves nothing. The original second
    /// assertion here, `XCTAssertNotEqual(template?.id, UUID())`, compared
    /// against a FRESHLY MINTED random UUID — that passes unconditionally
    /// regardless of what `makeAdHocTemplate` actually does, including
    /// under the exact `id: UUID()` mutant it claimed to guard (two random
    /// UUIDs essentially never collide, so the assertion is vacuous by
    /// construction).
    ///
    /// Replaced with an assertion that discriminates against that specific
    /// mutant: two INDEPENDENT calls must return the SAME id. Under the
    /// real production line (`id: AgentTemplate.shell.id`) that's always
    /// true. Under the `id: UUID()` mutant, two separate calls mint two
    /// different random UUIDs, so this fails hard instead of trivially
    /// passing. On its own it does not prove the id IS
    /// `AgentTemplate.shell.id` — a stable-but-wrong id (e.g.
    /// `AgentTemplate.claudeCode.id`, a hardcoded UUID) would pass this
    /// assertion too. That check is the pre-existing assertion above.
    /// Manually verified: broke `makeAdHocTemplate`'s `id:` argument to
    /// `UUID()`, ran the suite, confirmed BOTH assertions in this test go
    /// red; restored the production line and confirmed green (see PR
    /// description / task report for the red/green run output).
    func testMakeAdHocTemplateIdMatchesRealShellTemplateSymbolNotALocalCopy() {
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["cco"])
        // Deliberately re-derive from the production singleton rather than
        // a hardcoded UUID string, so a future change to `AgentTemplate.shell`
        // can't silently desync this assertion from what actually matters:
        // `WorkspacePersistence.validate` recognizing the id as a known template.
        XCTAssertEqual(template?.id, AgentTemplate.shell.id)

        let secondTemplate = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: ["bru"])
        XCTAssertEqual(template?.id, secondTemplate?.id)
    }

    // MARK: - Commit-path project resolution (finding 1 — scopes list to
    // project A, commits into project B)
    //
    // The bug itself lives in `SessionComposerPalette.commit(template:)`, a
    // SwiftUI `View` reading `@EnvironmentObject` state — no testable seam
    // without a view harness this repo doesn't have. The fix is the
    // resolution RULE (`resolveCommitProjectId`), extracted here as a pure
    // function specifically so the rule itself has real coverage. This is
    // rule coverage, not call-site coverage: the three tests below exercise
    // `commandProjectId ?? selectedProjectId` in isolation, but the call
    // site passes both arguments by name (`commit(template:)`, around
    // `SessionComposerPalette.swift:800-803`) with no independent test —
    // swapping `commandProjectId:`/`selectedProjectId:` there, the exact
    // polarity error this rule exists to prevent, leaves all three tests
    // passing.

    func testResolveCommitProjectIdPrefersCommandProjectOverSelection() {
        let commandProjectId = UUID()
        let selectedProjectId = UUID()
        XCTAssertEqual(
            SessionComposerCommandParser.resolveCommitProjectId(
                commandProjectId: commandProjectId,
                selectedProjectId: selectedProjectId
            ),
            commandProjectId
        )
    }

    func testResolveCommitProjectIdFallsBackToSelectionWhenNoCommand() {
        let selectedProjectId = UUID()
        XCTAssertEqual(
            SessionComposerCommandParser.resolveCommitProjectId(
                commandProjectId: nil,
                selectedProjectId: selectedProjectId
            ),
            selectedProjectId
        )
    }

    func testResolveCommitProjectIdReturnsNilWhenNeitherIsSet() {
        XCTAssertNil(
            SessionComposerCommandParser.resolveCommitProjectId(commandProjectId: nil, selectedProjectId: nil)
        )
    }

    // MARK: - B1 (breadcrumb chip review): the query field binding must be
    // lossless.
    //
    // `SessionComposerPalette.queryFieldText` used to `get`
    // `commandParse.remainderText` — `remainderTokens.joined(separator: " ")`
    // — and `set` by re-prepending the matched token with a single hardcoded
    // space. SwiftUI writes a binding's `get` value straight back into the
    // field on the next render, so that round trip being lossy is exactly
    // what made `ghostties cco -n "test"` untypable: a trailing space was
    // eaten the instant it was typed, and a typed quote character never
    // survived into `searchText` at all.

    /// The permanent regression test for the ACTUAL fix:
    /// `splitOnFirstToken` slices `searchText` directly rather than
    /// rebuilding it, so `prefix + remainder` round-trips through `parse`
    /// exactly — quotes, internal whitespace, and all. This is what
    /// `queryFieldText`'s `get`/`set` are wired to now.
    func testSplitOnFirstTokenRoundTripsThroughReparseWithQuotedArgument() {
        let project = makeProject(name: "ghostties")
        let original = #"ghostties cco -n "npm run dev""#
        let firstParse = SessionComposerCommandParser.parse(query: original, projects: [project], isLocked: false)
        XCTAssertEqual(firstParse.remainderTokens, ["cco", "-n", "npm run dev"])

        guard let split = SessionComposerCommandParser.splitOnFirstToken(original) else {
            XCTFail("expected a split for a resolved command")
            return
        }
        // F4 fix (round-2 review): `split.prefix + split.remainder ==
        // original` is TAUTOLOGICAL — slicing any string at any index and
        // concatenating the two halves reproduces the original string no
        // matter where the split point lands, so this assertion could never
        // fail even if `splitOnFirstToken` split at the wrong boundary
        // entirely. The discriminating assertion is on `split.remainder`'s
        // actual VALUE — this is what proves the split landed after "ghostties "
        // specifically, quotes and all, not just "somewhere". Proven
        // red-then-green against production code (task report has the
        // captured output): moving the split point by one character in
        // `splitOnFirstToken` turns this red while the old tautological
        // assertion stayed green.
        XCTAssertEqual(split.remainder, #"cco -n "npm run dev""#)

        // `get` returns `split.remainder` verbatim; `set` re-prepends
        // `split.prefix` verbatim — simulate a no-op edit (typing the same
        // remainder back in) and confirm the round trip reproduces the
        // exact same tokens.
        let reconstructed = split.prefix + split.remainder
        XCTAssertEqual(reconstructed, original)

        let secondParse = SessionComposerCommandParser.parse(query: reconstructed, projects: [project], isLocked: false)
        XCTAssertEqual(secondParse.remainderTokens, firstParse.remainderTokens)
    }

    /// The trailing-whitespace case B1 called out explicitly: a space typed
    /// after the last remainder token must survive into `searchText`
    /// unchanged, not be trimmed away by a tokenize/rejoin round trip.
    func testSplitOnFirstTokenPreservesTrailingWhitespaceInRemainder() {
        let project = makeProject(name: "ghostties")
        let original = "ghostties cco -n test "
        guard let split = SessionComposerCommandParser.splitOnFirstToken(original) else {
            XCTFail("expected a split")
            return
        }
        XCTAssertEqual(split.remainder, "cco -n test ")
        XCTAssertEqual(split.prefix + split.remainder, original)
    }

    func testSplitOnFirstTokenReturnsNilForBlankInput() {
        XCTAssertNil(SessionComposerCommandParser.splitOnFirstToken(""))
        XCTAssertNil(SessionComposerCommandParser.splitOnFirstToken("   "))
    }

    // MARK: - D3 (breadcrumb chip review): sticky chip through an
    // empty-remainder backspace.

    func testStickyChipProjectIdResolvesWhenRemainderIsEmptyAfterASeparator() {
        let project = makeProject(name: "ghostties")
        let id = SessionComposerCommandParser.stickyChipProjectId(rawQuery: "ghostties ", projects: [project], isLocked: false)
        XCTAssertEqual(id, project.id)
    }

    func testStickyChipProjectIdReturnsNilWithNoSeparatorEverTyped() {
        // The ordinary single-token project-search case — must NOT be
        // treated as sticky just because the token happens to match a
        // project (mirrors `testParseSingleTokenReturnsNilEvenWhenItMatchesAProjectName`).
        let project = makeProject(name: "bru")
        let id = SessionComposerCommandParser.stickyChipProjectId(rawQuery: "bru", projects: [project], isLocked: false)
        XCTAssertNil(id)
    }

    func testStickyChipProjectIdReturnsNilWhenLocked() {
        let project = makeProject(name: "ghostties")
        let id = SessionComposerCommandParser.stickyChipProjectId(rawQuery: "ghostties ", projects: [project], isLocked: true)
        XCTAssertNil(id)
    }

    func testStickyChipProjectIdReturnsNilWhenFirstTokenMatchesNoProject() {
        let project = makeProject(name: "ghostties")
        let id = SessionComposerCommandParser.stickyChipProjectId(rawQuery: "unknown ", projects: [project], isLocked: false)
        XCTAssertNil(id)
    }

    /// F2 (round-2 review): a quoted multi-word project name — DESIGN.md
    /// calls multi-word basenames "the normal case" — must stay sticky
    /// through the empty-remainder backspace exactly like a single-word
    /// name does above. The prior implementation extracted the token with
    /// `split.prefix.trimmingCharacters(in: .whitespaces)`, which strips
    /// whitespace only; `tokenize` also strips the quote characters
    /// wrapping a multi-word name, so the extracted token was
    /// `"\"ghostties web\""` — quotes still attached — which never matched
    /// `matches(_:token:)` against the bare project name "ghostties web".
    /// Proven red against that code (task report has the captured output).
    func testStickyChipProjectIdResolvesForQuotedMultiWordProjectName() {
        let project = makeProject(name: "ghostties web")
        let id = SessionComposerCommandParser.stickyChipProjectId(
            rawQuery: #""ghostties web" "#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(id, project.id)
    }

    // MARK: - FB (round-2 review): curly quotes (macOS's default "smart
    // quotes and dashes" substitution) must be recognized as quote
    // boundaries, not just the straight `"`.

    func testTokenizeTreatsCurlyQuotesAsQuoteCharacters() {
        let tokens = SessionComposerCommandParser.tokenize("ghostties \u{201C}npm run dev\u{201D}")
        XCTAssertEqual(tokens, ["ghostties", "npm run dev"])
    }

    func testStickyChipProjectIdResolvesForCurlyQuotedMultiWordProjectName() {
        let project = makeProject(name: "ghostties web")
        let id = SessionComposerCommandParser.stickyChipProjectId(
            rawQuery: "\u{201C}ghostties web\u{201D} ",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(id, project.id)
    }

    // MARK: - Slice B (composer breadcrumb spec): typable `>` segment
    // separator. Parser only — no UI, no store changes.

    /// Bug fix (2026-08-26, shipped-parser defect): this test USED TO PIN
    /// THE BUG — it asserted `branchToken == nil` and
    /// `remainderTokens == ["main"]`, i.e. that a `>` could never land on
    /// the branch position and a typed branch fell through to the ad-hoc
    /// remainder. That is exactly the real-world failure (`ghostties >
    /// backlog/migrate-ghostties` spawned `exec 'backlog/migrate-
    /// ghostties'` instead of opening the branch's worktree). No known
    /// branch list is passed to `parse` here, so "main" resolves to an
    /// UNRESOLVED branch segment — a truthful "not found" reported via
    /// `branchToken`, never silently exec'd. See
    /// `testParseResolvesTypedBranchAgainstKnownBranchNames` below for the
    /// branch-actually-exists case, and
    /// `testParseReproducesTheReportedGhosttiesBacklogMigrateBug` for the
    /// exact reported input.
    func testParseRecognizesChevronAsBranchSeparatorWithSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties > main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    /// See `testParseRecognizesChevronAsBranchSeparatorWithSpaces` — same
    /// bug, no-space chevron form.
    func testParseRecognizesChevronAsBranchSeparatorWithoutSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties>main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    /// Bug fix (2026-08-26): rewritten now that `>` lands on branch. The
    /// first `>` arms the branch position; "main" (no known branch list
    /// passed to `parsePath` here) resolves it as UNRESOLVED, not ad-hoc
    /// content. The second `>` (branch now filled) advances to operator and
    /// opens an ad-hoc run at "npm run build"; the third `>` (run open,
    /// kind `.operation`) closes it and opens a thread run; "log.txt"
    /// becomes the thread run's content — there's no fourth `>` in this
    /// query to test the "literal inside thread" rule, see
    /// `testParsePathChevronLiteralInsideThreadRun` for that half
    /// (previously combined into this one test, split because the meaning
    /// of every position after branch shifted by one chevron).
    func testParsePathChevronAdvancesThroughBranchThenClosesAdHocThenOpensThread() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > main > npm run build > log.txt",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        let branchSegment = result.segments.first { $0.kind == .branch }
        XCTAssertEqual(branchSegment?.resolved, .unresolved)
        XCTAssertEqual(branchSegment.map { $0.text(in: result.source) }, "main")
        let adHocSegments = result.segments.filter { $0.kind == .operation && $0.resolved == .adHoc }
        XCTAssertEqual(adHocSegments.map { $0.text(in: result.source) }, ["npm run build"])
        XCTAssertEqual(result.activeKind, .thread)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "log.txt")
    }

    /// The "literal `>` inside an open thread run" half of the old combined
    /// test, re-derived for the shifted grammar: one extra `>` (four total)
    /// is needed to actually reach thread and still have a `>` left over to
    /// swallow literally, now that the first `>` is spent arming branch.
    func testParsePathChevronLiteralInsideThreadRun() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > main > npm build > log.txt > extra",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.activeKind, .thread)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "log.txt > extra")
    }

    /// Sean's decision 2 (2026-08-26): each `>` advances exactly one slot,
    /// matching Tab — project > branch > operator > thread. A double
    /// chevron with nothing typed between them now skips the (still
    /// unfilled) branch slot entirely and lands on operator, so `ghostties
    /// > > refactor the parser` now offers `Run "refactor the parser"`
    /// where before the branch-arming fix it offered nothing (that
    /// unreachability was a side effect of the SAME bug this whole change
    /// fixes — two chevrons used to reach thread directly, skipping branch
    /// AND operator, because branch could never be landed on in the first
    /// place). This test previously asserted the OPPOSITE — that the
    /// thread name could never be reported as an ad-hoc command — and is
    /// rewritten per Sean's explicit acceptance of the new shape.
    func testDoubleChevronLandsOnOperatorPerDecision2() {
        let project = makeProject(name: "ghostties")
        let path = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > > refactor the parser",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertFalse(path.segments.contains { $0.kind == .branch })
        XCTAssertFalse(path.segments.contains { $0.kind == .operation })
        XCTAssertEqual(path.activeKind, .operation)
        XCTAssertFalse(path.openRunIsThreadRun)
        XCTAssertEqual(text(path.remainderRange, in: path.source), "refactor the parser")

        let result = SessionComposerCommandParser.parse(
            query: "ghostties > > refactor the parser",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["refactor", "the", "parser"])
    }

    /// The other half of the old test's real requirement: a redirect inside
    /// quotes must stay a literal argv word straight through `parse`'s flat
    /// adapter — unaffected by the path-grammar rewrite, since quoting still
    /// wins over the terminator (mirrors `testParseKeepsQuotedChevronLiteral`
    /// but exercises the ad-hoc-run path specifically, not the single-quoted-
    /// remainder path).
    func testParseKeepsQuotedChevronLiteralInAdHocRemainder() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: #"ghostties "npm run build > log.txt""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["npm run build > log.txt"])

        // D7 (round-1 review): stopping at `tokenize` output doesn't prove
        // the redirect survives all the way to the argv that actually gets
        // executed — `makeAdHocTemplate`/`buildCommand()` (`AgentTemplate`)
        // is where that's earned, via the per-token-escaped
        // `additionalFlags` carrier. Mutation-proof: reverting
        // `makeAdHocTemplate`'s re-split-first-token fix (putting the whole
        // `"npm run build > log.txt"` into `command` unsplit) turns
        // `buildCommand()` into `''npm run build > log.txt''` — one
        // unrunnable argv word — which fails this assertion; confirmed by
        // temporarily reverting that fix, running red, then restoring it.
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: result.remainderTokens)
        XCTAssertEqual(template?.command, "npm")
        XCTAssertEqual(template?.agent?.additionalFlags, ["run", "build", ">", "log.txt"])
        XCTAssertEqual(template?.buildCommand(), "'npm' 'run' 'build' '>' 'log.txt'")
    }

    // MARK: - Bug fix coverage (2026-08-26): typed branches unreachable,
    // silently exec'd as a shell command. Every production symbol here is
    // the real one — `parsePath`/`parse`, `knownBranchNames`,
    // `resolveTypedBranch` — never a re-declared literal.

    /// The exact reported input: `ghostties > backlog/migrate-ghostties`,
    /// with `backlog/migrate-ghostties` a real branch that simply has no
    /// worktree yet (`knownBranchNames` mirrors what
    /// `SessionComposerPalette.commandKnownBranchNames` now passes after
    /// appending `SessionComposerStore.branchesWithoutWorktree` — see that
    /// property's own fix comment). Before this fix the token was absorbed
    /// as ad-hoc content and `makeAdHocTemplate` would have synthesized a
    /// `Run "backlog/migrate-ghostties"` row, which
    /// `SessionCoordinator`'s login-shell wrapper then execs literally
    /// (the real failure: `exec 'backlog/migrate-ghostties'`, "no such
    /// file or directory"). After the fix: the branch resolves (not ad-hoc
    /// content), the remainder is empty, and `makeAdHocTemplate` refuses to
    /// synthesize a Run row at all — there is nothing left to exec.
    func testParseReproducesTheReportedGhosttiesBacklogMigrateBug() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > backlog/migrate-ghostties",
            projects: [project],
            knownBranchNames: ["backlog/migrate-ghostties"],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "backlog/migrate-ghostties")
        XCTAssertTrue(result.remainderTokens.isEmpty)
        XCTAssertNil(
            SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: result.remainderTokens),
            "no Run row must be synthesized — the token resolved as a branch, not a shell command"
        )
    }

    /// A branch WITH a worktree, reached via chevron — the
    /// `TypedBranchResolution.resolved` case, the ordinary "open a session
    /// in that branch's worktree" path. `resolveTypedBranch` is the real
    /// production seam `SessionComposerPalette.typedWorktreePath` reads.
    func testParseChevronBranchWithWorktreeResolvesToWorktreePath() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > feature-x",
            projects: [project],
            knownBranchNames: ["feature-x"],
            isLocked: false
        )
        XCTAssertEqual(result.branchToken, "feature-x")

        let worktree = GitWorktreeEnumerator.Worktree(path: "/Users/sean/Code/ghostties-feature-x", branch: "feature-x", isLocked: false)
        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [worktree],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .resolved(path: "/Users/sean/Code/ghostties-feature-x"))
    }

    /// A branch with NO worktree, reached via chevron — resolves as a
    /// branch segment (not ad-hoc), then `resolveTypedBranch` reports
    /// `.unresolved`, which is the signal `SessionComposerPalette` uses to
    /// offer a "Create worktree" row (decision 1) rather than a dead end.
    func testParseChevronBranchWithNoWorktreeReachesUnresolvedForCreateOffer() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > backlog/no-worktree-yet",
            projects: [project],
            knownBranchNames: ["backlog/no-worktree-yet"],
            isLocked: false
        )
        XCTAssertEqual(result.branchToken, "backlog/no-worktree-yet")

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .unresolved(token: "backlog/no-worktree-yet"))
    }

    /// A branch that genuinely does not exist — must fail truthfully
    /// (`.unresolved`, surfaced as "branch \"...\" not found"), never
    /// silently exec'd and never confused with the create-offer case above
    /// (that one distinguishes itself only at the `SessionComposerPalette`
    /// layer, by checking `branchesWithoutWorktree`; the parser/engine
    /// layer reports the identical `.unresolved` shape for both, correctly
    /// — see `SessionComposerCommandParser.TypedBranchResolution.unresolved`'s
    /// doc comment).
    func testParseNonexistentBranchReachesTruthfulError() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > totally-made-up-branch",
            projects: [project],
            knownBranchNames: ["main", "feature-x"],
            isLocked: false
        )
        // Doesn't match any known branch name at all: the segment is
        // `.unresolved`, and `branchToken` still surfaces the raw typed
        // text (item 3's fix) rather than vanishing.
        XCTAssertEqual(result.branchToken, "totally-made-up-branch")

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .unresolved(token: "totally-made-up-branch"))
        let commitResult = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: resolution,
            selectedWorktreePath: nil
        )
        switch commitResult {
        case .failure(let error):
            XCTAssertTrue(error.message.contains("No worktree found for branch"))
        case .success:
            XCTFail("a genuinely nonexistent branch must fail the commit, not silently succeed")
        }
    }

    /// Case-sensitivity fix: `resolveTypedBranch` compares the token
    /// EXACTLY (`:1090`/`:1093`-equivalent lines) while `parsePath` now
    /// matches branch names case-INSENSITIVELY — without storing the
    /// CANONICAL repo casing on the resolved segment, typing "Main" against
    /// a repo branch actually named "main" would resolve the segment (typed
    /// casing preserved) but then fail the exact-match downstream, reporting
    /// a wrong "No worktree found" error for a branch that plainly exists.
    func testParseTypedBranchCasingResolvesToCanonicalRepoBranchName() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > Main",
            projects: [project],
            knownBranchNames: ["main"],
            isLocked: false
        )
        // Canonical casing ("main"), NOT what was typed ("Main").
        XCTAssertEqual(result.branchToken, "main")

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .isDefaultBranch, "must resolve, not report a false \"not found\"")
    }

    /// A quoted `>` must stay a literal character inside the quoted
    /// argument, never a segment separator — the `!inQuotes` guard applies
    /// to chevron exactly as it already does to whitespace.
    func testParseKeepsQuotedChevronLiteral() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: #"ghostties "a > b""#, projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["a > b"])
    }

    /// Sticky chip triggered via `>` (no space) — mirrors the existing
    /// whitespace-triggered sticky chip.
    func testStickyChipProjectIdTriggeredByChevronWithNoSpace() {
        let project = makeProject(name: "ghostties")
        let id = SessionComposerCommandParser.stickyChipProjectId(rawQuery: "ghostties>", projects: [project], isLocked: false)
        XCTAssertEqual(id, project.id)
    }

    /// Named fast-path regression: with `>` now recognized as a segment
    /// separator, the single-token query must stay byte-identical to slice
    /// 1 — `commandProject` (driven by `parse(query:).projectId`) may only
    /// go non-nil when the text before a `>` (or whitespace) exactly
    /// matches a project name. A bare single-token query, even one that
    /// matches a project name outright, must still return `projectId ==
    /// nil` so `templateFilterQuery` falls through to the raw query
    /// unchanged.
    func testParseSingleTokenQueryStaysNilProjectIdEvenWithChevronSupportAdded() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties", projects: [project], isLocked: false)
        XCTAssertNil(result.projectId)
        XCTAssertNil(result.branchToken)
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    /// Disambiguation rule: a bare second token is a remainder, never a
    /// branch, unless an explicit `>` introduced it.
    func testParseTreatsBareSecondTokenAsRemainderNotBranch() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties main cco", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["main", "cco"])
        XCTAssertEqual(result.remainderText, "main cco")
    }

    // MARK: - resolutionLineSegments (model A rebuild — replaces the
    // breadcrumb chips with the composer's type-first field + resolution
    // line). Pure, so the model backing what the resolution line renders is
    // testable without a SwiftUI view-test harness (this repo's usual gap).

    /// A resolved parse: project and branch both picked, template
    /// resolved — every segment shows its plain, non-error label.
    func testResolutionLineSegmentsForAResolvedParse() {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: "ghostties",
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            typedBranchResolution: .resolved(path: "/tmp/ghostties-worktrees/feature-x"),
            currentBranchLabel: "feature-x",
            templateTitle: "Claude Code"
        )
        XCTAssertEqual(segments.projectLabel, "ghostties")
        XCTAssertTrue(segments.isProjectClickable)
        XCTAssertEqual(segments.branchLabel, "feature-x")
        XCTAssertFalse(segments.branchIsError)
        XCTAssertEqual(segments.templateLabel, "Claude Code")
    }

    /// An unresolved typed branch renders a legible, on-screen message in
    /// the error state — this is the acceptance criterion the deleted
    /// chips never met: an unresolved branch was only ever visible as a
    /// `writeError` message AFTER a failed Return, never on the resolution
    /// line itself.
    func testResolutionLineSegmentsForAnUnresolvedBranch() {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: "ghostties",
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: false,
            typedBranchResolution: .unresolved(token: "does-not-exist"),
            currentBranchLabel: "does-not-exist",
            templateTitle: "cco"
        )
        XCTAssertEqual(segments.branchLabel, "branch \"does-not-exist\" not found")
        XCTAssertTrue(segments.branchIsError)
    }

    /// An empty field: no project selected, no branch typed, but a
    /// template IS still resolved (the project's default, seeded on open) —
    /// this is what makes the resolution line answer "where will this go?"
    /// from the very first frame, per the brief's acceptance criterion.
    func testResolutionLineSegmentsForAnEmptyField() {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: nil,
            isProjectLocked: false,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            typedBranchResolution: .notTyped,
            currentBranchLabel: nil,
            templateTitle: "Claude Code"
        )
        XCTAssertEqual(segments.projectLabel, "Select project")
        XCTAssertTrue(segments.isProjectClickable)
        XCTAssertNil(segments.branchLabel, "a non-git/ineligible project must render NO branch segment, not a disabled one")
        XCTAssertEqual(segments.templateLabel, "Claude Code")
    }

    /// `.locked` project: never clickable, and falls back to "Project
    /// unavailable" (not "Select project") if the locked project can't
    /// resolve — a locked composer must never expose a live picker
    /// affordance, mirroring the deleted chip's own `.locked` rule.
    func testResolutionLineSegmentsForALockedProject() {
        let resolved = SessionComposerCommandParser.resolutionLineSegments(
            projectName: "ghostties",
            isProjectLocked: true,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            typedBranchResolution: .notTyped,
            currentBranchLabel: nil,
            templateTitle: "Claude Code"
        )
        XCTAssertEqual(resolved.projectLabel, "ghostties")
        XCTAssertFalse(resolved.isProjectClickable)

        let unresolved = SessionComposerCommandParser.resolutionLineSegments(
            projectName: nil,
            isProjectLocked: true,
            isBranchSegmentEligible: false,
            isCreatingWorktree: false,
            typedBranchResolution: .notTyped,
            currentBranchLabel: nil,
            templateTitle: nil
        )
        XCTAssertEqual(unresolved.projectLabel, "Project unavailable")
        XCTAssertFalse(unresolved.isProjectClickable)
        XCTAssertEqual(unresolved.templateLabel, "No match")
    }

    /// "Creating…" overrides whatever `currentBranchLabel` would otherwise
    /// show — mirrors the deleted branch chip's own precedence exactly.
    func testResolutionLineSegmentsShowsCreatingWhileWorktreeCreationIsInFlight() {
        let segments = SessionComposerCommandParser.resolutionLineSegments(
            projectName: "ghostties",
            isProjectLocked: false,
            isBranchSegmentEligible: true,
            isCreatingWorktree: true,
            typedBranchResolution: .notTyped,
            currentBranchLabel: "main",
            templateTitle: "cco"
        )
        XCTAssertEqual(segments.branchLabel, "Creating…")
        XCTAssertFalse(segments.branchIsError)
    }

    // MARK: - Path grammar (greedy, terminated-token walk) — checkpoint A,
    // parser only. Every test below names a real production symbol; the
    // mutation that would turn it red is noted per the plan's test table.

    /// `parsePath`, `PathParse.trailingTermRange`. Mutation: resolve the
    /// tail token anyway — `testParseSingleTokenReturnsNilProjectId` (:32)
    /// and its siblings would go red with it, since a bare single token
    /// would start resolving as a project.
    func testUnterminatedTrailingTokenNeverResolves() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghost",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertNil(result.projectId)
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertNotNil(result.trailingTermRange)
        XCTAssertEqual(text(result.trailingTermRange, in: result.source), "ghost")
    }

    /// `parsePath`, `Segment.Resolution.project`. Mutation: require two
    /// terminated tokens before resolving — `ghostties ` would stop
    /// resolving and the D3 backspace dead end (sticky chip) would return.
    func testSpaceTerminatesAndResolvesTheProject() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties ",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.segments.first?.resolved, .project(project.id))
        XCTAssertNil(result.trailingTermRange)
    }

    /// `parsePath`, `Segment.Resolution.project`. Mutation: drop `>` from
    /// the terminator set — `ghostties>` would stop resolving, regressing
    /// the behavior `testStickyChipProjectIdTriggeredByChevronWithNoSpace`
    /// (:445) already pins for `stickyChipProjectId`.
    func testChevronAloneTerminatesAndResolvesTheProject() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties>",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.segments.first?.resolved, .project(project.id))
    }

    /// `parsePath(rawQuery:)`. Mutation: trim inside `parsePath` — the
    /// trailing-space signal vanishes and termination silently never fires,
    /// so a project resolved via a trimmed caller would stop resolving.
    func testParsePathReadsRawTextNotTrimmed() {
        let project = makeProject(name: "ghostties")
        let raw = "ghostties "
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let rawResult = SessionComposerCommandParser.parsePath(
            rawQuery: raw, projects: [project], templates: [], isLocked: false
        )
        let trimmedResult = SessionComposerCommandParser.parsePath(
            rawQuery: trimmed, projects: [project], templates: [], isLocked: false
        )
        XCTAssertEqual(rawResult.projectId, project.id, "the raw, untrimmed query must resolve")
        XCTAssertNil(trimmedResult.projectId, "the trimmed query has lost its terminator and must NOT resolve")
    }

    /// `parsePath`, `PathParse.remainderRange`. D4 (round-1 review): the
    /// original version of this test was inert — two OTHER rules (there is
    /// no second project in scope to claim, and `dev` can never become a
    /// second `.project` segment since `.project` is already filled) were
    /// already sufficient to pass it; deleting the "matching stops" rule
    /// entirely left it green. The real property this rule protects is
    /// that a LATER token cannot claim a type that's still unfilled once
    /// matching has stopped — proven here with a token (`main`) that WOULD
    /// match a real, still-open type (`.branch`, via `knownBranchNames`) if
    /// it were retried independently, but must not be, because `npm`
    /// (immediately before it) already ended matching for good.
    ///
    /// Mutation: retry every terminated token against all currently-unfilled
    /// types independently (i.e. delete the "matching stops" rule) — `main`
    /// would then claim `.branch`, and this goes red. Ran red against that
    /// mutation (removed the `openRunKind == nil` gate's exclusivity so a
    /// later token could still reach the branch-match check), confirmed
    /// green again after restoring it.
    func testGreedyMatchingStopsAtFirstUnmatchedToken() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm main ",
            projects: [project],
            templates: [],
            knownBranchNames: ["main"],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertFalse(result.segments.contains { $0.kind == .branch }, "main must not be retried as a branch once matching stopped at npm")
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm main")
    }

    /// `parsePath`, `ParseResult.remainderTokens` (via the `parse` adapter).
    /// Mutation: any regression of PR #136's merged behavior — `ghostties
    /// <command>` must still resolve as an ad-hoc command with no `>`
    /// anywhere in the query.
    func testFlatFormAdHocSurvivesGreedyRewrite() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties npm run dev", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["npm", "run", "dev"])
    }

    /// B2 (round-1 review): pins the truncation behavior for the flat,
    /// no-leading-chevron shape — there was no test on it at all, which is
    /// exactly how a later "fix" could silently walk it back. This IS the
    /// correct, intentional behavior under the greedy rewrite: `>` is
    /// grammar, not shell syntax, once any operator text is being typed —
    /// an unquoted redirect needs quoting
    /// (`testParseKeepsQuotedChevronLiteralInAdHocRemainder` covers that).
    /// See `parse`'s own doc comment for the redirect-truncation note.
    ///
    /// Mutation: disable rule 4 case 2's chevron close (`parsePath`'s
    /// `kind == .operation` branch) so a `>` never closes an open ad-hoc
    /// run — this goes red because the run keeps absorbing everything
    /// through `log.txt`, and `remainderTokens` becomes
    /// `["npm","run","build",">","log.txt"]` again (the pre-rewrite
    /// shape). Note the truncation is earned entirely inside `parsePath`
    /// (the closed segment's own range already excludes `> log.txt`); the
    /// adapter's final `tokenize` call operates on already-truncated text,
    /// so mutating ITS `separatorsIncludeChevron` flag does not affect this
    /// test at all — tried that first, confirmed it stays green under that
    /// mutation, which is why the real mutation above is the one that
    /// matters. Ran red against the `parsePath`-level mutation, confirmed
    /// green after reverting.
    func testFlatFormRedirectTruncatesAtChevron() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties npm run build > log.txt",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["npm", "run", "build"])
    }

    /// `parsePath`, `Resolution.template`. Mutation: classify a known
    /// template name as ad-hoc instead — a Run row would appear where none
    /// should exist (the template should launch directly, not shell out to
    /// a command literally named "orchestrator").
    func testKnownTemplateTokenResolvesOperatorAndLeavesNoRemainder() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")
        // Trailing space: the operator token must be TERMINATED to be
        // eligible for type-matching at all (rule 1) — an unterminated
        // trailing token can only ever become free text, never a template
        // match, regardless of what it says.
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties orchestrator ",
            projects: [project],
            templates: [template],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        guard let operatorSegment = result.segments.first(where: { $0.kind == .operation }) else {
            XCTFail("expected a resolved operator segment")
            return
        }
        XCTAssertEqual(operatorSegment.resolved, .template(template.id))
        XCTAssertEqual(operatorSegment.text(in: result.source), "orchestrator")
        XCTAssertNil(result.remainderRange)
    }

    /// `PathParse.remainderRange` — parser half of the plan's
    /// `testSingleUnterminatedTokenYieldsNoRunRow`. The `commandOptions`
    /// half of that row (whether a bare unterminated token can synthesize a
    /// Run row) lives in `SessionComposerPalette.swift`, out of this
    /// task's file fence — not exercised here. Mutation: emit a remainder
    /// for the still-being-typed trailing term instead of `nil`; a bare
    /// `cco` (no trailing space) would become runnable.
    func testSingleUnterminatedTokenYieldsNoRemainderRange() {
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "cco",
            projects: [],
            templates: [],
            isLocked: false
        )
        XCTAssertNil(result.remainderRange)
        XCTAssertNotNil(result.trailingTermRange)
    }

    /// `parsePath`, `PathParse.activeKind`. Mutation: always classify the
    /// still-open run as `.operation` — a resolved operator followed by an
    /// explicit `>` (the only route to a thread name, D5) would never reach
    /// the thread position.
    func testRemainderIsThreadWhenOperatorResolved() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "cco")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties cco > refactor the parser",
            projects: [project],
            templates: [template],
            isLocked: false
        )
        XCTAssertEqual(result.activeKind, .thread)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "refactor the parser")
    }

    /// `parsePath`, `PathParse.activeKind`. Mutation: always classify the
    /// still-open run as `.thread` — the regression that would eat PR
    /// #136's merged ad-hoc-command behavior (`ghostties <command>` with no
    /// operator ever resolved).
    func testRemainderIsAdHocWhenOperatorUnresolved() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm run dev",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.activeKind, .operation)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm run dev")
    }

    /// `parsePath`. Mutation: treat `>` as "force the operator" (the
    /// withdrawn rule) — it would not even fire here, since `cco` is
    /// unmatched and matching has already stopped by the time `>` arrives;
    /// the amendment's whole point is that this `>` still closes the
    /// already-open ad-hoc run instead of being swallowed by it.
    func testChevronClosesAdHocRunAndOpensThread() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties main cco > refactor the parser",
            projects: [project],
            templates: [],
            knownBranchNames: ["main"],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertTrue(result.segments.contains { $0.kind == .branch && $0.resolved == .branch("main") })
        let adHoc = result.segments.first { $0.kind == .operation && $0.resolved == .adHoc }
        XCTAssertEqual(adHoc.map { text($0.range, in: result.source) }, "cco")
        XCTAssertEqual(result.activeKind, .thread)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "refactor the parser")
    }

    /// `parsePath`. Mutation: treat `>` as a positional advance regardless
    /// of what's ahead of it — `main` here must NOT be swallowed into the
    /// thing after the `>`; it stays part of a still-live matching attempt
    /// (it is unmatched here on purpose, no branch list is supplied) and
    /// once `>` arrives with no run yet open, matching stops for good and
    /// the operator position opens fresh, empty, right after the `>`.
    func testChevronStopsMatchingWhenMatchingStillLive() {
        let project = makeProject(name: "ghostties")
        // `main` must resolve as branch here (matching stays "live" through
        // it) so the chevron is genuinely hit BEFORE any token has failed —
        // that's what distinguishes case 1 from case 2 above. Without a
        // branch list, `main` would fail to match anything and open an
        // ad-hoc run of its own before the chevron ever arrives (case 2's
        // territory, exercised by `testChevronClosesAdHocRunAndOpensThread`).
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties main > npm run dev",
            projects: [project],
            templates: [],
            knownBranchNames: ["main"],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertTrue(result.segments.contains { $0.kind == .branch && $0.resolved == .branch("main") })
        XCTAssertFalse(result.segments.contains { $0.kind == .operation })
        XCTAssertEqual(result.activeKind, .operation)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm run dev")
    }

    /// `Segment.range`, `Segment.text(in:)`. Mutation: derive segment text
    /// by re-joining tokens with a hardcoded separator instead of slicing
    /// `source` by range — a trailing space (or, in another test, quotes)
    /// would silently drop from a real, on-screen segment.
    /// D5 (round-1 review): renamed and strengthened. The original name
    /// promised trailing-whitespace behavior but never asserted it — a
    /// resolved segment's range excludes its trailing separator BY
    /// CONSTRUCTION (the separator is consumed but never included when a
    /// word token's raw range is recorded), so this now proves that
    /// boundary explicitly instead of only re-testing quote preservation
    /// (already covered, for the operator segment, by
    /// `testSegmentRangeKeepsQuotedArgumentQuotesIntact` below).
    ///
    /// Mutation: extend a resolved word token's range to include the
    /// separator run that terminated it (e.g. `range.length += 1` at the
    /// project-match site) — the trailing-whitespace assertion goes red
    /// (the range now reaches into the two trailing spaces), while the
    /// quote-preservation assertion would still pass, which is exactly why
    /// the original test's name was misleading. Ran red against that
    /// mutation, confirmed green after reverting.
    func testSegmentRangeKeepsQuotedProjectNameQuotesIntactAndExcludesTrailingWhitespace() {
        let project = makeProject(name: "My Project")
        let raw = "\"My Project\"  "
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: raw, projects: [project], templates: [], isLocked: false
        )
        guard let segment = result.segments.first(where: { $0.kind == .project }) else {
            XCTFail("expected a resolved project segment")
            return
        }
        // The segment's own range covers exactly the quoted token as typed —
        // verbatim, quotes included, no re-join.
        XCTAssertEqual(segment.text(in: result.source), "\"My Project\"")
        // And it stops exactly at the closing quote — the two trailing
        // spaces (the terminator) are NOT part of the segment's range.
        let rawLength = (raw as NSString).length
        XCTAssertEqual(segment.range.location + segment.range.length, rawLength - 2)
    }

    /// `Segment.range`, `Segment.text(in:)`. Mutation: strip quotes when
    /// reconstructing segment text — a quoted argument segment would lose
    /// its quotes on round trip.
    func testSegmentRangeKeepsQuotedArgumentQuotesIntact() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "npm run dev")
        // Trailing space, same reason as
        // `testKnownTemplateTokenResolvesOperatorAndLeavesNoRemainder`
        // above: the quoted token must be terminated to be eligible for a
        // template match at all.
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties \"npm run dev\" ",
            projects: [project],
            templates: [template],
            isLocked: false
        )
        guard let segment = result.segments.first(where: { $0.kind == .operation }) else {
            XCTFail("expected a resolved operator segment")
            return
        }
        XCTAssertEqual(segment.text(in: result.source), "\"npm run dev\"")
    }

    /// `parsePath`, `Segment.range`. Mutation: an off-by-one in the scanner
    /// producing an overlapping or gapped range between two settled
    /// segments.
    func testSegmentRangesAreDisjointAndCoverEveryMatchedToken() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "cco")
        // No chevrons — all three types resolve through ordinary matching,
        // so this exercises range bookkeeping across a run of settled
        // segments without also involving the free-text-run machinery.
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties main cco ",
            projects: [project],
            templates: [template],
            knownBranchNames: ["main"],
            isLocked: false
        )
        let ranges = result.segments.map { $0.range }.sorted { $0.location < $1.location }
        XCTAssertEqual(ranges.count, 3)
        for i in 1..<ranges.count {
            let previousEnd = ranges[i - 1].location + ranges[i - 1].length
            XCTAssertLessThanOrEqual(previousEnd, ranges[i].location, "segment \(i) overlaps segment \(i - 1)")
        }
        XCTAssertEqual(ranges.map { text($0, in: result.source) }, ["ghostties", "main", "cco"])
    }

    /// `PathParse.source`. Mutation: store a trimmed or normalized copy
    /// instead of `rawQuery` verbatim — every `Segment.range` becomes a
    /// stale offset into a string that no longer matches.
    func testParsePathSourceMatchesTheRawQueryItWasParsedFrom() {
        let project = makeProject(name: "ghostties")
        let raw = "  ghostties cco  "
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: raw, projects: [project], templates: [], isLocked: false
        )
        XCTAssertEqual(result.source, raw)
    }

    /// `PathParse.remainderRange`. Nit (round-1 review): renamed — the old
    /// name promised BOTH halves of "runs to end of string unless chevron
    /// closes" but only ever tested the first half, and even that half
    /// overstated its own claim: an open run runs to the end of the last
    /// WORD (`--watch`), not literally to `source`'s `endIndex` (a trailing
    /// space or two, common while live-typing, would leave a gap between
    /// the two). Now tests both halves explicitly.
    ///
    /// Mutation (no-chevron half): end the remainder at the next token
    /// boundary instead of running to the end of the last word — a
    /// multi-token ad-hoc command would truncate to its first unmatched
    /// word.
    func testRemainderRangeRunsToEndOfLastWordUnlessChevronCloses() {
        let project = makeProject(name: "ghostties")
        let openEnded = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm run dev --watch",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(text(openEnded.remainderRange, in: openEnded.source), "npm run dev --watch")

        // Chevron half: a later `>` closes the open run early — the
        // remainder must NOT keep running to the end of the string once
        // that happens. Mutation: ignore `>` while inside an operation
        // run (revert B3/rule-4-case-2's close) — this half goes red
        // since the closed segment's range would then never exist and
        // `remainderRange` would run all the way to "the parser" instead.
        let chevronClosed = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm run dev > the parser",
            projects: [project],
            templates: [],
            isLocked: false
        )
        let closedAdHoc = chevronClosed.segments.first { $0.kind == .operation && $0.resolved == .adHoc }
        XCTAssertEqual(closedAdHoc.map { text($0.range, in: chevronClosed.source) }, "npm run dev")
        XCTAssertEqual(text(chevronClosed.remainderRange, in: chevronClosed.source), "the parser")
    }

    /// B1 (round-1 review): `PathParse.activeKind`,
    /// `openedByFinalUnterminatedToken`. The blocker's own worked example —
    /// a run that predates the final, still-being-typed token must NOT
    /// have its `activeKind` overridden to "first unfilled type"; only a
    /// run OPENED BY that exact final token gets the override (see the
    /// companion `testCompletingSplicesOverTrailingTermInARealParsePathResult`
    /// for that case).
    ///
    /// Mutation: apply the B1 override unconditionally whenever the query
    /// ends in an unterminated token, instead of only when THAT token is
    /// what opened the run — this goes red because `activeKind` would
    /// report `.branch` (first unfilled) instead of `.operation`. Ran red
    /// against that mutation (dropped the `openedByFinalUnterminatedToken`
    /// gate, applying the override whenever `trailingTermRange == nil` was
    /// false), confirmed green after reverting.
    func testActiveKindStaysOperationWhenRunPredatesTheFinalToken() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties cco -n te",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.activeKind, .operation)
        // "te" lands INSIDE the run "cco" already opened — legitimate
        // in-progress ad-hoc command text, not a completable lookup
        // target, so unlike the B1 test above there is no trailing term
        // here to complete against a known list.
        XCTAssertNil(result.trailingTermRange)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "cco -n te")
    }

    /// `PathParse.activeKind`. Mutation: return `.project` (or any non-nil
    /// value) for a genuinely empty query — an empty field would render as
    /// though the first segment were already active, corrupting first-open
    /// UI state.
    func testParsePathEmptyQueryHasNilActiveKind() {
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "", projects: [], templates: [], isLocked: false
        )
        XCTAssertNil(result.activeKind)
        XCTAssertEqual(result, .none)
    }

    /// `parsePath(knownBranchNames:)`. Mutation: match a branch token
    /// against an empty list — this is exactly what keeps
    /// `testParseTreatsBareSecondTokenAsRemainderNotBranch` (:469) green:
    /// with no branch list, `main` in `ghostties main cco` can never
    /// resolve as a branch, so matching stops there instead.
    func testBranchMatchesOnlyWhenBranchListIsNonEmpty() {
        let project = makeProject(name: "ghostties")
        let withoutBranches = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties main cco",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertFalse(withoutBranches.segments.contains { $0.kind == .branch })

        let withBranches = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties main cco",
            projects: [project],
            templates: [],
            knownBranchNames: ["main"],
            isLocked: false
        )
        XCTAssertTrue(withBranches.segments.contains { $0.kind == .branch && $0.resolved == .branch("main") })
    }

    /// `completing(parse:with:)`. D6 (round-1 review): the previous version
    /// hand-built a `PathParse` with a MID-STRING `trailingTermRange`
    /// followed by real trailing content ("REST OF THE QUERY") — a state
    /// `parsePath` could never actually produce, before OR after B1: an
    /// unterminated token is by construction always the LAST token in the
    /// scan (nothing can follow it in the raw string), so "preserves
    /// whatever comes after the term" was never a reachable scenario to
    /// begin with, hand-built or not. What B1 DID make reachable for the
    /// first time is a non-nil `trailingTermRange` on anything OTHER than
    /// the whole-query single-word case — i.e. completing a LATER segment
    /// (branch, here) while a project has already resolved ahead of it.
    /// This test now exercises exactly that, through a real `parsePath`
    /// call, splicing over the real trailing term and reparsing the
    /// spliced result to confirm the branch actually resolves — the
    /// closest real analogue to "the tail survives" available: everything
    /// BEFORE the term (`"ghostties "`) must also survive the splice
    /// untouched.
    ///
    /// Mutation: rebuild the completed string from the value alone,
    /// dropping the untouched prefix before the term (`"ghostties "`) —
    /// this goes red because the reparsed project would then be nil. Ran
    /// red against that mutation (returned `value + " "` alone from
    /// `completing`, discarding `parse.source`'s prefix), confirmed green
    /// after reverting.
    func testCompletingSplicesOverTrailingTermInARealParsePathResult() {
        let project = makeProject(name: "ghostties")
        // "m" is the still-being-typed branch token — unterminated, NOT the
        // first token (project "ghostties" already resolved ahead of it) —
        // exactly the case B1 fixed `trailingTermRange` for.
        let parse = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties m", projects: [project], templates: [], isLocked: false
        )
        XCTAssertNotNil(parse.trailingTermRange, "B1: a later unterminated token must still set trailingTermRange")
        XCTAssertEqual(parse.activeKind, .branch)

        let completed = SessionComposerCommandParser.completing(parse: parse, with: "main")
        XCTAssertEqual(completed, "ghostties main ")

        let reparsed = SessionComposerCommandParser.parsePath(
            rawQuery: completed, projects: [project], templates: [], knownBranchNames: ["main"], isLocked: false
        )
        XCTAssertEqual(reparsed.projectId, project.id, "the untouched prefix before the term must survive the splice")
        XCTAssertTrue(reparsed.segments.contains { $0.kind == .branch && $0.resolved == .branch("main") })
    }

    /// `completing(parse:with:)`. Mutation: omit the trailing space after
    /// the spliced value — Tab would complete the text but the segment
    /// would never actually terminate/resolve.
    func testCompletingAppendsTerminatorSoTheSegmentResolves() {
        let source = "gho"
        let termRange = NSRange(location: 0, length: 3)
        let parse = SessionComposerCommandParser.PathParse(
            source: source, segments: [], trailingTermRange: termRange,
            activeKind: .project, remainderRange: nil, projectId: nil,
            openRunIsThreadRun: false
        )
        let result = SessionComposerCommandParser.completing(parse: parse, with: "ghostties")
        XCTAssertTrue(result.hasSuffix(" "), "the completed text must end in the terminator")
        let project = makeProject(name: "ghostties")
        let reparsed = SessionComposerCommandParser.parsePath(
            rawQuery: result, projects: [project], templates: [], isLocked: false
        )
        XCTAssertEqual(reparsed.projectId, project.id, "the completed segment must now actually resolve")
    }

    // MARK: - Round-3 review: 4 blockers/defects + round-2 fix coverage

    /// Blocker 1: a resolved operator template must reach `ParseResult` even
    /// though its remainder is empty (`ParseResult.resolvedTemplateId`'s doc
    /// comment explains why the remainder alone can't carry this). Mutation:
    /// drop `resolvedTemplateId` from `ParseResult`/`parse(query:)` (or leave
    /// it always `nil`) — this test cannot even compile against that
    /// reverted shape, and once it does compile, would read `nil` instead of
    /// `template.id`. Verified red before the fix: `ParseResult` had no such
    /// field at all.
    func testParseThreadsResolvedTemplateIdThroughParseResult() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties orchestrator > my thread",
            projects: [project],
            templates: [template],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.resolvedTemplateId, template.id)
        XCTAssertTrue(result.remainderTokens.isEmpty, "the thread name is not reported through remainderTokens")
    }

    /// Defect: a template resolved from a run the user opened with a leading
    /// `>` (`ghostties > orchestrator > mythread`) must yield the exact same
    /// thread name as the no-leading-chevron shape
    /// (`ghostties orchestrator > mythread`) — both should be "mythread",
    /// not "> mythread". Mutation: revert the post-match state in the Fix 5
    /// branch back to `openRunKind = .thread` — the leading-chevron
    /// assertion goes red (`"> mythread"` instead of `"mythread"`) while the
    /// no-leading-chevron assertion stays green, which is exactly the
    /// asymmetry the defect describes. Verified red against that reversion.
    /// Bug fix (2026-08-26): a single `>` now arms BRANCH, not operator —
    /// reaching a template-resolved operator via chevron now needs the
    /// double-chevron form (decision 2: each `>` advances exactly one
    /// slot). Rewritten from the single-chevron form, which under the new
    /// grammar tries "orchestrator" as a branch first (no branch list
    /// passed here, so it would resolve `.unresolved`, not the template) —
    /// still asserts the same "operator resolving returns matching to
    /// live, so the next `>` is a separator, not a literal" property this
    /// test exists to prove, now also asserting the operator segment
    /// itself resolved (the old test never checked that directly).
    func testChevronResolvedOperatorReturnsToLiveMatchingSoTheNextChevronIsASeparatorNotALiteral() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")

        let leadingChevron = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > > orchestrator > mythread",
            projects: [project], templates: [template], isLocked: false
        )
        let noLeadingChevron = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties orchestrator > mythread",
            projects: [project], templates: [template], isLocked: false
        )

        let operatorSegment = leadingChevron.segments.first { $0.kind == .operation }
        XCTAssertEqual(operatorSegment?.resolved, .template(template.id))
        XCTAssertEqual(text(leadingChevron.remainderRange, in: leadingChevron.source), "mythread")
        XCTAssertEqual(text(noLeadingChevron.remainderRange, in: noLeadingChevron.source), "mythread")
    }

    /// Blocker 2: `effectiveParse` must preserve the sticky project chip
    /// through an empty remainder after a trailing space/chevron — the raw,
    /// untrimmed query is what carries that termination signal. Mutation:
    /// pass `rawQuery.trimmingCharacters(in: .whitespaces)` instead of the
    /// raw `rawQuery` into the re-parse inside `effectiveParse` — this test
    /// goes red (`remainderTokens` becomes `["ghostties"]`, the project's
    /// own name swallowed as ad-hoc operator content, instead of empty).
    /// Verified red against that mutation.
    func testEffectiveParsePreservesStickyProjectChipWithEmptyRemainderAfterTrailingSpace() {
        let project = makeProject(name: "ghostties")
        // The direct, trimmed-text parse never resolves a project from a
        // single bare token — sanity check that this test genuinely
        // exercises the fallback path, not the direct one.
        let directParse = SessionComposerCommandParser.parse(
            query: "ghostties", projects: [project], isLocked: false
        )
        XCTAssertNil(directParse.projectId)

        let result = SessionComposerCommandParser.effectiveParse(
            rawQuery: "ghostties ",
            directParse: directParse,
            impliedProject: project,
            projects: [project],
            knownBranchNames: [],
            templates: [],
            isLocked: false
        )
        XCTAssertTrue(result.remainderTokens.isEmpty, "the sticky-typed project name must not become ad-hoc remainder content")
    }

    /// Blocker 3: `effectiveParse` is the single parse of record — a branch
    /// typed with NO project token at all (project already implied by the
    /// picker) must resolve `branchToken`, matching what
    /// `templateFilterQuery`/`commandOptions` already saw via the same
    /// function. Mutation: have `effectiveParse` just return `directParse`
    /// unconditionally (i.e. never re-parse against `impliedProject`) — this
    /// test goes red (`branchToken` stays `nil`, exactly the silent
    /// worktree-inheritance bug Blocker 3 describes). Verified red against
    /// that mutation.
    func testEffectiveParseResolvesBranchTokenAgainstImpliedProjectWhenNoProjectTokenWasTyped() {
        let project = makeProject(name: "ghostties")
        // Mirrors production's `commandParse`: with no real project matching
        // "main", the direct parse (no branch/template lists, no implied
        // project) never sees a branch either.
        let directParse = SessionComposerCommandParser.parse(
            query: "main cco -n test", projects: [project], isLocked: false
        )
        XCTAssertNil(directParse.branchToken)

        let result = SessionComposerCommandParser.effectiveParse(
            rawQuery: "main cco -n test",
            directParse: directParse,
            impliedProject: project,
            projects: [project],
            knownBranchNames: ["main"],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertEqual(result.remainderTokens, ["cco", "-n", "test"])
    }

    /// `effectiveParse` must return `directParse` UNCHANGED when a project
    /// token really was typed — an implied project must never override an
    /// explicitly typed one. Mutation: drop the `directParse.projectId ==
    /// nil` guard — this test goes red because the re-parse (against
    /// `otherProject`) would silently win instead.
    func testEffectiveParseLeavesADirectlyResolvedParseUntouched() {
        let project = makeProject(name: "ghostties")
        let otherProject = makeProject(name: "other")
        let directParse = SessionComposerCommandParser.parse(
            query: "ghostties cco -n test", projects: [project, otherProject], isLocked: false
        )
        XCTAssertEqual(directParse.projectId, project.id)

        let result = SessionComposerCommandParser.effectiveParse(
            rawQuery: "ghostties cco -n test",
            directParse: directParse,
            impliedProject: otherProject,
            projects: [project, otherProject],
            knownBranchNames: [],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id, "a typed project must never be overridden by an implied one")
    }

    // MARK: - Round-4 review: trailing-space blocker, typed-project defect, sticky-empty-remainder minor

    /// Defect: `SessionComposerPalette.commandParse` used to feed `parse()`
    /// the TRIMMED `query` for the typed-project shape (`"ghostties
    /// orchestrator "` — a project literally typed, not implied), while
    /// `effectiveCommandParse` fed the same function raw
    /// `composerStore.searchText` for the implied-project shape. Since
    /// `effectiveParse` returns `directParse` (i.e. `commandParse`)
    /// UNCHANGED whenever a project token was typed, the typed-project shape
    /// never got the raw-text path — this pins the exact asymmetry at the
    /// `parse()` boundary both properties read: trimming away the trailing
    /// space that terminates "orchestrator" as an operator token is what
    /// silences `resolvedTemplateId`. This test calls `parse()` directly with
    /// both a hand-trimmed and a hand-raw string — it never touches
    /// `SessionComposerPalette.commandParse`, so it is NOT a discriminator of
    /// the palette-level fix; reverting `commandParse` back to trimmed
    /// `query` leaves this test green. It pins the raw-vs-trimmed asymmetry
    /// at the `parse()` boundary itself (round-6 review, Minor 2 — a prior
    /// round's mutation claim here was wrong). Mutation: make `parse()`
    /// trim its own `query` argument internally — this test goes red because
    /// the "trimmed" and "raw" assertions would then agree instead of
    /// diverging.
    func testParseRequiresRawUntrimmedTextForTypedProjectOperatorToResolveAfterTrailingSpace() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")

        let trimmed = SessionComposerCommandParser.parse(
            query: "ghostties orchestrator", // what `query` (trimmed) would read
            projects: [project], templates: [template], isLocked: false
        )
        let raw = SessionComposerCommandParser.parse(
            query: "ghostties orchestrator ", // what `composerStore.searchText` (raw) would read
            projects: [project], templates: [template], isLocked: false
        )

        XCTAssertNil(trimmed.resolvedTemplateId, "an untrimmed trailing space is the only signal that terminates the operator token")
        XCTAssertEqual(raw.resolvedTemplateId, template.id)
    }

    /// Blocker (closest testable proxy — the actual fix is a SwiftUI
    /// `.onChange(of:)` trigger, which has no test seam in this suite; see
    /// the PR description for why). Pins the underlying invariant that makes
    /// keying the reselect trigger off the TRIMMED `query` wrong: for an
    /// IMPLIED project (already selected via the picker, not typed —
    /// `effectiveParse`'s re-parse path), `resolvedTemplateId` differs
    /// between the trimmed and raw forms of the exact same edit
    /// (`"orchestrator"` -> `"orchestrator "`), even though
    /// `.trimmingCharacters` collapses both to the same `String` and would
    /// never fire a `.onChange(of: query)` observer. This is the shape that
    /// requires `.onChange(of: composerStore.searchText)` instead: only the
    /// raw string changes on the keystroke that flips this test's assertion.
    func testEffectiveParseResolvedTemplateIdDiffersBetweenTrimmedAndRawImpliedProjectQueryAfterTrailingSpace() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")

        // Neither "orchestrator" nor "orchestrator " resolves a project on
        // its own — single bare token, matching production's `commandParse`
        // for an implied (not typed) project.
        let directParseNoSpace = SessionComposerCommandParser.parse(
            query: "orchestrator", projects: [project], isLocked: false
        )
        let directParseWithSpace = SessionComposerCommandParser.parse(
            query: "orchestrator ".trimmingCharacters(in: .whitespaces), projects: [project], isLocked: false
        )
        XCTAssertEqual(directParseNoSpace, directParseWithSpace, "sanity check: trimming collapses both edits to an identical direct parse — `query` cannot see this transition at all")

        let beforeSpace = SessionComposerCommandParser.effectiveParse(
            rawQuery: "orchestrator",
            directParse: directParseNoSpace,
            impliedProject: project,
            projects: [project],
            knownBranchNames: [],
            templates: [template],
            isLocked: false
        )
        let afterSpace = SessionComposerCommandParser.effectiveParse(
            rawQuery: "orchestrator ",
            directParse: directParseWithSpace,
            impliedProject: project,
            projects: [project],
            knownBranchNames: [],
            templates: [template],
            isLocked: false
        )

        XCTAssertNil(beforeSpace.resolvedTemplateId)
        XCTAssertEqual(afterSpace.resolvedTemplateId, template.id, "the keystroke that types the trailing space must resolve the operator — a trigger keyed off trimmed `query` would never observe this edit and `selectedIndex` would stay stale")
    }

    /// Minor: `effectiveParse`'s sticky-empty-remainder branch (project
    /// typed/implied, nothing after it yet) routed an empty string through
    /// `parse()`, which hits `parsePath`'s `guard !rawQuery.isEmpty else {
    /// return .none }` and reports `projectId: nil` — wrong for the seam
    /// documented as "the single parse of record" even though no current
    /// caller reads `.projectId` off it. Mutation: restore the unconditional
    /// `parse(query: remainderRawQuery, ...)` call (drop the empty-remainder
    /// short-circuit) — this test goes red (`projectId` reads `nil` instead
    /// of `project.id`). Verified red against that mutation.
    ///
    /// Currently UNREACHABLE from production (round-6 review, Minor 1): the
    /// guard this branch sits behind requires `directParse.projectId ==
    /// nil`, but production always calls both `parse()` (via `commandParse`)
    /// and `effectiveParse(rawQuery:)` with the SAME raw
    /// `composerStore.searchText` — so any shape `stickyChipProjectId`
    /// accepts (a terminated project token like `"ghostties "`) is already
    /// resolved by the raw `directParse` itself, and the guard's `else`
    /// short-circuits before this branch runs. This test constructs the
    /// otherwise-unreachable state directly (a trimmed `directParse` paired
    /// with an untrimmed `rawQuery`) rather than through production wiring —
    /// left in place as correct defensive behavior for if the raw/trimmed
    /// contract ever changes back, not as coverage of a live path.
    func testEffectiveParseReturnsResolvedProjectIdInStickyEmptyRemainderBranch() {
        let project = makeProject(name: "ghostties")
        let directParse = SessionComposerCommandParser.parse(
            query: "ghostties", projects: [project], isLocked: false
        )
        XCTAssertNil(directParse.projectId, "sanity check: a single bare token never resolves a project directly")

        let result = SessionComposerCommandParser.effectiveParse(
            rawQuery: "ghostties ",
            directParse: directParse,
            impliedProject: project,
            projects: [project],
            knownBranchNames: [],
            templates: [],
            isLocked: false
        )

        XCTAssertEqual(result.projectId, project.id, "a definitively resolved project must not read back as nil from the parse of record")
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    // MARK: - Round-2 fix coverage (previously zero test coverage)

    /// Fix 1: `parse(query:...)` must actually forward `knownBranchNames`/
    /// `templates` through to `parsePath` — the production bug this fixed
    /// was the caller (`SessionComposerPalette.commandParse`) not passing
    /// real per-project lists, but the contract this locks down is the
    /// adapter's own: given real lists, both a branch and a template
    /// segment must resolve through `parse()`, not just `parsePath()`
    /// directly. Mutation: stop forwarding `knownBranchNames`/`templates`
    /// inside `parse(query:...)` (e.g. always pass `[]` to `parsePath`) —
    /// this test goes red (`branchToken` nil, `resolvedTemplateId` nil).
    func testParseForwardsKnownBranchNamesAndTemplatesToParsePath() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "cco")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties main cco ",
            projects: [project],
            knownBranchNames: ["main"],
            templates: [template],
            isLocked: false
        )
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertEqual(result.resolvedTemplateId, template.id)
    }

    /// Fix 2: `openRunIsThreadRun` is derived from the run's own
    /// classification, NOT from `activeKind` — the two can disagree
    /// (`activeKind` still reports the first unfilled type for
    /// still-being-typed-token completion purposes even once the run
    /// underneath is genuinely a thread run). Mutation: derive
    /// `openRunIsThreadRun` as `activeKind == .thread` instead of
    /// `openRunKind == .thread` — this test goes red (`false` instead of
    /// `true`) since `activeKind` reports `.branch` here.
    func testOpenRunIsThreadRunReflectsGenuineThreadRunEvenWhileActiveKindStillReportsBranch() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties orchestrator te",
            projects: [project], templates: [template], isLocked: false
        )
        XCTAssertEqual(result.activeKind, .branch)
        XCTAssertTrue(result.openRunIsThreadRun, "the open run is genuinely a thread run even though activeKind still reports .branch")
    }

    /// Fix 3/4: `preResolvedProject` must skip project-name MATCHING
    /// entirely — a token that would otherwise match a real project must
    /// NOT be allowed to override the externally-fixed project. Mutation:
    /// don't pre-fill `.project` into `filled` when the project position is
    /// fixed — this test goes red (`projectId` becomes `other.id`, and a
    /// `.project` segment appears in `segments`).
    func testParsePathPreResolvedProjectSkipsProjectNameMatchingInText() {
        let project = makeProject(name: "ghostties")
        let other = makeProject(name: "other")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "other cco ",
            projects: [project, other],
            templates: [],
            isLocked: false,
            preResolvedProject: project
        )
        XCTAssertEqual(result.projectId, project.id, "preResolvedProject wins even though \"other\" would otherwise match a real project")
        XCTAssertFalse(result.segments.contains { $0.kind == .project })
    }

    /// Fix 3/4: with the project position externally fixed, even a single
    /// BARE (unterminated) first token must open a run immediately — the
    /// bare-first-token withholding exists only to protect an
    /// as-yet-unresolved PROJECT name, which doesn't apply here. Mutation:
    /// don't set `hasProcessedAnyToken = projectPositionIsFixed` up front —
    /// this test goes red (`remainderRange` becomes `nil`, matching the
    /// ordinary bare-single-word withholding this fix exists to bypass).
    func testParsePathPreResolvedProjectOpensRunImmediatelyForABareFirstToken() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "cco",
            projects: [project],
            templates: [],
            isLocked: false,
            preResolvedProject: project
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "cco")
    }

    /// Fix 5: the first content token of a run opened by an EXPLICIT `>`
    /// (rule 4, case 1) still gets one shot against the known template list
    /// before becoming ad-hoc content — `ghostties > orchestrator` must
    /// resolve the Orchestrator template, not report ad-hoc/thread text.
    /// Mutation: skip the template-match branch for a chevron-opened run
    /// (only try it for the ordinary "nothing matched" run-open path) — this
    /// test goes red (no `.operation` segment at all; the text stays an
    /// open, unresolved run).
    /// Bug fix (2026-08-26): single chevron now arms branch; reaching an
    /// operator template via chevron now needs the double-chevron form —
    /// rewritten from the single-chevron query, which under the new
    /// grammar tries "orchestrator" as a branch first and, with no branch
    /// list passed here, resolves it `.unresolved` instead.
    func testChevronOpenedOperatorRunStillResolvesAgainstKnownTemplates() {
        let project = makeProject(name: "ghostties")
        let template = makeTemplate(name: "orchestrator")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > > orchestrator ",
            projects: [project], templates: [template], isLocked: false
        )
        let operatorSegment = result.segments.first { $0.kind == .operation }
        XCTAssertEqual(operatorSegment?.resolved, .template(template.id))
    }

    // The real-usage idiom invariant (`repo cco -n "thread name"` / `repo
    // ccp`, four tests from commit `151898bbd`) moved to
    // `cli/Tests/GhosttiesCoreTests/SessionComposerCommandParserIdiomTests.swift`
    // alongside `SessionComposerCommandParser`'s move into `GhosttiesCore` —
    // `swift test` in `cli/` runs there in CI; this app-hosted target does not.
}
