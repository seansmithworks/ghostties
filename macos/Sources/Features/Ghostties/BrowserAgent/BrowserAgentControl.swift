#if DEBUG
import Foundation

/// Connects the gateway's `POST /ghostties/browser/open` to the window that
/// owns the asking terminal. The gateway is process-wide; each window has its
/// own `SessionCoordinator`, registered here (weakly) as it starts.
@MainActor
enum BrowserAgentControl {
    private struct Entry { weak var coordinator: SessionCoordinator? }
    private static var entries: [Entry] = []

    static func register(_ coordinator: SessionCoordinator) {
        entries.removeAll { $0.coordinator == nil }
        if !entries.contains(where: { $0.coordinator === coordinator }) {
            entries.append(Entry(coordinator: coordinator))
        }
        BrowserAgentGateway.shared.openHandler = { sessionId, url in
            await BrowserAgentControl.open(sessionId: sessionId, url: url)
        }
    }

    /// Routes to the coordinator that owns the terminal `sessionId`.
    static func open(sessionId: UUID, url: String) async -> BrowserAgentHTTP.Response {
        guard let coordinator = entries.compactMap(\.coordinator).first(where: { $0.ownsTerminalSession(sessionId) }) else {
            return .json(404, ["error": "no such terminal session"])
        }
        return await coordinator.openAgentBrowser(sessionId: sessionId, url: url)
    }
}
#endif
