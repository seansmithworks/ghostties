import Foundation
import OSLog

/// Registers Ghostties' status-reporting hook into Codex's own
/// `<CODEX_HOME>/hooks.json` (default `~/.codex/hooks.json`) — a file
/// entirely separate from `HookInstaller`'s Claude Code seed, and one Sean
/// may already have other hooks configured in.
///
/// Codex hook trust is PER ARRAY POSITION (`hooks.state."<path>:<event>:
/// <arrayIndex>:<innerIndex>"`, Codex's own `config.toml` key — verified via
/// `codex doctor`/binary strings against codex-cli 0.153.0, never read or
/// written here). Prepending or reordering an existing entry re-indexes it
/// and silently un-trusts it (`exec` skips an untrusted hook with no
/// error). So every edit this type makes is APPEND-ONLY: existing event
/// arrays and their entries are left exactly as parsed, and Ghostties'
/// entry is appended at the end of its event's array (or the array is
/// created if the event has none yet). This type never writes a trust
/// marker and never uses `--dangerously-bypass-hook-trust` — Sean approves
/// the new entry once in Codex's own review UI.
///
/// The read-modify-write in `register(hooksJSONPath:scriptPath:)` takes no
/// file lock. A Codex process writing to `hooks.json` concurrently (e.g.
/// approving a hook in its own review UI) between this type's read and its
/// atomic replace could have that write silently lost. Acceptable: Codex
/// writes this file rarely (only on a trust decision), so the window is
/// narrow and the loss is recoverable — the user re-approves.
struct CodexHookRegistrar {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ghostties",
        category: "CodexHookRegistrar"
    )

    /// Default location of Codex's hook config file.
    static var defaultHooksJSONPath: String {
        ("~/.codex/hooks.json" as NSString).expandingTildeInPath
    }

    /// Every event Ghostties wants a Codex hook entry for — the Codex
    /// equivalents of what `ghostties-status.sh` is already registered for
    /// under Claude Code (`PermissionRequest` has no Codex analog reported
    /// to `ClaudeStateStore` yet — see `agent-data.md`/plan note "Codex has
    /// no Notification event").
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Stop", "SessionEnd",
    ]

    /// Register Ghostties' hook into `hooksJSONPath`, creating the file
    /// (and its parent directory) if absent. Returns `true` if the file is
    /// now in the desired state (including "already was" — idempotent, not
    /// "just wrote"); `false` on any failure, including a malformed
    /// existing file, which is left untouched rather than overwritten.
    @discardableResult
    static func register(hooksJSONPath: String = defaultHooksJSONPath, scriptPath: String) -> Bool {
        let fm = FileManager.default

        var root: [String: Any]
        if fm.fileExists(atPath: hooksJSONPath) {
            guard let data = fm.contents(atPath: hooksJSONPath) else {
                logger.error("Could not read \(hooksJSONPath, privacy: .public)")
                return false
            }
            // Empty file: treat as "no hooks yet", not malformed — some
            // tools touch an empty file as a placeholder.
            if data.isEmpty {
                root = [:]
            } else {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.error("hooks.json is not a valid JSON object — leaving untouched")
                    return false
                }
                root = parsed
            }
        } else {
            root = [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !containsGhosttiesEntry(entries, scriptPath: scriptPath) {
                entries.append(ghosttiesEntry(scriptPath: scriptPath))
                hooks[event] = entries
                changed = true
            }
        }

        guard changed else { return true }
        root["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            logger.error("Failed to serialize hooks.json")
            return false
        }

        let dir = (hooksJSONPath as NSString).deletingLastPathComponent
        if !dir.isEmpty, !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                logger.error("Failed to create \(dir, privacy: .public): \(error.localizedDescription)")
                return false
            }
        }

        // Same-directory temp file + rename/replace, matching HookInstaller
        // and ghostties-status.sh — never leaves the destination half-written.
        let tmpPath = hooksJSONPath + ".tmp"
        do {
            try data.write(to: URL(fileURLWithPath: tmpPath))
            if fm.fileExists(atPath: hooksJSONPath) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: hooksJSONPath), withItemAt: URL(fileURLWithPath: tmpPath))
            } else {
                try fm.moveItem(atPath: tmpPath, toPath: hooksJSONPath)
            }
        } catch {
            logger.error("Failed to write hooks.json: \(error.localizedDescription)")
            try? fm.removeItem(atPath: tmpPath)
            return false
        }

        return true
    }

    /// One `{"matcher": "", "hooks": [{"type": "command", "command": [...],
    /// "async": true}]}` entry, invoking the script with a trailing "codex"
    /// argument so `ghostties-status.sh` tags every state file it writes
    /// `"agent":"codex"`.
    private static func ghosttiesEntry(scriptPath: String) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                [
                    "type": "command",
                    "command": [scriptPath, "codex"],
                    "async": true,
                ],
            ],
        ]
    }

    /// True if any existing entry for this event already invokes
    /// `scriptPath` — matched by the command's first element (or substring,
    /// for a legacy string-form command), not full-array equality, so a
    /// future change to trailing args never creates a duplicate entry.
    private static func containsGhosttiesEntry(_ entries: [[String: Any]], scriptPath: String) -> Bool {
        entries.contains { entry in
            guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { inner in
                if let command = inner["command"] as? [String] {
                    return command.first == scriptPath
                }
                if let command = inner["command"] as? String {
                    return command.contains(scriptPath)
                }
                return false
            }
        }
    }
}
