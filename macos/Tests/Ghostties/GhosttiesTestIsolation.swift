import Foundation
import Testing
@testable import Ghostty

/// The test bundle's principal class (`NSPrincipalClass` in the GhosttyTests
/// build settings). XCTest instantiates it once, when the bundle loads and
/// before any test runs, so every test in `GhosttyTests` reads the sidebar
/// dials from a throwaway suite instead of the Dev app's real defaults domain
/// (`com.seansmithdesign.ghostties.dev`), where live-tuned values would
/// otherwise leak into layout and pixel tests. A new test cannot forget it.
@objc(GhosttiesTestIsolation)
final class GhosttiesTestIsolation: NSObject {
    static let suiteName = "com.seansmithdesign.ghostties.tests.sidebar-dials"

    override init() {
        super.init()
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        SidebarDialTuning.store = UserDefaults(suiteName: Self.suiteName)!
    }
}

@Suite("Test isolation: sidebar dial defaults")
struct SidebarDialIsolationTests {
    @Test("Dial readers see the test suite, not UserDefaults.standard")
    func dialReadersUseTheInjectedStore() throws {
        let key = SidebarDialTuning.trayInnerPaddingKey
        let sentinel = 12345.0
        let standard = UserDefaults.standard
        let standardBefore = standard.object(forKey: key) as? Double

        #expect(SidebarDialTuning.store !== UserDefaults.standard)
        // Whatever Dev's domain holds must not reach the production reader.
        #expect(SidebarDialTuning.trayInnerPadding() == TrayGlassStyle.innerPadding)

        let store = SidebarDialTuning.store
        store.set(sentinel, forKey: key)
        defer { store.removeObject(forKey: key) }

        #expect(SidebarDialTuning.trayInnerPadding() == CGFloat(sentinel))
        // The write went to the suite and never to standard.
        #expect(standard.object(forKey: key) as? Double == standardBefore)
    }
}
