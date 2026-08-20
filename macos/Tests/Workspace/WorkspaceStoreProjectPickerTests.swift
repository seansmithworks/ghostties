import Foundation
import Testing
@testable import Ghostty

/// Tests for the Phase 4 project-picker convergence (D10 fix):
/// `WorkspaceStore.addProjectViaFolderPicker` persists the last-used
/// directory via `@AppStorage("ghostties.lastProjectPickerDirectory")` on a
/// `static` property, read and written entirely outside any SwiftUI view.
///
/// `addProjectViaFolderPicker` itself calls `NSOpenPanel.runModal()`, which
/// blocks on UI and cannot run in a unit test. What IS testable — and is
/// the genuinely risky mechanic here — is whether `@AppStorage` on a static
/// property actually persists through `UserDefaults.standard` under the
/// key. This test writes through `WorkspaceStore`'s `#if DEBUG` accessor
/// (exercising the real wrapper), then reads `UserDefaults.standard` under
/// the key as a literal string, so a typo in the `@AppStorage` key in
/// production would make this test fail. It saves and restores the real
/// value so the suite doesn't leak state into other tests or the
/// developer's actual defaults.
struct WorkspaceStoreProjectPickerTests {

    @Test("Last-used picker directory round-trips through the real @AppStorage-backed UserDefaults key")
    @MainActor
    func lastPickerDirectoryRoundTripsThroughAppStorage() {
        let key = "ghostties.lastProjectPickerDirectory"
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: key)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let path = "/Users/example/Code/some-project"
        WorkspaceStore.testLastProjectPickerDirectoryPath = path

        #expect(defaults.string(forKey: key) == path)
        #expect(WorkspaceStore.testLastProjectPickerDirectoryPath == path)
    }
}
