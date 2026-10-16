import AppKit
import SwiftUI

/// Settings > Appearance: the theme pair cards, independent light and dark
/// pickers, and the user's own `theme =` line adopted as a Custom card.
/// A pick is stored in the app's defaults and applied live through
/// `reloadConfig()`; the user's config file is never written.
struct AppearanceSettingsView: View {
    @StateObject private var model = AppearanceSettingsModel()
    @AppStorage(ComposerThemePresentation.key, store: GhosttiesThemePicks.appDefaults)
    private var composerThemePresentation: ComposerThemePresentation = .grid

    var body: some View {
        Form {
            if model.state == .setByConfig {
                Section {
                    SetByConfigBanner(openConfig: model.openConfig)
                }
            }

            Section {
                LabeledContent("Mode") {
                    Text(model.modeLabel).foregroundStyle(.secondary)
                }
            }

            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(model.cards) { card in
                        ThemePairCard(card: card, preview: model.preview) { model.select(card) }
                    }
                }
                .padding(.vertical, 8)
                .disabled(model.locked)
                .opacity(model.locked ? 0.4 : 1)
            }

            Section {
                Group {
                    ThemeSidePicker(title: "Light theme", selection: model.lightBinding, names: model.themeNames)
                    ThemeSidePicker(title: "Dark theme", selection: model.darkBinding, names: model.themeNames)
                }
                .disabled(model.locked)
            } footer: {
                HStack {
                    Button("Open Config File", action: model.openConfig)
                    Spacer()
                    if let reset = model.resetLabel {
                        Button(reset) { model.clearPicks() }
                    }
                }
            }

            Section {
                Picker("Composer theme results", selection: $composerThemePresentation) {
                    Text("Grid").tag(ComposerThemePresentation.grid)
                    Text("Chips").tag(ComposerThemePresentation.chips)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
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
    struct Card: Identifiable, Equatable {
        enum Kind: Equatable { case pair(GhosttiesThemeCatalog.Pair), custom }
        let kind: Kind
        let title: String
        let subtitle: String?
        let light: String
        let dark: String
        let selected: Bool
        var id: String { title }
    }

    @Published private(set) var state: GhosttiesAppearanceState = .ghostties
    @Published private(set) var probe = GhosttiesThemeProbe.Result(kind: .none, themeName: nil)
    @Published private(set) var picks = GhosttiesThemePicks.none
    @Published private(set) var modeLabel = "System"

    let themeNames: [String]
    private let defaults: UserDefaults
    private var previews: [String: ThemePreview] = [:]

    init(defaults: UserDefaults = GhosttiesThemePicks.appDefaults) {
        self.defaults = defaults
        self.themeNames = GhosttiesThemeCatalog.bundledThemeNames()
        refresh()
    }

    private var ghostty: Ghostty.App? { (NSApp.delegate as? AppDelegate)?.ghostty }

    /// Re-reads the user's config and the stored pick.
    func refresh() {
        let path = ghostty?.configPath
        probe = GhosttiesThemeProbe.probe(configPath: path)
        picks = GhosttiesThemePicks.stored(in: defaults)
        state = GhosttiesAppearanceState.resolve(configPath: path, picks: picks)
        switch ghostty?.config.windowTheme {
        case "light": modeLabel = "Light, set by window-theme in your config"
        case "dark": modeLabel = "Dark, set by window-theme in your config"
        case "ghostty": modeLabel = "Follows the terminal theme (window-theme in your config)"
        default: modeLabel = "System"
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

    var cards: [Card] {
        let current = shown
        var cards = GhosttiesThemeCatalog.pairs.map { pair in
            Card(
                kind: .pair(pair), title: pair.name, subtitle: nil,
                light: pair.light, dark: pair.dark,
                selected: state != .setByConfig && current == (pair.light, pair.dark)
                    && !isCustomSelected
            )
        }
        // Shown whenever the config names a theme, so the card row and the
        // pickers (which show that theme) agree, locked state included.
        if probe.kind != .none, let name = probe.themeName {
            let base = baseline
            cards.append(Card(
                kind: .custom, title: "Custom", subtitle: name,
                light: base.light, dark: base.dark, selected: isCustomSelected
            ))
        }
        return cards
    }

    private var isCustomSelected: Bool {
        if case .custom = state { return true }
        return false
    }

    var lightBinding: Binding<String> {
        Binding(get: { self.shown.light }, set: { self.apply(light: $0, dark: self.shown.dark) })
    }

    var darkBinding: Binding<String> {
        Binding(get: { self.shown.dark }, set: { self.apply(light: self.shown.light, dark: $0) })
    }

    /// The reset button's label, or nil when there is no pick to clear.
    var resetLabel: String? {
        guard !picks.isEmpty, !locked else { return nil }
        return probe.kind == .themeOnly ? "Use Theme from Config" : "Reset to Ghostties"
    }

    func select(_ card: Card) {
        switch card.kind {
        case .custom: clearPicks()
        case let .pair(pair): apply(light: pair.light, dark: pair.dark)
        }
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

private struct ThemePairCard: View {
    let card: AppearanceSettingsModel.Card
    let preview: (String) -> ThemePreview
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    MiniWindow(preview: preview(card.light))
                    MiniWindow(preview: preview(card.dark))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                HStack(spacing: 8) {
                    Text(card.title).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    if let subtitle = card.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(card.selected ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: card.selected ? 2 : 1)
            )
            .overlay(
                // The plain style draws no focus ring; this is the system's.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-4)
                    .opacity(focused ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityLabel(card.subtitle.map { "\(card.title), \($0)" } ?? card.title)
        .accessibilityAddTraits(card.selected ? .isSelected : [])
    }
}

/// A window in miniature: the sidebar strip in the theme's chrome, then
/// a few lines of terminal text in its palette on its canvas.
private struct MiniWindow: View {
    let preview: ThemePreview

    private static let lines: [[(width: CGFloat, accent: Int?)]] = [
        [(16, 0), (24, nil)],
        [(8, 1), (32, nil)],
        [(24, 2), (16, nil)],
        [(32, nil)],
        [(8, 3), (24, nil)],
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(preview.inkSecondary).frame(width: i == 2 ? 8 : 12, height: 3)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 4)
            .frame(width: 20, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(preview.chrome)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.lines.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(Self.lines[row].indices, id: \.self) { i in
                            let segment = Self.lines[row][i]
                            Capsule()
                                .fill(segment.accent.map { preview.accents[$0] } ?? preview.text)
                                .frame(width: segment.width, height: 3)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(preview.canvas)
        }
        .frame(height: 64)
        .accessibilityHidden(true)
    }
}

private struct ThemeSidePicker: View {
    let title: String
    @Binding var selection: String
    let names: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            // A Custom side may name a theme that isn't bundled (a path).
            if !names.contains(selection) {
                Text(selection).tag(selection)
            }
            ForEach(names, id: \.self) { Text($0).tag($0) }
        }
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
