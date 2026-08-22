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

    /// Split `input` on whitespace, honoring double quotes so a quoted
    /// argument (`"ghostties website"`) survives as a single token instead
    /// of splitting on its internal space. Quote characters themselves are
    /// stripped from the resulting tokens.
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var inQuotes = false

        for char in input {
            if char == "\"" {
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
