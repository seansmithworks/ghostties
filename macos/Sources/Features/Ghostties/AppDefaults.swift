import Foundation

/// The defaults domain for the app's own settings (approvals, sidebar tab,
/// view mode, widths): the scoped store when one is bound, else the shared
/// one. Every reader and writer of those settings goes through it, including
/// their `@AppStorage`s. `scripts/check-test-defaults.sh` holds that line.
enum AppDefaults {
    static var store: UserDefaults { SidebarDialTuning.scopedStore ?? sharedStore }

    /// `.standard` in production, and in a capture-fixture launch, where the
    /// fixture's tab override and `verify` rely on it (the dial store is the
    /// one that moves to the fixture's suite). The test bundle swaps in its
    /// throwaway suite at load (`GhosttiesTestIsolation`): a hosted test runs
    /// inside the app, so `.standard` is the real domain of any live build
    /// sharing its bundle ID, and a write there reaches that build's windows.
    nonisolated(unsafe) static var sharedStore: UserDefaults = .standard
}
