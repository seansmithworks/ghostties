import Foundation
import Testing
@testable import Ghostty

/// Coverage for `CodexHookConfirmation.isHookUnconfirmed` — pure, no
/// filesystem, no `SessionCoordinator`. Every combination in the decision's
/// doc comment gets its own case (BACKLOG D2).
struct CodexHookConfirmationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func graceNotElapsedIsFalse() {
        let launchedAt = now.addingTimeInterval(-5)
        #expect(!CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: true,
            launchedAt: launchedAt,
            hasReported: false,
            now: now
        ))
    }

    @Test func elapsedAndNeverReportedIsTrue() {
        let launchedAt = now.addingTimeInterval(-CodexHookConfirmation.graceInterval - 1)
        #expect(CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: true,
            launchedAt: launchedAt,
            hasReported: false,
            now: now
        ))
    }

    @Test func reportedOnceIsFalseForever() {
        let launchedAt = now.addingTimeInterval(-CodexHookConfirmation.graceInterval - 1000)
        #expect(!CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: true,
            launchedAt: launchedAt,
            hasReported: true,
            now: now
        ))
    }

    @Test func nonCodexIsFalse() {
        let launchedAt = now.addingTimeInterval(-CodexHookConfirmation.graceInterval - 1)
        #expect(!CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: false,
            launchedAt: launchedAt,
            hasReported: false,
            now: now
        ))
    }

    @Test func noLaunchTimeIsFalse() {
        #expect(!CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: true,
            launchedAt: nil,
            hasReported: false,
            now: now
        ))
    }

    @Test func exactlyAtGraceBoundaryIsTrue() {
        let launchedAt = now.addingTimeInterval(-CodexHookConfirmation.graceInterval)
        #expect(CodexHookConfirmation.isHookUnconfirmed(
            isCodexSession: true,
            launchedAt: launchedAt,
            hasReported: false,
            now: now
        ))
    }
}
