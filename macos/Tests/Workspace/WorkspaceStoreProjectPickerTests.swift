import Foundation
import Testing
@testable import Ghostty

/// Tests for the Phase 4 project-picker convergence (D10 fix):
/// `WorkspaceStore.addProjectViaFolderPicker` persists the last-used
/// directory via `@AppStorage("ghostties.lastProjectPickerDirectory")` so
/// the panel reopens where the user last was.
///
/// `addProjectViaFolderPicker` itself calls `NSOpenPanel.runModal()`, which
/// blocks on UI and cannot run in a unit test. What IS genuinely testable
/// without UI is the persistence contract the fix depends on: the exact
/// `UserDefaults.standard` key round-trips a directory path, and an empty
/// value is treated as "no starting directory" (the store's `!isEmpty`
/// guard). These tests exercise `UserDefaults.standard` directly under that
/// key, saving and restoring the real value so the suite doesn't leak state
/// into other tests or the developer's actual defaults.
struct WorkspaceStoreProjectPickerTests {

    private static let key = "ghostties.lastProjectPickerDirectory"

    @Test("Last-used picker directory round-trips through UserDefaults")
    func lastPickerDirectoryRoundTrips() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.key)
        defer {
            if let saved {
                defaults.set(saved, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }

        let path = "/Users/example/Code/some-project"
        defaults.set(path, forKey: Self.key)

        #expect(defaults.string(forKey: Self.key) == path)
    }

    @Test("Absent last-used directory reads back as empty, the store's no-starting-directory sentinel")
    func absentLastPickerDirectoryReadsEmpty() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.key)
        defer {
            if let saved {
                defaults.set(saved, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }

        defaults.removeObject(forKey: Self.key)

        // @AppStorage's declared default is "" when the key is absent —
        // this is the exact value `addProjectViaFolderPicker` checks with
        // `!isEmpty` before setting `panel.directoryURL`.
        #expect((defaults.string(forKey: Self.key) ?? "").isEmpty)
    }
}
