import Foundation

/// Pure, testable command-grammar parsing for the session composer's
/// text-forward command entry (command grammar slice 1). Neither type here
/// touches SwiftUI or `@MainActor` state — see `SessionComposerRanking.swift`
/// for the same discipline applied to relevance ranking.
///
/// Target: typing `ghostties cco -n "test"` resolves project=ghostties,
/// tokenizes the remainder `cco -n test`, and offers a `Run "cco -n test"`
/// row that spawns a real session running that command — without ever
/// blanket-executing the remainder as a shell command (that would break
/// `ghostties orchestrator`, which must still reach the Orchestrator
/// template via the ordinary template-matching path).
enum SessionComposerCommandParser {

    /// The fixed identity of the composer's synthesized "Run" row.
    /// `ComposerOption.id` is injectable specifically to avoid UUID churn on
    /// every keystroke (see `SessionComposerPalette.ComposerOption`) — this
    /// row's underlying command changes on every keystroke by design, so a
    /// stable sentinel id (rather than deriving one from the command text)
    /// is what keeps hover/scroll state settled while the label updates.
    static let runRowId = UUID(uuidString: "89FA0000-0000-0000-0000-000000000001")!

    /// Result of tokenizing a composer query against the known project
    /// list. `projectId == nil` means "no command was recognized" — every
    /// caller must fall through to the existing whole-string filter,
    /// byte-identical, in that case.
    struct ParseResult: Equatable {
        let projectId: UUID?
        let remainderTokens: [String]

        /// The remainder tokens rejoined with single spaces, for display
        /// (`Run "<remainderText>"`) and for scoping the project's own
        /// template filter. Quote marks used only to keep a multi-word
        /// argument as one token are not reconstructed — display never
        /// needs to round-trip back into a query string.
        var remainderText: String {
            remainderTokens.joined(separator: " ")
        }

        static let none = ParseResult(projectId: nil, remainderTokens: [])
    }

    /// Straight `"` plus the curly quotes macOS's "Use smart quotes and
    /// dashes" substitutes it with by default (FB, round-2 review) — a
    /// pasted or typed `"` can arrive as U+201C/U+201D by the time it lands
    /// in `searchText`, and without this both `tokenize` and
    /// `splitOnFirstToken` would silently fail to recognize it as a quote
    /// boundary at all.
    private static let quoteCharacters: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]

    /// Split `input` on whitespace, honoring double quotes (straight or
    /// curly, see `quoteCharacters`) so a quoted argument
    /// (`"ghostties website"`) survives as a single token instead of
    /// splitting on its internal space. Quote characters themselves are
    /// stripped from the resulting tokens.
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var inQuotes = false

        for char in input {
            if quoteCharacters.contains(char) {
                inQuotes.toggle()
                hasCurrent = true
                continue
            }
            if char.isWhitespace, !inQuotes {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
                continue
            }
            current.append(char)
            hasCurrent = true
        }
        if hasCurrent {
            tokens.append(current)
        }
        return tokens
    }

    /// Parse `query` for the `<project> <remainder...>` command grammar.
    ///
    /// Tokenizes ONLY when ALL of: there are ≥2 tokens, token 1 exactly
    /// matches a project `name` or folder basename (case-insensitive), and
    /// `isLocked` is false. Any other case returns `.none` — the caller
    /// must treat that as "no command", not as an error, and keep filtering
    /// the raw query exactly as it did before this parser existed.
    static func parse(query: String, projects: [Project], isLocked: Bool) -> ParseResult {
        guard !isLocked else { return .none }

        let tokens = tokenize(query)
        guard tokens.count >= 2 else { return .none }

        guard let project = projects.first(where: { matches($0, token: tokens[0]) }) else {
            return .none
        }

        return ParseResult(projectId: project.id, remainderTokens: Array(tokens.dropFirst()))
    }

    /// Splits `rawQuery` into `(prefix, remainder)` on the boundary token 1
    /// occupies — quote-aware, mirrors `tokenize`'s scanning rules exactly so
    /// it agrees with what `tokenize` calls token 1. `prefix` is everything
    /// up to and including token 1 and the whitespace run separating it from
    /// the remainder; `remainder` is everything after that. BOTH are taken
    /// VERBATIM from `rawQuery` — no re-tokenizing, no rejoining. `nil` when
    /// `rawQuery` has no separable first token (blank/whitespace-only).
    ///
    /// This exists specifically so the breadcrumb chip's editable text
    /// (`SessionComposerPalette.queryFieldText`) can be lossless (B1,
    /// composer breadcrumb spec review). The binding used to reconstruct the
    /// remainder from `remainderText` — `remainderTokens.joined(separator: "
    /// ")` — which silently drops trailing whitespace and un-quotes a
    /// quoted argument (by design for DISPLAY purposes: `remainderText`
    /// backs `Run "<remainder>"` and the template filter, neither of which
    /// needs to round-trip). SwiftUI writes that lossy reconstruction back
    /// into the field on the very next update pass, so a space typed after
    /// "ghostties cco -n" was eaten the instant it was typed, and a typed
    /// quote character never survived into `searchText` at all. Slicing the
    /// ORIGINAL string instead of rebuilding one has no reconstruction step
    /// to lose anything in.
    static func splitOnFirstToken(_ rawQuery: String) -> (prefix: String, remainder: String)? {
        var index = rawQuery.startIndex
        var inQuotes = false
        var sawFirstToken = false

        // Skip leading whitespace before token 1 (mirrors `tokenize`, which
        // never emits a leading empty token).
        while index < rawQuery.endIndex, rawQuery[index].isWhitespace {
            index = rawQuery.index(after: index)
        }

        // Skip token 1 itself, honoring quotes exactly as `tokenize` does.
        while index < rawQuery.endIndex {
            let char = rawQuery[index]
            if quoteCharacters.contains(char) {
                inQuotes.toggle()
                sawFirstToken = true
                index = rawQuery.index(after: index)
                continue
            }
            if char.isWhitespace, !inQuotes { break }
            sawFirstToken = true
            index = rawQuery.index(after: index)
        }
        guard sawFirstToken else { return nil }

        // Skip the whitespace run separating token 1 from the remainder —
        // NOT included in `remainder`, but IS included in `prefix` (it's
        // re-prepended verbatim on every edit).
        while index < rawQuery.endIndex, rawQuery[index].isWhitespace {
            index = rawQuery.index(after: index)
        }

        return (
            prefix: String(rawQuery[rawQuery.startIndex..<index]),
            remainder: String(rawQuery[index...])
        )
    }

    /// Whether `rawQuery` is "mid-command with an empty remainder": a single
    /// token that exactly matches a project, followed by at least one real
    /// whitespace character and nothing else (`"ghostties "`,
    /// `"ghostties  "`). `parse(query:)` can't express this — it's fed the
    /// TRIMMED search text, and trimming is exactly what erases the
    /// trailing-whitespace signal checked here.
    ///
    /// Exists to fix D3 (composer breadcrumb spec review): without it, the
    /// chip is driven purely by `parse(query:)`, which requires ≥2 tokens —
    /// so backspacing a command's remainder down to nothing drops the token
    /// count to 1, `commandProject` goes `nil`, and the chip falls back
    /// silently to whatever `selectedProjectId` still reads (a DIFFERENT,
    /// previously-selected project). The typed project name is lost with
    /// it, and retyping doesn't recover it — the caret is at the end of
    /// whatever text remains, so `ghostties` + `c` becomes `ghossttiesc`,
    /// one token, no command. Keeping the chip resolved through the
    /// empty-remainder state (this function) means backspacing to nothing
    /// and retyping stays inside the same two-token shape the whole time.
    static func stickyChipProjectId(rawQuery: String, projects: [Project], isLocked: Bool) -> UUID? {
        guard !isLocked else { return nil }
        guard let split = splitOnFirstToken(rawQuery), split.remainder.isEmpty else { return nil }
        // `splitOnFirstToken("bru")` ALSO returns an empty remainder when
        // there was never a separator at all (end of string reached mid
        // token) — that's the ordinary single-token project-search case
        // (`testParseSingleTokenReturnsNilEvenWhenItMatchesAProjectName`)
        // and must NOT count as sticky. A genuine separator was consumed
        // only when `prefix` itself ends in whitespace.
        guard split.prefix.last?.isWhitespace == true else { return nil }
        // F2 fix (round-2 review): `trimmingCharacters(in: .whitespaces)`
        // only strips whitespace — `tokenize` also strips quote characters,
        // so a quoted multi-word name (`"ghostties web" `) produced a token
        // of `"\"ghostties web\""`, quotes still attached, which never
        // matched `matches(_:token:)` against the bare project name. That
        // silently defeated the sticky chip for every multi-word or quoted
        // project name — exactly the D3 dead end this function exists to
        // close. `tokenize(split.prefix).first` runs the SAME quote-aware
        // scan `splitOnFirstToken` above already mirrors, so it agrees with
        // what `tokenize` calls token 1 for both plain and quoted names.
        guard let token = tokenize(split.prefix).first else { return nil }
        guard let project = projects.first(where: { matches($0, token: token) }) else { return nil }
        return project.id
    }

    private static func matches(_ project: Project, token: String) -> Bool {
        if project.name.caseInsensitiveCompare(token) == .orderedSame { return true }
        let basename = (project.rootPath as NSString).lastPathComponent
        return basename.caseInsensitiveCompare(token) == .orderedSame
    }

    /// Synthesize the ad-hoc template for a resolved command's remainder.
    ///
    /// Reuses `AgentTemplate.shell.id` (never mints a fresh UUID) so
    /// `WorkspacePersistence.validate` doesn't delete the session on
    /// relaunch — relaunching an ad-hoc session relaunches plain Shell,
    /// an accepted degradation. `agent:` is set purely to buy the
    /// login-shell wrapper `SessionCoordinator.createSession` writes
    /// whenever `template.launchBanner != nil` (i.e. `agent != nil`) —
    /// `exec` inside that `#!/bin/zsh -l` wrapper resolves zsh functions
    /// like `cco`, which a bare `/bin/sh -c` spawn never would.
    ///
    /// The remainder's first token becomes `command` (the only
    /// single-quoted-whole carrier, `AgentTemplate.shellEscape`); every
    /// token after it becomes `agent.additionalFlags`, the only
    /// per-token-escaped carrier — splitting this way is what keeps
    /// `cco -n test` from collapsing into one unrunnable argv word.
    static func makeAdHocTemplate(remainderTokens: [String]) -> AgentTemplate? {
        guard let first = remainderTokens.first else { return nil }
        let rest = Array(remainderTokens.dropFirst())

        // Blocker fix: a quoted first remainder token (`ghostties "npm run
        // dev"`) survives `tokenize` as one token containing internal
        // whitespace. Putting that whole into `command` reintroduces the
        // `shellEscape` blocker verbatim — `buildCommand()` would quote it
        // as a single argv word (`'npm run dev'`), which the shell can't
        // resolve. Re-split the first token on whitespace: only its first
        // word becomes `command`; every word after it flows into
        // `additionalFlags` ahead of the rest of the remainder. This also
        // covers an unbalanced-quote remainder (`ghostties "` tokenizes to
        // `["ghostties", ""]`) — an empty or whitespace-only first token
        // splits to zero words, so `command` guards below and this
        // returns `nil` instead of committing a live `Run ""` row.
        let firstWords = first.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let command = firstWords.first else { return nil }
        let flags = Array(firstWords.dropFirst()) + rest

        return AgentTemplate(
            id: AgentTemplate.shell.id,
            name: command,
            kind: .custom,
            command: command,
            agent: AgentTemplate.AgentConfig(additionalFlags: flags)
        )
    }

    /// Resolves which project a commit should land in: a resolved command
    /// project (typed `<project> <remainder>`) takes precedence over
    /// whatever project is currently selected in the dropdown. Pure/testable
    /// extraction of the write-path polarity fixed by the "scopes list to
    /// project A, commits into project B" blocker — `SessionComposerPalette`
    /// itself has no testable seam for this (a SwiftUI `View` reading
    /// `@EnvironmentObject` state), so this is the seam.
    static func resolveCommitProjectId(commandProjectId: UUID?, selectedProjectId: UUID?) -> UUID? {
        commandProjectId ?? selectedProjectId
    }
}
