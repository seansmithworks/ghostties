import Foundation
import Testing
@testable import Ghostty

/// Coverage for `lastOutputAt` — the field split out of `lastActiveAt` so
/// browsing (focus, selection, keyboard cycling) stops advancing the
/// timestamp Sessions rows and the Archive sort display. See
/// `reference_lastactiveat-written-on-focus.md`.
///
/// `WorkspaceStore.recordActivity`'s `isOutput` parameter is the single write
/// gate: `SessionCoordinator.subscribeToOutput`'s output sink is the only
/// caller that passes `isOutput: true`; every other call site (session
/// creation, `focusSession`, keyboard cycling via `focusAdjacentLiveSession`)
/// leaves it at the `false` default.
@MainActor
struct WorkspaceStoreLastOutputAtTests {
    private let template = AgentTemplate.shell

    private func makeStore(session: AgentSession, project: Project) -> WorkspaceStore {
        WorkspaceStore(testingProjects: [project], testingSessions: [session])
    }

    private func makeProject(id: UUID = UUID()) -> Project {
        Project(id: id, name: "Proj", rootPath: "/tmp/proj")
    }

    /// Focus/selection/keyboard-cycling all funnel through `recordActivity`
    /// with `isOutput` left at its `false` default (mirrors
    /// `SessionCoordinator.focusSession`/`focusAdjacentLiveSession`). This
    /// must advance `lastActiveAt` (project bucketing still needs "focus
    /// counts as a touch") but must leave `lastOutputAt` untouched.
    @Test func focusAdvancesLastActiveAtButNotLastOutputAt() {
        let project = makeProject()
        let session = AgentSession(name: "s", templateId: template.id, projectId: project.id)
        let store = makeStore(session: session, project: project)

        #expect(store.sessions[0].lastActiveAt == nil)
        #expect(store.sessions[0].lastOutputAt == nil)

        // Simulates a focus/row-click/keyboard-cycle write — isOutput left false.
        store.recordActivity(sessionId: session.id, projectId: project.id)

        #expect(store.sessions[0].lastActiveAt != nil)
        #expect(store.sessions[0].lastOutputAt == nil)
    }

    /// The real output sink (`SessionCoordinator.subscribeToOutput`) passes
    /// `isOutput: true`. That must advance both fields.
    @Test func outputAdvancesBothLastActiveAtAndLastOutputAt() {
        let project = makeProject()
        let session = AgentSession(name: "s", templateId: template.id, projectId: project.id)
        let store = makeStore(session: session, project: project)

        store.recordActivity(sessionId: session.id, projectId: project.id, isOutput: true)

        #expect(store.sessions[0].lastActiveAt != nil)
        #expect(store.sessions[0].lastOutputAt != nil)
        #expect(store.sessions[0].lastActiveAt == store.sessions[0].lastOutputAt)
    }

    /// Repro of the exact bug this ships to fix: a session that has real
    /// output history, then gets merely focused/browsed afterward. The
    /// focus write must not disturb `lastOutputAt` even though it advances
    /// `lastActiveAt` past it.
    @Test func subsequentFocusDoesNotOverwritePriorLastOutputAt() {
        let project = makeProject()
        let session = AgentSession(name: "s", templateId: template.id, projectId: project.id)
        let store = makeStore(session: session, project: project)

        let outputTime = Date(timeIntervalSince1970: 1_000_000)
        store.recordActivity(
            sessionId: session.id,
            projectId: project.id,
            isOutput: true,
            now: { outputTime }
        )
        let recordedOutputAt = store.sessions[0].lastOutputAt
        #expect(recordedOutputAt == outputTime)

        // A later focus (e.g. tabbing back to this session) — well past the
        // 5s granularity guard, isOutput left false.
        let focusTime = outputTime.addingTimeInterval(3600)
        store.recordActivity(
            sessionId: session.id,
            projectId: project.id,
            now: { focusTime }
        )

        #expect(store.sessions[0].lastActiveAt == focusTime, "focus still advances lastActiveAt")
        #expect(store.sessions[0].lastOutputAt == recordedOutputAt, "focus must not touch lastOutputAt")
    }

    /// `displayTimestamp` — the read-side used by Sessions rows and the
    /// Archive sort — must prefer `lastOutputAt` and fall back to
    /// `lastActiveAt` only when absent (the migration case for sessions
    /// persisted before this field existed).
    @Test func displayTimestampPrefersLastOutputAtFallsBackToLastActiveAt() {
        let outputAt = Date(timeIntervalSince1970: 2_000_000)
        let activeAt = Date(timeIntervalSince1970: 1_000_000)

        let withOutput = AgentSession(
            name: "withOutput", templateId: template.id, projectId: UUID(),
            lastActiveAt: activeAt, lastOutputAt: outputAt
        )
        #expect(withOutput.displayTimestamp == outputAt)

        let migratedNoOutput = AgentSession(
            name: "migrated", templateId: template.id, projectId: UUID(),
            lastActiveAt: activeAt, lastOutputAt: nil
        )
        #expect(migratedNoOutput.displayTimestamp == activeAt)

        let untouched = AgentSession(
            name: "untouched", templateId: template.id, projectId: UUID(),
            lastActiveAt: nil, lastOutputAt: nil
        )
        #expect(untouched.displayTimestamp == nil)
    }
}
