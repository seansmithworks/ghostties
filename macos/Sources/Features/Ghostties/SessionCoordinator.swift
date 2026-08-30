import AppKit
import Combine
import SwiftUI
import GhosttyKit
import GhosttiesCore

/// Bridges the SwiftUI sidebar to Ghostty's terminal surface system.
///
/// Sessions work like **vertical tabs**: each session owns a terminal surface tree
/// (which may contain splits), and the sidebar switches which tree occupies the
/// terminal area. Only one session is visible at a time. Background sessions keep
/// their processes running — the coordinator holds strong references to their trees.
///
/// When the user creates splits via Ghostty shortcuts (Cmd+D), those splits live in
/// the controller's `surfaceTree`. Before switching sessions, we snapshot the current
/// tree back into `sessionTrees` so splits are preserved across switches.
///
/// Each window gets its own coordinator instance, injected via `.environmentObject()`.
/// The coordinator discovers its window controller lazily through the view hierarchy.
@MainActor
final class SessionCoordinator: ObservableObject {
    private let ghostty: Ghostty.App?

    /// Weak reference to the container NSView — used to find the window controller.
    weak var containerView: NSView?

    /// Session-hybrid: set by `WorkspaceViewContainer` after init. When present,
    /// terminal session lifecycle events (spawn, close) create/GC `SessionDraft`
    /// rows in the sidebar's ACTIVE zone. Nil during tests or legacy-only code
    /// paths — guards everywhere tolerate absence.
    weak var sessionDraftStore: SessionDraftStore?

    /// The currently displayed session. Nil before any session is created.
    @Published private(set) var activeSessionId: UUID?

    /// Maps session IDs to their full split trees. Trees are kept alive here even
    /// when not displayed — this preserves both the surfaces and any user-created
    /// splits. The active session's tree may be stale (the controller owns the
    /// live version); call `snapshotActiveTree()` to sync before reading.
    private(set) var sessionTrees: [UUID: SplitTree<Ghostty.SurfaceView>] = [:]

    /// Browser tab managers for browser-kind sessions. A session is either in
    /// sessionTrees (terminal) OR browserManagers (browser), never both.
    private(set) var browserManagers: [UUID: BrowserTabManager] = [:]

    /// Every session ID that has ever had a live surface (terminal tree or
    /// browser manager) during this process's lifetime. Inserted into wherever
    /// a `sessionTrees` or `browserManagers` entry is first established; never
    /// removed — not on close, not on `clearRuntime`, not on surface teardown.
    /// In-memory only, never persisted to `workspace.json`: it resets naturally
    /// on relaunch, which is the desired semantics. Distinguishes a
    /// stopped-this-launch session (INACTIVE) from one restored from disk that
    /// never started this launch (ARCHIVE) — see `RecentsListView`.
    private(set) var sessionIdsStartedThisLaunch: Set<UUID> = []

    /// Bridges CEF callbacks to the browser UI. Keyed by session ID.
    private var browserBridges: [UUID: BrowserSessionBridge] = [:]

    /// Per-window runtime status. Views should prefer `WorkspaceStore.shared.globalStatuses`
    /// for cross-window visibility; this local copy is kept for backward compatibility.
    @Published private(set) var statuses: [UUID: SessionStatus] = [:]

    /// Cache resolved command paths to avoid repeated shell spawns.
    /// Guarded by `resolvedPathsLock` since `resolveCommand` runs on detached tasks.
    /// `nonisolated(unsafe)` opts out of @MainActor isolation so the nonisolated
    /// `resolveCommand` method can access these; the lock provides actual safety.
    nonisolated(unsafe) private static let resolvedPathsLock = NSLock()
    nonisolated(unsafe) private static var _resolvedPaths: [String: String] = [:]

    /// Tracks the last focused session per project per window, so clicking a
    /// project in the icon rail can restore the correct terminal session.
    private(set) var lastActiveSessionPerProject: [UUID: UUID] = [:]

    /// Tracks when each session last produced output (title change as proxy).
    /// Used with the activity threshold to distinguish active vs waiting.
    private var lastOutputTimestamps: [UUID: ContinuousClock.Instant] = [:]

    /// Combine subscriptions for each session's root surface `$lastOutputDate`.
    private var outputSubscriptions: [UUID: AnyCancellable] = [:]

    /// Exit codes received from `GHOSTTY_ACTION_COMMAND_FINISHED` before the surface closes.
    /// Keyed by surface ID (not session ID) since the notification targets a surface.
    private var pendingExitCodes: [UUID: Int16] = [:]

    /// 1-second timer that triggers view re-evaluation for activity state transitions.
    private var activityTimer: Timer?

    /// How long after the last output before a running session transitions from processing.
    private static let activityThreshold: ContinuousClock.Duration = .seconds(2)

    /// Whether each session is currently at a shell prompt (OSC 133;B received).
    /// Reset to false on any output activity. Used to distinguish idle vs waiting.
    private var isAtPrompt: [UUID: Bool] = [:]

    /// The last surface title seen for each session. Used as a proxy for the last
    /// terminal output line when detecting "needs attention" prompts.
    private var lastSurfaceTitle: [UUID: String] = [:]

#if DEBUG
    /// Test-only override for `isAgentKindSession`'s store lookup, so tests
    /// can exercise the agent-kind branch of `indicatorState(for:)` against
    /// an isolated `WorkspaceStore` instead of `WorkspaceStore.shared` (which
    /// persists to the real `workspace.json`). nil in production.
    var agentKindLookupStoreForTesting: WorkspaceStore?

    /// Test-only override for `claudeStateStore`, so tests can point this
    /// coordinator at a temp-directory `ClaudeStateStore` instead of
    /// `.shared` (which reads/writes the real `~/.ghostties/state/`, where
    /// live sessions are writing right now). nil in production.
    var claudeStateStoreForTesting: ClaudeStateStore?
#endif

    /// The `ClaudeStateStore` this coordinator reads/writes. Always
    /// `.shared` in production; overridable in DEBUG builds via
    /// `claudeStateStoreForTesting` so tests never touch the real
    /// `~/.ghostties/state/`.
    private var claudeStateStore: ClaudeStateStore {
#if DEBUG
        claudeStateStoreForTesting ?? .shared
#else
        .shared
#endif
    }

    /// Per-session Combine subscription for Claude Code → sidebar name sync.
    /// Subscribes directly to `surface.$title` (see `subscribeNameSync`) —
    /// `@Published` only ever emits a settled value (`SurfaceView_AppKit`'s
    /// title-coalescing timer is the sole writer), so there is no
    /// sampling-at-fire-time problem to solve, unlike the deleted
    /// `TrailingEdgeDebouncer`. `removeDuplicates()` is what actually fixes
    /// the starvation bug that debounce had: Claude Code re-emits an
    /// identical OSC 2 title on every render frame (see
    /// `src/termio/stream_handler.zig:995-1029`, which — unlike
    /// `setMouseShape` two lines below it — does no dedupe), so without
    /// `removeDuplicates()` a debounce/throttle downstream never sees a quiet
    /// window during sustained activity. `throttle(latest: true)` gives
    /// leading-edge (name updates the moment a new title appears after a
    /// quiet spell) plus trailing-edge (the final title of a burst still
    /// lands), bounded to one write per `nameSyncThrottle` while titles are
    /// actively changing.
    private var nameSyncSubscriptions: [UUID: AnyCancellable] = [:]

    /// How often the sidebar name may update while titles are actively
    /// changing (throttle window). Not a "must go quiet" wait — see
    /// `nameSyncSubscriptions` above.
    static let nameSyncThrottle: TimeInterval = 5

    /// When each session entered the processing state (continuous output).
    /// Cleared when the session returns to a prompt. Used for long-running detection.
    private var processingStartTimes: [UUID: ContinuousClock.Instant] = [:]

    /// Last-published indicator state snapshot per session. The activity timer
    /// compares against this cache and suppresses objectWillChange when nothing changed.
    private var cachedIndicatorStates: [UUID: SessionIndicatorState]? = nil

    /// How long a session must be continuously processing before showing as long-running.
    private static let longRunningThreshold: ContinuousClock.Duration = .seconds(1800)

    /// Known prompt patterns for detecting "needs attention" state.
    private static let promptPatterns: [String] = [
        "\\[Y/n\\]", "\\[y/N\\]", "\\[yes/no\\]",
        "Allow\\s", "Do you want", "Press Enter",
        "Confirm", "approve", "permission",
        "\\(y\\)", "\\(yes\\)",
    ]

    init(ghostty: Ghostty.App) {
        self.ghostty = ghostty
        observeLifecycle()
        observeProjectRemoval()
        observeCommandFinished()
        observePromptReady()
        observeMenuBarFocus()
        startActivityTimer()
    }

    #if DEBUG
    /// Testing stub — no GhosttyKit dependency, observers not started.
    init() {
        self.ghostty = nil
    }
    #endif

    // MARK: - Session Creation

    /// Create a new terminal session from a template within a project.
    ///
    /// Resolves the command path off the main thread (with a 3-second timeout),
    /// then creates a Ghostty surface and makes it the sole occupant of the
    /// terminal area. The previous session's tree is snapshotted before the switch.
    @discardableResult
    func createSession(
        session: AgentSession,
        template: AgentTemplate,
        project: Project,
        sourceTaskId: String? = nil,
        sourceTaskFilePath: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) async -> Bool {
        // Browser sessions bypass the terminal path entirely.
        if template.kind == .browser {
            return createBrowserSession(session: session, template: template, project: project)
        }

        guard let ghosttyApp = ghostty?.app else { return false }

        // Build the full command string and resolve the binary path, both off
        // the main thread. buildCommand() may write prompt cache files and
        // resolveCommand() may spawn a login shell — neither should block UI.
        // For shell templates (no command), resolvedCommand stays nil -> default shell.
        let resolvedCommand: String? = await {
            guard template.command != nil else { return nil }

            let buildAndResolveTask = _Concurrency.Task.detached(priority: .userInitiated) { () -> String? in
                // Build the full command string (includes agent flags, prompt file references).
                let built = template.buildCommand()
                guard !built.isEmpty else { return nil }

                // Extract the base command (first token) for PATH resolution.
                let baseCommand = String(built.prefix(while: { !$0.isWhitespace }))
                let resolvedBase = Self.resolveCommand(baseCommand)

                // Replace the base command with its resolved absolute path.
                if resolvedBase != baseCommand {
                    return resolvedBase + built.dropFirst(baseCommand.count)
                }
                return built
            }
            let timeoutTask = _Concurrency.Task {
                try await _Concurrency.Task.sleep(for: .seconds(3))
                buildAndResolveTask.cancel()
            }
            let result = await buildAndResolveTask.value
            timeoutTask.cancel()
            return result
        }()

        // For agent templates, write a wrapper script that prints a banner
        // then exec's into the real command. Direct `&&` chaining breaks because
        // Ghostty wraps the command with `exec -l`, which replaces the process
        // before the second command runs.
        let finalCommand: String? = {
            guard let cmd = resolvedCommand else { return nil }
            guard let banner = template.launchBanner else { return cmd }

            let scriptDir = Self.launcherScriptDir
            let fm = FileManager.default
            if !fm.fileExists(atPath: scriptDir) {
                try? fm.createDirectory(atPath: scriptDir, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o700,
                ])
            }
            let scriptPath = (scriptDir as NSString).appendingPathComponent("\(session.id.uuidString).sh")
            // Spawn banner: first output line confirms task context before Claude starts.
            // Uses env vars set in config.environmentVariables so they're already in scope.
            let spawnBannerEcho = #"echo "task: $GHOSTTIES_TASK_ID · file: $GHOSTTIES_TASK_FILE · cwd: $(pwd)""#
            let script = "#!/bin/zsh -l\n. ~/.zshrc 2>/dev/null\n\(banner)\n\(spawnBannerEcho)\nexec \(cmd)\n"
            if (try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil {
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
                return scriptPath
            }
            return cmd // fallback: skip banner
        }()

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = template.workingDirectory ?? project.rootPath
        config.command = finalCommand
        config.environmentVariables = Self.spawnEnvironment(
            template: template,
            taskFilePath: sourceTaskFilePath,
            taskId: sourceTaskId,
            extra: extraEnvironment,
            sessionId: session.id
        )

        let newView = Ghostty.SurfaceView(ghosttyApp, baseConfig: config)
        let newTree = SplitTree(view: newView)

        // Snapshot the outgoing session's tree (captures any user-created splits).
        snapshotActiveTree()

        sessionTrees[session.id] = newTree
        sessionIdsStartedThisLaunch.insert(session.id)
        setStatus(.running, for: session.id)
        subscribeToOutput(surface: newView, sessionId: session.id)
        activeSessionId = session.id
        lastActiveSessionPerProject[session.projectId] = session.id

        // Session-hybrid: register an anonymous draft row in the sidebar
        // unless the spawn originated from an existing task (which already
        // owns its own row). The cwd is captured at spawn time — later cwd
        // changes inside the shell don't update the draft.
        if sourceTaskId == nil, let store = sessionDraftStore {
            let cwd = template.workingDirectory ?? project.rootPath
            let draft = store.register(cwd: cwd, terminalSessionId: session.id)
            _ = draft
        }
        // Stamp creation as activity so the project surfaces in `.recent`
        // (or `.activeNow` once the surface produces output) right away.
        // isOutput: true — a fresh session (including a relaunch reusing the
        // same persisted `AgentSession`) must not keep a stale prior
        // `lastOutputAt`. Without this, `displayTimestamp` would prefer that
        // stale value over the brand-new `lastActiveAt` and the row would
        // show yesterday's timestamp for a session that's live right now.
        WorkspaceStore.shared.recordActivity(
            sessionId: session.id,
            projectId: session.projectId,
            isOutput: true
        )

        showSession(newTree, focusView: newView)

        // Sidebar smart-sections (plan unit 4): session creation / relaunch is a
        // user action and a fresh layout commit point. Release any held freeze
        // snapshot so the parent project re-buckets on the next sidebar read.
        // Coexists with `WorkspaceStore.addSession`'s release call — both are
        // idempotent (release-while-unfrozen is a no-op).
        WorkspaceStore.shared.releaseSnapshot()
        return true
    }

    /// Create a session using the project's default or specified template with auto-generated naming.
    ///
    /// Shared helper used by ProjectDisclosureRow, WorkspaceSidebarView, and TemplatePickerView
    /// to avoid duplicating session-creation logic.
    @discardableResult
    func createQuickSession(
        for project: Project,
        template: AgentTemplate,
        sourceTaskId: String? = nil,
        sourceTaskFilePath: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) async -> Bool {
        let store = WorkspaceStore.shared
        let count = store.sessions(for: project.id).count
        let name = "\(template.name) \(count + 1)"
        let session = store.addSession(name: name, templateId: template.id, projectId: project.id)
        return await createSession(
            session: session,
            template: template,
            project: project,
            sourceTaskId: sourceTaskId,
            sourceTaskFilePath: sourceTaskFilePath,
            extraEnvironment: extraEnvironment
        )
    }

    // MARK: - Browser Sessions

    /// Create a browser session. Instead of a Ghostty surface, this initializes CEF
    /// and shows a browser panel in the terminal area.
    private func createBrowserSession(
        session: AgentSession,
        template: AgentTemplate,
        project: Project
    ) -> Bool {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else { return false }

        let manager = BrowserTabManager()
        let tab = manager.createTab(url: "https://www.google.com")

        let browserView = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                                         url: tab.url)
        manager.registerBrowserView(browserView, for: tab.id)

        let bridge = BrowserSessionBridge(
            sessionId: session.id,
            tabManager: manager
        )
        browserView.delegate = bridge
        bridge.activeTabId = tab.id
        browserBridges[session.id] = bridge

        snapshotActiveTree()

        browserManagers[session.id] = manager
        sessionIdsStartedThisLaunch.insert(session.id)
        setStatus(.running, for: session.id)
        activeSessionId = session.id
        lastActiveSessionPerProject[session.projectId] = session.id
        // Stamp creation as activity so the project surfaces in `.recent`
        // right away (browser sessions don't emit terminal output events).
        // isOutput: true — browser sessions never fire `lastOutputSubject` at
        // all, so without this `lastOutputAt` would stay nil for the
        // session's entire life while focus kept moving `lastActiveAt`; the
        // row's `displayTimestamp` would then read stale/nil forever instead
        // of tracking real recency. Also covers browser relaunch reusing a
        // stale persisted `lastOutputAt` — same reasoning as the terminal
        // creation site above.
        WorkspaceStore.shared.recordActivity(
            sessionId: session.id,
            projectId: session.projectId,
            isOutput: true
        )

        showBrowserInContainer(manager)

        // Sidebar smart-sections (plan unit 4): browser-session creation is a
        // structural change too — release any held freeze snapshot.
        WorkspaceStore.shared.releaseSnapshot()
        return true
    }

    /// Whether a session is a browser session (not a terminal session).
    func isSessionBrowser(_ id: UUID) -> Bool {
        browserManagers[id] != nil
    }

    /// Returns the bridge for a given browser tab manager, if one exists.
    func bridge(for manager: BrowserTabManager) -> BrowserSessionBridge? {
        browserBridges.values.first { $0.tabManager === manager }
    }

    /// Show the given browser manager's content in the workspace container.
    private func showBrowserInContainer(_ manager: BrowserTabManager) {
        guard let container = containerView as? WorkspaceViewContainer else { return }
        container.showBrowserContent(manager, bridge: browserBridges.values.first {
            $0.tabManager === manager
        })
    }

    /// Restore the terminal display in the workspace container.
    private func showTerminalInContainer() {
        guard let container = containerView as? WorkspaceViewContainer else { return }
        container.showTerminalContent()
    }

    // MARK: - Session Switching

    /// Switch the terminal area to show a specific session.
    ///
    /// Snapshots the current session's tree (preserving splits) before switching.
    /// This is the "vertical tab" behavior — clicking a session in the sidebar
    /// replaces the terminal content with the target session's full split tree.
    func focusSession(id: UUID) {
        // Browser session path.
        if let manager = browserManagers[id] {
            snapshotActiveTree()
            activeSessionId = id
            showBrowserInContainer(manager)
            if let session = WorkspaceStore.shared.sessions.first(where: { $0.id == id }) {
                lastActiveSessionPerProject[session.projectId] = id
                // Focus counts as a touch — refresh activity so the project
                // stays in `.recent`/`.activeNow` instead of demoting to `.all`.
                WorkspaceStore.shared.recordActivity(
                    sessionId: id,
                    projectId: session.projectId
                )
            }
            return
        }

        guard let tree = sessionTrees[id] else { return }

        // Snapshot the outgoing session's tree first.
        snapshotActiveTree()

        activeSessionId = id
        // Restore terminal display if coming from a browser session.
        showTerminalInContainer()
        showSession(tree, focusView: tree.first)

        // Record this session as the last active one for its project.
        if let session = WorkspaceStore.shared.sessions.first(where: { $0.id == id }) {
            lastActiveSessionPerProject[session.projectId] = id
            // Focus counts as a touch — refresh activity so the project stays
            // in `.recent`/`.activeNow` instead of demoting to `.all`.
            WorkspaceStore.shared.recordActivity(
                sessionId: id,
                projectId: session.projectId
            )
        }
    }

    /// Task-row-click entry point: focus the project's last-active session if
    /// one exists, otherwise spawn a fresh shell session rooted at `rootPath`.
    ///
    /// Resolution order:
    ///   1. If a `Project` already exists in `WorkspaceStore` with `name`,
    ///      reuse it (its `rootPath` wins — don't clobber the user's setup).
    ///   2. Otherwise auto-register a new, unpinned `Project(name:, rootPath:)`
    ///      — this is a background registration, not an explicit "add
    ///      project" action, so it must not force the pinned section.
    ///   3. If that project already has a live session, focus it (same path as
    ///      `focusLastSession(forProject:)`).
    ///   4. Else spawn a new Shell session via `createQuickSession`. The
    ///      spawn is async — fire and forget. The terminal area flips to the
    ///      new session when GhosttyKit finishes initializing (~500ms cold).
    ///
    /// Silently no-ops on the spawn path if no shell template is available
    /// (shouldn't happen — `AgentTemplate.shell` ships as a default).
    ///
    /// The `.ghostties/tasks/*.md` file is opened by the caller
    /// (`TaskRowView.handleTap`) before we get here; this method owns only
    /// the terminal side of "click = start working".
    ///
    /// `templateName` (optional) is matched case-insensitively against
    /// `WorkspaceStore.templates[*].name`. Unresolved names log to stderr
    /// and fall back to the project default / built-in Shell.
    func startOrFocusSession(
        forProjectNamed name: String,
        rootPath: String,
        templateName: String? = nil,
        sourceTaskId: String? = nil,
        sourceTaskFilePath: String? = nil,
        extraEnvironment: [String: String] = [:],
        forceSpawn: Bool = false
    ) {
        let store = WorkspaceStore.shared

        // 1/2. Resolve or register the project. `addProject(at:)` handles
        // duplicate-path detection without clobbering an existing record's
        // `rootPath` or ghost character.
        let project: Project = {
            if let existing = store.projects.first(where: { $0.name == name }) {
                return existing
            }
            // Auto-register unpinned — this is a background/implicit
            // registration, not an explicit user "add project" action, so it
            // must not force the project into the pinned sidebar section.
            // `addProject(at:)` does the standardization.
            let url = URL(fileURLWithPath: rootPath, isDirectory: true)
            store.addProject(at: url)
            // Re-fetch by path (name may diverge — URL.lastPathComponent
            // becomes the display name on fresh register).
            let stdPath = url.standardizedFileURL.path
            return store.projects.first(where: { $0.rootPath == stdPath })
                ?? store.projects.last!   // addProject guarantees at least one match
        }()

        // 3. Focus the existing live session if there is one — unless the caller
        //    explicitly wants a fresh spawn (e.g. task row click always creates a
        //    new Claude session rather than recycling an existing shell).
        if !forceSpawn {
            if let lastId = lastActiveSessionPerProject[project.id],
               sessionTrees[lastId] != nil || browserManagers[lastId] != nil {
                focusSession(id: lastId)
                return
            }
            let projectSessions = store.sessions(for: project.id)
            if let running = projectSessions.first(where: {
                sessionTrees[$0.id] != nil || browserManagers[$0.id] != nil
            }) {
                focusSession(id: running.id)
                return
            }
        }

        // 4. No live session — resolve template, then spawn.
        //    Resolution chain:
        //      a. explicit `templateName` arg (from task frontmatter or user pref)
        //      b. project.defaultTemplateId
        //      c. built-in Shell
        //    If (a) is non-nil but no match is found, log and fall through to (b)/(c).
        let fallbackTemplate: AgentTemplate? = {
            if let defaultId = project.defaultTemplateId,
               let t = store.templates.first(where: { $0.id == defaultId }) {
                return t
            }
            return store.templates.first(where: { $0.id == AgentTemplate.shell.id })
                ?? store.templates.first(where: { $0.kind == .shell })
        }()

        let resolvedTemplate: AgentTemplate? = {
            guard let requested = templateName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !requested.isEmpty else {
                return fallbackTemplate
            }
            let needle = requested.lowercased()
            if let match = store.templates.first(where: {
                $0.name.lowercased() == needle
            }) {
                return match
            }
            FileHandle.standardError.write(Data(
                "⚠️ Ghostties: template '\(requested)' not found; falling back to default\n".utf8
            ))
            return fallbackTemplate
        }()

        guard let template = resolvedTemplate else { return }

        _Concurrency.Task { @MainActor in
            await self.createQuickSession(
                for: project,
                template: template,
                sourceTaskId: sourceTaskId,
                sourceTaskFilePath: sourceTaskFilePath,
                extraEnvironment: extraEnvironment
            )
        }
    }

    /// Focus the last active session for a given project, or the first running session if none.
    ///
    /// Called when the user clicks a project in the icon rail to auto-switch the terminal
    /// to the most recently used session in that project.
    func focusLastSession(forProject projectId: UUID) {
        // Try the remembered session first.
        if let lastId = lastActiveSessionPerProject[projectId],
           sessionTrees[lastId] != nil || browserManagers[lastId] != nil {
            focusSession(id: lastId)
            return
        }

        // Fall back to the first running session in this project.
        let projectSessions = WorkspaceStore.shared.sessions(for: projectId)
        if let running = projectSessions.first(where: {
            sessionTrees[$0.id] != nil || browserManagers[$0.id] != nil
        }) {
            focusSession(id: running.id)
        }
    }

    // MARK: - Lifecycle

    /// Check if a session has a live surface.
    func isRunning(id: UUID) -> Bool {
        (sessionTrees[id] != nil || browserManagers[id] != nil) && statuses[id] == .running
    }

    /// Whether a session has a live surface tree or browser manager, regardless
    /// of its running/completed/exited/killed status. Broader than `isRunning`
    /// on purpose — used for Cmd+Shift+[/] session cycling so the list matches
    /// what the sidebar actually shows (browser-tab mental model), not just
    /// currently-running processes. Do not use in place of `isRunning`; other
    /// call sites depend on its stricter running-only semantics.
    func hasLiveSurface(id: UUID) -> Bool {
        sessionTrees[id] != nil || browserManagers[id] != nil
    }

    /// Focuses the next/previous session in `sessions` relative to
    /// `activeSessionId`, wrapping at both ends. No-ops (returns `nil`, no
    /// beep, no crash) when `sessions` is empty. Shared by
    /// `WorkspaceSidebarView` (Projects + Sessions tabs) and `TaskSidebarView`
    /// (task-first mode) so Cmd+Shift+[/] cycles the active terminal
    /// identically in all three sidebar views.
    func focusAdjacentLiveSession(offset: Int, in sessions: [AgentSession]) -> AgentSession? {
        guard !sessions.isEmpty else { return nil }

        guard let currentId = activeSessionId,
              let currentIndex = sessions.firstIndex(where: { $0.id == currentId }) else {
            let target = offset > 0 ? sessions[0] : sessions[sessions.count - 1]
            focusSession(id: target.id)
            return target
        }

        let newIndex = (currentIndex + offset + sessions.count) % sessions.count
        let target = sessions[newIndex]
        focusSession(id: target.id)
        return target
    }

    /// Close a session's surface tree. All processes in the tree are terminated.
    func closeSession(id: UUID) {
        // Browser session path.
        if let manager = browserManagers[id] {
            manager.closeAllTabs()
            browserManagers.removeValue(forKey: id)
            browserBridges.removeValue(forKey: id)
            setStatus(.killed, for: id)
            if activeSessionId == id {
                switchToNextSession()
            }
            return
        }

        guard let tree = sessionTrees[id] else { return }

        // Remove from our tracking first, then close surfaces via the controller.
        sessionTrees.removeValue(forKey: id)
        outputSubscriptions.removeValue(forKey: id)
        nameSyncSubscriptions[id]?.cancel()
        nameSyncSubscriptions.removeValue(forKey: id)
        setStatus(.killed, for: id)
        gcDraftIfPresent(for: id)
        Self.removeLauncherScript(for: id)

        // If this was the active session, switch to another running session.
        if activeSessionId == id {
            switchToNextSession()
        }

        // Tell Ghostty to close each surface in the tree (kills processes).
        guard let controller = terminalController else { return }
        for surface in tree {
            controller.closeSurface(surface, withConfirmation: false)
        }
    }

    /// "Close Session" — Cmd+W, browser-tab semantics. Confirms via
    /// `NSAlert` (never SwiftUI `confirmationDialog` — see
    /// `BaseTerminalController.closeSurface(_:withConfirmation:)`'s doc
    /// comment for why a Cmd+W handler can't risk a dialog that Cmd+W itself
    /// can dismiss) when the current session is "active" — the same
    /// live/inactive split `RecentsListView` already uses for its
    /// Active/Archive sections (`indicatorState != .inactive`). Closing then
    /// runs through the existing `closeSession(id:)`, which already focuses
    /// a replacement session if one is running. If that leaves this window
    /// with no live session at all, closes the window — browser standard:
    /// closing your last tab closes the window.
    func closeCurrentSessionWithConfirmation() {
        guard let id = activeSessionId else {
            // Nothing to close, and nothing live left in this window — browser
            // convention: ⌘W then closes the window. If live sessions DO exist but
            // none is active, stay a no-op rather than closing out from under them.
            if sessionTrees.isEmpty && browserManagers.isEmpty {
                terminalController?.window?.close()
            }
            return
        }

        let indicatorState = WorkspaceStore.shared.globalIndicatorStates[id] ?? .inactive
        let isActive = indicatorState != .inactive

        func performClose() {
            closeSession(id: id)
            if sessionTrees.isEmpty && browserManagers.isEmpty {
                terminalController?.window?.close()
            }
        }

        guard isActive, let controller = terminalController else {
            performClose()
            return
        }

        controller.confirmClose(
            messageText: "Close Session?",
            informativeText: "This session is still active. Closing it will stop the running process."
        ) {
            performClose()
        }
    }

    /// Clean up runtime state for a session (after removing from the store).
    func clearRuntime(id: UUID) {
        sessionTrees.removeValue(forKey: id)
        browserManagers.removeValue(forKey: id)
        browserBridges.removeValue(forKey: id)
        statuses.removeValue(forKey: id)
        outputSubscriptions.removeValue(forKey: id)
        lastOutputTimestamps.removeValue(forKey: id)
        isAtPrompt.removeValue(forKey: id)
        processingStartTimes.removeValue(forKey: id)
        lastSurfaceTitle.removeValue(forKey: id)
        nameSyncSubscriptions[id]?.cancel()
        nameSyncSubscriptions.removeValue(forKey: id)
        WorkspaceStore.shared.removeSessionStatus(id: id)
        WorkspaceStore.shared.removeIndicatorState(id: id)
    }

    // MARK: - Private

    /// Discovers the terminal controller through the view hierarchy.
    private var terminalController: BaseTerminalController? {
        containerView?.window?.windowController as? BaseTerminalController
    }

    /// Snapshot the active session's current tree from the controller.
    ///
    /// The controller owns the live tree (including any splits the user created
    /// via Ghostty shortcuts). We must capture it before every switch so that
    /// returning to this session restores the user's split layout.
    private func snapshotActiveTree() {
        guard let currentId = activeSessionId,
              let controller = terminalController,
              sessionTrees[currentId] != nil else { return }
        sessionTrees[currentId] = controller.surfaceTree
    }

    /// Replace the terminal area with a session's full split tree.
    ///
    /// Uses `replaceSurfaceTree` (the canonical safe setter) instead of direct
    /// `surfaceTree` assignment to avoid bypassing undo registration.
    /// We pass `undoAction: nil` because session switching is a sidebar navigation
    /// action, not an undoable edit.
    private func showSession(_ tree: SplitTree<Ghostty.SurfaceView>, focusView: Ghostty.SurfaceView?) {
        guard let controller = terminalController else { return }
        let oldFocused = controller.focusedSurface

        controller.replaceSurfaceTree(
            tree,
            moveFocusTo: focusView,
            moveFocusFrom: oldFocused
        )
    }

    /// Switch to the next available running session, or show nothing.
    private func switchToNextSession() {
        // Try terminal sessions first.
        if let (nextId, nextTree) = sessionTrees.first(where: { statuses[$0.key] == .running }) {
            activeSessionId = nextId
            showTerminalInContainer()
            showSession(nextTree, focusView: nextTree.first)
            return
        }
        // Try browser sessions.
        if let (nextId, nextManager) = browserManagers.first(where: { statuses[$0.key] == .running }) {
            activeSessionId = nextId
            showBrowserInContainer(nextManager)
            return
        }
        activeSessionId = nil
    }

    /// Close all sessions belonging to a project. Called before the project is
    /// removed from the store, so that running terminals are properly terminated.
    func closeAllSessions(forProject projectId: UUID) {
        let projectSessions = WorkspaceStore.shared.sessions.filter { $0.projectId == projectId }
        for session in projectSessions {
            if sessionTrees[session.id] != nil || browserManagers[session.id] != nil {
                closeSession(id: session.id)
            }
            clearRuntime(id: session.id)
        }
        lastActiveSessionPerProject.removeValue(forKey: projectId)
    }

    /// Observe project removal notifications so we can close running sessions
    /// before the store deletes the project's session records.
    private func observeProjectRemoval() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(projectWillBeRemoved(_:)),
            name: .workspaceProjectWillBeRemoved,
            object: nil
        )
    }

    @objc private func projectWillBeRemoved(_ notification: Notification) {
        guard let projectId = notification.userInfo?["projectId"] as? UUID else { return }
        closeAllSessions(forProject: projectId)
    }

    /// Observe Ghostty surface close notifications to track session lifecycle.
    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(surfaceDidClose(_:)),
            name: Ghostty.Notification.ghosttyCloseSurface,
            object: nil
        )
    }

    @objc private func surfaceDidClose(_ notification: Notification) {
        // Defer processing by one run-loop tick. BaseTerminalController also observes
        // ghosttyCloseSurface and updates the live surfaceTree synchronously, but
        // NotificationCenter delivery order depends on registration order and is not
        // guaranteed. By dispatching async we ensure the controller has already
        // removed the closed surface before we snapshot its tree.
        DispatchQueue.main.async { [weak self] in
            self?.handleSurfaceClose(notification)
        }
    }

    private func handleSurfaceClose(_ notification: Notification) {
        guard let closedSurface = notification.object as? Ghostty.SurfaceView else { return }

        // Find which session owns this surface by scanning all stored trees.
        guard let sessionId = sessionId(for: closedSurface) else { return }

        let processAlive = notification.userInfo?["process_alive"] as? Bool ?? false

        // Resolve the exit status using cached exit codes from COMMAND_FINISHED.
        let exitStatus: SessionStatus = {
            if processAlive { return .killed }
            let exitCode = pendingExitCodes.removeValue(forKey: closedSurface.id)
            switch exitCode {
            case .none:        return .exited      // No shell integration — fallback
            case .some(-1):    return .exited      // Shell integration present but no exit code reported
            case .some(0):     return .completed
            case .some(let c): return .error(exitCode: c)
            }
        }()

        // For the active session, read the live tree from the controller (which
        // BaseTerminalController has already updated to remove the closed surface).
        // For background sessions, remove the surface from our stored tree.
        if sessionId == activeSessionId {
            if let controller = terminalController {
                let liveTree = controller.surfaceTree
                if liveTree.isEmpty {
                    sessionTrees.removeValue(forKey: sessionId)
                    outputSubscriptions.removeValue(forKey: sessionId)
                    nameSyncSubscriptions[sessionId]?.cancel()
                    nameSyncSubscriptions.removeValue(forKey: sessionId)
                    setStatus(exitStatus, for: sessionId)
                    gcDraftIfPresent(for: sessionId)
                    switchToNextSession()
                } else {
                    sessionTrees[sessionId] = liveTree
                }
            }
        } else {
            // Background session: remove the closed surface's node from our stored tree.
            if let tree = sessionTrees[sessionId],
               let node = tree.root?.node(view: closedSurface) {
                let updated = tree.removing(node)
                if updated.isEmpty {
                    sessionTrees.removeValue(forKey: sessionId)
                    outputSubscriptions.removeValue(forKey: sessionId)
                    nameSyncSubscriptions[sessionId]?.cancel()
                    nameSyncSubscriptions.removeValue(forKey: sessionId)
                    setStatus(exitStatus, for: sessionId)
                    gcDraftIfPresent(for: sessionId)
                } else {
                    sessionTrees[sessionId] = updated
                }
            }
        }
    }

    /// Session-hybrid GC: if the terminal that just closed has a matching
    /// unpromoted `SessionDraft`, drop it from the sidebar. Promoted drafts
    /// are left alone — the task row that replaced them is what tracks the
    /// ongoing lifecycle.
    private func gcDraftIfPresent(for sessionId: UUID) {
        guard let store = sessionDraftStore else { return }
        store.detachOrRemove(forTerminalSession: sessionId)
    }

    /// Resolve a bare command name to its absolute path using the user's login shell.
    ///
    /// Ghostty launches commands via `/usr/bin/login ... --noprofile --norc`, so the
    /// user's PATH from shell profiles isn't available. This spawns a login shell to
    /// get the full PATH, then searches for the binary. Returns the original command
    /// if resolution fails or the command is already absolute.
    nonisolated private static func resolveCommand(_ command: String) -> String {
        guard !command.hasPrefix("/") else { return command }

        // Check cache first.
        resolvedPathsLock.lock()
        let cached = _resolvedPaths[command]
        resolvedPathsLock.unlock()
        if let cached { return cached }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Fast path: check common CLI tool installation directories directly.
        // This avoids spawning a subprocess, which can fail silently in the
        // macOS GUI app context (minimal environment, no TTY).
        let commonPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for dir in commonPaths {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if fm.isExecutableFile(atPath: candidate) {
                resolvedPathsLock.lock()
                _resolvedPaths[command] = candidate
                resolvedPathsLock.unlock()
                return candidate
            }
        }

        // Slow path: spawn a login shell to discover the full PATH.
        // Covers binaries in unusual locations not in the common list above.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return command
        }

        guard task.terminationStatus == 0 else { return command }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let pathString = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !pathString.isEmpty else { return command }

        for dir in pathString.split(separator: ":").map(String.init) {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if fm.isExecutableFile(atPath: candidate) {
                resolvedPathsLock.lock()
                _resolvedPaths[command] = candidate
                resolvedPathsLock.unlock()
                return candidate
            }
        }

        return command
    }

    // MARK: - Launcher Script Lifecycle

    /// `~/.ghostties/cache/launchers` — per-session wrapper scripts written by
    /// `createSession`. Each one leaks its session's task context (banner text,
    /// command line) to anything that can read the directory, so scripts must
    /// not accumulate indefinitely.
    nonisolated static var launcherScriptDir: String {
        ("~/.ghostties/cache/launchers" as NSString).expandingTildeInPath
    }

    /// Delete a single session's launcher script at teardown. A no-op if the
    /// session never got one (e.g. templates without a `launchBanner`).
    nonisolated static func removeLauncherScript(for sessionId: UUID) {
        let path = (launcherScriptDir as NSString).appendingPathComponent("\(sessionId.uuidString).sh")
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Assemble the environment for a spawned session: the template's own
    /// vars, the task-context overlays, the `GHOSTTIES_SESSION_ID` stamp
    /// (every template, including plain shell), and finally any per-call
    /// overrides so a caller can still win.
    nonisolated static func spawnEnvironment(
        template: AgentTemplate,
        taskFilePath: String?,
        taskId: String?,
        extra: [String: String],
        sessionId: UUID
    ) -> [String: String] {
        var result = template.environmentVariables
        if let taskFilePath {
            result["GHOSTTIES_TASK_FILE"] = taskFilePath
        }
        if let taskId {
            result["GHOSTTIES_TASK_ID"] = taskId
        }
        result["GHOSTTIES_SESSION_ID"] = sessionId.uuidString
        // Overlay any per-call env vars (e.g. GHOSTTIES_TEMPLATE for review sessions).
        for (key, value) in extra {
            result[key] = value
        }
        return result
    }

    /// Sweep `~/.ghostties/cache/launchers` on app launch for `*.sh` scripts
    /// older than 24h, catching any left behind by a crash or force-quit that
    /// skipped `closeSession`'s per-session cleanup. Scoped to exactly this
    /// directory and this extension; does not follow symlinks out of it.
    nonisolated static func sweepStaleLauncherScripts() {
        let fm = FileManager.default
        let dir = launcherScriptDir
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for name in entries {
            guard name.hasSuffix(".sh") else { continue }
            let path = (dir as NSString).appendingPathComponent(name)

            // Use a symlink-aware stat so a planted symlink can't redirect the
            // deletion (or the age check) outside this directory.
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff else { continue }

            try? fm.removeItem(atPath: path)
        }
    }

    /// Find which session owns a given surface by searching all stored trees.
    private func sessionId(for surface: Ghostty.SurfaceView) -> UUID? {
        // Check the active session's live tree first (from the controller).
        if let activeId = activeSessionId,
           let controller = terminalController,
           controller.surfaceTree.contains(where: { $0 === surface }) {
            return activeId
        }
        // Check stored trees for background sessions.
        for (id, tree) in sessionTrees where id != activeSessionId {
            if tree.contains(where: { $0 === surface }) {
                return id
            }
        }
        return nil
    }

    // MARK: - Activity Tracking

    /// Subscribe to a session's root surface output activity via Combine.
    private func subscribeToOutput(surface: Ghostty.SurfaceView, sessionId: UUID) {
        subscribeToOutput(
            sessionId: sessionId,
            outputPublisher: surface.lastOutputSubject,
            titleProvider: { [weak surface] in surface?.title }
        )

        // Name sync is its own subscription, independent of `lastOutputSubject`
        // above — it does not piggyback on the output-activity signal path
        // that caused the June invalidation-storm incident. See
        // `nameSyncSubscriptions`'s doc comment for the mechanism.
        //
        // `isManualTitle` reads `surface.isManuallyTitled` at fire time — true
        // once the user has used the "Set Title" dialog on this surface (see
        // `SurfaceView_AppKit.promptTitle()`), and sticky thereafter (the
        // terminal is blocked from overwriting `title` once that happens). A
        // manually-set title is captured by `weak surface` so this closure
        // never keeps the surface alive.
        subscribeNameSync(
            sessionId: sessionId,
            titlePublisher: surface.$title,
            isManualTitle: { [weak surface] in surface?.isManuallyTitled ?? false }
        )
    }

    /// Testable core of `subscribeToOutput` — generic over the output
    /// publisher and injectable `store`, mirroring `subscribeNameSync`'s
    /// `interval:`/`store:` pattern below, so `@testable import` can drive it
    /// with a `PassthroughSubject<Void, Never>` and an isolated
    /// `WorkspaceStore(testingProjects:testingSessions:)`, with no live
    /// `Ghostty.SurfaceView`/GhosttyKit dependency.
    ///
    /// This is the ONLY place `recordActivity` is called with
    /// `isOutput: true` for real terminal-output-activity signals (see the
    /// two session-creation call sites in `createSession`/
    /// `createBrowserSession`, which also pass `isOutput: true` but for a
    /// different reason — clearing a stale persisted value at (re)launch).
    /// `SessionCoordinatorOutputActivityTests` asserts one send here
    /// advances `lastOutputAt` — deleting the `isOutput: true` argument
    /// below must fail that test.
    func subscribeToOutput<P: Publisher>(
        sessionId: UUID,
        outputPublisher: P,
        titleProvider: @escaping () -> String? = { nil },
        store: WorkspaceStore = .shared
    ) where P.Output == Void, P.Failure == Never {
        outputSubscriptions[sessionId] = outputPublisher
            .sink { [weak self] in
                guard let self else { return }
                self.lastOutputTimestamps[sessionId] = .now
                // Output means we're no longer at the prompt.
                self.isAtPrompt[sessionId] = false
                // Start tracking processing duration if not already.
                if self.processingStartTimes[sessionId] == nil {
                    self.processingStartTimes[sessionId] = .now
                }
                // Capture the surface title as a proxy for the last output line.
                // Used by isLikelyPromptingForInput to detect attention-needed state.
                if let title = titleProvider(), !title.isEmpty {
                    self.lastSurfaceTitle[sessionId] = title
                }
                // Push activity into the workspace store so per-project /
                // per-session `lastActiveAt` and `lastOutputAt` stay current
                // with the last output-activity signal (terminal title event
                // — the same proxy the indicator states use), and so the
                // grace-period tracker stays current. The store handles the
                // active-vs-idle indicator-state check internally.
                if let projectId = store.sessions
                    .first(where: { $0.id == sessionId })?.projectId {
                    store.recordActivity(
                        sessionId: sessionId,
                        projectId: projectId,
                        isOutput: true
                    )
                }
            }
    }

    /// Wires a session's title publisher into the Claude Code → sidebar name
    /// sync pipeline (one direction only — nothing here ever writes back into
    /// the running agent's terminal).
    ///
    /// Generic over any `String`/`Never` publisher (not tied to
    /// `Ghostty.SurfaceView.$title`) so `@testable import` can drive it
    /// directly with a `PassthroughSubject<String, Never>` in unit tests,
    /// with no live `Ghostty.SurfaceView`/GhosttyKit dependency. `store`
    /// defaults to the real shared instance in production; tests inject an
    /// isolated `WorkspaceStore(testingProjects:testingSessions:)` so
    /// exercising this never touches the real `workspace.json`.
    ///
    /// `interval` is honored on every call — unlike the deleted
    /// `scheduleNameSync(interval:)`, there is no "already exists, silently
    /// ignore the new value" hazard here because this is called exactly once
    /// per session, at subscription setup in `subscribeToOutput`.
    func subscribeNameSync<P: Publisher>(
        sessionId: UUID,
        titlePublisher: P,
        interval: TimeInterval = SessionCoordinator.nameSyncThrottle,
        store: WorkspaceStore = .shared,
        isManualTitle: @escaping () -> Bool = { false }
    ) where P.Output == String, P.Failure == Never {
        nameSyncSubscriptions[sessionId] = titlePublisher
            // `@Published` replays its current value on subscribe, and a
            // brand-new `SurfaceView`'s first emission is always "". Without
            // this filter that empty value passes `removeDuplicates()` (there
            // is nothing before it to compare against) and consumes the
            // throttle's leading edge, deferring the first real title by up
            // to the full throttle interval on every new session.
            .filter { !$0.isEmpty }
            .removeDuplicates()
            .throttle(for: .seconds(interval), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] title in
                self?.performNameSync(sessionId: sessionId, title: title, store: store, isManualTitle: isManualTitle())
            }
    }

    /// Applies an already-deduped, already-throttled title to the sidebar
    /// name.
    ///
    /// Pin check comes first, before any lookup work: a pinned session's
    /// sync is going to be discarded by `WorkspaceStore.syncSessionNameFromTitle`
    /// regardless, so there's no reason to pay for the project lookup + URL
    /// construction below on every fire for a pinned session.
    ///
    /// `isManualTitle` means this title came from the user's "Set Title"
    /// dialog (`SurfaceView_AppKit.promptTitle()`), not from the terminal.
    /// That's an explicit naming decision, so it's treated as a pin — via
    /// `WorkspaceStore.renameSession`, the same call the sidebar's manual
    /// rename UI uses — rather than a bare sync. This is also what keeps the
    /// state visible and reversible: pinning surfaces the "Sync name
    /// automatically" menu item, so the user can see sync stopped and turn
    /// it back on, instead of a session silently and permanently losing
    /// agent-title sync with no indication why.
    ///
    /// Not `private` for the same testability reason as `subscribeNameSync`.
    func performNameSync(sessionId: UUID, title: String, store: WorkspaceStore = .shared, isManualTitle: Bool = false) {
        guard !title.isEmpty else { return }
        guard let session = store.sessions.first(where: { $0.id == sessionId }) else { return }

        if isManualTitle {
            store.renameSession(id: sessionId, name: title)
            return
        }

        guard !session.isNamePinned else { return }

        let projectDirectoryName = store.projects
            .first(where: { $0.id == session.projectId })
            .map { URL(fileURLWithPath: $0.rootPath).lastPathComponent }

        store.syncSessionNameFromTitle(
            id: sessionId,
            title: title,
            projectDirectoryName: projectDirectoryName
        )
    }

    /// Observe `GHOSTTY_ACTION_COMMAND_FINISHED` to cache exit codes before surfaces close.
    private func observeCommandFinished() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(commandDidFinish(_:)),
            name: Ghostty.Notification.ghosttyCommandFinished,
            object: nil
        )
    }

    @objc private func commandDidFinish(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let exitCode = notification.userInfo?["exit_code"] as? Int16,
              sessionId(for: surface) != nil else { return }
        // Cache the exit code keyed by surface ID. It will be consumed in handleSurfaceClose.
        pendingExitCodes[surface.id] = exitCode
    }

    /// Observe `GHOSTTY_ACTION_PROMPT_READY` to track shell prompt state.
    private func observePromptReady() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(promptDidBecomeReady(_:)),
            name: Ghostty.Notification.ghosttyPromptReady,
            object: nil
        )
    }

    @objc private func promptDidBecomeReady(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let sessionId = sessionId(for: surface) else { return }
        isAtPrompt[sessionId] = true
        processingStartTimes.removeValue(forKey: sessionId)
    }

    /// Observe menu bar session focus requests so clicking a row in the dropdown
    /// activates the correct session and brings its window to the front.
    private func observeMenuBarFocus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarDidRequestFocus(_:)),
            name: .menuBarFocusSession,
            object: nil
        )
    }

    @objc private func menuBarDidRequestFocus(_ notification: Notification) {
        guard let sessionId = notification.userInfo?["sessionId"] as? UUID,
              sessionTrees[sessionId] != nil || browserManagers[sessionId] != nil else { return }
        focusSession(id: sessionId)
        // Bring this coordinator's window to the front.
        if let window = containerView?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Start a 1-second repeating timer that triggers view re-evaluation.
    ///
    /// This is how the sidebar detects the active→waiting transition: the timer
    /// fires, `objectWillChange` causes SwiftUI to re-read `indicatorState(for:)`,
    /// and the 2-second threshold comparison returns a different result.
    private func startActivityTimer() {
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performActivityTick()
            }
        }
    }

    /// The 1Hz tick body: recompute indicator states for all live sessions
    /// and publish to the global store if anything changed. Extracted from
    /// `startActivityTimer`'s timer closure so it can be invoked directly
    /// (by the real timer, or synchronously by tests) without waiting on a
    /// `Timer` fire.
    private func performActivityTick() {
        // Clear any stale `processingStartTimes` entry for a session whose
        // latest Claude hook event is `idle` (a `Stop`). This is the
        // 30-minute false-orange fix: `processingStartTimes` is set on
        // first output and, before this, cleared in exactly one place
        // (`promptDidBecomeReady`, on OSC 133) which Claude's TUI never
        // emits — so every Claude session promoted to `.longRunning` 30
        // minutes after its first output and stayed there forever.
        reconcileClaudeState()

        // Only fire objectWillChange if there are running sessions that could transition.
        let hasRunning = self.statuses.values.contains { $0.isAlive }
        if hasRunning {
            let runningCount = self.statuses.values.lazy.filter { $0.isAlive }.count
            let tickState = Perf.signposter.beginInterval("sessionCoordinator.tick", "\(runningCount) running sessions")

            // Compute current indicator states for all running sessions.
            var current: [UUID: SessionIndicatorState] = [:]
            for (id, status) in self.statuses where status.isAlive {
                current[id] = self.indicatorState(for: id)
            }

            // SEA-214: Only send objectWillChange when state actually changed,
            // suppressing the 7-view full-sidebar re-render that fired every second.
            //
            // Store writes (WorkspaceStore) are moved inside the same changed-branch
            // so the @Published dict assignments and updateProjectActivity only run
            // when the aggregate state actually shifted. The guards in
            // WorkspaceStore.updateIndicatorState / updateSessionStatus are a
            // belt-and-suspenders second layer but this avoids even the dict lookup
            // churn on no-change ticks.
            Perf.publishIfChanged(
                "sessionCoordinator.tick",
                current: current,
                cached: &self.cachedIndicatorStates
            ) {
                self.objectWillChange.send()

                // Push each running session's indicator state to the global store
                // so the menu bar icon can reflect the aggregate status.
                for (id, state) in current {
                    WorkspaceStore.shared.updateIndicatorState(id: id, state: state)
                }

                // Refresh the per-project grace-period tracker so projects
                // whose sessions emit output at <1Hz still keep their
                // `.activeNow` slot for the full grace window.
                WorkspaceStore.shared.updateProjectActivityFromIndicatorStates()
            }
            Perf.signposter.endInterval("sessionCoordinator.tick", tickState)
        }
    }

    /// Clear `processingStartTimes` for any alive session whose latest
    /// Claude hook state is `idle` — the same mutation `promptDidBecomeReady`
    /// performs on OSC 133. Mutation lives here (called once per 1Hz tick),
    /// never inside `indicatorState(for:)`, which must stay a pure read
    /// since it is called directly from SwiftUI `body`.
    private func reconcileClaudeState() {
        for id in statuses.keys where statuses[id]?.isAlive == true {
            if claudeStateStore.state(for: id)?.state == .idle {
                processingStartTimes.removeValue(forKey: id)
            }
        }
    }

    /// Compute the view-layer indicator state for a session.
    ///
    /// Combines lifecycle status, output recency, and shell prompt signals into
    /// one of seven visual states. For running sessions:
    /// - A Claude hook state (if present, not ended, not stale) wins outright
    /// - Recent output → processing (or long-running if 30+ min continuous)
    /// - No recent output + at shell prompt → idle
    /// - No recent output + NOT at prompt + likely prompting → needsAttention
    /// - No recent output + NOT at shell prompt → waiting
    func indicatorState(for sessionId: UUID) -> SessionIndicatorState {
        // Browser sessions: map tab loading state to indicator.
        if let manager = browserManagers[sessionId] {
            guard let activeTab = manager.tabs.first(where: { $0.id == manager.activeTabId }) else {
                return .idle
            }
            return activeTab.isLoading ? .processing : .idle
        }

        let status = statuses[sessionId]
            ?? WorkspaceStore.shared.globalStatuses[sessionId]
            ?? .exited

        switch status {
        case .running:
            // Pure in-memory dictionary lookup, steady-state — no filesystem
            // access from this render-path call. (The *first* access of
            // `ClaudeStateStore.shared` does touch the filesystem via its
            // `init`; `AppDelegate` warms it at launch so that happens before
            // any render, not here.) `ClaudeStateStore.state(for:)` already
            // filters out `.ended` and stale entries, so `.ended` never
            // reaches this switch; the case exists only for exhaustiveness.
            if let claudeState = claudeStateStore.state(for: sessionId) {
                switch claudeState.state {
                case .busy:
                    if let start = processingStartTimes[sessionId],
                       ContinuousClock.now - start > Self.longRunningThreshold {
                        return .longRunning
                    }
                    return .processing
                case .idle:
                    return .idle
                case .needsInput, .needsPermission:
                    return .needsAttention
                case .ended:
                    break
                }
            }
            // Check if the session has produced output recently.
            if let lastOutput = lastOutputTimestamps[sessionId],
               ContinuousClock.now - lastOutput < Self.activityThreshold {
                // Check long-running: continuously processing for 30+ min.
                if let start = processingStartTimes[sessionId],
                   ContinuousClock.now - start > Self.longRunningThreshold {
                    return .longRunning
                }
                return .processing
            }
            // No recent output — check if we're at a shell prompt.
            if isAtPrompt[sessionId] == true {
                return .idle
            }
            // Not at prompt — check if the agent is likely prompting for user input.
            if isLikelyPromptingForInput(sessionId: sessionId) {
                return .needsAttention
            }
            // Silent, not at a shell prompt, no prompt-shaped title. For plain
            // shell sessions `isAtPrompt` is a trustworthy signal (driven by
            // real OSC 133 markers), so silence-without-it genuinely means
            // "waiting on something". Agent-kind sessions (Claude Code, custom
            // agent CLIs) are full-screen TUIs that never emit OSC 133 — for
            // those, `isAtPrompt` is permanently false and silence alone is not
            // evidence the user is needed. Absence of evidence must fall back
            // to the low-salience state, not an attention-seeking one.
            if isAgentKindSession(sessionId) {
                return .idle
            }
            return .waiting

        case .completed, .exited, .killed:
            return .inactive

        case .error:
            return .error
        }
    }

    /// Whether a session's template is an agent CLI (Claude Code, custom) rather
    /// than a plain shell.
    ///
    /// Plain shell sessions emit real OSC 133 prompt markers, so `isAtPrompt`
    /// is trustworthy for them. Agent-kind sessions are full-screen TUIs that
    /// never emit that marker, so `isAtPrompt` never becomes true for their
    /// entire lifetime — the `.waiting` fallback in `indicatorState(for:)`
    /// needs to treat their silence differently. Unknown/missing session or
    /// template (lookup failure) returns `false`, preserving the historic
    /// shell-like fallback rather than guessing.
    private func isAgentKindSession(_ sessionId: UUID) -> Bool {
        #if DEBUG
        let store = agentKindLookupStoreForTesting ?? WorkspaceStore.shared
        #else
        let store = WorkspaceStore.shared
        #endif
        guard let session = store.sessions.first(where: { $0.id == sessionId }),
              let template = store.templates.first(where: { $0.id == session.templateId }) else {
            return false
        }
        return template.kind != .shell
    }

    /// Check if a session is likely blocked on user input based on its last output.
    ///
    /// Uses two layers of detection:
    /// - Layer 1: Last output ends with `?` or `:` (prompt character heuristic)
    /// - Layer 2: Known prompt patterns (permission prompts, yes/no, confirm)
    ///
    /// Returns true if a known pattern matches, or if the last line ends with a
    /// prompt character and is long enough to be meaningful (> 3 chars).
    private func isLikelyPromptingForInput(sessionId: UUID) -> Bool {
        guard let lastLine = lastSurfaceTitle[sessionId] else { return false }
        let trimmed = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Layer 1: Last character is ? or :
        let endsWithPromptChar = trimmed.hasSuffix("?") || trimmed.hasSuffix(":")

        // Layer 2: Known prompt patterns (pure regex, no LLM)
        let matchesPattern = Self.promptPatterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }

        // Pattern match is a strong signal on its own.
        // Prompt char is weaker — require minimum line length to avoid false positives.
        return matchesPattern || (endsWithPromptChar && trimmed.count > 3)
    }

    /// Update a session's status locally and in the global store.
    ///
    /// Both the store's and the coordinator's own indicator caches must be
    /// kept coherent here, because once a session stops being alive it drops
    /// out of the 1Hz tick's `statuses where status.isAlive` loop — nothing
    /// else will ever recompute or self-heal its cached indicator again:
    ///
    /// - `WorkspaceStore.shared`'s `globalIndicatorStates` is what every view
    ///   reads.
    /// - `cachedIndicatorStates` here is the change-comparator the 1Hz tick
    ///   uses to decide whether to publish (`Perf.publishIfChanged`), which
    ///   swaps in `current` (built only from alive sessions) wholesale on
    ///   every publish. A dead session's key survives in that comparator
    ///   only until the *next* tick that actually runs a publish — but if
    ///   this was the last alive session, `hasRunning` goes false and the
    ///   tick body (including that swap) never runs again, freezing the
    ///   stale entry indefinitely.
    ///
    /// Terminal, non-error statuses (`.completed`/`.exited`/`.killed`) clear
    /// both caches, so lookups fall back to `.inactive` (the existing
    /// `?? .inactive` pattern at read sites) and the session drops to
    /// ARCHIVE. `.error` writes `.error` into both caches instead of
    /// clearing them, so the failed session gets a distinct error indicator
    /// and stays visible in ACTIVE until relaunched or Removed. Writing
    /// `cachedIndicatorStates` (not just the store) here matters for the
    /// same reason the terminal-status clear does: without it, relaunching
    /// the same session id could recompute a value that coincidentally
    /// matches the stale pre-error cache entry, suppressing the publish and
    /// leaving the store stuck on `.error` for a session that is actually
    /// running again.
    private func setStatus(_ status: SessionStatus, for id: UUID) {
        statuses[id] = status
        WorkspaceStore.shared.updateSessionStatus(id: id, status: status)
        switch status {
        case .completed, .exited, .killed:
            cachedIndicatorStates?.removeValue(forKey: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
            claudeStateStore.removeState(for: id)
        case .error:
            cachedIndicatorStates?[id] = .error
            WorkspaceStore.shared.updateIndicatorState(id: id, state: .error)
        case .running:
            break
        }
    }

    deinit {
        activityTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        // Clean up this coordinator's session entries from the global store.
        // SessionCoordinator is always deallocated on the main thread (UI object),
        // so assumeIsolated is safe here.
        MainActor.assumeIsolated {
            for id in statuses.keys {
                WorkspaceStore.shared.removeSessionStatus(id: id)
                WorkspaceStore.shared.removeIndicatorState(id: id)
            }
        }
    }

    // MARK: - Debug stress load

#if DEBUG
    /// Inject N fake "running" sessions to pressure-test the 1-second timer
    /// without launching real Claude agents. Triggered via env var:
    ///   GHOSTTIES_STRESS_SESSIONS=8 open /path/to/Ghostties\ Dev.app
    func injectStressLoad(count: Int) {
        for _ in 0..<count {
            let id = UUID()
            statuses[id] = .running
            lastOutputTimestamps[id] = .now
        }
        if activityTimer == nil {
            startActivityTimer()
        }
    }

    /// Test-only seam for exercising the `nameSyncSubscriptions` teardown
    /// paths (`closeSession`, `handleSurfaceClose`) without a live GhosttyKit
    /// surface: an empty `SplitTree` satisfies `closeSession`'s
    /// `sessionTrees[id] != nil` guard while iterating zero real surfaces.
    /// Never used in production.
    func seedEmptySessionTreeForTesting(id: UUID) {
        sessionTrees[id] = SplitTree()
        sessionIdsStartedThisLaunch.insert(id)
    }

    /// Test-only: current count of live name-sync subscriptions, so tests
    /// can assert the dictionary shrinks after teardown without reaching
    /// into a `private` property directly.
    var nameSyncSubscriptionCountForTesting: Int { nameSyncSubscriptions.count }

    /// Test-only seam for driving `setStatus(_:for:)` directly. Exercises the
    /// same mutation `closeSession`/`handleSurfaceClose` use, including
    /// `.exited`/`.completed` terminal statuses that `handleSurfaceClose`
    /// reaches but which have no seam reachable without a live GhosttyKit
    /// surface. Never used in production.
    func setStatusForTesting(_ status: SessionStatus, for id: UUID) {
        setStatus(status, for: id)
    }

    /// Test-only: seed a "live" session (running + producing recent output)
    /// so `indicatorState(for:)` resolves `.processing`, without needing a
    /// real GhosttyKit surface. Never used in production.
    func seedRunningSessionForTesting(id: UUID) {
        statuses[id] = .running
        lastOutputTimestamps[id] = .now
    }

    /// Test-only: run one 1Hz activity tick synchronously, without waiting
    /// for the real `Timer` to fire. Never used in production.
    func runActivityTickForTesting() {
        performActivityTick()
    }

    /// Test-only seam for exercising `indicatorState(for:)`'s decision tree
    /// without live GhosttyKit surfaces. Sets exactly the internal state
    /// `indicatorState(for:)` reads and nothing else. Never used in production.
    func seedIndicatorStateForTesting(
        id: UUID,
        status: SessionStatus = .running,
        lastOutputSecondsAgo: Int? = nil,
        processingStartSecondsAgo: Int? = nil,
        isAtPrompt: Bool = false,
        lastSurfaceTitle: String? = nil
    ) {
        statuses[id] = status
        if let lastOutputSecondsAgo {
            lastOutputTimestamps[id] = ContinuousClock.now - .seconds(lastOutputSecondsAgo)
        }
        if let processingStartSecondsAgo {
            processingStartTimes[id] = ContinuousClock.now - .seconds(processingStartSecondsAgo)
        }
        self.isAtPrompt[id] = isAtPrompt
        if let lastSurfaceTitle {
            self.lastSurfaceTitle[id] = lastSurfaceTitle
        }
    }
#endif
}
