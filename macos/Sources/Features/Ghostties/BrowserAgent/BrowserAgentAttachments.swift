#if DEBUG
import Foundation

/// Which DevTools targets agents are attached to through the gateway.
///
/// Each client WebSocket is one entry. A page route (`/devtools/page/<id>`)
/// attaches its client to that page for as long as the socket is open. A
/// browser route client (Playwright's `connectOverCDP`) attaches to pages
/// with CDP's `Target.attachToTarget` / auto-attach; those show up as
/// `Target.attachedToTarget` and `Target.detachedFromTarget` events in what
/// CEF sends back, keyed by CDP session id. A target is driven while any
/// client holds it.
struct BrowserAgentAttachments: Equatable {
    /// The CDP session key for the target a page route itself names.
    static let routeKey = ""

    /// Client -> (CDP session id -> target id).
    private var targetsByClient: [UUID: [String: String]] = [:]

    /// Every target at least one client is attached to.
    var drivenTargets: Set<String> {
        []
    }

    mutating func attach(client: UUID, target: String, cdpSession: String = routeKey) {}

    mutating func detach(client: UUID, cdpSession: String) {}

    /// The client's socket closed: everything it held is released.
    mutating func removeClient(_ client: UUID) {}

    /// Applies one CEF -> client text frame: a page attach or a detach.
    /// Anything else is ignored.
    mutating func observe(upstreamFrame text: String, client: UUID) {}
}
#endif
