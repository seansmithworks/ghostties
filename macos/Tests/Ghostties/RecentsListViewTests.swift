import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for the recents-list ordering + section-membership logic in RecentsListView.
///
/// Exercises the static `sorted(sessions:)` and `SessionBucket.membership(status:startedThisLaunch:)`
/// helpers plus `relativeLabel(_:)` — all are pure functions with no SwiftUI or AppKit dependencies.
final class RecentsListViewTests: XCTestCase {

    // MARK: - Helpers

    private func session(
        name: String,
        lastActiveAt: Date? = nil,
        lastOutputAt: Date? = nil,
        sortOrder: Int? = nil
    ) -> AgentSession {
        AgentSession(
            name: name,
            templateId: UUID(),
            projectId: UUID(),
            sortOrder: sortOrder,
            lastActiveAt: lastActiveAt,
            lastOutputAt: lastOutputAt
        )
    }

    // MARK: - Sorting (stable order — NOT recency-based)

    /// Recency (`lastActiveAt`) must NOT affect order — that was the bug (rows
    /// reshuffling under the cursor as `recordActivity` bumps the timestamp
    /// every ~5s during streaming). Position/creation order should win instead.
    func testLastActiveAtDoesNotAffectOrder() {
        let early = session(name: "early", lastActiveAt: Date(timeIntervalSinceNow: -3600))
        let middle = session(name: "middle", lastActiveAt: Date(timeIntervalSinceNow: -1800))
        let recent = session(name: "recent", lastActiveAt: Date(timeIntervalSinceNow: -60))

        // Passed in append/creation order: early, middle, recent.
        let sorted = RecentsListView.sorted(sessions: [early, middle, recent])

        XCTAssertEqual(sorted.map(\.name), ["early", "middle", "recent"])
    }

    /// FIX 3: `sortOrder` is scoped WITHIN a project and must never be used as
    /// a cross-project key — the flat Sessions tab orders by array position
    /// (append/creation order) alone, ignoring `sortOrder` entirely.
    func testSortOrderDoesNotAffectFlatOrder() {
        let a = session(name: "a", sortOrder: 2)
        let b = session(name: "b", sortOrder: 0)
        let c = session(name: "c", sortOrder: 1)

        // Passed in append/creation order: a, b, c — sortOrder (2, 0, 1) must
        // be ignored, or this would come back as b, c, a instead.
        let sorted = RecentsListView.sorted(sessions: [a, b, c])

        XCTAssertEqual(sorted.map(\.name), ["a", "b", "c"])
    }

    func testSessionsWithSortOrderDoNotComeBeforeNilSortOrder() {
        let noOrder = session(name: "noOrder", sortOrder: nil)
        let ordered = session(name: "ordered", sortOrder: 0)

        // Append order is noOrder, ordered — sortOrder must not reorder this.
        let sorted = RecentsListView.sorted(sessions: [noOrder, ordered])

        XCTAssertEqual(sorted.map(\.name), ["noOrder", "ordered"])
    }

    /// FIX 3 (the concrete bug): two sessions in DIFFERENT projects both with
    /// `sortOrder: 0` (exactly what `addSession` assigns independently per
    /// project) must not interleave — append order wins, full stop.
    func testSortOrderZeroInDifferentProjectsDoesNotInterleave() {
        let projectA = UUID()
        let projectB = UUID()
        let a1 = AgentSession(name: "A1", templateId: UUID(), projectId: projectA, sortOrder: 0)
        let b1 = AgentSession(name: "B1", templateId: UUID(), projectId: projectB, sortOrder: 0)
        let a2 = AgentSession(name: "A2", templateId: UUID(), projectId: projectA, sortOrder: 1)

        let sorted = RecentsListView.sorted(sessions: [a1, b1, a2])

        XCTAssertEqual(sorted.map(\.name), ["A1", "B1", "A2"])
    }

    /// `sorted(sessions:)` must never trap on a duplicate session id (FIX 5) —
    /// duplicate ids can appear in `workspace.json`, a file on disk written by
    /// multiple windows.
    func testSortedDoesNotTrapOnDuplicateSessionId() {
        let sharedId = UUID()
        let first = AgentSession(id: sharedId, name: "first", templateId: UUID(), projectId: UUID())
        let duplicate = AgentSession(id: sharedId, name: "duplicate", templateId: UUID(), projectId: UUID())

        let sorted = RecentsListView.sorted(sessions: [first, duplicate])

        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted.map(\.name), ["first", "duplicate"])
    }

    /// Nil `sortOrder` falls back to append/creation position (index in the
    /// passed-in array), not any other ordering.
    func testNilSortOrderFallsBackToAppendPosition() {
        let first = session(name: "first", sortOrder: nil)
        let second = session(name: "second", sortOrder: nil)
        let third = session(name: "third", sortOrder: nil)

        let sorted = RecentsListView.sorted(sessions: [first, second, third])

        XCTAssertEqual(sorted.map(\.name), ["first", "second", "third"])
    }

    func testEmptySessionListReturnsEmpty() {
        let sorted = RecentsListView.sorted(sessions: [])
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSingleSessionReturnedUnchanged() {
        let s = session(name: "only", lastActiveAt: Date())
        let sorted = RecentsListView.sorted(sessions: [s])
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.name, "only")
    }

    func testAllNilSortOrdersPreservesCount() {
        let sessions = (0..<5).map { session(name: "s\($0)", sortOrder: nil) }
        let sorted = RecentsListView.sorted(sessions: sessions)
        XCTAssertEqual(sorted.count, 5)
    }

    // MARK: - Section Membership (SessionBucket.membership — the shared rule)

    func testClosedSessionBelongsInArchiveByDefault() {
        XCTAssertEqual(SessionBucket.membership(status: nil, startedThisLaunch: false), .archive)
    }

    func testRunningStatusBelongsInActive() {
        XCTAssertEqual(SessionBucket.membership(status: .running, startedThisLaunch: false), .active)
    }

    /// FIX 6: selection must NEVER promote a session into Active. Selection
    /// isn't even a parameter to `membership` — there is no way to wire it in
    /// accidentally. Membership depends only on `status`/`startedThisLaunch`.
    func testSelectionDoesNotAffectMembership() {
        XCTAssertEqual(SessionBucket.membership(status: nil, startedThisLaunch: false), .archive)
        XCTAssertEqual(SessionBucket.membership(status: .running, startedThisLaunch: false), .active)
    }

    /// The bug this whole rewrite exists to fix: a session whose surface
    /// already closed with a non-zero exit code must NOT count as Active.
    /// The OLD rule (`SessionIndicatorState != .inactive`) read `.error` as
    /// "not inactive" even though `SessionCoordinator.handleSurfaceClose`
    /// only sets `.error` AFTER removing the surface from `sessionTrees` —
    /// leaving a closed, errored session stuck in Active forever.
    /// `SessionStatus.isAlive` is `false` for `.error`, so `membership`
    /// correctly buckets it as Inactive/Archive instead.
    func testErrorStatusDoesNotCountAsActive() {
        XCTAssertEqual(SessionBucket.membership(status: .error(exitCode: 1), startedThisLaunch: true), .inactive)
        XCTAssertEqual(SessionBucket.membership(status: .error(exitCode: 1), startedThisLaunch: false), .archive)
    }

    /// `.exited`/`.completed`/`.killed` are all terminal, non-alive statuses —
    /// each must land in Inactive (started this launch) or Archive (never
    /// started), never Active.
    func testAllTerminalStatusesDoNotCountAsActive() {
        let terminalStatuses: [SessionStatus] = [.exited, .completed, .killed, .error(exitCode: 1)]
        for status in terminalStatuses {
            XCTAssertNotEqual(
                SessionBucket.membership(status: status, startedThisLaunch: true),
                .active,
                "\(status) must not count as Active"
            )
        }
    }

    /// `membership` must be an exact partition — every `(status,
    /// startedThisLaunch)` combination resolves to exactly one bucket. Pinned
    /// here so a future case addition can't silently produce ambiguity.
    func testMembershipCoversEveryStatusExactlyOnce() {
        let statuses: [SessionStatus?] = [nil, .running, .exited, .completed, .killed, .error(exitCode: 1)]
        for status in statuses {
            for startedThisLaunch in [true, false] {
                let bucket = SessionBucket.membership(status: status, startedThisLaunch: startedThisLaunch)
                XCTAssertTrue(SessionBucket.allCases.contains(bucket))
            }
        }
    }

    // MARK: - Active/Inactive/Archive Sessions (pure helpers)

    /// Sean hit this directly: at cold launch every session has no
    /// `globalStatuses` entry yet (no live surface), Active is empty, nothing
    /// is selected, and Archive's stored preference is `false` (its default).
    /// Archive must render COLLAPSED — an empty Active section is not a
    /// reason to override the user's collapsed/expanded choice for Archive.
    /// A bare sidebar in this state is the accepted outcome; it is not this
    /// helper's job to prevent it.
    func testColdLaunchArchiveStaysCollapsedWhenActiveIsEmpty() {
        let sessions = (0..<14).map { session(name: "s\($0)") }

        let active = RecentsListView.activeSessions(from: sessions, statuses: [:])
        let inactive = RecentsListView.inactiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: [])
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: [])

        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(inactive.isEmpty)
        XCTAssertEqual(archive.count, 14)

        let archiveExpanded = RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .archive,
            sectionContainsSelectedSession: false
        )
        XCTAssertFalse(archiveExpanded, "Archive must honor the collapsed stored preference even when Active is empty")
    }

    /// FIX 6: a selected session that belongs in Archive stays in Archive
    /// (no promotion) — but its section renders expanded via the auto-expand
    /// override, so it's still visible without moving.
    func testSelectedArchiveSessionStaysInArchiveButSectionExpands() {
        let selected = session(name: "selected")
        let other = session(name: "other")
        let sessions = [selected, other]
        let statuses: [UUID: SessionStatus] = [other.id: .running]

        let active = RecentsListView.activeSessions(from: sessions, statuses: statuses)
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: [])

        XCTAssertTrue(archive.contains { $0.id == selected.id }, "selected session must stay in Archive")
        XCTAssertFalse(active.contains { $0.id == selected.id }, "selected session must NOT be promoted into Active")

        let archiveExpanded = RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .archive,
            sectionContainsSelectedSession: archive.contains { $0.id == selected.id }
        )
        XCTAssertTrue(archiveExpanded, "Archive must expand because it contains the selected session")
    }

    /// Same as above, but for the new INACTIVE section: a selected session
    /// that ran-then-stopped (started at some point this launch) stays in
    /// Inactive — no promotion into Active, no relocation into Archive — but
    /// its section force-expands so it's visible without moving. This is the
    /// exact case Sean hit: stop a running session, expect it somewhere
    /// other than Archive, and it must be reachable even if Inactive were
    /// collapsed.
    func testSelectedInactiveSessionStaysInInactiveButSectionExpands() {
        let selected = session(name: "selected")
        let other = session(name: "other")
        let sessions = [selected, other]
        let statuses: [UUID: SessionStatus] = [other.id: .running]

        let inactive = RecentsListView.inactiveSessions(
            from: sessions,
            statuses: statuses,
            sessionIdsStartedThisLaunch: [selected.id]
        )
        let archive = RecentsListView.archiveSessions(
            from: sessions,
            statuses: statuses,
            sessionIdsStartedThisLaunch: [selected.id]
        )

        XCTAssertTrue(inactive.contains { $0.id == selected.id }, "stopped-but-started-this-launch session must land in Inactive")
        XCTAssertFalse(archive.contains { $0.id == selected.id }, "must NOT be lumped into Archive")

        let inactiveExpanded = RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .inactive,
            sectionContainsSelectedSession: true
        )
        XCTAssertTrue(inactiveExpanded, "Inactive must expand because it contains the selected session")
    }

    /// The auto-expand override is render-time only — it must never depend on
    /// (or imply writing to) the stored `@AppStorage` preference. Passing a
    /// `storedPreference` of `false` still yields `true` under the override
    /// condition, proving the override doesn't require/mutate storage.
    func testEffectiveExpandedOverrideIgnoresStoredPreferenceWhenTriggered() {
        XCTAssertTrue(RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .archive,
            sectionContainsSelectedSession: true
        ))
        // No override condition met — falls through to the stored preference.
        XCTAssertFalse(RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .archive,
            sectionContainsSelectedSession: false
        ))
    }

    /// FIX (dead ACTIVE header): the selected-session override must exclude
    /// `.active`. A selected, running session lives in Active essentially
    /// all the time during normal use, so applying the override there would
    /// make the ACTIVE header collapse control permanently dead — tapping it
    /// while a session is selected must actually collapse the section, honoring
    /// the stored preference the same way as when nothing is selected.
    func testActiveSectionRespectsStoredPreferenceEvenWhenItContainsSelectedSession() {
        XCTAssertFalse(RecentsListView.effectiveExpanded(
            storedPreference: false,
            section: .active,
            sectionContainsSelectedSession: true
        ), "Active must not force-expand for the selected session — only Inactive/Archive get that override")
    }

    /// The three static buckets must be an EXACT partition: every session
    /// lands in exactly one of Active/Inactive/Archive, never zero, never
    /// two. Mixes all combinations of status x started-this-launch across a
    /// set of sessions.
    func testActiveInactiveArchivePartitionIsExact() {
        let liveNoSurface = session(name: "liveNoSurface") // active status, not tracked as started (impossible in prod but must still partition)
        let liveWithSurface = session(name: "liveWithSurface") // active, started this launch
        let stoppedWithSurface = session(name: "stoppedWithSurface") // inactive, started this launch -> Inactive
        let neverStarted = session(name: "neverStarted") // inactive, never started -> Archive
        let sessions = [liveNoSurface, liveWithSurface, stoppedWithSurface, neverStarted]

        let statuses: [UUID: SessionStatus] = [
            liveNoSurface.id: .running,
            liveWithSurface.id: .running,
            // stoppedWithSurface, neverStarted absent -> not alive.
        ]
        let sessionIdsStartedThisLaunch: Set<UUID> = [liveWithSurface.id, stoppedWithSurface.id]

        let active = RecentsListView.activeSessions(from: sessions, statuses: statuses)
        let inactive = RecentsListView.inactiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)

        for s in sessions {
            let memberships = [active, inactive, archive].filter { bucket in bucket.contains { $0.id == s.id } }
            XCTAssertEqual(memberships.count, 1, "\(s.name) must land in exactly one section, found in \(memberships.count)")
        }
        XCTAssertEqual(active.count + inactive.count + archive.count, sessions.count, "buckets must cover every session exactly once")

        XCTAssertTrue(active.contains { $0.id == liveNoSurface.id })
        XCTAssertTrue(active.contains { $0.id == liveWithSurface.id })
        XCTAssertTrue(inactive.contains { $0.id == stoppedWithSurface.id })
        XCTAssertTrue(archive.contains { $0.id == neverStarted.id })
    }

    /// The exact bug Sean hit: a session that RAN and was stopped (no live
    /// status, but was started at some point this launch) must land in
    /// INACTIVE, not ARCHIVE. This is the pure-function analog of
    /// `testStartedThenStoppedSessionLandsInInactiveNotArchive` below.
    func testStoppedButStillSurfacedSessionLandsInInactiveNotArchive() {
        let stopped = session(name: "stopped")
        let sessions = [stopped]
        let sessionIdsStartedThisLaunch: Set<UUID> = [stopped.id]

        let inactive = RecentsListView.inactiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)

        XCTAssertTrue(inactive.contains { $0.id == stopped.id }, "a stopped-but-started-this-launch session must land in Inactive")
        XCTAssertTrue(archive.isEmpty, "must not also land in Archive")
    }

    /// A session that never started this launch (restored from disk,
    /// never started) must land in ARCHIVE, not INACTIVE.
    func testNeverStartedSessionLandsInArchiveNotInactive() {
        let neverStarted = session(name: "neverStarted")
        let sessions = [neverStarted]

        let inactive = RecentsListView.inactiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: [])
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: [:], sessionIdsStartedThisLaunch: [])

        XCTAssertTrue(archive.contains { $0.id == neverStarted.id }, "a never-started session must land in Archive")
        XCTAssertTrue(inactive.isEmpty, "must not also land in Inactive")
    }

    /// Integration-level regression test for PR #108's actual bug, exercised
    /// through the real `SessionCoordinator` rather than a hand-built Set.
    ///
    /// A session is started this launch (`seedEmptySessionTreeForTesting`
    /// establishes a tree, mirroring production's `createSession`, which
    /// also inserts into `sessionIdsStartedThisLaunch`), then stopped
    /// (`closeSession` removes the tree — mirroring every real way a
    /// session stops: `closeSession`, natural process exit, and
    /// `clearRuntime` all remove the tree). The session now has NO live
    /// status.
    ///
    /// It must land in INACTIVE. This is the exact case that broke: under
    /// the OLD `hasLiveSurface(id:)`-based discriminator, a stopped session
    /// has `sessionTrees[id] == nil` and `browserManagers[id] == nil`, so
    /// `hasLiveSurface` returns `false` — the session would fail the
    /// Inactive membership test and fall through to Archive instead. The
    /// assertion below on `coordinator.sessionIdsStartedThisLaunch` (which
    /// stays `true` after the stop, unlike `hasLiveSurface`) is what
    /// distinguishes the fixed behavior from the old, broken one.
    @MainActor
    func testStartedThenStoppedSessionLandsInInactiveNotArchive() {
        let stopped = session(name: "stopped")
        let sessions = [stopped]

        let coordinator = SessionCoordinator()
        // closeSession -> setStatus(.killed) reaches claudeStateStore.removeState(for:);
        // point it at a temp directory so this never touches Sean's real
        // ~/.ghostties/state/ (matches SessionCoordinatorIndicatorCacheTests).
        let claudeStateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentsListViewTests-\(UUID().uuidString)", isDirectory: true)
        coordinator.claudeStateStoreForTesting = ClaudeStateStore(directoryURL: claudeStateDir)
        addTeardownBlock { try? FileManager.default.removeItem(at: claudeStateDir) }
        coordinator.seedEmptySessionTreeForTesting(id: stopped.id)
        XCTAssertTrue(coordinator.hasLiveSurface(id: stopped.id), "sanity: session has a live surface right after starting")

        coordinator.closeSession(id: stopped.id)

        // Old, broken discriminator: this is now false — proving that a
        // hasLiveSurface-based bucketing would misclassify this session.
        XCTAssertFalse(coordinator.hasLiveSurface(id: stopped.id), "stopping removes the tree, so the OLD discriminator would (wrongly) exclude this session from Inactive")
        // New discriminator: stays true for the rest of the launch.
        XCTAssertTrue(coordinator.sessionIdsStartedThisLaunch.contains(stopped.id), "started-this-launch tracking must survive the stop")

        let inactive = RecentsListView.inactiveSessions(
            from: sessions,
            statuses: [:],
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
        let archive = RecentsListView.archiveSessions(
            from: sessions,
            statuses: [:],
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )

        XCTAssertTrue(inactive.contains { $0.id == stopped.id }, "a started-then-stopped session must land in Inactive")
        XCTAssertTrue(archive.isEmpty, "must not fall through to Archive")
    }

    // MARK: - Ordering (Archive newest-first by lastActiveAt; Active/Inactive unchanged)

    /// Archive renders newest-first by `lastActiveAt` — Sean's call. This
    /// fixture deliberately inserts sessions in an order that DISAGREES with
    /// reverse-insertion-order: append order is [twoHoursAgo, fiveMinAgo,
    /// oneHourAgo], so a naive `Array(archived.reversed())` would produce
    /// [oneHourAgo, fiveMinAgo, twoHoursAgo] — wrong. Only a real sort on
    /// `lastActiveAt` produces the correct [fiveMinAgo, oneHourAgo,
    /// twoHoursAgo]. Active and Inactive keep the existing append-order
    /// behavior (see `testLastActiveAtDoesNotAffectOrder` etc. above)
    /// unchanged.
    func testArchiveOrdersNewestFirstByLastActiveAt() {
        let twoHoursAgo = session(name: "twoHoursAgo", lastActiveAt: Date(timeIntervalSinceNow: -7200))
        let fiveMinAgo = session(name: "fiveMinAgo", lastActiveAt: Date(timeIntervalSinceNow: -300))
        let oneHourAgo = session(name: "oneHourAgo", lastActiveAt: Date(timeIntervalSinceNow: -3600))

        // Append/creation order: twoHoursAgo, fiveMinAgo, oneHourAgo —
        // NOT chronological, so reverse-insertion-order and newest-first
        // disagree here.
        let archive = RecentsListView.archiveSessions(
            from: [twoHoursAgo, fiveMinAgo, oneHourAgo],
            statuses: [:],
            sessionIdsStartedThisLaunch: []
        )

        XCTAssertEqual(
            archive.map(\.name),
            ["fiveMinAgo", "oneHourAgo", "twoHoursAgo"],
            "Archive must sort by lastActiveAt descending, not reverse insertion order"
        )
    }

    /// Sessions with a `nil` `lastActiveAt` sort last, after every
    /// timestamped session — regardless of insertion position.
    func testArchiveSortsNilLastActiveAtLast() {
        let noTimestamp = session(name: "noTimestamp", lastActiveAt: nil)
        let oneHourAgo = session(name: "oneHourAgo", lastActiveAt: Date(timeIntervalSinceNow: -3600))
        let fiveMinAgo = session(name: "fiveMinAgo", lastActiveAt: Date(timeIntervalSinceNow: -300))

        // noTimestamp is inserted FIRST, but must still render LAST.
        let archive = RecentsListView.archiveSessions(
            from: [noTimestamp, oneHourAgo, fiveMinAgo],
            statuses: [:],
            sessionIdsStartedThisLaunch: []
        )

        XCTAssertEqual(
            archive.map(\.name),
            ["fiveMinAgo", "oneHourAgo", "noTimestamp"],
            "nil lastActiveAt must sort after every timestamped session"
        )
    }

    /// Archive must sort by `lastOutputAt` (real output), not `lastActiveAt`
    /// (which also advances on a plain focus/browse), when both are present.
    /// `staleOutputFreshFocus` has a stale `lastOutputAt` but a very recent
    /// `lastActiveAt` from being clicked in the sidebar a moment ago —
    /// `freshOutput` must still sort first, because browsing must not reorder
    /// Archive. This is the field-overloading fix from
    /// `reference_lastactiveat-written-on-focus.md`.
    func testArchiveOrdersByLastOutputAtNotLastActiveAt() {
        let staleOutputFreshFocus = session(
            name: "staleOutputFreshFocus",
            lastActiveAt: Date(timeIntervalSinceNow: -5),
            lastOutputAt: Date(timeIntervalSinceNow: -7200)
        )
        let freshOutput = session(
            name: "freshOutput",
            lastActiveAt: Date(timeIntervalSinceNow: -3600),
            lastOutputAt: Date(timeIntervalSinceNow: -300)
        )

        let archive = RecentsListView.archiveSessions(
            from: [staleOutputFreshFocus, freshOutput],
            statuses: [:],
            sessionIdsStartedThisLaunch: []
        )

        XCTAssertEqual(
            archive.map(\.name),
            ["freshOutput", "staleOutputFreshFocus"],
            "a recent focus/click must not out-rank real output recency in Archive"
        )
    }

    /// Migration case: a session persisted before `lastOutputAt` existed has
    /// `lastOutputAt == nil` but a real `lastActiveAt`. It must fall back to
    /// `lastActiveAt` for ordering purposes rather than sorting as if it had
    /// no timestamp at all (which would dump every pre-migration session at
    /// the bottom, collapsed together).
    func testArchiveFallsBackToLastActiveAtWhenLastOutputAtAbsent() {
        let migratedRecent = session(
            name: "migratedRecent",
            lastActiveAt: Date(timeIntervalSinceNow: -300),
            lastOutputAt: nil
        )
        let migratedOlder = session(
            name: "migratedOlder",
            lastActiveAt: Date(timeIntervalSinceNow: -3600),
            lastOutputAt: nil
        )

        let archive = RecentsListView.archiveSessions(
            from: [migratedOlder, migratedRecent],
            statuses: [:],
            sessionIdsStartedThisLaunch: []
        )

        XCTAssertEqual(
            archive.map(\.name),
            ["migratedRecent", "migratedOlder"],
            "pre-migration sessions must fall back to lastActiveAt, preserving their relative recency"
        )
    }

    /// When every session lacks a `lastActiveAt` (all nil), the sort must be
    /// stable and preserve incoming (append/creation) order rather than
    /// reordering arbitrarily.
    func testArchivePreservesAppendOrderWhenAllLastActiveAtAreNil() {
        let first = session(name: "first", lastActiveAt: nil)
        let second = session(name: "second", lastActiveAt: nil)
        let third = session(name: "third", lastActiveAt: nil)

        let archive = RecentsListView.archiveSessions(
            from: [first, second, third],
            statuses: [:],
            sessionIdsStartedThisLaunch: []
        )

        XCTAssertEqual(archive.map(\.name), ["first", "second", "third"], "all-nil list must preserve insertion order")
    }

    /// Active's ordering is unchanged by the three-way split — still
    /// append/creation order, exactly like before.
    func testActiveOrderingUnchangedByThreeWaySplit() {
        let first = session(name: "first")
        let second = session(name: "second")
        let third = session(name: "third")
        let statuses: [UUID: SessionStatus] = [
            first.id: .running, second.id: .running, third.id: .running,
        ]

        let active = RecentsListView.activeSessions(from: [first, second, third], statuses: statuses)

        XCTAssertEqual(active.map(\.name), ["first", "second", "third"], "Active must keep append order")
    }

    /// Inactive's ordering is append/creation order too, NOT reversed like
    /// Archive.
    func testInactiveOrderingIsAppendOrderNotReversed() {
        let first = session(name: "first")
        let second = session(name: "second")
        let third = session(name: "third")
        let sessionIdsStartedThisLaunch: Set<UUID> = [first.id, second.id, third.id]

        let inactive = RecentsListView.inactiveSessions(
            from: [first, second, third],
            statuses: [:],
            sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch
        )

        XCTAssertEqual(inactive.map(\.name), ["first", "second", "third"], "Inactive must keep append order, not reverse like Archive")
    }

    // MARK: - Sessions-tab Cmd+Shift+[/] cycle order (single shared source)

    /// `WorkspaceSidebarView.selectAdjacentLiveSession(offset:)` feeds the
    /// Sessions tab's Cmd+Shift+[/] cycle from
    /// `RecentsListView.activeSessions(from:statuses:)` — the exact same
    /// static the tab renders the ACTIVE zone from — so cycle order can never
    /// drift from render order. This does NOT exercise that composition end
    /// to end (the production method is private on a SwiftUI view and isn't
    /// called here); it builds the ACTIVE zone with the same static and
    /// cycles it directly via
    /// `SessionCoordinator.focusAdjacentLiveSession(offset:in:)`, asserting
    /// both forward and backward wraparound. Archive rows (no live status)
    /// must be skipped entirely.
    @MainActor
    func testSessionsTabCycleOrderMatchesActiveZoneRenderOrderWithWraparound() {
        let project = Project(name: "p", rootPath: "~/p")
        let a = AgentSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: project.id)
        let c = AgentSession(name: "c", templateId: UUID(), projectId: project.id)
        let archived = AgentSession(name: "archived", templateId: UUID(), projectId: project.id)

        let statuses: [UUID: SessionStatus] = [
            a.id: .running,
            b.id: .running,
            c.id: .running,
            // archived.id intentionally absent -> not alive -> Archive, not Active.
        ]

        // Same call the Sessions tab renders from — the single shared source.
        let activeZone = RecentsListView.activeSessions(
            from: [a, b, c, archived],
            statuses: statuses
        )
        XCTAssertEqual(activeZone.map(\.name), ["a", "b", "c"], "must match the ACTIVE zone RecentsListView renders")

        let coordinator = SessionCoordinator()
        for session in activeZone {
            coordinator.seedEmptySessionTreeForTesting(id: session.id)
        }

        // No active session yet -> forward cycle starts at the first entry.
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: 1, in: activeZone)?.name, "a")
        // Forward from a -> b -> c -> wraps back to a.
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: 1, in: activeZone)?.name, "b")
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: 1, in: activeZone)?.name, "c")
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: 1, in: activeZone)?.name, "a", "must wrap forward past the end")

        // Backward from a -> wraps to c.
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: -1, in: activeZone)?.name, "c", "must wrap backward past the start")
        XCTAssertEqual(coordinator.focusAdjacentLiveSession(offset: -1, in: activeZone)?.name, "b")
    }

    /// Regression test for the dead-end-cycling bug: the ACTIVE zone
    /// guarantees nothing about liveness on its own if status and surface
    /// ever disagree (`RecentsListView.activeSessions` filters on
    /// `SessionStatus.isAlive`, which in production only ever holds while a
    /// live surface exists — but `sessionsTabCycleOrder` keeps an explicit
    /// `hasLiveSurface` filter as a belt-and-suspenders guard). Seeds live
    /// surfaces for `a` and `c` but not `b`, so the production filter must
    /// drop `b` from the cycle.
    ///
    /// Asserts on `coordinator.activeSessionId`, not on
    /// `focusAdjacentLiveSession`'s return value: `focusSession` bails via
    /// `guard let tree = sessionTrees[id] else { return }` when the target
    /// has no live surface, but the caller still returns the target
    /// non-nil, so the return value alone can't tell success from a no-op.
    @MainActor
    func testSessionsTabCycleSkipsActiveZoneEntriesWithoutLiveSurface() {
        let project = Project(name: "p", rootPath: "~/p")
        let a = AgentSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: project.id)
        let c = AgentSession(name: "c", templateId: UUID(), projectId: project.id)

        let statuses: [UUID: SessionStatus] = [
            a.id: .running,
            b.id: .running,
            c.id: .running,
        ]

        let coordinator = SessionCoordinator()
        // b never gets a live surface -> stale status, exited session.
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedEmptySessionTreeForTesting(id: c.id)

        // The exact composition `selectAdjacentLiveSession` uses on the
        // Sessions tab — calls through the production static, not a
        // reimplementation of it.
        let liveSessions = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [a, b, c],
            statuses: statuses,
            coordinator: coordinator
        )
        XCTAssertEqual(liveSessions.map(\.name), ["a", "c"], "b has no live surface and must be excluded from the cycle")

        _ = coordinator.focusAdjacentLiveSession(offset: 1, in: liveSessions)
        XCTAssertEqual(coordinator.activeSessionId, a.id, "cycle starts at a")

        _ = coordinator.focusAdjacentLiveSession(offset: 1, in: liveSessions)
        XCTAssertEqual(coordinator.activeSessionId, c.id, "cycling forward from a must skip b and land on c")
    }

    // MARK: - Cmd+1-9 positional session focus (index mapping)

    /// `WorkspaceSidebarView.session(at:in:)` — Cmd+1..8. Pure index math:
    /// 1-indexed, first visible session for Cmd+1.
    func testSessionAtIndexOneReturnsFirstVisible() {
        let a = session(name: "a")
        let b = session(name: "b")
        let c = session(name: "c")

        XCTAssertEqual(WorkspaceSidebarView.session(at: 1, in: [a, b, c])?.name, "a")
        XCTAssertEqual(WorkspaceSidebarView.session(at: 2, in: [a, b, c])?.name, "b")
        XCTAssertEqual(WorkspaceSidebarView.session(at: 3, in: [a, b, c])?.name, "c")
    }

    /// Out-of-range is a no-op — not a wrap, not a clamp. Cmd+7 with only 4
    /// sessions visible must return nil, never wrap to session 3 or clamp to
    /// session 4.
    func testSessionAtOutOfRangeIndexIsNoOp() {
        let sessions = (0..<4).map { session(name: "s\($0)") }

        XCTAssertNil(WorkspaceSidebarView.session(at: 7, in: sessions), "out-of-range must be a no-op, not a wrap or clamp")
        XCTAssertNil(WorkspaceSidebarView.session(at: 0, in: sessions), "index 0 is out of range (1-indexed)")
        XCTAssertNil(WorkspaceSidebarView.session(at: -1, in: sessions))
        XCTAssertNil(WorkspaceSidebarView.session(at: 5, in: sessions), "one past the end must still be a no-op")
    }

    func testSessionAtIndexOnEmptyListIsNoOp() {
        XCTAssertNil(WorkspaceSidebarView.session(at: 1, in: []))
    }

    /// `WorkspaceSidebarView.lastSession(in:)` — Cmd+9. Always the LAST
    /// visible session, regardless of count — never literally "index 9".
    func testLastSessionReturnsLastRegardlessOfCount() {
        let three = (0..<3).map { session(name: "s\($0)") }
        XCTAssertEqual(WorkspaceSidebarView.lastSession(in: three)?.name, "s2", "with 3 sessions, Cmd+9 must land on the 3rd, not no-op")

        let twelve = (0..<12).map { session(name: "s\($0)") }
        XCTAssertEqual(WorkspaceSidebarView.lastSession(in: twelve)?.name, "s11", "with 12 sessions, Cmd+9 must land on the 12th, not the 9th")
    }

    func testLastSessionOnEmptyListIsNoOp() {
        XCTAssertNil(WorkspaceSidebarView.lastSession(in: []))
    }

    /// Sessions-tab composition: Cmd+1..9 must index the ACTIVE zone only —
    /// Archive rows (no live status) are excluded, same source as the
    /// Cmd+Shift+[/] cycle (`sessionsTabCycleOrder`).
    @MainActor
    func testSessionAtIndexExcludesArchiveRowsOnSessionsTab() {
        let project = Project(name: "p", rootPath: "~/p")
        let a = AgentSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: project.id)
        let archived = AgentSession(name: "archived", templateId: UUID(), projectId: project.id)

        let statuses: [UUID: SessionStatus] = [
            a.id: .running,
            b.id: .running,
            // archived.id intentionally absent -> not alive -> Archive.
        ]

        let coordinator = SessionCoordinator()
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedEmptySessionTreeForTesting(id: b.id)
        coordinator.seedEmptySessionTreeForTesting(id: archived.id)

        let visible = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [a, b, archived],
            statuses: statuses,
            coordinator: coordinator
        )

        XCTAssertEqual(WorkspaceSidebarView.session(at: 1, in: visible)?.name, "a")
        XCTAssertEqual(WorkspaceSidebarView.session(at: 2, in: visible)?.name, "b")
        // Only 2 visible sessions -> Cmd+3 is out of range even though a
        // 3rd session exists in the Archive.
        XCTAssertNil(WorkspaceSidebarView.session(at: 3, in: visible), "the archived session must not be reachable by index")
        XCTAssertEqual(WorkspaceSidebarView.lastSession(in: visible)?.name, "b")
    }

    /// Projects-tab composition: Cmd+1..9 indexes
    /// `WorkspaceStore.sessionsInVisualOrder(coordinator:)` — every session
    /// with a live surface, not just running ones (browser-tab mental
    /// model), matching what `selectAdjacentLiveSession`'s Projects-tab
    /// branch already cycles through.
    @MainActor
    func testSessionAtIndexUsesVisualOrderOnProjectsTab() {
        let project = Project(name: "p", rootPath: "~/p")
        let store = WorkspaceStore(testingProjects: [project])
        let a = store.addSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = store.addSession(name: "b", templateId: UUID(), projectId: project.id)
        let noSurface = store.addSession(name: "noSurface", templateId: UUID(), projectId: project.id)

        let coordinator = SessionCoordinator()
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedEmptySessionTreeForTesting(id: b.id)
        // noSurface never gets a live surface -> excluded from visual order.

        let visible = store.sessionsInVisualOrder(coordinator: coordinator)

        XCTAssertEqual(WorkspaceSidebarView.session(at: 1, in: visible)?.name, "a")
        XCTAssertEqual(WorkspaceSidebarView.session(at: 2, in: visible)?.name, "b")
        XCTAssertNil(WorkspaceSidebarView.session(at: 3, in: visible), "noSurface has no live surface and must not be reachable by index")
        XCTAssertEqual(WorkspaceSidebarView.lastSession(in: visible)?.name, "b")
    }

    // MARK: - Pinned Section (BACKLOG item B)

    /// A pinned session is excluded from Active/Inactive/Archive entirely,
    /// regardless of what bucket `SessionBucket.membership` would otherwise
    /// put it in — pinning is a separate partition layered on top, not a
    /// second copy of the Active/Inactive/Archive rule (see `SessionSection`).
    func testPinnedSessionExcludedFromAllThreeLifecycleBuckets() {
        var pinnedAndRunning = session(name: "pinnedRunning")
        pinnedAndRunning.isPinned = true
        var pinnedAndClosed = session(name: "pinnedClosed")
        pinnedAndClosed.isPinned = true
        let sessions = [pinnedAndRunning, pinnedAndClosed]
        let statuses: [UUID: SessionStatus] = [pinnedAndRunning.id: .running]

        let pinned = RecentsListView.pinnedSessions(from: sessions)
        let active = RecentsListView.activeSessions(from: sessions, statuses: statuses)
        let inactive = RecentsListView.inactiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: [])
        let archive = RecentsListView.archiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: [])

        XCTAssertEqual(pinned.map(\.name).sorted(), ["pinnedClosed", "pinnedRunning"], "both pinned sessions land in Pinned regardless of live status")
        XCTAssertTrue(active.isEmpty, "a pinned+running session must not also appear in Active")
        XCTAssertTrue(inactive.isEmpty)
        XCTAssertTrue(archive.isEmpty, "a pinned+closed session must not fall through to Archive")
    }

    /// Pinned/Active/Inactive/Archive together are still an exact partition
    /// once pinning is layered in — every session lands in exactly one of
    /// the four sections.
    func testPinnedActiveInactiveArchivePartitionIsExact() {
        var pinned = session(name: "pinned")
        pinned.isPinned = true
        let active = session(name: "active")
        let inactive = session(name: "inactive")
        let archived = session(name: "archived")
        let sessions = [pinned, active, inactive, archived]
        let statuses: [UUID: SessionStatus] = [active.id: .running]
        let startedThisLaunch: Set<UUID> = [inactive.id]

        let pinnedList = RecentsListView.pinnedSessions(from: sessions)
        let activeList = RecentsListView.activeSessions(from: sessions, statuses: statuses)
        let inactiveList = RecentsListView.inactiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: startedThisLaunch)
        let archiveList = RecentsListView.archiveSessions(from: sessions, statuses: statuses, sessionIdsStartedThisLaunch: startedThisLaunch)

        for s in sessions {
            let memberships = [pinnedList, activeList, inactiveList, archiveList].filter { bucket in bucket.contains { $0.id == s.id } }
            XCTAssertEqual(memberships.count, 1, "\(s.name) must land in exactly one section")
        }
        XCTAssertEqual(pinnedList.count + activeList.count + inactiveList.count + archiveList.count, sessions.count)
    }

    /// `orderedBySessionViewOrder` sorts ascending on `sessionViewOrder`,
    /// nil-last, falling back to append/creation position for ties/nils —
    /// same shape as `AgentSession.sortedNewestFirst`'s tie-break, but
    /// ascending on an explicit order instead of descending on a timestamp.
    func testOrderedBySessionViewOrderSortsAscendingNilLast() {
        var withOrder2 = session(name: "order2")
        withOrder2.sessionViewOrder = 2
        var withOrder0 = session(name: "order0")
        withOrder0.sessionViewOrder = 0
        let noOrder = session(name: "noOrder")
        var withOrder1 = session(name: "order1")
        withOrder1.sessionViewOrder = 1

        let ordered = RecentsListView.orderedBySessionViewOrder([withOrder2, withOrder0, noOrder, withOrder1])

        XCTAssertEqual(ordered.map(\.name), ["order0", "order1", "order2", "noOrder"])
    }

    func testOrderedBySessionViewOrderPreservesAppendOrderWhenAllNil() {
        let sessions = (0..<4).map { session(name: "s\($0)") }
        let ordered = RecentsListView.orderedBySessionViewOrder(sessions)
        XCTAssertEqual(ordered.map(\.name), ["s0", "s1", "s2", "s3"])
    }

    /// `activeSessions`/`inactiveSessions`/`pinnedSessions` apply
    /// `sessionViewOrder` on top of bucket membership — a drag-reorder
    /// result must be visible in render order, not just append order.
    func testActiveSessionsHonorsSessionViewOrder() {
        var first = session(name: "first")
        first.sessionViewOrder = 1
        var second = session(name: "second")
        second.sessionViewOrder = 0
        let statuses: [UUID: SessionStatus] = [first.id: .running, second.id: .running]

        let active = RecentsListView.activeSessions(from: [first, second], statuses: statuses)

        XCTAssertEqual(active.map(\.name), ["second", "first"], "sessionViewOrder must reorder Active, not just append order")
    }

    /// Sessions-tab cycle order puts Pinned before Active — matching render
    /// order (Pinned renders above Active in `RecentsListView.body`).
    @MainActor
    func testSessionsTabCycleOrderPutsPinnedFirst() {
        let project = Project(name: "p", rootPath: "~/p")
        var pinnedOpen = AgentSession(name: "pinnedOpen", templateId: UUID(), projectId: project.id)
        pinnedOpen.isPinned = true
        let activeOpen = AgentSession(name: "activeOpen", templateId: UUID(), projectId: project.id)

        let statuses: [UUID: SessionStatus] = [pinnedOpen.id: .running, activeOpen.id: .running]

        let coordinator = SessionCoordinator()
        coordinator.seedEmptySessionTreeForTesting(id: pinnedOpen.id)
        coordinator.seedEmptySessionTreeForTesting(id: activeOpen.id)

        let cycleOrder = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [activeOpen, pinnedOpen],
            statuses: statuses,
            coordinator: coordinator
        )

        XCTAssertEqual(cycleOrder.map(\.name), ["pinnedOpen", "activeOpen"], "Pinned must cycle before Active")
    }

    /// A pinned session with a CLOSED terminal has no live surface — it must
    /// be excluded from the cycle even though it's in Pinned, because there's
    /// nothing live to focus.
    @MainActor
    func testSessionsTabCycleOrderExcludesPinnedSessionWithClosedTerminal() {
        let project = Project(name: "p", rootPath: "~/p")
        var pinnedClosed = AgentSession(name: "pinnedClosed", templateId: UUID(), projectId: project.id)
        pinnedClosed.isPinned = true
        let activeOpen = AgentSession(name: "activeOpen", templateId: UUID(), projectId: project.id)

        let statuses: [UUID: SessionStatus] = [activeOpen.id: .running]

        let coordinator = SessionCoordinator()
        // pinnedClosed never gets a live surface.
        coordinator.seedEmptySessionTreeForTesting(id: activeOpen.id)

        let cycleOrder = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [pinnedClosed, activeOpen],
            statuses: statuses,
            coordinator: coordinator
        )

        XCTAssertEqual(cycleOrder.map(\.name), ["activeOpen"], "pinned-but-closed must not be cycled to")
    }

    // MARK: - Relative Time Labels

    func testRelativeLabelJustNow() {
        let date = Date(timeIntervalSinceNow: -10)
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "just now")
    }

    func testRelativeLabelMinutes() {
        let date = Date(timeIntervalSinceNow: -120) // 2 minutes ago
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "2m")
    }

    func testRelativeLabelHours() {
        let date = Date(timeIntervalSinceNow: -7200) // 2 hours ago
        XCTAssertEqual(RecentsRowView.relativeLabel(date), "2h")
    }

    func testRelativeLabelDayAbbreviation() {
        // 2 days ago — formatter uses en_US_POSIX locale so output is always 3-char English
        let date = Date(timeIntervalSinceNow: -172800)
        let label = RecentsRowView.relativeLabel(date)
        let validAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        XCTAssertTrue(validAbbreviations.contains(label),
            "Day abbreviation '\(label)' should be an English 3-char weekday")
    }

    func testRelativeLabelOldDate() {
        // 10 days ago — should use "MMM d" format (en_US_POSIX, e.g. "May 1")
        let date = Date(timeIntervalSinceNow: -864000)
        let label = RecentsRowView.relativeLabel(date)
        // Contains a space between month abbreviation and day number
        XCTAssertTrue(label.contains(" "), "Old date label '\(label)' should be 'MMM d' format")
    }
}
