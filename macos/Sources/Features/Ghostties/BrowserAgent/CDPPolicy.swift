#if DEBUG
import Foundation

/// Which Chrome DevTools Protocol commands an agent may send to the app's
/// browser. Pure functions, no I/O.
///
/// The browser is shared with Sean and lives inside the app process, so a few
/// browser-level commands are unsafe for an agent to run: `Browser.close`
/// makes Chromium quit the whole app, and `Target.createTarget` would open a
/// page the sidebar knows nothing about. Everything else is forwarded as-is,
/// including the calls Playwright's `connectOverCDP` makes while attaching.
///
/// This is a guardrail for well-behaved agents, not a security boundary.
enum CDPPolicy {
    enum Verdict: Equatable {
        case allow
        case deny(message: String)
    }

    /// What the gateway does with one frame from the client.
    enum FrameAction: Equatable {
        /// Pass it to the browser untouched.
        case forward
        /// Do not forward; send this text back to the client instead.
        case reply(String)
        /// Do not forward and do not answer (a denied command with no id to
        /// answer to).
        case drop
    }

    /// Commands that can end the app, crash the browser or resize/steer the
    /// host window.
    private static let deniedMethods: Set<String> = [
        "Browser.close",
        "Browser.crash",
        "Browser.crashGpuProcess",
        "Browser.setWindowBounds",
        "Browser.executeBrowserCommand",
        // Bypasses: sendMessageToTarget carries another command as a nested
        // JSON string the policy cannot see (deprecated; Playwright and
        // Puppeteer use flattened sessions), and attachToBrowserTarget hands a
        // page-scoped client a browser-level session.
        "Target.sendMessageToTarget",
        "Target.attachToBrowserTarget",
        // Injects a binding that lets page JavaScript send commands to the
        // browser target, Browser.close included.
        "Target.exposeDevToolsProtocol",
    ]

    static func decide(method: String) -> Verdict {
        if method == "Target.createTarget" {
            return .deny(message: "Ghostties: Target.createTarget is not allowed; use `gt browser open`")
        }
        if deniedMethods.contains(method) {
            return .deny(message: "Ghostties: \(method) is not allowed")
        }
        return .allow
    }

    /// Decides what to do with a raw text frame from the client. Fails
    /// closed: only a frame that parses as a JSON object with a string
    /// `method`, an integer `id` and no duplicate top-level key is forwarded
    /// (when its method is allowed). Anything else, including what
    /// Foundation's parser rejects, is answered with an error or dropped.
    /// Chromium's parser may read such a frame differently (the second of two
    /// duplicate keys, say), so forwarding it is how a bypass happens.
    static func action(forClientFrame text: String) -> FrameAction {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let keys = topLevelKeys(of: text), Set(keys).count == keys.count,
              let method = object["method"] as? String,
              let id = integerId(object["id"])
        else { return unreadable(text) }

        guard case .deny(let message) = decide(method: method) else { return .forward }
        return .reply(errorResponse(id: id, sessionId: object["sessionId"] as? String, message: message))
    }

    private static func unreadable(_ text: String) -> FrameAction {
        // Best effort: answer the request if its id can be found.
        if let range = text.range(of: #""id"\s*:\s*-?\d+"#, options: .regularExpression),
           let digits = text[range].range(of: #"-?\d+"#, options: .regularExpression),
           let id = Int(text[range][digits]) {
            return .reply(errorResponse(id: id, message: "Ghostties: unreadable or ambiguous CDP frame"))
        }
        return .drop
    }

    /// `id` as a whole number; rejects booleans, strings and fractions.
    private static func integerId(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 9e15 else { return nil }
        return number.intValue
    }

    /// The decoded keys of the top-level object, in order, duplicates kept
    /// (JSONSerialization hides them). Also validates string escapes: a lone
    /// UTF-16 surrogate makes this return nil. Expects text that Foundation
    /// already parsed as one JSON object.
    private static func topLevelKeys(of text: String) -> [String]? {
        let bytes = Array(text.utf8)
        var keys: [String] = []
        var depth = 0
        var expectKey = false
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                guard let end = stringEnd(bytes, from: i), escapesAreValid(bytes, i, end) else { return nil }
                if depth == 1, expectKey {
                    var wrapped = Data("[".utf8)
                    wrapped.append(contentsOf: bytes[i...end])
                    wrapped.append(contentsOf: "]".utf8)
                    guard let decoded = ((try? JSONSerialization.jsonObject(with: wrapped)) as? [String])?.first else { return nil }
                    keys.append(decoded)
                    expectKey = false
                }
                i = end
            case UInt8(ascii: "{"):
                depth += 1
                if depth == 1 { expectKey = true }
            case UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 1 { expectKey = true }
            default:
                break
            }
            i += 1
        }
        return keys
    }

    /// Index of the closing quote of the string literal opening at `start`.
    private static func stringEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var i = start + 1
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "\\") { i += 2; continue }
            if bytes[i] == UInt8(ascii: "\"") { return i }
            i += 1
        }
        return nil
    }

    /// Every `\uXXXX` surrogate in the literal must be half of a valid pair.
    private static func escapesAreValid(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Bool {
        func unit(at i: Int) -> UInt32? {
            guard i + 5 < end + 1, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") else { return nil }
            let hex = String(decoding: bytes[(i + 2)...(i + 5)], as: UTF8.self)
            return UInt32(hex, radix: 16)
        }
        var i = start + 1
        while i < end {
            if bytes[i] == UInt8(ascii: "\\") {
                if bytes[i + 1] == UInt8(ascii: "u") {
                    guard let code = unit(at: i) else { return false }
                    if (0xD800...0xDBFF).contains(code) {
                        guard let low = unit(at: i + 6), (0xDC00...0xDFFF).contains(low) else { return false }
                        i += 12
                        continue
                    }
                    if (0xDC00...0xDFFF).contains(code) { return false }
                    i += 6
                    continue
                }
                i += 2
                continue
            }
            i += 1
        }
        return true
    }

    /// The error a denied command is answered with. A command sent on a
    /// flattened session must be answered on that session, or the client
    /// never matches the reply to its request.
    static func errorResponse(id: Int, sessionId: String? = nil, message: String) -> String {
        var response: [String: Any] = [
            "id": id,
            "error": ["code": -32000, "message": message] as [String: Any],
        ]
        if let sessionId { response["sessionId"] = sessionId }
        let data = (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
