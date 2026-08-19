import Foundation

/// Pure, testable relevance ranking + project ordering for the session
/// composer (Phase 2 of session-creation-unified). Neither type touches
/// SwiftUI or `@MainActor` state — they are plain functions over value
/// types so the ship-gate behaviors that CAN be unit tested (gates 3 and 4)
/// have real coverage.
enum SessionComposerRanking {

    /// Relevance tiers, best match first. `CommandPalette`'s inherited
    /// `filteredOptions` only ever does a boolean match + color scoring —
    /// this replaces that with an ordering where an exact prefix match
    /// always outranks a substring match, which always outranks an
    /// initials match (e.g. "cc" -> "Claude Code"). Color scoring is
    /// dropped entirely for this surface (D11 in the plan).
    enum MatchTier: Int, Comparable {
        case exactPrefix
        case substring
        case initials

        static func < (lhs: MatchTier, rhs: MatchTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Returns the best tier `title` (or, failing that, `subtitle`) matches
    /// `query` at, or `nil` if neither matches. Upstream `CommandPaletteView`
    /// matches title OR subtitle (`CommandPalette.swift:78-79`) — without
    /// this a template's command/description isn't searchable. Reuses
    /// `String.matchedIndices(for:)` (`CommandPalette.swift`, module-scope)
    /// for the substring/initials fallback so highlighting stays consistent
    /// with the inherited row rendering.
    static func matchTier(title: String, subtitle: String? = nil, query: String) -> MatchTier? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let titleTier = rawMatchTier(for: title, query: query)
        let subtitleTier = subtitle.flatMap { rawMatchTier(for: $0, query: query) }

        switch (titleTier, subtitleTier) {
        case let (t?, s?): return min(t, s)
        case let (t?, nil): return t
        case let (nil, s?): return s
        case (nil, nil): return nil
        }
    }

    private static func rawMatchTier(for text: String, query: String) -> MatchTier? {
        if text.range(of: query, options: [.caseInsensitive, .anchored]) != nil {
            return .exactPrefix
        }
        if text.range(of: query, options: .caseInsensitive) != nil {
            return .substring
        }
        // At this point there's no substring match, so a non-nil result
        // from matchedIndices(for:) can only have come from its initials
        // fallback.
        if text.matchedIndices(for: query) != nil {
            return .initials
        }
        return nil
    }

    /// Filters `items` to those matching `query` (by `title` or `subtitle`)
    /// and sorts by match tier, preserving each item's original relative
    /// order within its tier (a stable partition, not a full sort). When
    /// `query` is blank, returns `items` unfiltered and unreordered.
    static func sorted<T>(
        _ items: [T],
        query: String,
        title: (T) -> String,
        subtitle: (T) -> String? = { _ in nil }
    ) -> [T] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }

        let ranked: [(offset: Int, tier: MatchTier, item: T)] = items.enumerated().compactMap { offset, item in
            guard let tier = matchTier(title: title(item), subtitle: subtitle(item), query: query) else { return nil }
            return (offset, tier, item)
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                return lhs.offset < rhs.offset
            }
            .map { $0.item }
    }
}

/// The three-tier project dropdown ordering (locked decision, no visible
/// section headers): cascade pick first (if present in `projects`), then
/// recently-used most-recent-first, then everything else alphabetically.
enum SessionComposerProjectOrdering {
    static func order(
        projects: [Project],
        cascadePick: UUID?,
        recentProjectIds: [UUID]
    ) -> [Project] {
        var seen = Set<UUID>()
        var result: [Project] = []

        if let cascadePick, let match = projects.first(where: { $0.id == cascadePick }) {
            result.append(match)
            seen.insert(match.id)
        }

        for id in recentProjectIds where !seen.contains(id) {
            guard let match = projects.first(where: { $0.id == id }) else { continue }
            result.append(match)
            seen.insert(match.id)
        }

        let remaining = projects
            .filter { !seen.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.append(contentsOf: remaining)

        return result
    }
}
