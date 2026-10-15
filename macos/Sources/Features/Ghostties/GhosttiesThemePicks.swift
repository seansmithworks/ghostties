import Foundation

/// The theme the Settings > Appearance pane picked for each side, persisted
/// in the app's own defaults (never the user's config). An unpicked side
/// (nil) falls back to the Ghostties theme for that side; no pick at all
/// loads no override layer, so the user's own `theme =` line (or the
/// Ghostties default) is what shows.
struct GhosttiesThemePicks: Equatable {
    var light: String?
    var dark: String?

    init(light: String? = nil, dark: String? = nil) {
        self.light = light
        self.dark = dark
    }

    /// A pair card sets both sides.
    init(pair: GhosttiesThemeCatalog.Pair) {
        self.init(light: pair.light, dark: pair.dark)
    }

    static let none = GhosttiesThemePicks()

    var isEmpty: Bool { light == nil && dark == nil }

    static let lightKey = "ghostties.theme.light"
    static let darkKey = "ghostties.theme.dark"

    /// The app's defaults domain: `.standard` in production, the throwaway
    /// suite in a capture-fixture launch or a hosted test (same store the
    /// sidebar dials use).
    static var appDefaults: UserDefaults { SidebarDialTuning.store }

    static func stored(in defaults: UserDefaults) -> GhosttiesThemePicks {
        GhosttiesThemePicks(
            light: defaults.string(forKey: lightKey),
            dark: defaults.string(forKey: darkKey)
        )
    }

    /// Writes both sides; a nil side removes its key.
    func save(to defaults: UserDefaults) {
        if let light { defaults.set(light, forKey: Self.lightKey) } else { defaults.removeObject(forKey: Self.lightKey) }
        if let dark { defaults.set(dark, forKey: Self.darkKey) } else { defaults.removeObject(forKey: Self.darkKey) }
    }

    static func clear(in defaults: UserDefaults) {
        GhosttiesThemePicks.none.save(to: defaults)
    }
}

/// The curated light/dark theme pairs the pane offers as cards. Slice 3
/// ships the Ghostties pair alone; every name is a bundled theme file
/// (`GhosttiesDefaultThemeTests`).
enum GhosttiesThemeCatalog {
    struct Pair: Equatable {
        let name: String
        let light: String
        let dark: String
    }

    static let ghostties = Pair(name: "Ghostties", light: "Ghostties Light", dark: "Ghostties Dark")

    static let pairs: [Pair] = [ghostties]

    /// Every theme bundled in `ghostty/themes`, sorted for a picker.
    static func bundledThemeNames(bundle: Bundle = .main) -> [String] {
        guard let dir = bundle.resourceURL?.appendingPathComponent("ghostty/themes"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// What the user's own config says about colours, read by scanning its
/// lines (and the files it includes). It never loads or writes the config.
enum GhosttiesThemeProbe {
    enum Kind {
        /// No `theme`, `background`, `foreground` or `palette` line.
        case none
        /// A `theme =` line and no explicit colour line: a pick can beat it.
        case themeOnly
        /// An explicit `background`, `foreground` or `palette` line: Ghostty
        /// replays these over any theme, so a pick cannot beat them.
        case explicitColors
    }

    struct Result: Equatable {
        let kind: Kind
        /// The last `theme =` line's value, verbatim (display only).
        let themeName: String?
    }

    /// `configPath` nil scans the default user config files, in Ghostty's
    /// load order.
    static func probe(configPath: String?) -> Result {
        let files = configPath.map { [URL(fileURLWithPath: $0)] } ?? defaultFiles()
        var scan = Scan()
        scan.load(files)
        if scan.explicitColors { return Result(kind: .explicitColors, themeName: scan.theme) }
        if let theme = scan.theme { return Result(kind: .themeOnly, themeName: theme) }
        return Result(kind: .none, themeName: nil)
    }

    /// The theme a `theme =` value shows on each side: `light:A,dark:B`
    /// splits, a single name is both. Nil for a side the value leaves out.
    static func sides(of value: String) -> (light: String?, dark: String?) {
        guard value.contains("light:") || value.contains("dark:") else { return (value, value) }
        var light: String?
        var dark: String?
        for part in value.split(separator: ",") {
            let entry = part.trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix("light:") { light = String(entry.dropFirst("light:".count)) }
            if entry.hasPrefix("dark:") { dark = String(entry.dropFirst("dark:".count)) }
        }
        return (light, dark)
    }

    /// Ghostty's default user files (`Config.loadDefaultFiles`): XDG, then
    /// the app's Application Support folder, legacy name before current.
    private static func defaultFiles() -> [URL] {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let xdg = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        var files = [
            xdg.appendingPathComponent("ghostty/config"),
            xdg.appendingPathComponent("ghostty/config.ghostty"),
        ]
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("com.seansmithdesign.ghostties")
            files.append(dir.appendingPathComponent("config"))
            files.append(dir.appendingPathComponent("config.ghostty"))
        }
        return files
    }

    private static let colorKeys: Set<String> = ["background", "foreground", "palette"]

    /// Mirrors Ghostty's load order (`Config.loadRecursiveFiles`): every
    /// top-level file in order, then the queued `config-file` includes in
    /// queue order, each include appending its own to the end of the queue.
    /// An include loads once; top-level files are not deduplicated.
    private struct Scan {
        var theme: String?
        private var explicitKeys: Set<String> = []
        private var includes: [URL] = []
        private var loadedIncludes: Set<String> = []

        var explicitColors: Bool { !explicitKeys.isEmpty }

        mutating func load(_ files: [URL]) {
            for file in files { read(file) }
            var i = 0
            while i < includes.count {
                let include = includes[i]
                i += 1
                guard loadedIncludes.insert(include.standardizedFileURL.path).inserted else { continue }
                read(include)
            }
        }

        private mutating func read(_ url: URL) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            for raw in text.split(whereSeparator: \.isNewline) {
                // `cli.args.LineIterator`: trim, skip comments, unquote a
                // fully quoted value.
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.hasPrefix("#"),
                      let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = Self.unquote(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
                if key == "theme" {
                    theme = value.isEmpty ? nil : value
                } else if GhosttiesThemeProbe.colorKeys.contains(key) {
                    // An empty value resets the key to its default.
                    if value.isEmpty { explicitKeys.remove(key) } else { explicitKeys.insert(key) }
                } else if key == "config-file" {
                    queueInclude(value, from: url)
                }
            }
        }

        /// `RepeatablePath.parseCLI` + `Path.parse`: an empty value clears
        /// the queue; the optional `?` comes off before the quotes; a value
        /// empty after that is ignored. A relative path resolves against the
        /// including file's directory, `~/` against home.
        private mutating func queueInclude(_ raw: String, from file: URL) {
            guard !raw.isEmpty else {
                includes.removeAll()
                return
            }
            var path = raw
            if path.hasPrefix("?") { path.removeFirst() }
            path = Self.unquote(path)
            guard !path.isEmpty else { return }
            let target: URL
            if path.hasPrefix("/") {
                target = URL(fileURLWithPath: path)
            } else if path.hasPrefix("~/") {
                target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
            } else {
                target = file.deletingLastPathComponent().appendingPathComponent(path)
            }
            includes.append(target)
        }

        private static func unquote(_ s: String) -> String {
            guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
            return String(s.dropFirst().dropLast())
        }
    }
}

/// What the Appearance pane shows as selected.
enum GhosttiesAppearanceState: Equatable {
    /// No pick and no user theme: the Ghostties default.
    case ghostties
    /// No pick; the user's own `theme =` line, adopted as Custom.
    case custom(themeName: String)
    /// A pick (an unpicked side shows the Ghostties theme for that side).
    case picked(light: String, dark: String)
    /// Explicit colour keys in the user's config; they beat any pick.
    case setByConfig

    static func resolve(configPath: String?, picks: GhosttiesThemePicks) -> GhosttiesAppearanceState {
        let probe = GhosttiesThemeProbe.probe(configPath: configPath)
        if probe.kind == .explicitColors { return .setByConfig }
        if !picks.isEmpty {
            return .picked(
                light: picks.light ?? GhosttiesThemeCatalog.ghostties.light,
                dark: picks.dark ?? GhosttiesThemeCatalog.ghostties.dark
            )
        }
        if probe.kind == .themeOnly, let name = probe.themeName { return .custom(themeName: name) }
        return .ghostties
    }
}
