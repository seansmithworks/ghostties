import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Tests for `WorkspaceStore.updateResume(id:resume:)`, the write side of
/// `AgentSession.resume` — called from `ClaudeStateStore.refresh()`, but
/// exercised here directly against a test-only `WorkspaceStore` so no test
/// touches the real `~/.ghostties/state/` or `workspace.json`.
@MainActor
struct WorkspaceStoreResumeTests {
    private func makeSession(name: String = "a") -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: UUID())
    }

    private func makeResume(sessionId: String = "claude-1") -> AgentResume {
        AgentResume(agent: .claude, sessionId: sessionId, transcriptPath: "/tmp/t.jsonl", cwd: "/tmp", launcher: "cco")
    }

    @Test func updateResumeWritesTheRecord() {
        let s = makeSession()
        let store = WorkspaceStore(testingSessions: [s])
        let resume = makeResume()

        store.updateResume(id: s.id, resume: resume)

        #expect(store.sessions.first(where: { $0.id == s.id })?.resume == resume)
    }

    @Test func updateResumeReplacesOnSessionIdChange() {
        let s = makeSession()
        let store = WorkspaceStore(testingSessions: [s])
        store.updateResume(id: s.id, resume: makeResume(sessionId: "claude-1"))

        // A Claude /clear or /new reports a fresh session_id in the next
        // hook event — the stored record must be replaced, not merged.
        let replacement = makeResume(sessionId: "claude-2")
        store.updateResume(id: s.id, resume: replacement)

        #expect(store.sessions.first(where: { $0.id == s.id })?.resume == replacement)
    }

    @Test func updateResumeIsANoOpForAnUnknownSessionId() {
        let store = WorkspaceStore(testingSessions: [])
        // Must not crash when the session isn't present.
        store.updateResume(id: UUID(), resume: makeResume())
        #expect(store.sessions.isEmpty)
    }

    /// `ClaudeStateStore.removeState(for:)` deletes the hook status files
    /// and its own in-memory `states` cache — it has no reference to
    /// `WorkspaceStore` at all, so a session's resume record is
    /// structurally unable to be cleared by it. This test pins that
    /// decoupling down directly.
    @Test func resumeRecordSurvivesRemoveState() {
        let s = makeSession()
        let store = WorkspaceStore(testingSessions: [s])
        let resume = makeResume()
        store.updateResume(id: s.id, resume: resume)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceStoreResumeTests-\(UUID().uuidString)", isDirectory: true)
        let claudeStateStore = ClaudeStateStore(directoryURL: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        claudeStateStore.removeState(for: s.id)

        #expect(store.sessions.first(where: { $0.id == s.id })?.resume == resume)
    }
}
