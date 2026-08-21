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
    /// Replaced with an assertion that actually discriminates: two
    /// INDEPENDENT calls must return the SAME id. Under the real
    /// production line (`id: AgentTemplate.shell.id`) that's always true.
    /// Under the `id: UUID()` mutant, two separate calls mint two
    /// different random UUIDs, so this fails hard instead of trivially
    /// passing. Manually verified: broke `makeAdHocTemplate`'s `id:`
    /// argument to `UUID()`, ran the suite, confirmed BOTH assertions in
    /// this test go red; restored the production line and confirmed green
    /// (see PR description / task report for the red/green run output).
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
    // function specifically so the rule itself has real coverage; the
    // view's job is reduced to calling it with the right two ids, which is
    // one line, not independently tested.

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
}
