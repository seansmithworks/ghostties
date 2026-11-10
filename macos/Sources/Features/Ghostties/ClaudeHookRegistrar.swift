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
/// Add once: the first time the file ends up holding the hook (merged in
/// now, or already there), `registeredKey` is recorded in Ghostties' own
/// defaults and `register` never touches the file again, so a user who
/// removes the hook keeps it removed. A launch that could not register
/// (Claude Code not installed, unreadable or wrong-shaped file) records
/// nothing, so a later launch tries again.
///
/// Self-guarding: the written command is a silent no-op when the script is
/// gone (`guardedCommand`), so deleting `~/.ghostties` after an uninstall
/// leaves harmless entries instead of exit-127 errors on every agent event.
/// A one-time migration (`guardedKey`) rewrites entries written by earlier
/// versions (and hand-pasted ones) to that form; it never adds or removes
/// an entry.
///
/// Known limit: a read-modify-write with no file lock — a concurrent write
/// by Claude Code between the read and the atomic replace is lost.
struct ClaudeHookRegistrar {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ghostties",
        category: "ClaudeHookRegistrar"
    )

    /// Set in Ghostties' defaults once the hook has been registered.
    static let registeredKey = "ghostties.claudeHookRegistered"

    /// Set once existing Ghostties entries have been rewritten to the
    /// guarded command. Versioned: bump to re-run the migration.
    static let guardedKey = "ghostties.claudeHookGuarded.v1"

    static var defaultSettingsPath: String {
        ("~/.claude/settings.json" as NSString).expandingTildeInPath
    }

    /// The events and matchers `ghostties-status.sh` documents for Claude
    /// Code (see the snippet at the top of the script).
    static let events: [(event: String, matcher: String)] = [
        ("UserPromptSubmit", ""), ("PreToolUse", ""), ("PostToolUse", "TodoWrite"),
        ("Stop", ""), ("Notification", ""), ("PermissionRequest", ""), ("SessionEnd", ""),
    ]

    /// Merge Ghostties' hook into `settingsPath`, unless `defaults` records it
    /// was registered before. Returns `true` if the hook is registered (now,
    /// already present, or on an earlier launch); `false` if the file
    /// could not be read, parsed or written, or if there is nothing to
    /// register into (neither the file nor its directory exists — Claude
    /// Code isn't installed, so one isn't created for it).
    @discardableResult
    static func register(
        settingsPath: String = defaultSettingsPath,
        scriptPath: String,
        defaults: UserDefaults = AppDefaults.store
    ) -> Bool {
        let needsAdd = !defaults.bool(forKey: registeredKey)
        let needsGuard = !defaults.bool(forKey: guardedKey)
        if !needsAdd && !needsGuard { return true }
        guard sync(settingsPath: settingsPath, scriptPath: scriptPath, addMissing: needsAdd) else { return false }
        defaults.set(true, forKey: registeredKey)
        defaults.set(true, forKey: guardedKey)
        return true
    }

    /// `[ -x '<script>' ] && '<script>'<args> || true`: runs the script when
    /// it exists and does nothing (exit 0) when it does not. The path is
    /// POSIX single-quoted (`'` becomes `'\''`), so no character in it can
    /// break out. Keeps the literal script name, so `classify` recognises it.
    static func guardedCommand(scriptPath: String, args: String = "") -> String {
        let q = "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ -x \(q) ] && \(q)\(args) || true"
    }

    /// True if `word` is the status script: exactly its name, or a path
    /// ending in `/ghostties-status.sh`. Not a mere substring match, so
    /// `ghostties-status.sh.log` is not ours.
    static func isScriptWord(_ word: String) -> Bool {
        word == HookInstaller.scriptName || word.hasSuffix("/" + HookInstaller.scriptName)
    }

    /// The first shell word of `s` from `start`: quotes removed, a backslash
    /// escapes the next character, whitespace outside quotes ends it.
    /// `end` is the index just past the word.
    private static func shellWord(_ s: String, from start: String.Index) -> (word: String, end: String.Index) {
        var word = ""
        var quote: Character?
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == q {
                    quote = nil
                } else if c == "\\", q == "\"", s.index(after: i) < s.endIndex {
                    i = s.index(after: i)
                    word.append(s[i])
                } else {
                    word.append(c)
                }
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c == "\\", s.index(after: i) < s.endIndex {
                i = s.index(after: i)
                word.append(s[i])
            } else if c.isWhitespace {
                break
            } else {
                word.append(c)
            }
            i = s.index(after: i)
        }
        return (word, i)
    }

    /// Recognise a Ghostties command string: either the old unguarded form
    /// (the script as the first word, `rest` = any trailing arguments) or the
    /// guarded form. `nil` for anything else.
    static func classify(_ command: String) -> (guarded: Bool, rest: String)? {
        let s = String(command.drop(while: { $0.isWhitespace }))
        if s.hasPrefix("[ -x ") {
            let first = shellWord(s, from: s.index(s.startIndex, offsetBy: 5))
            guard isScriptWord(first.word), s[first.end...].hasPrefix(" ] && ") else { return nil }
            return (true, "")
        }
        let first = shellWord(s, from: s.startIndex)
        guard isScriptWord(first.word) else { return nil }
        return (false, String(s[first.end...]))
    }

    /// The edit behind `register`, in one read-modify-write: rewrites every
    /// existing Ghostties command to the guarded form and, if `addMissing`,
    /// appends our entry to events that have none. `true` if the file is in
    /// that state afterwards.
    private static func sync(settingsPath: String, scriptPath: String, addMissing: Bool) -> Bool {
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

        // A key that exists with an unexpected shape is the user's, not ours
        // to replace: leave the whole file untouched rather than overwrite it.
        if root["hooks"] != nil, !(root["hooks"] is [String: Any]) {
            logger.error("settings.json \"hooks\" is not an object — leaving untouched")
            return false
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, _) in events where hooks[event] != nil && !(hooks[event] is [[String: Any]]) {
            logger.error("settings.json hooks.\(event, privacy: .public) is not an array of objects — leaving untouched")
            return false
        }
        var changed = false
        for (event, matcher) in events {
            // `?? []` only ever covers a missing key: the shape check above
            // has already refused any present-but-wrong value.
            var entries = hooks[event] as? [[String: Any]] ?? []
            if containsGhosttiesEntry(entries) {
                if guardExistingCommands(&entries, scriptPath: scriptPath) {
                    hooks[event] = entries
                    changed = true
                }
            } else if addMissing {
                entries.append(ghosttiesEntry(matcher: matcher, scriptPath: scriptPath))
                hooks[event] = entries
                changed = true
            }
        }
        guard changed else { return true }
        root["hooks"] = hooks

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
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
                ["type": "command", "command": guardedCommand(scriptPath: scriptPath), "async": true] as [String: Any],
            ],
        ]
    }

    /// Rewrite the `command` of every unguarded Ghostties hook in `entries`
    /// to the guarded form (keeping any trailing arguments), leaving every
    /// other key as parsed. `true` if any changed.
    private static func guardExistingCommands(_ entries: inout [[String: Any]], scriptPath: String) -> Bool {
        var changed = false
        for i in entries.indices {
            guard var inner = entries[i]["hooks"] as? [[String: Any]] else { continue }
            var entryChanged = false
            for j in inner.indices {
                guard let command = inner[j]["command"] as? String,
                      let found = classify(command), !found.guarded else { continue }
                inner[j]["command"] = guardedCommand(scriptPath: scriptPath, args: found.rest)
                entryChanged = true
            }
            if entryChanged {
                entries[i]["hooks"] = inner
                changed = true
            }
        }
        return changed
    }

    /// True if any entry already runs `ghostties-status.sh` (see `classify`),
    /// so a hand-pasted `"$HOME"/.ghostties/...` command counts.
    private static func containsGhosttiesEntry(_ entries: [[String: Any]]) -> Bool {
        entries.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { hook in
                (hook["command"] as? String).flatMap(classify) != nil
            }
        }
    }
}
