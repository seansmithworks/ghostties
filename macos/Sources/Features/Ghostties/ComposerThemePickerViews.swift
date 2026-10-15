import AppKit
import SwiftUI

// MARK: - Model

/// The composer theme picker's state: the parsed command, the selected
/// result, the hovered thumbnail half, and the live preview. Owned by
/// `SessionComposerStore`, so every way the composer closes reverts the
/// preview (`reset`).
@MainActor
final class ComposerThemePickerModel: ObservableObject {
    let preview: ThemePreviewController
    let families: [ThemeFamily]
    private let defaults: UserDefaults
    private let appearanceProvider: @MainActor () -> ChromeTheme.Polarity
    private let appearanceState: @MainActor (GhosttiesThemePicks) -> GhosttiesAppearanceState

    @Published private(set) var command: ComposerThemeCommand = .none
    /// Read from Settings each time the picker opens.
    @Published private(set) var presentation: ComposerThemePresentation = .grid
    @Published private(set) var selection = 0
    /// The thumbnail half (C2) or chip (C1) under the pointer, previewing
    /// instead of the selection.
    @Published private(set) var peekName: String?
    /// The family that shows right now, for the grid's checkmark. Nil for a
    /// Custom theme.
    @Published private(set) var appliedFamily: String?
    /// Explicit colour keys in the user's config beat any theme, so the
    /// picker offers nothing (Settings locks the same way).
    @Published private(set) var isLockedByConfig = false

    /// Whether the selection is shown on the window: true once the user
    /// moves, hovers or types a query. An empty `theme ` shows what is
    /// applied, so typing the word alone never changes the window.
    private var selectionIsPreviewed = false
    private var thumbnails: [String: ThemePreview] = [:]

    init(
        defaults: UserDefaults,
        families: [ThemeFamily] = GhosttiesThemeCatalog.families,
        reload: @escaping (GhosttiesThemePicks?) -> Void,
        appearance: @escaping @MainActor () -> ChromeTheme.Polarity = ComposerThemePickerModel.systemAppearance,
        appearanceState: @escaping @MainActor (GhosttiesThemePicks) -> GhosttiesAppearanceState = ComposerThemePickerModel.liveAppearanceState
    ) {
        self.defaults = defaults
        self.families = families
        self.preview = ThemePreviewController(defaults: defaults, reload: reload)
        self.appearanceProvider = appearance
        self.appearanceState = appearanceState
    }

    /// The Mac's appearance: the side a `light:X,dark:Y` pick shows.
    static func systemAppearance() -> ChromeTheme.Polarity {
        NSApplication.shared.effectiveAppearance.isDark ? .dark : .light
    }

    static func liveAppearanceState(_ picks: GhosttiesThemePicks) -> GhosttiesAppearanceState {
        GhosttiesAppearanceState.resolve(configPath: (NSApp.delegate as? AppDelegate)?.ghostty.configPath, picks: picks)
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

    var gridResults: [ThemeFamily] {
        isLockedByConfig ? [] : ComposerThemeMatcher.grid(query: query, families: families)
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
        presentation == .grid ? gridResults.count : chipResults.count
    }

    /// Return commits (vs. shakes).
    var hasSelection: Bool { isActive && resultCount > 0 }

    var isGridShown: Bool { isActive && presentation == .grid }
    /// ← / → belong to the grid only while it has something to move between.
    var claimsHorizontalArrows: Bool { isGridShown && hasSelection }
    var isChipsShown: Bool { isActive && presentation == .chips }

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
                top = gridResults[safe: selection].map { [$0.themeName(for: appearance), $0.name] } ?? []
            case .chips:
                top = chipResults[safe: selection].map { [$0.name, $0.family] } ?? []
            }
            return typed + ComposerThemeMatcher.ghostSuffix(typed: typed, query: query, topNames: top)
        }
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
        guard case .theme(let query) = command else {
            selectionIsPreviewed = false
            preview.revert()
            return
        }
        if !wasActive {
            presentation = .stored(in: defaults)
            let state = appearanceState(applied)
            isLockedByConfig = state == .setByConfig
            appliedFamily = Self.familyName(for: state, in: families)
        }
        switch presentation {
        case .grid:
            selection = ComposerThemeMatcher.initialGridIndex(query: query, results: gridResults, applied: applied)
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

    /// Return or a click: stores the selected family. False when there is
    /// nothing to commit.
    @discardableResult
    func commit() -> Bool {
        guard isActive else { return false }
        let picks: GhosttiesThemePicks
        switch presentation {
        case .grid:
            guard let family = gridResults[safe: selection] else { return false }
            picks = family.picks
        case .chips:
            guard let choice = chipResults[safe: selection],
                  let family = family(named: choice.family) else { return false }
            picks = family.picks
        }
        preview.commit(light: picks.light, dark: picks.dark)
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
        preview.revert()
    }

    private func showSelection() {
        guard selectionIsPreviewed else { return preview.revert() }
        switch presentation {
        case .grid:
            guard let family = gridResults[safe: selection] else { return preview.revert() }
            let picks = family.picks
            preview.preview(light: picks.light, dark: picks.dark)
        case .chips:
            guard let choice = chipResults[safe: selection],
                  let picks = family(named: choice.family)?.picks else { return preview.revert() }
            preview.preview(light: picks.light, dark: picks.dark)
        }
    }

    /// The Settings banner's "Open Config File": `Ghostty.App.openConfig`.
    func openConfig() {
        (NSApp.delegate as? AppDelegate)?.ghostty.openConfig()
    }

    private static func familyName(for state: GhosttiesAppearanceState, in families: [ThemeFamily]) -> String? {
        switch state {
        case .ghostties:
            return GhosttiesThemeCatalog.ghostties.name
        case .picked(let light, let dark):
            let picks = GhosttiesThemePicks(light: light, dark: dark)
            return families.first { $0.picks == picks }?.name
        case .custom, .setByConfig:
            return nil
        }
    }
}

// MARK: - Shared ink

/// Colours the picker draws, all existing tokens: the composer's selection
/// accent, the chrome's secondary ink and composer-row wash, and the
/// system separator.
private enum ComposerThemeInk {
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

/// C2: the card grows downward into a grid of light|dark thumbnails.
/// Arrow keys move in 2D; hovering a thumbnail half previews that side.
struct ComposerThemeGrid: View {
    @ObservedObject var model: ComposerThemePickerModel
    /// The card's width.
    let width: CGFloat
    let titleSize: CGFloat
    let onCommit: () -> Void

    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    static let thumbnailHeight: CGFloat = 48
    static let maxVisibleRows = 2

    /// Three columns on the default card, two on a narrow one.
    static func columns(cardWidth: CGFloat) -> Int {
        cardWidth >= 480 ? 3 : 2
    }

    private var columns: Int { Self.columns(cardWidth: width) }
    private var labelSize: CGFloat { (titleSize * 0.72).rounded() }
    private var labelHeight: CGFloat { (labelSize * 1.3).rounded(.up) }
    private var cardHeight: CGFloat { Self.inset + Self.thumbnailHeight + Self.spacing + labelHeight + Self.inset }

    private func gridHeight(count: Int) -> CGFloat {
        let rows = min(Self.maxVisibleRows, Int((Double(count) / Double(columns)).rounded(.up)))
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * cardHeight + CGFloat(rows - 1) * Self.spacing + 2 * Self.inset
    }

    var body: some View {
        let results = model.gridResults
        VStack(alignment: .leading, spacing: 0) {
            ComposerCardHairline()
                .padding(.horizontal, Self.inset + 4)
            ComposerResumeSectionHeader(
                systemImage: "paintpalette",
                title: results.count == 1 ? "1 theme" : "\(results.count) themes",
                size: titleSize * 0.62
            )
            if results.isEmpty {
                ComposerThemeStatusLine(model: model, size: labelSize)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: results.count > columns * Self.maxVisibleRows) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns),
                            spacing: Self.spacing
                        ) {
                            ForEach(Array(results.enumerated()), id: \.element.name) { index, family in
                                ComposerThemeCard(
                                    model: model,
                                    family: family,
                                    index: index,
                                    isSelected: index == model.selection,
                                    isApplied: family.name == model.appliedFamily,
                                    labelSize: labelSize,
                                    labelHeight: labelHeight,
                                    onCommit: onCommit
                                )
                                .id(family.name)
                            }
                        }
                        .padding(Self.inset)
                    }
                    .frame(height: gridHeight(count: results.count))
                    .onChange(of: model.selection) { index in
                        guard let family = results[safe: index] else { return }
                        proxy.scrollTo(family.name)
                    }
                }
                .onHover { inside in
                    if !inside { model.endHover() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Themes")
    }
}

/// One family: its light and dark thumbnails side by side, then its name.
private struct ComposerThemeCard: View {
    @ObservedObject var model: ComposerThemePickerModel
    let family: ThemeFamily
    let index: Int
    let isSelected: Bool
    let isApplied: Bool
    let labelSize: CGFloat
    let labelHeight: CGFloat
    let onCommit: () -> Void
    @ChromeScheme private var colorScheme

    private var sides: [String] { [family.light, family.dark].compactMap { $0 } }
    private var isPair: Bool { family.light != nil && family.dark != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: ComposerThemeGrid.spacing) {
            HStack(spacing: 0) {
                ForEach(sides, id: \.self) { name in
                    ComposerThemeHalf(preview: model.thumbnail(name), isPeeked: isPair && model.peekName == name)
                        .onHover { inside in
                            guard isPair else { return }
                            if inside {
                                if model.selection != index { model.select(index) }
                                model.peek(name)
                            } else if model.peekName == name {
                                model.peek(nil)
                            }
                        }
                }
            }
            .frame(height: ComposerThemeGrid.thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 4) {
                Text(family.name)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if isApplied {
                    Image(systemName: "checkmark")
                        .font(.system(size: labelSize * 0.8, weight: .semibold))
                        .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
                }
                Spacer(minLength: 4)
                if !isPair {
                    Text(family.light != nil ? "light" : "dark")
                        .font(.system(size: labelSize * 0.9))
                        .foregroundStyle(ComposerThemeInk.secondary(colorScheme))
                }
            }
            .frame(height: labelHeight)
            .padding(.horizontal, 4)
        }
        .padding(ComposerThemeGrid.inset)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? ComposerThemeInk.selection.opacity(0.10) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? ComposerThemeInk.selection : ComposerThemeInk.hairline, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in
            if inside, model.selection != index || model.peekName != nil { model.select(index) }
        }
        .onTapGesture {
            if model.commit(at: index) { onCommit() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction(.default) { if model.commit(at: index) { onCommit() } }
    }

    private var accessibilityLabel: String {
        var label = family.name
        if !isPair { label += family.light != nil ? ", light only" : ", dark only" }
        if isApplied { label += ", applied" }
        return label
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
