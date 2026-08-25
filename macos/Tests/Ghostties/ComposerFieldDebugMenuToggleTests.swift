import AppKit
import Testing
@testable import Ghostty

/// Composer field A/B toggle (composer-ui-11) — the Debug menu's
/// "Composer: New Text Field (Experimental)" item, added so Sean can flip
/// between the two composer field implementations from inside the running
/// app instead of `defaults write` + relaunch.
///
/// Calls the REAL `AppDelegate.toggleComposerModelBField(_:)` selector via
/// the Objective-C runtime (which ignores Swift's `private` — the method is
/// still `@objc` for menu dispatch), then asserts against
/// `ComposerGhostTextField.modelBFieldStorageKey`, the actual production
/// constant `@AppStorage` binds in `SessionComposerPalette`. A test that
/// re-declared the key as a local string literal would pass even if the
/// production toggle wrote a typo'd key — see
/// `feedback_vacuous-tests-pass-green.md`, three prior instances in this
/// repo. This one fails on that typo because both the toggle and the
/// assertion resolve the same symbol.
#if DEBUG
@MainActor
struct ComposerFieldDebugMenuToggleTests {
    @Test func toggleFlipsProductionAppStorageKey() {
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)

        let appDelegate = AppDelegate()
        let selector = Selector(("toggleComposerModelBField:"))
        #expect(appDelegate.responds(to: selector))

        appDelegate.perform(selector, with: NSMenuItem())
        #expect(defaults.bool(forKey: key) == true)

        appDelegate.perform(selector, with: NSMenuItem())
        #expect(defaults.bool(forKey: key) == false)
    }
}
#endif
