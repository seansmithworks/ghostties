import AppKit
import Foundation

#if DEBUG

/// Action channel for the composer test harness. Interface fixed in
/// `capture-script-schema.md`; `GHOSTTIES_CAPTURE_SCRIPT=<json path>` is read
/// once, when the workspace window is key. Active only when
/// `CaptureFixture.isActive`. Every op calls an existing product seam and
/// every key event goes through `NSWindow.sendEvent` in-process; there is no
/// CGEvent or AX anywhere.
enum CaptureScript {

    struct Failure: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct KeySpec: Equatable {
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    enum Step: Equatable {
        case composerOpen
        case rowPlus(project: String, option: Bool)
        case newSession
        case newSessionInstant
        case type(String)
        case key(KeySpec)
        case mark(String)
        case wait(TimeInterval)
        case pref(Bool?)
    }

    static let namedKeys: Set<String> = ["return", "escape", "tab", "up", "down", "left", "right", "delete"]
    static let prefKey = "newSessionOpensComposer"

    // MARK: - Parsing

    /// Parses the whole script up front, so a bad step 7 fails before step 1
    /// runs. Throws a one-line `Failure`.
    static func parse(_ data: Data) throws -> [Step] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure("script is not a JSON object")
        }
        guard let raw = root["steps"] as? [Any] else { throw Failure("missing steps array") }
        return try raw.enumerated().map { index, item in
            guard let dict = item as? [String: Any] else { throw Failure("step \(index): not an object") }
            do { return try parseStep(dict) } catch let f as Failure { throw Failure("step \(index): \(f.message)") }
        }
    }

    private static func parseStep(_ d: [String: Any]) throws -> Step {
        guard let op = d["op"] as? String else { throw Failure("missing op") }
        switch op {
        case "composer.open": return .composerOpen
        case "newSession": return .newSession
        case "newSessionInstant": return .newSessionInstant
        case "rowPlus":
            guard let project = d["project"] as? String, !project.isEmpty else {
                throw Failure("rowPlus needs a project string")
            }
            return .rowPlus(project: project, option: try optionalBool(d["option"], field: "option") ?? false)
        case "type":
            guard let text = d["text"] as? String else { throw Failure("type needs a text string") }
            return .type(text)
        case "key":
            guard let key = d["key"] as? String else { throw Failure("key needs a key string") }
            guard namedKeys.contains(key) || key.count == 1 else { throw Failure("unknown key '\(key)'") }
            return .key(KeySpec(key: key, modifiers: try parseModifiers(d["modifiers"])))
        case "mark":
            guard let name = d["name"] as? String, !name.isEmpty,
                  name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
                  !name.hasPrefix(".")
            else { throw Failure("mark needs a name of letters, digits, - _ .") }
            return .mark(name)
        case "wait":
            guard let seconds = (d["seconds"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds >= 0 else {
                throw Failure("wait needs seconds >= 0")
            }
            return .wait(seconds)
        case "pref":
            guard d["key"] as? String == prefKey else { throw Failure("pref key must be \(prefKey)") }
            guard let value = d["value"] else { throw Failure("pref needs a value (true, false or null)") }
            if value is NSNull { return .pref(nil) }
            guard let bool = try optionalBool(value, field: "value") else { throw Failure("pref value must be true, false or null") }
            return .pref(bool)
        default:
            throw Failure("unknown op '\(op)'")
        }
    }

    private static func optionalBool(_ value: Any?, field: String) throws -> Bool? {
        guard let value else { return nil }
        // NSNumber also matches 0/1; only real JSON booleans are accepted.
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
            throw Failure("\(field) must be a boolean")
        }
        return n.boolValue
    }

    private static func parseModifiers(_ value: Any?) throws -> NSEvent.ModifierFlags {
        guard let value else { return [] }
        guard let names = value as? [String] else { throw Failure("modifiers must be an array of strings") }
        var flags: NSEvent.ModifierFlags = []
        for name in names {
            switch name {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: throw Failure("unknown modifier '\(name)'")
            }
        }
        return flags
    }

    // MARK: - Pref

    /// The only preference the script may touch. Writes the capture suite
    /// only; `nil` removes the key.
    static func applyPref(_ value: Bool?) {
        WorkspaceViewContainer.setNewSessionOpensComposerForCapture(
            value, in: CaptureFixture.defaults(fixtureActive: true))
    }

    // MARK: - Key events

    private static let keyCodes: [String: (code: UInt16, chars: String)] = [
        "return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "delete": (51, "\u{7f}"),
        "up": (126, String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        "down": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!)),
        "left": (123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        "right": (124, String(UnicodeScalar(NSRightArrowFunctionKey)!)),
    ]

    /// Sends keyDown + keyUp to `window` through `NSWindow.sendEvent`.
    @MainActor
    static func send(_ spec: KeySpec, to window: NSWindow) {
        let (code, chars) = keyCodes[spec.key] ?? (0, spec.key)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: spec.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: code
            ) else { continue }
            window.sendEvent(event)
        }
    }

    @MainActor
    static func type(_ text: String, to window: NSWindow) {
        for character in text { send(KeySpec(key: String(character), modifiers: []), to: window) }
    }

    // MARK: - Running

    @MainActor
    protocol Host: AnyObject {
        var isReady: Bool { get }
        func composerOpen()
        func rowPlus(project: String, option: Bool) throws
        func newSession()
        func newSessionInstant()
        func type(_ text: String)
        func key(_ spec: KeySpec)
        func setPref(_ value: Bool?)
    }

    /// Runs steps against a host and reports through files in `stateDir`:
    /// `marks.jsonl` + `marks/<name>.done` (handshake), `script.done`,
    /// `script.error`.
    @MainActor
    final class Runner {
        let host: Host
        let stateDir: URL
        let markTimeout: TimeInterval
        let pollInterval: TimeInterval

        init(host: Host, stateDir: URL, markTimeout: TimeInterval = 10, pollInterval: TimeInterval = 0.05) {
            self.host = host
            self.stateDir = stateDir
            self.markTimeout = markTimeout
            self.pollInterval = pollInterval
        }

        func writeError(_ message: String) {
            let oneLine = message.replacingOccurrences(of: "\n", with: " ")
            try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try? (oneLine + "\n").write(to: stateDir.appendingPathComponent("script.error"), atomically: true, encoding: .utf8)
        }

        /// Loads the script at `path`, parses it fully, then runs it.
        func run(scriptAt path: String) async {
            guard let data = FileManager.default.contents(atPath: path) else {
                return writeError("cannot read script at \(path)")
            }
            do { await run(try CaptureScript.parse(data)) } catch let f as Failure { writeError(f.message) } catch {}
        }

        func run(_ steps: [Step]) async {
            try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            for (index, step) in steps.enumerated() {
                do { try await perform(step) } catch let f as Failure {
                    return writeError("step \(index): \(f.message)")
                } catch { return writeError("step \(index): \(error)") }
            }
            try? Data().write(to: stateDir.appendingPathComponent("script.done"))
        }

        private func perform(_ step: Step) async throws {
            switch step {
            case .composerOpen: host.composerOpen()
            case .rowPlus(let project, let option): try host.rowPlus(project: project, option: option)
            case .newSession: host.newSession()
            case .newSessionInstant: host.newSessionInstant()
            case .type(let text): host.type(text)
            case .key(let spec): host.key(spec)
            case .pref(let value): host.setPref(value)
            case .wait(let seconds): try await Task.sleep(for: .seconds(seconds))
            case .mark(let name): try await mark(name)
            }
        }

        private func mark(_ name: String) async throws {
            let fm = FileManager.default
            try? fm.createDirectory(at: stateDir.appendingPathComponent("marks"), withIntermediateDirectories: true)
            CaptureFixture.appendLine(
                CaptureFixture.jsonLine(["name": name, "t": Date().timeIntervalSince1970]),
                to: stateDir.appendingPathComponent("marks.jsonl"))
            let done = stateDir.appendingPathComponent("marks/\(name).done").path
            let deadline = Date().addingTimeInterval(markTimeout)
            while !fm.fileExists(atPath: done) {
                guard Date() < deadline else { throw Failure("mark '\(name)' timed out waiting for .done") }
                try await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    /// Waits for the workspace window to be key, lets the sidebar load, then runs.
    @MainActor
    static func launch(scriptAt path: String, host: Host, stateDir: URL) async {
        let runner = Runner(host: host, stateDir: stateDir)
        let deadline = Date().addingTimeInterval(30)
        while !host.isReady {
            guard Date() < deadline else { return runner.writeError("workspace window never became key") }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1))
        await runner.run(scriptAt: path)
    }
}

extension CaptureFixture {
    /// `GHOSTTIES_CAPTURE_SCRIPT`: absolute path to the script JSON.
    static var scriptPath: String? {
        guard isActive, let raw = ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_SCRIPT"], !raw.isEmpty else { return nil }
        return raw
    }
}

#endif
