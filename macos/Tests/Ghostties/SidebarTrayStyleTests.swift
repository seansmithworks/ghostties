import XCTest
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
}
