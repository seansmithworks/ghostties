import AppKit
import Combine
import XCTest
@testable import Ghostty

/// The browser keeps the keyboard through its own page swaps, as Safari does:
/// opening, switching or closing a tab, pressing Return in the address
/// field, and a page finishing its load never leave the keys with the bare
/// window, so Cmd+T, Cmd+L and the other browser shortcuts keep reaching it.
///
/// Hosted, with live CEF pages: a stand-in view would prove the container
/// asks for focus, not that a real page view takes it. If CEF cannot
/// initialize, every test FAILS rather than skipping. Run through
/// `scripts/build-capture.sh test` (the `.capture` bundle's own CEF profile),
/// never under Sean's Dev bundle id. Every store is the injected,
/// persistence-disabled kind.
@MainActor
final class BrowserFocusTests: XCTestCase {
    // MARK: Hosting

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    /// Records each page's creation and its loads finishing.
    private final class PageWatcher: NSObject, CEFBrowserViewDelegate {
        var created: Set<ObjectIdentifier> = []
        var finishedLoads: [ObjectIdentifier: Int] = [:]
        func browserViewDidCreate(_ view: CEFBrowserView) { created.insert(ObjectIdentifier(view)) }
        func browserView(_ view: CEFBrowserView, didChangeLoadingState isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
            if !isLoading { finishedLoads[ObjectIdentifier(view), default: 0] += 1 }
        }
    }

    private let watcher = PageWatcher()

    private struct NoCEF: Error {}

    private func requireCEF() throws {
        CEFBridgeManager.initializeIfNeeded()
        guard CEFBridgeManager.isInitialized else {
            XCTFail("CEF did not initialize; the focus rule cannot be exercised (this must fail, not skip)")
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

    private func page(_ title: String) -> String {
        let html = "<!doctype html><title>\(title)</title><body>\(title)</body>"
        return "data:text/html," + (html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    }

    /// A browser manager whose tabs each have a live page view.
    private func manager(tabs titles: [String]) -> BrowserTabManager {
        let manager = BrowserTabManager()
        for title in titles {
            let tab = manager.createTab(url: page(title))
            let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: page(title))
            view.delegate = watcher
            manager.registerBrowserView(view, for: tab.id)
        }
        return manager
    }

    private func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func view(_ manager: BrowserTabManager, _ index: Int) -> CEFBrowserView {
        manager.browserViews[manager.tabs[index].id] as! CEFBrowserView
    }

    /// Waits for `view`'s page to exist and finish loading, then a beat more
    /// for any focus move a navigation makes.
    private func settle(_ view: CEFBrowserView, loads: Int = 1) {
        pump(20) { watcher.created.contains(ObjectIdentifier(view)) && watcher.finishedLoads[ObjectIdentifier(view), default: 0] >= loads }
        XCTAssertTrue(watcher.created.contains(ObjectIdentifier(view)), "the page was never created")
        pump(1)
    }

    private func navigationBar(in container: NSView) -> BrowserNavigationBar {
        func find(_ view: NSView) -> BrowserNavigationBar? {
            if let bar = view as? BrowserNavigationBar { return bar }
            for sub in view.subviews { if let bar = find(sub) { return bar } }
            return nil
        }
        return find(container)!
    }

    /// Puts the keys in `view`'s page the way a click does: on the deepest
    /// view under it that takes first responder (Chromium's own view).
    private func clickFocus(_ view: CEFBrowserView, _ window: NSWindow) {
        func deepest(_ v: NSView) -> NSView? {
            for sub in v.subviews.reversed() { if let hit = deepest(sub) { return hit } }
            return v.acceptsFirstResponder ? v : nil
        }
        let target = deepest(view)
        XCTAssertNotNil(target, "the page has a view that takes the keys")
        if let target { XCTAssertTrue(window.makeFirstResponder(target)) }
    }

    private func isIn(_ view: NSView, _ window: NSWindow) -> Bool {
        guard let responder = window.firstResponder as? NSView else { return false }
        return responder === view || responder.isDescendant(of: view)
    }

    private func addressFieldHasKeys(_ bar: BrowserNavigationBar, _ window: NSWindow) -> Bool {
        (window.firstResponder as? NSText)?.delegate === bar.urlField
    }

    // MARK: The rule

    func testSwitchingTabsKeepsTheKeysInTheBrowser() throws {
        try requireCEF()
        let (container, window) = host()
        let manager = manager(tabs: ["One", "Two"])
        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        settle(view(manager, 0))
        clickFocus(view(manager, 0), window)
        XCTAssertTrue(isIn(view(manager, 0), window), "the first page has the keys")

        // What a click on the second tab calls.
        manager.switchTab(id: manager.tabs[1].id)
        XCTAssertTrue(isIn(view(manager, 1), window), "the keys move with the tab at once, never to the window")
        settle(view(manager, 1))

        XCTAssertTrue(isIn(view(manager, 1), window), "the page switched to has the keys, not the window")
        XCTAssertTrue(container.handleBrowserShortcut(key: "r"), "Cmd+R still reaches the browser")
    }

    func testClosingTheSelectedTabKeepsTheKeysInTheBrowser() throws {
        try requireCEF()
        let (container, window) = host()
        let manager = manager(tabs: ["One", "Two", "Three"])
        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        manager.switchTab(id: manager.tabs[1].id)
        settle(view(manager, 1))
        clickFocus(view(manager, 1), window)
        let next = view(manager, 2)

        // What the selected tab's close button calls.
        manager.closeTab(id: manager.tabs[1].id)
        XCTAssertTrue(isIn(next, window), "the keys move to the next tab at once, never to the window")
        settle(next)

        XCTAssertTrue(isIn(next, window), "the tab that takes the closed one's place has the keys")
        XCTAssertTrue(container.handleBrowserShortcut(key: "r"), "Cmd+R still reaches the browser")
    }

    func testReturnInTheAddressFieldHandsTheKeysToThePage() throws {
        try requireCEF()
        let (container, window) = host()
        let manager = manager(tabs: ["One"])
        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        let shown = view(manager, 0)
        settle(shown)
        let bar = navigationBar(in: container)
        XCTAssertTrue(window.makeFirstResponder(bar.urlField))
        bar.urlField.stringValue = page("Committed")
        let editor = try XCTUnwrap(bar.urlField.currentEditor() as? NSTextView)

        // Return in the address field.
        _ = container.control(bar.urlField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(isIn(shown, window), "Return hands the keys to the page at once, never to the window")
        settle(shown, loads: 2)

        XCTAssertTrue(isIn(shown, window), "the page has the keys after Return, not the window")
        XCTAssertTrue(container.handleBrowserShortcut(key: "t"), "Cmd+T opens a browser tab, not a new session")
    }

    /// A new tab opens with the address field focused (Cmd+T's own step), and
    /// its page loading must not take the keys from the field.
    func testANewTabsPageDoesNotTakeTheKeysFromTheAddressField() throws {
        try requireCEF()
        let (container, window) = host()
        let manager = manager(tabs: ["One"])
        container.showBrowserContent(manager, bridge: nil, presentation: .fullCanvas)
        settle(view(manager, 0))
        let bar = navigationBar(in: container)

        // What `SessionCoordinator.addBrowserTab` does, then Cmd+T's focus step.
        let tab = manager.createTab(url: page("New"))
        let fresh = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: page("New"))
        fresh.delegate = watcher
        manager.registerBrowserView(fresh, for: tab.id)
        manager.switchTab(id: tab.id)
        bar.focusURLField()
        settle(fresh)

        XCTAssertTrue(addressFieldHasKeys(bar, window), "the address field keeps the keys while the new page loads")
        XCTAssertTrue(container.handleBrowserShortcut(key: "t"), "a second Cmd+T reaches the browser")
    }

    /// A tab's page view can take the keys before its page exists (a tab
    /// just opened or switched to), and hands them to the page once it does.
    func testAPageViewHoldsTheKeysBeforeItsPageExists() throws {
        try requireCEF()
        let (_, window) = host()
        let view = CEFBrowserView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), url: page("Early"))
        view.delegate = watcher
        window.contentView?.addSubview(view)

        XCTAssertTrue(window.makeFirstResponder(view), "the page view takes the keys before its page is created")
        settle(view)

        XCTAssertTrue(isIn(view, window), "once created, the page itself has the keys")
        view.removeFromSuperview()
    }
}
