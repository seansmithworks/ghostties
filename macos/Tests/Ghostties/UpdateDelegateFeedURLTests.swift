import Cocoa
import Sparkle
import Testing
@testable import Ghostty

/// Regression coverage for the demo-app Sparkle exposure: a re-bundled copy
/// of the shipping app (same `SUPublicEDKey`, different bundle id) had no
/// `SUFeedURL` in its own Info.plist, so `UpdateDriver.feedURLString(for:)`
/// fell through to the delegate's real channel feeds — a manual "Check for
/// Updates…" in the demo would install the real Ghostties over it.
/// `feedURLString(for:)` now honours an explicit Info.plist `SUFeedURL`
/// first (see `UpdateDelegate.swift`), so the demo build can carry a
/// deliberately-unreachable feed of its own.
///
/// `feedURLString(for:)` reads `Bundle.main`, which can't be mutated at
/// runtime inside `xcodebuild test`, so these tests drive it through
/// `UpdateDriver.testOverrideInfoPlistFeedURL` — a test-only seam on the
/// real production type, not a re-declared constant (see
/// `feedback_vacuous-tests-pass-green.md`).
@MainActor
struct UpdateDelegateFeedURLTests {
    private func makeDriver() -> UpdateDriver {
        UpdateDriver(viewModel: UpdateViewModel(), hostBundle: Bundle.main)
    }

    @Test func feedURLStringReturnsPlistValueWhenSUFeedURLIsPresent() {
        let previous = UpdateDriver.testOverrideInfoPlistFeedURL
        defer { UpdateDriver.testOverrideInfoPlistFeedURL = previous }

        let demoFeed = "https://ghostties.org/appcast-demo.xml"
        UpdateDriver.testOverrideInfoPlistFeedURL = demoFeed

        let driver = makeDriver()
        // `updater` argument is unused by the production implementation; Sparkle
        // gives us no lightweight way to construct a real `SPUUpdater` in a unit
        // test, so this only needs to be a value of the right type.
        let result = driver.feedURLString(for: SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: driver
        ))

        #expect(result == demoFeed)
    }

    @Test func shippingInfoPlistHasNoSUFeedURLKey() throws {
        // #filePath: .../macos/Tests/Ghostties/UpdateDelegateFeedURLTests.swift
        // Three `deletingLastPathComponent()` calls reach `macos/`.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let plistPath = url.appendingPathComponent("Ghostties-Info.plist").path

        let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(plist as? [String: Any])

        // If this ever fails, someone added SUFeedURL to the shipping app's
        // Info.plist — which would let it silently reroute the real update
        // feed. That needs a deliberate decision, not a silent pass.
        #expect(dict["SUFeedURL"] == nil)
    }
}
