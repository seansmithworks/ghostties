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

        // Move "a" (index 0) to index 2 — after "c".
        store.moveSessionInSessionsView(id: a.id, toIndex: 2, within: section)

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
        // PRE-pin snapshot of the Pinned list at index 1 (between pinnedA and pinnedB).
        store.setSessionPinned(id: newlyPinned.id, true)
        store.moveSessionInSessionsView(id: newlyPinned.id, toIndex: 1, within: [pinnedA, pinnedB])

        let pinnedOrder = RecentsListView.pinnedSessions(from: store.sessions)
        #expect(pinnedOrder.map(\.name) == ["pinnedA", "newlyPinned", "pinnedB"])
    }

    @Test func moveSessionInSessionsViewClampsOutOfRangeIndex() {
        let a = makeSession(name: "a")
        let b = makeSession(name: "b")
        let store = WorkspaceStore(testingSessions: [a, b])

        // Way out of range — must clamp to the end, not crash or no-op.
        store.moveSessionInSessionsView(id: a.id, toIndex: 999, within: [a, b])

        let reordered = RecentsListView.orderedBySessionViewOrder(store.sessions)
        #expect(reordered.map(\.name) == ["b", "a"])
    }

    @Test func moveSessionInSessionsViewOnUnknownIdIsNoOp() {
        let a = makeSession(name: "a")
        let store = WorkspaceStore(testingSessions: [a])

        store.moveSessionInSessionsView(id: UUID(), toIndex: 0, within: [a]) // must not crash

        #expect(store.sessions.map(\.name) == ["a"])
    }
}
