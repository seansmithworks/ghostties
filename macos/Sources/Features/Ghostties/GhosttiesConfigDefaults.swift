import Foundation

/// Ghostties-level config defaults, layered UNDER the user's config.
///
/// libghostty has no string-load API, so the defaults are written to a
/// temp file and loaded first in `Ghostty.Config.loadConfig` — every file
/// loaded after it (the user's config, CLI args, `config-file` includes)
/// still overrides any key set here.
enum GhosttiesConfigDefaults {
    /// Terminal text padding inside the floating card (Sean,
    /// sidebar-presence review round 3): 16pt horizontal, 8pt vertical.
    /// This is the text inset within the terminal surface — separate from
    /// `terminalInset`, the 8pt outer card margin.
    static let contents = """
    window-padding-x = 16
    window-padding-y = 8
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
