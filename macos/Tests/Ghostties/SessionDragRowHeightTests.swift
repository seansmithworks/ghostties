import XCTest
import GhosttiesCore
@testable import Ghostty

/// Drag reflow measures a row by what is drawn: a plain row is the row
/// height dial (48pt), not a stale 36pt constant, so a pointer splits it at
/// its true midpoint, and the live gap reopens exactly the dragged row's
/// slot.
@MainActor
final class SessionDragRowHeightTests: XCTestCase {
    private let atlas = Project(name: "atlas-api", rootPath: "/Users/example/work/atlas-api")

    private func session(_ name: String) -> AgentSession {
        AgentSession(name: name, templateId: UUID(), projectId: atlas.id)
    }

    func testAPlainRowIsMeasuredAtItsDrawnHeight() {
        XCTAssertEqual(SessionDragReflow.rowHeight, SidebarDialTuning.rowHeight(),
                       "a session row's drag height is the drawn row height")
    }

    /// A project drag over a plain row splits it at its midpoint: 20pt down
    /// a 48pt row is its top half (before), 28pt down is its bottom half.
    func testAProjectDragSplitsARowAtItsMidpoint() throws {
        let a1 = session("a1"), a2 = session("a2")
        let groups = SidebarProjectGroup.make(active: [a1, a2], projects: [atlas])
        let items = SidebarProjectGroupItem.items(groups, collapsed: [])
        let slots = ProjectDragReflow.slots(groups: groups, items: items)
        let slot = try XCTUnwrap(slots[a1.id.uuidString])
        XCTAssertEqual(slot.height, SidebarDialTuning.rowHeight(), "the slot is the drawn row's height")
        let half = SidebarDialTuning.rowHeight() / 2
        let above = ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: slot.slot, slotCount: slot.slotCount, fraction: (half - 4) / slot.height)
        let below = ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: slot.slot, slotCount: slot.slotCount, fraction: (half + 4) / slot.height)
        XCTAssertEqual(slot.slot, 1)
        XCTAssertNotEqual(above, below, "4pt either side of the row's midpoint land on different sides")
    }

    /// A needs-you row is taller (its action line); a project drag over it
    /// splits it at its own midpoint, not a plain row's.
    func testANeedsYouRowIsMeasuredWithItsActionLine() throws {
        let a1 = session("a1"), a2 = session("a2")
        let groups = SidebarProjectGroup.make(active: [a1, a2], projects: [atlas])
        let items = SidebarProjectGroupItem.items(groups, collapsed: [])
        let tall = SidebarListRowHeight.row(hasActions: true)
        XCTAssertGreaterThan(tall, SidebarListRowHeight.row(hasActions: false))
        let slots = ProjectDragReflow.slots(groups: groups, items: items) {
            SidebarListRowHeight.row(hasActions: $0 == a1.id)
        }
        let slot = try XCTUnwrap(slots[a1.id.uuidString])
        XCTAssertEqual(slot.height, tall)
        let above = ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: slot.slot, slotCount: slot.slotCount, fraction: (tall / 2 - 4) / slot.height)
        let below = ProjectDragReflow.insertionIndex(hoveredIndex: 0, slot: slot.slot, slotCount: slot.slotCount, fraction: (tall / 2 + 4) / slot.height)
        XCTAssertNotEqual(above, below, "the tall row splits at its own midpoint")
    }
}
