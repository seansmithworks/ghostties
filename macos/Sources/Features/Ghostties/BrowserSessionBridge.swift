import AppKit

/// Bridges CEFBrowserView delegate callbacks to the browser UI layer.
///
/// Each browser session gets one bridge instance. It receives URL/title/loading
/// state changes from the CEF C++ handlers (dispatched to main queue) and
/// forwards them to the BrowserTabManager and BrowserNavigationBar.
@MainActor
final class BrowserSessionBridge: NSObject, CEFBrowserViewDelegate {
    let sessionId: UUID
    weak var tabManager: BrowserTabManager?
    weak var navigationBar: BrowserNavigationBar?

    /// Forwarded to the panel's inline failure state — set by
    /// `WorkspaceViewContainer` when embedding the browser view.
    var onCreationFailed: (() -> Void)?
    /// Forwarded so the panel can dismiss its inline failure state once the
    /// browser materialises (including after a retry).
    var onCreationSucceeded: (() -> Void)?

    /// Called with the tab whose browser was closed from outside the app (an
    /// agent's `Target.closeTarget` / `Page.close`, or `window.close()`).
    var onCloseRequested: ((UUID) -> Void)?

    init(sessionId: UUID, tabManager: BrowserTabManager) {
        self.sessionId = sessionId
        self.tabManager = tabManager
        super.init()
    }

    // MARK: - CEFBrowserViewDelegate

    /// The tab `view` belongs to. One bridge serves every tab of a browser,
    /// so a callback is attributed by its view, never by "the" active tab.
    private func tabId(for view: CEFBrowserView) -> UUID? {
        tabManager?.browserViews.first(where: { $0.value === view })?.key
    }

    func browserView(_ view: CEFBrowserView, didChangeURL url: String) {
        guard let tabId = tabId(for: view) else { return }
        tabManager?.updateTab(id: tabId, url: url)
        // The bar shows the tab on screen; a background tab only updates its record.
        if tabId == tabManager?.activeTabId {
            navigationBar?.urlField.stringValue = url
        }
    }

    func browserView(_ view: CEFBrowserView, didChangeTitle title: String) {
        guard let tabId = tabId(for: view) else { return }
        tabManager?.updateTab(id: tabId, title: title)
    }

    func browserView(_ view: CEFBrowserView, didChangeLoadingState isLoading: Bool, canGoBack: Bool, canGoForward forward: Bool) {
        guard let tabId = tabId(for: view) else { return }
        tabManager?.updateTab(id: tabId, isLoading: isLoading)
        guard tabId == tabManager?.activeTabId else { return }
        navigationBar?.reflect(isLoading: isLoading, canGoBack: canGoBack, canGoForward: forward)
    }

    func browserViewDidFail(toCreate view: CEFBrowserView) {
        onCreationFailed?()
    }

    func browserViewDidCreate(_ view: CEFBrowserView) {
        onCreationSucceeded?()
    }

    func browserViewDidRequestClose(_ view: CEFBrowserView) {
        guard let tabId = tabId(for: view) else { return }
        onCloseRequested?(tabId)
    }
}
