import Foundation
import SwiftUI
import Testing
import XCTest
@testable import Ghostty

/// The test bundle's principal class (`NSPrincipalClass` in the GhosttyTests
/// build settings). XCTest instantiates it once, when the bundle loads and
/// before any test runs, so every test in `GhosttyTests` reads the sidebar
/// dials from a throwaway suite instead of the Dev app's real defaults domain
/// (`com.seansmithdesign.ghostties.dev`), where live-tuned values would
/// otherwise leak into layout and pixel tests. A new test cannot forget it.
///
/// The suite is private to this process (its name carries the pid), so a
/// parallel test process starting up can't clear it mid-render. A test that
/// needs its own dial values never writes this shared suite: it binds a
/// private one around its render with `withDials(_:_:)`.
@objc(GhosttiesTestIsolation)
final class GhosttiesTestIsolation: NSObject, XCTestObservation {
    static let suiteName = "com.seansmithdesign.ghostties.tests.sidebar-dials.\(getpid())"

    override init() {
        super.init()
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        SidebarDialTuning.sharedStore = UserDefaults(suiteName: Self.suiteName)!
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
    }
}

/// Runs `body` with every dial reader (and every dial `@AppStorage` built
/// inside it) reading a fresh private suite, seeded by `configure`. Nothing
/// is written to the suite other tests read, so concurrent tests can't see
/// these values or clear them. Render inside `body`: views constructed and
/// laid out there read this suite.
@discardableResult
func withDials<R>(_ configure: (UserDefaults) -> Void = { _ in }, _ body: () throws -> R) rethrows -> R {
    let name = "com.seansmithdesign.ghostties.tests.dials.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    configure(suite)
    return try SidebarDialTuning.$scopedStore.withValue(suite) { try body() }
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

        withDials({ $0.set(sentinel, forKey: key) }) {
            #expect(SidebarDialTuning.trayInnerPadding() == CGFloat(sentinel))
        }
        // The value never reached the shared suite or standard.
        #expect(SidebarDialTuning.sharedStore.object(forKey: key) == nil)
        #expect(standard.object(forKey: key) as? Double == standardBefore)
    }

    @Test("The shared suite is private to this test process")
    func sharedSuiteIsPerProcess() {
        #expect(GhosttiesTestIsolation.suiteName.hasSuffix(".\(getpid())"))
    }

    /// A dial `@AppStorage` built inside the scope reads the scoped suite.
    @Test("Views built inside withDials read the scoped suite")
    @MainActor
    func appStorageInsideScopeReadsScopedSuite() {
        struct Probe: View {
            @AppStorage(SidebarDialTuning.windowMarginKey, store: SidebarDialTuning.store) var margin = 0.0
            var body: some View { Color.clear }
        }
        let read = withDials({ $0.set(31.0, forKey: SidebarDialTuning.windowMarginKey) }) { Probe().margin }
        #expect(read == 31)
        #expect(Probe().margin == 0)
    }
}

@Suite("Locked sidebar dial defaults")
struct SidebarLockedDefaultsTests {
    /// The values tuned in the Dev DialKit, locked as the code defaults for
    /// beta.26 (re-baked 2026-10-08 from Dev's stored dials, plus Sean's
    /// calls: Tint + shimmer selected row, One view, History hidden, A5
    /// Resume list). Read from an empty suite so nothing stored can mask them.
    @Test("Empty defaults read the locked, tuned values")
    func emptyDefaultsEqualTunedSnapshot() throws {
        let name = "com.seansmithdesign.ghostties.tests.locked-defaults"
        let d = try #require(UserDefaults(suiteName: name))
        d.removePersistentDomain(forName: name)
        defer { d.removePersistentDomain(forName: name) }

        #expect(SidebarDialTuning.windowMargin(defaults: d) == 8)
        #expect(SidebarDialTuning.trayHorizontalButtonSize(defaults: d) == 44)
        #expect(SidebarDialTuning.trayVerticalButtonSize(defaults: d) == 44)
        #expect(SidebarDialTuning.trayHorizontalIconSize(defaults: d) == 18)
        #expect(SidebarDialTuning.trayVerticalIconSize(defaults: d) == 18)
        #expect(SidebarDialTuning.trayInnerPadding(defaults: d) == 8)
        #expect(SidebarDialTuning.trayGroupGap(defaults: d) == 8)
        #expect(SidebarDialTuning.trayWidth(defaults: d) == .fill)
        #expect(SidebarDialTuning.trayGlassInteractive(defaults: d))
        #expect(SidebarDialTuning.trayGlassCornerStyle(defaults: d) == .radius)
        #expect(SidebarDialTuning.trayGlassCornerRadius(defaults: d) == 20)
        #expect(SidebarDialTuning.selectedTitleWeight(defaults: d) == .regular)
        #expect(SidebarDialTuning.tintShimmerDarkIntensity(defaults: d) == 0.3)
        #expect(SidebarDialTuning.contentPaddingLeading(defaults: d) == 0)
        #expect(SidebarDialTuning.contentPaddingTop(defaults: d) == 0)
        #expect(SidebarDialTuning.listToTrayGap(defaults: d) == 0)
        #expect(SidebarDialTuning.railExtraWidth(defaults: d) == 0)
        #expect(SidebarDialTuning.rowHeight(defaults: d) == 48)
        #expect(SidebarDialTuning.rowGap(defaults: d) == 4)
        #expect(SidebarDialTuning.rowTitleSize(defaults: d) == 14)
        #expect(SidebarDialTuning.rowSubtitleSize(defaults: d) == 11)
        #expect(SidebarDialTuning.rowGhostSize(defaults: d) == 20)
        #expect(SidebarDialTuning.rowLeadingPadding(defaults: d) == 16)
        #expect(SidebarDialTuning.rowTrailingPadding(defaults: d) == 16)
        #expect(SidebarDialTuning.projectsLayout(defaults: d) == .oneView)
        #expect(!SidebarDialTuning.historyInSidebar(defaults: d))
        #expect(ComposerResumeLayout.current(defaults: d) == .list)
        #expect(ComposerSingleLineShadowDials.radius(defaults: d) == 48)
        #expect(ComposerSingleLineShadowDials.yOffset(defaults: d) == 43)
        #expect(ComposerSingleLineShadowDials.opacity(defaults: d) == 0.34)

        let light = SidebarDialTuning.trayGlass(for: .light, defaults: d)
        #expect(light == TrayGlassStyle.Look(
            variant: .identity, tintOpacity: 0.15, surfaceOpacity: 0.7,
            rimWidth: 1.25, rimOpacity: 0.25,
            shadowOpacity: 0.15, shadowRadius: 8, shadowYOffset: 3,
            chromaticIntensity: 0.3, chromaticWidth: 2.25, chromaticRotation: 202.7, chromaticBlur: 1.7,
            chromaticPalette: .pastel, chromaticBlend: .normal,
            specularStrength: 0.5, specularAngle: 189
        ))

        let dark = SidebarDialTuning.trayGlass(for: .dark, defaults: d)
        #expect(dark == TrayGlassStyle.Look(
            variant: .identity, tintOpacity: 0.15, surfaceOpacity: 0.45,
            rimWidth: 0.25, rimOpacity: 0.12,
            shadowOpacity: 0.298, shadowRadius: 8, shadowYOffset: 2.5,
            chromaticIntensity: 0.15, chromaticWidth: 0.5, chromaticRotation: 72.9, chromaticBlur: 1.4,
            chromaticPalette: .pastel, chromaticBlend: .plusLighter,
            specularStrength: 0.1, specularAngle: 270
        ))
    }
}
