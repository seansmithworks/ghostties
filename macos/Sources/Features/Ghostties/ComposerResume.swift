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

/// A5's ↓ list holds two sections, RESUME (past sessions) then TEMPLATES
/// (the current project's start options), and ↓/↑ walk them as one list.
/// An empty section is omitted; with both empty, RESUME stays as the
/// empty-state holder ("No past sessions" / "No matches").
enum ComposerDownList {
    enum Section: Equatable { case resume, templates }

    static let templatesSymbol = "rectangle.stack"

    static func sections(resumeCount: Int, templateCount: Int) -> [Section] {
        var sections: [Section] = []
        if resumeCount > 0 { sections.append(.resume) }
        if templateCount > 0 { sections.append(.templates) }
        return sections.isEmpty ? [.resume] : sections
    }

    /// Visible rows per section: a lone section shows `soloCap`; with both
    /// showing, each scrolls within `sharedCap` so the list stays short
    /// enough to hang under a centred field.
    static func cap(sectionCount: Int, soloCap: Int = 5, sharedCap: Int = 3) -> Int {
        sectionCount > 1 ? sharedCap : soloCap
    }

    /// The keyboard order: every resume row, then every template row.
    static func rowIDs(resume: [UUID], templates: [UUID]) -> [UUID] {
        resume + templates
    }
}

/// One TEMPLATES row in the ↓ list: what it shows and what Return/click
/// runs (the composer's own start action for that template).
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

/// The Resume rows under the field (A5) or in the right column (A4). A5
/// also passes `templates`, which follow as a TEMPLATES section.
struct ComposerResumeListView: View {
    let rows: [HistoryEntry]
    var templates: [ComposerTemplateRow] = []
    let selectedID: UUID?
    let isFocused: Bool
    let hasHistory: Bool
    let cap: Int
    let titleSize: CGFloat
    let now: Date
    let onResume: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    static let accessibilityLabel = "Resume a past session"

    var body: some View {
        let sections = ComposerDownList.sections(resumeCount: rows.count, templateCount: templates.count)
        let sectionCap = ComposerDownList.cap(sectionCount: sections.count, soloCap: cap)
        VStack(alignment: .leading, spacing: 0) {
            if sections.contains(.resume) {
                ComposerResumeSectionHeader(systemImage: "clock.arrow.circlepath", title: "Resume", size: titleSize * 0.62)
            }
            if rows.isEmpty, sections.contains(.resume) {
                Text(hasHistory ? "No matches" : "No past sessions")
                    .font(.system(size: titleSize * 0.8))
                    .foregroundStyle(ComposerResumeInk.secondary(colorScheme))
                    .padding(.horizontal, 12)
                    .frame(height: titleSize + 24, alignment: .leading)
            } else if !rows.isEmpty {
                let selectedIndex = selectedID.flatMap { id in rows.firstIndex { $0.id == id } }
                ForEach(rows[ComposerResumeRows.window(count: rows.count, selected: selectedIndex, cap: sectionCap)]) { entry in
                    ComposerListRow(
                        systemImage: "clock.arrow.circlepath",
                        title: entry.title,
                        meta: ComposerResumeRows.meta(projectName: entry.projectName, lastActiveAt: entry.lastActiveAt, now: now),
                        isSelected: isFocused && entry.id == selectedID,
                        showsReturnGlyph: true,
                        titleSize: titleSize,
                        action: { onResume(entry.id) }
                    )
                }
            }
            if sections.contains(.templates) {
                ComposerResumeSectionHeader(systemImage: ComposerDownList.templatesSymbol, title: "Templates", size: titleSize * 0.62)
                let selectedIndex = selectedID.flatMap { id in templates.firstIndex { $0.id == id } }
                ForEach(templates[ComposerResumeRows.window(count: templates.count, selected: selectedIndex, cap: sectionCap)]) { row in
                    ComposerListRow(
                        systemImage: row.systemImage,
                        title: row.title,
                        meta: row.meta,
                        isSelected: isFocused && row.id == selectedID,
                        showsReturnGlyph: true,
                        titleSize: titleSize,
                        action: row.action
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel)
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
