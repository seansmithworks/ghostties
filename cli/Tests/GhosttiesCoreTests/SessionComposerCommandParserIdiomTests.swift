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

    // MARK: - Defect 2: a single typed `>` must not force the next token
    // into an unresolvable branch slot when it plainly reads as the
    // command (Sean's dominant shape has no branch at all).

    /// The exact repro from Sean's report: `atlas > cco -n "test"` used to
    /// resolve `branchToken == "cco"`, which `resolveTypedBranch` then
    /// failed with `No worktree found for branch "cco"` before the commit
    /// ever reached the command. `cco` must land in `remainderTokens`
    /// instead, with no branch captured at all.
    func testChevronThenAdHocCommandResolvesAsCommandNotUnresolvedBranch() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: #"atlas > cco -n "test""#,
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken, "\"cco\" matches no known branch and must not be captured as one")
        XCTAssertEqual(result.remainderTokens, ["cco", "-n", "test"])
    }

    /// Same shape, the other half of the 95% idiom (`repo ccp`) — with an
    /// explicit `>` this time, since that's the one-chevron shape the
    /// defect actually hit.
    func testChevronThenBareCommandResolvesAsCommandNotUnresolvedBranch() {
        let project = makeProject(name: "atlas", rootPath: "/Users/example/Code/atlas")
        let result = SessionComposerCommandParser.parse(
            query: "atlas > ccp",
            projects: [project],
            isLocked: false
        )
        XCTAssertEqual(result.projectId, project.id)
        XCTAssertNil(result.branchToken)
        XCTAssertEqual(result.remainderTokens, ["ccp"])
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
    /// case — a real branch with no worktree yet, where a
    /// `Create worktree for "X"` row (`typedBranchCreateOffer`) is already
    /// sitting in the result list. Retyping the SAME correct branch name
    /// reproduces the identical error. The reworded message must name that
    /// suggestion so the copy stops contradicting the row next to it.
    func testUnresolvedBranchMessageNamesTheCreateWorktreeSuggestion() {
        let message = SessionComposerCommandParser.unresolvedBranchMessage(token: "cco")
        XCTAssertTrue(
            message.lowercased().contains("create") && message.lowercased().contains("worktree"),
            "must name the create-worktree action that actually resolves the dominant reachable case"
        )
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
