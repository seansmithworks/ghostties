import Combine
import Foundation

/// Raw on-disk shape written by `ghostties-status.sh` to
/// `~/.ghostties/state/<GHOSTTIES_SESSION_ID>.json`: `{"ghosttiesSessionId",
/// "updatedAt","hook"}`, where `hook` is the Claude Code hook payload
/// verbatim. `updatedAt` is unix seconds (`date +%s`).
struct ClaudeHookWrapper: Decodable {
    let ghosttiesSessionId: String
    let updatedAt: Double
    let hook: ClaudeHookPayload

    /// `"claude"` or `"codex"` — written by `ghostties-status.sh` from its
    /// invocation argument (`ghostties-status.sh codex` for a Codex hook,
    /// unset/absent for Claude). Absent on every file written before this
    /// field existed, which is always a Claude session.
    let agent: String?

    /// `$GHOSTTIES_LAUNCHER` at spawn time (e.g. `cco`, `ccob`), written by
    /// `ghostties-status.sh`. Absent for a shell-hosted `claude` with no
    /// wrapper, or a state file predating this field.
    let launcher: String?
}

/// The union of hook payload keys `ClaudeStateStore.derive(from:)` cares
/// about, across every event Sean's `~/.claude/settings.json` registers
/// (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `Notification`,
/// `PermissionRequest`, `SessionEnd`). Unlisted keys in the real payload
/// (e.g. `background_tasks`) are ignored by `Decodable`, not an error.
/// `tool_input` is decoded only as the narrow `ToolInputSummary` below. Measured shapes: `docs/plans/session-row-status/gate-evidence.md`.
struct ClaudeHookPayload: Decodable {
    let hookEventName: String
    let toolName: String?
    let notificationType: String?
    let sessionId: String?
    let cwd: String?
    /// The agent CLI's own transcript/rollout file for this conversation.
    /// Claude Code always includes it; Codex's hook payload includes it too
    /// (`gate-evidence.md`/spike 2026-09-13). Used by `AgentResume` to
    /// gate a Claude resume on the transcript still existing.
    let transcriptPath: String?
    /// The few `tool_input` fields the session popover shows for a
    /// `PermissionRequest`. Nil when the payload has no `tool_input`.
    let toolInput: ToolInputSummary?
    /// `UserPromptSubmit`'s `prompt` — real user text. Held in memory only
    /// by `SessionSummary`; never persisted, logged, or written to a fixture.
    let prompt: String?
    /// `PreToolUse`/`PostToolUse`'s `tool_use_id`, used only to count each
    /// edit once when `refresh()` re-reads an unchanged file.
    let toolUseId: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case sessionId = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
    }

    /// `hook_event_name` is required; every other field is optional AND
    /// tolerant — a wrongly-typed `prompt` or `tool_use_id` becomes nil
    /// instead of failing the payload (and the session's state with it).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        toolName = try? c.decodeIfPresent(String.self, forKey: .toolName)
        notificationType = try? c.decodeIfPresent(String.self, forKey: .notificationType)
        sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
        transcriptPath = try? c.decodeIfPresent(String.self, forKey: .transcriptPath)
        toolInput = try? c.decodeIfPresent(ToolInputSummary.self, forKey: .toolInput)
        prompt = try? c.decodeIfPresent(String.self, forKey: .prompt)
        toolUseId = try? c.decodeIfPresent(String.self, forKey: .toolUseId)
    }
}

/// The subset of a hook's `tool_input` object the session popover renders:
/// `command` + `description` (Bash), `file_path` (Edit/Write/Read-style
/// tools). Every field is optional and decoding never throws — a missing,
/// non-object, or wrongly-typed `tool_input` yields an all-nil summary rather
/// than failing the whole hook payload (and with it the session's state).
struct ToolInputSummary: Decodable, Equatable {
    let command: String?
    let description: String?
    let filePath: String?
    /// First of the other single-target keys tools use in place of
    /// `file_path` (Glob/Grep `pattern`, Notebook `notebook_path`, `path`,
    /// WebFetch `url`), for the "first arg" of a non-Bash tool line.
    let firstArgument: String?

    private enum Keys: String, CodingKey {
        case command, description
        case filePath = "file_path"
        case path, pattern, url
        case notebookPath = "notebook_path"
    }

    init(command: String? = nil, description: String? = nil, filePath: String? = nil, firstArgument: String? = nil) {
        self.command = command
        self.description = description
        self.filePath = filePath
        self.firstArgument = firstArgument
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else {
            self.init()
            return
        }
        func string(_ key: Keys) -> String? {
            guard let value = try? c.decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
            return value
        }
        self.init(
            command: string(.command),
            description: string(.description),
            filePath: string(.filePath),
            firstArgument: string(.notebookPath) ?? string(.path) ?? string(.pattern) ?? string(.url)
        )
    }
}

/// What a session is doing right now, for the popover's "what's happening"
/// block. Lives ONLY in memory in `ClaudeStateStore.summaries`, separate from
/// `states` (whose contents feed the indicator caches): it is built from the
/// hook stream as events are ingested, because the state file is
/// last-event-wins and the prompt is overwritten by the next tool event.
/// Never persisted -- `prompt` is real user text.
struct SessionSummary: Equatable {
    /// The last `UserPromptSubmit` prompt, whitespace collapsed. nil until one
    /// has been seen (e.g. after an app relaunch, mid-turn).
    private(set) var prompt: String?
    /// Latest `PreToolUse`, as "running npm test" / "editing config.ts".
    private(set) var currentStep: String?
    /// The current Bash command, first line, truncated. Bash only.
    private(set) var currentCommand: String?
    /// Edit/Write/MultiEdit `PostToolUse` events since the last prompt.
    private(set) var editCount = 0
    /// True after `Stop`, until the next prompt.
    private(set) var isDone = false
    private(set) var updatedAt = Date.distantPast

    /// A repeated read of the same file (`refresh()` re-decodes every file on
    /// every directory change) must not double-count.
    private var lastEventKey: String?
    private var countedEditIds: Set<String> = []

    static let maxPromptLength = 400
    static let maxCommandLength = 80
    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit"]

    init() {}

    /// Test/fixture seam: an already-built summary.
    init(prompt: String?, currentStep: String? = nil, currentCommand: String? = nil,
         editCount: Int = 0, isDone: Bool = false, updatedAt: Date = Date()) {
        self.prompt = prompt
        self.currentStep = currentStep
        self.currentCommand = currentCommand
        self.editCount = editCount
        self.isDone = isDone
        self.updatedAt = updatedAt
    }

    /// Fold one hook event in. Idempotent for a repeated read of the same
    /// file. `updatedAt` is unix SECONDS, so two events in one second are
    /// told apart by `tool_use_id`, not the timestamp.
    mutating func ingest(_ hook: ClaudeHookPayload, updatedAt: Date) {
        let key = "\(updatedAt.timeIntervalSince1970)|\(hook.hookEventName)|\(hook.toolUseId ?? "")"
        guard key != lastEventKey else { return }

        switch hook.hookEventName {
        case "UserPromptSubmit":
            self = SessionSummary()
            let text = hook.prompt.map(Self.collapse) ?? ""
            prompt = text.isEmpty ? nil : String(text.prefix(Self.maxPromptLength))
        case "PreToolUse":
            isDone = false
            currentStep = Self.step(tool: hook.toolName, input: hook.toolInput)
            currentCommand = hook.toolName == "Bash" ? hook.toolInput?.command.map(Self.firstLine) : nil
        case "PostToolUse":
            if let tool = hook.toolName, Self.editTools.contains(tool) {
                if let id = hook.toolUseId {
                    if countedEditIds.insert(id).inserted { editCount += 1 }
                } else {
                    editCount += 1
                }
            }
        case "Stop":
            isDone = true
            currentStep = nil
            currentCommand = nil
        default:
            return
        }
        lastEventKey = key
        self.updatedAt = updatedAt
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func firstLine(_ command: String) -> String {
        let line = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = collapse(line)
        return trimmed.count > maxCommandLength ? String(trimmed.prefix(maxCommandLength)) + "…" : trimmed
    }

    private static func basename(_ path: String?) -> String? {
        path.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func step(tool: String?, input: ToolInputSummary?) -> String? {
        guard let tool, !tool.isEmpty else { return nil }
        switch tool {
        case "Bash":
            return input?.command.map { "running " + firstLine($0) } ?? "running a command"
        case "Edit", "Write", "MultiEdit":
            return basename(input?.filePath).map { "editing " + $0 } ?? "editing"
        case "Read":
            return basename(input?.filePath).map { "reading " + $0 } ?? "reading"
        case "Grep", "Glob":
            return "searching"
        case "Task", "Agent":
            return "running a subagent"
        default:
            return tool.lowercased()
        }
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
    /// What the tool is about to do — carried here and nowhere else, so it
    /// exists only while the state is `.needsPermission`.
    var toolInput: ToolInputSummary? = nil
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
    static let staleInterval: TimeInterval = 30 * 60

    private let directoryURL: URL
    private var states: [UUID: ClaudeState] = [:]
    /// In-memory "what's happening" per session; see `SessionSummary`. Kept
    /// apart from `states` on purpose -- nothing that feeds the indicator
    /// caches reads it, so ingesting summaries cannot change what they publish.
    private var summaries: [UUID: SessionSummary] = [:]
    private var watcher: TaskFileWatcher?

    /// Fires after every `refresh()` rebuilds `states`, so a live consumer
    /// (the session popover) can re-derive instead of trusting a snapshot.
    let didRefresh = PassthroughSubject<Void, Never>()

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

    /// The session's summary, or nil if no prompt has been seen this run or
    /// it has gone stale. The popover shows no summary block on nil.
    func summary(for id: UUID) -> SessionSummary? {
        guard let summary = summaries[id], summary.prompt != nil,
              Date().timeIntervalSince(summary.updatedAt) <= Self.staleInterval else { return nil }
        return summary
    }

    // MARK: - Writes

    /// Delete both state files for a session. Called from `SessionCoordinator
    /// .setStatus(_:for:)`'s terminal branch, the same seam that already
    /// clears both indicator caches, so a closed session's Claude state
    /// cannot outlive the session that owned it.
    func removeState(for id: UUID) {
        states.removeValue(forKey: id)
        summaries.removeValue(forKey: id)
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
            summaries = [:]
            didRefresh.send()
            return
        }

        var newStates: [UUID: ClaudeState] = [:]
        var seen: Set<UUID> = []
        for url in entries {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !name.hasSuffix(".todos.json") else { continue }
            let stem = String(name.dropLast(".json".count))
            guard let ghosttiesSessionId = UUID(uuidString: stem) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let wrapper = try? JSONDecoder().decode(ClaudeHookWrapper.self, from: data) else { continue }

            // Persist the resume record BEFORE `derive`'s event filtering —
            // every event carries the agent's own session id, and a resume
            // record must survive event kinds `derive` doesn't act on (and
            // `Stop`, which `derive` keeps but which deletes this same file
            // via `removeState(for:)` afterward). See `AgentResume`.
            persistResumeIfPresent(ghosttiesSessionId: ghosttiesSessionId, wrapper: wrapper)

            // Summary ingest: reads the same wrapper, writes only `summaries`.
            seen.insert(ghosttiesSessionId)
            if wrapper.hook.hookEventName == "SessionEnd" {
                summaries.removeValue(forKey: ghosttiesSessionId)
            } else {
                var summary = summaries[ghosttiesSessionId] ?? SessionSummary()
                summary.ingest(wrapper.hook, updatedAt: Date(timeIntervalSince1970: wrapper.updatedAt))
                summaries[ghosttiesSessionId] = summary
            }

            guard let state = Self.derive(from: wrapper) else { continue }
            newStates[state.ghosttiesSessionId] = state
        }
        states = newStates
        // A session whose file is gone has gone away.
        summaries = summaries.filter { seen.contains($0.key) }
        didRefresh.send()
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

    // MARK: - Resume record (writes to WorkspaceStore, not `states`)

    /// Build an `AgentResume` from `wrapper` and hand it to
    /// `WorkspaceStore.updateResume(id:resume:)` (or the test seam), unless
    /// the hook payload carries no session id to resume. `updateResume`
    /// itself is the no-op guard for "replace only when it changed" — this
    /// method always calls it, on every refresh, for every file.
    private func persistResumeIfPresent(ghosttiesSessionId: UUID, wrapper: ClaudeHookWrapper) {
        guard let claudeSessionId = wrapper.hook.sessionId, !claudeSessionId.isEmpty else { return }
        let agent = AgentResume.Agent(rawValue: wrapper.agent ?? "claude") ?? .claude
        let resume = AgentResume(
            agent: agent,
            sessionId: claudeSessionId,
            transcriptPath: wrapper.hook.transcriptPath,
            cwd: wrapper.hook.cwd,
            launcher: wrapper.launcher
        )
#if DEBUG
        if let resumeWriterForTesting {
            resumeWriterForTesting(ghosttiesSessionId, resume)
            return
        }
#endif
        WorkspaceStore.shared.updateResume(id: ghosttiesSessionId, resume: resume)
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
            structuredPrompt = StructuredPrompt(toolName: hook.toolName ?? "", toolUseId: nil, toolInput: hook.toolInput)
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

    /// Test-only override for where `refresh()` persists a resume record,
    /// so tests never touch `WorkspaceStore.shared` / the real
    /// `workspace.json`. nil (production behavior — write to
    /// `WorkspaceStore.shared`) outside DEBUG builds and by default.
#if DEBUG
    var resumeWriterForTesting: ((UUID, AgentResume) -> Void)?

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
