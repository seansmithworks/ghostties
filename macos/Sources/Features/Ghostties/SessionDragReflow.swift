import Foundation
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

/// Pure geometry for the Sessions-tab live drag reflow (BACKLOG "2026-09-12 —
/// Sidebar section vocabulary", item G). Turns "a drag is hovering row N at
/// fraction F down its height" into "open the gap at index I in section S" —
/// or `nil` when `SessionSectionDrop.resolve` would reject the drop, so a
/// rejected hover never opens a gap. Kept free of any view/store state so it
/// is directly unit-testable; `RecentsListView` owns the transient
/// `SessionDragState` this produces and never writes it into the persisted
/// model until a real drop lands (see `SessionSectionDrop`/
/// `WorkspaceStore.moveSessionInSessionsView`).
enum SessionDragReflow {
    /// Matches `RecentsRowView`'s fixed row height — the gap spacer is
    /// exactly this tall so reflow only ever moves existing vertical space,
    /// never adds or removes any.
    static let rowHeight: CGFloat = 36

    /// Where the reflow gap should render: which section, and which index
    /// within that section's list (the dragged session already excluded).
    /// `index == nil` means "at the end" — used for a section's end-of-list
    /// drop zone and for an empty section's drop zone.
    struct GapPosition: Equatable {
        let section: SessionSection
        let index: Int?
    }

    /// Insertion point for a drag hovering row `hoveredIndex` (its position
    /// within the target section's list, dragged session already excluded)
    /// at vertical `fraction` through that row's height — `0` is the row's
    /// top edge, `1` its bottom edge. The top half of a row inserts before
    /// it; the bottom half inserts after it. Returns `nil` for any target
    /// `SessionSectionDrop.resolve` would reject — callers must not render a
    /// gap for a rejected hover.
    static func insertionPoint(
        draggedSection: SessionSection,
        draggedIsOpen: Bool,
        targetSection: SessionSection,
        hoveredIndex: Int,
        fraction: CGFloat
    ) -> GapPosition? {
        guard accepts(draggedSection: draggedSection, draggedIsOpen: draggedIsOpen, targetSection: targetSection) else {
            return nil
        }
        let index = fraction < 0.5 ? hoveredIndex : hoveredIndex + 1
        return GapPosition(section: targetSection, index: index)
    }

    /// Insertion point for hovering a section's end-of-list drop zone, or an
    /// empty section's drop zone (e.g. "Drop to pin" on an empty Pinned
    /// section) — always "at the end" of whatever the section resolves to
    /// when the drop isn't rejected.
    static func endInsertionPoint(
        draggedSection: SessionSection,
        draggedIsOpen: Bool,
        targetSection: SessionSection
    ) -> GapPosition? {
        guard accepts(draggedSection: draggedSection, draggedIsOpen: draggedIsOpen, targetSection: targetSection) else {
            return nil
        }
        return GapPosition(section: targetSection, index: nil)
    }

    private static func accepts(draggedSection: SessionSection, draggedIsOpen: Bool, targetSection: SessionSection) -> Bool {
        SessionSectionDrop.resolve(
            draggedSection: draggedSection,
            draggedIsOpen: draggedIsOpen,
            targetSection: targetSection
        ) != .reject
    }
}

/// Transient drag state for the Sessions-tab live reflow — held in
/// `RecentsListView` only, never persisted. `gap` is the proposed drop
/// position computed by `SessionDragReflow`; the model is written only on a
/// successful `performDrop`, via the existing
/// `SessionSectionDrop.resolve`/`WorkspaceStore.moveSessionInSessionsView`
/// path. `cancel()` is the single revert path — used on drag-exit-without-a-
/// drop and on Escape — so exiting, cancelling, or pressing Escape always
/// returns to the same "no drag in progress" state.
struct SessionDragState: Equatable {
    var draggingSessionId: UUID?
    var gap: SessionDragReflow.GapPosition?

    var isDragging: Bool { draggingSessionId != nil }

    mutating func cancel() {
        draggingSessionId = nil
        gap = nil
    }
}

// MARK: - Gap Spacer

/// The reflow gap itself — a plain spacer exactly one row tall (see
/// `SessionDragReflow.rowHeight`), spliced into a section's `ForEach` at the
/// proposed insertion point (item 1). Deliberately empty, not a placeholder
/// card — the surrounding rows moving apart IS the affordance.
struct SessionDragGapView: View {
    var body: some View {
        Color.clear
            .frame(height: SessionDragReflow.rowHeight)
            .transition(.opacity.combined(with: .scale(scale: 0.01, anchor: .center)))
    }
}

// MARK: - Row Drag Modifier

/// Attaches the `.onDrag` drag source to a session row, only when
/// `isEnabled` — `false` only for the temporary render-evidence harness (see
/// `RecentsListView.dragInteractionsEnabledForRendering`).
struct SessionRowDragModifier: ViewModifier {
    let isEnabled: Bool
    let session: AgentSession
    @Binding var dragState: SessionDragState

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrag {
                // Old-API `onDrag`, not `.draggable` — its closure runs
                // synchronously at drag start, so `dragState.draggingSessionId`
                // is set the instant the drag begins, before any drop
                // delegate's `dropEntered` can fire. Every delegate reads
                // that id directly instead of decoding the `NSItemProvider`
                // payload asynchronously, which is what makes the live
                // reflow possible — there is no round trip to wait on.
                dragState.draggingSessionId = session.id
                return NSItemProvider(object: session.id.uuidString as NSString)
            } preview: {
                Text(session.name)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            content
        }
    }
}

// MARK: - Row Drop Modifier

/// Attaches the live-reflow drop delegate to a session row, only when
/// `isEnabled` (Archive rows are drag sources but never a drop target — see
/// `RecentsListView.sessionRow`'s `supportsReorder` guard).
struct SessionRowDropModifier: ViewModifier {
    let isEnabled: Bool
    let section: SessionSection
    let sectionList: [AgentSession]
    let hoveredSession: AgentSession
    @Binding var dragState: SessionDragState
    let draggedContext: (UUID) -> (section: SessionSection, isOpen: Bool)?
    let performDrop: (UUID, SessionDragReflow.GapPosition) -> Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrop(of: [.text], delegate: SessionRowDropDelegate(
                section: section,
                sectionList: sectionList,
                hoveredSession: hoveredSession,
                dragState: $dragState,
                draggedContext: draggedContext,
                performDrop: performDrop
            ))
        } else {
            content
        }
    }
}

/// Live-reflow drop delegate for one session row. Reads the dragged session's
/// id straight off `dragState` (set synchronously at drag start by the
/// row's `.onDrag` — see `RecentsListView.sessionRow`), so every hover
/// callback can resolve a gap position with no async item-provider decode in
/// the way.
struct SessionRowDropDelegate: DropDelegate {
    let section: SessionSection
    let sectionList: [AgentSession]
    let hoveredSession: AgentSession
    @Binding var dragState: SessionDragState
    let draggedContext: (UUID) -> (section: SessionSection, isOpen: Bool)?
    let performDrop: (UUID, SessionDragReflow.GapPosition) -> Bool

    func dropEntered(info: DropInfo) {
        updateGap(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateGap(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Deliberately a no-op: leaving this row's bounds either lands on an
        // adjacent target (its `dropEntered` overwrites the gap before
        // anything reads a stale value) or on dead space, in which case
        // `RecentsListView`'s `leftMouseUp` monitor is the revert path once
        // the drag actually ends — see `installDragEndMonitors()`.
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = dragState.draggingSessionId,
              let gap = currentGap(location: info.location) else { return false }
        let handled = performDrop(draggedId, gap)
        dragState.cancel()
        return handled
    }

    private func updateGap(info: DropInfo) {
        dragState.gap = currentGap(location: info.location)
    }

    private func currentGap(location: CGPoint) -> SessionDragReflow.GapPosition? {
        guard let draggedId = dragState.draggingSessionId,
              let context = draggedContext(draggedId) else { return nil }
        let working = sectionList.filter { $0.id != draggedId }
        guard let hoveredIndex = working.firstIndex(where: { $0.id == hoveredSession.id }) else { return nil }
        let fraction = min(max(location.y / SessionDragReflow.rowHeight, 0), 1)
        return SessionDragReflow.insertionPoint(
            draggedSection: context.section,
            draggedIsOpen: context.isOpen,
            targetSection: section,
            hoveredIndex: hoveredIndex,
            fraction: fraction
        )
    }
}

/// Live-reflow drop delegate for a section's end-of-list zone, and for an
/// empty section's stand-in drop zone — both always resolve to "insert at
/// the end" via `SessionDragReflow.endInsertionPoint`, so unlike
/// `SessionRowDropDelegate` there is no per-row fraction math.
struct SessionEndZoneDropDelegate: DropDelegate {
    let section: SessionSection
    @Binding var dragState: SessionDragState
    let resolveGap: (SessionSection, Bool) -> SessionDragReflow.GapPosition?
    let draggedContext: (UUID) -> (section: SessionSection, isOpen: Bool)?
    let performDrop: (UUID, SessionDragReflow.GapPosition) -> Bool

    func dropEntered(info: DropInfo) {
        updateGap()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateGap()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // See `SessionRowDropDelegate.dropExited` — same reasoning.
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = dragState.draggingSessionId,
              let context = draggedContext(draggedId),
              let gap = resolveGap(context.section, context.isOpen) else { return false }
        let handled = performDrop(draggedId, gap)
        dragState.cancel()
        return handled
    }

    private func updateGap() {
        guard let draggedId = dragState.draggingSessionId,
              let context = draggedContext(draggedId) else { return }
        dragState.gap = resolveGap(context.section, context.isOpen)
    }
}

/// Drop delegate for the top/bottom auto-scroll edge zones (item 4) — never
/// resolves a gap or claims a real drop, only starts/stops the scroll timer
/// while a drag hovers it. Returning `false` from `performDrop` is
/// deliberate: nothing should ever actually land in this thin edge strip.
struct SessionAutoScrollEdgeDropDelegate: DropDelegate {
    let onHover: () -> Void
    let onExit: () -> Void

    func dropEntered(info: DropInfo) { onHover() }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover()
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { onExit() }
    func performDrop(info: DropInfo) -> Bool { false }
}
