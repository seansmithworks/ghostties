import Foundation
import Testing
@testable import Ghostty

struct CDPJSONRewriteTests {
    /// Each path gets its own gateway port, like the real routes.
    private func rewritten(_ text: String, raw: Int = 51234) -> String {
        let ports = ["/devtools/browser/abc": 60001, "/devtools/page/A": 60002, "/devtools/page/B": 60003]
        return String(decoding: CDPJSONRewrite.rewrite(Data(text.utf8), rawPort: raw, routePort: { ports[$0] }), as: UTF8.self)
    }

    @Test func versionPointsTheBrowserSocketAtItsRoute() {
        let body = #"{"Browser":"Chrome/144","webSocketDebuggerUrl":"ws://127.0.0.1:51234/devtools/browser/abc"}"#
        #expect(rewritten(body) == #"{"Browser":"Chrome/144","webSocketDebuggerUrl":"ws://127.0.0.1:60001/devtools/browser/abc"}"#)
    }

    @Test func listRewritesEveryEntryIncludingTheFrontendUrl() {
        let body = """
        [{"id":"A","webSocketDebuggerUrl":"ws://127.0.0.1:51234/devtools/page/A","devtoolsFrontendUrl":"/devtools/inspector.html?ws=127.0.0.1:51234/devtools/page/A"},
         {"id":"B","webSocketDebuggerUrl":"ws://localhost:51234/devtools/page/B"}]
        """
        let out = rewritten(body)
        #expect(!out.contains("51234"))
        #expect(out.contains("ws://127.0.0.1:60002/devtools/page/A"))
        #expect(out.contains("ws=127.0.0.1:60002/devtools/page/A"))
        #expect(out.contains("ws://127.0.0.1:60003/devtools/page/B"))
    }

    @Test func otherPortsAreLeftAlone() {
        // 512345 starts with the raw port's digits; it must not be clipped.
        let body = #"{"a":"http://127.0.0.1:8080/devtools/page/A","b":"127.0.0.1:512345/devtools/page/A"}"#
        #expect(rewritten(body) == body)
    }

    @Test func aPathWithoutARouteNeverLeaksTheRawPort() {
        let body = #"{"webSocketDebuggerUrl":"ws://127.0.0.1:51234/devtools/page/UNKNOWN"}"#
        let out = rewritten(body)
        #expect(!out.contains("51234"))
        #expect(out.contains("127.0.0.1:0/devtools/page/UNKNOWN"))
    }

    @Test func nonTextBodyIsReturnedUnchanged() {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x01])
        #expect(CDPJSONRewrite.rewrite(bytes, rawPort: 1, routePort: { _ in 2 }) == bytes)
    }
}
