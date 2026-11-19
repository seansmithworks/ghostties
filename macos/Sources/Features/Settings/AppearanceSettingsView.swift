import AppKit
import SwiftUI

/// Settings > Appearance: the Mode switch, the same 3x3 theme grid as the
/// composer (`ThemeGridModel`; the user's own `theme =` line, or a mixed
/// pair, is the Custom card), and the All themes browse view with a
/// Light/Dark side switch for mixing. A pick is stored in the app's
/// defaults and applied live through `reloadConfig()`; the user's config
/// file is never written.
struct AppearanceSettingsView: View {
    @StateObject private var model: AppearanceSettingsModel
    @Environment(\.colorScheme) private var colorScheme

    /// `model` is injectable so the pane can be rendered offscreen in a
    /// given state.
    init(model: @autoclosure @escaping () -> AppearanceSettingsModel) {
        _model = StateObject(wrappedValue: model())
    }

    init() {
        self.init(model: AppearanceSettingsModel(applyMode: {
            (NSApp.delegate as? AppDelegate)?.applyAppearanceMode()
        }))
    }

    var body: some View {
        Form {
            Section {
                let preview = model.preview(model.previewThemeName(systemScheme: colorScheme))
                SettingsPreviewStrip(palette: .theme(preview)) {
                    SettingsPreviewSidebarSketch(ink: preview.text, inkSecondary: preview.inkSecondary)
                }
                .listRowInsets(EdgeInsets())
            }

            if model.state == .setByConfig {
                Section {
                    SetByConfigBanner(openConfig: model.openConfig)
                }
            }

            Section {
                Picker("Mode", selection: $model.mode) {
                    Text("System").tag(GhosttiesAppearanceMode.system)
                    Text("Light").tag(GhosttiesAppearanceMode.light)
                    Text("Dark").tag(GhosttiesAppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .disabled(model.modeLockedByConfig)
                if let note = model.modeLockedNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Group {
                    if model.isBrowsing {
                        ThemeBrowsePanel(model: model)
                    } else {
                        ThemeGridPanel(model: model)
                    }
                }
                .padding(.vertical, 8)
                .disabled(model.locked)
                .opacity(model.locked ? 0.4 : 1)
            } header: {
                Text("Theme")
            } footer: {
                HStack {
                    if !model.isBrowsing {
                        Button(AppearanceSettingsModel.mixTitle, action: model.openMix)
                            .disabled(model.locked)
                    }
                    Spacer()
                    if let reset = model.resetLabel {
                        Button(reset) { model.clearPicks() }
                    }
                    Button("Open Config File", action: model.openConfig)
                }
            }

        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyConfigDidChange)) { note in
            // App-level config only (a surface's own reload carries the surface).
            guard note.object == nil else { return }
            model.refresh()
        }
    }
}

// MARK: - Model

@MainActor
final class AppearanceSettingsModel: ObservableObject {
    static let mixTitle = "Mix light & dark…"

    @Published private(set) var state: GhosttiesAppearanceState = .ghostties
    @Published private(set) var probe = GhosttiesThemeProbe.Result(kind: .none, themeName: nil)
    @Published private(set) var picks = GhosttiesThemePicks.none
    @Published private(set) var configWindowTheme: String?
    @Published private var storedMode: GhosttiesAppearanceMode
    /// All themes shows in place of the grid.
    @Published private(set) var isBrowsing = false
    /// The side a single theme chosen in All themes sets.
    @Published var browseSide: ChromeTheme.Polarity = .light
    @Published var browseFilter: ThemeBrowseFilter = .pairs
    @Published var browseQuery = ""

    let themeNames: [String]
    private lazy var browseFamilies = GhosttiesThemeCatalog.browseFamilies(themes: themeNames)
    private let defaults: UserDefaults
    private var previews: [String: ThemePreview] = [:]

    private let windowTheme: () -> String?
    private let applyMode: () -> Void

    /// `windowTheme` reads the running app's config `window-theme`;
    /// `applyMode` re-applies the app appearance after the mode changes
    /// (a no-op unless the caller wires it, so tests never touch `NSApp`).
    init(
        defaults: UserDefaults = GhosttiesThemePicks.appDefaults,
        windowTheme: @escaping () -> String? = { (NSApp.delegate as? AppDelegate)?.ghostty.config.windowTheme },
        applyMode: @escaping () -> Void = {}
    ) {
        self.defaults = defaults
        self.windowTheme = windowTheme
        self.applyMode = applyMode
        self.storedMode = GhosttiesAppearanceMode.stored(in: defaults)
        self.themeNames = GhosttiesThemeCatalog.bundledThemeNames()
        ThemeBrowseModel.warmPolarityCache(themes: themeNames)
        refresh()
    }

    private var ghostty: Ghostty.App? { (NSApp.delegate as? AppDelegate)?.ghostty }

    /// Re-reads the user's config and the stored pick.
    func refresh() {
        let path = ghostty?.configPath
        probe = GhosttiesThemeProbe.probe(configPath: path)
        picks = GhosttiesThemePicks.stored(in: defaults)
        state = GhosttiesAppearanceState.resolve(configPath: path, picks: picks)
        configWindowTheme = windowTheme()
        storedMode = GhosttiesAppearanceMode.stored(in: defaults)
    }

    /// System / Light / Dark. Setting it stores the choice and applies it live.
    var mode: GhosttiesAppearanceMode {
        get { storedMode }
        set {
            guard newValue != storedMode else { return }
            newValue.store(in: defaults)
            storedMode = newValue
            applyMode()
        }
    }

    /// The theme the window shows now, for the preview strip: the side the
    /// mode picks, with System following `systemScheme`.
    func previewThemeName(systemScheme: ColorScheme) -> String {
        let dark: Bool
        switch mode {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = systemScheme == .dark
        }
        return dark ? shown.dark : shown.light
    }

    /// `window-theme` in the user's config fixes the appearance.
    var modeLockedByConfig: Bool { GhosttiesAppearanceMode.isLocked(byConfigWindowTheme: configWindowTheme) }

    var modeLockedNote: String? {
        switch configWindowTheme {
        case "light": return "Light, set by window-theme in your config"
        case "dark": return "Dark, set by window-theme in your config"
        case "ghostty": return "Follows the terminal theme (window-theme in your config)"
        default: return nil
        }
    }

    /// Explicit colour keys in the user's config beat any pick.
    var locked: Bool { state == .setByConfig }

    /// What each side shows with no pick: the user's own theme, else Ghostties.
    private var baseline: (light: String, dark: String) {
        let ghostties = GhosttiesThemeCatalog.ghostties
        guard probe.kind != .none, let name = probe.themeName else { return (ghostties.light, ghostties.dark) }
        let sides = GhosttiesThemeProbe.sides(of: name)
        return (sides.light ?? ghostties.light, sides.dark ?? ghostties.dark)
    }

    /// The theme each side shows right now.
    var shown: (light: String, dark: String) {
        if case let .picked(light, dark) = state { return (light, dark) }
        return baseline
    }

    /// What each side shows, as picks.
    var shownPicks: GhosttiesThemePicks {
        let current = shown
        return GhosttiesThemePicks(light: current.light, dark: current.dark)
    }

    /// The composer's grid, for what shows here.
    var gridCells: [ThemeGridCell] { ThemeGridModel.cells(current: shownPicks) }

    /// The cell that shows now, or nil when the config locks the theme.
    var selectedCellIndex: Int? { locked ? nil : ThemeGridModel.selectedIndex(current: shownPicks) }

    var browseEntries: [ThemeBrowseEntry] {
        ThemeBrowseModel.entries(filter: browseFilter, query: browseQuery, themes: themeNames, families: browseFamilies)
    }

    /// Whether `entry` is what shows now.
    func isApplied(_ entry: ThemeBrowseEntry) -> Bool {
        guard !locked else { return false }
        switch entry {
        case .family(let family): return family.picks == shownPicks
        case .single(let name, let polarity): return (polarity == .light ? shown.light : shown.dark) == name
        }
    }

    /// The reset button's label, or nil when there is no pick to clear.
    var resetLabel: String? {
        guard !picks.isEmpty, !locked else { return nil }
        return probe.kind == .themeOnly ? "Use Theme from Config" : "Reset to Ghostties"
    }

    /// A grid cell: a family or Custom stores its pair (Custom with no
    /// pick is the user's own theme, so that clears instead); All themes
    /// opens the browse view and stores nothing.
    func select(_ cell: ThemeGridCell) {
        guard let picks = cell.picks else { return openMix() }
        let shown = GhosttiesThemeCatalog.resolved(picks)
        apply(light: shown.light ?? GhosttiesThemeCatalog.ghostties.light, dark: shown.dark ?? GhosttiesThemeCatalog.ghostties.dark)
    }

    /// An All themes card: a pair sets both sides, a single theme only the
    /// `browseSide` side.
    func choose(_ entry: ThemeBrowseEntry) {
        let picks = ThemeBrowseModel.picks(choosing: entry, side: browseSide, current: shownPicks)
        let shown = GhosttiesThemeCatalog.resolved(picks)
        apply(light: shown.light ?? GhosttiesThemeCatalog.ghostties.light, dark: shown.dark ?? GhosttiesThemeCatalog.ghostties.dark)
    }

    /// "Mix light & dark…" (and the All themes cell): the browse view.
    func openMix() {
        isBrowsing = true
    }

    func closeBrowse() {
        isBrowsing = false
    }

    /// Stores both sides, so changing one side away from a Custom theme
    /// keeps the user's theme on the other. A pick that equals what shows
    /// with no pick is cleared instead, leaving no override layer.
    func apply(light: String, dark: String) {
        let base = baseline
        if (light, dark) == base {
            GhosttiesThemePicks.clear(in: defaults)
        } else {
            GhosttiesThemePicks(light: light, dark: dark).save(to: defaults)
        }
        reload()
    }

    func clearPicks() {
        GhosttiesThemePicks.clear(in: defaults)
        reload()
    }

    func openConfig() {
        ghostty?.openConfig()
    }

    private func reload() {
        ghostty?.reloadConfig()
        refresh()
    }

    func preview(_ name: String) -> ThemePreview {
        if let cached = previews[name] { return cached }
        let preview = ThemePreview(name: name)
        previews[name] = preview
        return preview
    }
}

/// The colours a card draws for one theme, read from its bundled file;
/// the sidebar strip is the chrome that theme gets (`ChromeTheme.resolve`).
struct ThemePreview {
    let canvas: Color
    let chrome: Color
    let inkSecondary: Color
    let text: Color
    let accents: [Color]

    init(name: String) {
        let background = ThemeFile.background(named: name)
        let foreground = ThemeFile.foreground(named: name) ?? background
        let chrome = ChromeTheme.resolve(background: background, foreground: foreground)
        canvas = Color(nsColor: background)
        self.chrome = Color(nsColor: chrome.chrome)
        inkSecondary = Color(nsColor: chrome.inkSecondary)
        text = Color(nsColor: foreground)
        accents = [2, 4, 1, 5].map { Color(nsColor: ThemeFile.palette($0, named: name) ?? foreground) }
    }
}

// MARK: - Views

/// The sizes Settings draws the shared theme cards at.
private enum SettingsThemeCards {
    static let metrics = ThemeCardMetrics(thumbnailHeight: 48, labelSize: 13)
    static let spacing: CGFloat = 8
    static let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: ThemeGridModel.columns)
    /// All themes scrolls inside three rows of cards.
    static let browseHeight: CGFloat = {
        let rows = CGFloat(3)
        return rows * metrics.cardHeight + (rows - 1) * spacing
    }()
}

/// The composer's 3x3 grid, in the same order.
private struct ThemeGridPanel: View {
    @ObservedObject var model: AppearanceSettingsModel

    var body: some View {
        let selected = model.selectedCellIndex
        LazyVGrid(columns: SettingsThemeCards.columns, spacing: SettingsThemeCards.spacing) {
            ForEach(Array(model.gridCells.enumerated()), id: \.offset) { index, cell in
                SettingsThemeCardButton(isSelected: index == selected, action: { model.select(cell) }) {
                    ThemeGridCellCard(
                        cell: cell,
                        isSelected: index == selected,
                        isApplied: index == selected,
                        themeCount: model.themeNames.count,
                        metrics: SettingsThemeCards.metrics,
                        thumbnail: model.preview
                    )
                }
            }
        }
    }
}

/// All themes: the side a single theme sets, search, the chips, and the
/// scrolling cards. A click applies, as the grid's cards do.
private struct ThemeBrowsePanel: View {
    @ObservedObject var model: AppearanceSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Apply single themes to")
                    .foregroundStyle(.secondary)
                Picker("Apply single themes to", selection: $model.browseSide) {
                    Text("Light").tag(ChromeTheme.Polarity.light)
                    Text("Dark").tag(ChromeTheme.Polarity.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 8)
                Button("Done", action: model.closeBrowse)
            }
            HStack(spacing: 8) {
                TextField("Search", text: $model.browseQuery, prompt: Text("Search \(model.themeNames.count) themes"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                ThemeBrowseChips(selection: model.browseFilter, size: 12) { model.browseFilter = $0 }
            }
            let entries = model.browseEntries
            ScrollView(.vertical) {
                LazyVGrid(columns: SettingsThemeCards.columns, spacing: SettingsThemeCards.spacing) {
                    ForEach(entries, id: \.id) { entry in
                        let applied = model.isApplied(entry)
                        SettingsThemeCardButton(isSelected: applied, action: { model.choose(entry) }) {
                            ThemeBrowseCard(
                                entry: entry,
                                isSelected: applied,
                                isApplied: applied,
                                metrics: SettingsThemeCards.metrics,
                                thumbnail: model.preview
                            )
                        }
                    }
                }
                .padding(4)
            }
            .frame(height: SettingsThemeCards.browseHeight + 8)
            .overlay {
                if entries.isEmpty {
                    Text(ComposerThemeCopy.noMatches).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A shared theme card as a Settings button, with the system focus ring
/// (the plain style draws none).
private struct SettingsThemeCardButton<Card: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let card: () -> Card
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            card()
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeCardMetrics.cornerRadius + 4, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-4)
                        .opacity(focused ? 1 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: ThemeCardMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetByConfigBanner: View {
    let openConfig: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Set by your config").font(.headline)
                Text("Your config sets background, foreground or palette directly. Those lines win over any theme, so the choices below are off until you remove them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Config File", action: openConfig)
        }
    }
}
