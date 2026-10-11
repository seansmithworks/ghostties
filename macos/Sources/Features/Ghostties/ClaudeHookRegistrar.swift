import Foundation
import OSLog

/// Registers Ghostties' status hook into Claude Code's user settings
/// (`~/.claude/settings.json`) so the sidebar's "needs you" status works
/// without a hand-pasted JSON snippet. Mirrors `CodexHookRegistrar`.
///
/// The settings file is the user's, full of keys this type knows nothing
/// about. So the edit is a MERGE: every existing key and hook is carried
/// through exactly as parsed (and nothing is reordered within an event's
/// array); Ghostties' entry is appended to an event only when no existing
/// entry already runs `ghostties-status.sh` (which also recognises the
/// snippet people pasted by hand, so it never doubles up). A file that is
/// not a valid JSON object is left untouched.
///
/// Known limit: a read-modify-write with no file lock — a concurrent write
/// by Claude Code between the read and the atomic replace is lost.
struct ClaudeHookRegistrar {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ghostties",
        category: "ClaudeHookRegistrar"
    )

    static var defaultSettingsPath: String {
        ("~/.claude/settings.json" as NSString).expandingTildeInPath
    }

    /// The events and matchers `ghostties-status.sh` documents for Claude
    /// Code (see the snippet at the top of the script).
    static let events: [(event: String, matcher: String)] = [
        ("UserPromptSubmit", ""), ("PreToolUse", ""), ("PostToolUse", "TodoWrite"),
        ("Stop", ""), ("Notification", ""), ("PermissionRequest", ""), ("SessionEnd", ""),
    ]

    /// Merge Ghostties' hook into `settingsPath`. Returns `true` if the file
    /// is now in the desired state (including "already was"); `false` if it
    /// could not be read, parsed or written, or if there is nothing to
    /// register into (neither the file nor its directory exists — Claude
    /// Code isn't installed, so one isn't created for it).
    @discardableResult
    static func register(settingsPath: String = defaultSettingsPath, scriptPath: String) -> Bool {
        let fm = FileManager.default
        // Write through a symlinked settings.json (dotfiles repos) rather
        // than replacing the link with a plain file.
        let path = URL(fileURLWithPath: settingsPath).resolvingSymlinksInPath().path

        var root: [String: Any] = [:]
        if fm.fileExists(atPath: path) {
            guard let data = fm.contents(atPath: path) else {
                logger.error("Could not read \(path, privacy: .public)")
                return false
            }
            if !data.isEmpty {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.error("settings.json is not a valid JSON object — leaving untouched")
                    return false
                }
                root = parsed
            }
        } else if !fm.fileExists(atPath: (path as NSString).deletingLastPathComponent) {
            return false
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for (event, matcher) in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !containsGhosttiesEntry(entries) {
                entries.append(ghosttiesEntry(matcher: matcher, scriptPath: scriptPath))
                hooks[event] = entries
                changed = true
            }
        }
        guard changed else { return true }
        root["hooks"] = hooks

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            logger.error("Failed to serialize settings.json")
            return false
        }
        do {
            try out.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            logger.error("Failed to write settings.json: \(error.localizedDescription)")
            return false
        }
        return true
    }

    private static func ghosttiesEntry(matcher: String, scriptPath: String) -> [String: Any] {
        [
            "matcher": matcher,
            "hooks": [
                ["type": "command", "command": "\"\(scriptPath)\"", "async": true] as [String: Any],
            ],
        ]
    }

    /// True if any entry already runs `ghostties-status.sh` — matched by
    /// script name so a hand-pasted `"$HOME"/.ghostties/...` command counts.
    private static func containsGhosttiesEntry(_ entries: [[String: Any]]) -> Bool {
        entries.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { hook in
                (hook["command"] as? String)?.contains(HookInstaller.scriptName) == true
            }
        }
    }
}
