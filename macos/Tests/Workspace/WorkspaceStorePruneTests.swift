import Foundation
import Testing
@testable import Ghostty

/// Tests for the launch-time stale-session prune (`pruneStaleSessionsAtLaunch()`).
///
/// Policy under test — a session is KEPT if EITHER:
///   1. `lastActiveAt` is within `WorkspaceStore.sessionRetentionWindow` (30 days).
///      A `nil` `lastActiveAt` does NOT satisfy this condition.
///   2. It ranks among the most-recent `WorkspaceStore.maxRetainedSessionsPerProject`
///      (15) sessions within its own project, by `lastActiveAt` descending (nil ranks
///      last).
/// A session is only dropped when BOTH conditions fail.
///
/// The prune only runs via the real disk-load `init()` in production, but the
/// test-only `init(testingProjects:testingSessions:)` bypasses that path entirely —
/// so these tests call `pruneStaleSessionsAtLaunch()` directly against a store built
/// via the testing initializer, with `_setTestClock(_:)` pinning "now" for
/// deterministic age math.
///
/// Coverage also includes the `nil` `lastActiveAt` path (sessions that predate
/// the timestamp feature — always fails condition 1, ranks last in condition
/// 2's per-project cap), the tie-break rule when multiple sessions share an
/// identical `lastActiveAt`, and the exact `<=` boundary of
/// `sessionRetentionWindow`.
struct WorkspaceStorePruneTests {
    // MARK: - Fixtures

    private let template = AgentTemplate.shell

    private func makeProject(id: UUID = UUID(), name: String = "Proj") -> Project {
        Project(id: id, name: name, rootPath: "/tmp/\(name)", isPinned: false)
    }

    private func makeSession(
        id: UUID = UUID(),
        name: String = "Session",
        projectId: UUID,
        lastActiveAt: Date?
    ) -> AgentSession {
        AgentSession(
            id: id,
            name: name,
            templateId: template.id,
            projectId: projectId,
            lastActiveAt: lastActiveAt
        )
    }

    // MARK: - Tests

    /// 1. Beyond-15-and-stale sessions get pruned: 20 sessions in one project, all
    /// 40 days old (stale — fails condition 1), spread by minutes so the recency
    /// ranking is unambiguous. Only the 15 most-recent (by `lastActiveAt`) survive
    /// condition 2's per-project cap; the other 5 are dropped.
    @MainActor
    @Test func beyondCapAndStaleSessionsArePruned() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        // Oldest session first, most recent last: index 0 is 40 days + 19 minutes
        // ago, index 19 is 40 days ago exactly. Ranking descending by lastActiveAt
        // puts index 19 first (most recent), index 0 last (least recent).
        let sessions = (0..<20).map { i in
            makeSession(
                name: "S\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-40 * 24 * 60 * 60 - Double(19 - i) * 60)
            )
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.count == 15)
        // The 15 most-recent by lastActiveAt (indices 5...19) must survive; the 5
        // oldest (indices 0...4) must be dropped.
        let keptNames = Set(store.sessions.map(\.name))
        let expectedKept = Set((5..<20).map { "S\($0)" })
        #expect(keptNames == expectedKept)
    }

    /// 2. All-recent sessions are never pruned even if the project has >15 of them:
    /// condition 1 alone (30-day window) saves every one regardless of the 15-cap.
    @MainActor
    @Test func allRecentSessionsSurviveEvenBeyondCap() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let sessions = (0..<20).map { i in
            makeSession(
                name: "S\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-5 * 24 * 60 * 60)
            )
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.count == 20)
    }

    /// 3. A single very-stale project with exactly the cap or fewer is untouched:
    /// 10 sessions, all 60 days old — condition 2 alone (top-15 == all 10, since
    /// there are fewer than 15) keeps all of them.
    @MainActor
    @Test func staleProjectAtOrUnderCapIsUntouched() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let sessions = (0..<10).map { i in
            makeSession(
                name: "S\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-60 * 24 * 60 * 60 - Double(i) * 60)
            )
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.count == 10)
    }

    /// 4. Cross-project independence: project A has 20 stale (60-day) sessions,
    /// project B has 3 stale (60-day) sessions. A's per-project ranking must not be
    /// affected by B's sessions and vice versa — A drops to 15, B's 3 are untouched.
    @MainActor
    @Test func pruningIsIndependentPerProject() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let sessionsA = (0..<20).map { i in
            makeSession(
                name: "A\(i)",
                projectId: projectA.id,
                lastActiveAt: now.addingTimeInterval(-60 * 24 * 60 * 60 - Double(19 - i) * 60)
            )
        }
        let sessionsB = (0..<3).map { i in
            makeSession(
                name: "B\(i)",
                projectId: projectB.id,
                lastActiveAt: now.addingTimeInterval(-60 * 24 * 60 * 60 - Double(2 - i) * 60)
            )
        }
        let store = WorkspaceStore(
            testingProjects: [projectA, projectB],
            testingSessions: sessionsA + sessionsB
        )
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        let remainingA = store.sessions.filter { $0.projectId == projectA.id }
        let remainingB = store.sessions.filter { $0.projectId == projectB.id }
        #expect(remainingA.count == 15)
        #expect(remainingB.count == 3)
    }

    /// 5. No-op guard: nothing qualifies for pruning (a small set of recent
    /// sessions), so `sessions` must be unchanged after the call — same count and
    /// same ids, in the same order. This is the observable evidence for the
    /// "skip the assignment/write when nothing would be pruned" guard; the disk
    /// write itself isn't observable here because the testing initializer always
    /// sets `persistenceDisabled = true` regardless of the guard.
    @MainActor
    @Test func noOpWhenNothingQualifiesForPruning() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let sessions = (0..<3).map { i in
            makeSession(
                name: "S\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-Double(i) * 60)
            )
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }
        let idsBefore = store.sessions.map(\.id)

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.map(\.id) == idsBefore)
        #expect(store.sessions.count == sessions.count)
    }

    // MARK: - Nil `lastActiveAt` (sessions predating the timestamp feature)

    /// 6. All-nil sessions in a project respect the cap deterministically: 20
    /// sessions, every one with `lastActiveAt: nil` (always fails condition 1),
    /// so the cap ranking is decided entirely by the tie-break (original array
    /// index ascending, since there are no dates to differentiate). The first
    /// 15 sessions in original array order survive; the last 5 are dropped.
    @MainActor
    @Test func allNilLastActiveAtSessionsKeepFirstFifteenByOriginalOrder() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let sessions = (0..<20).map { i in
            makeSession(name: "S\(i)", projectId: project.id, lastActiveAt: nil)
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.count == 15)
        let keptNames = Set(store.sessions.map(\.name))
        let expectedKept = Set((0..<15).map { "S\($0)" })
        #expect(keptNames == expectedKept)
    }

    /// 7. A mix of nil and recent-dated sessions in one project (>15 total)
    /// ranks/prunes as intended: a concrete date always ranks ahead of nil
    /// (see the `(_?, nil): return true` branch in the cap comparator), so the
    /// 3 dated sessions occupy the top of the per-project cap ranking, and the
    /// 17 nil sessions fill the remaining cap slots in original array order.
    /// The dated sessions here are also RECENT (within the 30-day retention
    /// window), so condition 1 keeps them independently too — proving the
    /// final kept set matches the cap ranking exactly, whichever condition is
    /// responsible.
    @MainActor
    @Test func mixedNilAndRecentDatedSessionsRankDatedAheadOfNilByIndex() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let dated = (0..<3).map { i in
            makeSession(
                name: "D\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-Double(i + 1) * 24 * 60 * 60)
            )
        }
        let nilSessions = (0..<17).map { i in
            makeSession(name: "N\(i)", projectId: project.id, lastActiveAt: nil)
        }
        let store = WorkspaceStore(
            testingProjects: [project],
            testingSessions: dated + nilSessions
        )
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        // Cap ranking: all 3 dated sessions first, then nil sessions in
        // original array order. Top 15 = the 3 dated + the first 12 nil
        // sessions (N0...N11); the remaining 5 nil sessions (N12...N16) are
        // dropped.
        #expect(store.sessions.count == 15)
        let keptNames = Set(store.sessions.map(\.name))
        let expectedKept = Set(["D0", "D1", "D2"]).union((0..<12).map { "N\($0)" })
        #expect(keptNames == expectedKept)
    }

    // MARK: - Boundary Conditions

    /// 8. Identical `lastActiveAt` timestamps across a >15-session project
    /// break ties deterministically by original array index. All 20 sessions
    /// here share the exact same stale (60-day-old) timestamp — condition 1
    /// fails for every one of them, so the cap ranking is decided entirely by
    /// the index tie-break, not by date. The first 15 by original order
    /// survive; the last 5 are dropped.
    @MainActor
    @Test func identicalLastActiveAtTimestampsBreakTiesByOriginalIndex() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let staleDate = now.addingTimeInterval(-60 * 24 * 60 * 60)
        let sessions = (0..<20).map { i in
            makeSession(name: "S\(i)", projectId: project.id, lastActiveAt: staleDate)
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.count == 15)
        let keptNames = Set(store.sessions.map(\.name))
        let expectedKept = Set((0..<15).map { "S\($0)" })
        #expect(keptNames == expectedKept)
    }

    /// 9. A session whose `lastActiveAt` is EXACTLY `now - sessionRetentionWindow`
    /// (30 days to the second) is kept — condition 1's boundary is inclusive
    /// (`<=`). The 15 filler sessions here are all more recent, so they occupy
    /// every slot of the per-project cap ahead of the boundary session, which
    /// therefore ranks 16th (last) and fails condition 2 entirely. Its
    /// survival can only come from condition 1's `<=` comparison landing
    /// exactly on the boundary — this test exercises that exact-equality case,
    /// which none of the other tests above (all comfortably inside or outside
    /// the window) touch.
    @MainActor
    @Test func sessionExactlyAtRetentionWindowBoundaryIsKeptDespiteFailingCap() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = makeProject()
        let fillers = (0..<WorkspaceStore.maxRetainedSessionsPerProject).map { i in
            makeSession(
                name: "Filler\(i)",
                projectId: project.id,
                lastActiveAt: now.addingTimeInterval(-Double(i + 1) * 60)
            )
        }
        let boundary = makeSession(
            name: "Boundary",
            projectId: project.id,
            lastActiveAt: now.addingTimeInterval(-WorkspaceStore.sessionRetentionWindow)
        )
        let store = WorkspaceStore(
            testingProjects: [project],
            testingSessions: fillers + [boundary]
        )
        store._setTestClock { now }

        store.pruneStaleSessionsAtLaunch()

        #expect(store.sessions.contains(where: { $0.id == boundary.id }))
    }
}
