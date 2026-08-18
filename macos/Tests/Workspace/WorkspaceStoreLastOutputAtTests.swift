import Foundation
import Testing
@testable import Ghostty

/// Coverage for `lastOutputAt` — the field split out of `lastActiveAt` so
/// browsing (focus, selection, keyboard cycling) stops advancing the
/// timestamp Sessions rows and the Archive sort display. See
/// `reference_lastactiveat-written-on-focus.md`.
///
/// `WorkspaceStore.recordActivity`'s `isOutput` parameter is the write gate.
/// Two kinds of call site pass `isOutput: true`: the real output sink
/// (`SessionCoordinator.subscribeToOutput`, on an actual output-activity
/// signal — see `SessionCoordinatorOutputActivityTests`) and the two
/// session-creation sites (`createSession`/`createBrowserSession`), which
/// pass `true` to clear a stale persisted `lastOutputAt` on a fresh or
/// relaunched session. `focusSession`/keyboard cycling
/// (`focusAdjacentLiveSession`) leave it at the `false` default — browsing
/// must never advance `lastOutputAt`.
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

    /// Direct coverage of the `outputNeedsUpdate` branch in `recordActivity`
    /// (`WorkspaceStore.swift`) — the one genuinely new guard term this
    /// feature added. Sequence: output at T (both fields land at T), focus at
    /// T+6 (past the 5s granularity guard — `lastActiveAt` advances to T+6,
    /// `lastOutputAt` must NOT), output again at T+8 (only 2s past the focus
    /// write, but `lastOutputAt`'s OWN last-stored value is still T — 8s
    /// prior — so it must advance to T+8 even though `sessionNeedsUpdate`
    /// alone would say no). Without `outputNeedsUpdate` as a separate guard
    /// term (rather than folding it into `if sessionNeedsUpdate`),
    /// `lastOutputAt` would stick at T forever for any regularly-focused
    /// session, with the rest of the suite still green.
    @Test func outputNeedsUpdateAdvancesIndependentlyOfLastActiveAtGuard() {
        let project = makeProject()
        let session = AgentSession(name: "s", templateId: template.id, projectId: project.id)
        let store = makeStore(session: session, project: project)

        let t = Date(timeIntervalSince1970: 1_000_000)
        store.recordActivity(sessionId: session.id, projectId: project.id, isOutput: true, now: { t })
        #expect(store.sessions[0].lastActiveAt == t)
        #expect(store.sessions[0].lastOutputAt == t)

        let tPlus6 = t.addingTimeInterval(6)
        store.recordActivity(sessionId: session.id, projectId: project.id, now: { tPlus6 })
        #expect(store.sessions[0].lastActiveAt == tPlus6, "focus past the 5s guard must advance lastActiveAt")
        #expect(store.sessions[0].lastOutputAt == t, "focus must not touch lastOutputAt")

        let tPlus8 = t.addingTimeInterval(8)
        store.recordActivity(sessionId: session.id, projectId: project.id, isOutput: true, now: { tPlus8 })
        #expect(
            store.sessions[0].lastOutputAt == tPlus8,
            "lastOutputAt's own 8s-since-T gap must clear its guard even though lastActiveAt only moved 2s since tPlus6"
        )
        #expect(store.sessions[0].lastActiveAt == tPlus6, "lastActiveAt must NOT advance again — only 2s since tPlus6, under the 5s guard")
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
