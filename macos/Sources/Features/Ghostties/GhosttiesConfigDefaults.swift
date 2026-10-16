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
    ///
    /// Terminal theme: the Ghostties pair bundled in
    /// `macos/Resources/ghostty/themes/` (Apple System Colors with the
    /// background set to the card's canvas fill — DESIGN.md "Terminal
    /// theme"). A user `theme =` line loads later and wins.
    static let contents = """
    window-padding-x = 20
    window-padding-y = 20
    theme = light:Ghostties Light,dark:Ghostties Dark
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

    /// The Settings > Appearance pick, as one config line, or nil when
    /// nothing is picked. Loaded AFTER the user's config (see
    /// `Ghostty.Config.loadConfig`), so it beats their `theme =` line; their
    /// explicit `background`/`foreground`/`palette` lines still win, because
    /// Ghostty replays explicit keys over any theme. An unpicked side keeps
    /// the Ghostties theme for that side.
    static func overrideContents(picks: GhosttiesThemePicks) -> String? {
        guard !picks.isEmpty else { return nil }
        let light = picks.light ?? GhosttiesThemeCatalog.ghostties.light
        let dark = picks.dark ?? GhosttiesThemeCatalog.ghostties.dark
        return "theme = light:\(light),dark:\(dark)"
    }

    /// Writes the override file and returns its path; nil when nothing is
    /// picked or the write failed. Never the user's config file.
    static func overrideFileURL(picks: GhosttiesThemePicks) -> URL? {
        guard let contents = overrideContents(picks: picks) else { return nil }
        // One file per call: configs load concurrently (hosted tests, a
        // reload racing a surface reload), so a shared path could be read
        // mid-rewrite by another load with different picks.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-config-override-\(UUID().uuidString)")
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
