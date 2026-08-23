import XCTest
@testable import Ghostty

/// Tests for the composer's text-forward command grammar (slice 1). Pure
/// value-type parsing — no SwiftUI, no `@MainActor` state.
final class SessionComposerCommandParserTests: XCTestCase {

    private func makeProject(name: String, rootPath: String = "/Users/sean/Code/ghostties") -> Project {
        Project(name: name, rootPath: rootPath)
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

    /// `>` as separator, with and without surrounding spaces.
    func testParseRecognizesChevronAsBranchSeparatorWithSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties > main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    func testParseRecognizesChevronAsBranchSeparatorWithoutSpaces() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties>main", projects: [project], isLocked: false)
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertTrue(result.remainderTokens.isEmpty)
    }

    /// A `>` in the command remainder (past the branch segment) must stay a
    /// literal argv word, not a further segment separator — a shell
    /// redirect must survive.
    func testParseKeepsChevronLiteralInRemainderPastBranchSegment() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(
            query: "ghostties > main > npm run build > log.txt",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.branchToken, "main")
        XCTAssertEqual(result.remainderTokens, ["npm", "run", "build", ">", "log.txt"])
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

    // MARK: - resolvedFieldSplit (should-fix 10 / blocker 1, Slice B review round 2)
    //
    // Hoisted out of `SessionComposerPalette` specifically so blocker 1 —
    // a regression in this exact function shipped by the round-1 fix —
    // has real coverage going forward.

    /// The ordinary case: project resolved, no branch typed. Only the
    /// project segment is consumed into `prefix`.
    func testResolvedFieldSplitConsumesOnlyProjectWhenNoBranchTyped() {
        let split = SessionComposerCommandParser.resolvedFieldSplit(
            searchText: "ghostties cco -n test",
            hasResolvedProject: true,
            branchToken: nil
        )
        XCTAssertEqual(split?.prefix, "ghostties ")
        XCTAssertEqual(split?.remainder, "cco -n test")
    }

    /// A resolved branch WITH a genuine remainder after it: both segments
    /// are consumed into `prefix`, and the field shows only the remainder —
    /// the original finding-15 fix this function preserves.
    func testResolvedFieldSplitConsumesBothSegmentsWhenBranchHasARemainder() {
        let split = SessionComposerCommandParser.resolvedFieldSplit(
            searchText: "ghostties > main > cco",
            hasResolvedProject: true,
            branchToken: "main"
        )
        XCTAssertEqual(split?.prefix, "ghostties > main > ")
        XCTAssertEqual(split?.remainder, "cco")
    }

    /// Blocker 1's exact repro, at the moment the trap used to spring:
    /// the branch segment's own remainder has just been backspaced to
    /// nothing (`"ghostties > mian "` — typo intentional, matches the task
    /// repro). The branch token must NOT be folded into `prefix` here — it
    /// must still be part of the visible, editable `remainder`, or it
    /// becomes unreachable (no macOS-13-safe route back into a hidden
    /// prefix).
    func testResolvedFieldSplitKeepsBranchTokenLiveWhenItsOwnRemainderIsEmpty() {
        let split = SessionComposerCommandParser.resolvedFieldSplit(
            searchText: "ghostties > mian ",
            hasResolvedProject: true,
            branchToken: "mian"
        )
        XCTAssertEqual(split?.prefix, "ghostties > ")
        XCTAssertEqual(split?.remainder, "mian ", "the typed branch token must stay in the EDITABLE remainder, not vanish into the hidden prefix")
    }

    /// Same case with no trailing separator at all — the branch token was
    /// just typed and nothing follows it yet.
    func testResolvedFieldSplitKeepsBranchTokenLiveWithNoTrailingSeparator() {
        let split = SessionComposerCommandParser.resolvedFieldSplit(
            searchText: "ghostties > main",
            hasResolvedProject: true,
            branchToken: "main"
        )
        XCTAssertEqual(split?.prefix, "ghostties > ")
        XCTAssertEqual(split?.remainder, "main")
    }

    /// Continuing to backspace the now-live branch token must keep working
    /// via ordinary field editing — each character removed reproduces the
    /// same "keep it live" split, all the way down to empty.
    func testResolvedFieldSplitKeepsWorkingAsTheBranchTokenIsBackspacedToNothing() {
        for partial in ["mia", "mi", "m", ""] {
            let searchText = "ghostties > \(partial)"
            let split = SessionComposerCommandParser.resolvedFieldSplit(
                searchText: searchText,
                hasResolvedProject: true,
                branchToken: partial.isEmpty ? nil : partial
            )
            if partial.isEmpty {
                // No branch token left at all once the last character is
                // gone — only the project segment is consumed.
                XCTAssertEqual(split?.prefix, "ghostties > ")
                XCTAssertEqual(split?.remainder, "")
            } else {
                XCTAssertEqual(split?.prefix, "ghostties > ", "partial = \(partial)")
                XCTAssertEqual(split?.remainder, partial, "partial = \(partial)")
            }
        }
    }

    /// No resolved project at all — the whole string is the remainder,
    /// nothing is consumed.
    func testResolvedFieldSplitReturnsNilWithNoResolvedProject() {
        let split = SessionComposerCommandParser.resolvedFieldSplit(
            searchText: "ghostties cco",
            hasResolvedProject: false,
            branchToken: nil
        )
        XCTAssertNil(split)
    }
}
