import Foundation
import Testing
@testable import Ghostty

/// Debug builds reserve a random loopback port for CEF's DevTools server so
/// the agent gateway can proxy to it. Hosted: needs a live CEF (capture
/// bundle); fails rather than skips when CEF is unavailable.
@Suite(.serialized)
@MainActor
struct DebugCDPPortTests {
    @Test func pickFreeLoopbackPortReturnsAnUnprivilegedPort() {
        let a = CEFBridgeManager.pickFreeLoopbackPort()
        #expect(a >= 1024 && a <= 65535, "port out of range: \(a)")
    }

    @Test func cefListensOnItsReservedLoopbackPort() async throws {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else {
            Issue.record("CEF did not initialize; cannot check its DevTools port (this must fail, not skip)")
            return
        }
        let port = CEFBridgeManager.remoteDebuggingPort
        #expect(port >= 1024, "no DevTools port was reserved")

        // The server comes up a moment after CefInitialize returns.
        var version: [String: Any]?
        for _ in 0..<60 where version == nil {
            if let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/json/version")!) {
                version = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            if version == nil { try? await _Concurrency.Task.sleep(for: .milliseconds(100)) }
        }
        let browser = try #require(version?["Browser"] as? String, "/json/version never answered on 127.0.0.1:\(port)")
        #expect(browser.hasPrefix("Chrome/"))
    }
}
