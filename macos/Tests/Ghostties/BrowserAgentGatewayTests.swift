import Foundation
import Network
import Testing
@testable import Ghostty

/// The gateway sits between agents and CEF's DevTools port. These tests run it
/// against a stub standing in for CEF: real CEF would answer `Browser.close`
/// by quitting the app and putting up the "Quit Ghostties?" alert, so the
/// stub is the only safe way to prove the command is never forwarded.
///
/// Debug builds only, like the gateway itself. No CEF needed.
@Suite(.serialized)
struct BrowserAgentGatewayTests {
    /// Records every text frame it receives and answers each command with an
    /// empty result, like a browser would.
    final class StubCDPServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "stub-cdp")
        private let lock = NSLock()
        private var frames: [String] = []
        private(set) var port = 0

        init() throws {
            let websocket = NWProtocolWebSocket.Options()
            websocket.autoReplyPing = true
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
            parameters.requiredInterfaceType = .loopback
            listener = try NWListener(using: parameters)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                self?.receive(on: connection)
            }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 2)
            port = Int(listener.port?.rawValue ?? 0)
        }

        func stop() { listener.cancel() }

        var received: [String] {
            lock.lock(); defer { lock.unlock() }
            return frames
        }

        private func receive(on connection: NWConnection) {
            connection.receiveMessage { [weak self] data, context, _, error in
                guard let self, error == nil else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata
                if metadata?.opcode == .text, let data {
                    let text = String(decoding: data, as: UTF8.self)
                    self.lock.lock(); self.frames.append(text); self.lock.unlock()
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = object["id"] as? Int {
                        let reply = Data(#"{"id":\#(id),"result":{}}"#.utf8)
                        let out = NWProtocolWebSocket.Metadata(opcode: .text)
                        connection.send(
                            content: reply,
                            contentContext: NWConnection.ContentContext(identifier: "r", metadata: [out]),
                            isComplete: true,
                            completion: .contentProcessed { _ in }
                        )
                    }
                }
                self.receive(on: connection)
            }
        }
    }

    /// Sends one command to the gateway's route and returns the reply text,
    /// or nil if none arrives in time.
    private func roundTrip(port: Int, path: String, command: String, timeout: TimeInterval = 5) async -> String? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)\(path)")!)
        task.resume()
        // No reply (a frame the gateway refuses to answer or forward) must not
        // hang the test: cancelling the task makes `receive` throw.
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { task.cancel() }
        do {
            try await task.send(.string(command))
            let message = try await task.receive()
            if case .string(let text) = message { return text }
            return nil
        } catch {
            return nil
        }
    }

    @Test func browserCloseIsAnsweredWithAnErrorAndNeverReachesTheBrowser() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/browser/abc"))

        let reply = await roundTrip(port: port, path: "/devtools/browser/abc", command: #"{"id":9,"method":"Browser.close"}"#)

        let text = try #require(reply, "the gateway never answered Browser.close")
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["id"] as? Int == 9)
        let error = try #require(json["error"] as? [String: Any], "Browser.close got a result, not an error")
        #expect(error["message"] as? String == "Ghostties: Browser.close is not allowed")
        #expect(!stub.received.contains { $0.contains("Browser.close") }, "Browser.close reached the browser")
    }

    @Test func createTargetIsDeniedAndNeverReachesTheBrowser() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/browser/abc"))

        let reply = await roundTrip(
            port: port, path: "/devtools/browser/abc",
            command: #"{"id":4,"method":"Target.createTarget","params":{"url":"about:blank"}}"#
        )

        let text = try #require(reply)
        #expect(text.contains("gt browser open"))
        #expect(!stub.received.contains { $0.contains("Target.createTarget") })
    }

    @Test func nestedAndBrowserScopedBypassesNeverReachTheBrowser() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/page/xyz"))

        let nested = #"{"id":3,"method":"Target.sendMessageToTarget","params":{"sessionId":"S","message":"{\"id\":1,\"method\":\"Browser.close\"}"}}"#
        let nestedReply = await roundTrip(port: port, path: "/devtools/page/xyz", command: nested)
        #expect(try #require(nestedReply, "no answer to sendMessageToTarget").contains("not allowed"))

        let attachReply = await roundTrip(
            port: port, path: "/devtools/page/xyz",
            command: #"{"id":4,"method":"Target.attachToBrowserTarget"}"#
        )
        #expect(try #require(attachReply, "no answer to attachToBrowserTarget").contains("not allowed"))

        #expect(stub.received.isEmpty, "a bypass reached the browser: \(stub.received)")
    }

    @Test func ambiguousOrUnreadableFramesNeverReachTheBrowser() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/page/xyz"))

        let frames = [
            #"{"id":1,"method":"Page.enable","method":"Browser.close"}"#,
            #"{"id":2,"method":"Browser.close","method":"Page.enable"}"#,
            #"{"id":3,"method":"Page.enable"} trailing"#,
            #"{"id":4,/*c*/"method":"Browser.close"}"#,
            "{\"id\":5,\"method\":\"Browser.close\",\"params\":{\"s\":\"\\ud800\"}}",
            "garbage",
            #"{"id":6,"method":"Target.exposeDevToolsProtocol","params":{"targetId":"T","bindingName":"b"}}"#,
        ]
        for frame in frames {
            _ = await roundTrip(port: port, path: "/devtools/page/xyz", command: frame, timeout: 1)
        }

        #expect(stub.received.isEmpty, "an ambiguous frame reached the browser: \(stub.received)")
    }

    /// CDP is text. A binary frame has no method to check, so it is never
    /// forwarded and the connection is closed.
    @Test func aBinaryFrameIsNeverForwardedAndClosesTheConnection() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/page/xyz"))

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/devtools/page/xyz")!)
        task.resume()
        try await task.send(.data(Data(#"{"id":1,"method":"Browser.close"}"#.utf8)))
        try await _Concurrency.Task.sleep(for: .seconds(1))

        #expect(stub.received.isEmpty, "a binary frame reached the browser: \(stub.received)")
        // If the gateway leaves the connection open, nothing ever arrives;
        // give up after 3s (cancelling the task unblocks `receive`).
        final class Timeout: @unchecked Sendable { var fired = false }
        let timeout = Timeout()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { timeout.fired = true; task.cancel() }
        let closed: Bool = await withCheckedContinuation { continuation in
            task.receive { result in
                if case .failure = result { continuation.resume(returning: !timeout.fired) } else { continuation.resume(returning: false) }
            }
        }
        #expect(closed, "the connection stayed open after a binary frame")
    }

    @Test func aWebPageCannotConnectBecauseItsUpgradeCarriesAnOrigin() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/browser/abc"))

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/devtools/browser/abc")!)
        request.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        let task = session.webSocketTask(with: request)
        task.resume()
        task.send(.string(#"{"id":1,"method":"Page.navigate"}"#)) { _ in }
        // A refused upgrade never produces a reply; waiting longer than the
        // allowed round trip takes is enough to tell.
        try await _Concurrency.Task.sleep(for: .seconds(2))

        // (`otherCommandsPassThroughBothWays` is the control: the same send
        // without an Origin reaches the stub within milliseconds.)
        #expect(stub.received.isEmpty, "a request with an Origin header reached the browser")
    }

    @Test func otherCommandsPassThroughBothWays() async throws {
        let stub = try StubCDPServer()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        let port = try #require(gateway.routePort(forPath: "/devtools/page/xyz"))

        let reply = await roundTrip(
            port: port, path: "/devtools/page/xyz",
            command: #"{"id":2,"method":"Page.navigate","params":{"url":"about:blank"}}"#
        )

        #expect(reply == #"{"id":2,"result":{}}"#)
        #expect(stub.received.contains { $0.contains("Page.navigate") })
    }
}
