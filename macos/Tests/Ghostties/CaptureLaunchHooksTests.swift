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
}
