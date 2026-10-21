import Foundation

/// Rewrites the JSON that Chromium's `/json/*` endpoints return so every
/// DevTools address in it points at the gateway instead of the browser's own
/// debugging port. Without it a client that follows `webSocketDebuggerUrl`
/// would connect straight to Chromium and skip the method policy.
enum CDPJSONRewrite {
    /// Replaces `127.0.0.1:<rawPort>/devtools/page|browser/<id>` (and the
    /// `localhost` spelling) with `127.0.0.1:<port>/devtools/...`, where
    /// `routePort` supplies the gateway port that serves that path. This
    /// covers `webSocketDebuggerUrl` and the `ws=` query inside
    /// `devtoolsFrontendUrl`. An address whose path has no route becomes port
    /// 0, which cannot connect, rather than leaking the browser's port.
    /// Anything that is not UTF-8 text is returned unchanged.
    static func rewrite(_ body: Data, rawPort: Int, routePort: (String) -> Int?) -> Data {
        guard let text = String(data: body, encoding: .utf8),
              // Lookaheads keep a longer port (51234 vs 512345) and a longer
              // id intact.
              let pattern = try? NSRegularExpression(
                  pattern: "(?:127\\.0\\.0\\.1|localhost):\(rawPort)(?![0-9])(/devtools/(?:page|browser)/[A-Za-z0-9_-]+)"
              )
        else { return body }

        var out = ""
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let pathRange = Range(match.range(at: 1), in: text) else { continue }
            let path = String(text[pathRange])
            out += text[cursor..<whole.lowerBound]
            out += "127.0.0.1:\(routePort(path) ?? 0)\(path)"
            cursor = whole.upperBound
        }
        out += text[cursor...]
        return Data(out.utf8)
    }
}
