import AppKit
import Foundation
import Testing
@testable import Ghostty

/// `CEFBrowserView.fetchDevToolsTargetId` must return the browser's own
/// DevTools target id, in-process, without needing CEF's debugging port.
///
/// Hosted: needs a live CEF. If CEF cannot initialize or the browser is never
/// created, this FAILS rather than skipping. Run through the capture bundle
/// (`scripts/build-capture.sh test`), never under Sean's Dev bundle id.
@Suite(.serialized)
@MainActor
struct DevToolsTargetIdTests {
    /// Yields the main actor between polls. A nested `RunLoop.run` would NOT
    /// drain the main dispatch queue from inside a main-queue job, so results
    /// delivered with `dispatch_async(main)` would never arrive.
    private func pump(until done: () -> Bool, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            try? await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func fetchReturnsThisBrowsersTargetId() async {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else {
            Issue.record("CEF did not initialize; cannot fetch a target id (this must fail, not skip)")
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), url: "about:blank")
        window.contentView = view
        window.orderBack(nil)

        // Asked before the browser exists on purpose: the call must wait for
        // creation instead of failing.
        var fetched: String??
        view.fetchDevToolsTargetId(withTimeout: 20) { fetched = .some($0) }
        await pump(until: { fetched != nil }, timeout: 25)

        let targetId = fetched ?? nil
        #expect(targetId != nil, "no target id came back")
        if let targetId {
            #expect(targetId.count >= 16, "target id looks too short: \(targetId)")
            #expect(targetId.allSatisfy { $0.isHexDigit }, "target id is not hex: \(targetId)")
        }

        view.closeBrowser()
        await pump(until: { false }, timeout: 0.5)
        window.contentView = nil
        window.orderOut(nil)
    }
}
