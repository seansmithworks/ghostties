// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
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
}
