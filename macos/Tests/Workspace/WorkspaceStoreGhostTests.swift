import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Tests for per-session/per-project ghost assignment:
///   - Launch-time backfill of legacy (`ghostCharacter == nil`) sessions (FIX 2)
///   - Uniqueness on `addSession`, including the unified project+session pool (FIX 4)
///   - Graceful degradation past the 24-ghost ceiling (FIX 11)
///
/// Like `WorkspaceStorePruneTests`, these use the test-only
/// `init(testingProjects:testingSessions:)` initializer and call the
/// launch-only methods directly, since the real backfill/prune only run via
/// the disk-load `init()` in production.
struct WorkspaceStoreGhostTests {
    private let template = AgentTemplate.shell

    private func makeProject(id: UUID = UUID(), name: String = "Proj", ghostCharacter: GhostCharacter? = nil) -> Project {
        Project(id: id, name: name, rootPath: "/tmp/\(name)", isPinned: false, ghostCharacter: ghostCharacter)
    }

    private func makeSession(
        id: UUID = UUID(),
        name: String = "Session",
        projectId: UUID,
        ghostCharacter: GhostCharacter? = nil
    ) -> AgentSession {
        AgentSession(id: id, name: name, templateId: template.id, projectId: projectId, ghostCharacter: ghostCharacter)
    }

    // MARK: - Backfill (FIX 2)

    /// A session that predates the per-session ghost system gets a
    /// `ghostCharacter` assigned and PERSISTED by the backfill — after the
    /// call, `ghostCharacter` is no longer nil (so `resolvedGhostCharacter`
    /// no longer depends on the transient fallback at all).
    @MainActor
    @Test func backfillAssignsGhostToLegacySession() {
        let project = makeProject()
        let legacySession = makeSession(projectId: project.id, ghostCharacter: nil)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [legacySession])

        store.backfillGhostCharactersAtLaunch()

        let updated = store.sessions.first { $0.id == legacySession.id }
        #expect(updated?.ghostCharacter != nil)
    }

    /// Backfill must not reassign a session that already has a ghost.
    @MainActor
    @Test func backfillLeavesExistingGhostUntouched() {
        let project = makeProject()
        let session = makeSession(projectId: project.id, ghostCharacter: .wraith)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [session])

        store.backfillGhostCharactersAtLaunch()

        #expect(store.sessions.first?.ghostCharacter == .wraith)
    }

    /// Backfill assigns distinct ghosts to multiple legacy sessions in one
    /// pass — assignment must not repeat within a single backfill run.
    @MainActor
    @Test func backfillAssignsDistinctGhostsAcrossMultipleLegacySessions() {
        let project = makeProject()
        let legacySessions = (0..<5).map { _ in makeSession(projectId: project.id, ghostCharacter: nil) }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: legacySessions)

        store.backfillGhostCharactersAtLaunch()

        let assigned = store.sessions.compactMap(\.ghostCharacter)
        #expect(assigned.count == 5)
        #expect(Set(assigned).count == 5)
    }

    // MARK: - Uniqueness on addSession (FIX 4 unified pool)

    @MainActor
    @Test func addSessionAssignsDistinctGhostsToTwoNewSessions() {
        let project = makeProject()
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [])

        let first = store.addSession(name: "First", templateId: template.id, projectId: project.id)
        let second = store.addSession(name: "Second", templateId: template.id, projectId: project.id)

        #expect(first.ghostCharacter != nil)
        #expect(second.ghostCharacter != nil)
        #expect(first.ghostCharacter != second.ghostCharacter)
    }

    /// FIX 4: a session must never be assigned the same ghost as its own
    /// parent project — the exclusion pool is unified across both.
    @MainActor
    @Test func addSessionNeverCollidesWithParentProjectGhost() {
        let project = makeProject(ghostCharacter: .blinky)
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [])

        let session = store.addSession(name: "S", templateId: template.id, projectId: project.id)

        #expect(session.ghostCharacter != .blinky)
    }

    /// Past the 24th ghost, assignment must still be well-defined (no crash)
    /// and should not be a uniform random draw that ignores usage — every
    /// ghost already appears at least once, so `randomUnused` degrades to its
    /// least-used round-robin. This just proves it doesn't crash / always
    /// returns a valid ghost at the boundary.
    @MainActor
    @Test func addSessionAtTwentyFifthSessionStillReturnsValidGhost() {
        let project = makeProject()
        var sessions: [AgentSession] = []
        for index in 0..<24 {
            let character = GhostCharacter.allCases[index]
            sessions.append(makeSession(name: "s\(index)", projectId: project.id, ghostCharacter: character))
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)

        let twentyFifth = store.addSession(name: "25th", templateId: template.id, projectId: project.id)

        #expect(twentyFifth.ghostCharacter != nil)
    }

    // MARK: - Least-Used Round Robin (FIX 11)

    /// Once every ghost is used at least once, `randomUnused` must pick the
    /// least-used one deterministically rather than a uniform random pick
    /// over all 24 (which would include visible duplicates and never improve).
    @Test func randomUnusedDegradesToLeastUsedRoundRobinPastCeiling() {
        // Every ghost used once, except `.wraith`, which is used twice — so
        // every OTHER ghost is tied for least-used at count 1, and `.wraith`
        // (count 2) must never be picked.
        var used = GhostCharacter.allCases
        used.append(.wraith)

        // Feed each pick back into the multiset (as production does via
        // `allAssignedGhosts()`) so successive calls actually round-robin
        // instead of re-deriving the same tied-least-used pick every time —
        // without feeding back, `allCases.min(by:)` is deterministic and every
        // iteration returns the identical character, proving only that
        // `.wraith` is excluded, not that assignment distributes.
        var picks: [GhostCharacter] = []
        for _ in 0..<10 {
            let pick = GhostCharacter.randomUnused(excluding: used)
            #expect(pick != .wraith)
            picks.append(pick)
            used.append(pick)
        }

        #expect(Set(picks).count == picks.count, "round-robin should visit distinct ghosts, not repeat one pick")
    }
}
