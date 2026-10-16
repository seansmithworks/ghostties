import AppKit
import Foundation
import os

// The composer's theme picker: typing `theme` (or `/theme`) in the Cmd+T
// composer turns it into a live theme picker. Two presentations share one
// engine: C1 shows matching theme names as chips in the status-strip slot,
// C2 (the default) grows the card into a grid of light|dark thumbnails.
// Moving the selection previews the theme on the whole window (terminal and
// chrome) through a temporary config override; Return stores the pick,
// Esc or closing the composer drops the override.
//
// This file is the non-visual core (`ComposerThemePickerTests`); the views
// live in `ComposerThemePickerViews.swift`.

// MARK: - Parsing

/// What the composer's text says about the theme picker.
enum ComposerThemeCommand: Equatable {
    /// `theme`, `/theme dra`: picker mode. `query` is trimmed and lowercased.
    case theme(query: String)
    /// `the`, `/t`: a proper prefix of the word. `completion` is the ghost
    /// text to append (the rest of the word plus a space).
    case partial(completion: String)
    case none

    static let word = "theme"

    /// An optional single leading `/`, then `theme` as the FIRST token (any
    /// case), then end of input or whitespace and a query. A bare word that
    /// starts a project's name (`theme` for `themes-app`, `the` for
    /// `thesis`) is that project's, never the picker's; a leading `/` is
    /// always the picker.
    static func parse(_ text: String, projectNames: [String] = []) -> ComposerThemeCommand {
        var rest = Substring(text).drop(while: \.isWhitespace)
        let slashed = rest.first == "/"
        if slashed { rest = rest.dropFirst() }
        let token = rest.prefix(while: { !$0.isWhitespace })
        let tail = rest.dropFirst(token.count)
        let typed = token.lowercased()
        guard !typed.isEmpty else { return .none }
        let projects = projectNames.map { $0.lowercased() }
        if !slashed, projects.contains(where: { $0.hasPrefix(typed) }) { return .none }

        if typed == word {
            return .theme(query: tail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        guard tail.isEmpty, word.hasPrefix(typed), typed.count >= (slashed ? 1 : 3) else { return .none }
        return .partial(completion: String(word.dropFirst(typed.count)) + " ")
    }
}

// MARK: - Catalog

/// A light/dark theme pair as the picker offers it. The curated set is
/// complete pairs; a one-sided family is still valid (C1's matcher).
struct ThemeFamily: Equatable {
    let name: String
    let light: String?
    let dark: String?

    init(name: String, light: String?, dark: String?) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// The theme this family shows on `polarity`'s side, else its other side.
    func themeName(for polarity: ChromeTheme.Polarity) -> String {
        switch polarity {
        case .light: return light ?? dark ?? name
        case .dark: return dark ?? light ?? name
        }
    }

    /// Both sides set: a missing side is filled by the other, so a one-sided
    /// family shows on either appearance.
    var picks: GhosttiesThemePicks {
        GhosttiesThemePicks(light: light ?? dark, dark: dark ?? light)
    }

    /// Each theme in the family, light side first.
    var members: [ThemeChoice] {
        var out: [ThemeChoice] = []
        if let light { out.append(ThemeChoice(name: light, family: name, polarity: .light)) }
        if let dark { out.append(ThemeChoice(name: dark, family: name, polarity: .dark)) }
        return out
    }
}

/// One theme as a chip: its name, its family, and which side it is.
struct ThemeChoice: Equatable {
    let name: String
    let family: String
    let polarity: ChromeTheme.Polarity
}

extension GhosttiesThemeCatalog {
    /// The curated set the picker grid offers, Ghostties first: eight
    /// complete light/dark pairs. Every name is a bundled theme file
    /// (`v2CatalogIsTheEightCompletePairs`).
    static let families: [ThemeFamily] = [
        ThemeFamily(name: ghostties.name, light: ghostties.light, dark: ghostties.dark),
        ThemeFamily(name: "Catppuccin", light: "Catppuccin Latte", dark: "Catppuccin Mocha"),
        ThemeFamily(name: "Rosé Pine", light: "Rose Pine Dawn", dark: "Rose Pine"),
        ThemeFamily(name: "Tokyo Night", light: "TokyoNight Day", dark: "TokyoNight Night"),
        ThemeFamily(name: "GitHub", light: "GitHub Light Default", dark: "GitHub Dark Default"),
        ThemeFamily(name: "Gruvbox", light: "Gruvbox Light", dark: "Gruvbox Dark"),
        ThemeFamily(name: "Everforest", light: "Everforest Light Med", dark: "Everforest Dark Hard"),
        ThemeFamily(name: "Nord", light: "Nord Light", dark: "Nord"),
    ]

    /// The pairs "All themes" lists first: the curated set, then every
    /// bundled `<Name> Light` + `<Name> Dark` (or `Day` + `Night`) pair the
    /// curated set doesn't already hold, in `themes` order.
    static func browseFamilies(themes: [String]) -> [ThemeFamily] {
        let available = Set(themes)
        var taken = Set(families.flatMap { [$0.light, $0.dark].compactMap { $0 } })
        var out = families
        for name in themes where !taken.contains(name) {
            for (lightSuffix, darkSuffix) in [(" Light", " Dark"), (" Day", " Night")] where name.hasSuffix(lightSuffix) {
                let base = String(name.dropLast(lightSuffix.count))
                let dark = base + darkSuffix
                guard available.contains(dark), !taken.contains(dark) else { continue }
                out.append(ThemeFamily(name: base, light: name, dark: dark))
                taken.formUnion([name, dark])
            }
        }
        return out
    }

    /// `picks` with an unpicked side filled by the Ghostties theme for that
    /// side: what actually shows.
    static func resolved(_ picks: GhosttiesThemePicks) -> GhosttiesThemePicks {
        GhosttiesThemePicks(light: picks.light ?? ghostties.light, dark: picks.dark ?? ghostties.dark)
    }
}

// MARK: - Grid

/// One cell of the 3x3 theme grid the composer and Settings share.
enum ThemeGridCell: Equatable {
    case family(ThemeFamily)
    /// What shows is outside the curated set: the user's own theme, or a
    /// mixed pair.
    case custom(light: String, dark: String)
    /// Opens "All themes"; not a theme itself.
    case allThemes

    var picks: GhosttiesThemePicks? {
        switch self {
        case .family(let family): return family.picks
        case .custom(let light, let dark): return GhosttiesThemePicks(light: light, dark: dark)
        case .allThemes: return nil
        }
    }
}

enum ThemeGridModel {
    static let columns = 3
    static let cellCount = 9

    /// The curated families then All themes. When what shows (`current`, a
    /// nil side read as Ghostties) is no family, a Custom cell takes the
    /// first slot and the last family drops off, so it is always 9 cells.
    static func cells(current: GhosttiesThemePicks) -> [ThemeGridCell] {
        let families = GhosttiesThemeCatalog.families
        let shown = GhosttiesThemeCatalog.resolved(current)
        let familySlots = cellCount - 1
        if families.contains(where: { $0.picks == shown }) {
            return families.prefix(familySlots).map(ThemeGridCell.family) + [.allThemes]
        }
        let custom = ThemeGridCell.custom(
            light: shown.light ?? GhosttiesThemeCatalog.ghostties.light,
            dark: shown.dark ?? GhosttiesThemeCatalog.ghostties.dark
        )
        return [custom] + families.prefix(familySlots - 1).map(ThemeGridCell.family) + [.allThemes]
    }

    /// The cell that shows now: the matching family, else Custom (0).
    static func selectedIndex(current: GhosttiesThemePicks) -> Int {
        let shown = GhosttiesThemeCatalog.resolved(current)
        return cells(current: current).firstIndex {
            if case .family(let family) = $0 { return family.picks == shown }
            return false
        } ?? 0
    }
}

// MARK: - All themes

/// The chips over "All themes", in order.
enum ThemeBrowseFilter: CaseIterable {
    case pairs, light, dark

    var title: String {
        switch self {
        case .pairs: return "Pairs"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// One card in "All themes": a pair, or one theme tagged light or dark.
enum ThemeBrowseEntry: Equatable {
    case family(ThemeFamily)
    case single(name: String, polarity: ChromeTheme.Polarity)

    var title: String {
        switch self {
        case .family(let family): return family.name
        case .single(let name, _): return name
        }
    }
}

enum ThemeBrowseModel {
    /// Light or dark by the theme file's background, with `ChromeTheme`'s
    /// rule, from one read of the file. Cached: "All themes" asks for every
    /// bundled theme. Safe on any thread.
    static func polarity(ofTheme name: String) -> ChromeTheme.Polarity {
        if let cached = polarityCache.value(name) { return cached }
        let colors = ThemeFile.backgroundAndForeground(named: name)
        // The same fallbacks as `ThemeFile.background(named:)` and
        // `ThemePreview`: the window colour, then the background.
        let background = colors.background ?? .windowBackgroundColor
        let polarity = ChromeTheme.polarity(background: background, foreground: colors.foreground ?? background)
        polarityCache.store(polarity, for: name)
        return polarity
    }

    /// Classifies `themes` on a background queue, so opening All themes
    /// finds them cached instead of reading every file on the main thread.
    /// Runs once per process; later calls return at once. A lookup that
    /// arrives first computes (and caches) that one theme itself, with the
    /// same result.
    static func warmPolarityCache(themes: [String]) {
        guard polarityCache.claimWarmUp() else { return }
        DispatchQueue.global(qos: .utility).async {
            for name in themes { _ = polarity(ofTheme: name) }
        }
    }

    /// `.pairs`: matching families, then the other themes. `.light` /
    /// `.dark`: every theme of that polarity, family members included.
    /// `query` (trimmed, case-insensitive substring) filters all three; a
    /// family matches on its name or either member's.
    static func entries(
        filter: ThemeBrowseFilter, query: String, themes: [String],
        families: [ThemeFamily] = GhosttiesThemeCatalog.families,
        polarity: (String) -> ChromeTheme.Polarity = ThemeBrowseModel.polarity(ofTheme:)
    ) -> [ThemeBrowseEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ name: String?) -> Bool {
            guard let name else { return false }
            return q.isEmpty || name.lowercased().contains(q)
        }
        switch filter {
        case .pairs:
            let members = Set(families.flatMap { [$0.light, $0.dark].compactMap { $0 } })
            let pairs = families
                .filter { matches($0.name) || matches($0.light) || matches($0.dark) }
                .map(ThemeBrowseEntry.family)
            let singles = themes
                .filter { !members.contains($0) && matches($0) }
                .map { ThemeBrowseEntry.single(name: $0, polarity: polarity($0)) }
            return pairs + singles
        case .light, .dark:
            let wanted: ChromeTheme.Polarity = filter == .light ? .light : .dark
            return themes.compactMap { name in
                guard matches(name) else { return nil }
                let side = polarity(name)
                return side == wanted ? ThemeBrowseEntry.single(name: name, polarity: side) : nil
            }
        }
    }

    /// The picks after choosing `entry` from `current` (a nil side reads as
    /// Ghostties). A pair sets both sides; a single theme sets one side
    /// only, `side` if given, else its own polarity.
    static func picks(
        choosing entry: ThemeBrowseEntry, side: ChromeTheme.Polarity?,
        current: GhosttiesThemePicks
    ) -> GhosttiesThemePicks {
        let shown = GhosttiesThemeCatalog.resolved(current)
        switch entry {
        case .family(let family):
            return family.picks
        case .single(let name, let polarity):
            switch side ?? polarity {
            case .light: return GhosttiesThemePicks(light: name, dark: shown.dark)
            case .dark: return GhosttiesThemePicks(light: shown.light, dark: name)
            }
        }
    }

    private static let polarityCache = PolarityCache()

    /// Every read and write of its state holds `lock`, so the warm-up
    /// queue and the main thread can share it.
    private final class PolarityCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: ChromeTheme.Polarity] = [:]
        private var warmUpClaimed = false

        /// True for the first caller only.
        func claimWarmUp() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !warmUpClaimed else { return false }
            warmUpClaimed = true
            return true
        }

        func value(_ name: String) -> ChromeTheme.Polarity? {
            lock.lock()
            defer { lock.unlock() }
            return values[name]
        }

        func store(_ polarity: ChromeTheme.Polarity, for name: String) {
            lock.lock()
            defer { lock.unlock() }
            values[name] = polarity
        }
    }
}

// MARK: - Matching

enum ComposerThemeMatcher {
    /// C1: individual theme names. Ranked by: the applied theme for this
    /// appearance first (empty query only), then the appearance's own side,
    /// then a name that starts with the query, then catalog order.
    static func chips(
        query: String,
        families: [ThemeFamily],
        applied: GhosttiesThemePicks,
        appearance: ChromeTheme.Polarity,
        limit: Int = 6
    ) -> [ThemeChoice] {
        let q = normalized(query)
        let current = GhosttiesThemeCatalog.resolved(applied)
        let currentName = appearance == .light ? current.light : current.dark
        var pool: [(choice: ThemeChoice, order: Int)] = []
        for family in families {
            for choice in family.members where q.isEmpty
                || choice.name.lowercased().contains(q) || family.name.lowercased().contains(q) {
                pool.append((choice, pool.count))
            }
        }
        func key(_ entry: (choice: ThemeChoice, order: Int)) -> (Int, Int, Int, Int) {
            (
                q.isEmpty && entry.choice.name == currentName ? 0 : 1,
                entry.choice.polarity == appearance ? 0 : 1,
                entry.choice.name.lowercased().hasPrefix(q) ? 0 : 1,
                entry.order
            )
        }
        return pool.sorted { key($0) < key($1) }.prefix(max(limit, 0)).map(\.choice)
    }

    /// The ghost text after what is typed: the rest of the first top name
    /// the typed query starts (in that name's case), the space after a bare
    /// `theme`, else nothing. Reads the query as typed (trailing space kept)
    /// so `theme rose ` completes `Pine`, not ` Pine`.
    static func ghostSuffix(typed: String, query: String, topNames: [String]) -> String {
        let typedQuery: String
        if let tail = tail(afterWordIn: typed) {
            guard !tail.isEmpty else { return " " }
            typedQuery = String(tail.drop(while: \.isWhitespace))
        } else {
            typedQuery = query
        }
        guard !typedQuery.isEmpty else { return "" }
        for name in topNames {
            if let range = name.range(of: typedQuery, options: [.caseInsensitive, .anchored]) {
                return String(name[range.upperBound...])
            }
        }
        return ""
    }

    /// What follows `theme` in `typed`, or nil when `typed` isn't the command.
    private static func tail(afterWordIn typed: String) -> Substring? {
        var rest = Substring(typed).drop(while: \.isWhitespace)
        if rest.first == "/" { rest = rest.dropFirst() }
        guard rest.lowercased().hasPrefix(ComposerThemeCommand.word) else { return nil }
        let tail = rest.dropFirst(ComposerThemeCommand.word.count)
        guard tail.first.map(\.isWhitespace) ?? true else { return nil }
        return tail
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Live preview

/// Previews a theme on the whole window without storing it. `reload` loads
/// the TEMPORARY override picks, or nil for "the stored picks as usual".
/// Defaults are only written by a commit.
@MainActor
final class ThemePreviewController {
    private let defaults: UserDefaults
    private let reload: (GhosttiesThemePicks?) -> Void

    /// The picks being previewed; nil when nothing is.
    private(set) var previewing: GhosttiesThemePicks?
    var isPreviewing: Bool { previewing != nil }

    init(defaults: UserDefaults, reload: @escaping (GhosttiesThemePicks?) -> Void) {
        self.defaults = defaults
        self.reload = reload
    }

    private var stored: GhosttiesThemePicks { .stored(in: defaults) }

    /// Whether `picks` is what a stored pick already shows. With no pick
    /// nothing counts as applied: the user's own `theme =` line (Custom) may
    /// be showing, so even the Ghostties pair is a real preview.
    private func isApplied(_ picks: GhosttiesThemePicks) -> Bool {
        let stored = stored
        return !stored.isEmpty && GhosttiesThemeCatalog.resolved(stored) == GhosttiesThemeCatalog.resolved(picks)
    }

    /// Shows `light`/`dark` (a missing side takes the other). Previewing the
    /// applied theme ends any preview instead.
    func preview(light: String?, dark: String?) {
        guard light != nil || dark != nil else { return revert() }
        let picks = GhosttiesThemePicks(light: light ?? dark, dark: dark ?? light)
        guard !isApplied(picks) else { return revert() }
        guard picks != previewing else { return }
        previewing = picks
        reload(picks)
    }

    /// Back to the stored picks. A no-op when not previewing.
    func revert() {
        guard previewing != nil else { return }
        previewing = nil
        reload(nil)
    }

    /// Stores the previewed picks. False (and nothing happens) when not
    /// previewing.
    @discardableResult
    func commit() -> Bool {
        guard let picks = previewing else { return false }
        picks.save(to: defaults)
        previewing = nil
        reload(nil)
        return true
    }

    /// Stores these picks directly, ending any preview.
    func commit(light: String?, dark: String?) {
        let picks = GhosttiesThemePicks(light: light ?? dark, dark: dark ?? light)
        let wasPreviewing = previewing != nil
        previewing = nil
        guard picks != stored else {
            if wasPreviewing { reload(nil) }
            return
        }
        picks.save(to: defaults)
        reload(nil)
    }
}

/// The production reload hook: loads the override into `Ghostty.App` and
/// reloads the config, so the terminal re-themes and the chrome follows
/// through the config-change path (`ChromeThemeStore`).
///
/// A reload blocks the main thread for ~50-100ms, so held arrow keys would
/// queue one reload each and lag behind. Requests are coalesced instead: one
/// reload runs per main-loop turn, and a request that arrives while one is
/// in flight replaces the pending one. The last request always lands.
@MainActor
enum ComposerThemeReload {
    static let signposter = OSSignposter(subsystem: "com.seansmithdesign.ghostties", category: "ThemePreview")

    /// The newest request not yet loaded (`.some(nil)` = back to stored).
    private static var pending: (picks: GhosttiesThemePicks?, requestedAt: UInt64)?
    private static var isScheduled = false

    static func live(_ picks: GhosttiesThemePicks?) {
        let requestedAt = pending?.requestedAt ?? DispatchTime.now().uptimeNanoseconds
        pending = (picks, requestedAt)
        guard !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { flush() }
    }

    private static func flush() {
        guard let request = pending, let app = (NSApp.delegate as? AppDelegate)?.ghostty else {
            pending = nil
            isScheduled = false
            return
        }
        pending = nil
        let state = signposter.beginInterval("preview")
        let start = DispatchTime.now().uptimeNanoseconds
        app.previewThemePicks(request.picks)
        let loaded = DispatchTime.now().uptimeNanoseconds
        // The next main-loop turn is when the window commits the frame that
        // shows the reloaded colours; only then does the next request load.
        DispatchQueue.main.async {
            signposter.endInterval("preview", state)
            let frame = DispatchTime.now().uptimeNanoseconds
            ThemePreviewLatency.record(
                reloadMs: Double(loaded - start) / 1_000_000,
                frameMs: Double(frame - request.requestedAt) / 1_000_000,
                picks: request.picks
            )
            if pending != nil {
                DispatchQueue.main.async { flush() }
            } else {
                isScheduled = false
            }
        }
    }
}

/// DEBUG-only latency log for the live preview: the reload's own duration,
/// and request (the arrow key) -> the next main-loop turn after it loaded.
enum ThemePreviewLatency {
    static func record(reloadMs: Double, frameMs: Double, picks: GhosttiesThemePicks?) {
        #if DEBUG
        let label = picks.map { "\($0.light ?? "-")|\($0.dark ?? "-")" } ?? "stored"
        NSLog("[ThemePreview] %@ reload=%.1fms frame=%.1fms", label, reloadMs, frameMs)
        if let dir = CaptureFixture.harnessStateDir {
            CaptureFixture.appendLine(
                CaptureFixture.jsonLine(["picks": label, "reloadMs": reloadMs, "frameMs": frameMs]),
                to: dir.appendingPathComponent("theme-preview-latency.jsonl")
            )
        }
        #endif
    }
}

// MARK: - Presentation setting

/// How the composer shows theme results: chips (C1) or the thumbnail grid
/// (C2, the default). Settings > Appearance > "Composer theme results".
enum ComposerThemePresentation: String, CaseIterable {
    case chips
    case grid

    static let key = "ghostties.composer.themePresentation"

    static func stored(in defaults: UserDefaults) -> ComposerThemePresentation {
        defaults.string(forKey: key).flatMap(ComposerThemePresentation.init(rawValue:)) ?? .grid
    }

    func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }
}
