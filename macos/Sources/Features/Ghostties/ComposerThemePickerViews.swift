import AppKit
import SwiftUI

// MARK: - Model

/// What Return (or a click) did in the theme picker.
enum ComposerThemeActivation: Equatable {
    /// A theme was stored; the composer closes.
    case committed
    /// The All themes tile opened the browse view in place.
    case openedBrowse
    /// Nothing to act on.
    case none
}

/// The composer theme picker's state: the parsed command, the selected
/// result, the hovered thumbnail half, and the live preview. Owned by
/// `SessionComposerStore`, so every way the composer closes reverts the
/// preview (`reset`).
///
/// C2 shows the shared 3x3 grid (`ThemeGridModel`: eight pairs and an All
/// themes tile). The tile, or `theme <query>`, switches it to the All
/// themes browse view (`ThemeBrowseModel`) in place.
@MainActor
final class ComposerThemePickerModel: ObservableObject {
    let preview: ThemePreviewController
    /// C1's chip families.
    let families: [ThemeFamily]
    private let defaults: UserDefaults
    private let appearanceProvider: @MainActor () -> ChromeTheme.Polarity
    private let appearanceState: @MainActor (GhosttiesThemePicks) -> GhosttiesAppearanceState
    private let themesProvider: () -> [String]

    @Published private(set) var command: ComposerThemeCommand = .none
    /// Read from Settings each time the picker opens.
    @Published private(set) var presentation: ComposerThemePresentation = .grid
    @Published private(set) var selection = 0
    /// The thumbnail half (C2) or chip (C1) under the pointer, previewing
    /// instead of the selection.
    @Published private(set) var peekName: String?
    /// Explicit colour keys in the user's config beat any theme, so the
    /// picker offers nothing (Settings locks the same way).
    @Published private(set) var isLockedByConfig = false
    /// What each side shows right now, read when the picker opens.
    @Published private(set) var current = GhosttiesThemePicks.none
    /// The grid's nine cells, read when the picker opens.
    @Published private(set) var gridCells: [ThemeGridCell] = []
    /// The All themes tile opened the browse view (a typed query opens it
    /// too, without this).
    @Published private(set) var isBrowseOpened = false
    @Published private(set) var browseFilter: ThemeBrowseFilter = .pairs
    @Published private(set) var browseEntries: [ThemeBrowseEntry] = []

    /// Whether the selection is shown on the window: true once the user
    /// moves, hovers or types a query. An empty `theme ` shows what is
    /// applied, so typing the word alone never changes the window.
    private var selectionIsPreviewed = false
    /// Esc left All themes with a query typed: the caller is clearing it,
    /// and that text change must land on the All themes tile, not the
    /// applied cell.
    private var landOnAllThemesAfterClose = false
    private var thumbnails: [String: ThemePreview] = [:]
    private lazy var themes: [String] = themesProvider()
    private lazy var browseFamilies: [ThemeFamily] = GhosttiesThemeCatalog.browseFamilies(themes: themes)

    init(
        defaults: UserDefaults,
        families: [ThemeFamily] = GhosttiesThemeCatalog.families,
        reload: @escaping (GhosttiesThemePicks?) -> Void,
        appearance: @escaping @MainActor () -> ChromeTheme.Polarity = ComposerThemePickerModel.systemAppearance,
        appearanceState: @escaping @MainActor (GhosttiesThemePicks) -> GhosttiesAppearanceState = ComposerThemePickerModel.liveAppearanceState,
        themes: @escaping () -> [String] = { GhosttiesThemeCatalog.bundledThemeNames() }
    ) {
        self.defaults = defaults
        self.families = families
        self.preview = ThemePreviewController(defaults: defaults, reload: reload)
        self.appearanceProvider = appearance
        self.appearanceState = appearanceState
        self.themesProvider = themes
    }

    /// The Mac's appearance: the side a `light:X,dark:Y` pick shows.
    static func systemAppearance() -> ChromeTheme.Polarity {
        NSApplication.shared.effectiveAppearance.isDark ? .dark : .light
    }

    static func liveAppearanceState(_ picks: GhosttiesThemePicks) -> GhosttiesAppearanceState {
        GhosttiesAppearanceState.resolve(configPath: (NSApp.delegate as? AppDelegate)?.ghostty.configPath, picks: picks)
    }

    /// What each side shows for `state`, an unset side filled by Ghostties.
    static func shownPicks(for state: GhosttiesAppearanceState) -> GhosttiesThemePicks {
        switch state {
        case .ghostties, .setByConfig:
            return GhosttiesThemeCatalog.resolved(.none)
        case .custom(let themeName):
            let sides = GhosttiesThemeProbe.sides(of: themeName)
            return GhosttiesThemeCatalog.resolved(GhosttiesThemePicks(light: sides.light, dark: sides.dark))
        case .picked(let light, let dark):
            return GhosttiesThemePicks(light: light, dark: dark)
        }
    }

    // MARK: Derived

    var isActive: Bool {
        if case .theme = command { return true }
        return false
    }

    var query: String {
        if case .theme(let query) = command { return query }
        return ""
    }

    var appearance: ChromeTheme.Polarity { appearanceProvider() }
    private var applied: GhosttiesThemePicks { .stored(in: defaults) }

    /// Every bundled theme: the All themes tile's count.
    var themeCount: Int { themes.count }

    /// The grid cell that shows now (checkmarked), or nil when locked.
    var appliedIndex: Int? {
        isLockedByConfig ? nil : ThemeGridModel.selectedIndex(current: current)
    }

    /// C1's chips: one per family, in the matcher's ranking, each carrying
    /// the theme that ranked it (its subtitle). A chip previews and commits
    /// the family's pair, so what shows is what Return stores.
    var chipResults: [ThemeChoice] {
        guard !isLockedByConfig else { return [] }
        let ranked = ComposerThemeMatcher.chips(
            query: query, families: families, applied: applied, appearance: appearance, limit: .max
        )
        var seen: Set<String> = []
        return Array(ranked.filter { seen.insert($0.family).inserted }.prefix(Self.chipLimit))
    }

    static let chipLimit = 6

    func family(named name: String) -> ThemeFamily? {
        families.first { $0.name == name }
    }

    private var resultCount: Int {
        switch presentation {
        case .grid: return isBrowsing ? browseEntries.count : gridCells.count
        case .chips: return chipResults.count
        }
    }

    /// Return commits (vs. shakes).
    var hasSelection: Bool { isActive && resultCount > 0 }

    /// C2's expanded card: the grid or the browse view.
    var isGridShown: Bool { isActive && presentation == .grid }
    /// The browse view shows in place of the grid.
    var isBrowsing: Bool { isGridShown && (isBrowseOpened || !query.isEmpty) }
    /// ← / → belong to the grid only while it has something to move between.
    var claimsHorizontalArrows: Bool { isGridShown && hasSelection }
    var isChipsShown: Bool { isActive && presentation == .chips }

    /// Whether the browse entry shows now (checkmarked).
    func isApplied(_ entry: ThemeBrowseEntry) -> Bool {
        guard !isLockedByConfig else { return false }
        switch entry {
        case .family(let family): return family.picks == current
        case .single(let name, let polarity): return (polarity == .light ? current.light : current.dark) == name
        }
    }

    /// The field's ghost path: what is typed plus the completion, or nil
    /// when the text isn't the theme command.
    func ghostFullPath(typed: String) -> String? {
        switch command {
        case .none:
            return nil
        case .partial(let completion):
            return typed + completion
        case .theme(let query):
            let top: [String]
            switch presentation {
            case .grid:
                if isBrowsing {
                    switch browseEntries[safe: selection] {
                    case .family(let family): top = [family.themeName(for: appearance), family.name]
                    case .single(let name, _): top = [name]
                    case nil: top = []
                    }
                } else if case .family(let family) = gridCells[safe: selection] {
                    top = [family.themeName(for: appearance), family.name]
                } else {
                    top = []
                }
            case .chips:
                top = chipResults[safe: selection].map { [$0.name, $0.family] } ?? []
            }
            return typed + ComposerThemeMatcher.ghostSuffix(typed: typed, query: query, topNames: top)
        }
    }

    /// The composer opened: classify every bundled theme off the main
    /// thread before All themes can ask (`ThemeBrowseModel.warmPolarityCache`).
    func warmThemes() {
        ThemeBrowseModel.warmPolarityCache(themes: themes)
    }

    func thumbnail(_ name: String) -> ThemePreview {
        if let cached = thumbnails[name] { return cached }
        let made = ThemePreview(name: name)
        thumbnails[name] = made
        return made
    }

    // MARK: Events

    /// The composer's text changed.
    func sync(text: String, projectNames: [String]) {
        let wasActive = isActive
        command = ComposerThemeCommand.parse(text, projectNames: projectNames)
        peekName = nil
        let landOnAllThemes = landOnAllThemesAfterClose
        landOnAllThemesAfterClose = false
        guard case .theme(let query) = command else {
            selectionIsPreviewed = false
            isBrowseOpened = false
            preview.revert()
            return
        }
        if !wasActive {
            presentation = .stored(in: defaults)
            let state = appearanceState(applied)
            isLockedByConfig = state == .setByConfig
            current = Self.shownPicks(for: state)
            gridCells = isLockedByConfig ? [] : ThemeGridModel.cells(current: current)
            isBrowseOpened = false
            browseFilter = .pairs
        }
        switch presentation {
        case .grid:
            if isBrowsing {
                refreshBrowseEntries()
                selection = 0
            } else if landOnAllThemes {
                selection = max(gridCells.count - 1, 0)
            } else {
                selection = appliedIndex ?? 0
            }
        case .chips:
            selection = 0
        }
        selectionIsPreviewed = !query.isEmpty
        showSelection()
    }

    /// An arrow key. False when the picker doesn't take it.
    func move(_ direction: MoveCommandDirection, columns: Int) -> Bool {
        let count = resultCount
        guard isActive, count > 0 else { return false }
        switch presentation {
        case .grid:
            let delta: Int
            switch direction {
            case .left: delta = -1
            case .right: delta = 1
            case .up: delta = -max(columns, 1)
            case .down: delta = max(columns, 1)
            @unknown default: return false
            }
            selection = min(max(selection + delta, 0), count - 1)
        case .chips:
            switch direction {
            case .up: selection = (selection - 1 + count) % count
            case .down: selection = (selection + 1) % count
            default: return false
            }
        }
        peekName = nil
        selectionIsPreviewed = true
        showSelection()
        return true
    }

    /// Selects a result and previews it (pointer over a card, or a capture).
    func select(_ index: Int) {
        guard isActive, resultCount > 0 else { return }
        selection = min(max(index, 0), resultCount - 1)
        peekName = nil
        selectionIsPreviewed = true
        showSelection()
    }

    /// The pointer is over a chip: preview its family's pair, the pick a
    /// click stores.
    func peekChip(_ choice: ThemeChoice) {
        guard isActive, let picks = family(named: choice.family)?.picks else { return }
        peekName = choice.name
        preview.preview(light: picks.light, dark: picks.dark)
    }

    /// The pointer is over one thumbnail half: preview exactly that theme on
    /// either appearance. Nil hands back to the selection.
    func peek(_ name: String?) {
        guard isActive else { return }
        peekName = name
        if let name {
            preview.preview(light: name, dark: name)
        } else {
            showSelection()
        }
    }

    /// The pointer left the results.
    func endHover() {
        guard isActive, peekName != nil || selectionIsPreviewed else { return }
        peekName = nil
        showSelection()
    }

    /// A chip over All themes: Pairs, Light or Dark.
    func setBrowseFilter(_ filter: ThemeBrowseFilter) {
        guard isBrowsing, filter != browseFilter else { return }
        browseFilter = filter
        refreshBrowseEntries()
        selection = 0
        peekName = nil
        selectionIsPreviewed = !query.isEmpty
        showSelection()
    }

    /// The All themes tile: the browse view, in place, nothing previewed.
    func openBrowse() {
        guard isGridShown, !isLockedByConfig else { return }
        isBrowseOpened = true
        browseFilter = .pairs
        refreshBrowseEntries()
        selection = 0
        peekName = nil
        selectionIsPreviewed = false
        preview.revert()
    }

    /// Esc in the browse view: back to the grid on the All themes tile,
    /// preview reverted. The caller clears a typed query.
    func closeBrowse() {
        guard isBrowsing else { return }
        landOnAllThemesAfterClose = !query.isEmpty
        isBrowseOpened = false
        peekName = nil
        selectionIsPreviewed = false
        preview.revert()
        selection = max(gridCells.count - 1, 0)
    }

    /// Return: stores the selected theme, or opens All themes from its tile.
    func activate() -> ComposerThemeActivation {
        guard isActive else { return .none }
        if presentation == .grid, !isBrowsing, gridCells[safe: selection] == ThemeGridCell.allThemes {
            openBrowse()
            return .openedBrowse
        }
        return commit() ? .committed : .none
    }

    /// A click on result `index`.
    func activate(at index: Int) -> ComposerThemeActivation {
        guard isActive, resultCount > index else { return .none }
        selection = index
        return activate()
    }

    /// Stores the selected result. False when there is nothing to commit
    /// (no result, or the All themes tile).
    @discardableResult
    func commit() -> Bool {
        guard isActive, let picks = selectedPicks else { return false }
        if case .custom = gridCells[safe: selection], presentation == .grid, !isBrowsing, applied.isEmpty {
            // Custom with no pick is the user's own theme: keep it as is.
            preview.revert()
        } else {
            preview.commit(light: picks.light, dark: picks.dark)
        }
        selectionIsPreviewed = false
        return true
    }

    /// A click on result `index`.
    func commit(at index: Int) -> Bool {
        guard isActive, resultCount > index else { return false }
        selection = index
        return commit()
    }

    /// Esc, or the composer closed: drop the preview and leave theme mode.
    func reset() {
        command = .none
        peekName = nil
        selectionIsPreviewed = false
        isBrowseOpened = false
        preview.revert()
    }

    /// What the selection stores (and previews), nil for none or the All
    /// themes tile.
    private var selectedPicks: GhosttiesThemePicks? {
        switch presentation {
        case .grid:
            if isBrowsing {
                guard let entry = browseEntries[safe: selection] else { return nil }
                return ThemeBrowseModel.picks(choosing: entry, side: nil, current: current)
            }
            return gridCells[safe: selection]?.picks
        case .chips:
            guard let choice = chipResults[safe: selection] else { return nil }
            return family(named: choice.family)?.picks
        }
    }

    private func showSelection() {
        guard selectionIsPreviewed, let picks = selectedPicks else { return preview.revert() }
        if case .custom = gridCells[safe: selection], !isBrowsing, presentation == .grid, applied.isEmpty {
            // The user's own theme is what already shows.
            return preview.revert()
        }
        preview.preview(light: picks.light, dark: picks.dark)
    }

    private func refreshBrowseEntries() {
        browseEntries = isLockedByConfig ? [] : ThemeBrowseModel.entries(
            filter: browseFilter, query: query, themes: themes, families: browseFamilies
        )
    }

    /// The Settings banner's "Open Config File": `Ghostty.App.openConfig`.
    func openConfig() {
        (NSApp.delegate as? AppDelegate)?.ghostty.openConfig()
    }
}

// MARK: - Shared ink

/// Colours the picker draws, all existing tokens: the composer's selection
/// accent, the chrome's secondary ink and composer-row wash, and the
/// system separator.
enum ComposerThemeInk {
    static let selection = WorkspaceLayout.composerSelectionAccent

    static func secondary(_ scheme: ColorScheme) -> Color {
        ChromeTheme.active(scheme).inkSecondaryColor
    }

    static func wash(_ scheme: ColorScheme) -> Color {
        ChromeTheme.active(scheme).ink(.composerRow)
    }

    static let hairline = Color(nsColor: .separatorColor)
}

private struct ComposerThemeEmptyText: View {
    let text: String
    let size: CGFloat
    @ChromeScheme private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ComposerThemeCopy {
    static let noMatches = "No theme matches"
    static let locked = "Your config sets colors directly, so a theme can't change them."
    static let openConfig = "Open Config File"
}

/// The empty/locked line under the results: the message, plus the Settings
/// banner's "Open Config File" when the user's config locks the theme.
private struct ComposerThemeStatusLine: View {
    @ObservedObject var model: ComposerThemePickerModel
    let size: CGFloat
    @ChromeScheme private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ComposerThemeEmptyText(
                text: model.isLockedByConfig ? ComposerThemeCopy.locked : ComposerThemeCopy.noMatches,
                size: size
            )
            if model.isLockedByConfig {
                Button(ComposerThemeCopy.openConfig) { model.openConfig() }
                    .buttonStyle(.link)
                    .font(.system(size: size, weight: .medium))
            }
        }
    }
}

// MARK: - C2: thumbnail grid

/// C2: the card grows downward into the shared 3x3 grid (eight pairs and
/// the All themes tile), or the All themes browse view in its place.
/// Arrow keys move in 2D; hovering a thumbnail half previews that side.
struct ComposerThemeGrid: View {
    @ObservedObject var model: ComposerThemePickerModel
    /// The card's width.
    let width: CGFloat
    let titleSize: CGFloat
    let onCommit: () -> Void

    /// The composer's width while the grid shows, room permitting: three
    /// full rows of cards without scrolling.
    static let cardWidth: CGFloat = 860
    /// Kept clear beside the card: the palette's 8pt shake inset and 16pt
    /// of window on each side.
    static let windowMargin: CGFloat = 48
    /// Never narrower than this, however small the window.
    static let minimumCardWidth: CGFloat = 320
    /// The narrowest card that fits three columns (a card needs ~180pt for
    /// its two thumbnails and a name).
    static let threeColumnWidth: CGFloat = 600
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    static let thumbnailHeight: CGFloat = 64
    static let visibleRows = 3

    /// `min(cardWidth, available - windowMargin)`; `cardWidth` when the
    /// window's width isn't known.
    static func cardWidth(available: CGFloat?) -> CGFloat {
        guard let available else { return cardWidth }
        return max(min(cardWidth, available - windowMargin), minimumCardWidth)
    }

    /// Three columns when they fit, else two.
    static func columns(cardWidth: CGFloat) -> Int {
        cardWidth >= threeColumnWidth ? ThemeGridModel.columns : 2
    }

    private var columns: Int { Self.columns(cardWidth: width) }
    private var labelSize: CGFloat { (titleSize * 0.72).rounded() }
    private var headerSize: CGFloat { titleSize * 0.62 }
    private var metrics: ThemeCardMetrics {
        ThemeCardMetrics(thumbnailHeight: Self.thumbnailHeight, labelSize: labelSize)
    }

    /// Three rows of cards: the grid's height, and the browse view's, so
    /// the card doesn't jump between them.
    private var rowsHeight: CGFloat {
        let rows = CGFloat(Self.visibleRows)
        return rows * metrics.cardHeight + (rows - 1) * Self.spacing + 2 * Self.inset
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerCardHairline()
                .padding(.horizontal, Self.inset + 4)
            header
            if model.isLockedByConfig || (model.isBrowsing ? model.browseEntries.isEmpty : model.gridCells.isEmpty) {
                ComposerThemeStatusLine(model: model, size: labelSize)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .frame(height: model.isBrowsing ? rowsHeight : nil, alignment: .top)
            } else if model.isBrowsing {
                browseGrid
            } else {
                cellGrid
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isBrowsing ? "All themes" : "Themes")
    }

    /// The palette icon and THEMES (no count: the grid is always nine), or
    /// ALL THEMES with its count and the chips.
    private var header: some View {
        ComposerResumeSectionHeader(
            systemImage: "paintpalette",
            title: model.isBrowsing ? "All themes · \(model.themeCount)" : "Themes",
            size: headerSize
        )
        .overlay(alignment: .trailing) {
            Group {
                if model.isBrowsing {
                    ThemeBrowseChips(selection: model.browseFilter, size: headerSize * 1.1) { model.setBrowseFilter($0) }
                } else {
                    ComposerThemeHint(size: headerSize)
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
    }

    /// The nine cells. Three columns fit without scrolling; two (a narrow
    /// window) scroll inside the same three-row height.
    @ViewBuilder
    private var cellGrid: some View {
        if columns >= ThemeGridModel.columns {
            cells
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { cells }
                    .frame(height: rowsHeight)
                    .onChange(of: model.selection) { proxy.scrollTo($0) }
            }
        }
    }

    private var cells: some View {
        LazyVGrid(columns: gridColumns, spacing: Self.spacing) {
            ForEach(Array(model.gridCells.enumerated()), id: \.offset) { index, cell in
                ComposerThemeCellCard(
                    model: model,
                    index: index,
                    isSelected: index == model.selection,
                    metrics: metrics,
                    onCommit: onCommit
                ) {
                    ThemeGridCellCard(
                        cell: cell,
                        isSelected: index == model.selection,
                        isApplied: index == model.appliedIndex,
                        themeCount: model.themeCount,
                        metrics: metrics,
                        thumbnail: model.thumbnail,
                        peekName: model.peekName,
                        onPeek: { name in peek(name, index: index) }
                    )
                }
                .id(index)
            }
        }
        .padding(Self.inset)
        .onHover { inside in
            if !inside { model.endHover() }
        }
    }

    private var browseGrid: some View {
        let entries = model.browseEntries
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: entries.count > columns * Self.visibleRows) {
                LazyVGrid(columns: gridColumns, spacing: Self.spacing) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ComposerThemeCellCard(
                            model: model,
                            index: index,
                            isSelected: index == model.selection,
                            metrics: metrics,
                            onCommit: onCommit
                        ) {
                            ThemeBrowseCard(
                                entry: entry,
                                isSelected: index == model.selection,
                                isApplied: model.isApplied(entry),
                                metrics: metrics,
                                thumbnail: model.thumbnail,
                                peekName: model.peekName,
                                onPeek: { name in peek(name, index: index) }
                            )
                        }
                        .id(entry.id)
                    }
                }
                .padding(Self.inset)
            }
            .frame(height: rowsHeight)
            .onChange(of: model.selection) { index in
                guard let entry = entries[safe: index] else { return }
                proxy.scrollTo(entry.id)
            }
        }
        .onHover { inside in
            if !inside { model.endHover() }
        }
    }

    private func peek(_ name: String?, index: Int) {
        if let name {
            if model.selection != index { model.select(index) }
            model.peek(name)
        } else if model.peekName != nil {
            model.peek(nil)
        }
    }
}

private struct ComposerAvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The width the composer overlay has to lay out in (the window's), or
    /// nil outside it. The theme grid clamps the card to it.
    var composerAvailableWidth: CGFloat? {
        get { self[ComposerAvailableWidthKey.self] }
        set { self[ComposerAvailableWidthKey.self] = newValue }
    }
}

/// "↵ keep · esc revert", the grid header's trailing hint.
private struct ComposerThemeHint: View {
    let size: CGFloat
    @ChromeScheme private var colorScheme

    var body: some View {
        Text("↵ keep · esc revert")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
            .accessibilityHidden(true)
    }
}

/// The composer's wiring around one card: hover selects (and previews),
/// a click acts, VoiceOver reads it as a button.
private struct ComposerThemeCellCard<Card: View>: View {
    @ObservedObject var model: ComposerThemePickerModel
    let index: Int
    let isSelected: Bool
    let metrics: ThemeCardMetrics
    let onCommit: () -> Void
    @ViewBuilder let card: () -> Card

    var body: some View {
        card()
            .contentShape(RoundedRectangle(cornerRadius: ThemeCardMetrics.cornerRadius, style: .continuous))
            .onHover { inside in
                if inside, model.selection != index || model.peekName != nil { model.select(index) }
            }
            .onTapGesture { activate() }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction(.default) { activate() }
    }

    private func activate() {
        if model.activate(at: index) == .committed { onCommit() }
    }
}

// MARK: - Shared cards (composer + Settings)

/// The sizes one theme card draws at; the composer and Settings differ
/// only in these.
struct ThemeCardMetrics {
    let thumbnailHeight: CGFloat
    let labelSize: CGFloat

    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    static let cornerRadius: CGFloat = 10
    static let thumbnailRadius: CGFloat = 6

    var labelHeight: CGFloat { (labelSize * 1.3).rounded(.up) }
    var cardHeight: CGFloat { Self.inset + thumbnailHeight + Self.spacing + labelHeight + Self.inset }
}

/// One grid cell as a card: a family, Custom, or the All themes tile.
struct ThemeGridCellCard: View {
    let cell: ThemeGridCell
    let isSelected: Bool
    let isApplied: Bool
    let themeCount: Int
    let metrics: ThemeCardMetrics
    let thumbnail: (String) -> ThemePreview
    var peekName: String?
    var onPeek: ((String?) -> Void)?

    var body: some View {
        switch cell {
        case .family(let family):
            ThemeCard(
                title: family.name, sides: [family.light, family.dark].compactMap { $0 }, tag: nil,
                isSelected: isSelected, isApplied: isApplied, metrics: metrics,
                thumbnail: thumbnail, peekName: peekName, onPeek: onPeek
            )
        case .custom(let light, let dark):
            ThemeCard(
                title: "Custom", sides: [light, dark], tag: light == dark ? light : "\(light) · \(dark)",
                isSelected: isSelected, isApplied: isApplied, metrics: metrics,
                thumbnail: thumbnail, peekName: peekName, onPeek: onPeek
            )
        case .allThemes:
            ThemeAllThemesCard(count: themeCount, isSelected: isSelected, metrics: metrics)
        }
    }
}

/// One All themes entry as a card: a pair, or one theme tagged light or
/// dark.
struct ThemeBrowseCard: View {
    let entry: ThemeBrowseEntry
    let isSelected: Bool
    let isApplied: Bool
    let metrics: ThemeCardMetrics
    let thumbnail: (String) -> ThemePreview
    var peekName: String?
    var onPeek: ((String?) -> Void)?

    var body: some View {
        switch entry {
        case .family(let family):
            ThemeCard(
                title: family.name, sides: [family.light, family.dark].compactMap { $0 }, tag: nil,
                isSelected: isSelected, isApplied: isApplied, metrics: metrics,
                thumbnail: thumbnail, peekName: peekName, onPeek: onPeek
            )
        case .single(let name, let polarity):
            ThemeCard(
                title: name, sides: [name], tag: polarity == .light ? "light" : "dark",
                isSelected: isSelected, isApplied: isApplied, metrics: metrics,
                thumbnail: thumbnail, peekName: nil, onPeek: nil
            )
        }
    }
}

extension ThemeBrowseEntry {
    /// Stable across filters: a pair and a single theme never share one.
    var id: String {
        switch self {
        case .family(let family): return "pair:\(family.name)"
        case .single(let name, _): return "theme:\(name)"
        }
    }
}

/// A theme as a card: its light and dark thumbnails side by side (one for
/// a single theme), then its name, a checkmark when it shows now, and a
/// trailing tag.
struct ThemeCard: View {
    let title: String
    let sides: [String]
    let tag: String?
    let isSelected: Bool
    let isApplied: Bool
    let metrics: ThemeCardMetrics
    let thumbnail: (String) -> ThemePreview
    var peekName: String?
    /// Hovering one half of a pair previews that side; nil turns it off.
    var onPeek: ((String?) -> Void)?
    @ChromeScheme private var colorScheme

    private var isPair: Bool { sides.count == 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeCardMetrics.spacing) {
            HStack(spacing: 0) {
                ForEach(Array(sides.enumerated()), id: \.offset) { _, name in
                    ComposerThemeHalf(preview: thumbnail(name), isPeeked: isPair && peekName == name)
                        .onHover { inside in
                            guard isPair, let onPeek else { return }
                            if inside {
                                onPeek(name)
                            } else if peekName == name {
                                onPeek(nil)
                            }
                        }
                }
            }
            .frame(height: metrics.thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: ThemeCardMetrics.thumbnailRadius, style: .continuous))

            ThemeCardLabel(title: title, tag: tag, isApplied: isApplied, metrics: metrics)
        }
        .modifier(ThemeCardChrome(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var label = title
        if let tag { label += ", \(tag)" }
        if isApplied { label += ", applied" }
        return label
    }
}

/// The ninth cell: the bundled theme count where the thumbnails go, then
/// "All themes →".
struct ThemeAllThemesCard: View {
    let count: Int
    let isSelected: Bool
    let metrics: ThemeCardMetrics
    @ChromeScheme private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeCardMetrics.spacing) {
            VStack(spacing: 0) {
                Text("\(count)")
                    .font(.system(size: (metrics.labelSize * 1.7).rounded(), weight: .bold))
                    .foregroundStyle(.primary)
                Text("themes")
                    .font(.system(size: metrics.labelSize * 0.9))
                    .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.thumbnailHeight)
            .background(
                RoundedRectangle(cornerRadius: ThemeCardMetrics.thumbnailRadius, style: .continuous)
                    .fill(ComposerThemeInk.wash(colorScheme))
            )

            ThemeCardLabel(title: "All themes", tag: nil, isApplied: false, metrics: metrics, trailingArrow: true)
        }
        .modifier(ThemeCardChrome(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All themes, \(count) themes")
    }
}

/// A card's name row.
private struct ThemeCardLabel: View {
    let title: String
    let tag: String?
    let isApplied: Bool
    let metrics: ThemeCardMetrics
    var trailingArrow = false
    @ChromeScheme private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: metrics.labelSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if trailingArrow {
                Image(systemName: "arrow.right")
                    .font(.system(size: metrics.labelSize * 0.8, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            if isApplied {
                Image(systemName: "checkmark")
                    .font(.system(size: metrics.labelSize * 0.8, weight: .semibold))
                    .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
            }
            Spacer(minLength: 4)
            if let tag {
                Text(tag)
                    .font(.system(size: metrics.labelSize * 0.9))
                    .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: metrics.labelHeight)
        .padding(.horizontal, 4)
    }
}

/// The card's padding, selection wash and border.
private struct ThemeCardChrome: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ThemeCardMetrics.cornerRadius, style: .continuous)
        content
            .padding(ThemeCardMetrics.inset)
            .background(shape.fill(isSelected ? ComposerThemeInk.selection.opacity(0.10) : .clear))
            .overlay(
                shape.strokeBorder(
                    isSelected ? ComposerThemeInk.selection : ComposerThemeInk.hairline,
                    lineWidth: isSelected ? 2 : 1
                )
            )
    }
}

/// Pairs / Light / Dark over All themes.
struct ThemeBrowseChips: View {
    let selection: ThemeBrowseFilter
    let size: CGFloat
    let onSelect: (ThemeBrowseFilter) -> Void
    @ChromeScheme private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ThemeBrowseFilter.allCases, id: \.self) { filter in
                let selected = filter == selection
                Text(filter.title)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(selected ? Color.primary : ComposerThemeInk.secondary(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selected ? ComposerThemeInk.wash(colorScheme) : .clear)
                    )
                    .contentShape(Capsule(style: .continuous))
                    .onTapGesture { onSelect(filter) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(filter.title)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onSelect(filter) }
            }
        }
    }
}

/// A window in miniature for one theme: the sidebar strip in the theme's
/// chrome, then a few lines of terminal text in its palette on its canvas.
private struct ComposerThemeHalf: View {
    let preview: ThemePreview
    let isPeeked: Bool

    private var lines: [(color: Color, fraction: CGFloat)] {
        [
            (preview.accents[0], 0.7), (preview.accents[1], 0.9), (preview.accents[2], 0.55),
            (preview.text, 0.8), (preview.accents[3], 0.4),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            preview.chrome.frame(width: 16)
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines.indices, id: \.self) { i in
                        Capsule()
                            .fill(lines[i].color)
                            .frame(width: geo.size.width * lines[i].fraction, height: 3)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(preview.canvas)
        .overlay(
            Rectangle()
                .strokeBorder(ComposerThemeInk.selection, lineWidth: 2)
                .opacity(isPeeked ? 1 : 0)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - C1: chips

/// C1: up to six matching theme names as chips in the status-strip slot.
struct ComposerThemeChips: View {
    @ObservedObject var model: ComposerThemePickerModel
    let titleSize: CGFloat
    let onCommit: () -> Void

    private var labelSize: CGFloat { (titleSize * 0.72).rounded() }

    var body: some View {
        let chips = model.chipResults
        Group {
            if chips.isEmpty {
                ComposerThemeStatusLine(model: model, size: labelSize)
            } else {
                ComposerChipFlow(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.element.name) { index, choice in
                        ComposerThemeChip(
                            preview: model.thumbnail(
                                model.family(named: choice.family)?.themeName(for: model.appearance) ?? choice.name
                            ),
                            family: choice.family,
                            matched: choice.name,
                            isSelected: index == model.selection,
                            labelSize: labelSize
                        )
                        .onHover { inside in
                            if inside {
                                model.peekChip(choice)
                            } else if model.peekName == choice.name {
                                model.endHover()
                            }
                        }
                        .onTapGesture {
                            if model.commit(at: index) { onCommit() }
                        }
                        .accessibilityAction(.default) { if model.commit(at: index) { onCommit() } }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Themes")
    }
}

/// One family as a chip: the swatch and name of the side that shows on
/// this appearance, then the theme the query matched, in secondary ink
/// (omitted when it is just the family's name).
private struct ComposerThemeChip: View {
    let preview: ThemePreview
    let family: String
    let matched: String
    let isSelected: Bool
    let labelSize: CGFloat
    @ChromeScheme private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(preview.canvas)
                .overlay(Circle().fill(preview.accents[3]).padding(3))
                .overlay(Circle().strokeBorder(ComposerThemeInk.hairline, lineWidth: 1))
                .frame(width: 12, height: 12)
            Text(family)
                .font(.system(size: labelSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if matched != family {
                Text(matched)
                    .font(.system(size: labelSize * 0.85))
                    .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? ComposerThemeInk.selection.opacity(0.22) : ComposerThemeInk.wash(colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ComposerThemeInk.selection, lineWidth: 1)
                .opacity(isSelected ? 1 : 0)
        )
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(matched == family ? family : "\(family), \(matched)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Lays chips left to right, wrapping to a new line when the next one
/// doesn't fit.
private struct ComposerChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Expand

/// Grows its content downward from zero height: the grid's reveal. A
/// layout that reports a fraction of the content's height, animated.
struct ComposerRevealDown: AnimatableModifier {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        ComposerHeightFraction(fraction: fraction) { content }
            .clipped()
    }
}

private struct ComposerHeightFraction: Layout {
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height * fraction)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

extension AnyTransition {
    /// The theme grid's expand: height from zero, top edge fixed.
    static var composerRevealDown: AnyTransition {
        .modifier(active: ComposerRevealDown(fraction: 0), identity: ComposerRevealDown(fraction: 1))
    }
}
