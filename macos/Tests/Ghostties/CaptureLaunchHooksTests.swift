import Foundation
import Testing
@testable import Ghostty

/// Env-string grammar for the DEBUG-only capture launch hooks
/// (`CaptureFixture`'s "Launch-state hooks"). A typo in a hook value must
/// parse to nil (no hook), never to a different state, so a capture can't
/// silently show the wrong thing.
struct CaptureLaunchHooksTests {

    // MARK: - GHOSTTIES_CAPTURE_COMPOSER

    @Test func composerOpenUsesDefaultDelay() {
        #expect(CaptureFixture.parseComposerHook("open")
            == .init(target: .open, delay: CaptureFixture.ComposerHook.defaultDelay))
    }

    @Test func composerOpenWithDelay() {
        #expect(CaptureFixture.parseComposerHook("open:delay=2") == .init(target: .open, delay: 2))
        #expect(CaptureFixture.parseComposerHook("open:delay=0.5") == .init(target: .open, delay: 0.5))
    }

    @Test func composerPrefilledNamesTheProject() {
        #expect(CaptureFixture.parseComposerHook("prefilled:switchboard")
            == .init(target: .prefilled(projectName: "switchboard"), delay: CaptureFixture.ComposerHook.defaultDelay))
        #expect(CaptureFixture.parseComposerHook("prefilled:atlas-api:delay=3")
            == .init(target: .prefilled(projectName: "atlas-api"), delay: 3))
    }

    @Test func composerRejectsMalformedValues() {
        for raw in [nil, "", "new", "prefilled", "prefilled:", "open:delay=", "open:delay=x",
                    "open:delay=-1", "open:wait=2", "prefilled:wren:delay=2:extra"] {
            #expect(CaptureFixture.parseComposerHook(raw) == nil, "\(raw ?? "nil")")
        }
    }

    // MARK: - GHOSTTIES_CAPTURE_PROJECT_SETTINGS

    @Test func projectSettingsBareProject() {
        #expect(CaptureFixture.parseProjectSettingsHook("switchboard")
            == .init(projectName: "switchboard", templateAction: .none))
    }

    @Test func projectSettingsTemplateSuffixes() {
        #expect(CaptureFixture.parseProjectSettingsHook("silo:templates-edit")
            == .init(projectName: "silo", templateAction: .edit))
        #expect(CaptureFixture.parseProjectSettingsHook("silo:templates-delete")
            == .init(projectName: "silo", templateAction: .delete))
    }

    @Test func projectSettingsRejectsMalformedValues() {
        for raw in [nil, "", ":templates-edit", "silo:templates", "silo:edit", "silo:templates-edit:x"] {
            #expect(CaptureFixture.parseProjectSettingsHook(raw) == nil, "\(raw ?? "nil")")
        }
    }

    // MARK: - GHOSTTIES_CAPTURE_EXPAND_PROJECT

    @Test func expandProjectNamesTheProject() {
        #expect(CaptureFixture.parseExpandProject("switchboard") == "switchboard")
        #expect(CaptureFixture.parseExpandProject(" wren ") == "wren")
    }

    @Test func expandProjectRejectsEmpty() {
        #expect(CaptureFixture.parseExpandProject(nil) == nil)
        #expect(CaptureFixture.parseExpandProject("") == nil)
        #expect(CaptureFixture.parseExpandProject("   ") == nil)
    }

    // MARK: - GHOSTTIES_CAPTURE_SIDEBAR_TOGGLE_AFTER

    @Test func sidebarToggleAfterParsesSeconds() {
        #expect(CaptureFixture.parseSidebarToggleAfter("4") == 4)
        #expect(CaptureFixture.parseSidebarToggleAfter("2.5") == 2.5)
    }

    @Test func sidebarToggleAfterRejectsNonPositive() {
        for raw in [nil, "", "0", "-3", "abc", "inf", "nan"] {
            #expect(CaptureFixture.parseSidebarToggleAfter(raw) == nil, "\(raw ?? "nil")")
        }
    }

    // MARK: - Motion hooks (reveal style, collapse, select sequence, fold toggle)

    @Test func revealStyleParses() {
        #expect(CaptureFixture.parseRevealStyle("push") == .push)
        #expect(CaptureFixture.parseRevealStyle("overlay") == .overlay)
        for raw in [nil, "", "Push", "slide"] {
            #expect(CaptureFixture.parseRevealStyle(raw) == nil, "\(raw ?? "nil")")
        }
    }

    @Test func selectSequenceParses() {
        #expect(CaptureFixture.parseSelectSequence("2:1") == .init(interval: 2, steps: 1))
        #expect(CaptureFixture.parseSelectSequence("1.5:-2") == .init(interval: 1.5, steps: -2))
        for raw in [nil, "", "2", "2:", ":1", "0:1", "2:0", "x:1", "2:x", "2:1:1"] {
            #expect(CaptureFixture.parseSelectSequence(raw) == nil, "\(raw ?? "nil")")
        }
    }

    @Test func foldToggleParses() {
        #expect(CaptureFixture.parseFoldToggle("atlas-api:2") == .init(projectName: "atlas-api", interval: 2))
        #expect(CaptureFixture.parseFoldToggle("wren:0.5") == .init(projectName: "wren", interval: 0.5))
        for raw in [nil, "", "wren", "wren:", ":2", "wren:0", "wren:x"] {
            #expect(CaptureFixture.parseFoldToggle(raw) == nil, "\(raw ?? "nil")")
        }
    }

    /// Mutant check: deleting `guard active` in `CaptureFixture.gatedEnv`
    /// (the only gate `env(_:)` goes through) makes the inactive assertions
    /// below return non-nil, failing this test.
    @Test func motionHooksAreInertWithoutFixtureGate() {
        let environment = [
            "GHOSTTIES_CAPTURE_REVEAL_STYLE": "overlay",
            "GHOSTTIES_CAPTURE_RAIL_REVEAL_COLLAPSE_AFTER": "2",
            "GHOSTTIES_CAPTURE_SELECT_SEQUENCE": "2:1",
            "GHOSTTIES_CAPTURE_FOLD_TOGGLE": "wren:2",
        ]
        for (key, value) in environment {
            #expect(CaptureFixture.gatedEnv(key, active: false, in: environment) == nil, "\(key)")
            #expect(CaptureFixture.gatedEnv(key, active: true, in: environment) == value, "\(key)")
        }
        #expect(CaptureFixture.parseRevealStyle(CaptureFixture.gatedEnv("GHOSTTIES_CAPTURE_REVEAL_STYLE", active: true, in: environment)) == .overlay)
        #expect(CaptureFixture.parseSelectSequence(CaptureFixture.gatedEnv("GHOSTTIES_CAPTURE_SELECT_SEQUENCE", active: false, in: environment)) == nil)
    }

    @Test func railRevealCollapseAfterParsesSeconds() {
        #expect(CaptureFixture.parseRailRevealCollapseAfter("3") == 3)
        #expect(CaptureFixture.parseRailRevealCollapseAfter("1.5") == 1.5)
        for raw in [nil, "", "0", "-1", "x", "inf"] {
            #expect(CaptureFixture.parseRailRevealCollapseAfter(raw) == nil, "\(raw ?? "nil")")
        }
    }

    @Test func revealStyleSeedsOnlyTheGivenSuite() {
        let name = "ghostties.test.revealSeed.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let key = SidebarDialTuning.hoverRevealStyleKey
        let standardBefore = UserDefaults.standard.object(forKey: key) as? String

        CaptureFixture.seedRevealStyle(nil, into: suite)
        #expect(suite.object(forKey: key) == nil)
        CaptureFixture.seedRevealStyle(.overlay, into: suite)
        #expect(suite.string(forKey: key) == "overlay")
        #expect(SidebarDialTuning.hoverRevealStyle(defaults: suite) == .overlay)
        #expect(UserDefaults.standard.object(forKey: key) as? String == standardBefore)
    }
}
