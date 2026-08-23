import XCTest
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

    /// Path-grammar rewrite: `>` no longer means "advance to branch" through
    /// `parse`'s adapter — it closes whatever free-text run is open and
    /// advances (rule 4). With no branch list offered (`parse` never passes
    /// `knownBranchNames`), `main` matches nothing, so `ghostties > main`
    /// resolves the project and reports `main` as the ad-hoc remainder, not
    /// a branch.
    func testParseRecognizesChevronAsBranchSeparatorWithSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties > main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["main"])
    }

    func testParseRecognizesChevronAsBranchSeparatorWithoutSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties>main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["main"])
    }

    /// Path-grammar rewrite (split from the old
    /// `testParseKeepsChevronLiteralInRemainderPastBranchSegment`, which
    /// tested a now-defunct branch reading of `>`). Exercises the
    /// free-text-run rule directly against `parsePath`: the first `>`
    /// (matching still live) opens an ad-hoc run at `main`; the second `>`
    /// (run open, kind `.operation`) closes it and opens a thread run; the
    /// third `>` (run open, kind `.thread`) is swallowed as a literal
    /// character since thread is the terminal position.
    func testParsePathChevronClosesAdHocThenLiteralInsideThread() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties > main > npm run build > log.txt",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        let adHocSegments = result.segments.filter { $0.kind == .operation && $0.resolved == .adHoc }
        XCTAssertEqual(adHocSegments.map { $0.text(in: result.source) }, ["main"])
        XCTAssertEqual(result.activeKind, .thread)
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm run build > log.txt")
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

    /// `parsePath`, `PathParse.remainderRange`. Mutation: try every token
    /// independently instead of stopping at the first unmatched one — `dev`
    /// in `npm run dev` would get claimed as a project once `npm`/`run`
    /// fail, corrupting the ad-hoc command mid-string.
    func testGreedyMatchingStopsAtFirstUnmatchedToken() {
        let project = makeProject(name: "ghostties")
        let devProject = makeProject(name: "dev", rootPath: "/Users/sean/Code/dev")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm run dev",
            projects: [project, devProject],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertFalse(result.segments.contains { $0.resolved == .project(devProject.id) })
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm run dev")
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
    func testSegmentRangeRoundTripsVerbatimIncludingTrailingWhitespace() {
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

    /// `PathParse.remainderRange`. Mutation: end the remainder at the next
    /// token boundary instead of running to end-of-string — a multi-token
    /// ad-hoc command would truncate to its first unmatched word.
    func testRemainderRangeRunsToEndOfStringUnlessChevronCloses() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parsePath(
            rawQuery: "ghostties npm run dev --watch",
            projects: [project],
            templates: [],
            isLocked: false
        )
        XCTAssertEqual(text(result.remainderRange, in: result.source), "npm run dev --watch")
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

    /// `completing(parse:with:)`. Mutation: rebuild the result from the
    /// completed prefix only, dropping whatever followed the trailing term
    /// — a hand-constructed `PathParse` with a mid-string
    /// `trailingTermRange` proves the splice preserves the tail verbatim,
    /// not just the common (term-at-end) case every real `parsePath` call
    /// happens to produce.
    func testCompletingSplicesOverTrailingTermAndPreservesTheTail() {
        let source = "ghostties gho REST OF THE QUERY"
        let termRange = NSRange(location: 10, length: 3) // "gho"
        let parse = SessionComposerCommandParser.PathParse(
            source: source, segments: [], trailingTermRange: termRange,
            activeKind: .project, remainderRange: nil, projectId: nil
        )
        let result = SessionComposerCommandParser.completing(parse: parse, with: "ghostties")
        XCTAssertEqual(result, "ghostties ghostties  REST OF THE QUERY")
    }

    /// `completing(parse:with:)`. Mutation: omit the trailing space after
    /// the spliced value — Tab would complete the text but the segment
    /// would never actually terminate/resolve.
    func testCompletingAppendsTerminatorSoTheSegmentResolves() {
        let source = "gho"
        let termRange = NSRange(location: 0, length: 3)
        let parse = SessionComposerCommandParser.PathParse(
            source: source, segments: [], trailingTermRange: termRange,
            activeKind: .project, remainderRange: nil, projectId: nil
        )
        let result = SessionComposerCommandParser.completing(parse: parse, with: "ghostties")
        XCTAssertTrue(result.hasSuffix(" "), "the completed text must end in the terminator")
        let project = makeProject(name: "ghostties")
        let reparsed = SessionComposerCommandParser.parsePath(
            rawQuery: result, projects: [project], templates: [], isLocked: false
        )
        XCTAssertEqual(reparsed.projectId, project.id, "the completed segment must now actually resolve")
    }
}
