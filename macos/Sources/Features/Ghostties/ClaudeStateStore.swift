import Foundation

/// Raw on-disk shape written by `ghostties-status.sh` to
/// `~/.ghostties/state/<GHOSTTIES_SESSION_ID>.json`: `{"ghosttiesSessionId",
/// "updatedAt","hook"}`, where `hook` is the Claude Code hook payload
/// verbatim. `updatedAt` is unix seconds (`date +%s`).
struct ClaudeHookWrapper: Decodable {
    let ghosttiesSessionId: String
    let updatedAt: Double
    let hook: ClaudeHookPayload
}

/// The union of hook payload keys `ClaudeStateStore.derive(from:)` cares
/// about, across every event Sean's `~/.claude/settings.json` registers
/// (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `Notification`,
/// `PermissionRequest`, `SessionEnd`). Unlisted keys in the real payload
/// (e.g. `tool_input`, `background_tasks`) are ignored by `Decodable`, not
/// an error. Measured shapes: `docs/plans/session-row-status/gate-evidence.md`.
struct ClaudeHookPayload: Decodable {
    let hookEventName: String
    let toolName: String?
    let notificationType: String?
    let sessionId: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case sessionId = "session_id"
        case cwd
    }
}

/// A permission or tool-use identity carried by a `needsPermission` state.
///
/// `toolUseId` is `String?`, not `String`, because `PermissionRequest`
/// carries no `tool_use_id` of its own (gate-evidence E2), and because the
/// state file is last-event-wins, the preceding `PreToolUse`'s id has
/// already been overwritten by the time this event lands on disk. Pairing
/// a permission prompt back to its triggering tool call is a Phase 4
/// concern (in-memory PreToolUse tracking), not this phase's.
struct StructuredPrompt: Equatable {
    let toolName: String
    let toolUseId: String?
}

/// Decoded, derived state for one Ghostties session, keyed by
/// `ghosttiesSessionId` (== `AgentSession.id` == `GHOSTTIES_SESSION_ID`).
struct ClaudeState: Equatable {
    enum Kind: Equatable {
        case busy
        case idle
        case needsInput
        case needsPermission
        case ended
    }

    let ghosttiesSessionId: UUID
    let claudeSessionId: String
    let cwd: String
    let state: Kind
    let structuredPrompt: StructuredPrompt?
    let updatedAt: Date
}

/// A row-facing summary of why a session needs the user's attention.
/// `ClaudeStateStore.attention(for:)` is what Phases 3-5 will consume;
/// nothing reads it yet in this phase.
enum AttentionPayload: Equatable {
    case freeform
    case permission(toolName: String, toolUseId: String?)
}

/// Reads Claude Code's own idea of session state from
/// `~/.ghostties/state/<id>.json`, written by the `ghostties-status.sh`
/// hook (seeded by `HookInstaller`), and exposes it as a small in-memory
/// map so `SessionCoordinator.indicatorState(for:)` can consult it as a
/// pure dictionary lookup — no filesystem access on the render path.
///
/// One instance is global (`.shared`), not per-window, because
/// `~/.ghostties/state/` is a single global directory regardless of how
/// many `SessionCoordinator`s (one per window) are alive.
@MainActor
final class ClaudeStateStore {
    static let shared = ClaudeStateStore(directoryURL: ClaudeStateStore.defaultDirectoryURL)

    /// How stale a state file can be before `state(for:)`/`attention(for:)`
    /// stop trusting it and fall back to today's output-based heuristics.
    /// A crashed or force-quit Claude process leaves its last hook event on
    /// disk forever otherwise.
    private static let staleInterval: TimeInterval = 30 * 60

    private let directoryURL: URL
    private var states: [UUID: ClaudeState] = [:]
    private var watcher: TaskFileWatcher?

    nonisolated static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghostties", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        ensureDirectory()
        let watcher = TaskFileWatcher(url: directoryURL) { [weak self] in
            self?.refresh()
        }
        self.watcher = watcher
        watcher.start()
    }

    // MARK: - Reads (pure, in-memory)

    /// The most recent Claude-derived state for a session, or nil if there is
    /// none, it has gone terminal (`.ended`), or it is stale (older than
    /// `staleInterval`). Callers fall through to today's heuristics on nil.
    func state(for id: UUID) -> ClaudeState? {
        guard let state = states[id] else { return nil }
        if state.state == .ended { return nil }
        guard Date().timeIntervalSince(state.updatedAt) <= Self.staleInterval else { return nil }
        return state
    }

    /// Attention payload for a session, or nil unless the session's current
    /// state is `needsInput`/`needsPermission`. Not consumed anywhere yet —
    /// Phases 3-5 read this to render the second row line / Approve button.
    func attention(for id: UUID) -> AttentionPayload? {
        guard let state = state(for: id) else { return nil }
        switch state.state {
        case .needsInput:
            return .freeform
        case .needsPermission:
            guard let prompt = state.structuredPrompt else {
                return .permission(toolName: "", toolUseId: nil)
            }
            return .permission(toolName: prompt.toolName, toolUseId: prompt.toolUseId)
        case .busy, .idle, .ended:
            return nil
        }
    }

    // MARK: - Writes

    /// Delete both state files for a session. Called from `SessionCoordinator
    /// .setStatus(_:for:)`'s terminal branch, the same seam that already
    /// clears both indicator caches, so a closed session's Claude state
    /// cannot outlive the session that owned it.
    func removeState(for id: UUID) {
        states.removeValue(forKey: id)
        let fm = FileManager.default
        try? fm.removeItem(at: directoryURL.appendingPathComponent("\(id.uuidString).json"))
        try? fm.removeItem(at: directoryURL.appendingPathComponent("\(id.uuidString).todos.json"))
    }

    /// Delete `*.json` state files, and orphaned `*.tmp` files, older than
    /// 24h. `*.json` catches state left behind by a Claude process that
    /// crashed or was force-quit without a `SessionEnd` hook firing. `*.tmp`
    /// catches `ghostties-status.sh`'s `<dest>.<pid>.tmp` if the process dies
    /// between its `printf` and `mv -f` — `refresh()` and this sweep both
    /// filter on `.json`, so a `.tmp` is otherwise never noticed, let alone
    /// deleted, and it carries the same tool-name/prompt-text content as the
    /// state file it was about to become. Scoped to exactly this directory;
    /// symlink-aware stat so a planted symlink can't redirect the deletion
    /// outside it. Mirrors `SessionCoordinator.sweepStaleLauncherScripts()`.
    nonisolated static func sweepStale() {
        let fm = FileManager.default
        let dir = defaultDirectoryURL.path
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for name in entries {
            guard name.hasSuffix(".json") || name.hasSuffix(".tmp") else { continue }
            let path = (dir as NSString).appendingPathComponent(name)

            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff else { continue }

            try? fm.removeItem(atPath: path)
        }
    }

    // MARK: - Refresh (watcher callback only — never on the render path)

    /// Rebuild `states` from scratch by listing `directoryURL` and decoding
    /// every `<uuid>.json` file (never `*.todos.json`, which is out of
    /// scope this phase). One bad file is skipped, not fatal to the whole
    /// refresh. Full rebuild (not an incremental merge) is deliberate: the
    /// hook overwrites its one file per session on every event, and a
    /// rebuild is also how a deleted file's session naturally drops out.
    private func refresh() {
        // Do NOT call `ensureDirectory()` unconditionally here. Its
        // existing-directory branch does a `chmod`, and `TaskFileWatcher`'s
        // event mask includes `.attrib`, so a `chmod` on the watched
        // directory fires another `refresh()` ~150ms later. On the success
        // path below the directory's mode is already fine (we just listed
        // it), so calling it there would re-arm the watcher forever. On the
        // failure path it is called at most once per failed listing — once
        // `ensureDirectory()` repairs the mode, the *next* refresh (driven by
        // the hook's own `chmod 700` in `ghostties-status.sh`, or this same
        // repair's `.attrib` event) takes the success path above and stops
        // calling it, so it cannot loop.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            // Self-heal a mode-drifted directory (e.g. `chmod 000` while
            // running) so a permanent EACCES doesn't wipe `states` forever.
            // `init`'s `ensureDirectory()` alone is not sufficient for this —
            // it only ever runs once, at construction.
            ensureDirectory()
            states = [:]
            return
        }

        var newStates: [UUID: ClaudeState] = [:]
        for url in entries {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !name.hasSuffix(".todos.json") else { continue }
            let stem = String(name.dropLast(".json".count))
            guard UUID(uuidString: stem) != nil else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let wrapper = try? JSONDecoder().decode(ClaudeHookWrapper.self, from: data) else { continue }
            guard let state = Self.derive(from: wrapper) else { continue }
            newStates[state.ghosttiesSessionId] = state
        }
        states = newStates
    }

    /// Create `directoryURL` at `0o700` if absent; enforce `0o700` on an
    /// existing one. These files carry tool names and per-session context —
    /// the same class of leak `SessionCoordinator.launcherScriptDir`'s
    /// comment warns about.
    ///
    /// The existing-directory branch only calls `setAttributes` when the
    /// current mode isn't already `0o700`. `TaskFileWatcher` watches this
    /// same directory with `.attrib` in its event mask, so an unconditional
    /// `chmod` here — even a no-op one — fires another debounced `refresh()`.
    /// `refresh()` calls this only on its failure path (a mode-drifted
    /// directory self-heal), never on success — this conditional-chmod guard
    /// is what keeps that call from looping: once the mode is `0o700` it's a
    /// no-op, so the retriggered `.attrib` refresh takes the success path
    /// and stops calling this method at all.
    private func ensureDirectory() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue {
            let currentMode = (try? fm.attributesOfItem(atPath: directoryURL.path))?[.posixPermissions] as? NSNumber
            if currentMode?.uint16Value != 0o700 {
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            }
        } else {
            try? fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    // MARK: - Pure mapping (no filesystem — testable directly)

    /// Map one decoded hook payload to a `ClaudeState`, or nil if the event
    /// is not one this phase acts on. Pure function: no filesystem, no
    /// `self` access, so tests call it directly against fixtures built from
    /// the measured payload key sets in `gate-evidence.md`.
    static func derive(from wrapper: ClaudeHookWrapper) -> ClaudeState? {
        guard let ghosttiesSessionId = UUID(uuidString: wrapper.ghosttiesSessionId) else { return nil }
        let hook = wrapper.hook

        let kind: ClaudeState.Kind
        var structuredPrompt: StructuredPrompt?

        switch hook.hookEventName {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            kind = .busy
        case "Stop":
            kind = .idle
        case "PermissionRequest":
            kind = .needsPermission
            // toolUseId is nil — see StructuredPrompt's doc comment above.
            structuredPrompt = StructuredPrompt(toolName: hook.toolName ?? "", toolUseId: nil)
        case "Notification":
            switch hook.notificationType {
            case "permission_prompt":
                kind = .needsPermission
            case "idle_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                kind = .needsInput
            default:
                return nil
            }
        case "SessionEnd":
            kind = .ended
        default:
            return nil
        }

        return ClaudeState(
            ghosttiesSessionId: ghosttiesSessionId,
            claudeSessionId: hook.sessionId ?? "",
            cwd: hook.cwd ?? "",
            state: kind,
            structuredPrompt: structuredPrompt,
            updatedAt: Date(timeIntervalSince1970: wrapper.updatedAt)
        )
    }

#if DEBUG
    /// Test-only: force a synchronous refresh from `directoryURL`, bypassing
    /// the watcher's 150ms debounce. Never used in production.
    func refreshForTesting() {
        refresh()
    }

    /// Test-only: seed an in-memory state directly on `.shared` without
    /// touching any filesystem, so `SessionCoordinator` tests can exercise
    /// the read path without ever writing to the real
    /// `~/.ghostties/state/`. Never used in production.
    func seedStateForTesting(_ state: ClaudeState) {
        states[state.ghosttiesSessionId] = state
    }
#endif
}
