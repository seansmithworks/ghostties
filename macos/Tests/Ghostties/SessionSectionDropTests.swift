import XCTest
import GhosttiesCore
@testable import Ghostty

/// Tests for `SessionSectionDrop.resolve` — the pure function mapping a
/// Sessions-tab drag/drop to an action. One test per row of Sean's decision 3
/// (BACKLOG "2026-09-12 — Sidebar section vocabulary", item C).
final class SessionSectionDropTests: XCTestCase {

    // MARK: - Dropping on Pinned always pins

    func testDroppingActiveSessionOnPinnedPins() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .active, draggedIsOpen: true, targetSection: .pinned),
            .pin
        )
    }

    func testDroppingInactiveSessionOnPinnedPins() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .inactive, draggedIsOpen: false, targetSection: .pinned),
            .pin
        )
    }

    func testDroppingArchivedSessionOnPinnedPins() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .archive, draggedIsOpen: false, targetSection: .pinned),
            .pin
        )
    }

    func testReorderingWithinPinnedIsStillPin() {
        // Already-pinned session dropped back on Pinned — a same-section
        // reorder. `.pin` is idempotent on the store side (setSessionPinned
        // no-ops if already true) and still repositions.
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .pinned, draggedIsOpen: true, targetSection: .pinned),
            .pin
        )
    }

    // MARK: - Dropping on Active

    func testDroppingPinnedOpenSessionOnActiveUnpinsWithoutRelaunch() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .pinned, draggedIsOpen: true, targetSection: .active),
            .unpin(relaunchIfClosed: false)
        )
    }

    func testDroppingPinnedClosedSessionOnActiveUnpinsAndRelaunches() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .pinned, draggedIsOpen: false, targetSection: .active),
            .unpin(relaunchIfClosed: true)
        )
    }

    func testReorderingWithinActiveIsReorder() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .active, draggedIsOpen: true, targetSection: .active),
            .reorder
        )
    }

    func testDroppingInactiveSessionOnActiveRelaunches() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .inactive, draggedIsOpen: false, targetSection: .active),
            .relaunch
        )
    }

    func testDroppingArchivedSessionOnActiveRelaunches() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .archive, draggedIsOpen: false, targetSection: .active),
            .relaunch
        )
    }

    // MARK: - Dropping on Inactive (reorder only within Inactive; drag-down is rejected)

    func testReorderingWithinInactiveIsReorder() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .inactive, draggedIsOpen: false, targetSection: .inactive),
            .reorder
        )
    }

    func testDraggingDownFromPinnedToInactiveIsRejected() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .pinned, draggedIsOpen: true, targetSection: .inactive),
            .reject
        )
    }

    func testDraggingDownFromActiveToInactiveIsRejected() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .active, draggedIsOpen: true, targetSection: .inactive),
            .reject
        )
    }

    func testDraggingFromArchiveToInactiveIsRejected() {
        XCTAssertEqual(
            SessionSectionDrop.resolve(draggedSection: .archive, draggedIsOpen: false, targetSection: .inactive),
            .reject
        )
    }

    // MARK: - Archive is never a drop target

    func testDroppingOnArchiveIsAlwaysRejected() {
        for draggedSection in SessionSection.allCases {
            XCTAssertEqual(
                SessionSectionDrop.resolve(draggedSection: draggedSection, draggedIsOpen: false, targetSection: .archive),
                .reject,
                "\(draggedSection) -> archive must always reject"
            )
        }
    }

    // MARK: - SessionSection.section(isPinned:bucket:) — pinning as a layered partition

    func testSectionResolutionPinningWinsOverBucket() {
        XCTAssertEqual(SessionSection.section(isPinned: true, bucket: .active), .pinned)
        XCTAssertEqual(SessionSection.section(isPinned: true, bucket: .inactive), .pinned)
        XCTAssertEqual(SessionSection.section(isPinned: true, bucket: .archive), .pinned)
    }

    func testSectionResolutionFallsThroughToBucketWhenNotPinned() {
        XCTAssertEqual(SessionSection.section(isPinned: false, bucket: .active), .active)
        XCTAssertEqual(SessionSection.section(isPinned: false, bucket: .inactive), .inactive)
        XCTAssertEqual(SessionSection.section(isPinned: false, bucket: .archive), .archive)
    }
}
