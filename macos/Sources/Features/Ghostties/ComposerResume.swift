import SwiftUI
import GhosttiesCore

// MARK: - Layout dial

/// How the Cmd+T composer offers past sessions (sidebar vnext, 2026-10-08:
/// History left the sidebar and lives in the composer).
enum ComposerResumeLayout: String, CaseIterable {
    /// A5, the default: the composer stays one line; ↓ reveals the Resume
    /// list under the field, ↑ from its top row or Esc collapses it.
    case list
    /// A4: a two-column composer, start | resume, always open. → from the
    /// end of the field crosses into the resume column, ← crosses back.
    case columns

    static let storageKey = "ghostties.composerResumeLayout"

    static func current(defaults: UserDefaults = .standard) -> ComposerResumeLayout {
        defaults.string(forKey: storageKey).flatMap(ComposerResumeLayout.init(rawValue:)) ?? .list
    }
}

// MARK: - Rows

/// The composer's resume rows: every inactive and archived session (the
/// set the sidebar's History row stood for), newest first, filtered by the
/// typed text with the history browser's own matcher.
enum ComposerResumeRows {
    static func rows(entries: [HistoryEntry], query: String) -> [HistoryEntry] {
        var model = HistoryBrowserModel(entries: entries)
        model.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.rows.map(\.entry)
    }

    /// The trailing meta on a resume row: "atlas-api · 2h". Ages read like
    /// the sidebar's ("5m", "2h", "3d", "2w"), except one day reads
    /// "yesterday".
    static func meta(projectName: String, lastActiveAt: Date, now: Date = .now) -> String {
        "\(projectName) · \(age(lastActiveAt, now: now))"
    }

    static func age(_ date: Date, now: Date = .now) -> String {
        guard date != .distantPast else { return "—" }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "now" }
        let days = Int(elapsed / 86_400)
        if days == 1 { return "yesterday" }
        return HistorySummary.ago(date, now: now)
    }

    /// The rows visible in a list capped at `cap`, scrolled so `selected`
    /// stays in view.
    static func window(count: Int, selected: Int?, cap: Int) -> Range<Int> {
        guard count > cap else { return 0..<count }
        let selected = selected ?? 0
        let start = min(max(0, selected - cap + 1), count - cap)
        return start..<(start + cap)
    }
}

// MARK: - Down list (A5)

/// A5's ↓ list holds three sections, RESUME (past sessions), TEMPLATES
/// (the current project's start options), then PROJECTS (every project,
/// so a project is reachable by typing its name), and ↓/↑ walk them as one
/// list. An empty section is omitted; with all empty, RESUME stays as the
/// empty-state holder ("No past sessions" / "No matches").
///
/// Sections never scroll on their own (Sean, 2026-10-08): each shows its
/// first `collapsedRowCap` rows, then a "Show N more" row that expands it
/// in place. The whole list scrolls as one.
enum ComposerDownList {
    enum Section: Hashable, CaseIterable { case resume, templates, projects }

    /// One line of the ↓ list, in on-screen order.
    enum Item: Equatable {
        case header(Section)
        case row(Section, UUID)
        /// "Show N more": a real list row with its own id.
        case showMore(Section, hidden: Int)

        /// The id ↓/↑ land on; headers have none.
        var keyboardID: UUID? {
            switch self {
            case .header: return nil
            case .row(_, let id): return id
            case .showMore(let section, _): return ComposerDownList.showMoreID(for: section)
            }
        }
    }

    static let templatesSymbol = "rectangle.stack"
    static let projectsSymbol = "folder"

    static func sections(resumeCount: Int, templateCount: Int, projectCount: Int = 0) -> [Section] {
        var sections: [Section] = []
        if resumeCount > 0 { sections.append(.resume) }
        if templateCount > 0 { sections.append(.templates) }
        if projectCount > 0 { sections.append(.projects) }
        return sections.isEmpty ? [.resume] : sections
    }

    /// Rows a collapsed section shows before its "Show N more" row.
    static let collapsedRowCap = 3

    /// Fixed per section, so a "Show N more" row keeps its identity (and
    /// its highlight) across keystrokes. Never collides with a session,
    /// template or project id, which are random.
    static func showMoreID(for section: Section) -> UUID {
        switch section {
        case .resume: return UUID(uuidString: "5D0E0000-0000-4000-8000-000000000001")!
        case .templates: return UUID(uuidString: "5D0E0000-0000-4000-8000-000000000002")!
        case .projects: return UUID(uuidString: "5D0E0000-0000-4000-8000-000000000003")!
        }
    }

    static func showMoreSection(for id: UUID) -> Section? {
        Section.allCases.first { showMoreID(for: $0) == id }
    }

    /// The list's lines: each non-empty section's header, its first
    /// `collapsedRowCap` rows (all of them once expanded), then "Show N
    /// more" when rows are still hidden. With every section empty, the
    /// RESUME header alone (the view adds the empty-state text).
    static func items(resume: [UUID], templates: [UUID], projects: [UUID], expanded: Set<Section>) -> [Item] {
        let all: [(Section, [UUID])] = [(.resume, resume), (.templates, templates), (.projects, projects)]
        var items: [Item] = []
        for (section, ids) in all where !ids.isEmpty {
            items.append(.header(section))
            let shown = expanded.contains(section) ? ids : Array(ids.prefix(collapsedRowCap))
            items += shown.map { .row(section, $0) }
            if shown.count < ids.count {
                items.append(.showMore(section, hidden: ids.count - shown.count))
            }
        }
        return items.isEmpty ? [.header(.resume)] : items
    }

    /// The order ↓/↑ walk: every row and "Show N more" row, top to bottom.
    static func keyboardIDs(_ items: [Item]) -> [UUID] {
        items.compactMap(\.keyboardID)
    }

    /// The row "Show N more" reveals first — where the highlight lands.
    static func firstRevealed(in ids: [UUID]) -> UUID? {
        ids.count > collapsedRowCap ? ids[collapsedRowCap] : nil
    }

    /// VoiceOver's name for a "Show N more" row.
    static func showMoreAccessibilityLabel(section: Section, hidden: Int) -> String {
        let noun: String
        switch section {
        case .resume: noun = "past sessions"
        case .templates: noun = "templates"
        case .projects: noun = "projects"
        }
        return "Show \(hidden) more \(noun)"
    }
}

/// One TEMPLATES or PROJECTS row in the ↓ list: what it shows and what
/// Return/click runs (the composer option's own action — start that
/// template, or select that project).
struct ComposerTemplateRow: Identifiable {
    let id: UUID
    let systemImage: String
    let title: String
    let meta: String?
    let action: () -> Void
}

// MARK: - Keyboard state

/// The resume half of the composer's keyboard model, free of SwiftUI so
/// every transition is unit-testable. The composer feeds it each key first;
/// `.passThrough` hands the key back to the composer's own start handling.
struct ComposerResumeState: Equatable {
    enum Key: Equatable { case up, down, left, right, submit, exit }

    enum Outcome: Equatable {
        /// Not a resume key in this state — the composer handles it.
        case passThrough
        case handled
        /// Resume this session through the existing relaunch flow.
        case resume(UUID)
    }

    /// A5: the Resume list is showing under the field.
    private(set) var isRevealed = false
    /// A4: the resume column holds the keyboard.
    private(set) var isResumeColumnFocused = false
    /// The highlighted resume row. Re-anchors to the first row when it no
    /// longer matches the typed text.
    private(set) var selectedID: UUID?
    /// A5 sections expanded past their first rows by "Show N more".
    /// Cleared on open (`reset`) and whenever the typed text changes.
    private(set) var expandedSections: Set<ComposerDownList.Section> = []

    /// Whether resume rows (rather than the start options) own Return.
    var ownsKeyboard: Bool { isRevealed || isResumeColumnFocused }

    func selection(in rowIDs: [UUID]) -> UUID? {
        if let selectedID, rowIDs.contains(selectedID) { return selectedID }
        return rowIDs.first
    }

    mutating func reset() {
        self = ComposerResumeState()
    }

    mutating func select(_ id: UUID) {
        selectedID = id
    }

    /// "Show N more": expands `section` in place and highlights the first
    /// row it revealed.
    mutating func expand(_ section: ComposerDownList.Section, selecting firstRevealed: UUID?) {
        expandedSections.insert(section)
        if let firstRevealed { selectedID = firstRevealed }
    }

    mutating func collapseSections() {
        expandedSections = []
    }

    mutating func handle(_ key: Key, layout: ComposerResumeLayout, rowIDs: [UUID]) -> Outcome {
        switch layout {
        case .list: return handleList(key, rowIDs: rowIDs)
        case .columns: return handleColumns(key, rowIDs: rowIDs)
        }
    }

    private mutating func handleList(_ key: Key, rowIDs: [UUID]) -> Outcome {
        guard isRevealed else {
            guard key == .down else { return .passThrough }
            isRevealed = true
            selectedID = rowIDs.first
            return .handled
        }
        switch key {
        case .down:
            move(by: 1, in: rowIDs)
            return .handled
        case .up:
            if index(in: rowIDs) ?? 0 == 0 {
                isRevealed = false
            } else {
                move(by: -1, in: rowIDs)
            }
            return .handled
        case .exit:
            isRevealed = false
            return .handled
        case .submit:
            guard let id = selection(in: rowIDs) else { return .passThrough }
            return .resume(id)
        case .left, .right:
            return .passThrough
        }
    }

    private mutating func handleColumns(_ key: Key, rowIDs: [UUID]) -> Outcome {
        guard isResumeColumnFocused else {
            guard key == .right, !rowIDs.isEmpty else { return .passThrough }
            isResumeColumnFocused = true
            selectedID = selection(in: rowIDs)
            return .handled
        }
        switch key {
        case .down:
            move(by: 1, in: rowIDs)
            return .handled
        case .up:
            move(by: -1, in: rowIDs)
            return .handled
        case .left:
            isResumeColumnFocused = false
            return .handled
        case .right:
            return .handled
        case .submit:
            guard let id = selection(in: rowIDs) else {
                isResumeColumnFocused = false
                return .passThrough
            }
            return .resume(id)
        case .exit:
            return .passThrough
        }
    }

    private func index(in rowIDs: [UUID]) -> Int? {
        selection(in: rowIDs).flatMap { rowIDs.firstIndex(of: $0) }
    }

    /// Clamps at both ends, like the history browser.
    private mutating func move(by delta: Int, in rowIDs: [UUID]) {
        guard !rowIDs.isEmpty else { selectedID = nil; return }
        let next = min(max((index(in: rowIDs) ?? 0) + delta, 0), rowIDs.count - 1)
        selectedID = rowIDs[next]
    }
}

// MARK: - Views

/// Colours shared by the composer's resume surfaces.
private enum ComposerResumeInk {
    static func secondary(_ scheme: ColorScheme) -> Color {
        WorkspaceLayout.sectionHeaderForeground(for: scheme)
    }

    static func selectedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WorkspaceLayout.composerRowSelectedDark : WorkspaceLayout.composerRowSelectedLight
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
    }
}

/// A small-caps section label: "RESUME", "START IN ATLAS-API".
struct ComposerResumeSectionHeader: View {
    let systemImage: String
    let title: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.9, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: size, weight: .semibold))
                .tracking(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One composer row: leading icon, title, trailing meta, and a return glyph
/// on the highlighted row. Used by both the resume rows and A4's start
/// column.
struct ComposerListRow: View {
    let systemImage: String
    let title: String
    let meta: String?
    let isSelected: Bool
    let showsReturnGlyph: Bool
    let titleSize: CGFloat
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: titleSize * 0.8, weight: .regular))
                .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
                .frame(width: titleSize, alignment: .center)
            Text(title)
                .font(.system(size: titleSize, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let meta {
                Text(meta)
                    .font(.system(size: titleSize * 0.75, weight: .medium))
                    .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
                    .lineLimit(1)
            }
            if showsReturnGlyph && isSelected {
                Image(systemName: "return")
                    .font(.system(size: titleSize * 0.7, weight: .medium))
                    .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: titleSize + 24)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? ComposerResumeInk.selectedFill(colorScheme) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A4's resume column: the Resume rows, scrolled within `cap` so the
/// highlighted one stays in view.
struct ComposerResumeListView: View {
    let rows: [HistoryEntry]
    let selectedID: UUID?
    let isFocused: Bool
    let hasHistory: Bool
    let cap: Int
    let titleSize: CGFloat
    let now: Date
    let onResume: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerResumeSectionHeader(systemImage: "clock.arrow.circlepath", title: "Resume", size: titleSize * 0.62)
            if rows.isEmpty {
                ComposerResumeEmptyText(hasHistory: hasHistory, titleSize: titleSize)
            } else {
                let selectedIndex = selectedID.flatMap { id in rows.firstIndex { $0.id == id } }
                ForEach(rows[ComposerResumeRows.window(count: rows.count, selected: selectedIndex, cap: cap)]) { entry in
                    ComposerResumeEntryRow(entry: entry, isSelected: isFocused && entry.id == selectedID,
                                           titleSize: titleSize, now: now, onResume: onResume)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ComposerDownListView.accessibilityLabel(hasTemplates: false))
    }
}

/// A5's ↓ list: RESUME, TEMPLATES, PROJECTS as one list
/// (`ComposerDownList.items`). Sections never scroll on their own; past
/// `maxHeight` the whole list scrolls, keeping the highlighted row in view.
struct ComposerDownListView: View {
    let rows: [HistoryEntry]
    let templates: [ComposerTemplateRow]
    let projects: [ComposerTemplateRow]
    let expanded: Set<ComposerDownList.Section>
    let selectedID: UUID?
    let hasHistory: Bool
    let titleSize: CGFloat
    let maxHeight: CGFloat
    let now: Date
    let onResume: (UUID) -> Void
    let onShowMore: (ComposerDownList.Section) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 0

    /// The list's VoiceOver name: it holds TEMPLATES too whenever any show.
    static func accessibilityLabel(hasTemplates: Bool) -> String {
        hasTemplates ? "Resume or start a session" : "Resume a past session"
    }

    /// The tallest the list grows before it scrolls: the old two-section
    /// list's full height (two headers, three rows each).
    static func maxHeight(titleSize: CGFloat) -> CGFloat {
        let row = titleSize + 24
        let header = (titleSize * 0.62 * 1.25).rounded(.up) + 12
        return 6 * row + 2 * header
    }

    var body: some View {
        let items = ComposerDownList.items(
            resume: rows.map(\.id), templates: templates.map(\.id), projects: projects.map(\.id), expanded: expanded
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: contentHeight > maxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        line(item)
                    }
                    if rows.isEmpty, templates.isEmpty, projects.isEmpty {
                        ComposerResumeEmptyText(hasHistory: hasHistory, titleSize: titleSize)
                    }
                }
                .background(GeometryReader { geo in
                    // Preferences don't leave an AppKit-backed ScrollView,
                    // so the content height is written straight to state.
                    Color.clear
                        .onAppear { contentHeight = geo.size.height }
                        .onChange(of: geo.size.height) { contentHeight = $0 }
                })
            }
            .frame(height: min(contentHeight, maxHeight))
            .onChange(of: selectedID) { id in
                guard let id, let index = items.firstIndex(where: { $0.keyboardID == id }) else { return }
                // A section's first row brings its header into view with it.
                if index > 0, case .header(let section) = items[index - 1] {
                    proxy.scrollTo(Self.headerID(section))
                } else {
                    proxy.scrollTo(id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel(hasTemplates: !templates.isEmpty))
    }

    private static func headerID(_ section: ComposerDownList.Section) -> String {
        "header-\(section)"
    }

    @ViewBuilder
    private func line(_ item: ComposerDownList.Item) -> some View {
        switch item {
        case .header(.resume):
            ComposerResumeSectionHeader(systemImage: "clock.arrow.circlepath", title: "Resume", size: titleSize * 0.62)
                .id(Self.headerID(.resume))
        case .header(.templates):
            ComposerResumeSectionHeader(systemImage: ComposerDownList.templatesSymbol, title: "Templates", size: titleSize * 0.62)
                .id(Self.headerID(.templates))
        case .header(.projects):
            ComposerResumeSectionHeader(systemImage: ComposerDownList.projectsSymbol, title: "Projects", size: titleSize * 0.62)
                .id(Self.headerID(.projects))
        case .row(.resume, let id):
            if let entry = rows.first(where: { $0.id == id }) {
                ComposerResumeEntryRow(entry: entry, isSelected: id == selectedID, titleSize: titleSize, now: now, onResume: onResume)
                    .id(id)
            }
        case .row(let section, let id):
            if let row = (section == .templates ? templates : projects).first(where: { $0.id == id }) {
                ComposerListRow(
                    systemImage: row.systemImage, title: row.title, meta: row.meta,
                    isSelected: id == selectedID, showsReturnGlyph: true, titleSize: titleSize, action: row.action
                )
                .id(id)
            }
        case .showMore(let section, let hidden):
            ComposerShowMoreRow(
                hidden: hidden,
                accessibilityLabel: ComposerDownList.showMoreAccessibilityLabel(section: section, hidden: hidden),
                isSelected: ComposerDownList.showMoreID(for: section) == selectedID,
                titleSize: titleSize,
                action: { onShowMore(section) }
            )
            .id(ComposerDownList.showMoreID(for: section))
        }
    }
}

/// "Show N more": a secondary-ink row at the end of a collapsed section.
/// Return or a click expands the section in place.
struct ComposerShowMoreRow: View {
    let hidden: Int
    let accessibilityLabel: String
    let isSelected: Bool
    let titleSize: CGFloat
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.down")
                .font(.system(size: titleSize * 0.7, weight: .medium))
                .frame(width: titleSize, alignment: .center)
            Text("Show \(hidden) more")
                .font(.system(size: titleSize * 0.8, weight: .regular))
                .lineLimit(1)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: titleSize * 0.7, weight: .medium))
            }
        }
        .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
        .padding(.horizontal, 12)
        .frame(height: titleSize + 24)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? ComposerResumeInk.selectedFill(colorScheme) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction(.default) { action() }
    }
}

/// One past session as a composer row.
private struct ComposerResumeEntryRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let titleSize: CGFloat
    let now: Date
    let onResume: (UUID) -> Void

    var body: some View {
        ComposerListRow(
            systemImage: "clock.arrow.circlepath",
            title: entry.title,
            meta: ComposerResumeRows.meta(projectName: entry.projectName, lastActiveAt: entry.lastActiveAt, now: now),
            isSelected: isSelected,
            showsReturnGlyph: true,
            titleSize: titleSize,
            action: { onResume(entry.id) }
        )
    }
}

/// RESUME's empty state: "No past sessions" / "No matches".
private struct ComposerResumeEmptyText: View {
    let hasHistory: Bool
    let titleSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(hasHistory ? "No matches" : "No past sessions")
            .font(.system(size: titleSize * 0.8))
            .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
            .padding(.horizontal, 12)
            .frame(height: titleSize + 24, alignment: .leading)
    }
}

/// A5's resting hint at the field's trailing edge: the most recent past
/// session and a ↓ key cap — "↓ opens the list".
struct ComposerResumeHint: View {
    let entry: HistoryEntry
    let size: CGFloat
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: size * 0.9, weight: .medium))
            Text("\(entry.title) · \(ComposerResumeRows.age(entry.lastActiveAt, now: now))")
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.8, weight: .semibold))
                .frame(width: size + 6, height: size + 6)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ComposerResumeInk.selectedFill(colorScheme)))
        }
        .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(ComposerResumeInk.selectedFill(colorScheme)))
        .frame(maxWidth: 260, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(entry.title), press down arrow for past sessions")
    }
}

/// A4's footer legend: key caps and what they do.
struct ComposerKeyLegend: View {
    let items: [(key: String, label: String)]
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(items[index].key)
                        .font(.system(size: size, weight: .medium))
                        .padding(.horizontal, 5)
                        .frame(minWidth: size + 10, minHeight: size + 8)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ComposerResumeInk.selectedFill(colorScheme)))
                    Text(items[index].label)
                        .font(.system(size: size))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A full-bleed 1pt separator inside the composer card.
struct ComposerCardHairline: View {
    var vertical = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(ComposerResumeInk.hairline(colorScheme))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

extension ComposerResumeState.Key {
    /// The composer field's key events, as resume keys. Tab-accept isn't one.
    init?(_ event: ComposerGhostTextField.KeyboardEvent) {
        switch event {
        case .exit: self = .exit
        case .submit, .submitNoMatch: self = .submit
        case .move(.up): self = .up
        case .move(.down): self = .down
        case .move(.left): self = .left
        case .move(.right): self = .right
        case .move: return nil
        case .acceptedGhost: return nil
        }
    }
}
