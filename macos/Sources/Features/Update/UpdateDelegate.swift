import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    /// Test-only override for the resolved Info.plist `SUFeedURL` — `Bundle.main`'s
    /// Info.plist can't be mutated at runtime inside `xcodebuild test`, so tests set
    /// this instead. `nil` (the default) means "read from `Bundle.main` as normal."
    static var testOverrideInfoPlistFeedURL: String?

    func feedURLString(for updater: SPUUpdater) -> String? {
        // Honour an explicit Info.plist SUFeedURL when present (e.g. the demo
        // build's deliberately-unreachable feed). The shipping app carries no
        // SUFeedURL, so this is inert for it.
        let plistFeedURL = UpdateDriver.testOverrideInfoPlistFeedURL
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        if let plistFeedURL, !plistFeedURL.isEmpty {
            return plistFeedURL
        }

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }

        // Ghostties-specific appcast feeds (not upstream Ghostty).
        // Hosted on ghostties.org (Vercel) — updated by release workflow after each tag.
        // Stable channel: only receives non-beta releases.
        // Tip/beta channel: receives all releases including betas.
        switch appDelegate.ghostty.config.autoUpdateChannel {
        case .tip: return "https://ghostties.org/appcast-beta.xml"
        case .stable: return "https://ghostties.org/appcast-stable.xml"
        }
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }
}
