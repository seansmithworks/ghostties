import AppKit
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

    // MARK: - Harness state dir + dispatch log

    /// `$GHOSTTIES_STATE_DIR`, only when fixture mode is active and it is
    /// set. Unlike `WorkspacePersistence.directory` there is no fallback to
    /// the real Application Support path: the harness logs never go there.
    static var harnessStateDir: URL? {
        stateDir(fixtureActive: isActive, env: ProcessInfo.processInfo.environment)
    }

    static func stateDir(fixtureActive: Bool, env: [String: String]) -> URL? {
        guard fixtureActive, let raw = env["GHOSTTIES_STATE_DIR"], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// One JSON object, no trailing newline. Optional values encode as null.
    static func jsonLine(_ fields: [String: Any?]) -> Data {
        let object = fields.mapValues { $0 ?? NSNull() }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// Appends `line` plus a newline to `url`, creating the file (and its
    /// directory) when missing.
    static func appendLine(_ line: Data, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line + Data("\n".utf8))
    }

    static func dispatchLine(
        t: TimeInterval, project: String, cwd: String, command: String?, template: String?
    ) -> Data {
        jsonLine(["t": t, "project": project, "cwd": cwd, "command": command, "template": template])
    }

    /// `SessionCoordinator.createSession` calls this just before it spawns.
    /// Appends to `$GHOSTTIES_STATE_DIR/dispatch.jsonl`; no-op outside fixture mode.
    static func logDispatch(
        project: String, cwd: String, command: String?, template: String?, stateDir dir: URL? = harnessStateDir
    ) {
        guard let dir else { return }
        appendLine(
            dispatchLine(t: Date().timeIntervalSince1970, project: project, cwd: cwd, command: command, template: template),
            to: dir.appendingPathComponent("dispatch.jsonl")
        )
    }

    // MARK: - Isolated defaults

    /// Throwaway per-process suite for fixture runs, so a harness run never
    /// writes Sean's real Dev settings (composer state, the Cmd+T pref).
    static var defaultsSuiteName: String { "ghostties.capture.\(ProcessInfo.processInfo.processIdentifier)" }

    private static let fixtureDefaults: UserDefaults? = UserDefaults(suiteName: defaultsSuiteName)

    /// The defaults the composer store and the Cmd+T pref read/write:
    /// the throwaway suite in fixture mode, `.standard` otherwise.
    static func defaults(fixtureActive: Bool) -> UserDefaults {
        guard fixtureActive else { return .standard }
        // Fixture mode must never fall back to `.standard`: that is Sean's Dev domain.
        guard let suite = fixtureDefaults else {
            preconditionFailure("could not create the capture defaults suite \(defaultsSuiteName)")
        }
        return suite
    }

    /// Removes the suite's domain and the plist it left behind. Called from
    /// `applicationWillTerminate`; a no-op outside fixture mode.
    static func cleanUpDefaults(fixtureActive: Bool) {
        guard fixtureActive else { return }
        let name = defaultsSuiteName
        UserDefaults.standard.removePersistentDomain(forName: name)
        fixtureDefaults?.removePersistentDomain(forName: name)
        // cfprefsd may still re-create an EMPTY plist after the process exits
        // (observed ~1 run in 2); `run.sh` deletes the file once the pid is
        // gone. `synchronize()` here made it worse, so it is not called.
        try? FileManager.default.removeItem(at: defaultsPlistURL)
    }

    static var defaultsPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(defaultsSuiteName).plist")
    }

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

    // MARK: - Opt-in seed knobs

    /// Two opt-in variations on the seeded cast, for contract rows that need
    /// a state the default cast can't show. Both are off unless set, and the
    /// default cast is byte-for-byte the same with both off.
    ///   - `VERIFY_FIXTURE_PROJECTS=none` -> `GHOSTTIES_CAPTURE_FIXTURE_PROJECTS=none`:
    ///     0 projects and 0 sessions (X3: the Run row accepts any text once a
    ///     project exists).
    ///   - `VERIFY_FIXTURE_TEMPLATE_IN_USE=1` -> `GHOSTTIES_CAPTURE_FIXTURE_TEMPLATE_IN_USE=1`:
    ///     one user template, "Mine", used by two trove sessions (T6: the
    ///     in-use delete alert).
    struct SeedKnobs: Equatable {
        var zeroProjects = false
        var templateInUse = false
    }

    static func parseSeedKnobs(_ env: [String: String]) -> SeedKnobs {
        SeedKnobs(
            zeroProjects: env["GHOSTTIES_CAPTURE_FIXTURE_PROJECTS"] == "none",
            templateInUse: env["GHOSTTIES_CAPTURE_FIXTURE_TEMPLATE_IN_USE"] == "1"
        )
    }

    static let seedKnobs: SeedKnobs = isActive ? parseSeedKnobs(ProcessInfo.processInfo.environment) : SeedKnobs()

    /// The in-use user template. Fixed id so the sessions can reference it.
    static let inUseTemplate = AgentTemplate(id: fixedId("9001"), name: "Mine", kind: .custom)

    /// Fixture sessions that use `inUseTemplate` under the knob.
    private static let inUseTemplateSessionNames: Set<String> = ["build fix", "release notes"]

    static func seededProjects(_ knobs: SeedKnobs) -> [Project] {
        if knobs.zeroProjects { return [] }
        return fixtureProjects.map { fp in
            Project(
                id: fixedId(String(format: "%04d", fixtureProjects.firstIndex { $0.name == fp.name }! + 1)),
                name: fp.name,
                rootPath: fixtureWorkingDirectory(for: fp.name),
                isPinned: fp.isPinned,
                ghostCharacter: fp.ghost,
                lastActiveAt: Date()
            )
        }
    }

    static let projects: [Project] = seededProjects(seedKnobs)

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
        FixtureSession(name: "reconnect race", project: "switchboard", ghost: .mist, state: .processing, hoursAgo: 0),
        FixtureSession(name: "rate limiter", project: "switchboard", ghost: .gloom, state: .processing, hoursAgo: 0.02),
        FixtureSession(name: "flaky ci", project: "switchboard", ghost: .polter, state: .waiting, hoursAgo: 0.05),
        FixtureSession(name: "deps bump", project: "switchboard", ghost: .wraith, state: .waiting, hoursAgo: 0.07),
        FixtureSession(name: "offline sync", project: "fieldwork", ghost: .shade, state: .waiting, hoursAgo: 0.1),
        FixtureSession(name: "auth migration", project: "atlas-api", ghost: .hex, state: .needsAttention, hoursAgo: 0.03),
        FixtureSession(name: "chart polish", project: "pendulum", ghost: .spike, state: .inactive, hoursAgo: 2),
        FixtureSession(name: "docs pass", project: "silo", ghost: .drift, state: .inactive, hoursAgo: 24),
        FixtureSession(name: "build fix", project: "trove", ghost: .chill, state: .error, hoursAgo: 48),
        FixtureSession(name: "release notes", project: "trove", ghost: .clyde, state: .inactive, hoursAgo: 72),
        FixtureSession(name: "icon pass", project: "wren", ghost: .pinky, state: .inactive, hoursAgo: 168),
    ]

    /// Round 6 follow-up: the one session the fixture marks focused, so a
    /// capture actually exercises the sidebar's selected-row styling
    /// (the expanded list's chip, `SidebarRowChipBackground`)
    /// instead of leaving every row in its resting state. The first entry ("reconnect race", switchboard, top of
    /// Active) — same row position Flow 07's own "portfolio" occupies.
    /// Wired in by `SessionCoordinator.applyCaptureFixtureFocusIfNeeded()`,
    /// called from both `WorkspaceSidebarView.onAppear` and
    /// `SidebarRailColumn.onAppear`.
    static var focusedSessionId: UUID? {
        sessions.first?.id
    }

    static func seededSessions(_ knobs: SeedKnobs, projects: [Project]) -> [AgentSession] {
        if knobs.zeroProjects { return [] }
        return fixtureSessions.enumerated().map { index, fs in
            let now = Date()
            let usesInUseTemplate = knobs.templateInUse && inUseTemplateSessionNames.contains(fs.name)
            return AgentSession(
                id: fixedId(String(format: "%04d", 100 + index)),
                name: fs.name,
                templateId: usesInUseTemplate ? inUseTemplate.id : AgentTemplate.claudeCode.id,
                projectId: projects.first { $0.name == fs.project }!.id,
                sortOrder: index,
                lastActiveAt: now.addingTimeInterval(-fs.hoursAgo * 3600),
                lastOutputAt: now.addingTimeInterval(-fs.hoursAgo * 3600),
                isNamePinned: true,
                ghostCharacter: fs.ghost
            )
        }
    }

    static let sessions: [AgentSession] = seededSessions(seedKnobs, projects: projects)

    /// Build the seeded `WorkspaceStore` and apply the canned indicator
    /// states — indicator state is separate, ephemeral, non-persisted
    /// per-window state, so it can't be baked into the `AgentSession`
    /// records above and has to be pushed in after construction.
    ///
    /// `SessionBucket.membership` (the Active/Inactive/Archive rule, see
    /// `git show 1c0f78b2b`) keys off `SessionStatus.isAlive`, NOT indicator
    /// state — so a fixture session also needs a `SessionStatus` pushed in,
    /// or every session lands in Archive regardless of indicator state. The
    /// status reported mirrors what the real app would set for that
    /// indicator state, so the fixture honors the rule rather than
    /// special-casing it: `.error` reports a non-alive status (a real error
    /// means the process already exited) and lands wherever the rule sends
    /// a non-alive session; every other non-`.inactive` state reports
    /// `.running` (a real open terminal), landing in Active.
    @MainActor
    static func makeStore(knobs: SeedKnobs = seedKnobs) -> WorkspaceStore {
        let seededProjects = seededProjects(knobs)
        let store = WorkspaceStore(
            testingProjects: seededProjects,
            testingSessions: seededSessions(knobs, projects: seededProjects),
            hasShownPinMigrationNotice: true,
            hasDismissedPinMigrationNotice: true
        )
        if knobs.templateInUse { store.addTemplate(inUseTemplate) }
        for (fs, session) in zip(fixtureSessions, store.sessions) {
            store.updateIndicatorState(id: session.id, state: fs.state)
            switch fs.state {
            case .inactive:
                break
            case .error:
                store.updateSessionStatus(id: session.id, status: .error(exitCode: 1))
            default:
                store.updateSessionStatus(id: session.id, status: .running)
            }
        }
        if let mode = initialSidebarMode {
            store.updateSidebarMode(mode)
        }
        // Listed projects first, in the given order, through the same
        // `moveProject` a header drop calls; the rest keep their order.
        for name in projectOrder(ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_PROJECT_ORDER"]).reversed() {
            guard let id = store.projects.first(where: { $0.name == name })?.id else { continue }
            store.moveProject(id: id, before: store.projects.first?.id)
        }
        return store
    }

    /// `GHOSTTIES_CAPTURE_PROJECT_ORDER`: comma-separated project names.
    static func projectOrder(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - Coordinator seeding (D2)

    /// Far-future output timestamp, so `indicatorState(for:)` keeps reading
    /// "producing output" instead of decaying after the 2s activity window.
    private static let alwaysRecentOutputSecondsAgo = -31_536_000

    /// Seeds the coordinator for every fixture session that is alive, then
    /// copies what the coordinator derives into the store. The Sessions tab
    /// (store cache) and the Projects tab (`coordinator.indicatorState`) then
    /// read one source, as the live app does after each 1Hz tick. Sessions
    /// the coordinator cannot derive a state for (an agent session with no
    /// evidence resolves to `.idle`, never `.waiting`) show what the live app
    /// would show. Not-alive sessions (inactive, error) fall back to the
    /// store's statuses, which `makeStore` already set.
    @MainActor
    static func seedCoordinator(_ coordinator: SessionCoordinator, store: WorkspaceStore) {
        for (fs, session) in zip(fixtureSessions, sessions) {
            switch fs.state {
            case .processing, .longRunning:
                coordinator.seedIndicatorStateForTesting(
                    id: session.id, lastOutputSecondsAgo: alwaysRecentOutputSecondsAgo)
            case .needsAttention:
                coordinator.seedIndicatorStateForTesting(
                    id: session.id, lastSurfaceTitle: "Allow this edit? (y/n)")
            case .waiting, .idle:
                coordinator.seedIndicatorStateForTesting(id: session.id)
            case .inactive, .error:
                continue
            }
            store.updateIndicatorState(id: session.id, state: coordinator.indicatorState(for: session.id))
        }
    }

    // MARK: - Session popover fixture

    /// `GHOSTTIES_CAPTURE_POPOVER` (`needs-bash`, `needs-edit`, `running`, `done`):
    /// force the sidebar session popover open for one fixture session,
    /// without hovering. Nil unless fixture mode is active and the value is
    /// recognised.
    enum PopoverScenario: String {
        case needsBash = "needs-bash"
        case needsEdit = "needs-edit"
        case running
        case done
    }

    static var popoverScenario: PopoverScenario? {
        guard isActive,
              let raw = ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_POPOVER"] else { return nil }
        return PopoverScenario(rawValue: raw)
    }

    /// The fixture session the popover opens over: the row already in the
    /// "needs attention" state for the approval scenarios, the focused
    /// (processing) row for `running`.
    static var popoverTargetSessionId: UUID? {
        switch popoverScenario {
        case .needsBash, .needsEdit: return sessions.first { $0.name == "auth migration" }?.id
        case .running: return sessions.first?.id
        case .done: return sessions.first { $0.name == "flaky ci" }?.id
        case nil: return nil
        }
    }

    /// Invented card content for the target session — never the fixture
    /// project's real temp-directory path or any real session data.
    struct PopoverOverride {
        let approval: ClaudeState?
        var summary: SessionSummary? = nil
        var indicator: SessionIndicatorState? = nil
    }

    static func popoverOverride(for id: UUID) -> PopoverOverride? {
        guard let scenario = popoverScenario, id == popoverTargetSessionId else { return nil }
        func permission(tool: String, input: ToolInputSummary) -> ClaudeState {
            ClaudeState(
                ghosttiesSessionId: id,
                claudeSessionId: "fixture-claude-session",
                cwd: "~/work/dab",
                state: .needsPermission,
                structuredPrompt: StructuredPrompt(toolName: tool, toolUseId: nil, toolInput: input),
                updatedAt: Date()
            )
        }
        switch scenario {
        case .needsBash:
            return PopoverOverride(approval: permission(
                tool: "Bash",
                input: ToolInputSummary(command: "rm -rf build/", description: "Clean stale artifacts before rebuild")
            ))
        case .needsEdit:
            return PopoverOverride(approval: permission(
                tool: "Edit",
                input: ToolInputSummary(description: "Raise the request timeout to 30s", filePath: "src/server/config.ts")
            ))
        case .running:
            return PopoverOverride(approval: nil, summary: SessionSummary(
                prompt: "fix the flaky router tests",
                currentStep: "running npm test"
            ), indicator: .processing)
        case .done:
            return PopoverOverride(approval: nil, summary: SessionSummary(
                prompt: "fix the flaky router tests",
                isDone: true
            ), indicator: .idle)
        }
    }

    /// Optional starting sidebar mode for a capture, from
    /// `GHOSTTIES_CAPTURE_SIDEBAR_MODE` (`pinned`, `collapsed`, `closed`).
    /// The fixture store never persists, so without this every capture
    /// starts pinned and the rail/closed states need synthetic keystrokes.
    private static var initialSidebarMode: SidebarMode? {
        switch ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_SIDEBAR_MODE"] {
        case "pinned": return .pinned
        case "collapsed": return .collapsed
        case "closed": return .closed
        default: return nil
        }
    }

    // MARK: - Launch-state hooks

    // Each hook opens the app straight into a state that otherwise needs a
    // click, by calling the same action that click calls. Agents may never
    // send synthetic input, so these are the only way a headless capture
    // reaches these states. All are nil unless fixture mode is active.
    // Parsing is split out as pure functions so the env-string grammar is
    // unit-testable without launching.

    /// `GHOSTTIES_CAPTURE_COMPOSER`: `open[:delay=<s>]` (the tray "+") or
    /// `prefilled:<project>[:delay=<s>]` (a project row's "+").
    struct ComposerHook: Equatable {
        enum Target: Equatable {
            case open
            case prefilled(projectName: String)
        }
        let target: Target
        /// Seconds after the window appears. The default leaves the window
        /// time to become key; a longer delay makes the open animation
        /// visible in a recording.
        let delay: TimeInterval
        static let defaultDelay: TimeInterval = 1
    }

    /// `GHOSTTIES_CAPTURE_PROJECT_SETTINGS`:
    /// `<project>[:templates-edit|:templates-delete]`.
    struct ProjectSettingsHook: Equatable {
        enum TemplateAction: Equatable {
            case none
            case edit
            case delete
        }
        let projectName: String
        let templateAction: TemplateAction
    }

    static func parseComposerHook(_ raw: String?) -> ComposerHook? {
        guard let raw else { return nil }
        var parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var delay = ComposerHook.defaultDelay
        if let last = parts.last, last.hasPrefix("delay=") {
            guard let seconds = parsePositiveSeconds(String(last.dropFirst("delay=".count))) else { return nil }
            delay = seconds
            parts.removeLast()
        }
        switch parts.count {
        case 1 where parts[0] == "open":
            return ComposerHook(target: .open, delay: delay)
        case 2 where parts[0] == "prefilled" && !parts[1].isEmpty:
            return ComposerHook(target: .prefilled(projectName: parts[1]), delay: delay)
        default:
            return nil
        }
    }

    static func parseProjectSettingsHook(_ raw: String?) -> ProjectSettingsHook? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first, !name.isEmpty else { return nil }
        switch parts.count {
        case 1: return ProjectSettingsHook(projectName: name, templateAction: .none)
        case 2 where parts[1] == "templates-edit": return ProjectSettingsHook(projectName: name, templateAction: .edit)
        case 2 where parts[1] == "templates-delete": return ProjectSettingsHook(projectName: name, templateAction: .delete)
        default: return nil
        }
    }

    /// `GHOSTTIES_CAPTURE_EXPAND_PROJECT=<project>`.
    static func parseExpandProject(_ raw: String?) -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// `GHOSTTIES_CAPTURE_SIDEBAR_TOGGLE_AFTER=<seconds>`.
    static func parseSidebarToggleAfter(_ raw: String?) -> TimeInterval? {
        raw.flatMap(parsePositiveSeconds)
    }

    /// `GHOSTTIES_CAPTURE_MORPH_STEPS=<n>:<holdMs>`: holds the sidebar at
    /// `n` evenly spaced steps of the pinned ⇄ rail morph, 0 through 1, each
    /// for `holdMs` (`WorkspaceViewContainer.applyMorphStep`), so a capture
    /// can screenshot every step without synthetic input. At least 2 steps.
    struct MorphSteps: Equatable {
        let count: Int
        let hold: TimeInterval
    }

    static func parseMorphSteps(_ raw: String?) -> MorphSteps? {
        guard let parts = raw?.split(separator: ":"), parts.count == 2,
              let count = Int(parts[0]), count >= 2,
              let holdMs = Double(parts[1]), holdMs.isFinite, holdMs > 0 else { return nil }
        return MorphSteps(count: count, hold: holdMs / 1000)
    }

    static var morphSteps: MorphSteps? { parseMorphSteps(env("GHOSTTIES_CAPTURE_MORPH_STEPS")) }

    /// `GHOSTTIES_CAPTURE_SIDEBAR_RAIL_CLOSE_PIN_AFTER=<seconds>` — drives
    /// pinned -> rail -> closed -> pinned, one step per interval.
    static func parseSidebarRailClosePinAfter(_ raw: String?) -> TimeInterval? {
        raw.flatMap(parsePositiveSeconds)
    }

    private static func parsePositiveSeconds(_ raw: String) -> TimeInterval? {
        guard let value = Double(raw), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func env(_ key: String) -> String? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment[key]
    }

    static var composerHook: ComposerHook? { parseComposerHook(env("GHOSTTIES_CAPTURE_COMPOSER")) }
    static var projectSettingsHook: ProjectSettingsHook? {
        parseProjectSettingsHook(env("GHOSTTIES_CAPTURE_PROJECT_SETTINGS"))
    }
    static var expandProjectName: String? { parseExpandProject(env("GHOSTTIES_CAPTURE_EXPAND_PROJECT")) }
    static var sidebarRailClosePinAfter: TimeInterval? {
        parseSidebarRailClosePinAfter(env("GHOSTTIES_CAPTURE_SIDEBAR_RAIL_CLOSE_PIN_AFTER"))
    }
    static var sidebarToggleAfter: TimeInterval? {
        parseSidebarToggleAfter(env("GHOSTTIES_CAPTURE_SIDEBAR_TOGGLE_AFTER"))
    }
    /// `GHOSTTIES_CAPTURE_RAIL_REVEAL_AFTER=<seconds>`: on the rail, reveal
    /// the sidebar as a completed hover dwell would (`RailHoverReveal.revealNow`),
    /// so the revealed state can be captured without a pointer. Pair with
    /// `GHOSTTIES_CAPTURE_SIDEBAR_MODE=collapsed`.
    static var railRevealAfter: TimeInterval? {
        env("GHOSTTIES_CAPTURE_RAIL_REVEAL_AFTER").flatMap(parsePositiveSeconds)
    }
    /// `GHOSTTIES_CAPTURE_TRAY_HOVER=<SidebarTrayItem.id>` (e.g. `newSession`):
    /// draws that tray button's hover highlight without a pointer, so the
    /// hovered state can be captured without synthetic input.
    static var trayHoverItemId: String? { env("GHOSTTIES_CAPTURE_TRAY_HOVER").flatMap { $0.isEmpty ? nil : $0 } }
    /// `GHOSTTIES_CAPTURE_BACKGROUND=1`: the capture app never activates
    /// itself (`suppressActivation`), and opens its first window at launch
    /// instead of on first activation (`AppDelegate`), so a capture launched
    /// with `open -g` never takes focus or keystrokes from the app in use.
    static var staysInBackground: Bool { env("GHOSTTIES_CAPTURE_BACKGROUND") == "1" }

    /// Turns every `NSApp.activate(ignoringOtherApps:)` into a no-op for
    /// this process. Called once at launch, only when `staysInBackground`.
    @MainActor static func suppressActivation() {
        guard let original = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.activate(ignoringOtherApps:))),
              let replacement = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.captureBackground_activate(ignoringOtherApps:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    /// `GHOSTTIES_CAPTURE_WINDOW_SIZE=<width>x<height>` (points, e.g.
    /// `900x500`): the content size the first workspace window is set to
    /// once it is up, so a capture can show a short window.
    static var windowContentSize: CGSize? { parseWindowContentSize(env("GHOSTTIES_CAPTURE_WINDOW_SIZE")) }

    static func parseWindowContentSize(_ raw: String?) -> CGSize? {
        guard let parts = raw?.lowercased().split(separator: "x"), parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    /// `GHOSTTIES_CAPTURE_APPEARANCE=light|dark`: the launch value of
    /// `SidebarAppearancePreview`, so a capture can show either glass set
    /// regardless of the terminal theme.
    static var appearancePreview: String? { env("GHOSTTIES_CAPTURE_APPEARANCE") }
    /// `GHOSTTIES_CAPTURE_SIDEBAR_TAB=projects|sessions`: the sidebar tab
    /// for this launch. Set in the process's volatile argument domain, which
    /// outranks the persistent one and is never written to disk, so the
    /// capture shows the tab without touching the Dev app's saved tab.
    static func applySidebarTabOverride() {
        guard isActive, let raw = env("GHOSTTIES_CAPTURE_SIDEBAR_TAB"),
              let tab = SidebarTab(rawValue: raw) else { return }
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["ghostties.sidebarTab"] = tab.rawValue
        // Setting a volatile domain that already exists raises; replace it.
        UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// Each hook fires once per process. The views that host them re-appear
    /// (a rail/pinned toggle remounts the sidebar), and a second firing would
    /// re-select or re-open state the capture didn't ask for.
    @MainActor private static var firedHooks: Set<String> = []
    @MainActor static func claimHook(_ key: String) -> Bool {
        firedHooks.insert(key).inserted
    }

    #endif

    // MARK: - Transcript Script Writer

    /// Writes `script` to a uniquely-named launcher script under
    /// `~/.ghostties/cache/launchers` (the same directory and permissions
    /// the real launch-banner script mechanism already uses — see
    /// `SessionCoordinator.captureFixtureCommand(for:)` and
    /// `createSession`'s banner-script block) and returns its path. Shared
    /// by every surface-creation call site that needs to substitute a
    /// canned transcript for a real shell while fixture mode is active:
    /// `SessionCoordinator.createSession` (session rows) and
    /// `TerminalController.init` (the default/untitled window opened at
    /// cold launch, before any Ghosties project or session is picked).
    /// Falls back to `/bin/true` (an inert, silent no-op) if the write
    /// fails, so a broken fixture never accidentally falls through to a
    /// real shell and leaks real state.
    static func writeTranscriptScript(id: String, script: String) -> String {
        let scriptDir = ("~/.ghostties/cache/launchers" as NSString).expandingTildeInPath
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptDir) {
            try? fm.createDirectory(atPath: scriptDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700,
            ])
        }
        let scriptPath = (scriptDir as NSString).appendingPathComponent("capture-fixture-\(id).sh")
        guard (try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil else {
            return "/bin/true"
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        return scriptPath
    }

    // MARK: - Canned Terminal Transcripts

    /// The script a fixture session's terminal runs: that session's own
    /// transcript from `sessionTranscripts`, so selecting a different row
    /// shows a different terminal. Any session the fixture didn't seed (one
    /// created during a capture) gets `newSessionTranscript`.
    static func transcriptScript(forSessionId id: UUID?) -> String {
        #if DEBUG
        if let id, let name = sessions.first(where: { $0.id == id })?.name,
           let body = sessionTranscripts[name] {
            return script(body)
        }
        #endif
        return script(newSessionTranscript)
    }

    /// The cold-launch window shows the focused fixture session's transcript,
    /// so the terminal matches the row the sidebar marks selected.
    static var defaultWindowTranscriptScript: String {
        #if DEBUG
        return transcriptScript(forSessionId: focusedSessionId)
        #else
        return script(newSessionTranscript)
        #endif
    }

    static func script(_ body: String) -> String {
        "#!/bin/zsh\nclear\n" + banner + "printf '\\n'\n" + body + "printf '\\n'\nexec cat > /dev/null\n"
    }

    /// `printf` lines for a bold box. Padding is computed from each row's
    /// `plain` (visible) text, so every row is the same cell width whatever
    /// escapes `styled` carries. Rows must not contain `'` or `%`.
    static func boxLines(_ rows: [(plain: String, styled: String)], minWidth: Int = 0) -> String {
        let inner = max(minWidth, rows.map(\.plain.count).max() ?? 0)
        let rule = String(repeating: "─", count: inner + 2)
        var out = #"printf '\033[1m╭"# + rule + #"╮\033[0m\n'"# + "\n"
        for row in rows {
            let pad = String(repeating: " ", count: inner - row.plain.count)
            out += #"printf '\033[1m│\033[0m "# + row.styled + pad + #" \033[1m│\033[0m\n'"# + "\n"
        }
        out += #"printf '\033[1m╰"# + rule + #"╯\033[0m\n'"# + "\n"
        return out
    }

    private static let banner = boxLines(
        [(plain: "✻ Claude Code", styled: #"\033[35m✻\033[0m\033[1m Claude Code\033[0m"#)],
        minWidth: 39
    )

    /// A session the fixture didn't seed: an empty Claude Code prompt.
    static let newSessionTranscript = #"""
        printf '\033[2m  Try "fix the flaky test in dispatch"\033[0m\n'

        """#

    /// One canned transcript per fixture session (all 11), keyed by session name
    /// (fixture names are unique). Invented engineering work scoped to each
    /// fixture project; no real hostname or path, links only under
    /// github.com/example. Each fits a 1280x705pt window without scrolling
    /// the banner away. A live state ends mid-work, a done one ends on the
    /// result, the needs-you one ends on a permission prompt.
    static let sessionTranscripts: [String: String] = [
        "reconnect race": #"""
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
            printf '\033[35m⏺\033[0m Write(sync/reconnect_test.go)\n'
            printf '  \033[2m⎿  Wrote 38 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go test ./sync/... -run TestReconnect -race -v)\n'
            printf '  \033[2m⎿  === RUN   TestReconnect_ConcurrentSend\033[0m\n'
            printf '\n'
            printf '\033[35m✻ Running tests…\033[0m \033[2m(14s · esc to interrupt)\033[0m\n'

            """#,
        "rate limiter": #"""
            printf '\033[1m> \033[0mAdd a token-bucket rate limiter to the public API, 100 requests a minute per key\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Search(pattern: "func .*Middleware", path: "middleware/")\n'
            printf '  \033[2m⎿  Found 4 matches across 3 files\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Read(middleware/chain.go)\n'
            printf '  \033[2m⎿  Read 64 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Plan: a per-key token bucket in middleware/ratelimit.go, refilled\n'
            printf '  lazily on each request and wired in after auth, so the key is\n'
            printf '  already resolved. An empty bucket answers 429 with Retry-After.\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Write(middleware/ratelimit.go)\n'
            printf '  \033[2m⎿  Wrote 71 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(middleware/ratelimit.go)\n'
            printf '  \033[2m⎿  Updated middleware/ratelimit.go with 5 additions and 1 removal\033[0m\n'
            printf '  \033[2m     28\033[0m   func (l *Limiter) Allow(key string) bool {\n'
            printf '  \033[2m29\033[0m \033[31m-\033[0m    b := l.buckets[key]\n'
            printf '  \033[2m29\033[0m \033[32m+\033[0m    l.mu.Lock()\n'
            printf '  \033[2m30\033[0m \033[32m+\033[0m    defer l.mu.Unlock()\n'
            printf '  \033[2m31\033[0m \033[32m+\033[0m    b, ok := l.buckets[key]\n'
            printf '  \033[2m32\033[0m \033[32m+\033[0m    if !ok {\n'
            printf '  \033[2m33\033[0m \033[32m+\033[0m        b = newBucket(l.rate, l.burst)\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(middleware/chain.go)\n'
            printf '\n'
            printf '\033[35m✻ Editing…\033[0m \033[2m(6s · esc to interrupt)\033[0m\n'

            """#,
        "flaky ci": #"""
            printf '\033[1m> \033[0mTestDispatch_Timeout fails about 1 in 10 CI runs. Find out why and fix it\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go test ./dispatch/... -run TestDispatch_Timeout -count=50)\n'
            printf '  \033[2m⎿  --- FAIL: TestDispatch_Timeout (0.21s)\033[0m\n'
            printf '  \033[2m       dispatch_test.go:88: expected ErrTimeout, got <nil>\033[0m\n'
            printf '  \033[2m   FAIL  4 of 50 runs\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m The test sleeps 200ms and expects a 200ms timeout to have fired.\n'
            printf '  On a loaded runner the timer and the sleep race. It needs a clock\n'
            printf '  the test controls, not wall time.\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(dispatch/dispatch.go)\n'
            printf '  \033[2m⎿  Updated dispatch/dispatch.go with 3 additions and 2 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(dispatch/dispatch_test.go)\n'
            printf '  \033[2m⎿  Updated dispatch/dispatch_test.go with 9 additions and 4 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go test ./dispatch/... -run TestDispatch_Timeout -count=500)\n'
            printf '  \033[2m⎿  ok      switchboard/dispatch    1.904s\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(gh workflow run ci.yml --ref fix/dispatch-clock)\n'
            printf '  \033[2m⎿  \033[0m\033[32m✓\033[0m\033[2m ci #812   \033[0m\033[32m✓\033[0m\033[2m ci #813   \033[0m\033[32m✓\033[0m\033[2m ci #814\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Fixed. Dispatch now takes a Clock, and the test advances a fake\n'
            printf '  clock past the deadline instead of sleeping.\n'
            printf '  CI green on 3 consecutive runs.\n'

            """#,
        "deps bump": #"""
            printf '\033[1m> \033[0mBump our Go dependencies, minor versions only, and make sure tests pass\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go list -m -u all)\n'
            printf '  \033[2m⎿  github.com/example/pgx v1.14.2 [v1.15.0]\033[0m\n'
            printf '  \033[2m   github.com/example/zap v1.26.0 [v1.27.1]\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go get -u ./... && go mod tidy)\n'
            printf '  \033[2m⎿  go: upgraded github.com/example/pgx v1.14.2 => v1.15.0\033[0m\n'
            printf '  \033[2m   go: upgraded github.com/example/zap v1.26.0 => v1.27.1\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go test ./...)\n'
            printf '  \033[2m⎿  ok      switchboard/api         0.512s\033[0m\n'
            printf '  \033[2m   ok      switchboard/dispatch    0.204s\033[0m\n'
            printf '  \033[2m   ok      switchboard/sync        0.331s\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bumped pgx to v1.15.0 and zap to v1.27.1. All tests pass.\n'

            """#,
        "offline sync": #"""
            printf '\033[1m> \033[0mEdits queued offline overwrite newer server changes on reconnect. Fix it\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Read(sync/queue.ts)\n'
            printf '  \033[2m⎿  Read 188 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m The queue replays edits blindly. Each edit needs the server revision\n'
            printf '  it was based on, so a stale edit can be detected and merged.\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(sync/queue.ts)\n'
            printf '  \033[2m⎿  Updated sync/queue.ts with 14 additions and 3 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Write(sync/resolve.ts)\n'
            printf '  \033[2m⎿  Wrote 52 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(npm test -- sync)\n'
            printf '  \033[2m⎿  PASS  sync/queue.test.ts (9 tests)\033[0m\n'
            printf '  \033[2m   PASS  sync/resolve.test.ts (6 tests)\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(gh pr create --title "fix: resolve offline edit conflicts by revision")\n'
            printf '  \033[2m⎿  https://github.com/example/fieldwork/pull/88\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Done. Stale edits now carry their base revision. Field-level changes\n'
            printf '  merge; a true conflict keeps the server value and flags the edit.\n'

            """#,
        "auth migration": #"""
            printf '\033[1m> \033[0mMove session storage from the sessions table to signed JWTs\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Read(migrations/0041_sessions_index.sql)\n'
            printf '  \033[2m⎿  Read 12 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Write(migrations/0042_sessions_to_jwt.sql)\n'
            printf '  \033[2m⎿  Wrote 27 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(auth/session.go)\n'
            printf '  \033[2m⎿  Updated auth/session.go with 31 additions and 18 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(go test ./auth/...)\n'
            printf '  \033[2m⎿  ok      atlas-api/auth    0.418s\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Code and tests are ready. Next, apply the migration to the local\n'
            printf '  database.\n'
            printf '\n'

            """# + boxLines([
                (plain: "Bash command", styled: #"\033[1mBash command\033[0m"#),
                (plain: "", styled: ""),
                (plain: "  psql -f migrations/0042_sessions_to_jwt.sql", styled: "  psql -f migrations/0042_sessions_to_jwt.sql"),
                (plain: "  Apply migration 0042: move sessions to JWT", styled: #"\033[2m  Apply migration 0042: move sessions to JWT\033[0m"#),
                (plain: "", styled: ""),
                (plain: "Do you want to proceed?", styled: "Do you want to proceed?"),
                (plain: "❯ 1. Yes", styled: #"\033[36m❯ 1. Yes\033[0m"#),
                (plain: "  2. Yes, and do not ask again for psql commands", styled: "  2. Yes, and do not ask again for psql commands"),
                (plain: "  3. No, and tell Claude what to do differently (esc)", styled: "  3. No, and tell Claude what to do differently (esc)"),
            ]),
        "chart polish": #"""
            printf '\033[1m> \033[0mTighten the axis labels on the latency chart and fix the legend overlap\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(src/charts/LatencyChart.tsx)\n'
            printf '  \033[2m⎿  Updated src/charts/LatencyChart.tsx with 5 additions and 3 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(npm test -- LatencyChart)\n'
            printf '  \033[2m⎿  PASS  src/charts/LatencyChart.test.tsx (4 tests)\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Axis labels now use compact units (1.2k, 340ms) and the legend sits\n'
            printf '  below the plot, clear of the p99 line.\n'

            """#,
        "docs pass": #"""
            printf '\033[1m> \033[0mThe README install steps are out of date. Update them for v2\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Edit(README.md)\n'
            printf '  \033[2m⎿  Updated README.md with 11 additions and 14 removals\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Install now takes one command, and the old config migration\n'
            printf '  steps moved to docs/upgrading.md.\n'

            """#,
        "build fix": #"""
            printf '\033[1m> \033[0mThe release build fails on the asset step. Fix it\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(make release)\n'
            printf '  \033[2m⎿  \033[0m\033[31merror: assets/manifest.json: unexpected end of JSON input\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Read(assets/manifest.json)\n'
            printf '  \033[2m⎿  Read 0 lines\033[0m\n'
            printf '\n'
            printf '\033[31mProcess exited with code 1\033[0m\n'

            """#,
        "release notes": #"""
            printf '\033[1m> \033[0mDraft release notes for v1.8 from the merged PRs\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(gh pr list --state merged --base main --limit 30)\n'
            printf '  \033[2m⎿  23 pull requests\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Write(CHANGELOG.md)\n'
            printf '  \033[2m⎿  Wrote 19 lines\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Drafted v1.8: 4 features, 9 fixes, grouped by area.\n'

            """#,
        "icon pass": #"""
            printf '\033[1m> \033[0mExport the new toolbar icons at 1x and 2x\n'
            printf '\n'
            printf '\033[35m⏺\033[0m Bash(npm run icons)\n'
            printf '  \033[2m⎿  Exported 24 icons to public/icons\033[0m\n'
            printf '\n'
            printf '\033[35m⏺\033[0m All 12 toolbar icons exported at 1x and 2x.\n'

            """#,
    ]
}

#if DEBUG
extension NSApplication {
    /// `CaptureFixture.suppressActivation`: activation does nothing.
    @objc fileprivate func captureBackground_activate(ignoringOtherApps flag: Bool) {}
}
#endif
