#if DEBUG
import AppKit
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

    /// The process-wide gateway. Started by the first `SessionCoordinator`.
    static let shared = BrowserAgentGateway(upstreamPort: { Int(CEFBridgeManager.remoteDebuggingPort) })

    /// Whether the app should start the process-wide gateway by itself.
    /// Not under XCTest: the hosted test run launches the real app, and a
    /// gateway started by its coordinators would publish `cdp.json` into the
    /// real state directory. A test that wants a gateway starts its own.
    static func shouldAutoStart(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        xctestLoaded: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil && !xctestLoaded
    }

    /// Bearer token the `gt` control route requires. Handed to terminals as
    /// `GHOSTTIES_BROWSER_TOKEN` and to tools through `cdp.json`.
    let token: String = {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess { bytes = (0..<32).map { _ in UInt8.random(in: 0...255) } }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }()

    /// Answers `POST /ghostties/browser/open`. Set by the app once a
    /// coordinator exists; nil until then.
    var openHandler: (@Sendable (_ sessionId: UUID, _ url: String) async -> BrowserAgentHTTP.Response)? {
        get { lock.lock(); defer { lock.unlock() }; return _openHandler }
        set { lock.lock(); _openHandler = newValue; lock.unlock() }
    }
    private var _openHandler: (@Sendable (UUID, String) async -> BrowserAgentHTTP.Response)?

    /// Called with the full set of driven targets whenever it changes (an
    /// agent attached to or let go of a page), on a gateway queue.
    var onDrivenTargetsChange: (@Sendable (Set<String>) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onDrivenTargetsChange }
        set { lock.lock(); _onDrivenTargetsChange = newValue; lock.unlock() }
    }
    private var _onDrivenTargetsChange: (@Sendable (Set<String>) -> Void)?

    private var attachments = BrowserAgentAttachments()

    /// Applies `change` to the attachments and reports the driven set if it
    /// moved. Reports under the lock, so changes from different routes'
    /// queues arrive in order.
    fileprivate func updateAttachments(_ change: (inout BrowserAgentAttachments) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let before = attachments.drivenTargets
        change(&attachments)
        let after = attachments.drivenTargets
        if after != before { _onDrivenTargetsChange?(after) }
    }

    private var http: BrowserAgentHTTP.Server?
    private var publisher: BrowserControlPublisher?

    /// Port of the HTTP endpoint (`/json/*` and the control route), or 0
    /// before `start`.
    var httpPort: Int {
        lock.lock(); defer { lock.unlock() }
        return http?.port ?? 0
    }

    /// `http://127.0.0.1:<port>`, or nil before `start`.
    var endpoint: String? {
        let port = httpPort
        return port > 0 ? "http://127.0.0.1:\(port)" : nil
    }

    /// Starts the HTTP endpoint (once) and, when `directory` is given,
    /// publishes `cdp.json` there. Returns whether the gateway is running.
    @discardableResult
    func start(publishingTo directory: URL?) -> Bool {
        lock.lock()
        if http != nil { lock.unlock(); return true }
        lock.unlock()

        let server = BrowserAgentHTTP.Server { [weak self] request, respond in
            guard let self else { respond(.json(503, ["error": "gateway stopped"])); return }
            self.handle(request, respond)
        }
        guard let port = server.start() else { return false }
        lock.lock()
        http = server
        lock.unlock()

        if let directory {
            let publisher = BrowserControlPublisher(directory: directory)
            try? publisher.publish(endpoint: "http://127.0.0.1:\(port)", token: token)
            lock.lock()
            self.publisher = publisher
            lock.unlock()
            // A quit takes cdp.json with it; a crash leaves it behind, which
            // is why it also records the pid.
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.stop() }
        }
        return true
    }

    func stop() {
        lock.lock()
        let all = routes.values
        routes.removeAll()
        let server = http
        http = nil
        let publisher = publisher
        self.publisher = nil
        lock.unlock()
        for route in all { route.cancel() }
        server?.stop()
        publisher?.remove()
    }

    // MARK: - HTTP

    private static let jsonPaths: Set<String> = ["/json", "/json/list", "/json/version"]

    private func handle(_ request: BrowserAgentHTTP.Request, _ respond: @escaping @Sendable (BrowserAgentHTTP.Response) -> Void) {
        // A web page can aim a DNS name at 127.0.0.1; its requests carry that
        // name as Host. Only our own loopback spellings pass.
        let port = httpPort
        guard let host = request.headers["host"], host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            respond(.json(403, ["error": "Ghostties: unexpected Host header"]))
            return
        }

        // Playwright asks for "/json/version/" with a trailing slash.
        var path = request.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/json/new" {
            respond(.json(403, ["error": "Ghostties: /json/new is not allowed; use `gt browser open`"]))
        } else if request.method == "GET", Self.jsonPaths.contains(path) {
            proxyJSON(path, rewrite: true, respond)
        } else if request.method == "GET", path == "/json/protocol"
                    || path.hasPrefix("/json/close/") || path.hasPrefix("/json/activate/") {
            proxyJSON(path, rewrite: false, respond)
        } else if request.method == "POST", path == "/ghostties/browser/open" {
            openBrowser(request, respond)
        } else {
            respond(.json(404, ["error": "not found"]))
        }
    }

    private func proxyJSON(_ path: String, rewrite: Bool, _ respond: @escaping @Sendable (BrowserAgentHTTP.Response) -> Void) {
        let raw = upstreamPort()
        guard raw > 0, let url = URL(string: "http://127.0.0.1:\(raw)\(path)") else {
            respond(.json(502, ["error": "the browser is not running yet; run `gt browser open <url>`"]))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Chromium's DevTools server drops connections between requests; a
        // reused one fails. Ask for a fresh one each time.
        request.setValue("close", forHTTPHeaderField: "Connection")
        fetch(request, attemptsLeft: 5) { [weak self] data, response, error in
            guard let self, let data, let http = response as? HTTPURLResponse else {
                respond(.json(502, ["error": "the browser did not answer: \(error?.localizedDescription ?? "no response")"]))
                return
            }
            var body = data
            if rewrite {
                body = CDPJSONRewrite.rewrite(data, rawPort: raw) { self.routePort(forPath: $0) }
                if path != "/json/version" { self.pruneRoutes(keepingPagesIn: body) }
            }
            var out = BrowserAgentHTTP.Response(status: http.statusCode, body: body)
            if let type = http.value(forHTTPHeaderField: "Content-Type") { out.contentType = type }
            respond(out)
        }
    }

    /// GET with a few retries: CEF's DevTools server comes up shortly after
    /// the browser does, and can refuse the very first connection.
    private func fetch(
        _ request: URLRequest,
        attemptsLeft: Int,
        completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) {
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if data == nil, attemptsLeft > 1, let self {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    self.fetch(request, attemptsLeft: attemptsLeft - 1, completion: completion)
                }
                return
            }
            completion(data, response, error)
        }.resume()
    }

    private func openBrowser(_ request: BrowserAgentHTTP.Request, _ respond: @escaping @Sendable (BrowserAgentHTTP.Response) -> Void) {
        guard request.headers["authorization"] == "Bearer \(token)" else {
            respond(.json(401, ["error": "missing or wrong token"]))
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let sessionId = (object["sessionId"] as? String).flatMap(UUID.init(uuidString:)),
              let url = object["url"] as? String
        else {
            respond(.json(400, ["error": "body must be {\"sessionId\": <uuid>, \"url\": <string>}"]))
            return
        }
        guard let handler = openHandler else {
            respond(.json(503, ["error": "browser control is not ready"]))
            return
        }
        _Concurrency.Task { respond(await handler(sessionId, url)) }
    }

    /// Drops page routes whose page is no longer in `listJSON` (a `/json/list`
    /// body, already rewritten). Keeps the browser route.
    private func pruneRoutes(keepingPagesIn listJSON: Data) {
        guard let entries = try? JSONSerialization.jsonObject(with: listJSON) as? [[String: Any]] else { return }
        let live = Set(entries.compactMap { entry -> String? in
            guard let url = entry["webSocketDebuggerUrl"] as? String, let range = url.range(of: "/devtools/page/") else { return nil }
            return String(url[range.lowerBound...])
        })
        lock.lock()
        let stale = routes.filter { $0.key.hasPrefix("/devtools/page/") && !live.contains($0.key) }
        for key in stale.keys { routes.removeValue(forKey: key) }
        lock.unlock()
        for route in stale.values { route.cancel() }
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
            let queue = DispatchQueue(label: "ghostties.browser-agent.route")
            // Browsers always send an Origin header on WebSocket upgrades;
            // agents' CDP clients do not. Refusing any upgrade that carries
            // one stops a web page from reaching the browser through here.
            websocket.setClientRequestHandler(queue) { _, headers in
                let fromWebPage = headers.contains { $0.name.lowercased() == "origin" }
                return NWProtocolWebSocket.Response(status: fromWebPage ? .reject : .accept, subprotocol: nil)
            }
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters) else { return nil }
            self.listener = listener
            self.queue = queue

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
            // The client is attached to a page route's page for as long as
            // its socket is open; to any other page while CEF says so.
            let client = UUID()
            let pagePrefix = "/devtools/page/"
            let target = path.hasPrefix(pagePrefix) ? String(path.dropFirst(pagePrefix.count)) : nil
            gateway.updateAttachments {
                $0.connect(client: client)
                if let target { $0.attach(client: client, target: target) }
            }
            session.onUpstreamText = { [weak gateway] text in
                guard BrowserAgentAttachments.mayBeAttachEvent(text) else { return }
                gateway?.updateAttachments { $0.observe(upstreamFrame: text, client: client) }
            }
            session.onClose = { [weak self, weak gateway] in
                self?.sessionsLock.lock()
                self?.sessions.removeValue(forKey: key)
                self?.sessionsLock.unlock()
                gateway?.updateAttachments { $0.removeClient(client) }
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
        /// Every text frame CEF sends this client, before it is forwarded.
        var onUpstreamText: ((String) -> Void)?

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
                    // CDP is text. A binary frame has no method the policy
                    // can check, so it is never forwarded.
                    self.close()
                    return
                default:
                    break
                }
                self.receiveFromClient()
            }
        }

        private func handleClientText(_ text: String) {
            switch CDPPolicy.action(forClientFrame: text) {
            case .forward:
                upstream.send(.string(text)) { [weak self] error in
                    if error != nil { self?.close() }
                }
            case .reply(let response):
                sendToClient(Data(response.utf8), opcode: .text)
            case .drop:
                break
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
                    case .string(let text):
                        self.onUpstreamText?(text)
                        self.sendToClient(Data(text.utf8), opcode: .text)
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
