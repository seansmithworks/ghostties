import CoreGraphics
import Testing
@testable import Ghostty

/// The closed sidebar's reveal fires only in the leading-edge strip, never
/// mid-window or at the right side.
struct ClosedRevealZoneTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private var strip: CGFloat { WorkspaceLayout.overlayTriggerWidth }

    @Test func leadingEdgeIsInZone() {
        #expect(WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: 0, y: 400), bounds: bounds))
        #expect(WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: strip - 1, y: 10), bounds: bounds))
        #expect(WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: strip / 2, y: 799), bounds: bounds))
    }

    @Test func justPastTheStripIsOutside() {
        #expect(!WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: strip, y: 400), bounds: bounds))
        #expect(!WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: strip + 1, y: 400), bounds: bounds))
    }

    @Test func midWindowIsOutside() {
        #expect(!WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: bounds.midX, y: bounds.midY), bounds: bounds))
    }

    @Test func rightSideIsOutside() {
        #expect(!WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: bounds.maxX - 1, y: 400), bounds: bounds))
        #expect(!WorkspaceLayout.isInClosedRevealZone(point: CGPoint(x: bounds.maxX - strip / 2, y: 400), bounds: bounds))
    }

    @Test func zoneIsTheStripAtFullHeight() {
        let zone = WorkspaceLayout.closedRevealZone(in: bounds)
        #expect(zone == CGRect(x: 0, y: 0, width: strip, height: 800))
    }
}
