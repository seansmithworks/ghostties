import AppKit
import Combine
import XCTest
@testable import Ghostty

/// Keys handed to a page view end up inside the page (Chromium's own view),
/// not on the container around it, where typing would go nowhere. And a
/// browser that opens while nothing has the keys still takes them, as it
/// did before navigation focus was limited.
///
/// Hosted, live CEF; fails (never skips) without it. Run through
/// `scripts/build-capture.sh test`, never under Sean's Dev bundle id.
@MainActor
final class BrowserPageFocusTests: XCTestCase {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private final class PageWatcher: NSObject, CEFBrowserViewDelegate {
        var created = false
        var finishedLoads = 0
        func browserViewDidCreate(_ view: CEFBrowserView) { created = true }
        func browserView(_ view: CEFBrowserView, didChangeLoadingState isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
            if !isLoading { finishedLoads += 1 }
        }
    }

    private struct NoCEF: Error {}

    private func requireCEF() throws {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else {
            XCTFail("CEF did not initialize (this must fail, not skip)")
            throw NoCEF()
        }
    }

    private func host() -> (WorkspaceViewContainer, NSWindow) {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        container.coordinatorForTesting.agentKindLookupStoreForTesting = store
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderBack(nil)
        window.makeKey()
        container.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        return (container, window)
    }

    private func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    /// Strictly inside `view`: Chromium's view, not the container itself.
    private func insidePage(_ view: NSView, _ window: NSWindow) -> Bool {
        guard let responder = window.firstResponder as? NSView else { return false }
        return responder !== view && responder.isDescendant(of: view)
    }

    private let blank = "about:blank"

    func testKeysHandedToAPageViewBeforeItsPageExistsReachThePage() throws {
        try requireCEF()
        let (_, window) = host()
        let watcher = PageWatcher()
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), url: blank)
        view.delegate = watcher
        window.contentView?.addSubview(view)
        XCTAssertTrue(window.makeFirstResponder(view))
        XCTAssertTrue(window.firstResponder === view, "the page view holds the keys before its page exists")

        pump(20) { watcher.created && watcher.finishedLoads > 0 }
        pump(1)
        XCTAssertTrue(insidePage(view, window), "the page itself has the keys once it exists")
        view.removeFromSuperview()
    }

    func testReturnInTheAddressFieldPutsTheKeysInsideThePage() throws {
        try requireCEF()
        let (container, window) = host()
        let watcher = PageWatcher()
        let manager = BrowserTabManager()
        let tab = manager.createTab(url: blank)
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: blank)
        view.delegate = watcher
        manager.registerBrowserView(view, for: tab.id)
        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        pump(20) { watcher.created && watcher.finishedLoads > 0 }

        let bar = try XCTUnwrap(navigationBar(in: container))
        XCTAssertTrue(window.makeFirstResponder(bar.urlField))
        bar.urlField.stringValue = blank
        let editor = try XCTUnwrap(bar.urlField.currentEditor() as? NSTextView)
        let loadsBefore = watcher.finishedLoads
        _ = container.control(bar.urlField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        pump(20) { watcher.finishedLoads > loadsBefore }
        pump(1)
        XCTAssertTrue(insidePage(view, window), "after Return the page itself has the keys, so typing reaches it")
    }

    func testABrowserOpenedWhileNothingHasTheKeysTakesThem() throws {
        try requireCEF()
        let (container, window) = host()
        let watcher = PageWatcher()
        let manager = BrowserTabManager()
        let tab = manager.createTab(url: blank)
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: blank)
        view.delegate = watcher
        manager.registerBrowserView(view, for: tab.id)
        window.makeFirstResponder(nil)

        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        pump(20) { watcher.created && watcher.finishedLoads > 0 }
        pump(1)

        XCTAssertTrue(insidePage(view, window), "a new page still takes keys nobody holds")
    }

    private func navigationBar(in view: NSView) -> BrowserNavigationBar? {
        if let bar = view as? BrowserNavigationBar { return bar }
        for sub in view.subviews { if let bar = navigationBar(in: sub) { return bar } }
        return nil
    }
}
