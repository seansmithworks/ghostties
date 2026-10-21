import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Regression: closing a CEF browser must never ask the host window to close.
/// CEF's default `DoClose` sends `performClose:` to the browser's top-level
/// window, which on Ghostties is the whole workspace window ("Close Window?").
///
/// Hosted: needs a live CEF. If CEF cannot initialize, this test FAILS rather
/// than skipping, so a green run always means the close path was exercised.
/// Uses the test host's own CEF profile (the `.capture` bundle via
/// `scripts/build-capture.sh test`); never run it under Sean's Dev bundle id.
@Suite(.serialized)
@MainActor
struct BrowserCloseKeepsWindowTests {
    private final class CountingWindow: NSWindow {
        var performCloseCount = 0
        override func performClose(_ sender: Any?) {
            performCloseCount += 1
        }
    }

    private final class CreateWaiter: NSObject, CEFBrowserViewDelegate {
        var created = false
        func browserViewDidCreate(_ view: CEFBrowserView) { created = true }
    }

    private func pump(until done: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    @Test func closingBrowserNeverPerformsCloseOnHostWindow() {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else {
            Issue.record("CEF did not initialize; cannot exercise the close path (this must fail, not skip)")
            return
        }

        let window = CountingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let waiter = CreateWaiter()
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), url: "about:blank")
        view.delegate = waiter
        window.contentView = view
        window.orderBack(nil)

        pump(until: { waiter.created }, timeout: 20)
        guard waiter.created else {
            Issue.record("CEF browser was never created; cannot exercise the close path")
            window.orderOut(nil)
            return
        }

        view.closeBrowser()
        // Give CEF time to run DoClose / OnBeforeClose.
        pump(until: { window.performCloseCount > 0 }, timeout: 3)

        #expect(window.performCloseCount == 0, "closing a browser asked the host window to close")
        window.contentView = nil
        window.orderOut(nil)
    }
}
