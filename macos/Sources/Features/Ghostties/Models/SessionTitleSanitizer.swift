import Foundation

/// Turns a raw terminal-title string (as set by OSC escape sequences, e.g. by
/// Claude Code while it works) into a candidate sidebar session name — or
/// rejects it outright.
///
/// Pure, stateless, and side-effect free by design so it can be unit tested
/// without any SwiftUI/AppKit/Combine plumbing. Callers (`SessionCoordinator`)
/// own the throttling and pin-checking; this type only answers "is this title
/// usable as a name, and if so what does it look like sanitized."
enum SessionTitleSanitizer {

    /// Ceiling on sanitized name length. The sidebar row renders at ~12pt in a
    /// column clamped between 180–480pt wide — 40 characters comfortably fits
    /// without truncation ellipsis at typical widths.
    static let maxLength = 40

    /// Bare shell/program names that show up as terminal titles but carry no
    /// information about what the session is doing.
    private static let bareProgramNames: Set<String> = [
        "claude", "zsh", "bash", "-zsh", "-bash", "sh", "-sh", "fish", "-fish"
    ]

    /// Returns a sanitized name to write, or `nil` if nothing should be written —
    /// either because the title isn't usable, or because the sanitized result
    /// is identical to `currentName` (a no-op write).
    ///
    /// - Parameters:
    ///   - title: the raw terminal title (e.g. `surface.title`).
    ///   - currentName: the session's current sidebar name, for the unchanged-value guard.
    ///   - projectDirectoryName: the project's root directory name (e.g. "ghostties"),
    ///     rejected as a bare-directory-name title since it carries no information
    ///     beyond what the sidebar already shows via the project row.
    static func sanitize(
        title: String,
        currentName: String,
        projectDirectoryName: String? = nil
    ) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        if bareProgramNames.contains(lowercased) { return nil }
        if let projectDirectoryName, lowercased == projectDirectoryName.lowercased() {
            return nil
        }

        // Bare filesystem path: starts with "/" or "~" and has no whitespace
        // (a real sentence describing work will almost always contain a space).
        if (trimmed.hasPrefix("/") || trimmed.hasPrefix("~")) && !trimmed.contains(" ") {
            return nil
        }

        // Shell prompt: conventionally ends in "$", "%", or "#" (optionally followed
        // by trailing whitespace already stripped above).
        if trimmed.hasSuffix("$") || trimmed.hasSuffix("%") || trimmed.hasSuffix("#") {
            return nil
        }

        let sanitized = truncated(trimmed, maxLength: maxLength)
        guard !sanitized.isEmpty, sanitized != currentName else { return nil }
        return sanitized
    }

    /// Truncates to `maxLength`, backing up to the nearest preceding word
    /// boundary so the result never ends mid-word.
    private static func truncated(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let prefix = String(string.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace])
        }
        return prefix
    }
}
