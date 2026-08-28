// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Coverage for the Phase 2 read: `SessionCoordinator.indicatorState(for:)`
/// consulting its `claudeStateStore`, and `performActivityTick()`'s
/// `reconcileClaudeState()` clearing `processingStartTimes` on a hook
/// `idle`.
///
/// Each test in *this file*'s `SessionCoordinator` is pointed at its own
/// temp-directory `ClaudeStateStore` via `claudeStateStoreForTesting`, seeded
/// in-memory via `seedStateForTesting` — never `.shared`, which reads/writes
/// the real `~/.ghostties/state/` that live sessions are writing to right
/// now. `SessionCoordinatorIndicatorCacheTests.swift` and
/// `SessionCoordinatorIndicatorStateTests.swift` follow the same injection
/// pattern for their own `SessionCoordinator`/`WorkspaceStore` instances —
/// this comment describes this file only; check each file for its own seam.
///
/// `seedStateForTesting` mutates the store's in-memory dictionary directly;
/// it is not durable across a `refresh()`. `refresh()` does a full rebuild
/// (`states = newStates`), so if a test body ever becomes `async` and lets
/// the main runloop turn between a seed and its assertion, a watcher-driven
/// refresh of the (empty) temp directory would wipe the seed. Every test
/// here is synchronous today, so nothing preempts — keep it that way, or
/// re-seed after any awaited gap.
@MainActor
final class SessionCoordinatorClaudeStateTests: XCTestCase {

    private func makeStore() -> (store: ClaudeStateStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCoordinatorClaudeStateTests-\(UUID().uuidString)", isDirectory: true)
        return (ClaudeStateStore(directoryURL: dir), dir)
    }

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

    private func teardown(_ id: UUID, dir: URL) {
        WorkspaceStore.shared.removeSessionStatus(id: id)
        WorkspaceStore.shared.removeIndicatorState(id: id)
        try? FileManager.default.removeItem(at: dir)
    }

    func testHookBusyMapsToProcessing() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        // Deliberately no recent output seeded (unlike
        // `seedRunningSessionForTesting`): with no `lastOutputTimestamps`
        // entry, `isAtPrompt` false, and no surface title, the pre-Phase-2
        // fall-through resolves `.waiting`, not `.processing` — so this only
        // passes if the hook busy read is what actually produced
        // `.processing`.
        coordinator.seedIndicatorStateForTesting(id: id)
        store.seedStateForTesting(claudeState(id: id, kind: .busy))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)
    }

    func testHookIdleMapsToIdle() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        // Recent output would resolve to .processing under today's
        // heuristics alone — the hook idle state must win.
        coordinator.seedRunningSessionForTesting(id: id)
        store.seedStateForTesting(claudeState(id: id, kind: .idle))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .idle)
    }

    func testHookNeedsInputMapsToNeedsAttention() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        coordinator.seedRunningSessionForTesting(id: id)
        store.seedStateForTesting(claudeState(id: id, kind: .needsInput))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .needsAttention)
    }

    func testHookNeedsPermissionMapsToNeedsAttention() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        coordinator.seedRunningSessionForTesting(id: id)
        store.seedStateForTesting(
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
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        // Seed a session that has been "processing" continuously for far
        // longer than the 1800s long-running threshold, as though it had
        // been promoted to .longRunning before hook coverage existed.
        coordinator.seedIndicatorStateForTesting(
            id: id,
            lastOutputSecondsAgo: 0,
            processingStartSecondsAgo: 2000
        )

        // A Stop event lands: the hook says idle.
        store.seedStateForTesting(claudeState(id: id, kind: .idle))
        coordinator.runActivityTickForTesting()

        // A fresh turn starts: the hook says busy again.
        store.seedStateForTesting(claudeState(id: id, kind: .busy))
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
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        coordinator.seedRunningSessionForTesting(id: id)
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .processing)
    }

    /// F5: `reconcileClaudeState()`'s partner promotion inside
    /// `indicatorState(for:)` — a hook `busy` whose `processingStartTimes`
    /// entry already exceeds the long-running threshold must resolve
    /// `.longRunning`, not `.processing`. No existing test reached this:
    /// `testHookIdleClearsProcessingStartTime` clears the value on the idle
    /// tick before the busy read, and every other test above never sets
    /// `processingStartTimes` at all.
    func testHookBusyPastThresholdMapsToLongRunning() {
        let id = UUID()
        let (store, dir) = makeStore()
        let coordinator = SessionCoordinator()
        coordinator.claudeStateStoreForTesting = store
        addTeardownBlock { self.teardown(id, dir: dir) }

        // Seed a session already past the 1800s long-running threshold, with
        // no intervening idle tick to clear processingStartTimes. Deliberately
        // no recent output (`lastOutputSecondsAgo` omitted): with no
        // `lastOutputTimestamps` entry the pre-Phase-2 fall-through resolves
        // `.waiting`, not `.longRunning` — so this only passes if the hook
        // busy + past-threshold read is what actually produced
        // `.longRunning`.
        coordinator.seedIndicatorStateForTesting(
            id: id,
            processingStartSecondsAgo: 2000
        )
        store.seedStateForTesting(claudeState(id: id, kind: .busy))
        coordinator.runActivityTickForTesting()

        XCTAssertEqual(WorkspaceStore.shared.globalIndicatorStates[id], .longRunning)
    }
}
