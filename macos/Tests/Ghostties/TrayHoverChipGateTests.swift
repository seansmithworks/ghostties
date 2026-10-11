import XCTest
import SwiftUI
@testable import Ghostty

/// Gate for Sean's tray-hover call (2026-10-11). Pure geometry: every
/// argument is explicit, so no test reads UserDefaults.
///
/// 1. A sole-in-capsule button (the sidebar toggle) hovers full bleed: the
///    chip is the whole capsule, frame == cell, corner == the pill radius.
/// 2. A button in a grouped pill keeps its inset chip, but the corner stays
///    clearly rounded: concentric with the pill when that radius is at least
///    `minimumVisibleRadius`, else at least `minimumVisibleRadius`.
///
/// Shipping defaults: innerPadding 2, hoverInset 4, corner style .radius,
/// pill radius = concentricCornerRadius(margin: terminalInset) = 16 - 8 = 8.
final class TrayHoverChipGateTests: XCTestCase {
    private let minimumVisibleRadius: CGFloat = 6
    private let shippingPillRadius = WorkspaceLayout.concentricCornerRadius(margin: WorkspaceLayout.terminalInset)
    private let shippingPadding = TrayGlassStyle.innerPadding
    private let shippingInset = TrayGlassStyle.hoverInset

    func testSoleTrayButtonHoverIsFullBleed() {
        for size in [CGSize(width: 48, height: 48), CGSize(width: 48, height: 40)] {
            let cell = CGRect(origin: CGPoint(x: 5, y: 7), size: size)
            let chip = TrayGlassStyle.hoverChip(
                cell: cell, soleInCapsule: true,
                inset: shippingInset, innerPadding: shippingPadding, pillCornerRadius: shippingPillRadius
            )
            XCTAssertEqual(chip.frame, cell, "sole chip frame is the cell, no inset (\(size))")
            XCTAssertEqual(chip.cornerRadius, shippingPillRadius, accuracy: 0.001, "sole chip corner is the pill radius (\(size))")
        }
    }

    func testSoleTrayButtonHoverIsFullBleedAtOffDefaultDials() {
        let cell = CGRect(x: 0, y: 0, width: 48, height: 48)
        let chip = TrayGlassStyle.hoverChip(
            cell: cell, soleInCapsule: true,
            inset: 3, innerPadding: 10, pillCornerRadius: 16
        )
        XCTAssertEqual(chip.frame, cell, "full bleed ignores the hover inset dial")
        XCTAssertEqual(chip.cornerRadius, 16, accuracy: 0.001)
    }

    func testGroupedTrayChipKeepsAVisibleRadiusAtShippingDefaults() {
        let cell = CGRect(x: 0, y: 0, width: 48, height: 48)
        let chip = TrayGlassStyle.hoverChip(
            cell: cell, soleInCapsule: false,
            inset: shippingInset, innerPadding: shippingPadding, pillCornerRadius: shippingPillRadius
        )
        let concentric = shippingPillRadius - shippingPadding - shippingInset
        XCTAssertGreaterThan(chip.cornerRadius, 0, "grouped chip is rounded")
        if concentric >= minimumVisibleRadius {
            XCTAssertEqual(chip.cornerRadius, concentric, accuracy: 0.001, "grouped chip is concentric with the pill")
        } else {
            XCTAssertGreaterThanOrEqual(
                chip.cornerRadius, minimumVisibleRadius,
                "grouped chip corner reads rounded (concentric \(concentric) is too small); got \(chip.cornerRadius)"
            )
        }
    }

    func testGroupedTrayChipStaysInsetFromItsCell() {
        let cell = CGRect(x: 0, y: 0, width: 48, height: 48)
        let chip = TrayGlassStyle.hoverChip(
            cell: cell, soleInCapsule: false,
            inset: shippingInset, innerPadding: shippingPadding, pillCornerRadius: shippingPillRadius
        )
        XCTAssertEqual(chip.frame, cell.insetBy(dx: shippingInset, dy: shippingInset), "grouped chip keeps its inset")
    }
}
