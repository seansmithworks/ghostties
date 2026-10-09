import AppKit
import GhosttyKit

extension NSAppearance {
    /// Returns true if the appearance is some kind of dark.
    var isDark: Bool {
        return name.rawValue.lowercased().contains("dark")
    }

    /// The libghostty color scheme matching this appearance.
    var ghosttyColorScheme: ghostty_color_scheme_e {
        isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }

    /// Initialize a desired NSAppearance for the Ghostty configuration.
    convenience init?(ghosttyConfig config: Ghostty.Config) {
        guard let theme = config.windowTheme else { return nil }
        switch theme {
        case "dark":
            self.init(named: .darkAqua)

        case "light":
            self.init(named: .aqua)

        case "auto":
            let color = NSColor(config.backgroundColor)
            if color.isLightColor {
                self.init(named: .aqua)
            } else {
                self.init(named: .darkAqua)
            }

        default:
            return nil
        }
    }
}
