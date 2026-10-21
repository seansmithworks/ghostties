import Foundation

/// Rewrites the JSON that Chromium's `/json/*` endpoints return so every
/// address in it points at the gateway instead of the browser's own debugging
/// port. Without it a client that follows `webSocketDebuggerUrl` would connect
/// straight to Chromium and skip the method policy.
enum CDPJSONRewrite {
    /// Replaces `127.0.0.1:<rawPort>` and `localhost:<rawPort>` with
    /// `127.0.0.1:<gatewayPort>` anywhere in `body`. This covers
    /// `webSocketDebuggerUrl` and the `ws=` query inside `devtoolsFrontendUrl`.
    /// Anything that is not UTF-8 text is returned unchanged.
    static func rewrite(_ body: Data, rawPort: Int, gatewayPort: Int) -> Data {
        guard let text = String(data: body, encoding: .utf8),
              // The lookahead keeps a longer port (51234 vs 512345) intact.
              let pattern = try? NSRegularExpression(
                  pattern: "(?:127\\.0\\.0\\.1|localhost):\(rawPort)(?![0-9])"
              )
        else { return body }
        let out = pattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "127.0.0.1:\(gatewayPort)"
        )
        return Data(out.utf8)
    }
}
