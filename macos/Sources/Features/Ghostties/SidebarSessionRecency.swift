import Foundation
import GhosttiesCore

// MARK: - Recency order (one view)

/// The one-view list's row order inside a project: last activity, newest
/// first, with the selected session leading its project.
///
/// `AgentSession.lastActiveAt` moves every few seconds while a session
/// prints, so the list never sorts on it live. It sorts on `held`, a
/// snapshot retaken only when the selection changes or a session finishes,
/// and never while the pointer is over the list: a reorder asked for then
/// waits (`isPending`) until the pointer leaves. Rows therefore never move
/// under the pointer.
///
/// One per window (`SessionCoordinator.recencyOrdered`), so the list, the
/// rail and the session shortcuts all read the same order.
struct SessionRecencyOrder: Equatable {
    /// What asks for a reorder.
    enum Event: Equatable {
        /// The first read of the order (`SessionCoordinator.recencyOrdered`):
        /// orders the rows if they have no order yet.
        case listAppeared
        case selectionChanged
        /// A session stopped working (`finished(from:to:)`).
        case sessionFinished
        /// The pointer left the list: applies a waiting reorder.
        case pointerExited
    }

    /// Session ids, top row first, as of the last reorder.
    private(set) var held: [UUID] = []
    /// A reorder was asked for while the pointer was over the list.
    private(set) var isPending = false

    /// Takes `event`. Returns true when `held` changed, so the caller can
    /// animate the rows to their new places.
    @discardableResult
    mutating func handle(
        _ event: Event, sessions: [AgentSession], selected: UUID?, pointerOverList: Bool
    ) -> Bool {
        switch event {
        case .listAppeared:
            guard held.isEmpty else { return false }
        case .selectionChanged, .sessionFinished:
            if pointerOverList {
                isPending = true
                return false
            }
        case .pointerExited:
            guard isPending else { return false }
        }
        isPending = false
        let ranking = Self.ranking(sessions, selected: selected)
        guard ranking != held else { return false }
        held = ranking
        return true
    }

    /// `sessions` newest first by `lastActiveAt`, the selected one leading:
    /// focus only advances `lastActiveAt` in 5s steps
    /// (`WorkspaceStore.recordActivity`), so the timestamp alone can leave
    /// the session just switched to below the one switched from. A session
    /// with no timestamp trails; ties keep `sessions`' order.
    static func ranking(_ sessions: [AgentSession], selected: UUID?) -> [UUID] {
        sessions.enumerated().sorted { a, b in
            let aSelected = a.element.id == selected, bSelected = b.element.id == selected
            if aSelected != bSelected { return aSelected }
            switch (a.element.lastActiveAt, b.element.lastActiveAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element.id)
    }

    /// `sessions` in the held order. A session the order has not seen (one
    /// created since) leads, newest first, so it is at the top of its
    /// project before the next reorder too. With no order held yet,
    /// `sessions` as given.
    func ordered(_ sessions: [AgentSession]) -> [AgentSession] {
        guard !held.isEmpty else { return sessions }
        let rank = Dictionary(held.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return sessions.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (l?, r?): return l < r
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return a.offset > b.offset
            }
        }.map(\.element)
    }

    /// True when a session in `before` that was working is no longer
    /// working in `after`: it finished, asked a question, failed or stopped.
    static func finished(from before: Set<UUID>, to after: Set<UUID>) -> Bool {
        !before.subtracting(after).isEmpty
    }

    /// The sessions that are working (the spinner's states).
    static func working(_ sessions: [AgentSession], indicators: [UUID: SessionIndicatorState]) -> Set<UUID> {
        Set(sessions.map(\.id).filter { indicators[$0]?.statusGlyphKind == .working })
    }
}

// MARK: - Following the selection

/// What the list does when the selection changes: whether its rows
/// reorder, which project unfolds, and which row scrolls into view.
enum SidebarSelectionFollow {
    /// How the selection moved.
    enum Route: Equatable {
        /// A click, the composer, the CLI, a new or resumed session.
        case direct
        /// Next/Previous Session or Cmd+1-9.
        case keyboard
    }

    struct Plan: Equatable {
        /// The rows take their recency order. The session shortcuts walk
        /// the list by position, so a reorder on each press would send
        /// Next Session back and forth between the same two rows: a
        /// keyboard move leaves the order alone.
        var reorders = false
        /// The folded project to unfold, so the selected row exists.
        var unfold: UUID?
        /// The row to scroll into view (`SidebarProjectGroupItem.id`).
        var scrollTo: String?
        /// Keyboard moves don't animate (motion spec, "stays still").
        var animates = false
    }

    /// The rows the list draws, and which projects are folded.
    struct Rows: Equatable {
        var pinned: [AgentSession] = []
        var active: [AgentSession] = []
        var collapsed: Set<UUID> = []
    }

    /// One view follows every selection. The tabs layout keeps what it had:
    /// only the rail scrolls, and only for a keyboard move.
    static func plan(
        layout: SidebarProjectsLayout, route: Route, selected: UUID?, rows: Rows, isRail: Bool
    ) -> Plan {
        guard let selected else { return Plan() }
        guard layout == .oneView else {
            return Plan(scrollTo: route == .keyboard && isRail ? selected.uuidString : nil)
        }
        let reorders = route == .direct
        let animates = route == .direct
        if rows.pinned.contains(where: { $0.id == selected }) {
            return Plan(reorders: reorders, scrollTo: selected.uuidString, animates: animates)
        }
        // A session with no row (History's, or one whose terminal closed)
        // has nothing to scroll to.
        guard let session = rows.active.first(where: { $0.id == selected }) else { return Plan(reorders: reorders) }
        return Plan(
            reorders: reorders,
            unfold: rows.collapsed.contains(session.projectId) ? session.projectId : nil,
            scrollTo: selected.uuidString,
            animates: animates
        )
    }
}
