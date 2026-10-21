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

    /// Decides what to do with a raw text frame from the client. A frame that
    /// is not a JSON command (malformed, binary, no method) is forwarded
    /// unchanged: the browser rejects it itself, and the gateway should not
    /// invent behaviour for traffic it does not understand.
    static func action(forClientFrame text: String) -> FrameAction {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String
        else { return .forward }

        guard case .deny(let message) = decide(method: method) else { return .forward }
        guard let id = (object["id"] as? NSNumber)?.intValue else { return .drop }
        return .reply(errorResponse(id: id, sessionId: object["sessionId"] as? String, message: message))
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
