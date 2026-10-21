import Foundation
import Testing
@testable import Ghostty

struct CDPJSONRewriteTests {
    private func rewritten(_ text: String, raw: Int = 51234, gateway: Int = 60001) -> String {
        String(decoding: CDPJSONRewrite.rewrite(Data(text.utf8), rawPort: raw, gatewayPort: gateway), as: UTF8.self)
    }

    @Test func versionPointsTheBrowserSocketAtTheGateway() {
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
        #expect(out.contains("ws://127.0.0.1:60001/devtools/page/A"))
        #expect(out.contains("ws=127.0.0.1:60001/devtools/page/A"))
        #expect(out.contains("ws://127.0.0.1:60001/devtools/page/B"))
    }

    @Test func otherPortsAreLeftAlone() {
        // 512345 starts with the raw port's digits; it must not be clipped.
        let body = #"{"a":"http://127.0.0.1:8080/","b":"127.0.0.1:512345","c":"127.0.0.1:51234"}"#
        #expect(rewritten(body) == #"{"a":"http://127.0.0.1:8080/","b":"127.0.0.1:512345","c":"127.0.0.1:60001"}"#)
    }

    @Test func nonTextBodyIsReturnedUnchanged() {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x01])
        #expect(CDPJSONRewrite.rewrite(bytes, rawPort: 1, gatewayPort: 2) == bytes)
    }
}
