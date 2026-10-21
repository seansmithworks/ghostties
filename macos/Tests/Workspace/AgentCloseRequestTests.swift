import AppKit
import Foundation
import Testing
@testable import Ghostty

/// A close that comes from outside the app (an agent's `Page.close` /
/// `Target.closeTarget`, or `window.close()`) must reach the delegate as a
/// close request, and must never ask the host window to close.
///
/// Hosted: needs a live CEF. Fails rather than skips when CEF is unavailable.
/// Run through the capture bundle (`scripts/build-capture.sh test`).
@Suite(.serialized)
@MainActor
struct AgentCloseRequestTests {
    private final class CountingWindow: NSWindow {
        var performCloseCount = 0
        override func performClose(_ sender: Any?) {
            performCloseCount += 1
        }
    }

    private final class Recorder: NSObject, CEFBrowserViewDelegate {
        var created = false
        var closeRequests = 0
        var onCloseRequest: ((CEFBrowserView) -> Void)?
        func browserViewDidCreate(_ view: CEFBrowserView) { created = true }
        func browserViewDidRequestClose(_ view: CEFBrowserView) {
            closeRequests += 1
            onCloseRequest?(view)
        }
    }

    /// Yields the main actor between polls so `dispatch_async(main)` work runs.
    private func pump(until done: () -> Bool, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            try? await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func pageCloseFromOutsideRequestsCloseWithoutClosingTheWindow() async {
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
        let recorder = Recorder()
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), url: "about:blank")
        view.delegate = recorder
        window.contentView = view
        window.orderBack(nil)

        await pump(until: { recorder.created }, timeout: 20)
        guard recorder.created else {
            Issue.record("CEF browser was never created; cannot exercise the close path")
            window.orderOut(nil)
            return
        }

        #expect(view.executeDevToolsMethod(forTesting: "Page.close"), "CEF rejected Page.close")
        await pump(until: { recorder.closeRequests > 0 }, timeout: 5)

        #expect(recorder.closeRequests == 1, "an outside close never reached the delegate")
        #expect(window.performCloseCount == 0, "an outside close asked the host window to close")

        view.closeBrowser()
        await pump(until: { false }, timeout: 0.5)
        window.contentView = nil
        window.orderOut(nil)
    }

    /// What the coordinator does with a close request: close the browser. CEF
    /// has already accepted the outside close (`DoClose` returned true), so
    /// this must still finish destroying the browser, or the DevTools target
    /// lingers and the page stays alive with no UI.
    @Test func closingTheBrowserAfterAnOutsideCloseDestroysIt() async {
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
        let recorder = Recorder()
        recorder.onCloseRequest = { $0.closeBrowser() }
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), url: "about:blank")
        view.delegate = recorder
        window.contentView = view
        window.orderBack(nil)

        await pump(until: { recorder.created }, timeout: 20)
        guard recorder.created else {
            Issue.record("CEF browser was never created; cannot exercise the close path")
            window.orderOut(nil)
            return
        }

        #expect(view.executeDevToolsMethod(forTesting: "Page.close"))
        // OnBeforeClose removes the view from its window once CEF has really
        // destroyed the browser.
        await pump(until: { view.window == nil }, timeout: 5)

        #expect(view.window == nil, "the browser was never destroyed after an outside close")
        window.contentView = nil
        window.orderOut(nil)
    }

    @Test func appInitiatedCloseDoesNotRequestClose() async {
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
        let recorder = Recorder()
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), url: "about:blank")
        view.delegate = recorder
        window.contentView = view
        window.orderBack(nil)

        await pump(until: { recorder.created }, timeout: 20)
        guard recorder.created else {
            Issue.record("CEF browser was never created; cannot exercise the close path")
            window.orderOut(nil)
            return
        }

        view.closeBrowser()
        await pump(until: { recorder.closeRequests > 0 }, timeout: 2)

        #expect(recorder.closeRequests == 0, "closeBrowser() called back as if an outsider had closed it")
        #expect(window.performCloseCount == 0)
        window.contentView = nil
        window.orderOut(nil)
    }
}
