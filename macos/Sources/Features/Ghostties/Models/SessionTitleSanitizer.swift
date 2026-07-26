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

    /// The `titleFromTerminal` fallback `SurfaceView_AppKit` writes ~500ms after
    /// surface creation if no real title has arrived yet. It carries no
    /// information and must never make it into a persisted session name —
    /// belt-and-braces on top of the debounce that should prevent it ever
    /// being sampled in the first place (see `SessionCoordinator`).
    private static let placeholderTitle = "👻"

    /// Characters that must never appear in a sidebar session name: ASCII/C1
    /// control characters (NUL, BEL, BS, ESC, CR, embedded newlines, ...),
    /// bidi-override codepoints (can visually reverse the rendered string,
    /// e.g. hiding a malicious extension behind an RTL override), and
    /// zero-width characters (invisible padding/obfuscation). Stripped before
    /// any shape checks below.
    private static let disallowedCharacters: CharacterSet = {
        var set = CharacterSet.controlCharacters
        set.insert(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        set.insert(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}")
        return set
    }()

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

        // Strip control characters, bidi overrides, and zero-width characters
        // before any shape check below sees the string. Re-trim afterward:
        // removing an embedded control character can expose new leading/
        // trailing whitespace (e.g. a title that was "\u{1B}[31mTitle" has
        // only leading ANSI bytes, not whitespace, but this is cheap and safe
        // either way).
        let cleaned = String(trimmed.unicodeScalars.filter { !disallowedCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Explicit reject for the terminal's own "no title yet" placeholder —
        // belt-and-braces; the debounce on the caller side should prevent
        // this from ever being sampled, but a sanitizer that accepts it is a
        // second way for it to leak into workspace.json.
        guard cleaned != placeholderTitle else { return nil }

        // Reject strings with no actual content — punctuation-only titles
        // ("...", "!!!") and anything left that isn't alphanumeric (this also
        // catches stray emoji-only titles beyond the placeholder above).
        guard cleaned.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }

        let lowercased = cleaned.lowercased()
        if bareProgramNames.contains(lowercased) { return nil }
        if let projectDirectoryName, lowercased == projectDirectoryName.lowercased() {
            return nil
        }

        // Bare filesystem path: starts with "/" or "~" and reads as a short
        // path rather than a sentence. A real sentence describing work almost
        // always runs to more than a few words, even when it happens to
        // mention a path with spaces in a directory/file name (e.g.
        // "~/Code/my project" is still just a path, not a description of
        // work) — so gate on word count rather than requiring the whole
        // string to be space-free.
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~") {
            let wordCount = cleaned.split(separator: " ").count
            if wordCount <= 3 { return nil }
        }

        // Shell prompt: conventionally ends in "$", "%", or "#". But
        // percent-terminated PROGRESS reports (compaction %, coverage %,
        // build %) are a distinct, common agent-tooling shape that ends the
        // same way — the two are distinguished by what immediately precedes
        // the trailing character: a real prompt's trailing character follows
        // a hostname/path/space, never a bare digit, while "45%" is a
        // digit-percent pair. Reject only the non-digit-preceded case so
        // "Compacting conversation 45%" survives while real prompts don't.
        if cleaned.hasSuffix("$") || cleaned.hasSuffix("%") || cleaned.hasSuffix("#") {
            let beforeSuffix = cleaned.dropLast()
            if beforeSuffix.last?.isNumber != true {
                return nil
            }
        }

        let sanitized = truncated(cleaned, maxLength: maxLength)
        guard !sanitized.isEmpty, sanitized != currentName else { return nil }
        return sanitized
    }

    /// Truncates to `maxLength`, backing up to the nearest preceding
    /// whitespace boundary (space or other Unicode whitespace, e.g.
    /// non-breaking/thin space) so the result avoids splitting mid-word
    /// *when a whitespace boundary exists within the truncated prefix*. Falls
    /// back to a hard cut at `maxLength` when it doesn't — e.g. a single word
    /// longer than `maxLength` has no boundary to back up to.
    private static func truncated(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let prefix = String(string.prefix(maxLength))
        if let lastSpaceRange = prefix.rangeOfCharacter(from: .whitespaces, options: .backwards) {
            return String(prefix[..<lastSpaceRange.lowerBound])
        }
        return prefix
    }
}
