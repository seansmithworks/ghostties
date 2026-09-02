import Foundation
import Testing
@testable import Ghostty

/// Tests for the CEF browser-open crash-recovery sentinel (see the CEF
/// profile-poisoning bisection). The crash kills the process in
/// ~400-650ms — far faster than any in-process watchdog — so recovery is
/// sentinel-based, detected on the NEXT launch. These tests exercise the
/// sentinel file lifecycle and the profile-reset behavior directly against
/// `CEFBridgeManager`, the production symbol `CEFBrowserView` gates on.
///
/// CRITICAL: `CEFBridgeManager` derives all these paths from
/// `[NSBundle mainBundle] bundleIdentifier]`, which inside an `xcodebuild
/// test` run resolves to Sean's real "Ghostties Dev" bundle id — i.e. the
/// same on-disk directory the real Dev app's CEF browser actually uses.
/// Every test below MUST redirect `testOverrideAppSupportBundleDirectory`
/// to an isolated scratch directory before touching anything, and MUST
/// restore it to nil afterward. Do not remove this indirection.
///
/// Serialized: parallel test processes would otherwise race the shared
/// scratch directory (created once per suite run, not per test).
@Suite(.serialized)
struct CEFBrowserSentinelTests {
    /// Points `CEFBridgeManager` at an isolated scratch directory for the
    /// duration of `body`, then restores the real path. Never touches
    /// Sean's actual CEF profile directories.
    private func withIsolatedAppSupportDirectory(_ body: () throws -> Void) rethrows {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-cef-sentinel-tests-\(UUID().uuidString)")
            .path
        CEFBridgeManager.testOverrideAppSupportBundleDirectory = scratchDir
        defer {
            try? FileManager.default.removeItem(atPath: scratchDir)
            CEFBridgeManager.testOverrideAppSupportBundleDirectory = nil
        }
        try body()
    }

    @Test func testSentinelPathIsOutsideProfileDirectory() throws {
        try withIsolatedAppSupportDirectory {
            let sentinelPath = CEFBridgeManager.browserOpenAttemptSentinelPath()
            let profilePath = CEFBridgeManager.cefProfileDirectoryPath()

            // The sentinel must be a SIBLING of the profile directory, never a
            // descendant of it — otherwise a profile reset (which renames the
            // profile dir aside) would also remove the evidence.
            #expect(!sentinelPath.hasPrefix(profilePath + "/"))
            #expect((sentinelPath as NSString).deletingLastPathComponent
                    == (profilePath as NSString).deletingLastPathComponent)
        }
    }

    @Test func testNoAttemptRecordedMeansNothingUncleared() throws {
        try withIsolatedAppSupportDirectory {
            #expect(CEFBridgeManager.hasUnclearedBrowserOpenAttempt() == false)
        }
    }

    @Test func testRecordBrowserOpenAttemptMarksUncleared() throws {
        try withIsolatedAppSupportDirectory {
            #expect(CEFBridgeManager.hasUnclearedBrowserOpenAttempt() == false)
            CEFBridgeManager.recordBrowserOpenAttempt()
            #expect(CEFBridgeManager.hasUnclearedBrowserOpenAttempt() == true)
            #expect(FileManager.default.fileExists(atPath: CEFBridgeManager.browserOpenAttemptSentinelPath()))
        }
    }

    @Test func testClearBrowserOpenAttemptRemovesSentinel() throws {
        try withIsolatedAppSupportDirectory {
            CEFBridgeManager.recordBrowserOpenAttempt()
            #expect(CEFBridgeManager.hasUnclearedBrowserOpenAttempt() == true)

            CEFBridgeManager.clearBrowserOpenAttempt()
            #expect(CEFBridgeManager.hasUnclearedBrowserOpenAttempt() == false)
            #expect(!FileManager.default.fileExists(atPath: CEFBridgeManager.browserOpenAttemptSentinelPath()))
        }
    }

    @Test func testResetMovesExistingProfileAsideRatherThanDeleting() throws {
        try withIsolatedAppSupportDirectory {
            let fm = FileManager.default
            let profilePath = CEFBridgeManager.cefProfileDirectoryPath()
            try fm.createDirectory(atPath: profilePath, withIntermediateDirectories: true)
            let markerPath = (profilePath as NSString).appendingPathComponent("Cookies")
            try "poisoned-data".write(toFile: markerPath, atomically: true, encoding: .utf8)

            var error: NSError?
            let movedTo = CEFBridgeManager.resetProfileDirectoryPreservingDataError(&error)

            #expect(error == nil)
            let moved = try #require(movedTo)
            #expect(moved != profilePath)
            #expect((moved as NSString).lastPathComponent.hasPrefix("CEF-broken-"))

            // The old data is PRESERVED at the new location, not deleted.
            let preservedMarker = (moved as NSString).appendingPathComponent("Cookies")
            #expect(fm.fileExists(atPath: preservedMarker))
            #expect((try? String(contentsOfFile: preservedMarker, encoding: .utf8)) == "poisoned-data")

            // A fresh, empty directory exists at the original path.
            var isDir: ObjCBool = false
            #expect(fm.fileExists(atPath: profilePath, isDirectory: &isDir))
            #expect(isDir.boolValue)
            #expect(try fm.contentsOfDirectory(atPath: profilePath).isEmpty)
        }
    }

    @Test func testResetWithNoExistingProfileReturnsNilWithoutError() throws {
        try withIsolatedAppSupportDirectory {
            #expect(!FileManager.default.fileExists(atPath: CEFBridgeManager.cefProfileDirectoryPath()))

            var error: NSError?
            let movedTo = CEFBridgeManager.resetProfileDirectoryPreservingDataError(&error)

            #expect(movedTo == nil)
            #expect(error == nil)
            // Still ensures a fresh directory exists for the next attempt.
            #expect(FileManager.default.fileExists(atPath: CEFBridgeManager.cefProfileDirectoryPath()))
        }
    }

    // MARK: - Downgrade guard version comparison
    //
    // Calls the production symbol `CEFBridgeManager.isProfileDowngradeGivenRecordedMajor(_:runningMajor:)`
    // directly — the same comparison `+_performDowngradeGuardIfNeeded` reduces
    // to before moving a profile aside. Mutant-verified 2026-09-02: flipping
    // the production `>` to `<` made `testNewerRecordedMajorIsADowngrade`
    // and `testOlderRecordedMajorIsNotADowngrade` both fail; restoring the
    // `>` made the full suite pass again. See feedback_vacuous-tests-pass-green
    // — a test that never references a production symbol is not coverage.

    @Test func testNewerRecordedMajorIsADowngrade() throws {
        #expect(CEFBridgeManager.isProfileDowngrade(givenRecordedMajor: 150, runningMajor: 144) == true)
    }

    @Test func testOlderRecordedMajorIsNotADowngrade() throws {
        #expect(CEFBridgeManager.isProfileDowngrade(givenRecordedMajor: 140, runningMajor: 144) == false)
    }

    @Test func testEqualMajorIsNotADowngrade() throws {
        #expect(CEFBridgeManager.isProfileDowngrade(givenRecordedMajor: 144, runningMajor: 144) == false)
    }

    @Test func testAbsentRecordedMajorIsNotADowngrade() throws {
        // 0 is the sentinel `_recordedChromiumMajorVersionOrZero` returns
        // for an absent/unparseable version — must never trigger a move.
        #expect(CEFBridgeManager.isProfileDowngrade(givenRecordedMajor: 0, runningMajor: 144) == false)
    }

    // MARK: - Recorded-major parsing (_recordedChromiumMajorVersionOrZero)
    //
    // Calls the production symbol
    // CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting(), a
    // DEBUG-only wrapper that forwards directly to
    // +_recordedChromiumMajorVersionOrZero — the exact parsing the downgrade
    // guard runs before every CefInitialize. This is where the actual risk
    // lives (see the review finding that motivated it): an unbounded,
    // unvalidated parse of a truncated/corrupted `last_chrome_version` like
    // "1440.1.2.3" would read as major 1440, compare as a downgrade against
    // running major 144, and move aside a HEALTHY same-version profile.
    //
    // Mutant-verified 2026-09-02: temporarily removing the
    // `value > kGhosttiesMaxPlausibleChromiumMajor` bound from
    // +_sanitizedMajorVersionFromDigitString: made
    // testOversizedPreferencesMajorIsUnparseable AND
    // testOversizedStampIsUnparseable fail (both returned 1440 instead of
    // 0); restoring the bound made the suite green again.

    private func writePreferences(lastChromeVersion: String?, profilePath: String) throws {
        let fm = FileManager.default
        let defaultDir = (profilePath as NSString).appendingPathComponent("Default")
        try fm.createDirectory(atPath: defaultDir, withIntermediateDirectories: true)
        let prefsPath = (defaultDir as NSString).appendingPathComponent("Preferences")
        var json: [String: Any] = [:]
        if let lastChromeVersion {
            json["extensions"] = ["last_chrome_version": lastChromeVersion]
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: URL(fileURLWithPath: prefsPath))
    }

    @Test func testAbsentStampAndAbsentPreferencesIsZero() throws {
        try withIsolatedAppSupportDirectory {
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testAbsentStampWithValidPreferencesReadsThePreferencesMajor() throws {
        try withIsolatedAppSupportDirectory {
            try writePreferences(
                lastChromeVersion: "150.0.7871.129",
                profilePath: CEFBridgeManager.cefProfileDirectoryPath()
            )
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 150)
        }
    }

    @Test func testMalformedNonJSONPreferencesIsZero() throws {
        try withIsolatedAppSupportDirectory {
            let fm = FileManager.default
            let defaultDir = (CEFBridgeManager.cefProfileDirectoryPath() as NSString).appendingPathComponent("Default")
            try fm.createDirectory(atPath: defaultDir, withIntermediateDirectories: true)
            let prefsPath = (defaultDir as NSString).appendingPathComponent("Preferences")
            try "not json at all { [ garbage".write(toFile: prefsPath, atomically: true, encoding: .utf8)
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testExtensionsPresentButLastChromeVersionMissingIsZero() throws {
        try withIsolatedAppSupportDirectory {
            let fm = FileManager.default
            let defaultDir = (CEFBridgeManager.cefProfileDirectoryPath() as NSString).appendingPathComponent("Default")
            try fm.createDirectory(atPath: defaultDir, withIntermediateDirectories: true)
            let prefsPath = (defaultDir as NSString).appendingPathComponent("Preferences")
            let json: [String: Any] = ["extensions": ["some_other_key": "value"]]
            try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: prefsPath))
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testEmptyLastChromeVersionStringIsZero() throws {
        try withIsolatedAppSupportDirectory {
            try writePreferences(lastChromeVersion: "", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testNonDigitMajorIsZero() throws {
        try withIsolatedAppSupportDirectory {
            try writePreferences(lastChromeVersion: "abc.1.2", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testOversizedPreferencesMajorIsUnparseable() throws {
        try withIsolatedAppSupportDirectory {
            // A truncated/corrupted version string that concatenates two
            // components into one run of digits — the exact review finding
            // this bound exists to catch.
            try writePreferences(lastChromeVersion: "1440.1.2.3", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }

    @Test func testEqualVersionInPreferencesReadsExactly() throws {
        try withIsolatedAppSupportDirectory {
            try writePreferences(lastChromeVersion: "144.0.1.2", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 144)
        }
    }

    @Test func testOlderVersionInPreferencesReadsExactly() throws {
        try withIsolatedAppSupportDirectory {
            try writePreferences(lastChromeVersion: "100.0.5.6", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 100)
        }
    }

    private func writeStamp(_ contents: String) throws {
        let stampPath = CEFBridgeManager.chromiumVersionStampPath()
        try FileManager.default.createDirectory(
            atPath: (stampPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try contents.write(toFile: stampPath, atomically: true, encoding: .utf8)
    }

    @Test func testValidStampIsPreferredOverPreferences() throws {
        try withIsolatedAppSupportDirectory {
            try writeStamp("150")
            // A different (and otherwise valid) Preferences value must be
            // ignored — the stamp wins when it parses.
            try writePreferences(lastChromeVersion: "100.0.0.0", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 150)
        }
    }

    @Test func testMalformedStampFallsBackToPreferences() throws {
        try withIsolatedAppSupportDirectory {
            try writeStamp("150garbage")
            try writePreferences(lastChromeVersion: "150.0.7871.129", profilePath: CEFBridgeManager.cefProfileDirectoryPath())
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 150)
        }
    }

    @Test func testOversizedStampIsUnparseable() throws {
        try withIsolatedAppSupportDirectory {
            // Same corruption class as testOversizedPreferencesMajorIsUnparseable,
            // but on the stamp path — item 1 required the SAME bound and
            // digit validation apply to both.
            try writeStamp("1440")
            #expect(CEFBridgeManager.recordedChromiumMajorVersionOrZeroForTesting() == 0)
        }
    }
}
