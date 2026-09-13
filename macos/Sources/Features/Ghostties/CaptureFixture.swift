import Foundation

/// Marketing-capture fixture mode — the data source for automated screenshots
/// of the app used on ghostties.org (`scripts/capture-marketing.sh`).
///
/// Activated **only** by the `GHOSTTIES_CAPTURE_FIXTURE=1` launch
/// environment variable (never a `-key value` launch argument — see
/// `isActive`'s doc comment for why argv doesn't work for this app). When
/// active:
///   - `WorkspaceStore.shared` is seeded with an invented project/session
///     cast instead of loading the real `~/Library/Application
///     Support/Ghostties/workspace.json` — see `WorkspaceStore.shared`.
///   - `SessionCoordinator.createSession` runs a canned terminal transcript
///     instead of the user's real login shell — see the fixture branch
///     there.
///   - `BuildInfoBadgeView` force-hides regardless of the
///     `ghostties.devBuildInfoBadge.enabled` default — see that view.
///
/// This is privacy-critical: a spike capture (pre-fixture) leaked Sean's real
/// project names, his `seansmith@macbookpro` hostname, and the dev build
/// badge into a saved PNG. Every one of those paths is gated behind
/// `isActive`, which defaults to `false` — without the environment variable
/// this file changes nothing about the app's behavior.
enum CaptureFixture {
    /// Whether fixture mode is active for this process launch.
    ///
    /// Read from an **environment variable**
    /// (`app.launchEnvironment["GHOSTTIES_CAPTURE_FIXTURE"] = "1"`), not a
    /// `-key value` launch argument. Ghostty's own core CLI parser scans
    /// `argv` for config directives and pops a "Configuration Errors" dialog
    /// on any token it doesn't recognize — verified by hand: passing
    /// `-GhosttiesCaptureFixture 1` produced a 6-error dialog (one per
    /// argv token across three attempted flags), even though
    /// `-ApplePersistenceIgnoreState YES` alone (a recognized system launch
    /// argument) is silently accepted. The environment-variable channel is
    /// the same one `GhosttyCustomConfigCase.ghosttyApplication()` already
    /// uses for `GHOSTTY_CONFIG_PATH` / `GHOSTTY_USER_DEFAULTS_SUITE`, and
    /// never reaches argv at all.
    static let isActive: Bool = ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_FIXTURE"] == "1"

    // MARK: - Canned Workspace

    #if DEBUG

    /// Deterministic UUID so repeated captures produce byte-stable ghost
    /// assignments and ordering — never `UUID()`, which would reshuffle the
    /// sidebar (and the ghost pick) on every relaunch.
    private static func fixedId(_ tail: String) -> UUID {
        let padded = String(repeating: "0", count: max(0, 12 - tail.count)) + tail
        return UUID(uuidString: "CAFEFEED-0000-4000-8000-\(padded)")!
    }

    /// Invented project cast — same names already used as the invented cast
    /// in `docs/design/web-redesign/rebuild/index.html` (switchboard,
    /// atlas-api, fieldwork, pendulum, silo, trove, wren). Never Sean's real
    /// projects. `rootPath` points at a real, writable directory created
    /// under the sandbox's own temp container — see
    /// `fixtureWorkingDirectory(for:)` — so a canned session's shell `cd`
    /// succeeds without inventing (or touching) a path on Sean's disk.
    private struct FixtureProject {
        let name: String
        let ghost: GhostCharacter
        let isPinned: Bool
    }

    private static let fixtureProjects: [FixtureProject] = [
        FixtureProject(name: "atlas-api", ghost: .banshee, isPinned: true),
        FixtureProject(name: "fieldwork", ghost: .clyde, isPinned: true),
        FixtureProject(name: "pendulum", ghost: .ember, isPinned: true),
        FixtureProject(name: "silo", ghost: .haunt, isPinned: true),
        FixtureProject(name: "switchboard", ghost: .pinky, isPinned: true),
        FixtureProject(name: "trove", ghost: .specter, isPinned: true),
        FixtureProject(name: "wren", ghost: .wisp, isPinned: true),
    ]

    /// A real, writable directory under the sandbox temp container so a
    /// canned session's `cd` succeeds. Created lazily on first access;
    /// idempotent (`withIntermediateDirectories: true`).
    static func fixtureWorkingDirectory(for projectName: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostties-capture-fixture", isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static let projects: [Project] = fixtureProjects.map { fp in
        Project(
            id: fixedId(String(format: "%04d", fixtureProjects.firstIndex { $0.name == fp.name }! + 1)),
            name: fp.name,
            rootPath: fixtureWorkingDirectory(for: fp.name),
            isPinned: fp.isPinned,
            ghostCharacter: fp.ghost,
            lastActiveAt: Date()
        )
    }

    private static func projectId(_ name: String) -> UUID {
        projects.first { $0.name == name }!.id
    }

    /// `(name, project, ghost, indicator state)` — mirrors the rebuild
    /// reference's session cast: switchboard has 4 live sessions (2 waiting,
    /// 2 processing), fieldwork 1 waiting, plus a couple of idle/archived
    /// entries elsewhere so neither sidebar tab reads as empty.
    private struct FixtureSession {
        let name: String
        let project: String
        let ghost: GhostCharacter
        let state: SessionIndicatorState
        let hoursAgo: Double
    }

    private static let fixtureSessions: [FixtureSession] = [
        FixtureSession(name: "Claude Code 4", project: "switchboard", ghost: .mist, state: .processing, hoursAgo: 0),
        FixtureSession(name: "Claude Code 3", project: "switchboard", ghost: .gloom, state: .processing, hoursAgo: 0.02),
        FixtureSession(name: "Claude Code 2", project: "switchboard", ghost: .polter, state: .waiting, hoursAgo: 0.05),
        FixtureSession(name: "Claude Code 1", project: "switchboard", ghost: .wraith, state: .waiting, hoursAgo: 0.07),
        FixtureSession(name: "Claude Code 1", project: "fieldwork", ghost: .shade, state: .waiting, hoursAgo: 0.1),
        FixtureSession(name: "Claude Code 5", project: "pendulum", ghost: .spike, state: .inactive, hoursAgo: 2),
        FixtureSession(name: "docs pass", project: "silo", ghost: .drift, state: .inactive, hoursAgo: 24),
        FixtureSession(name: "release notes", project: "trove", ghost: .clyde, state: .inactive, hoursAgo: 72),
        FixtureSession(name: "icon pass", project: "wren", ghost: .pinky, state: .inactive, hoursAgo: 168),
    ]

    static let sessions: [AgentSession] = fixtureSessions.enumerated().map { index, fs in
        let now = Date()
        return AgentSession(
            id: fixedId(String(format: "%04d", 100 + index)),
            name: fs.name,
            templateId: AgentTemplate.claudeCode.id,
            projectId: projectId(fs.project),
            sortOrder: index,
            lastActiveAt: now.addingTimeInterval(-fs.hoursAgo * 3600),
            lastOutputAt: now.addingTimeInterval(-fs.hoursAgo * 3600),
            isNamePinned: true,
            ghostCharacter: fs.ghost
        )
    }

    /// Build the seeded `WorkspaceStore` and apply the canned indicator
    /// states — indicator state is separate, ephemeral, non-persisted
    /// per-window state, so it can't be baked into the `AgentSession`
    /// records above and has to be pushed in after construction.
    @MainActor
    static func makeStore() -> WorkspaceStore {
        let store = WorkspaceStore(
            testingProjects: projects,
            testingSessions: sessions,
            hasShownPinMigrationNotice: true,
            hasDismissedPinMigrationNotice: true
        )
        for (fs, session) in zip(fixtureSessions, sessions) {
            store.updateIndicatorState(id: session.id, state: fs.state)
        }
        return store
    }

    #endif

    // MARK: - Transcript Script Writer

    /// Writes `transcriptScript` to a uniquely-named launcher script under
    /// `~/.ghostties/cache/launchers` (the same directory and permissions
    /// the real launch-banner script mechanism already uses — see
    /// `SessionCoordinator.captureFixtureCommand(for:)` and
    /// `createSession`'s banner-script block) and returns its path. Shared
    /// by every surface-creation call site that needs to substitute the
    /// canned transcript for a real shell while fixture mode is active:
    /// `SessionCoordinator.createSession` (session rows) and
    /// `TerminalController.init` (the default/untitled window opened at
    /// cold launch, before any Ghosties project or session is picked).
    /// Falls back to `/bin/true` (an inert, silent no-op) if the write
    /// fails, so a broken fixture never accidentally falls through to a
    /// real shell and leaks real state.
    static func writeTranscriptScript(id: String) -> String {
        let scriptDir = ("~/.ghostties/cache/launchers" as NSString).expandingTildeInPath
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptDir) {
            try? fm.createDirectory(atPath: scriptDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700,
            ])
        }
        let scriptPath = (scriptDir as NSString).appendingPathComponent("capture-fixture-\(id).sh")
        guard (try? transcriptScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil else {
            return "/bin/true"
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        return scriptPath
    }

    // MARK: - Canned Terminal Transcript

    /// A dense, plausible Claude Code session transcript — real chrome, real
    /// rendering, staged data only. No real hostname or path appears; the
    /// engineering problem is invented and scoped to the `switchboard`
    /// fixture project. Deliberately NOT near-empty — the site's previous
    /// replica was rejected specifically for a sparse-looking terminal pane.
    static let transcriptScript: String = #"""
        #!/bin/zsh
        clear
        printf '\033[1m╭─────────────────────────────────────────╮\033[0m\n'
        printf '\033[1m│ \033[35m✻\033[0m\033[1m Claude Code\033[0m                              │\n'
        printf '\033[1m╰─────────────────────────────────────────╯\033[0m\n'
        printf '\n'
        printf '\033[1m> \033[0mFix the race condition in the reconnect handler and add a regression test\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Read(sync/reconnect.go)\n'
        printf '  \033[2m⎿  Read 142 lines\033[0m\n'
        printf '\n'
        printf '\033[35m⏺\033[0m I see it — the retry loop swaps the socket without holding the\n'
        printf '  connection lock, so a concurrent Send() can grab a half-closed fd.\n'
        printf '  Checking the call sites before widening the lock scope.\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Search(pattern: "reconnect(", path: "sync/")\n'
        printf '  \033[2m⎿  Found 3 matches across 2 files\033[0m\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Edit(sync/reconnect.go)\n'
        printf '  \033[2m⎿  Updated sync/reconnect.go with 8 additions and 2 removals\033[0m\n'
        printf '  \033[2m     41\033[0m   func (c *Client) reconnect(ctx context.Context) error {\n'
        printf '  \033[2m42\033[0m \033[31m-\033[0m    c.socket = nil\n'
        printf '  \033[2m43\033[0m \033[32m+\033[0m    c.mu.Lock()\n'
        printf '  \033[2m44\033[0m \033[32m+\033[0m    defer c.mu.Unlock()\n'
        printf '  \033[2m45\033[0m \033[32m+\033[0m    old := c.socket\n'
        printf '  \033[2m46\033[0m \033[32m+\033[0m    c.socket = nil\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Bash(go test ./sync/... -run TestReconnect -v)\n'
        printf '  \033[2m⎿  === RUN   TestReconnect_ConcurrentSend\033[0m\n'
        printf '  \033[2m   --- PASS: TestReconnect_ConcurrentSend (0.04s)\033[0m\n'
        printf '  \033[2m   PASS\033[0m\n'
        printf '  \033[2m   ok      switchboard/sync    0.312s\033[0m\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Tests pass. The lock now covers the full swap, so Send() either sees\n'
        printf '  the old live socket or blocks until the new one is ready — no\n'
        printf '  half-closed window. Want me to open a PR?\n'
        printf '\n'
        printf '\033[1m> \033[0myes, and add a one-line changelog entry\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Write(CHANGELOG.md)\n'
        printf '  \033[2m⎿  Wrote 1 line\033[0m\n'
        printf '\n'
        printf '\033[35m⏺\033[0m Bash(gh pr create --title "fix: hold connection lock across socket swap")\n'
        printf '  \033[2m⎿  https://github.com/example/switchboard/pull/412\033[0m\n'
        printf '\n'
        exec cat > /dev/null
        """#
}
