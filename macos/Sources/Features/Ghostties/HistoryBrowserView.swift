import SwiftUI

/// One past session as the history browser shows it. The sidebar builds
/// these from the store; the browser never reads the store itself.
struct HistoryEntry: Identifiable, Equatable {
    let id: UUID
    let projectName: String
    let title: String
    let lastActiveAt: Date
    let isArchived: Bool
    let isPinned: Bool
}

/// The terminal-style (fzf-like) history picker shown in the canvas card
/// when the sidebar's History row is selected:
///
///     history › <query>
///     12/148 ── history ─────────
///     ▌ ghostties · tray glass pass        2h  inactive
///     ↑↓ move   ⏎ resume   ⌘P pin   esc close
///
/// All filtering/selection lives in `HistoryBrowserModel`; this view only
/// renders it and routes keys through `HistoryBrowserModel.handle`.
struct HistoryBrowserView: View {
    private let entries: [HistoryEntry]
    private let actions: HistoryBrowserModel.Actions

    @State private var model: HistoryBrowserModel
    @FocusState private var isQueryFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        entries: [HistoryEntry],
        onResume: @escaping (UUID) -> Void,
        onTogglePin: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.entries = entries
        self.actions = .init(onResume: onResume, onTogglePin: onTogglePin, onClose: onClose)
        _model = State(initialValue: HistoryBrowserModel(entries: entries))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            queryLine
                .padding(.bottom, 10)
            countLine
                .padding(.bottom, 6)
            list
            footer
                .padding(.top, 10)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, Style.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Style.background(colorScheme))
        .background(keyShortcuts)
        .onChange(of: entries) { model.setEntries($0) }
    }

    // MARK: - Query line

    private var queryLine: some View {
        HStack(spacing: 0) {
            Text("history › ")
                .foregroundColor(Style.muted(colorScheme))
            TextField("", text: $model.query)
                .textFieldStyle(.plain)
                .focused($isQueryFocused)
                .onSubmit { handle(.resume) }
                .onExitCommand { handle(.close) }
                .accessibilityLabel("Search history")
        }
        .font(Style.font)
        .padding(.leading, Style.gutter)
        .onAppear {
            // Same deferral as CommandPaletteView: focusing synchronously in
            // onAppear doesn't take on current macOS.
            DispatchQueue.main.async { isQueryFocused = true }
        }
    }

    // MARK: - Count line

    private var countLine: some View {
        HStack(spacing: 8) {
            Text("\(model.shown)/\(model.total)")
            rule.frame(width: 36)
            Text("history")
            rule
        }
        .font(Style.font)
        .foregroundColor(Style.muted(colorScheme))
        .padding(.leading, Style.gutter)
    }

    private var rule: some View {
        Rectangle()
            .fill(Style.muted(colorScheme).opacity(0.5))
            .frame(height: 1)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if let empty = model.emptyState {
            Text(empty.message)
                .font(Style.font)
                .foregroundColor(Style.muted(colorScheme))
                .padding(.leading, Style.gutter)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let columns = Columns(entries: model.entries, now: Date())
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // VStack, not LazyVStack: lazy rows froze at first
                    // construction in the sidebar (#121).
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.rows) { row in
                            HistoryBrowserRow(
                                row: row,
                                columns: columns,
                                isSelected: row.id == model.selectedID,
                                colorScheme: colorScheme
                            )
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(row.id) }
                        }
                    }
                }
                .onChange(of: model.selectedID) { id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
            .padding(.horizontal, -Style.horizontalInset)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 24) {
            hint("↑↓", "move")
            hint("⏎", "resume")
            if SessionPinning.isAvailable { hint("⌘P", "pin") }
            hint("esc", "close")
        }
        .font(Style.font)
        .padding(.leading, Style.gutter)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key).fontWeight(.semibold).foregroundColor(.primary)
            Text(label).foregroundColor(Style.muted(colorScheme))
        }
    }

    // MARK: - Keys

    /// Arrow keys and ⌘P as zero-size shortcut buttons — the same pattern
    /// `CommandPaletteQuery` uses, because a focused single-line field
    /// doesn't reliably deliver up/down through `onMoveCommand`.
    private var keyShortcuts: some View {
        Group {
            Button { handle(.up) } label: { Color.clear }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button { handle(.down) } label: { Color.clear }
                .keyboardShortcut(.downArrow, modifiers: [])
            if SessionPinning.isAvailable {
                Button { handle(.togglePin) } label: { Color.clear }
                    .keyboardShortcut("p", modifiers: [.command])
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func handle(_ key: HistoryBrowserModel.Key) {
        model.handle(key, actions: actions)
    }
}

// MARK: - Row

/// Column widths in characters, measured over ALL entries (not just the
/// shown ones) so columns don't shift while the query narrows the list.
private struct Columns {
    let project: Int
    let title: Int
    let age: Int
    let now: Date

    init(entries: [HistoryEntry], now: Date) {
        project = min(entries.map(\.projectName.count).max() ?? 0, 18)
        title = min(entries.map(\.title.count).max() ?? 0, 48)
        age = max(3, entries.map { HistoryBrowserModel.age(of: $0.lastActiveAt, now: now).count }.max() ?? 0)
        self.now = now
    }
}

private struct HistoryBrowserRow: View {
    let row: HistoryBrowserModel.Row
    let columns: Columns
    let isSelected: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? Style.selectionAccent : .clear)
                .frame(width: 3, height: 15)
                .padding(.leading, Style.barInset)
                .frame(width: Style.horizontalInset, alignment: .leading)
            Group {
                if row.entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Style.muted(colorScheme))
                        .accessibilityLabel("Pinned")
                } else {
                    Color.clear
                }
            }
            .frame(width: Style.pinSlot)
            Text(line)
                .font(Style.font)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .background(isSelected ? Style.selectionFill(colorScheme) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "project, title, age, archived|inactive[, pinned]" — the padded,
    /// truncated visual line reads badly aloud.
    private var accessibilityText: String {
        let e = row.entry
        var parts = [e.projectName, e.title, HistoryBrowserModel.age(of: e.lastActiveAt, now: columns.now), e.isArchived ? "archived" : "inactive"]
        if e.isPinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }

    private var line: AttributedString {
        let e = row.entry
        var out = cell(e.projectName, width: columns.project, matches: row.projectMatches, base: .primary)
        out += plain(" · ", Style.muted(colorScheme))
        out += cell(e.title, width: columns.title, matches: row.titleMatches, base: .primary)
        let age = HistoryBrowserModel.age(of: e.lastActiveAt, now: columns.now)
        out += plain("  " + String(repeating: " ", count: max(0, columns.age - age.count)) + age + "  ", Style.muted(colorScheme))
        out += e.isArchived
            ? plain("archived", Style.archivedAmber)
            : plain("inactive", Style.muted(colorScheme))
        return out
    }

    /// A fixed-width cell: truncated with "…" past `width`, space-padded
    /// below it, matched characters emphasised.
    private func cell(_ text: String, width: Int, matches: [Int], base: Color) -> AttributedString {
        let chars = Array(text)
        let visible = chars.count > width ? Array(chars.prefix(max(0, width - 1))) + ["…"] : chars
        let hits = Set(matches)
        var out = AttributedString()
        for (i, ch) in visible.enumerated() {
            var piece = AttributedString(String(ch))
            let isHit = hits.contains(i) && !(chars.count > width && i == visible.count - 1)
            piece.foregroundColor = isHit ? Style.selectionAccent : base
            if isHit { piece.font = Style.font.weight(.semibold) }
            out += piece
        }
        out += AttributedString(String(repeating: " ", count: max(0, width - visible.count)))
        return out
    }

    private func plain(_ s: String, _ color: Color) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = color
        return a
    }
}

// MARK: - Style

private enum Style {
    /// SF Mono at Ghostty's default terminal size. The user's configured
    /// terminal font isn't reachable from a standalone view.
    static let font = Font.system(size: 13, design: .monospaced)

    static let horizontalInset: CGFloat = 24
    /// Rows put a pin slot before their text; the query/count/footer lines
    /// indent by the same amount so all text shares one left edge.
    static let pinSlot: CGFloat = 20
    static let gutter: CGFloat = pinSlot
    static let barInset: CGFloat = 12

    /// The card's own background — DESIGN.md: canvas is never bound to the
    /// terminal theme.
    static func background(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? WorkspaceLayout.canvasBackgroundDark : WorkspaceLayout.canvasBackgroundLight)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WorkspaceLayout.textSecondaryDark : WorkspaceLayout.textSecondaryLight
    }

    static func selectionFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WorkspaceLayout.activeRowDark : WorkspaceLayout.activeRowLight
    }

    /// DESIGN.md reserves terracotta, so the selection bar and match
    /// emphasis use the composer's selection accent.
    static let selectionAccent = WorkspaceLayout.composerSelectionAccent

    /// Muted amber for "archived". No WorkspaceLayout token exists yet; this
    /// view may not edit that file, so it lives here until it's promoted.
    static let archivedAmber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0xD9 / 255.0, green: 0x9A / 255.0, blue: 0x4E / 255.0, alpha: 1)
            : NSColor(red: 0xB0 / 255.0, green: 0x5F / 255.0, blue: 0x12 / 255.0, alpha: 1)
    })
}
