import AppKit
import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

/// GATE for Theme picker v2 (option A of theme-picker-v2.html): one 3x3 grid
/// (8 curated pairs + an "All themes" tile) shared by the Cmd+T composer and
/// Settings > Appearance, plus an "All themes" browse model that replaces the
/// 465-row dropdowns. PURE model tests: injected UserDefaults suites, no
/// windows, no NSApp, no setenv. The builder may not edit this file.
///
/// API the builder must add (names and signatures are the contract):
///
///     // --- 1. Catalog (ComposerThemePicker.swift) ---------------------------
///     // GhosttiesThemeCatalog.families becomes EXACTLY these 8 complete pairs,
///     // in this order (family name: light / dark), every name a bundled file:
///     //   Ghostties:   Ghostties Light / Ghostties Dark
///     //   Catppuccin:  Catppuccin Latte / Catppuccin Mocha
///     //   Rosé Pine:   Rose Pine Dawn / Rose Pine           (name has the accent)
///     //   Tokyo Night: TokyoNight Day / TokyoNight Night
///     //   GitHub:      GitHub Light Default / GitHub Dark Default
///     //   Gruvbox:     Gruvbox Light / Gruvbox Dark
///     //   Everforest:  Everforest Light Med / Everforest Dark Hard
///     //   Nord:        Nord Light / Nord
///     // The old `shippedCatalogIsCuratedAndBundled` in ComposerThemePickerTests
///     // pins the OLD 8 (Solarized/Dracula, one-sided) and contradicts this
///     // contract; it must be retired when the catalog changes (this file's
///     // `v2CatalogIsTheEightCompletePairs` replaces it).
///
///     // --- 2. Grid composition (new, shared by composer + Settings) ---------
///     enum ThemeGridCell: Equatable {
///         case family(ThemeFamily)
///         case custom(light: String, dark: String)   // current theme is outside the 8
///         case allThemes
///         var picks: GhosttiesThemePicks? { get }
///             // .family -> family.picks; .custom -> picks of (light, dark);
///             // .allThemes -> nil (it opens the browse model, it is not a theme)
///     }
///     enum ThemeGridModel {
///         static let columns = 3
///         static let cellCount = 9
///         /// `current` = what each side shows now (a nil side reads as the
///         /// Ghostties theme for that side, `GhosttiesThemeCatalog.resolved`).
///         /// RULE: if resolved(current) equals some family's `picks`, the cells
///         /// are the 8 families then .allThemes. Otherwise the cells are
///         /// [.custom(light:dark:)] + the FIRST 7 families (the 8th, Nord,
///         /// drops off) + .allThemes. Always exactly 9; .allThemes always last.
///         static func cells(current: GhosttiesThemePicks) -> [ThemeGridCell]
///         /// Index of the selected cell: the custom cell (0) or the matching
///         /// family. Never the All themes cell.
///         static func selectedIndex(current: GhosttiesThemePicks) -> Int
///         /// The composer header count: derived from the cells handed in
///         /// (cells.count), never a constant.
///         static func headerCount(cells: [ThemeGridCell]) -> Int
///     }
///
///     // --- 3. All themes browse model ---------------------------------------
///     enum ThemeBrowseFilter: CaseIterable { case pairs, light, dark }  // chip order
///     enum ThemeBrowseEntry: Equatable {
///         case family(ThemeFamily)
///         case single(name: String, polarity: ChromeTheme.Polarity)
///     }
///     enum ThemeBrowseModel {
///         /// Light/dark by background luminance, reusing ChromeTheme's rule
///         /// (`ChromeTheme.resolve(background:foreground:).polarity` on the
///         /// bundled theme file's colours).
///         static func polarity(ofTheme name: String) -> ChromeTheme.Polarity
///         /// `polarity` is injectable (defaults to `polarity(ofTheme:)`).
///         /// .pairs: matching `families` (catalog order), then single themes
///         ///   in `themes` order, EXCLUDING any theme that is a member of a
///         ///   family in `families`.
///         /// .light / .dark: no families; every theme in `themes` of that
///         ///   polarity, in `themes` order (family members included).
///         /// `query` (trimmed, case-insensitive substring) filters all three;
///         ///   a family matches on its name or either member's name.
///         static func entries(
///             filter: ThemeBrowseFilter, query: String, themes: [String],
///             families: [ThemeFamily] = GhosttiesThemeCatalog.families,
///             polarity: (String) -> ChromeTheme.Polarity = ThemeBrowseModel.polarity(ofTheme:)
///         ) -> [ThemeBrowseEntry]
///         /// The picks after choosing `entry`, from `current` (nil side =
///         /// Ghostties for that side). .family sets both sides. .single sets
///         /// ONLY one side - `side` if given (Settings' Mix side selector),
///         /// else the theme's own polarity - the other side is unchanged.
///         static func picks(
///             choosing entry: ThemeBrowseEntry, side: ChromeTheme.Polarity?,
///             current: GhosttiesThemePicks
///         ) -> GhosttiesThemePicks
///     }
///
///     // --- 4/5. Settings (AppearanceSettingsView.swift) ---------------------
///     // AppearanceSettingsModel gains:
///     static let mixTitle = "Mix light & dark…"
///     var gridCells: [ThemeGridCell]   // == ThemeGridModel.cells(current: <shown light/dark>)
///     var isBrowsing: Bool             // false initially
///     var browseSide: ChromeTheme.Polarity  // default .light; settable
///     func openMix()                   // isBrowsing = true
///     func closeBrowse()               // isBrowsing = false
///     func select(_ cell: ThemeGridCell)
///         // .family: stores its picks; .allThemes: isBrowsing = true, stores nothing
///     func choose(_ entry: ThemeBrowseEntry)
///         // stores ThemeBrowseModel.picks(choosing:side: browseSide, current: shown)
///     // The Light theme / Dark theme dropdowns (ThemeSidePicker) are removed
///     // from AppearanceSettingsView.
@MainActor
struct ThemePickerV2Tests {
    private func suite() -> (UserDefaults, () -> Void) {
        let name = "ghostties.tests.themepicker-v2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private let expectedPairs: [(String, String, String)] = [
        ("Ghostties", "Ghostties Light", "Ghostties Dark"),
        ("Catppuccin", "Catppuccin Latte", "Catppuccin Mocha"),
        ("Rosé Pine", "Rose Pine Dawn", "Rose Pine"),
        ("Tokyo Night", "TokyoNight Day", "TokyoNight Night"),
        ("GitHub", "GitHub Light Default", "GitHub Dark Default"),
        ("Gruvbox", "Gruvbox Light", "Gruvbox Dark"),
        ("Everforest", "Everforest Light Med", "Everforest Dark Hard"),
        ("Nord", "Nord Light", "Nord"),
    ]

    private var families: [ThemeFamily] { GhosttiesThemeCatalog.families }

    // MARK: - 1. Catalog

    @Test func v2CatalogIsTheEightCompletePairs() {
        #expect(families.count == 8)
        #expect(families.map(\.name) == expectedPairs.map(\.0))
        for (family, expected) in zip(families, expectedPairs) {
            #expect(family.light == expected.1, "\(expected.0) light side")
            #expect(family.dark == expected.2, "\(expected.0) dark side")
        }
        // No half pairs.
        #expect(families.allSatisfy { $0.light != nil && $0.dark != nil })
        let bundled = Set(GhosttiesThemeCatalog.bundledThemeNames())
        #expect(!bundled.isEmpty, "themes dir not found in the test host bundle")
        for family in families {
            for name in [family.light, family.dark].compactMap({ $0 }) {
                #expect(bundled.contains(name), "\(name) is not a bundled theme")
            }
        }
    }

    // MARK: - 2. Grid composition

    @Test func gridIsEightFamiliesThenAllThemes() {
        let cells = ThemeGridModel.cells(current: families[1].picks)
        #expect(ThemeGridModel.columns == 3)
        #expect(ThemeGridModel.cellCount == 9)
        #expect(cells.count == 9)
        #expect(cells == families.map(ThemeGridCell.family) + [.allThemes])
    }

    @Test func noPickReadsAsGhosttiesAndSelectsItsCell() {
        let cells = ThemeGridModel.cells(current: .none)
        #expect(cells == families.map(ThemeGridCell.family) + [.allThemes])
        #expect(ThemeGridModel.selectedIndex(current: .none) == 0)
        // A half-set pick resolves the missing side to Ghostties.
        #expect(ThemeGridModel.selectedIndex(current: GhosttiesThemePicks(light: "Ghostties Light")) == 0)
    }

    @Test func selectedIndexFollowsTheMatchingFamily() {
        for (i, family) in families.enumerated() {
            #expect(ThemeGridModel.selectedIndex(current: family.picks) == i)
        }
    }

    @Test func customThemeTakesTheFirstSlotAndDropsTheEighthFamily() {
        let custom = GhosttiesThemePicks(light: "Apple System Colors", dark: "Apple System Colors")
        let cells = ThemeGridModel.cells(current: custom)
        #expect(cells.count == 9)
        #expect(cells.first == .custom(light: "Apple System Colors", dark: "Apple System Colors"))
        #expect(Array(cells[1...7]) == families.prefix(7).map(ThemeGridCell.family))
        #expect(!cells.contains(.family(families[7])), "Nord drops off to keep 9")
        #expect(cells.last == .allThemes)
        #expect(ThemeGridModel.selectedIndex(current: custom) == 0)
    }

    @Test func aMixedPairIsCustomToo() {
        // Light from one family, dark from another: no family matches.
        let mixed = GhosttiesThemePicks(light: "Gruvbox Light", dark: "Catppuccin Mocha")
        let cells = ThemeGridModel.cells(current: mixed)
        #expect(cells.first == .custom(light: "Gruvbox Light", dark: "Catppuccin Mocha"))
        #expect(cells.count == 9)
        #expect(cells.last == .allThemes)
    }

    @Test func allThemesCellIsLastAndEveryCellIsReachable() {
        for current in [GhosttiesThemePicks.none, GhosttiesThemePicks(light: "X", dark: "Y")] {
            let cells = ThemeGridModel.cells(current: current)
            #expect(cells.last == .allThemes)
            #expect(cells.filter { $0 == .allThemes }.count == 1)
            // It is a cell like any other: an index in the cells list, not a trailing control.
            #expect(cells.indices.contains(cells.count - 1))
        }
    }

    @Test func cellPicks() {
        #expect(ThemeGridCell.family(families[2]).picks == families[2].picks)
        #expect(ThemeGridCell.custom(light: "A", dark: "B").picks == GhosttiesThemePicks(light: "A", dark: "B"))
        #expect(ThemeGridCell.allThemes.picks == nil)
    }

    // MARK: - 3. Browse model

    private let fakePolarity: (String) -> ChromeTheme.Polarity = { $0.lowercased().contains("light") ? .light : .dark }
    private let pool = ["Alpha Light", "Alpha Dark", "Beta Light", "Gamma Dark", "Gruvbox Light", "Gruvbox Dark", "Zed Dark"]

    @Test func chipsAreInOrder() {
        #expect(ThemeBrowseFilter.allCases == [.pairs, .light, .dark])
    }

    @Test func pairsListFamiliesFirstThenSingles() {
        let entries = ThemeBrowseModel.entries(
            filter: .pairs, query: "", themes: pool, families: Array(families.prefix(6)), polarity: fakePolarity
        )
        #expect(Array(entries.prefix(6)) == families.prefix(6).map(ThemeBrowseEntry.family))
        // Gruvbox Light/Dark belong to the Gruvbox family (index 5), so they are not repeated.
        #expect(Array(entries.dropFirst(6)) == [
            .single(name: "Alpha Light", polarity: .light),
            .single(name: "Alpha Dark", polarity: .dark),
            .single(name: "Beta Light", polarity: .light),
            .single(name: "Gamma Dark", polarity: .dark),
            .single(name: "Zed Dark", polarity: .dark),
        ])
    }

    @Test func lightAndDarkListOnlySinglesOfThatPolarity() {
        let light = ThemeBrowseModel.entries(filter: .light, query: "", themes: pool, polarity: fakePolarity)
        #expect(light == [
            .single(name: "Alpha Light", polarity: .light),
            .single(name: "Beta Light", polarity: .light),
            .single(name: "Gruvbox Light", polarity: .light),
        ])
        let dark = ThemeBrowseModel.entries(filter: .dark, query: "", themes: pool, polarity: fakePolarity)
        #expect(dark == [
            .single(name: "Alpha Dark", polarity: .dark),
            .single(name: "Gamma Dark", polarity: .dark),
            .single(name: "Gruvbox Dark", polarity: .dark),
            .single(name: "Zed Dark", polarity: .dark),
        ])
    }

    @Test func queryFiltersCaseInsensitively() {
        let found = ThemeBrowseModel.entries(filter: .light, query: "  ALPHA ", themes: pool, polarity: fakePolarity)
        #expect(found == [.single(name: "Alpha Light", polarity: .light)])
        let pairs = ThemeBrowseModel.entries(filter: .pairs, query: "mocha", themes: pool, polarity: fakePolarity)
        #expect(pairs == [.family(families[1])], "a family matches on a member's name")
        #expect(ThemeBrowseModel.entries(filter: .pairs, query: "nomatchzzz", themes: pool, polarity: fakePolarity).isEmpty)
    }

    @Test func polarityComesFromBackgroundLuminance() {
        #expect(ThemeBrowseModel.polarity(ofTheme: "Ghostties Light") == .light)
        #expect(ThemeBrowseModel.polarity(ofTheme: "Ghostties Dark") == .dark)
        #expect(ThemeBrowseModel.polarity(ofTheme: "iTerm2 Solarized Light") == .light)
        #expect(ThemeBrowseModel.polarity(ofTheme: "Dracula") == .dark)
        // Same rule as ChromeTheme, not a name heuristic.
        for name in ["Catppuccin Latte", "Nord", "Gruvbox Light", "TokyoNight Night"] {
            let expected = ChromeTheme.resolve(
                background: ThemeFile.background(named: name),
                foreground: ThemeFile.foreground(named: name) ?? ThemeFile.background(named: name)
            ).polarity
            #expect(ThemeBrowseModel.polarity(ofTheme: name) == expected, "\(name)")
        }
    }

    @Test func pickingASingleLightThemeSetsOnlyTheLightSide() {
        let current = GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
        let result = ThemeBrowseModel.picks(
            choosing: .single(name: "Gruvbox Light", polarity: .light), side: nil, current: current
        )
        #expect(result == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Catppuccin Mocha"))
    }

    @Test func pickingASingleDarkThemeSetsOnlyTheDarkSide() {
        let current = GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
        let result = ThemeBrowseModel.picks(
            choosing: .single(name: "Dracula", polarity: .dark), side: nil, current: current
        )
        #expect(result == GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Dracula"))
    }

    @Test func theSideSelectorOverridesThePolarity() {
        let current = GhosttiesThemePicks(light: "Catppuccin Latte", dark: "Catppuccin Mocha")
        let result = ThemeBrowseModel.picks(
            choosing: .single(name: "Dracula", polarity: .dark), side: .light, current: current
        )
        #expect(result == GhosttiesThemePicks(light: "Dracula", dark: "Catppuccin Mocha"))
    }

    @Test func pickingAFamilySetsBothSides() {
        let current = GhosttiesThemePicks(light: "A", dark: "B")
        for side in [nil, ChromeTheme.Polarity.light, .dark] {
            let result = ThemeBrowseModel.picks(choosing: .family(families[3]), side: side, current: current)
            #expect(result == families[3].picks)
        }
    }

    @Test func anUnsetSideReadsAsGhostties() {
        let result = ThemeBrowseModel.picks(
            choosing: .single(name: "Gruvbox Light", polarity: .light), side: nil, current: .none
        )
        #expect(result == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Ghostties Dark"))
    }

    // MARK: - 4. Header count

    @Test func headerCountIsTheNumberOfCellsRendered() {
        let nine = ThemeGridModel.cells(current: .none)
        #expect(ThemeGridModel.headerCount(cells: nine) == nine.count)
        // Derived, not a constant: it follows whatever cells it is given.
        #expect(ThemeGridModel.headerCount(cells: Array(nine.prefix(6))) == 6)
        #expect(ThemeGridModel.headerCount(cells: []) == 0)
        let custom = ThemeGridModel.cells(current: GhosttiesThemePicks(light: "X", dark: "Y"))
        #expect(ThemeGridModel.headerCount(cells: custom) == custom.count)
    }

    // MARK: - 5. Settings

    private func model(_ defaults: UserDefaults) -> AppearanceSettingsModel {
        AppearanceSettingsModel(defaults: defaults, windowTheme: { nil })
    }

    @Test func settingsSharesTheComposersGrid() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = model(defaults)
        let shown = GhosttiesThemePicks(light: model.shown.light, dark: model.shown.dark)
        #expect(model.gridCells == ThemeGridModel.cells(current: shown))
        #expect(model.gridCells.count == 9)
        #expect(model.gridCells.last == .allThemes)
    }

    @Test func settingsGridFollowsAPick() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = model(defaults)
        model.select(.family(families[1]))
        #expect(GhosttiesThemePicks.stored(in: defaults) == families[1].picks)
        #expect(model.gridCells == ThemeGridModel.cells(current: families[1].picks))
    }

    @Test func mixEntryOpensTheBrowseModelWithASideSelector() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = model(defaults)
        #expect(AppearanceSettingsModel.mixTitle == "Mix light & dark…")
        #expect(!model.isBrowsing)
        #expect(model.browseSide == .light)
        model.openMix()
        #expect(model.isBrowsing)
        model.browseSide = .dark
        #expect(model.browseSide == .dark)
        model.closeBrowse()
        #expect(!model.isBrowsing)
    }

    @Test func theAllThemesCellOpensBrowseAndStoresNothing() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = model(defaults)
        model.select(.allThemes)
        #expect(model.isBrowsing)
        #expect(GhosttiesThemePicks.stored(in: defaults).isEmpty)
    }

    @Test func mixingASingleThemeKeepsTheOtherSide() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let model = model(defaults)
        model.select(.family(families[1]))   // Catppuccin
        model.openMix()
        model.browseSide = .light
        model.choose(.single(name: "Gruvbox Light", polarity: .light))
        #expect(GhosttiesThemePicks.stored(in: defaults)
            == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Catppuccin Mocha"))
        model.browseSide = .dark
        model.choose(.single(name: "Dracula", polarity: .dark))
        #expect(GhosttiesThemePicks.stored(in: defaults)
            == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Dracula"))
    }

    /// Source-text check: a model test cannot see a deleted view. The old
    /// per-side dropdown view must be gone from the Settings pane.
    @Test func theOldLightDarkDropdownsAreGone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = root.appendingPathComponent("macos/Sources/Features/Settings/AppearanceSettingsView.swift")
        let text = try String(contentsOf: view, encoding: .utf8)
        #expect(!text.contains("ThemeSidePicker"))
        #expect(!text.contains("\"Light theme\""))
        #expect(!text.contains("\"Dark theme\""))
        #expect(text.contains("mixTitle"))
    }
}
