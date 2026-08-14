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
        "claude", "claude code", "zsh", "bash", "-zsh", "-bash", "sh", "-sh", "fish", "-fish"
    ]

    /// Strips a leading run of status/spinner marker characters — and any
    /// whitespace immediately following the run — from `segment`, if
    /// present. Claude Code (and similar CLI agents) prefix a terminal title
    /// with a marker while working, either a fixed glyph (e.g. `"✳ Claude
    /// Code"`) or an animated spinner frame cycling through a symbol block
    /// (e.g. Braille Patterns `"⠐ "`, or circle-fill frames `"◐ "` / `"◑ "`).
    ///
    /// Matched structurally rather than by enumerating known glyphs — a
    /// leading character is stripped when it's Unicode general category `So`
    /// (Symbol, other) and does NOT default to emoji presentation. This
    /// covers every observed marker/spinner style without a hardcoded list
    /// (enumerating glyphs is exactly what made three previous sanitizer
    /// patches leak on a new spinner style), while a genuine leading emoji
    /// (`Emoji_Presentation=Yes`, e.g. 🚀) is left untouched since it's part
    /// of the title, not a status marker.
    ///
    /// This result is what `sanitize(title:currentName:projectDirectoryName:)`
    /// actually returns — the marker is not persisted into the sidebar name.
    private static func strippingLeadingStatusMarker(from segment: Substring) -> Substring {
        var result = segment
        while let first = result.first,
              first.unicodeScalars.count == 1,
              let scalar = first.unicodeScalars.first {
            let properties = scalar.properties
            guard properties.generalCategory == .otherSymbol, !properties.isEmojiPresentation else { break }
            result.removeFirst()
        }
        while let next = result.first, next.isWhitespace {
            result.removeFirst()
        }
        return result
    }

    /// Separators terminal titles commonly use to glue a program/repo name
    /// onto the "real" content, e.g. `"repo-name | Claude Code"` or
    /// `"repo-name — zsh"`. Deliberately excludes a bare, unspaced `-` —
    /// project/repo directory names are routinely hyphenated
    /// (`sample-web-project`), and splitting on every hyphen would shred
    /// that single informative segment into fragments that individually
    /// look like noise. Only a *spaced* hyphen (`" - "`) is treated as a
    /// separator, matching how humans actually punctuate a title.
    private static let titleSeparatorPattern = #"(?: - )|[|—–:·»>]"#

    /// Returns `true` if `cleaned`, once split on `titleSeparatorPattern`,
    /// contains at least one segment that isn't just `projectDirectoryName`
    /// or a bare program name — i.e. the title carries information beyond
    /// "this is project X, running program Y".
    private static func hasInformativeSegment(in cleaned: String, projectDirectoryName: String) -> Bool {
        let placeholder: Character = "\u{0}"
        let replaced = cleaned.replacingOccurrences(
            of: titleSeparatorPattern,
            with: String(placeholder),
            options: .regularExpression
        )
        let dirLower = projectDirectoryName.lowercased()
        for rawSegment in replaced.split(separator: placeholder, omittingEmptySubsequences: true) {
            let trimmedSegment = rawSegment.trimmingCharacters(in: .whitespaces)
            guard !trimmedSegment.isEmpty else { continue }
            // `cleaned` already had its leading status/spinner marker (if
            // any) stripped before this function is called, so only the
            // first segment could ever have carried one — no per-segment
            // stripping needed here.
            let segmentLower = trimmedSegment.lowercased()
            if segmentLower == dirLower { continue }
            if bareProgramNames.contains(segmentLower) { continue }
            return true
        }
        return false
    }

    /// True when `cleaned`, once split on `titleSeparatorPattern`, ends in a
    /// bare "Claude Code" segment — e.g. `"Code | Claude Code"` or
    /// `"sample-web-project — Claude Code"`. Claude Code's idle terminal
    /// title has the shape `"<cwd-basename> | Claude Code"`, where the
    /// segment before "Claude Code" is always a directory basename, never a
    /// description — so a trailing "Claude Code" segment marks the whole
    /// title as boilerplate regardless of what precedes it or what the
    /// project directory happens to be. Deliberately unconditional (no
    /// `projectDirectoryName` needed): the leading segment's identity
    /// doesn't matter here.
    ///
    /// This does mean a leading segment that reads as informative on its own
    /// (e.g. `"Fixing the parser | Claude Code"`) is still rejected. That's
    /// intentional, not an oversight: Claude Code's *working* title uses a
    /// marker prefix instead (`"<glyph> <task description>"`), never a
    /// trailing "| Claude Code" — so this exact shape doesn't occur for a
    /// genuine description, and the simple, unconditional rule is worth more
    /// than guarding an edge case that can't happen.
    private static func endsWithBareClaudeCodeSegment(_ cleaned: String) -> Bool {
        let placeholder: Character = "\u{0}"
        let replaced = cleaned.replacingOccurrences(
            of: titleSeparatorPattern,
            with: String(placeholder),
            options: .regularExpression
        )
        guard let lastSegment = replaced.split(separator: placeholder, omittingEmptySubsequences: true).last else {
            return false
        }
        return lastSegment.trimmingCharacters(in: .whitespaces).lowercased() == "claude code"
    }

    /// True when `cleaned` is an *abbreviated* filesystem path — the shape a
    /// terminal title uses to fit a long path into limited width, e.g.
    /// `"…/Code/sandbox/sample-web-project"` or
    /// `".../Users/someone/projects/thing"`. The existing bare-path check below
    /// only recognizes a path that starts with `/` or `~` outright; an
    /// elided prefix defeats it.
    ///
    /// Distinguished from ordinary prose that happens to start with an
    /// ellipsis (`"… and then it worked"`) by requiring a `/` to follow the
    /// ellipsis once any whitespace between them is skipped — a real
    /// abbreviated path always continues straight into the next path
    /// segment; prose does not.
    private static func hasAbbreviatedPathPrefix(_ cleaned: String) -> Bool {
        var remainder = Substring(cleaned)
        if remainder.hasPrefix("...") {
            remainder = remainder.dropFirst(3)
        } else if remainder.hasPrefix("…") {
            remainder = remainder.dropFirst()
        } else {
            return false
        }
        while let next = remainder.first, next.isWhitespace {
            remainder = remainder.dropFirst()
        }
        return remainder.hasPrefix("/")
    }

    /// The `titleFromTerminal` fallback `SurfaceView_AppKit` writes ~500ms after
    /// surface creation if no real title has arrived yet. It carries no
    /// information and must never make it into a persisted session name —
    /// belt-and-braces on top of the debounce that should prevent it ever
    /// being sampled in the first place (see `SessionCoordinator`).
    private static let placeholderTitle = "👻"

    /// Characters that are invisible-but-not-illegal: safe to strip rather
    /// than reject the whole title over. Bidi-override codepoints (can
    /// visually reverse the rendered string, e.g. hiding a malicious
    /// extension behind an RTL override) and zero-width padding/obfuscation
    /// characters. Stripped before any shape checks below.
    ///
    /// Deliberately does NOT include U+200C (ZWNJ) or U+200D (ZWJ) — those
    /// are load-bearing, not obfuscation: ZWJ is what stitches multi-codepoint
    /// emoji into one glyph (👨‍💻, 👨‍👩‍👧‍👦), and ZWNJ is required for correct
    /// rendering in Persian, Hindi, and Arabic text. Stripping either shatters
    /// the sequence into separate, wrong-looking characters.
    ///
    /// Real control characters (NUL, BEL, BS, ESC, CR, embedded newlines,
    /// C0/C1 controls) are handled separately in `sanitize(title:...)` — as a
    /// hard reject, not a strip. Splicing around a control byte can produce
    /// output that's worse than the unsanitized original (e.g. stripping the
    /// ESC byte from "\u{1B}[31mTitle" leaves the visible garbage "[31mTitle").
    private static let disallowedCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        set.insert(charactersIn: "\u{200B}\u{FEFF}")
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

        // Reject outright — never splice — any title containing a real
        // control character (Unicode General Category Cc: NUL, BEL, BS, ESC,
        // CR, embedded LF, the C1 range). A title with an embedded newline or
        // an ANSI escape sequence isn't a meaningful session name, and a
        // spliced result (welding the words on either side of the removed
        // byte together, or leaving a stray "[31m" behind) is worse than
        // rejecting it. Checked via `generalCategory` rather than
        // `CharacterSet.controlCharacters` so format characters (Cf) like
        // ZWJ/ZWNJ and the bidi overrides — which are handled separately
        // below as strip-not-reject — are never caught here.
        guard !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            return nil
        }

        // Strip bidi overrides and zero-width obfuscation characters before
        // any shape check below sees the string. Re-trim afterward: removing
        // one of these can expose new leading/trailing whitespace.
        let withoutDisallowedCharacters = String(trimmed.unicodeScalars.filter { !disallowedCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutDisallowedCharacters.isEmpty else { return nil }

        // Strip a leading status/spinner marker (e.g. "✳ ", "⠐ ", "◐ ") so it
        // is never persisted into the sidebar name — the row already encodes
        // session state via the colored status dot, and a stored spinner
        // frame captures one animation instant and then freezes it forever.
        // Every check below, and the value returned when a title is
        // accepted, operates on this already-stripped string.
        let cleaned = String(strippingLeadingStatusMarker(from: Substring(withoutDisallowedCharacters)))
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
        // Reject a title ending in a bare "Claude Code" segment regardless of
        // what precedes it — see `endsWithBareClaudeCodeSegment` doc comment.
        if endsWithBareClaudeCodeSegment(cleaned) { return nil }
        // Reject a title whose only content, once split on common title
        // separators (`|`, em/en dash, spaced `-`, `:`, `·`, `»`, `>`), is
        // the project directory name and/or a bare program name — e.g.
        // Claude Code's terminal title "repo-name | Claude Code" carries no
        // information beyond what the sidebar already shows via the project
        // row and the fact that a Claude session is running there.
        if let projectDirectoryName, !hasInformativeSegment(in: cleaned, projectDirectoryName: projectDirectoryName) {
            return nil
        }

        // Bare filesystem path: starts with "/" or "~" and reads as a short
        // path rather than a sentence. A real sentence describing work almost
        // always runs to more than a few words, even when it happens to
        // mention a path with spaces in a directory/file name (e.g.
        // "~/Code/my project" is still just a path, not a description of
        // work) — so gate on word count rather than requiring the whole
        // string to be space-free.
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~") || hasAbbreviatedPathPrefix(cleaned) {
            let wordCount = cleaned.split(separator: " ").count
            if wordCount <= 3 { return nil }
        }

        // Shell prompt: conventionally ends in "$", "%", or "#". A digit
        // immediately before the suffix does NOT prove innocence for "$" or
        // "#" — real prompts routinely end with a numbered host/directory
        // (`sean@mbp:~/Code/ghostties2$`, `root@server1#`), so those two
        // suffixes are rejected unconditionally. "%" is the one suffix where
        // a digit-preceded exemption is safe: percent-terminated PROGRESS
        // reports (compaction %, coverage %, build %) are a distinct, common
        // agent-tooling shape, and a shell prompt never legitimately ends in
        // "<digit>%" (zsh/bash prompt characters are never "%" preceded by a
        // bare digit in practice — a literal trailing "%" prompt is always
        // preceded by a space or path character). This keeps "Compacting
        // conversation 45%" passing while real prompts don't.
        if cleaned.hasSuffix("$") || cleaned.hasSuffix("#") {
            return nil
        }
        if cleaned.hasSuffix("%") {
            let beforeSuffix = cleaned.dropLast()
            if beforeSuffix.last?.isNumber != true {
                return nil
            }
        }

        // `user@host` token: bash/zsh's default PS1 (`\u@\h:\w\$`) and every
        // common SSH-style prompt embed this shape somewhere in the string
        // regardless of what character the prompt happens to end with —
        // reject on the token's presence alone rather than relying solely on
        // the trailing-character heuristic above.
        if cleaned.range(of: #"\S+@\S+"#, options: .regularExpression) != nil {
            return nil
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
