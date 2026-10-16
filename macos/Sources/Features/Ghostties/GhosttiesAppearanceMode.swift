import AppKit

/// Settings > Appearance > Mode: whether the whole app follows the system
/// appearance or is forced light or dark. Persisted in the app's own defaults
/// (never the user's config); `window-theme = light|dark` in the config wins.
enum GhosttiesAppearanceMode: String, CaseIterable {
    case system, light, dark

    static let key = "ghostties.appearance.mode"

    /// Missing or unknown reads as `.system`.
    static func stored(in defaults: UserDefaults) -> GhosttiesAppearanceMode {
        defaults.string(forKey: key).flatMap(GhosttiesAppearanceMode.init(rawValue:)) ?? .system
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    /// The app appearance to force, or nil to leave it to the caller's
    /// existing `window-theme` handling. The config's `light`/`dark` win over
    /// the mode; `ghostty` is left to Ghostty; otherwise the mode decides.
    static func resolvedAppearanceName(
        configWindowTheme: String?, mode: GhosttiesAppearanceMode
    ) -> NSAppearance.Name? {
        switch configWindowTheme {
        case "light": return .aqua
        case "dark": return .darkAqua
        case "ghostty": return nil
        default:
            switch mode {
            case .system: return nil
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }
    }

    /// Whether the config's `window-theme` fixes the appearance, so the
    /// mode has no say.
    static func isLocked(byConfigWindowTheme theme: String?) -> Bool {
        theme == "light" || theme == "dark" || theme == "ghostty"
    }
}
