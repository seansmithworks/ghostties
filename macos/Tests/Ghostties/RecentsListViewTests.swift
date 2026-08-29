import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for the recents-list ordering + section-membership logic in RecentsListView.
///
/// Exercises the static `sorted(sessions:)` and `belongsInActive(...)` helpers plus
/// `relativeLabel(_:)` — all are pure functions with no SwiftUI or AppKit dependencies.
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

    // MARK: - Section Membership (indicator-state-only — FIX 6)

    func testInactiveSessionBelongsInArchiveByDefault() {
        XCTAssertFalse(RecentsListView.belongsInActive(indicatorState: .inactive))
    }

    func testLiveIndicatorStateBelongsInActive() {
        XCTAssertTrue(RecentsListView.belongsInActive(indicatorState: .processing))
    }

    /// FIX 6: selection must NEVER promote a session into Active. Membership
    /// depends only on indicator state — otherwise clicking an Archive row
    /// makes it vanish from Archive and reappear in Active, shifting every
    /// row below it under the cursor.
    func testSelectionDoesNotAffectMembership() {
        // Selected but inactive — must stay in Archive (no promotion).
        XCTAssertFalse(RecentsListView.belongsInActive(indicatorState: .inactive))
        // Never selected but active — still belongs in Active.
        XCTAssertTrue(RecentsListView.belongsInActive(indicatorState: .waiting))
    }

    /// `belongsInActive` and its archive complement (`!belongsInActive`) must
    /// be exact complements across the FULL `SessionIndicatorState` enum —
    /// every session lands in exactly one section, never both, never neither.
    func testBelongsInActiveAndArchiveAreExactComplementsAcrossFullEnum() {
        let allStates: [SessionIndicatorState] = [
            .inactive, .idle, .processing, .longRunning, .waiting, .needsAttention, .error,
        ]
        for state in allStates {
            let inActive = RecentsListView.belongsInActive(indicatorState: state)
            let inArchive = !RecentsListView.belongsInActive(indicatorState: state)
            XCTAssertNotEqual(inActive, inArchive, "state \(state) must be in exactly one section")
        }
    }

    // MARK: - Active/Inactive/Archive Sessions (pure helpers)

    /// Sean hit this directly: at cold launch every session resolves
    /// `.inactive` (no `globalIndicatorStates` entries yet) and has no live
    /// surface, Active is empty, nothing is selected, and Archive's stored
    /// preference is `false` (its default). Archive must render COLLAPSED —
    /// an empty Active section is not a reason to override the user's
    /// collapsed/expanded choice for Archive. A bare sidebar in this state
    /// is the accepted outcome; it is not this helper's job to prevent it.
    func testColdLaunchArchiveStaysCollapsedWhenActiveIsEmpty() {
        let sessions = (0..<14).map { session(name: "s\($0)") }

        let active = RecentsListView.activeSessions(from: sessions, indicatorStates: [:])
        let inactive = RecentsListView.inactiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: [])
        let archive = RecentsListView.archiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: [])

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
        let indicatorStates: [UUID: SessionIndicatorState] = [other.id: .processing]

        let active = RecentsListView.activeSessions(from: sessions, indicatorStates: indicatorStates)
        let archive = RecentsListView.archiveSessions(from: sessions, indicatorStates: indicatorStates, sessionIdsStartedThisLaunch: [])

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
        let indicatorStates: [UUID: SessionIndicatorState] = [other.id: .processing]

        let inactive = RecentsListView.inactiveSessions(
            from: sessions,
            indicatorStates: indicatorStates,
            sessionIdsStartedThisLaunch: [selected.id]
        )
        let archive = RecentsListView.archiveSessions(
            from: sessions,
            indicatorStates: indicatorStates,
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
    /// two. Mixes all combinations of indicator state x live-surface
    /// presence across a set of sessions.
    func testActiveInactiveArchivePartitionIsExact() {
        let liveNoSurface = session(name: "liveNoSurface") // active, no surface (impossible in prod but must still partition)
        let liveWithSurface = session(name: "liveWithSurface") // active, started this launch
        let stoppedWithSurface = session(name: "stoppedWithSurface") // inactive, started this launch -> Inactive
        let neverStarted = session(name: "neverStarted") // inactive, never started -> Archive
        let sessions = [liveNoSurface, liveWithSurface, stoppedWithSurface, neverStarted]

        let indicatorStates: [UUID: SessionIndicatorState] = [
            liveNoSurface.id: .processing,
            liveWithSurface.id: .idle,
            // stoppedWithSurface, neverStarted absent -> resolve .inactive.
        ]
        let sessionIdsStartedThisLaunch: Set<UUID> = [liveWithSurface.id, stoppedWithSurface.id]

        let active = RecentsListView.activeSessions(from: sessions, indicatorStates: indicatorStates)
        let inactive = RecentsListView.inactiveSessions(from: sessions, indicatorStates: indicatorStates, sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)
        let archive = RecentsListView.archiveSessions(from: sessions, indicatorStates: indicatorStates, sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)

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

    /// The exact bug Sean hit: a session that RAN and was stopped (inactive
    /// indicator, but was started at some point this launch) must land in
    /// INACTIVE, not ARCHIVE. This is the pure-function analog of
    /// `testStartedThenStoppedSessionLandsInInactiveNotArchive` below.
    func testStoppedButStillSurfacedSessionLandsInInactiveNotArchive() {
        let stopped = session(name: "stopped")
        let sessions = [stopped]
        let sessionIdsStartedThisLaunch: Set<UUID> = [stopped.id]

        let inactive = RecentsListView.inactiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)
        let archive = RecentsListView.archiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch)

        XCTAssertTrue(inactive.contains { $0.id == stopped.id }, "a stopped-but-started-this-launch session must land in Inactive")
        XCTAssertTrue(archive.isEmpty, "must not also land in Archive")
    }

    /// A session that never started this launch (restored from disk,
    /// never started) must land in ARCHIVE, not INACTIVE.
    func testNeverStartedSessionLandsInArchiveNotInactive() {
        let neverStarted = session(name: "neverStarted")
        let sessions = [neverStarted]

        let inactive = RecentsListView.inactiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: [])
        let archive = RecentsListView.archiveSessions(from: sessions, indicatorStates: [:], sessionIdsStartedThisLaunch: [])

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
    /// `clearRuntime` all remove the tree). The session now has NO current
    /// surface and indicator state resolves to `.inactive`.
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
            indicatorStates: [:],
            sessionIdsStartedThisLaunch: coordinator.sessionIdsStartedThisLaunch
        )
        let archive = RecentsListView.archiveSessions(
            from: sessions,
            indicatorStates: [:],
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
            indicatorStates: [:],
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
            indicatorStates: [:],
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
            indicatorStates: [:],
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
            indicatorStates: [:],
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
            indicatorStates: [:],
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
        let indicatorStates: [UUID: SessionIndicatorState] = [
            first.id: .processing, second.id: .idle, third.id: .waiting,
        ]

        let active = RecentsListView.activeSessions(from: [first, second, third], indicatorStates: indicatorStates)

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
            indicatorStates: [:],
            sessionIdsStartedThisLaunch: sessionIdsStartedThisLaunch
        )

        XCTAssertEqual(inactive.map(\.name), ["first", "second", "third"], "Inactive must keep append order, not reverse like Archive")
    }

    // MARK: - Sessions-tab Cmd+Shift+[/] cycle order (single shared source)

    /// `WorkspaceSidebarView.selectAdjacentLiveSession(offset:)` feeds the
    /// Sessions tab's Cmd+Shift+[/] cycle from
    /// `RecentsListView.activeSessions(from:indicatorStates:)` — the exact
    /// same static the tab renders the ACTIVE zone from — so cycle order can
    /// never drift from render order. This does NOT exercise that
    /// composition end to end (the production method is private on a
    /// SwiftUI view and isn't called here); it builds the ACTIVE zone with
    /// the same static and cycles it directly via
    /// `SessionCoordinator.focusAdjacentLiveSession(offset:in:)`, asserting
    /// both forward and backward wraparound. Archive rows (no live
    /// indicator state) must be skipped entirely.
    @MainActor
    func testSessionsTabCycleOrderMatchesActiveZoneRenderOrderWithWraparound() {
        let project = Project(name: "p", rootPath: "~/p")
        let a = AgentSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: project.id)
        let c = AgentSession(name: "c", templateId: UUID(), projectId: project.id)
        let archived = AgentSession(name: "archived", templateId: UUID(), projectId: project.id)

        let indicatorStates: [UUID: SessionIndicatorState] = [
            a.id: .processing,
            b.id: .waiting,
            c.id: .idle,
            // archived.id intentionally absent -> resolves .inactive -> Archive, not Active.
        ]

        // Same call the Sessions tab renders from — the single shared source.
        let activeZone = RecentsListView.activeSessions(
            from: [a, b, c, archived],
            indicatorStates: indicatorStates
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
    /// guarantees nothing about liveness (`RecentsListView.activeSessions`
    /// filters only on indicator state, not on whether a session still has
    /// a live surface), so a session can sit in ACTIVE with a stale
    /// indicator after its surface has closed. `selectAdjacentLiveSession`
    /// must filter the ACTIVE zone down to `coordinator.hasLiveSurface`
    /// before cycling, matching what the Projects-tab branch already does
    /// via `sessionsInVisualOrder`. Seeds live surfaces for `a` and `c` but
    /// not `b`, so the production filter must drop `b` from the cycle.
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

        let indicatorStates: [UUID: SessionIndicatorState] = [
            a.id: .processing,
            b.id: .waiting,
            c.id: .idle,
        ]

        let coordinator = SessionCoordinator()
        // b never gets a live surface -> stale indicator, exited session.
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedEmptySessionTreeForTesting(id: c.id)

        // The exact composition `selectAdjacentLiveSession` uses on the
        // Sessions tab — calls through the production static, not a
        // reimplementation of it.
        let liveSessions = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [a, b, c],
            indicatorStates: indicatorStates,
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
    /// Archive rows (no live indicator state) are excluded, same source as
    /// the Cmd+Shift+[/] cycle (`sessionsTabCycleOrder`).
    @MainActor
    func testSessionAtIndexExcludesArchiveRowsOnSessionsTab() {
        let project = Project(name: "p", rootPath: "~/p")
        let a = AgentSession(name: "a", templateId: UUID(), projectId: project.id)
        let b = AgentSession(name: "b", templateId: UUID(), projectId: project.id)
        let archived = AgentSession(name: "archived", templateId: UUID(), projectId: project.id)

        let indicatorStates: [UUID: SessionIndicatorState] = [
            a.id: .processing,
            b.id: .idle,
            // archived.id intentionally absent -> resolves .inactive -> Archive.
        ]

        let coordinator = SessionCoordinator()
        coordinator.seedEmptySessionTreeForTesting(id: a.id)
        coordinator.seedEmptySessionTreeForTesting(id: b.id)
        coordinator.seedEmptySessionTreeForTesting(id: archived.id)

        let visible = WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: [a, b, archived],
            indicatorStates: indicatorStates,
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
