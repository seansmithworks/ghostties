import CoreGraphics
import Testing
@testable import Ghostty

/// The closed sidebar's reveal zone is the leading-edge strip only, never
/// mid-window or the right side.
struct ClosedRevealZoneTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private var strip: CGFloat { WorkspaceLayout.overlayTriggerWidth }
    private var zone: CGRect { WorkspaceLayout.closedRevealZone(in: bounds) }

    @Test func leadingEdgeIsInZone() {
        #expect(zone.contains(CGPoint(x: 0, y: 400)))
        #expect(zone.contains(CGPoint(x: strip - 1, y: 10)))
        #expect(zone.contains(CGPoint(x: strip / 2, y: 799)))
    }

    @Test func justPastTheStripIsOutside() {
        #expect(!zone.contains(CGPoint(x: strip, y: 400)))
        #expect(!zone.contains(CGPoint(x: strip + 1, y: 400)))
    }

    @Test func midWindowIsOutside() {
        #expect(!zone.contains(CGPoint(x: bounds.midX, y: bounds.midY)))
    }

    @Test func rightSideIsOutside() {
        #expect(!zone.contains(CGPoint(x: bounds.maxX - 1, y: 400)))
        #expect(!zone.contains(CGPoint(x: bounds.maxX - strip / 2, y: 400)))
    }

    @Test func zoneIsTheStripAtFullHeight() {
        #expect(zone == CGRect(x: 0, y: 0, width: strip, height: 800))
    }
}
