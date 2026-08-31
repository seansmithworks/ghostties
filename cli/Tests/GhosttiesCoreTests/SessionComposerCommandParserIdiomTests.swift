import XCTest
@testable import GhosttiesCore

/// Real-usage idiom invariant (`repo cco -n "thread name"` / `repo ccp`).
///
/// Moved out of `macos/Tests/Ghostties/SessionComposerCommandParserTests.swift`
/// (commit `151898bbd`) so it runs under `swift test` in CI —
/// `SessionComposerCommandParser` now lives in `GhosttiesCore`
/// (`cli/Sources/GhosttiesCore/SessionComposerCommandParser.swift`), which
/// `.github/workflows/test-ghostties.yml` actually executes (`swift test
/// --parallel`); the app-hosted macOS test target is build-only in CI.
///
/// Sean's actual daily usage is `repo cco -n "thread name"` and `repo
/// ccp`, ~95% of everything typed into the composer. `-n` is `cco`'s own
/// flag — the composer must NEVER claim it for itself (e.g. to name a
/// session). These tests pin that the remainder — including `-n` and a
/// quoted multi-word argument — reaches both `ParseResult.remainderTokens`
/// AND the synthesized `AgentTemplate` (what actually launches) byte-for-
/// byte, attributed entirely to the ad-hoc command (`cco`), never
/// consumed or reinterpreted by the parser. Synthetic project name
/// (`atlas`) — this is a public repo.
final class SessionComposerCommandParserIdiomTests: XCTestCase {

    private func makeProject(name: String, rootPath: String = "/Users/sean/Code/ghostties") -> Project {
        Project(name: name, rootPath: rootPath)
    }

    func testRealIdiomCcoDashNQuotedThreadNameReachesRemainderIntact() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: #"atlas cco -n "thread name""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["cco", "-n", "thread name"])
    }

    /// The remainder above must also reach the LAUNCHED command intact —
    /// `-n` and the quoted thread name attributed to `cco` via
    /// `additionalFlags`, not folded into `command` or dropped. Calls the
    /// real production `buildCommand()` so a future per-token escaping
    /// change that mangled `-n` specifically would also be caught here.
    func testRealIdiomCcoDashNQuotedThreadNameReachesLaunchCommandIntact() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: #"atlas cco -n "thread name""#,
            projects: [project],
            isLocked: false
        )
        let template = SessionComposerCommandParser.makeAdHocTemplate(remainderTokens: result.remainderTokens)
        XCTAssertEqual(template?.command, "cco")
        XCTAssertEqual(template?.agent?.additionalFlags, ["-n", "thread name"])
        XCTAssertEqual(template?.buildCommand(), "'cco' '-n' 'thread name'")
    }

    /// `repo ccp` — the other half of the 95% idiom. A single-token
    /// remainder must still resolve the project and pass `ccp` through
    /// untouched; nothing about a bare remainder should special-case or
    /// drop it.
    func testRealIdiomCcpSingleTokenRemainderResolves() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: "atlas ccp",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.remainderTokens, ["ccp"])
    }

    /// Explicit guard: `-n` must never be treated as a composer-owned flag
    /// anywhere in the parse — not consumed into `branchToken`, not
    /// resolved as a template/operator segment, and not stripped from
    /// `remainderTokens`. `ParseResult` has no field of its own for a
    /// captured session name; if one is ever added and wired to intercept
    /// `-n`, this must be the test that goes red first.
    func testDashNIsNeverClaimedAsAComposerOwnedFlag() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: #"atlas run -n "some name""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.remainderTokens, ["run", "-n", "some name"])
        XCTAssertNil(result.branchToken, "-n must not be captured as a branch/name segment")
        XCTAssertNil(result.resolvedTemplateId, "-n must not resolve as an operator/template segment")
    }

    // MARK: - Composer variant G (Sean's ruling, 2026-08-31): a single typed
    // `>` no longer forces a special "read this as the command" carve-out —
    // a typed `>` is Sean's deliberate, formal way to declare a branch, so a
    // non-matching token in that armed position ALWAYS resolves as a
    // (failed) branch lookup now, at every chevron count. This reverses
    // defect 2's decision (`b5286319b`/`4560d9b5c`): the dead end that
    // fall-through used to avoid (`No worktree found for branch "cco"` with
    // no escape hatch) no longer exists — `SessionComposerPalette
    // .commandOptions` now offers a "Create branch" row for exactly this
    // case (`typedBranchCreateOffer`, no longer gated on
    // `branchesWithoutWorktree`), AND still surfaces the `Run "X"` ad-hoc
    // reading as a separate, independently selectable row (the view layer
    // re-prepends the consumed token — see `SessionComposerPalette
    // .commandOptions`'s `runRemainderTokens`). Both interpretations are
    // offered; neither is guessed by the parser.

    /// The exact repro from Sean's original report: `atlas > cco -n "test"`
    /// resolves `branchToken == "cco"` — an unresolved (failed) branch
    /// lookup, not a command reading. `cco` no longer lands in
    /// `remainderTokens`; only what follows it does (the view layer, not
    /// the parser, re-attaches the branch token for the `Run` row's text —
    /// see `SessionComposerPalette.commandOptions`).
    func testChevronThenNonMatchingTokenResolvesAsUnresolvedBranchNotCommand() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: #"atlas > cco -n "test""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "cco", "an armed branch position always resolves as a (failed) branch lookup now, regardless of chevron count")
        XCTAssertEqual(result.remainderTokens, ["-n", "test"], "only the text AFTER the consumed branch token remains in the parser's own remainder")
    }

    /// Same shape, the other half of the 95% idiom (`repo ccp`) — a single
    /// word after one chevron, nothing else typed.
    func testChevronThenBareNonMatchingTokenResolvesAsUnresolvedBranchNotCommand() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: "atlas > ccp",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "ccp")
        XCTAssertEqual(result.remainderTokens, [], "the whole token is consumed as the (failed) branch lookup — nothing follows it")
    }

    /// Guard against breaking the real branch case while fixing the above:
    /// a token that DOES match a known branch must still resolve as the
    /// branch, and the command after it must still land in
    /// `remainderTokens` untouched.
    func testChevronThenKnownBranchStillResolvesAsBranch() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: "atlas > some-real-branch > cco",
            projects: [project],
            knownBranchNames: ["some-real-branch"],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertEqual(result.branchToken, "some-real-branch")
        XCTAssertEqual(result.remainderTokens, ["cco"])
    }

    // MARK: - Defect 3: unresolved-branch error copy no longer points at
    // a deleted control

    /// The old copy ("Pick one from the branch picker or clear the typed
    /// branch") named a mouse control (`branchControl`) that was deleted
    /// earlier on this branch. The new copy must describe an action that
    /// still exists — typing/deleting the token — and must never mention a
    /// picker/dropdown/chevron control.
    func testUnresolvedBranchMessageNeverReferencesTheDeletedPicker() {
        let message = SessionComposerCommandParser.unresolvedBranchMessage(token: "cco")
        XCTAssertTrue(message.contains("\"cco\""))
        XCTAssertFalse(message.lowercased().contains("picker"), "must not instruct the user to use a control that no longer exists")
        XCTAssertFalse(message.lowercased().contains("dropdown"))
        XCTAssertFalse(message.lowercased().contains("chevron"))
    }

    /// Finding 2 (review round 2): the defect-3 copy ("Retype the branch or
    /// delete it") described actions that cannot fix the dominant reachable
    /// case — a real branch with no worktree yet, where a create-offer row
    /// (`typedBranchCreateOffer`) is already sitting in the result list.
    /// Retyping the SAME correct branch name reproduces the identical error.
    /// The reworded message must name that suggestion so the copy stops
    /// contradicting the row next to it.
    func testUnresolvedBranchMessageNamesTheCreateWorktreeSuggestion() {
        let message = SessionComposerCommandParser.unresolvedBranchMessage(token: "cco")
        XCTAssertTrue(
            message.lowercased().contains("create") && message.lowercased().contains("worktree"),
            "must name the create-branch/create-worktree action that actually resolves the dominant reachable case"
        )
        XCTAssertTrue(message.contains("above"), "must point in the direction the row actually renders — see testUnresolvedBranchMessagePointsAboveNotBelow")
    }

    /// Stranded-copy fix (composer variant G): the create-offer row is
    /// appended near the start of `SessionComposerPalette.commandOptions`
    /// and now ranks FIRST in `bestSelectionIndex` whenever it's offered —
    /// it always renders ABOVE this status-strip message, never below. The
    /// old copy said "below", which was wrong even before this task (the row
    /// was already above) and doubly wrong for the unknown-token class this
    /// task adds (no row existed for it at all before now).
    func testUnresolvedBranchMessagePointsAboveNotBelow() {
        let message = SessionComposerCommandParser.unresolvedBranchMessage(token: "cco")
        XCTAssertTrue(message.lowercased().contains("above"))
        XCTAssertFalse(message.lowercased().contains("below"), "the create-offer row renders above this message, never below it")
    }

    // MARK: - Coupled-literal guard (composer variant G): `unresolvedBranchMessage`
    // and `createBranchOfferTitle` are two independent functions that both
    // describe the SAME row — this pins that the message never hardcodes
    // either of the row's two possible titles verbatim, which is what would
    // let one drift out of sync with the other silently (the drift class the
    // original defect-3 consolidation existed to prevent).

    func testUnresolvedBranchMessageNeverHardcodesEitherCreateOfferTitleVerbatim() {
        let token = "cco"
        let message = SessionComposerCommandParser.unresolvedBranchMessage(token: token)
        let knownBranchTitle = SessionComposerCommandParser.createBranchOfferTitle(token: token, isKnownBranchWithoutWorktree: true)
        let unknownTokenTitle = SessionComposerCommandParser.createBranchOfferTitle(token: token, isKnownBranchWithoutWorktree: false)
        XCTAssertFalse(message.contains(knownBranchTitle), "the message must not quote the known-branch row title verbatim — it can't tell the two create-offer classes apart (see createBranchOfferTitle's doc comment)")
        XCTAssertFalse(message.contains(unknownTokenTitle), "the message must not quote the unknown-token row title verbatim either, for the same reason")
    }

    /// The known-branch case keeps its pre-existing copy.
    func testCreateBranchOfferTitleForKnownBranchWithoutWorktree() {
        XCTAssertEqual(
            SessionComposerCommandParser.createBranchOfferTitle(token: "backlog/migrate-ghostties", isKnownBranchWithoutWorktree: true),
            "Create worktree for \"backlog/migrate-ghostties\""
        )
    }

    /// The new unknown-token case gets distinct copy — creating it also
    /// creates its worktree (`GitWorktreeEnumerator.add`'s `-b` branch), but
    /// the branch is the part the user is actually deciding about.
    func testCreateBranchOfferTitleForUnknownToken() {
        XCTAssertEqual(
            SessionComposerCommandParser.createBranchOfferTitle(token: "mybrnach", isKnownBranchWithoutWorktree: false),
            "Create branch \"mybrnach\""
        )
    }

    // MARK: - Composer variant G, decision 4: an armed branch token offers a
    // create row (never a shell command) at every chevron count.

    /// The exact single-chevron example from the brief: `ghostties >
    /// mybrnach` must offer to create "mybrnach", never resolve it as a
    /// shell command — `branchToken` is set (an unresolved branch lookup)
    /// and `remainderTokens` is empty, so no ad-hoc `Run` template could ever
    /// synthesize from the parser's own remainder alone.
    func testSingleChevronUnmatchedTokenOffersCreateBranchNotCommand() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties > mybrnach", projects: [project], isLocked: false)
        XCTAssertEqual(result.branchToken, "mybrnach", "an armed, non-matching branch token must resolve as a (failed) branch lookup")
        XCTAssertTrue(result.remainderTokens.isEmpty, "nothing should be left over to read as a shell command")

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .unresolved(token: "mybrnach"), "unresolved is what SessionComposerPalette.typedBranchCreateOffer reads to show the create row")
        XCTAssertEqual(
            SessionComposerCommandParser.createBranchOfferTitle(token: "mybrnach", isKnownBranchWithoutWorktree: false),
            "Create branch \"mybrnach\""
        )
    }

    /// The two-chevron example from the brief: `ghostties > mybrnach > cco`
    /// must ALSO offer to create "mybrnach" — the second `>` advances past
    /// the unresolved branch to the operator position, so "cco" survives as
    /// the operator remainder, never absorbed into the branch's own failed
    /// lookup.
    func testTwoChevronUnmatchedTokenAlsoOffersCreateBranchNotCommand() {
        let project = makeProject(name: "ghostties")
        let result = SessionComposerCommandParser.parse(query: "ghostties > mybrnach > cco", projects: [project], isLocked: false)
        XCTAssertEqual(result.branchToken, "mybrnach")
        XCTAssertEqual(result.remainderTokens, ["cco"])

        let resolution = SessionComposerCommandParser.resolveTypedBranch(
            branchToken: result.branchToken,
            worktrees: [],
            currentBranchAtProjectRoot: "main"
        )
        XCTAssertEqual(resolution, .unresolved(token: "mybrnach"))
    }

    /// `resolveCommitWorktreePathForCommit`'s `.unresolved` failure message
    /// must be the SAME string `unresolvedBranchMessage` produces — a
    /// single source, not two literals that can drift.
    func testResolveCommitWorktreePathForCommitUsesTheSharedUnresolvedBranchMessage() {
        let result = SessionComposerCommandParser.resolveCommitWorktreePathForCommit(
            typedBranch: .unresolved(token: "cco"),
            selectedWorktreePath: nil
        )
        guard case .failure(let error) = result else {
            XCTFail("an unresolved typed branch must fail the commit")
            return
        }
        XCTAssertEqual(error.message, SessionComposerCommandParser.unresolvedBranchMessage(token: "cco"))
    }
}
