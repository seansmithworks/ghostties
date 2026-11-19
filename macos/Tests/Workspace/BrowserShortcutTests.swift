import AppKit
import Testing
@testable import Ghostty

struct BrowserShortcutTests {
    // MARK: - Routing

    @Test func browserFocusedRoutesEachKeyToBrowserAction() {
        let routed = ["t", "l", "r", "[", "]"].map { BrowserShortcut.route(key: $0, browserHasFocus: true) }
        #expect(routed == [.newTab, .focusURLField, .reload, .back, .forward])
    }

    @Test func cmdTIsNotTheBrowsersWhenFocusIsElsewhere() {
        // nil means the existing Cmd+T handling (New Session) runs unchanged.
        #expect(BrowserShortcut.route(key: "t", browserHasFocus: false) == nil)
        #expect(BrowserShortcut.route(key: "T", browserHasFocus: false) == nil)
    }

    @Test func otherKeysFallThroughEvenWhenBrowserFocused() {
        #expect(BrowserShortcut.route(key: "w", browserHasFocus: true) == nil)
        #expect(BrowserShortcut.route(key: nil, browserHasFocus: true) == nil)
    }

    // MARK: - Focus detection

    @MainActor
    private func makeWindow() -> (NSWindow, NSView, NSTextField, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = root
        let contentArea = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let page = FocusableView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        contentArea.addSubview(page)
        let urlField = NSTextField(frame: NSRect(x: 0, y: 220, width: 300, height: 24))
        let terminal = FocusableView(frame: NSRect(x: 0, y: 250, width: 100, height: 40))
        root.addSubview(contentArea)
        root.addSubview(urlField)
        root.addSubview(terminal)
        return (window, contentArea, urlField, terminal)
    }

    @Test @MainActor func pageFocusCountsAsBrowser() {
        let (window, contentArea, urlField, _) = makeWindow()
        window.makeFirstResponder(contentArea.subviews[0])
        #expect(BrowserShortcut.browserHasFocus(
            firstResponder: window.firstResponder, contentArea: contentArea, urlField: urlField))
    }

    @Test @MainActor func urlFieldEditingCountsAsBrowser() {
        let (window, contentArea, urlField, _) = makeWindow()
        window.makeFirstResponder(urlField)
        // While editing, the first responder is the shared field editor.
        #expect(window.firstResponder is NSText)
        #expect(BrowserShortcut.browserHasFocus(
            firstResponder: window.firstResponder, contentArea: contentArea, urlField: urlField))
    }

    @Test @MainActor func terminalFocusIsNotBrowser() {
        let (window, contentArea, urlField, terminal) = makeWindow()
        window.makeFirstResponder(terminal)
        #expect(!BrowserShortcut.browserHasFocus(
            firstResponder: window.firstResponder, contentArea: contentArea, urlField: urlField))
    }

    @Test @MainActor func anotherTextFieldIsNotBrowser() {
        let (window, contentArea, urlField, _) = makeWindow()
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(other)
        window.makeFirstResponder(other)
        #expect(!BrowserShortcut.browserHasFocus(
            firstResponder: window.firstResponder, contentArea: contentArea, urlField: urlField))
        #expect(!BrowserShortcut.browserHasFocus(
            firstResponder: nil, contentArea: contentArea, urlField: urlField))
    }

    /// The Cmd+T decision end to end: browser focus takes it, terminal focus does not.
    @Test @MainActor func cmdTFollowsFocus() {
        let (window, contentArea, urlField, terminal) = makeWindow()
        func route() -> BrowserShortcut? {
            BrowserShortcut.route(
                key: "t",
                browserHasFocus: BrowserShortcut.browserHasFocus(
                    firstResponder: window.firstResponder, contentArea: contentArea, urlField: urlField))
        }
        window.makeFirstResponder(contentArea.subviews[0])
        #expect(route() == .newTab)
        window.makeFirstResponder(terminal)
        #expect(route() == nil)
    }
}

private final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
