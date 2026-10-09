import Foundation
import CoreGraphics
import SwiftUI

/// Pure geometry for dragging a project group in the one-view list — the
/// project-level twin of `SessionDragReflow`. A project's order is its place
/// in `WorkspaceStore.projects`, which the list and the rail both group by
/// (`SidebarProjectGroup.make`), so a drop is one `moveProject(id:before:)`.
///
/// Indices here count the reorderable groups (every group with a project)
/// with the dragged one already removed — the dragged group is not rendered
/// while it is in flight, the same way a dragged session row is omitted.
enum ProjectDragReflow {
    /// Gap index for a drag hovering slot `slot` of the group at
    /// `hoveredIndex`. A group's slots are its header (0) then its visible
    /// rows (1...), `slotCount` in all; `fraction` is how far down that slot
    /// the pointer is. The top half of the group inserts before it, the
    /// bottom half after it — so a header-only group (folded or empty)
    /// splits at its header's midpoint, like a session row.
    static func insertionIndex(hoveredIndex: Int, slot: Int, slotCount: Int, fraction: CGFloat) -> Int {
        let clamped = min(max(fraction, 0), 1)
        let position = (CGFloat(slot) + clamped) / CGFloat(max(slotCount, 1))
        return position < 0.5 ? hoveredIndex : hoveredIndex + 1
    }

    /// The project the dragged one lands before — nil means last. `order`
    /// is the full project order; the dragged id is removed before
    /// `gapIndex` is read, matching how the gap was computed.
    static func beforeId(gapIndex: Int, order: [UUID], dragged: UUID) -> UUID? {
        let working = order.filter { $0 != dragged }
        return working.indices.contains(gapIndex) ? working[gapIndex] : nil
    }

    /// Each rendered header's and row's place in its group, keyed by item
    /// id. `groups` is the rendered list (dragged group removed); the
    /// "Unknown" group has no project, so its items get no slot and never
    /// take a project drop.
    static func slots(groups: [SidebarProjectGroup], items: [SidebarProjectGroupItem]) -> [String: ProjectDropSlot] {
        let groupIndex = Dictionary(uniqueKeysWithValues: groups.filter { $0.projectId != nil }.enumerated().map { ($1.id, $0) })
        func member(_ item: SidebarProjectGroupItem) -> (group: SidebarProjectGroup, height: CGFloat)? {
            switch item {
            case .spacer: return nil
            case .header(let group, _): return (group, ProjectAccordionHeader.height)
            case .row(_, let group): return (group, SessionDragReflow.rowHeight)
            }
        }
        var slotCounts: [String: Int] = [:]
        for item in items {
            if let group = member(item)?.group { slotCounts[group.id, default: 0] += 1 }
        }
        var seen: [String: Int] = [:]
        var result: [String: ProjectDropSlot] = [:]
        for item in items {
            guard let (group, height) = member(item), let index = groupIndex[group.id] else { continue }
            let slot = seen[group.id, default: 0]
            seen[group.id] = slot + 1
            result[item.id] = ProjectDropSlot(groupIndex: index, slot: slot, slotCount: slotCounts[group.id] ?? 1, height: height)
        }
        return result
    }
}

/// Transient project-drag state, held in `RecentsListView` only and never
/// persisted. `gapIndex` is where the group would land (see
/// `ProjectDragReflow`); the store is written only on a real drop.
struct ProjectDragState: Equatable {
    var draggingProjectId: UUID?
    var gapIndex: Int?

    var isDragging: Bool { draggingProjectId != nil }

    mutating func cancel() {
        draggingProjectId = nil
        gapIndex = nil
    }
}

/// Where one header or row sits inside its project group, for a project
/// drag hovering it.
struct ProjectDropSlot {
    /// The group's index among the rendered reorderable groups.
    let groupIndex: Int
    /// 0 for the header, 1... for its visible rows.
    let slot: Int
    let slotCount: Int
    /// The hovered view's height, to turn a pointer y into a fraction.
    let height: CGFloat
}

/// What a header or row needs to take part in a project drag.
struct ProjectDropTarget {
    let slot: ProjectDropSlot
    let state: Binding<ProjectDragState>
    let performDrop: (UUID, Int) -> Bool

    func gapIndex(at location: CGPoint) -> Int {
        ProjectDragReflow.insertionIndex(
            hoveredIndex: slot.groupIndex,
            slot: slot.slot,
            slotCount: slot.slotCount,
            fraction: location.y / slot.height
        )
    }
}

/// The gap a dragged group leaves open: its header plus the break before it.
/// Empty, like `SessionDragGapView` — the groups parting is the affordance.
struct ProjectDragGapView: View {
    var body: some View {
        Color.clear
            .frame(height: ProjectAccordionHeader.height + SidebarProjectGroupItem.spacerHeight)
            .transition(.opacity.combined(with: .scale(scale: 0.01, anchor: .center)))
    }
}

/// Drop delegate for every header and row in the one-view list. A project
/// drag and a session drag are told apart by which drag state is set (each
/// source sets its own synchronously in `.onDrag`), so a session dragged
/// onto a header never reorders projects, and a project dragged across a
/// row never moves a session. Session drags on a row go to the row's own
/// `SessionRowDropDelegate`, unchanged; headers have none, so they refuse
/// session drags exactly as before they were drop targets.
struct ProjectSlotDropDelegate: DropDelegate {
    let target: ProjectDropTarget
    let session: SessionRowDropDelegate?

    private var projectDrag: ProjectDragState { target.state.wrappedValue }

    func validateDrop(info: DropInfo) -> Bool {
        projectDrag.isDragging || session != nil
    }

    func dropEntered(info: DropInfo) {
        if projectDrag.isDragging {
            target.state.wrappedValue.gapIndex = target.gapIndex(at: info.location)
        } else {
            session?.dropEntered(info: info)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if projectDrag.isDragging {
            target.state.wrappedValue.gapIndex = target.gapIndex(at: info.location)
            return DropProposal(operation: .move)
        }
        return session?.dropUpdated(info: info)
    }

    func dropExited(info: DropInfo) {
        // See `SessionRowDropDelegate.dropExited`: the next target's
        // `dropEntered` overwrites the gap, and `RecentsListView`'s
        // mouse-up monitor reverts a drop on dead space.
        if !projectDrag.isDragging { session?.dropExited(info: info) }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let draggedId = projectDrag.draggingProjectId {
            let handled = target.performDrop(draggedId, target.gapIndex(at: info.location))
            target.state.wrappedValue.cancel()
            return handled
        }
        return session?.performDrop(info: info) ?? false
    }
}
