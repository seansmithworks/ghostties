import Foundation

/// Filtering, ordering and selection for `HistoryBrowserView`, kept free of
/// SwiftUI so every behaviour is unit-testable.
///
/// - Order: `lastActiveAt` descending, always — filtering narrows the list,
///   it never re-ranks it, so a row doesn't jump while you type.
/// - Selection clamps at both ends (no wrap), like fzf.
/// - When the filter changes, the selected entry stays selected if it still
///   matches; otherwise selection re-anchors to the first match.
struct HistoryBrowserModel {

    /// A filtered row: the entry plus the character offsets the query matched
    /// in its project name and title, for emphasis.
    struct Row: Equatable, Identifiable {
        let entry: HistoryEntry
        let projectMatches: [Int]
        let titleMatches: [Int]
        var id: UUID { entry.id }
    }

    enum EmptyState: Equatable {
        /// There is no history at all.
        case noPastSessions
        /// There is history, but nothing matches the query.
        case noMatches

        var message: String {
            switch self {
            case .noPastSessions: return "No past sessions"
            case .noMatches: return "No matches"
            }
        }
    }

    /// The keys the browser responds to.
    enum Key: Equatable {
        case up, down, resume, togglePin, close
    }

    /// The browser's outward callbacks, in one place so `handle(_:actions:)`
    /// is the single key → callback mapping the view and the tests share.
    struct Actions {
        let onResume: (UUID) -> Void
        let onTogglePin: (UUID) -> Void
        let onClose: () -> Void
    }

    private(set) var entries: [HistoryEntry]
    private(set) var rows: [Row] = []
    private(set) var selectedID: UUID?

    var query: String = "" {
        didSet { if query != oldValue { refilter() } }
    }

    init(entries: [HistoryEntry]) {
        self.entries = Self.sorted(entries)
        refilter()
    }

    /// Replaces the entries (e.g. after a pin toggle upstream) while keeping
    /// the query and, where it still matches, the selection.
    mutating func setEntries(_ newEntries: [HistoryEntry]) {
        entries = Self.sorted(newEntries)
        refilter()
    }

    var total: Int { entries.count }
    var shown: Int { rows.count }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return rows.firstIndex { $0.id == selectedID }
    }

    var emptyState: EmptyState? {
        if entries.isEmpty { return .noPastSessions }
        if rows.isEmpty { return .noMatches }
        return nil
    }

    /// Moves the selection by `delta` rows, clamping at the first and last row.
    mutating func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { selectedID = nil; return }
        let current = selectedIndex ?? 0
        let next = min(max(current + delta, 0), rows.count - 1)
        selectedID = rows[next].id
    }

    /// Selects a row directly (mouse click). Ignored if `id` isn't shown.
    mutating func select(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Applies one key. Resume and pin act on the selected entry and do
    /// nothing when nothing is selected; close always fires.
    mutating func handle(_ key: Key, actions: Actions) {
        switch key {
        case .up: moveSelection(by: -1)
        case .down: moveSelection(by: 1)
        case .resume: if let selectedID { actions.onResume(selectedID) }
        case .togglePin: if let selectedID { actions.onTogglePin(selectedID) }
        case .close: actions.onClose()
        }
    }

    // MARK: - Filtering

    private mutating func refilter() {
        rows = entries.compactMap { entry in
            guard let m = Self.match(query: query, project: entry.projectName, title: entry.title) else { return nil }
            return Row(entry: entry, projectMatches: m.project, titleMatches: m.title)
        }
        if let selectedID, rows.contains(where: { $0.id == selectedID }) { return }
        selectedID = rows.first?.id
    }

    private static func sorted(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.enumerated()
            .sorted { a, b in
                a.element.lastActiveAt != b.element.lastActiveAt
                    ? a.element.lastActiveAt > b.element.lastActiveAt
                    : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Case-insensitive fuzzy match of `query` against an entry's project
    /// and title. Whitespace splits the query into terms that must ALL
    /// match (fzf's AND). Each term prefers a contiguous run in the project,
    /// then in the title; failing that it matches as an in-order subsequence
    /// across project-then-title, so "ghtray" finds "ghostties · tray glass".
    /// Returns the matched character offsets per field, or nil for no match.
    /// An empty query matches everything with no emphasis.
    static func match(query: String, project: String, title: String) -> (project: [Int], title: [Int])? {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map { Array($0) }
        if terms.isEmpty { return ([], []) }

        let p = project.map { Character($0.lowercased()) }
        let t = title.map { Character($0.lowercased()) }
        var pHits = Set<Int>(), tHits = Set<Int>()

        for term in terms {
            if let r = contiguous(term, in: p) {
                pHits.formUnion(r)
            } else if let r = contiguous(term, in: t) {
                tHits.formUnion(r)
            } else if let hits = subsequence(term, in: p + t) {
                for i in hits {
                    if i < p.count { pHits.insert(i) } else { tHits.insert(i - p.count) }
                }
            } else {
                return nil
            }
        }
        return (pHits.sorted(), tHits.sorted())
    }

    private static func contiguous(_ term: [Character], in haystack: [Character]) -> Range<Int>? {
        guard !term.isEmpty, term.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - term.count) where Array(haystack[start..<start + term.count]) == term {
            return start..<start + term.count
        }
        return nil
    }

    private static func subsequence(_ term: [Character], in haystack: [Character]) -> [Int]? {
        var hits: [Int] = []
        var i = 0
        for ch in term {
            while i < haystack.count, haystack[i] != ch { i += 1 }
            guard i < haystack.count else { return nil }
            hits.append(i)
            i += 1
        }
        return hits
    }

    // MARK: - Age

    /// Compact terminal-style age: `now`, `5m`, `2h`, `3d`, `2w`, `4mo`, `1y`.
    static func age(of date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        let minute = 60.0, hour = 3600.0, day = 86400.0
        switch s {
        case ..<minute: return "now"
        case ..<hour: return "\(Int(s / minute))m"
        case ..<day: return "\(Int(s / hour))h"
        case ..<(7 * day): return "\(Int(s / day))d"
        case ..<(30 * day): return "\(Int(s / (7 * day)))w"
        case ..<(365 * day): return "\(Int(s / (30 * day)))mo"
        default: return "\(Int(s / (365 * day)))y"
        }
    }
}
