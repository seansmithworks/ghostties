import XCTest
@testable import Ghostty

/// Approve/Deny become real keypresses ("1" / Esc), never paste, never Enter,
/// never menu options 2 or 3.
@MainActor
final class ApprovalKeysTests: XCTestCase {
    private final class FakeSurface: ApprovalKeySink {
        var events: [Ghostty.Input.KeyEvent] = []
        func sendKeyEvent(_ event: Ghostty.Input.KeyEvent) { events.append(event) }
    }

    func testApproveSendsDigitOnePressThenRelease() {
        let surface = FakeSurface()
        ApprovalKeys.deliver(.approve, to: surface)
        XCTAssertEqual(surface.events.map(\.key), [.digit1, .digit1])
        XCTAssertEqual(surface.events.map(\.action), [.press, .release])
        XCTAssertEqual(surface.events.first?.text, "1")
        XCTAssertEqual(surface.events.first?.mods, [])
    }

    func testDenySendsEscapeNeverATextKey() {
        let surface = FakeSurface()
        ApprovalKeys.deliver(.deny, to: surface)
        XCTAssertEqual(surface.events.map(\.key), [.escape, .escape])
        XCTAssertNil(surface.events.first?.text)
    }

    func testNoDecisionProducesEnterOrOtherMenuOptions() {
        for decision in [ApprovalDecision.approve, .deny] {
            let key = ApprovalKeys.event(for: decision).key
            XCTAssertTrue(key == .digit1 || key == .escape)
        }
    }
}
