import Foundation
import XCTest
@testable import Ghostty

/// Synthetic load harness measuring the cost of PR #54's session-name-sync
/// cache-invalidation path. Results, method, and headline numbers live in
/// `docs/perf/session-name-sync-cache-load.md` — this file is the harness
/// itself, not the report.
///
/// The suspected shape: `WorkspaceStore.sessions`'s `didSet` clears
/// `sessionGroupsCache` for **every** project on every mutation — including
/// `syncSessionNameFromTitle`, the write path PR #54 added to sync the
/// Claude Code terminal title into the sidebar session name, called on a
/// real per-session cadence of roughly once every 5 seconds. This harness
/// reproduces that cadence against a realistic multi-project fixture and
/// measures two things against each other:
///
///   1. The STORE-WIDE model — the real `WorkspaceStore`, its real
///      `sessionGroupsCache`, exercised through the real
///      `syncSessionNameFromTitle` → `sessionGroups(forProject:)` path.
///   2. A PER-PROJECT counterfactual — built from the exact same pure
///      `WorkspaceStore.computeSessionGroups` static function the store
///      itself calls on a cache miss, but invalidated only for the ONE
///      project whose session was renamed, never the others. This is a real
///      measurement (not an estimate): it runs the identical work over the
///      identical mutated state, just gated by a different invalidation
///      rule implemented locally in this test file.
///
/// The delta between the two is the wall-clock and recompute-count cost
/// directly attributable to the over-broad `didSet`, isolated from the
/// (unavoidable, correct) cost of recomputing the one project that actually
/// changed.
///
/// TIME COMPRESSION: ticks are driven by `WorkspaceStore._setTestClock`
/// (`#if DEBUG` test hook), advanced in software with no real
/// `Task.sleep`/wall clock wait between ticks. The WORK performed per tick
/// (one sanitized title write + a full-sidebar redraw read against both
/// models) is byte-for-byte identical to what the real cadence would do —
/// only the wait between ticks is removed. See the results doc for the
/// exact compression factor (simulated seconds represented vs. real xctest
/// wall-clock time to run the test).
///
/// Production-code footprint: ONE new `#if DEBUG`-gated, read-only counter
/// (`WorkspaceStore._sessionGroupsRecomputeCount`) was added to
/// `WorkspaceStore.swift` so this harness can distinguish a cache hit from a
/// miss without reaching into the (rightly) private `sessionGroupsCache`
/// dictionary. It increments on the existing cache-miss path and is
/// compiled out of release builds entirely — no behavior change, no
/// non-DEBUG diff. No other production code was touched. The `didSet` under
/// test is NOT modified — this harness measures, it does not fix.
@MainActor
final class SessionNameSyncCacheLoadTests: XCTestCase {

    // MARK: - Fixture

    private let template = AgentTemplate.shell

    /// 6 projects, sized 3–8 sessions each — matches the task brief's "5–7
    /// projects, each with 3–8 sessions" and the observed shape of
    /// `.ghostties/tasks/` (a handful of concurrently-worked projects, each
    /// having accumulated several sessions over time).
    private let projectSessionCounts = [8, 7, 6, 5, 4, 3]

    private struct Fixture {
        var projects: [Project]
        var sessions: [AgentSession]
        /// One "active agent" session per project — the one the harness
        /// renames on the real cadence. 6 total, matching the "5–7
        /// concurrent agents" basis the real-world cadence estimate in the
        /// task brief is built on.
        var activeSessionIds: [UUID]
        var projectIds: [UUID]
    }

    private func makeFixture() -> Fixture {
        var projects: [Project] = []
        var sessions: [AgentSession] = []
        var activeSessionIds: [UUID] = []

        for (i, count) in projectSessionCounts.enumerated() {
            let project = Project(name: "Project \(i)", rootPath: "/tmp/project-\(i)", isPinned: true)
            projects.append(project)
            for j in 0..<count {
                let session = AgentSession(
                    name: "Session \(i)-\(j)",
                    templateId: template.id,
                    projectId: project.id,
                    sortOrder: j
                )
                sessions.append(session)
                if j == 0 {
                    // The first session in each project is the "live agent"
                    // that gets its title synced on the real cadence.
                    activeSessionIds.append(session.id)
                }
            }
        }
        return Fixture(
            projects: projects,
            sessions: sessions,
            activeSessionIds: activeSessionIds,
            projectIds: projects.map(\.id)
        )
    }

    // MARK: - Harness core

    struct RunResult {
        var ticks: Int
        var writes: Int
        var simulatedSeconds: TimeInterval
        var storeWideRecomputes: Int
        var storeWideElapsed: TimeInterval
        var perProjectRecomputes: Int
        var perProjectElapsed: TimeInterval
    }

    /// Mirrors `WorkspaceStore.cacheTTL` (private in the production type) so
    /// the counterfactual model applies the identical TTL rule. If the real
    /// constant ever changes, `sessionGroupsCacheExpiresAfterTTLWithNoMutation`
    /// in `WorkspaceStoreSectionsTests.swift` will still pin the real value —
    /// this harness's TTL is a deliberate, documented duplicate, not a
    /// silent drift risk.
    private let cacheTTL: TimeInterval = 2.0

    /// Runs the synthetic name-sync cadence for `ticks` ticks. Each tick:
    ///
    ///   1. Advances the fake clock by `tickInterval` — `5.0/6.0`s, so with 6
    ///      round-robined active sessions, EACH individual session gets its
    ///      title synced exactly once every 5 simulated seconds (the real
    ///      per-session cadence from the task brief), and the aggregate
    ///      write rate across all 6 is 1.2 writes/sec (also matching the
    ///      brief's "~1–1.4 store-wide invalidations/sec at 5–7 agents").
    ///   2. One active session (round-robin) gets a fresh, sanitizer-passing
    ///      title via `syncSessionNameFromTitle` — the exact PR #54 write
    ///      path, which trips `sessions`'s `didSet` and clears
    ///      `sessionGroupsCache` for every project, not just the written one.
    ///   3. Simulates a sidebar redraw against the STORE-WIDE model: reads
    ///      `sessionGroups(forProject:)` for every project. Worst-realistic-
    ///      case assumption: all 6 projects are pinned/expanded at once (see
    ///      results doc for why this is the right assumption to report,
    ///      and what changes if fewer are expanded).
    ///   4. Simulates the identical redraw against the PER-PROJECT
    ///      counterfactual: a local shadow cache keyed by project id, TTL'd
    ///      exactly like the real one, but invalidated ONLY for the project
    ///      whose session was just renamed. Cache misses call the store's
    ///      own pure `computeSessionGroups` over the SAME live
    ///      `store.sessions` / `store.globalIndicatorStates` data.
    func runCadence(ticks: Int) -> RunResult {
        let fixture = makeFixture()
        let store = WorkspaceStore(testingProjects: fixture.projects, testingSessions: fixture.sessions)

        let tickInterval: TimeInterval = 5.0 / 6.0
        var simulatedTime = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTestClock { simulatedTime }

        // Prime both caches once before measuring so tick 0 doesn't pay a
        // one-time cold-start cost neither model would pay in steady state.
        for id in fixture.projectIds {
            _ = store.sessionGroups(forProject: id)
        }
        var shadowCachedAt: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: fixture.projectIds.map { ($0, simulatedTime) }
        )

        var writes = 0
        var storeWideRecomputes = 0
        var storeWideElapsed: TimeInterval = 0
        var perProjectRecomputes = 0
        var perProjectElapsed: TimeInterval = 0

        for tick in 0..<ticks {
            simulatedTime = simulatedTime.addingTimeInterval(tickInterval)

            let writerIndex = tick % fixture.activeSessionIds.count
            let sessionId = fixture.activeSessionIds[writerIndex]
            let writtenProjectId = fixture.projectIds[writerIndex]
            let title = "Working on migration step \(tick) of the request pipeline"
            store.syncSessionNameFromTitle(id: sessionId, title: title)
            writes += 1

            // --- Store-wide model: the real store, the real cache. ---
            let beforeCount = store._sessionGroupsRecomputeCount
            let storeWideStart = CFAbsoluteTimeGetCurrent()
            for id in fixture.projectIds {
                _ = store.sessionGroups(forProject: id)
            }
            storeWideElapsed += CFAbsoluteTimeGetCurrent() - storeWideStart
            storeWideRecomputes += store._sessionGroupsRecomputeCount - beforeCount

            // --- Per-project counterfactual: invalidate ONLY the written project. ---
            shadowCachedAt.removeValue(forKey: writtenProjectId)
            let perProjectStart = CFAbsoluteTimeGetCurrent()
            for id in fixture.projectIds {
                let isStale = shadowCachedAt[id].map { simulatedTime.timeIntervalSince($0) >= cacheTTL } ?? true
                if isStale {
                    _ = WorkspaceStore.computeSessionGroups(
                        projectId: id,
                        sessions: store.sessions,
                        indicatorStates: store.globalIndicatorStates,
                        now: { simulatedTime }
                    )
                    shadowCachedAt[id] = simulatedTime
                    perProjectRecomputes += 1
                }
            }
            perProjectElapsed += CFAbsoluteTimeGetCurrent() - perProjectStart
        }

        return RunResult(
            ticks: ticks,
            writes: writes,
            simulatedSeconds: Double(ticks) * tickInterval,
            storeWideRecomputes: storeWideRecomputes,
            storeWideElapsed: storeWideElapsed,
            perProjectRecomputes: perProjectRecomputes,
            perProjectElapsed: perProjectElapsed
        )
    }

    // MARK: - Tests

    /// The headline measurement. 3600 ticks × 5/6s = 3000 simulated seconds
    /// (50 minutes of continuous 6-agent load) run back-to-back with no real
    /// sleep — see the class doc comment for the compression rationale.
    func testSessionNameSyncCadence_StoreWideVsPerProjectInvalidation() {
        let ticks = 3600
        let result = runCadence(ticks: ticks)

        let excessRecomputes = result.storeWideRecomputes - result.perProjectRecomputes
        let excessElapsed = result.storeWideElapsed - result.perProjectElapsed

        // swiftlint:disable:next line_length
        let report = """
        === Session Name Sync Cache Load — Results ===
        Simulated duration: \(result.simulatedSeconds)s over \(result.ticks) ticks (compressed — no real sleep between ticks)
        Writes (title syncs): \(result.writes)
        Store-wide model  — recomputes: \(result.storeWideRecomputes), elapsed: \(result.storeWideElapsed * 1000)ms
        Per-project model — recomputes: \(result.perProjectRecomputes), elapsed: \(result.perProjectElapsed * 1000)ms
        Excess recomputes attributable to store-wide invalidation: \(excessRecomputes)
        Excess wall-clock attributable to store-wide invalidation: \(excessElapsed * 1000)ms
        Excess recomputes per write: \(Double(excessRecomputes) / Double(result.writes))
        Excess elapsed per write: \(excessElapsed / Double(result.writes) * 1_000_000)µs
        Excess elapsed per simulated second of load: \(excessElapsed / result.simulatedSeconds * 1000)ms/s
        ===============================================
        """
        print(report)

        // `print()` output from app-hosted GhosttyTests isn't reliably captured by
        // `xcodebuild test`'s console in this environment (see
        // `general-agent-context.md` — "app-hosted GhosttyTests execution stays
        // local-Cmd+U-only"). Also write the report to a fixed, well-known path
        // so a CLI run can recover the exact numbers this run produced for
        // `docs/perf/session-name-sync-cache-load.md`. Harmless side effect —
        // this is test code, not production code, and every run simply
        // overwrites the same file with its own fresh numbers.
        let reportPath = NSTemporaryDirectory() + "session-name-sync-cache-load-results.txt"
        try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)

        // Sanity floor: store-wide invalidation can never do LESS work than
        // per-project invalidation over the same mutation sequence.
        XCTAssertGreaterThanOrEqual(result.storeWideRecomputes, result.perProjectRecomputes)
        XCTAssertEqual(result.writes, ticks)
    }

    /// Official XCTest performance baseline: the cost of ONE full-sidebar
    /// redraw (all 6 projects) immediately following one store-wide-
    /// invalidating title sync, at the fixture's realistic session-per-
    /// project shape. Xcode records this baseline automatically; a future
    /// regression (e.g. a bigger fixture, or the invalidation getting even
    /// broader) shows up as a measurable timing increase here.
    func testSessionGroupsRedrawCost_AfterStoreWideInvalidation() {
        let fixture = makeFixture()
        let store = WorkspaceStore(testingProjects: fixture.projects, testingSessions: fixture.sessions)
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTestClock { now }

        measure {
            now = now.addingTimeInterval(5)
            store.syncSessionNameFromTitle(
                id: fixture.activeSessionIds[0],
                title: "Rotating measured title \(now.timeIntervalSince1970)"
            )
            for id in fixture.projectIds {
                _ = store.sessionGroups(forProject: id)
            }
        }
    }
}
