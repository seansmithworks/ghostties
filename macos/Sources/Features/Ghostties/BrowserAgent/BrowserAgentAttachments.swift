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
        Set(targetsByClient.values.flatMap(\.values))
    }

    mutating func attach(client: UUID, target: String, cdpSession: String = routeKey) {
        targetsByClient[client, default: [:]][cdpSession] = target
    }

    mutating func detach(client: UUID, cdpSession: String) {
        targetsByClient[client]?.removeValue(forKey: cdpSession)
        if targetsByClient[client]?.isEmpty == true { targetsByClient.removeValue(forKey: client) }
    }

    /// The client's socket closed: everything it held is released.
    mutating func removeClient(_ client: UUID) {
        targetsByClient.removeValue(forKey: client)
    }

    /// Applies one CEF -> client text frame: a page attach or a detach.
    /// Anything else is ignored.
    mutating func observe(upstreamFrame text: String, client: UUID) {
        switch Self.event(in: text) {
        case .attached(let session, let target): attach(client: client, target: target, cdpSession: session)
        case .detached(let session): detach(client: client, cdpSession: session)
        case nil: break
        }
    }

    private enum Event {
        case attached(session: String, target: String)
        case detached(session: String)
    }

    /// Attach events are small; anything larger (a screenshot, a DOM
    /// snapshot) is skipped without parsing.
    private static let largestEventFrame = 16 << 10

    /// Whether `text` could be an attach or detach event: a cheap check, so
    /// the gateway parses (and locks) only for those.
    static func mayBeAttachEvent(_ text: String) -> Bool {
        text.utf8.count <= largestEventFrame
            && (text.contains("Target.attachedToTarget") || text.contains("Target.detachedFromTarget"))
    }

    private static func event(in text: String) -> Event? {
        guard mayBeAttachEvent(text),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let method = object["method"] as? String,
              let params = object["params"] as? [String: Any],
              let session = params["sessionId"] as? String
        else { return nil }
        switch method {
        case "Target.attachedToTarget":
            // Workers, iframes and the like are not a browser panel.
            guard let info = params["targetInfo"] as? [String: Any], info["type"] as? String == "page",
                  let target = info["targetId"] as? String
            else { return nil }
            return .attached(session: session, target: target)
        case "Target.detachedFromTarget":
            return .detached(session: session)
        default:
            return nil
        }
    }
}
#endif
