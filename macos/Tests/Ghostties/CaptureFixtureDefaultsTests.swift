import Foundation
import Testing
@testable import Ghostty

/// In fixture mode the composer store and the Cmd+T preference must use the
/// throwaway `ghostties.capture.<pid>` suite, never Sean's real Dev domain.
@MainActor
@Suite(.serialized)
struct CaptureFixtureDefaultsTests {

    private let suiteName = "ghostties.capture.\(ProcessInfo.processInfo.processIdentifier)"
    private let probeKey = "ghostties.captureFixtureDefaultsTests.probe"

    @Test func suiteNameIsPerProcess() {
        #expect(CaptureFixture.defaultsSuiteName == suiteName)
    }

    @Test func storeResolvesToCaptureSuiteInFixtureMode() {
        let store = SessionComposerStore(captureFixtureActive: true)
        defer {
            CaptureFixture.cleanUpDefaults(fixtureActive: true)
            UserDefaults.standard.removeObject(forKey: probeKey) // a regression must not leak into Dev's domain
        }
        store.defaultsForTesting.set("x", forKey: probeKey)
        let suite = UserDefaults(suiteName: suiteName)!
        #expect(suite.string(forKey: probeKey) == "x")
        #expect(UserDefaults.standard.object(forKey: probeKey) == nil)
    }

    @Test func storeUsesStandardOutsideFixtureMode() {
        let store = SessionComposerStore(captureFixtureActive: false)
        #expect(store.defaultsForTesting === UserDefaults.standard)
    }

    @Test func prefResolvesToCaptureSuiteInFixtureMode() {
        let defaults = WorkspaceViewContainer.composerPreferenceDefaults(fixtureActive: true)
        let key = "ghostties.newSessionOpensComposer"
        let standardBefore = UserDefaults.standard.object(forKey: key)
        defer {
            CaptureFixture.cleanUpDefaults(fixtureActive: true)
            // A regression would have written Dev's domain; put it back.
            if let standardBefore { UserDefaults.standard.set(standardBefore, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        defaults.set(false, forKey: key)
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == false)
        #expect(UserDefaults(suiteName: suiteName)!.object(forKey: "ghostties.newSessionOpensComposer") != nil)
        #expect(WorkspaceViewContainer.composerPreferenceDefaults(fixtureActive: false) === UserDefaults.standard)
    }

    @Test func cleanupRemovesTheSuite() {
        let defaults = CaptureFixture.defaults(fixtureActive: true)
        defaults.set("x", forKey: probeKey)
        #expect(defaults.string(forKey: probeKey) == "x")
        CaptureFixture.cleanUpDefaults(fixtureActive: true)
        #expect(UserDefaults(suiteName: suiteName)!.string(forKey: probeKey) == nil)
        #expect(defaults.string(forKey: probeKey) == nil)
        // cfprefsd flushes asynchronously; nothing may reappear after a beat.
        Thread.sleep(forTimeInterval: 0.5)
        #expect(!FileManager.default.fileExists(atPath: CaptureFixture.defaultsPlistURL.path))
    }
}
