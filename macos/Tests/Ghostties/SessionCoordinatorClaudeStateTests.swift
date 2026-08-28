// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Coverage for the Phase 2 read: `SessionCoordinator.indicatorState(for:)`
/// consulting `ClaudeStateStore.shared`, and `performActivityTick()`'s
/// `reconcileClaudeState()` clearing `processingStartTimes` on a hook
/// `idle`. Follows the injection pattern in
/// `SessionCoordinatorIndicatorCacheTests.swift`.
///
/// Seeds go into `ClaudeStateStore.shared` via the in-memory
/// `seedStateForTesting`/`clearStateForTesting` seams — never through the
/// filesystem, so these tests never touch the real `~/.ghostties/state/`.
@MainActor
final class SessionCoordinatorClaudeStateTests: XCTestCase {

    private func claudeState(
        id: UUID,
        kind: ClaudeState.Kind,
        toolName: String? = nil,
        toolUseId: String? = nil
    ) -> ClaudeState {
        ClaudeState(
            ghosttiesSessionId: id,
            claudeSessionId: "claude-test",
            cwd: "/tmp",
            state: kind,
            structuredPrompt: toolName.map { StructuredPrompt(toolName: $0, toolUseId: toolUseId) },
            updatedAt: Date()
        )
    }

    private func teardown(_ id: UUID) {
        WorkspaceStore.shared.removeSessionStatus(id: id)
        WorkspaceStore.shared.removeIndicatorState(id: id)
        ClaudeStateStore.shared.clearStateForTesting(id: id)
    }

    func testHookBusyMapsToProcessing() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        coordinator.seedRunningSessionForTesting(id: id)
        ClaudeStateStore.shared.seedStateForTesting(claudeState(id: id, kind: .busy))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)
    }

    func testHookIdleMapsToIdle() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        // Recent output would resolve to .processing under today's
        // heuristics alone — the hook idle state must win.
        coordinator.seedRunningSessionForTesting(id: id)
        ClaudeStateStore.shared.seedStateForTesting(claudeState(id: id, kind: .idle))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .idle)
    }

    func testHookNeedsInputMapsToNeedsAttention() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        coordinator.seedRunningSessionForTesting(id: id)
        ClaudeStateStore.shared.seedStateForTesting(claudeState(id: id, kind: .needsInput))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .needsAttention)
    }

    func testHookNeedsPermissionMapsToNeedsAttention() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        coordinator.seedRunningSessionForTesting(id: id)
        ClaudeStateStore.shared.seedStateForTesting(
            claudeState(id: id, kind: .needsPermission, toolName: "Write", toolUseId: nil)
        )
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .needsAttention)
    }

    /// The false-orange regression test. Without `reconcileClaudeState()`
    /// clearing `processingStartTimes` on a hook `idle`, a session that was
    /// promoted to `.longRunning` before its hook ever went `idle` would
    /// stay `.longRunning` forever, even after a fresh `busy` event.
    func testHookIdleClearsProcessingStartTime() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        // Seed a session that has been "processing" continuously for far
        // longer than the 1800s long-running threshold, as though it had
        // been promoted to .longRunning before hook coverage existed.
        coordinator.seedIndicatorStateForTesting(
            id: id,
            lastOutputSecondsAgo: 0,
            processingStartSecondsAgo: 2000
        )

        // A Stop event lands: the hook says idle.
        ClaudeStateStore.shared.seedStateForTesting(claudeState(id: id, kind: .idle))
        coordinator.runActivityTickForTesting()

        // A fresh turn starts: the hook says busy again.
        ClaudeStateStore.shared.seedStateForTesting(claudeState(id: id, kind: .busy))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(
            WorkspaceStore.shared.globalIndicatorStates[id],
            .processing,
            "processingStartTimes must be cleared on a hook idle, so a subsequent busy read is .processing, not .longRunning"
        )
    }

    /// A session with no Claude state file must behave exactly as it did
    /// before this phase: byte-identical fallback to the output-recency
    /// heuristic.
    func testSessionWithNoStateFileKeepsExistingHeuristics() {
        let id = UUID()
        let coordinator = SessionCoordinator()
        addTeardownBlock { self.teardown(id) }

        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)
    }
}
