import Foundation
import Testing
import GhosttiesCore
@testable import Ghostty

/// Tests for the Sessions-tab pinning + drag-reorder store mutations
/// (BACKLOG "2026-09-12 — Sidebar section vocabulary", items B and C):
/// `setSessionPinned`, `toggleSessionPin`, and `moveSessionInSessionsView`.
@MainActor
struct WorkspaceStoreSessionPinningTests {
    private func makeSession(name: String, projectId: UUID = UUID(), isPinned: Bool = false, sessionViewOrder: Int? = nil) -> AgentSession {
        AgentSession(
            name: name,
            templateId: UUID(),
            projectId: projectId,
            isPinned: isPinned,
            sessionViewOrder: sessionViewOrder
        )
    }

    // MARK: - setSessionPinned / toggleSessionPin

    @Test func setSessionPinnedTruePinsAnUnpinnedSession() {
        let s = makeSession(name: "a")
        let store = WorkspaceStore(testingSessions: [s])

        store.setSessionPinned(id: s.id, true)

        #expect(store.sessions.first(where: { $0.id == s.id })?.isPinned == true)
    }

    @Test func setSessionPinnedIsIdempotent() {
        let s = makeSession(name: "a", isPinned: true)
        let store = WorkspaceStore(testingSessions: [s])

        // Calling with the already-current value must not crash or throw —
        // this is what makes SessionSectionDrop's `.pin` action (which fires
        // even for an already-pinned session dropped back on Pinned) safe.
        store.setSessionPinned(id: s.id, true)

        #expect(store.sessions.first(where: { $0.id == s.id })?.isPinned == true)
    }

    @Test func setSessionPinnedFalseUnpinsAPinnedSession() {
        let s = makeSession(name: "a", isPinned: true)
        let store = WorkspaceStore(testingSessions: [s])

        store.setSessionPinned(id: s.id, false)

        #expect(store.sessions.first(where: { $0.id == s.id })?.isPinned == false)
    }

    @Test func toggleSessionPinFlipsCurrentState() {
        let s = makeSession(name: "a")
        let store = WorkspaceStore(testingSessions: [s])

        store.toggleSessionPin(id: s.id)
        #expect(store.sessions.first(where: { $0.id == s.id })?.isPinned == true)

        store.toggleSessionPin(id: s.id)
        #expect(store.sessions.first(where: { $0.id == s.id })?.isPinned == false)
    }

    @Test func setSessionPinnedOnUnknownIdIsNoOp() {
        let store = WorkspaceStore(testingSessions: [])
        store.setSessionPinned(id: UUID(), true) // must not crash
        #expect(store.sessions.isEmpty)
    }

    // MARK: - moveSessionInSessionsView (same-section reorder)

    @Test func moveSessionInSessionsViewReordersWithinASection() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let c = makeSession(name: "c")
        let store = WorkspaceStore(testingSessions: [a, b, c])
        let section = [a, b, c]

        // Move "a" to the end — dropped past the last row.
        store.moveSessionInSessionsView(id: a.id, before: nil, within: section)

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["b", "c", "a"])
    }

    /// Fix-round repro: dragging A onto C in [A,B,C,D] must land A
    /// immediately BEFORE C -> [B,A,C,D]. The pre-fix call convention
    /// (`toIndex` = the drop target's index in the PRE-removal list, exactly
    /// what `handleSessionDrop` passed) instead removes A first — shifting C
    /// to index 1 — then inserts at the now-stale pre-removal index 2,
    /// producing [B,C,A,D]. Watched red against the pre-fix implementation;
    /// see task report for the exact totals line.
    @Test func moveSessionInSessionsViewDownwardDropMustInsertBeforeTarget() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let c = makeSession(name: "c")
        let d = makeSession(name: "d")
        let store = WorkspaceStore(testingSessions: [a, b, c, d])
        let section = [a, b, c, d]

        store.moveSessionInSessionsView(id: a.id, before: c.id, within: section)

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["b", "a", "c", "d"])
    }

    /// Upward mid-list: dragging D onto B in [A,B,C,D] must land D
    /// immediately BEFORE B -> [A,D,B,C]. Upward drags happened to already
    /// work under the pre-fix index math (the removed element was AFTER the
    /// target, so removal never shifted the target's index) — kept as a
    /// regression guard for the new `before:` API.
    @Test func moveSessionInSessionsViewUpwardDropMustInsertBeforeTarget() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let c = makeSession(name: "c")
        let d = makeSession(name: "d")
        let store = WorkspaceStore(testingSessions: [a, b, c, d])
        let section = [a, b, c, d]

        store.moveSessionInSessionsView(id: d.id, before: b.id, within: section)

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["a", "d", "b", "c"])
    }

    /// Dropping past the last row (`before: nil`) must land the session
    /// last, regardless of direction.
    @Test func moveSessionInSessionsViewDropAtEndLandsLast() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let c = makeSession(name: "c")
        let store = WorkspaceStore(testingSessions: [a, b, c])
        let section = [a, b, c]

        store.moveSessionInSessionsView(id: a.id, before: nil, within: section)

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["b", "c", "a"])
    }

    // MARK: - moveSessionInSessionsView (cross-section insert — pin/unpin/relaunch)

    /// The dragged session is NOT a member of `sectionSessions` — this is the
    /// pin/unpin/relaunch case, where the session is moving INTO a section it
    /// wasn't previously part of. `moveSessionInSessionsView` must insert it
    /// at the requested position rather than no-op.
    @Test func moveSessionInSessionsViewInsertsASessionNotInTheList() {
        let pinnedA = makeSession(name: "pinnedA", isPinned: true)
        let pinnedB = makeSession(name: "pinnedB", isPinned: true)
        let newlyPinned = makeSession(name: "newlyPinned")
        let store = WorkspaceStore(testingSessions: [pinnedA, pinnedB, newlyPinned])

        // Simulate the "pin" action: set pinned, then insert into the
        // PRE-pin snapshot of the Pinned list, before pinnedB.
        store.setSessionPinned(id: newlyPinned.id, true)
        store.moveSessionInSessionsView(id: newlyPinned.id, before: pinnedB.id, within: [pinnedA, pinnedB])

        let pinnedOrder = RecentsListView.pinnedSessions(from: store.sessions)
        #expect(pinnedOrder.map(\.name) == ["pinnedA", "newlyPinned", "pinnedB"])
    }

    @Test func moveSessionInSessionsViewClampsOutOfRangeIndex() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let store = WorkspaceStore(testingSessions: [a, b])

        // Dropped past the last row — must clamp to the end, not crash or no-op.
        store.moveSessionInSessionsView(id: a.id, before: nil, within: [a, b])

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["b", "a"])
    }

    @Test func moveSessionInSessionsViewOnUnknownIdIsNoOp() {
        let a = makeSession(name: "a")
        let store = WorkspaceStore(testingSessions: [a])

        store.moveSessionInSessionsView(id: UUID(), before: a.id, within: [a]) // must not crash

        #expect(store.sessions.map(\.name) == ["a"])
    }
}
