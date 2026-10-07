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

@Suite("Locked sidebar dial defaults")
struct SidebarLockedDefaultsTests {
    /// The values tuned in the Dev DialKit, locked as the code defaults for
    /// beta.26. Read from an empty suite so nothing stored can mask them.
    @Test("Empty defaults read the locked, tuned values")
    func emptyDefaultsEqualTunedSnapshot() throws {
        let name = "com.seansmithdesign.ghostties.tests.locked-defaults"
        let d = try #require(UserDefaults(suiteName: name))
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }

        #expect(SidebarDialTuning.trayHorizontalButtonSize(defaults: d) == 44)
        #expect(SidebarDialTuning.trayVerticalButtonSize(defaults: d) == 44)
        #expect(SidebarDialTuning.trayHorizontalIconSize(defaults: d) == 18)
        #expect(SidebarDialTuning.trayVerticalIconSize(defaults: d) == 18)
        #expect(SidebarDialTuning.trayInnerPadding(defaults: d) == 8)
        #expect(SidebarDialTuning.traySelectedPillWidth(defaults: d) == 44)
        #expect(SidebarDialTuning.trayGlassCornerStyle(defaults: d) == .radius)
        #expect(SidebarDialTuning.trayGlassCornerRadius(defaults: d) == 16.5)
        #expect(SidebarDialTuning.contentPaddingLeading(defaults: d) == 0)
        #expect(SidebarDialTuning.contentPaddingTop(defaults: d) == 0)
        #expect(SidebarDialTuning.rowHeight(defaults: d) == 48)
        #expect(SidebarDialTuning.rowGap(defaults: d) == 4)
        #expect(SidebarDialTuning.rowTitleSize(defaults: d) == 14)
        #expect(SidebarDialTuning.rowSubtitleSize(defaults: d) == 11)
        #expect(SidebarDialTuning.rowGhostSize(defaults: d) == 20)
        #expect(SidebarDialTuning.rowLeadingPadding(defaults: d) == 16)
        #expect(SidebarDialTuning.rowTrailingPadding(defaults: d) == 16)

        let dark = SidebarDialTuning.trayGlass(for: .dark, defaults: d)
        #expect(dark.rimWidth == 0.75)
        #expect(dark.rimOpacity == 0.12)
        #expect(dark.shadowOpacity == 0.506)
        #expect(dark.chromaticWidth == 1)
        #expect(dark.chromaticRotation == 72.9)
        #expect(dark.specularStrength == 0.1)
        #expect(dark.specularAngle == 268)

        let light = SidebarDialTuning.trayGlass(for: .light, defaults: d)
        #expect(light.variant == .identity)
        #expect(light.surfaceOpacity == 0.7)
        #expect(light.chromaticBlur == 1.7)
        #expect(light.specularAngle == 189)
    }
}
