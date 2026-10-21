#if DEBUG
import Foundation
import Network

/// A loopback proxy between agents and the app's browser.
///
/// Agents speak the Chrome DevTools Protocol. CEF's own debugging port is
/// never published; the agent connects here instead, and the gateway forwards
/// each WebSocket to CEF's real port. Debug builds only (see
/// `CEFBridgeManager.remoteDebuggingPort`): Release never opens the port and
/// never compiles this file.
///
/// Network.framework's WebSocket server does not expose the request path, so
/// each upstream path (`/devtools/browser/<id>`, `/devtools/page/<id>`) gets
/// its own listener port, a "route". The route's port picks the upstream path;
/// the path a client puts in its URL is ignored.
final class BrowserAgentGateway: @unchecked Sendable {
    /// Largest WebSocket message either side may send (screenshots, DOM
    /// snapshots).
    static let maximumMessageSize = 64 << 20

    private let upstreamPort: () -> Int
    private let lock = NSLock()
    private var routes: [String: Route] = [:]

    /// - Parameter upstreamPort: where CEF's DevTools server listens. A
    ///   closure so the process-wide gateway can ask CEF after it starts.
    init(upstreamPort: @escaping () -> Int) {
        self.upstreamPort = upstreamPort
    }

    func stop() {
        lock.lock()
        let all = routes.values
        routes.removeAll()
        lock.unlock()
        for route in all { route.cancel() }
    }

    // MARK: - Routes

    /// The loopback port whose WebSocket connections proxy to `path` on CEF.
    /// Creates the listener on first use. Blocks briefly while it comes up,
    /// so call it from outside the gateway's own queues.
    func routePort(forPath path: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = routes[path] { return existing.port }
        guard let route = Route(path: path, gateway: self) else { return nil }
        routes[path] = route
        return route.port
    }

    private final class Flag: @unchecked Sendable { var value = false }

    /// One WebSocket listener, fixed to one upstream path.
    private final class Route: @unchecked Sendable {
        let path: String
        private(set) var port = 0
        private let listener: NWListener
        private let queue: DispatchQueue
        private var sessions: [ObjectIdentifier: ProxySession] = [:]
        private let sessionsLock = NSLock()

        init?(path: String, gateway: BrowserAgentGateway) {
            self.path = path
            let websocket = NWProtocolWebSocket.Options()
            websocket.autoReplyPing = true
            websocket.maximumMessageSize = BrowserAgentGateway.maximumMessageSize
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters) else { return nil }
            self.listener = listener
            self.queue = DispatchQueue(label: "ghostties.browser-agent.route")

            let ready = DispatchSemaphore(value: 0)
            let failed = Flag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: ready.signal()
                case .failed, .cancelled: failed.value = true; ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self, weak gateway] connection in
                guard let self, let gateway else { connection.cancel(); return }
                self.accept(connection, gateway: gateway)
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 2) == .success, !failed.value,
                  let port = listener.port?.rawValue
            else {
                listener.cancel()
                return nil
            }
            self.port = Int(port)
        }

        func cancel() {
            listener.cancel()
            sessionsLock.lock()
            let all = sessions.values
            sessions.removeAll()
            sessionsLock.unlock()
            for session in all { session.close() }
        }

        private func accept(_ connection: NWConnection, gateway: BrowserAgentGateway) {
            let upstream = gateway.upstreamPort()
            guard upstream > 0, let url = URL(string: "ws://127.0.0.1:\(upstream)\(path)") else {
                connection.cancel()
                return
            }
            let session = ProxySession(client: connection, upstreamURL: url, queue: queue)
            let key = ObjectIdentifier(session)
            sessionsLock.lock()
            sessions[key] = session
            sessionsLock.unlock()
            session.onClose = { [weak self] in
                self?.sessionsLock.lock()
                self?.sessions.removeValue(forKey: key)
                self?.sessionsLock.unlock()
            }
            session.start()
        }
    }

    // MARK: - One client <-> CEF pairing

    private final class ProxySession: @unchecked Sendable {
        private let client: NWConnection
        private let upstream: URLSessionWebSocketTask
        private let urlSession: URLSession
        private let queue: DispatchQueue
        private let stateLock = NSLock()
        private var closed = false
        var onClose: (() -> Void)?

        init(client: NWConnection, upstreamURL: URL, queue: DispatchQueue) {
            self.client = client
            self.queue = queue
            self.urlSession = URLSession(configuration: .ephemeral)
            self.upstream = urlSession.webSocketTask(with: upstreamURL)
            self.upstream.maximumMessageSize = BrowserAgentGateway.maximumMessageSize
        }

        func start() {
            client.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled: self?.close()
                default: break
                }
            }
            client.start(queue: queue)
            upstream.resume()
            receiveFromClient()
            receiveFromUpstream()
        }

        func close() {
            stateLock.lock()
            if closed { stateLock.unlock(); return }
            closed = true
            stateLock.unlock()
            client.cancel()
            upstream.cancel(with: .goingAway, reason: nil)
            urlSession.invalidateAndCancel()
            onClose?()
        }

        // client -> CEF

        private func receiveFromClient() {
            client.receiveMessage { [weak self] data, context, _, error in
                guard let self else { return }
                if error != nil { self.close(); return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata
                switch metadata?.opcode {
                case .close:
                    self.close()
                    return
                case .text:
                    self.handleClientText(String(decoding: data ?? Data(), as: UTF8.self))
                case .binary:
                    self.upstream.send(.data(data ?? Data())) { _ in }
                default:
                    break
                }
                self.receiveFromClient()
            }
        }

        private func handleClientText(_ text: String) {
            upstream.send(.string(text)) { [weak self] error in
                if error != nil { self?.close() }
            }
        }

        // CEF -> client

        private func receiveFromUpstream() {
            upstream.receive { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure:
                    self.close()
                case .success(let message):
                    switch message {
                    case .string(let text): self.sendToClient(Data(text.utf8), opcode: .text)
                    case .data(let data): self.sendToClient(data, opcode: .binary)
                    @unknown default: break
                    }
                    self.receiveFromUpstream()
                }
            }
        }

        func sendToClient(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
            let context = NWConnection.ContentContext(identifier: "cdp", metadata: [metadata])
            client.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }
}
#endif
