import AppKit
import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// GATE for the composer-driven theme picker (C1 chips + C2 grid). Covers the
/// NON-visual core only: command parsing, matching/ranking, the live-preview
/// engine, and the presentation setting. Persistence uses an injected
/// `UserDefaults` suite (never `.standard`, never setenv); the reload hook is
/// injected so tests count reloads and read the override text a reload would
/// load.
///
/// API the builder must add (names and signatures are the contract):
///
///     // --- 1. Parsing -----------------------------------------------------
///     enum ComposerThemeCommand: Equatable {
///         case theme(query: String)          // `theme`, `/theme dra`; query trimmed + lowercased
///         case partial(completion: String)   // `the` -> "me "; the ghost text to append
///         case none
///         static func parse(_ text: String, projectNames: [String] = []) -> ComposerThemeCommand
///     }
///     // Rules: optional single leading "/", then the word `theme` (any case),
///     // then end-of-input or whitespace + query. Leading whitespace ignored.
///     // It must be the FIRST token: `repo theme dra` is .none. `themes-app`,
///     // `theme-app`, `/themes` are .none (no word boundary). Partial = a
///     // proper prefix of "theme"; bare (no slash) needs >= 3 typed chars
///     // ("the"), slashed needs >= 1 ("/t"); completion = rest of "theme" + " ".
///     // Never hijack a project: a BARE input whose first token equals a
///     // project name (case-insensitive), or (for partial) is a prefix of one,
///     // is .none. A leading "/" always wins (explicit command).
///
///     // --- 2. Matching ----------------------------------------------------
///     struct ThemeFamily: Equatable {
///         let name: String; let light: String?; let dark: String?
///         init(name: String, light: String?, dark: String?)
///         func themeName(for polarity: ChromeTheme.Polarity) -> String  // that side, else the other
///         var picks: GhosttiesThemePicks   // BOTH sides set; a missing side is filled by the other
///     }
///     struct ThemeChoice: Equatable { let name: String; let family: String; let polarity: ChromeTheme.Polarity }
///     extension GhosttiesThemeCatalog { static let families: [ThemeFamily] }   // curated, Ghostties first
///     enum ComposerThemeMatcher {
///         // C1: individual theme names as chips.
///         static func chips(query: String, families: [ThemeFamily], applied: GhosttiesThemePicks,
///                           appearance: ChromeTheme.Polarity, limit: Int = 6) -> [ThemeChoice]
///         // C2: whole families, catalog order.
///         static func grid(query: String, families: [ThemeFamily]) -> [ThemeFamily]
///         // C2: index the grid selection starts on (applied family when found, else 0).
///         static func initialGridIndex(query: String, results: [ThemeFamily], applied: GhosttiesThemePicks) -> Int
///         // Ghost completion text appended after what is typed.
///         static func ghostSuffix(typed: String, query: String, topNames: [String]) -> String
///     }
///
///     // --- 3. Preview engine ----------------------------------------------
///     @MainActor final class ThemePreviewController {
///         // `reload` receives the TEMPORARY override picks to load, or nil =
///         // "load the stored picks as usual" (no override layer).
///         init(defaults: UserDefaults, reload: @escaping (GhosttiesThemePicks?) -> Void)
///         private(set) var previewing: GhosttiesThemePicks?   // nil when not previewing
///         var isPreviewing: Bool
///         func preview(light: String?, dark: String?)
///         func revert()
///         @discardableResult func commit() -> Bool                  // persist the previewed picks
///         func commit(light: String?, dark: String?)                // persist these picks directly
///     }
///
///     // --- 4. Presentation setting ----------------------------------------
///     enum ComposerThemePresentation: String { case chips, grid
///         static let key: String
///         static func stored(in: UserDefaults) -> ComposerThemePresentation  // absent/garbage -> .grid
///         func save(to: UserDefaults)
///     }
@MainActor
struct ComposerThemePickerTests {
    // MARK: - Helpers

    private func suite() -> (UserDefaults, () -> Void) {
        let name = "ghostties.tests.themepicker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    /// Records every reload the controller asks for.
    private final class Reloads {
        var calls: [GhosttiesThemePicks?] = []
        var count: Int { calls.count }
        /// The `theme =` line a reload would load, nil when no override layer.
        func overrideText(at i: Int) -> String? {
            guard let picks = calls[i] else { return nil }
            return GhosttiesConfigDefaults.overrideContents(picks: picks)
        }
    }

    private func makeController(_ defaults: UserDefaults) -> (ThemePreviewController, Reloads) {
        let reloads = Reloads()
        let controller = ThemePreviewController(defaults: defaults) { reloads.calls.append($0) }
        return (controller, reloads)
    }

    /// The prototype's catalog (theme-picker-explorations.html), injected so
    /// ranking tests do not depend on what the bundle ships.
    private let catalog: [ThemeFamily] = [
        ThemeFamily(name: "Ghostties", light: "Ghostties Light", dark: "Ghostties Dark"),
        ThemeFamily(name: "Catppuccin", light: "Catppuccin Latte", dark: "Catppuccin Mocha"),
        ThemeFamily(name: "Gruvbox", light: "Gruvbox Light", dark: "Gruvbox Dark"),
        ThemeFamily(name: "Rose Pine", light: "Rose Pine Dawn", dark: "Rose Pine"),
        ThemeFamily(name: "Solarized", light: "iTerm2 Solarized Light", dark: nil),
        ThemeFamily(name: "Dracula", light: nil, dark: "Dracula"),
        ThemeFamily(name: "TokyoNight", light: nil, dark: "TokyoNight"),
        ThemeFamily(name: "Nord", light: nil, dark: "Nord"),
    ]

    private let ghosttiesApplied = GhosttiesThemePicks(pair: GhosttiesThemeCatalog.ghostties)

    // MARK: - 1. Command parsing

    @Test(arguments: [
        ("theme", ""), ("theme ", ""), ("/theme", ""), ("/theme ", ""),
        ("theme dra", "dra"), ("/theme dra", "dra"), ("THEME Dra", "dra"),
        ("Theme   rose pine  ", "rose pine"), ("theme\tnord", "nord"),
        ("  theme dra", "dra"),
    ])
    func themeCommandParsesWithQuery(text: String, query: String) {
        #expect(ComposerThemeCommand.parse(text) == .theme(query: query))
    }

    @Test(arguments: [
        ("the", "me "), ("THE", "me "), ("them", "e "),
        ("/t", "heme "), ("/th", "eme "), ("/the", "me "), ("/them", "e "),
    ])
    func partialCommandOffersTheRestOfTheWord(text: String, completion: String) {
        #expect(ComposerThemeCommand.parse(text) == .partial(completion: completion))
    }

    /// Sean's real idiom and near-misses must pass straight through.
    @Test(arguments: [
        "", " ", "/", "t", "th", "cco", "repo cco", "repo cco -n \"thread\"",
        "cco -n \"theme x\"", "repo theme dra", "themes-app", "theme-app", "themes",
        "/themes", "/themed", "them3", "thematic", "thx", "ghostties > main > claude",
    ])
    func everythingElseIsNone(text: String) {
        #expect(ComposerThemeCommand.parse(text) == .none)
    }

    /// A project literally named `theme` or starting with `the` keeps its
    /// meaning for the bare word; only `/` is an explicit command.
    @Test func projectNamesAreNeverHijacked() {
        let projects = ["Theme", "thesis", "atlas-api"]
        #expect(ComposerThemeCommand.parse("theme", projectNames: projects) == .none)
        #expect(ComposerThemeCommand.parse("theme dra", projectNames: projects) == .none)
        #expect(ComposerThemeCommand.parse("the", projectNames: projects) == .none)   // prefix of "thesis"
        #expect(ComposerThemeCommand.parse("/theme dra", projectNames: projects) == .theme(query: "dra"))
        #expect(ComposerThemeCommand.parse("/the", projectNames: projects) == .partial(completion: "me "))
        // Unrelated projects change nothing.
        #expect(ComposerThemeCommand.parse("theme dra", projectNames: ["atlas-api"]) == .theme(query: "dra"))
    }

    // MARK: - 2. Matching

    @Test func familyPicksFillAMissingSideWithTheOther() {
        #expect(catalog[5].picks == GhosttiesThemePicks(light: "Dracula", dark: "Dracula"))
        #expect(catalog[4].picks == GhosttiesThemePicks(light: "iTerm2 Solarized Light", dark: "iTerm2 Solarized Light"))
        #expect(catalog[2].picks == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark"))
        #expect(catalog[5].themeName(for: .light) == "Dracula")
        #expect(catalog[2].themeName(for: .light) == "Gruvbox Light")
        #expect(catalog[2].themeName(for: .dark) == "Gruvbox Dark")
    }

    @Test func chipQueryMatchesThemeNameAndFamilyCaseInsensitively() {
        let byName = ComposerThemeMatcher.chips(query: "mocha", families: catalog, applied: ghosttiesApplied, appearance: .dark)
        #expect(byName.map(\.name) == ["Catppuccin Mocha"])
        // Family name matches both members.
        let byFamily = ComposerThemeMatcher.chips(query: "CATPPUCCIN", families: catalog, applied: ghosttiesApplied, appearance: .dark)
        #expect(Set(byFamily.map(\.name)) == ["Catppuccin Latte", "Catppuccin Mocha"])
        #expect(byFamily.allSatisfy { $0.family == "Catppuccin" })
        #expect(ComposerThemeMatcher.chips(query: "zzz", families: catalog, applied: ghosttiesApplied, appearance: .dark).isEmpty)
    }

    @Test func chipsPutSamePolarityFirst() {
        let light = ComposerThemeMatcher.chips(query: "gruv", families: catalog, applied: ghosttiesApplied, appearance: .light)
        #expect(light.map(\.name) == ["Gruvbox Light", "Gruvbox Dark"])
        #expect(light.map(\.polarity) == [.light, .dark])
        let dark = ComposerThemeMatcher.chips(query: "gruv", families: catalog, applied: ghosttiesApplied, appearance: .dark)
        #expect(dark.map(\.name) == ["Gruvbox Dark", "Gruvbox Light"])
    }

    /// Polarity outranks prefix: a dark prefix match sits below a light
    /// non-prefix match when the window is light.
    @Test func polarityOutranksPrefixThenPrefixThenCatalogOrder() {
        // Query "r": light matches are Rose Pine Dawn (prefix), Gruvbox Light,
        // iTerm2 Solarized Light; dark matches are Rose Pine (prefix), Gruvbox
        // Dark, Dracula, Nord. Light window: all light first (prefix leading),
        // then dark (prefix leading); capped at 6.
        let light = ComposerThemeMatcher.chips(query: "r", families: catalog, applied: ghosttiesApplied, appearance: .light)
        #expect(light.map(\.name) == [
            "Rose Pine Dawn", "Gruvbox Light", "iTerm2 Solarized Light",
            "Rose Pine", "Gruvbox Dark", "Dracula",
        ])
        let dark = ComposerThemeMatcher.chips(query: "r", families: catalog, applied: ghosttiesApplied, appearance: .dark)
        #expect(dark.map(\.name) == [
            "Rose Pine", "Gruvbox Dark", "Dracula", "Nord",
            "Rose Pine Dawn", "Gruvbox Light",
        ])
    }

    @Test func chipsAreCappedAtTheLimit() {
        let all = ComposerThemeMatcher.chips(query: "", families: catalog, applied: ghosttiesApplied, appearance: .light)
        #expect(all.count == 6)
        let three = ComposerThemeMatcher.chips(query: "", families: catalog, applied: ghosttiesApplied, appearance: .light, limit: 3)
        #expect(three.count == 3)
    }

    @Test func emptyChipQueryListsTheCuratedSetWithTheCurrentPickFirst() {
        // Dark window, applied dark = Gruvbox Dark: it leads, then dark names
        // in catalog order, then light.
        let applied = GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark")
        let dark = ComposerThemeMatcher.chips(query: "", families: catalog, applied: applied, appearance: .dark, limit: 100)
        #expect(dark.first?.name == "Gruvbox Dark")
        #expect(Array(dark.map(\.name).prefix(4)) == ["Gruvbox Dark", "Ghostties Dark", "Catppuccin Mocha", "Rose Pine"])
        #expect(dark.count == 12)   // every theme in the injected catalog, none dropped
        // Light window: the light pick leads.
        let light = ComposerThemeMatcher.chips(query: "", families: catalog, applied: applied, appearance: .light, limit: 100)
        #expect(light.first?.name == "Gruvbox Light")
    }

    @Test func noPickMeansTheGhosttiesThemeIsCurrent() {
        let dark = ComposerThemeMatcher.chips(query: "", families: catalog, applied: .none, appearance: .dark)
        #expect(dark.first?.name == "Ghostties Dark")
        let light = ComposerThemeMatcher.chips(query: "", families: catalog, applied: .none, appearance: .light)
        #expect(light.first?.name == "Ghostties Light")
    }

    @Test func gridKeepsCatalogOrderAndFiltersByFamilyOrMemberName() {
        #expect(ComposerThemeMatcher.grid(query: "", families: catalog) == catalog)
        #expect(ComposerThemeMatcher.grid(query: "gru", families: catalog).map(\.name) == ["Gruvbox"])
        #expect(ComposerThemeMatcher.grid(query: "MOCHA", families: catalog).map(\.name) == ["Catppuccin"])
        #expect(ComposerThemeMatcher.grid(query: "dra", families: catalog).map(\.name) == ["Dracula"])
        // "light" hits member names: Ghostties Light, Catppuccin Latte no, Gruvbox Light, Solarized Light.
        #expect(ComposerThemeMatcher.grid(query: "light", families: catalog).map(\.name)
            == ["Ghostties", "Gruvbox", "Solarized"])
        #expect(ComposerThemeMatcher.grid(query: "zzz", families: catalog).isEmpty)
    }

    @Test func gridSelectionStartsOnTheAppliedFamilyForAnEmptyQuery() {
        let applied = GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark")
        let results = ComposerThemeMatcher.grid(query: "", families: catalog)
        #expect(ComposerThemeMatcher.initialGridIndex(query: "", results: results, applied: applied) == 2)
        // A typed query starts on the first match.
        let filtered = ComposerThemeMatcher.grid(query: "gru", families: catalog)
        #expect(ComposerThemeMatcher.initialGridIndex(query: "gru", results: filtered, applied: applied) == 0)
        // No pick = the Ghostties family; a Custom/unknown pick = first.
        #expect(ComposerThemeMatcher.initialGridIndex(query: "", results: results, applied: .none) == 0)
        let custom = GhosttiesThemePicks(light: "Some Theme", dark: "Other Theme")
        #expect(ComposerThemeMatcher.initialGridIndex(query: "", results: results, applied: custom) == 0)
        #expect(ComposerThemeMatcher.initialGridIndex(query: "", results: [], applied: applied) == 0)
    }

    @Test func ghostSuffixCompletesAPrefixOtherwiseJustTheSpace() {
        // Prefix of a theme name: the rest, in that name's own case.
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "theme dra", query: "dra", topNames: ["Dracula"]) == "cula")
        // First top name that matches wins (theme name before family).
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "/theme rose", query: "rose", topNames: ["Rose Pine Dawn", "Rose Pine"]) == " Pine Dawn")
        // Bare `theme`, no space typed yet: offer the space.
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "theme", query: "", topNames: ["Ghostties Light"]) == " ")
        // Space already typed, empty query: nothing.
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "theme ", query: "", topNames: ["Ghostties Light"]) == "")
        // Query matches only mid-name: nothing.
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "theme mocha", query: "mocha", topNames: ["Catppuccin Mocha"]) == "")
        // No results: nothing, except the bare-word space.
        #expect(ComposerThemeMatcher.ghostSuffix(typed: "theme zz", query: "zz", topNames: []) == "")
    }

    /// The shipped catalog: Ghostties first, and every name is a real bundled
    /// theme file (a typo here would preview as a silent no-op).
    @Test func shippedCatalogIsCuratedAndBundled() {
        let families = GhosttiesThemeCatalog.families
        #expect(families.first == ThemeFamily(name: "Ghostties", light: "Ghostties Light", dark: "Ghostties Dark"))
        let names = Set(families.map(\.name))
        for expected in ["Ghostties", "Catppuccin", "Gruvbox", "Rose Pine", "Solarized", "Dracula", "TokyoNight", "Nord"] {
            #expect(names.contains(expected), "missing family \(expected)")
        }
        #expect(families.allSatisfy { $0.light != nil || $0.dark != nil })
        let bundled = Set(GhosttiesThemeCatalog.bundledThemeNames())
        #expect(!bundled.isEmpty, "themes dir not found in the test host bundle")
        for family in families {
            for name in [family.light, family.dark].compactMap({ $0 }) {
                #expect(bundled.contains(name), "\(name) is not a bundled theme")
            }
        }
    }

    // MARK: - 3. Preview engine

    @Test func previewReloadsWithATemporaryOverrideAndWritesNoDefaults() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Catppuccin Latte", dark: "Catppuccin Mocha")

        #expect(reloads.count == 1)
        #expect(reloads.overrideText(at: 0) == "theme = light:Catppuccin Latte,dark:Catppuccin Mocha")
        #expect(controller.isPreviewing)
        #expect(controller.previewing == GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Catppuccin Mocha"))
        // Nothing persisted.
        #expect(defaults.object(forKey: GhosttiesThemePicks.lightKey) == nil)
        #expect(defaults.object(forKey: GhosttiesThemePicks.darkKey) == nil)
        #expect(GhosttiesThemePicks.stored(in: defaults).isEmpty)
    }

    @Test func repeatedPreviewsReplaceEachOther() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Gruvbox Light", dark: "Gruvbox Dark")
        controller.preview(light: "Rose Pine Dawn", dark: "Rose Pine")
        controller.preview(light: "Nord", dark: "Nord")

        #expect(reloads.count == 3)
        #expect(reloads.overrideText(at: 2) == "theme = light:Nord,dark:Nord")
        #expect(controller.previewing == GhosttiesThemePicks(light: "Nord", dark: "Nord"))
        #expect(GhosttiesThemePicks.stored(in: defaults).isEmpty)
    }

    @Test func previewingTheSamePicksAgainDoesNotReload() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Nord", dark: "Nord")
        controller.preview(light: "Nord", dark: "Nord")
        controller.preview(light: "Nord", dark: "Nord")

        #expect(reloads.count == 1)
    }

    @Test func revertWithNoPickRestoresNoPickExactly() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Dracula", dark: "Dracula")
        controller.revert()

        #expect(reloads.count == 2)
        #expect(reloads.calls[1] == .some(nil), "revert must ask for the stored picks (no override)")
        #expect(reloads.overrideText(at: 1) == nil)
        #expect(!controller.isPreviewing)
        #expect(controller.previewing == nil)
        // Keys still absent: not "removed and re-set", not set to Ghostties.
        #expect(defaults.object(forKey: GhosttiesThemePicks.lightKey) == nil)
        #expect(defaults.object(forKey: GhosttiesThemePicks.darkKey) == nil)
    }

    @Test func revertRestoresAStoredPairAndAOneSidedPickExactly() {
        for stored in [
            GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark"),
            GhosttiesThemePicks(light: "Nord Light", dark: nil),
            GhosttiesThemePicks(light: nil, dark: "Dracula"),
        ] {
            let (defaults, cleanup) = suite()
            defer { cleanup() }
            stored.save(to: defaults)
            let (controller, reloads) = makeController(defaults)

            controller.preview(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
            controller.preview(light: "Nord", dark: "Nord")
            controller.revert()

            #expect(GhosttiesThemePicks.stored(in: defaults) == stored)
            #expect(defaults.object(forKey: GhosttiesThemePicks.lightKey) as? String == stored.light)
            #expect(defaults.object(forKey: GhosttiesThemePicks.darkKey) as? String == stored.dark)
            #expect(reloads.calls.last == .some(nil))
            #expect(!controller.isPreviewing)
        }
    }

    /// Custom = no pick, the user's own `theme =` line. Reverting must hand
    /// back to it, which means a nil override and still-empty defaults.
    @Test func revertRestoresCustomByLoadingNoOverride() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Ghostties Light", dark: "Ghostties Dark")
        controller.revert()

        #expect(reloads.calls.last == .some(nil))
        #expect(GhosttiesThemePicks.stored(in: defaults).isEmpty)
        // The state the Settings pane resolves is unchanged by the round trip.
        #expect(GhosttiesAppearanceState.resolve(configPath: "/nonexistent", picks: .stored(in: defaults)) == .ghostties)
    }

    @Test func revertWhenNotPreviewingIsANoOp() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.revert()
        controller.preview(light: "Nord", dark: "Nord")
        controller.revert()
        controller.revert()

        #expect(reloads.count == 2)   // the preview and the first revert only
    }

    @Test func commitPersistsThePreviewedPicksAndEndsPreview() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
        let committed = controller.commit()

        #expect(committed)
        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Catppuccin Mocha"))
        #expect(defaults.string(forKey: GhosttiesThemePicks.lightKey) == "Catppuccin Latte")
        #expect(defaults.string(forKey: GhosttiesThemePicks.darkKey) == "Catppuccin Mocha")
        #expect(!controller.isPreviewing)
        // One reload for the preview, one to drop the override in favour of
        // the now-stored picks.
        #expect(reloads.count == 2)
        #expect(reloads.calls.last == .some(nil))
        // And a revert after commit has nothing to undo.
        controller.revert()
        #expect(reloads.count == 2)
        #expect(GhosttiesThemePicks.stored(in: defaults).light == "Catppuccin Latte")
    }

    @Test func commitWithoutAPreviewDoesNothing() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        GhosttiesThemePicks(light: "Nord Light", dark: "Nord").save(to: defaults)
        let (controller, reloads) = makeController(defaults)

        #expect(controller.commit() == false)

        #expect(reloads.count == 0)
        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Nord Light", dark: "Nord"))
    }

    @Test func directCommitPersistsAndReloadsOnce() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.commit(light: "Gruvbox Light", dark: "Gruvbox Dark")

        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark"))
        #expect(reloads.count == 1)
        #expect(reloads.calls[0] == .some(nil))
        #expect(!controller.isPreviewing)
    }

    @Test func directCommitAfterAPreviewEndsIt() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Nord", dark: "Nord")
        controller.commit(light: "Dracula", dark: "Dracula")

        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Dracula", dark: "Dracula"))
        #expect(!controller.isPreviewing)
        #expect(reloads.calls.last == .some(nil))
    }

    @Test func previewingTheAppliedThemeIsANoOp() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark").save(to: defaults)
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Gruvbox Light", dark: "Gruvbox Dark")

        #expect(reloads.count == 0)
        #expect(!controller.isPreviewing)
        #expect(controller.previewing == nil)
    }

    /// An unpicked stored side is the Ghostties theme for that side, so
    /// previewing that spelled out is also the applied theme.
    @Test func appliedComparisonTreatsAnUnpickedSideAsGhostties() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        GhosttiesThemePicks(light: "Gruvbox Light", dark: nil).save(to: defaults)
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Gruvbox Light", dark: "Ghostties Dark")

        #expect(reloads.count == 0)
        #expect(!controller.isPreviewing)
    }

    /// Hovering back onto the applied theme while another is previewed ends
    /// the preview (one reload back to stored), as the prototype does.
    @Test func previewingTheAppliedThemeAfterAnotherEndsThePreview() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let applied = GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark")
        applied.save(to: defaults)
        let (controller, reloads) = makeController(defaults)

        controller.preview(light: "Nord", dark: "Nord")
        controller.preview(light: "Gruvbox Light", dark: "Gruvbox Dark")

        #expect(reloads.count == 2)
        #expect(reloads.calls[1] == .some(nil))
        #expect(!controller.isPreviewing)
        #expect(GhosttiesThemePicks.stored(in: defaults) == applied)
    }

    /// Committing the stored picks is not a change: no reload.
    @Test func directCommitOfTheStoredPicksDoesNotReload() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        GhosttiesThemePicks(light: "Nord Light", dark: "Nord").save(to: defaults)
        let (controller, reloads) = makeController(defaults)

        controller.commit(light: "Nord Light", dark: "Nord")

        #expect(reloads.count == 0)
        #expect(GhosttiesThemePicks.stored(in: defaults) == GhosttiesThemePicks(light: "Nord Light", dark: "Nord"))
    }

    /// The reload hook's argument is what the real loader consumes: feed it
    /// through `Ghostty.Config.loadConfig` and the previewed theme shows.
    @Test func previewOverrideLoadsThroughTheRealConfigLoader() throws {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        var loaded: [GhosttiesThemePicks] = []
        let controller = ThemePreviewController(defaults: defaults) { picks in
            loaded.append(picks ?? .stored(in: defaults))
        }
        controller.preview(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("ghostty")
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = Ghostty.Config(config: Ghostty.Config.loadConfig(
            at: file.path(), finalize: true, picks: try #require(loaded.last)))
        #expect(config.errors.isEmpty, "\(config.errors)")
        let cfg = try #require(config.config)
        var c = ghostty_config_color_s()
        let key = "background"
        #expect(ghostty_config_get(cfg, &c, key, UInt(key.lengthOfBytes(using: .utf8))))
        let expected = ThemeFile.background(named: "Catppuccin Latte").usingColorSpace(.sRGB)!
        #expect([Int(c.r), Int(c.g), Int(c.b)]
            == [expected.redComponent, expected.greenComponent, expected.blueComponent].map { Int(($0 * 255).rounded()) })
    }

    // MARK: - 4. Presentation setting

    @Test func presentationDefaultsToGrid() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        #expect(ComposerThemePresentation.stored(in: defaults) == .grid)
    }

    @Test func presentationRoundTripsThroughTheInjectedSuite() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        ComposerThemePresentation.chips.save(to: defaults)
        #expect(ComposerThemePresentation.stored(in: defaults) == .chips)
        #expect(defaults.string(forKey: ComposerThemePresentation.key) == "chips")
        ComposerThemePresentation.grid.save(to: defaults)
        #expect(ComposerThemePresentation.stored(in: defaults) == .grid)
        #expect(defaults.string(forKey: ComposerThemePresentation.key) == "grid")
    }

    @Test func unknownPresentationValueFallsBackToGrid() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        defaults.set("carousel", forKey: ComposerThemePresentation.key)
        #expect(ComposerThemePresentation.stored(in: defaults) == .grid)
    }

    /// Presentation and picks are separate stores: switching the view never
    /// touches the theme.
    @Test func presentationNeverTouchesThemePicks() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let picks = GhosttiesThemePicks(light: "Nord Light", dark: "Nord")
        picks.save(to: defaults)
        ComposerThemePresentation.chips.save(to: defaults)
        #expect(GhosttiesThemePicks.stored(in: defaults) == picks)
    }
}
