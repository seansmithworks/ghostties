import Foundation

/// How a browser sits on the canvas.
enum BrowserPresentation: String, Codable, Equatable {
    /// Beside the terminal, in the right-hand panel.
    case split
    /// The whole canvas, with no terminal pane.
    case fullCanvas
}

/// Every way a browser reaches the canvas.
enum BrowserEntryRoute: Equatable {
    /// The composer's "Embedded Chromium browser" template.
    case composer
    /// Cmd+B ("Toggle Browser").
    case toggleShortcut
    /// `gt browser open` from a terminal's agent.
    case agentOpen
    /// A browser template launched without the composer: a project row's
    /// Option-click "+", or the tray's instant create.
    case quickCreate
    /// A browser session's own sidebar row, selected or relaunched. `created`
    /// is the presentation the session was made with; nil for a session
    /// saved before presentations were recorded.
    case browserRow(created: BrowserPresentation?)
    /// A terminal's sidebar row, for a terminal whose agent opened a browser.
    case terminalRowWithPairedBrowser
}

/// The one place that decides where a browser goes.
enum BrowserPlacement {
    static func presentation(for route: BrowserEntryRoute) -> BrowserPresentation {
        switch route {
        case .composer:
            return .fullCanvas
        case .toggleShortcut, .agentOpen, .quickCreate, .terminalRowWithPairedBrowser:
            return .split
        case .browserRow(let created):
            return created ?? .split
        }
    }

    /// What fills the canvas card's frame while a full-canvas browser is
    /// selected: History, mounted in the terminal card, takes the frame back
    /// while it is open.
    enum CanvasOccupant: Equatable {
        case terminalCard
        case browser
    }

    static func canvasOccupant(
        presentation: BrowserPresentation?,
        isHistoryPresented: Bool
    ) -> CanvasOccupant {
        presentation == .fullCanvas && !isHistoryPresented ? .browser : .terminalCard
    }
}
