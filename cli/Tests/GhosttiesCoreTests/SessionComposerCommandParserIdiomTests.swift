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
}
