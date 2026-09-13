import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for `SessionDragReflow` — the pure insertion-point math behind the
/// Sessions-tab live drag reflow (BACKLOG "2026-09-12 — Sidebar section
/// vocabulary", item G).
final class SessionDragReflowTests: XCTestCase {

    // MARK: - Top half inserts before, bottom half inserts after

    func testTopHalfInsertsBeforeHoveredRow() {
        let gap = SessionDragReflow.insertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .active,
            hoveredIndex: 2,
            fraction: 0.2
        )
        XCTAssertEqual(gap, .init(section: .active, index: 2))
    }

    func testBottomHalfInsertsAfterHoveredRow() {
        let gap = SessionDragReflow.insertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .active,
            hoveredIndex: 2,
            fraction: 0.8
        )
        XCTAssertEqual(gap, .init(section: .active, index: 3))
    }

    func testExactMidpointCountsAsBottomHalf() {
        // fraction == 0.5 is the boundary — must resolve to exactly one side,
        // never "before" the same row it also resolves to "after" for a
        // fraction just below 0.5.
        let gap = SessionDragReflow.insertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .active,
            hoveredIndex: 0,
            fraction: 0.5
        )
        XCTAssertEqual(gap, .init(section: .active, index: 1))
    }

    // MARK: - Section end (end-of-list drop zone)

    func testSectionEndInsertsAtEnd() {
        let gap = SessionDragReflow.endInsertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .active
        )
        XCTAssertEqual(gap, .init(section: .active, index: nil))
    }

    // MARK: - Empty Pinned zone ("Drop to pin")

    func testEmptyPinnedZoneAcceptsAnySession() {
        for draggedSection in SessionSection.allCases {
            let gap = SessionDragReflow.endInsertionPoint(
                draggedSection: draggedSection,
                draggedIsOpen: draggedSection == .active,
                targetSection: .pinned
            )
            XCTAssertEqual(gap, .init(section: .pinned, index: nil), "\(draggedSection) -> pinned must open the empty-Pinned zone")
        }
    }

    // MARK: - Rejected targets open no gap

    func testDraggingDownIntoInactiveOpensNoGap() {
        let gap = SessionDragReflow.insertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .inactive,
            hoveredIndex: 0,
            fraction: 0.9
        )
        XCTAssertNil(gap)
    }

    func testArchiveNeverOpensAGapAtAnyFraction() {
        for fraction: CGFloat in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let gap = SessionDragReflow.insertionPoint(
                draggedSection: .active,
                draggedIsOpen: true,
                targetSection: .archive,
                hoveredIndex: 0,
                fraction: fraction
            )
            XCTAssertNil(gap, "archive must never open a gap (fraction \(fraction))")
        }
    }

    func testArchiveEndZoneOpensNoGap() {
        let gap = SessionDragReflow.endInsertionPoint(
            draggedSection: .active,
            draggedIsOpen: true,
            targetSection: .archive
        )
        XCTAssertNil(gap)
    }

    // MARK: - Revert on cancel

    func testCancelClearsDraggingSessionAndGap() {
        var state = SessionDragState(
            draggingSessionId: UUID(),
            gap: SessionDragReflow.GapPosition(section: .active, index: 1)
        )
        state.cancel()
        XCTAssertNil(state.draggingSessionId)
        XCTAssertNil(state.gap)
        XCTAssertFalse(state.isDragging)
    }
}
