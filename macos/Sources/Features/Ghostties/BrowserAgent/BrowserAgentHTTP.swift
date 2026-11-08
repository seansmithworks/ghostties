#if DEBUG
import Foundation
import Network

/// A deliberately small HTTP/1.1 server for the gateway's own endpoints
/// (`/json/*` and the `gt` control route). It speaks GET and POST with
/// `Content-Length` bodies only and closes the connection after every
/// response; anything fancier is rejected. WebSockets are not handled here.
enum BrowserAgentHTTP {
    struct Request: Equatable {
        var method: String
        /// Path without the query string.
        var path: String
        /// Header names lowercased.
        var headers: [String: String]
        var body: Data
    }

    struct Response {
        var status: Int
        var body: Data
        var contentType = "application/json; charset=UTF-8"

        static func json(_ status: Int, _ object: [String: Any]) -> Response {
            let data = (try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            )) ?? Data("{}".utf8)
            return Response(status: status, body: data)
        }
    }

    enum Parse: Equatable {
        /// More bytes are needed.
        case incomplete
        case malformed
        case tooLarge
        case request(Request)
    }

    static let maxHeadBytes = 16 * 1024
    static let maxBodyBytes = 64 * 1024

    /// Parses one request from the start of `data`. Pure.
    static func parse(_ data: Data) -> Parse {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headEnd = data.range(of: terminator) else {
            return data.count > maxHeadBytes ? .tooLarge : .incomplete
        }
        guard headEnd.lowerBound <= maxHeadBytes else { return .tooLarge }

        let head = String(decoding: data[data.startIndex..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        // Chunked or otherwise framed bodies are not supported.
        if headers["transfer-encoding"] != nil { return .malformed }

        var length = 0
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else { return .malformed }
            guard parsed <= maxBodyBytes else { return .tooLarge }
            length = parsed
        }
        let bodyStart = headEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]

        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .request(Request(method: String(requestLine[0]), path: path, headers: headers, body: Data(body)))
    }

    static func serialize(_ response: Response) -> Data {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        case 502: reason = "Bad Gateway"
        case 504: reason = "Gateway Timeout"
        default: reason = "Status"
        }
        var out = Data("HTTP/1.1 \(response.status) \(reason)\r\n".utf8)
        out.append(Data("Content-Type: \(response.contentType)\r\n".utf8))
        out.append(Data("Content-Length: \(response.body.count)\r\n".utf8))
        out.append(Data("Connection: close\r\n\r\n".utf8))
        out.append(response.body)
        return out
    }

    // MARK: - Server

    final class Server: @unchecked Sendable {
        typealias Handler = @Sendable (Request, @escaping @Sendable (Response) -> Void) -> Void

        private let handler: Handler
        private let queue = DispatchQueue(label: "ghostties.browser-agent.http")
        private var listener: NWListener?
        private(set) var port = 0

        init(handler: @escaping Handler) {
            self.handler = handler
        }

        /// Binds a random loopback port. Returns it, or nil if it could not
        /// be bound within two seconds.
        func start() -> Int? {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters) else { return nil }
            let ready = DispatchSemaphore(value: 0)
            let failed = FailureFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: ready.signal()
                case .failed, .cancelled: failed.value = true; ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 2) == .success, !failed.value,
                  let bound = listener.port?.rawValue
            else {
                listener.cancel()
                return nil
            }
            self.listener = listener
            port = Int(bound)
            return port
        }

        func stop() {
            listener?.cancel()
            listener = nil
        }

        private final class FailureFlag: @unchecked Sendable { var value = false }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: queue)
            // A client that never finishes its request does not get to hold the connection.
            queue.asyncAfter(deadline: .now() + 30) { connection.cancel() }
            read(connection, buffer: Data())
        }

        private func read(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch BrowserAgentHTTP.parse(buffer) {
                case .request(let request):
                    self.handler(request) { response in
                        self.send(response, on: connection)
                    }
                case .malformed:
                    self.send(.json(400, ["error": "malformed request"]), on: connection)
                case .tooLarge:
                    self.send(.json(413, ["error": "request too large"]), on: connection)
                case .incomplete:
                    if error != nil || isComplete {
                        connection.cancel()
                    } else {
                        self.read(connection, buffer: buffer)
                    }
                }
            }
        }

        private func send(_ response: Response, on connection: NWConnection) {
            connection.send(
                content: BrowserAgentHTTP.serialize(response),
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }
}
#endif
