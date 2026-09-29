import Foundation

/// Ghostties-level config defaults, layered UNDER the user's config.
///
/// libghostty has no string-load API, so the defaults are written to a
/// temp file and loaded first in `Ghostty.Config.loadConfig` — every file
/// loaded after it (the user's config, CLI args, `config-file` includes)
/// still overrides any key set here.
enum GhosttiesConfigDefaults {
    /// Terminal text padding inside the floating card (round 6, Flow 07:
    /// `flow07.html` layer `r2Ds7p`/"Terminal Card", `padding: 20px` on all
    /// sides). This is the text inset within the terminal surface —
    /// separate from `terminalInset`, the 8pt outer card margin (unchanged
    /// by this round; see `WorkspaceLayout.terminalInset`).
    static let contents = """
    window-padding-x = 20
    window-padding-y = 20
    """

    /// Writes the defaults file and returns its path, or nil if the write
    /// failed (the app then just runs on upstream defaults).
    static func fileURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-config-defaults")
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
