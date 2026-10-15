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

/// A light/dark theme pair as the picker offers it. A family may have one
/// side only (Dracula is dark, Solarized here is light).
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
    /// The curated set the composer picker offers, Ghostties first. Every
    /// name is a bundled theme file (`shippedCatalogIsCuratedAndBundled`).
    static let families: [ThemeFamily] = [
        ThemeFamily(name: ghostties.name, light: ghostties.light, dark: ghostties.dark),
        ThemeFamily(name: "Catppuccin", light: "Catppuccin Latte", dark: "Catppuccin Mocha"),
        ThemeFamily(name: "Gruvbox", light: "Gruvbox Light", dark: "Gruvbox Dark"),
        ThemeFamily(name: "Rose Pine", light: "Rose Pine Dawn", dark: "Rose Pine"),
        ThemeFamily(name: "Solarized", light: "iTerm2 Solarized Light", dark: nil),
        ThemeFamily(name: "Dracula", light: nil, dark: "Dracula"),
        ThemeFamily(name: "TokyoNight", light: nil, dark: "TokyoNight"),
        ThemeFamily(name: "Nord", light: nil, dark: "Nord"),
    ]

    /// `picks` with an unpicked side filled by the Ghostties theme for that
    /// side: what actually shows.
    static func resolved(_ picks: GhosttiesThemePicks) -> GhosttiesThemePicks {
        GhosttiesThemePicks(light: picks.light ?? ghostties.light, dark: picks.dark ?? ghostties.dark)
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

    /// C2: whole families in catalog order, matched on the family or either
    /// member's name.
    static func grid(query: String, families: [ThemeFamily]) -> [ThemeFamily] {
        let q = normalized(query)
        guard !q.isEmpty else { return families }
        return families.filter { family in
            [family.name, family.light, family.dark].contains { $0?.lowercased().contains(q) == true }
        }
    }

    /// C2: where the selection starts. An empty query starts on the applied
    /// family (no pick = Ghostties); a typed query, or a pick no family
    /// matches, starts on the first result.
    static func initialGridIndex(query: String, results: [ThemeFamily], applied: GhosttiesThemePicks) -> Int {
        guard normalized(query).isEmpty else { return 0 }
        let current = GhosttiesThemeCatalog.resolved(applied)
        return results.firstIndex { $0.picks == current } ?? 0
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
