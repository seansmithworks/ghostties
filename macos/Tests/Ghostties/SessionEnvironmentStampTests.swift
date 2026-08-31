// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Phase 0 of the session-row-status plan: every spawned session's
/// environment is stamped with `GHOSTTIES_SESSION_ID`, unconditionally,
/// including plain shell templates (`command == nil`) which never go
/// through the launcher-script path.
final class SessionEnvironmentStampTests: XCTestCase {

    func testShellTemplateStampsGhosttiesSessionId() {
        let id = UUID()

        let result = SessionCoordinator.spawnEnvironment(
            template: .shell,
            taskFilePath: nil,
            taskId: nil,
            extra: [:],
            sessionId: id
        )

        XCTAssertEqual(result["GHOSTTIES_SESSION_ID"], id.uuidString)
    }

    /// The `extra` overlay runs last, so an existing caller (e.g. the
    /// review-session `GHOSTTIES_TEMPLATE` override) can still win against
    /// the stamp if it explicitly sets the same key.
    func testExtraEnvironmentCanOverrideSessionIdStamp() {
        let id = UUID()

        let result = SessionCoordinator.spawnEnvironment(
            template: .shell,
            taskFilePath: nil,
            taskId: nil,
            extra: ["GHOSTTIES_SESSION_ID": "override"],
            sessionId: id
        )

        XCTAssertEqual(result["GHOSTTIES_SESSION_ID"], "override")
    }

    /// Guards against a regression where deleting the `GHOSTTIES_TASK_FILE`
    /// assignment in `spawnEnvironment` still passes the whole suite, because
    /// both existing tests use `.shell` (empty `environmentVariables`) with
    /// nil task overlays. This exercises template vars, task overlays, and
    /// the extra overlay together against the exact resulting dictionary.
    func testSpawnEnvironmentPreservesTemplateVarsTaskOverlaysAndExtra() {
        let id = UUID()
        let template = AgentTemplate(
            name: "Custom",
            kind: .shell,
            environmentVariables: ["FOO": "bar", "KEEP": "1"]
        )

        let result = SessionCoordinator.spawnEnvironment(
            template: template,
            taskFilePath: "/tmp/x.md",
            taskId: "t-1",
            extra: ["FOO": "override", "ONLY_EXTRA": "y"],
            sessionId: id
        )

        XCTAssertEqual(result["FOO"], "override")
        XCTAssertEqual(result["KEEP"], "1")
        XCTAssertEqual(result["GHOSTTIES_TASK_FILE"], "/tmp/x.md")
        XCTAssertEqual(result["GHOSTTIES_TASK_ID"], "t-1")
        XCTAssertEqual(result["ONLY_EXTRA"], "y")
        XCTAssertEqual(result["GHOSTTIES_SESSION_ID"], id.uuidString)
        XCTAssertEqual(result.count, 6)
    }
}
