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
}
