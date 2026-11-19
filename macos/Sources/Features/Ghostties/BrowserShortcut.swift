import AppKit

/// The Cmd-shortcuts that act on the embedded browser, but only while the
/// browser has keyboard focus. Anywhere else they are not ours: Cmd+T keeps
/// opening a new session, and Cmd+L/R/[/] fall through untouched.
enum BrowserShortcut: Equatable {
    case newTab
    case focusURLField
    case reload
    case back
    case forward

    /// The shortcut for `key` (an event's `charactersIgnoringModifiers`, with
    /// Command as the only modifier), or nil when the browser does not own it.
    /// This is the one place focus decides: a nil result means "not the
    /// browser's", so the caller leaves the key to its existing handling.
    static func route(key: String?, browserHasFocus: Bool) -> BrowserShortcut? {
        guard browserHasFocus else { return nil }
        switch key?.lowercased() {
        case "t": return .newTab
        case "l": return .focusURLField
        case "r": return .reload
        case "[": return .back
        case "]": return .forward
        default: return nil
        }
    }

    /// Whether `responder` is the browser: the page (CEF's view lives under
    /// `contentArea`) or the URL field, whose text is edited by a shared
    /// field editor that names the field as its delegate.
    @MainActor
    static func browserHasFocus(
        firstResponder responder: NSResponder?,
        contentArea: NSView,
        urlField: NSTextField
    ) -> Bool {
        if let editor = responder as? NSText, editor.delegate === urlField { return true }
        if responder === urlField { return true }
        guard let view = responder as? NSView else { return false }
        return view === contentArea || view.isDescendant(of: contentArea)
    }
}
