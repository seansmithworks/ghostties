import XCTest
import SwiftUI
@testable import Ghostty

/// The "Tray style" dial (`SidebarDialTuning.trayStyle`): Glass by default,
/// Bare round-trips, and the key is in the reset list. Uses an injected
/// suite, never the real domain.
final class SidebarTrayStyleTests: XCTestCase {
    func testTrayStyleDefaultsToGlassAndRoundTripsBare() {
        let name = "com.seansmithdesign.ghostties.tests.tray-style"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(SidebarDialTuning.trayStyleKey, "ghostties.sidebarDial.trayStyle")
        XCTAssertEqual(SidebarDialTuning.trayStyle(defaults: d), .glass)
        d.set(TrayGlassStyle.TrayStyle.bare.rawValue, forKey: SidebarDialTuning.trayStyleKey)
        XCTAssertEqual(SidebarDialTuning.trayStyle(defaults: d), .bare)
        d.set("nonsense", forKey: SidebarDialTuning.trayStyleKey)
        XCTAssertEqual(SidebarDialTuning.trayStyle(defaults: d), .glass)
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.trayStyleKey))
    }

    func testTintShimmerDarkIntensityDefaultsToLightAndRoundTrips() {
        let name = "com.seansmithdesign.ghostties.tests.tint-shimmer-dark"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensityKey, "ghostties.sidebarDial.tintShimmerDarkIntensity")
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), TrayGlassStyle.light.chromaticIntensity)
        XCTAssertGreaterThan(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), 0)
        d.set(0.65, forKey: SidebarDialTuning.tintShimmerDarkIntensityKey)
        XCTAssertEqual(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d), 0.65)
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.tintShimmerDarkIntensityKey))
        // The glass dark look itself stays rim-less.
        XCTAssertEqual(SidebarDialTuning.trayGlass(for: .dark, defaults: d).chromaticIntensity, 0)
    }

    func testSelectedRowStyleDefaultsToFlatMigratesAndRoundTrips() {
        let name = "com.seansmithdesign.ghostties.tests.selected-row-style"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(SidebarDialTuning.selectedRowStyleKey, "ghostties.sidebarDial.selectedRowStyle")
        // Default reproduces what the retired "Selected style" dial shipped.
        XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), .flat)
        // Migration: new key absent, legacy key present (read-only).
        d.set("glass", forKey: SidebarDialTuning.legacySelectedStyleKey)
        XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), .glass)
        d.set("flat", forKey: SidebarDialTuning.legacySelectedStyleKey)
        XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), .flat)
        XCTAssertEqual(d.string(forKey: SidebarDialTuning.legacySelectedStyleKey), "flat")
        XCTAssertNil(d.object(forKey: SidebarDialTuning.selectedRowStyleKey))
        // The new key wins over the legacy one, for every option.
        d.set("glass", forKey: SidebarDialTuning.legacySelectedStyleKey)
        XCTAssertEqual(TrayGlassStyle.SelectedRowStyle.tintShimmer.rawValue, "tintShimmer")
        XCTAssertEqual(TrayGlassStyle.SelectedRowStyle.allCases.count, 7)
        for style in TrayGlassStyle.SelectedRowStyle.allCases {
            d.set(style.rawValue, forKey: SidebarDialTuning.selectedRowStyleKey)
            XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), style)
        }
        d.set("nonsense", forKey: SidebarDialTuning.selectedRowStyleKey)
        d.removeObject(forKey: SidebarDialTuning.legacySelectedStyleKey)
        XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), .flat)
        XCTAssertTrue(SidebarDialTuning.allKeys.contains(SidebarDialTuning.selectedRowStyleKey))
        XCTAssertFalse(SidebarDialTuning.allKeys.contains(SidebarDialTuning.legacySelectedStyleKey))
        // Reset clears the legacy key too, so it cannot resurrect.
        d.set("glass", forKey: SidebarDialTuning.legacySelectedStyleKey)
        SidebarDialTuning.reset(defaults: d)
        XCTAssertEqual(SidebarDialTuning.selectedRowStyle(defaults: d), .flat)
    }
}
