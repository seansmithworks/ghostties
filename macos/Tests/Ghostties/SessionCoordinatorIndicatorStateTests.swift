// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for the fallback branch at the end of the `.running` case in
/// `SessionCoordinator.indicatorState(for:)`.
///
/// Root cause this guards against: `isAtPrompt` is driven exclusively by
/// `GHOSTTY_ACTION_PROMPT_READY` (OSC 133 shell-prompt marker), which
/// full-screen agent TUIs like Claude Code never emit. Before this fix, any
/// silent Claude Code session — silent for as little as 2 seconds
/// (`activityThreshold`) — permanently fell through to `.waiting`, an
/// attention-seeking state, even though nothing was actually waiting on the
/// user. The fix inverts that fallback to `.idle` for agent-kind sessions
/// only; plain shell sessions (which DO get real OSC 133 markers) keep the
/// original `.waiting` fallback unchanged.
@MainActor
final class SessionCoordinatorIndicatorStateTests: XCTestCase {

    private func makeProject() -> Project {
        Project(name: "ghostties", rootPath: "/Users/sean/Code/ghostties", isPinned: true)
    }

    /// Builds an isolated `WorkspaceStore` (never touches the real
    /// `workspace.json`) seeded with a single session on the given template,
    /// and a `SessionCoordinator` wired to look up that store instead of
    /// `WorkspaceStore.shared`. Also points the coordinator's
    /// `claudeStateStore` at its own temp directory via
    /// `claudeStateStoreForTesting` — never `.shared`, which
    /// `indicatorState(for:)` would otherwise reach against the real
    /// `~/.ghostties/state/` that live sessions are writing to right now.
    /// Follows the pattern in `SessionCoordinatorClaudeStateTests.swift`.
    /// The temp directory is torn down in `addTeardownBlock` by the caller.
    private func makeCoordinator(templateId: UUID) -> (coordinator: SessionCoordinator, sessionId: UUID, claudeStateDir: URL) {
        let project = makeProject()
        let session = AgentSession(name: "Session 1", templateId: templateId, projectId: project.id)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])
        let coordinator = SessionCoordinator()
        coordinator.agentKindLookupStoreForTesting = store
        let claudeStateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCoordinatorIndicatorStateTests-\(UUID().uuidString)", isDirectory: true)
        coordinator.claudeStateStoreForTesting = ClaudeStateStore(directoryURL: claudeStateDir)
        return (coordinator, session.id, claudeStateDir)
    }

    // MARK: - The fix

    func testAgentSessionSilentNotAtPromptNoPromptTitleIsIdle() {
        let (coordinator, sessionId, claudeStateDir) = makeCoordinator(templateId: AgentTemplate.claudeCode.id)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedIndicatorStateForTesting(id: sessionId, status: .running, isAtPrompt: false)

        XCTAssertEqual(
            coordinator.indicatorState(for: sessionId),
            .idle,
            "a silent Claude Code session with no positive evidence of needing the user must read as idle, not waiting"
        )
    }

    // MARK: - Unchanged behavior for agent sessions

    func testAgentSessionRecentOutputIsProcessing() {
        let (coordinator, sessionId, claudeStateDir) = makeCoordinator(templateId: AgentTemplate.claudeCode.id)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedIndicatorStateForTesting(
            id: sessionId,
            status: .running,
            lastOutputSecondsAgo: 0,
            processingStartSecondsAgo: 0,
            isAtPrompt: false
        )

        XCTAssertEqual(coordinator.indicatorState(for: sessionId), .processing)
    }

    func testAgentSessionSustainedOutputThirtyPlusMinutesIsLongRunning() {
        let (coordinator, sessionId, claudeStateDir) = makeCoordinator(templateId: AgentTemplate.claudeCode.id)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedIndicatorStateForTesting(
            id: sessionId,
            status: .running,
            lastOutputSecondsAgo: 0,
            processingStartSecondsAgo: 1900, // > 1800s longRunningThreshold
            isAtPrompt: false
        )

        XCTAssertEqual(coordinator.indicatorState(for: sessionId), .longRunning)
    }

    func testAgentSessionPromptShapedTitleIsNeedsAttention() {
        let (coordinator, sessionId, claudeStateDir) = makeCoordinator(templateId: AgentTemplate.claudeCode.id)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedIndicatorStateForTesting(
            id: sessionId,
            status: .running,
            isAtPrompt: false,
            lastSurfaceTitle: "Overwrite existing file?"
        )

        XCTAssertEqual(
            coordinator.indicatorState(for: sessionId),
            .needsAttention,
            "a positive prompt-shaped-title signal must still win over the new idle fallback"
        )
    }

    // MARK: - Regression guard: plain shell sessions must be untouched

    /// THE regression guard that matters most: `isAtPrompt` is a trustworthy
    /// signal for plain shell sessions (real OSC 133 markers), so a silent
    /// shell session with no prompt marker yet must keep reading exactly as
    /// it did before this fix — `.waiting` — not flip to `.idle`.
    func testShellSessionSilentNotAtPromptStaysWaitingUnchanged() {
        let (coordinator, sessionId, claudeStateDir) = makeCoordinator(templateId: AgentTemplate.shell.id)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedIndicatorStateForTesting(id: sessionId, status: .running, isAtPrompt: false)

        XCTAssertEqual(
            coordinator.indicatorState(for: sessionId),
            .waiting,
            "plain shell sessions must keep the original .waiting fallback — only agent-kind sessions change"
        )
    }
}
