import Foundation

/// The client side of `gt browser open`: finds the app's browser gateway from
/// the terminal's environment, asks it to open a URL for this terminal, and
/// interprets the answer. The gateway lives in the Ghostties Dev app
/// (Debug builds); a terminal that has no gateway in its environment cannot
/// use this.
public enum BrowserControl {
    /// Environment variable names the app stamps into every terminal it spawns.
    public enum Variable {
        public static let endpoint = "GHOSTTIES_CDP_ENDPOINT"
        public static let token = "GHOSTTIES_BROWSER_TOKEN"
        public static let sessionId = "GHOSTTIES_SESSION_ID"
    }

    public struct Connection: Equatable {
        public let endpoint: String
        public let token: String
        public let sessionId: String
    }

    /// How long the app gets to open the browser and report its target.
    public static let timeout: TimeInterval = 20

    /// Reads the connection from `environment`. Throws a usage error naming
    /// what is missing when this is not a Ghostties Dev terminal.
    public static func connection(from environment: [String: String]) throws -> Connection {
        func value(_ name: String) -> String? {
            guard let v = environment[name], !v.isEmpty else { return nil }
            return v
        }
        guard let endpoint = value(Variable.endpoint),
              let token = value(Variable.token),
              let sessionId = value(Variable.sessionId)
        else {
            throw CLIError.usage("browser control needs a Ghostties Dev terminal")
        }
        return Connection(endpoint: endpoint, token: token, sessionId: sessionId)
    }

    /// The request that asks the app to open `url` for this terminal.
    public static func openRequest(for connection: Connection, url: String) throws -> URLRequest {
        guard var components = URLComponents(string: connection.endpoint) else {
            throw CLIError.usage("\(Variable.endpoint) is not a URL: \(connection.endpoint)")
        }
        components.path = "/ghostties/browser/open"
        guard let target = components.url else {
            throw CLIError.usage("\(Variable.endpoint) is not a URL: \(connection.endpoint)")
        }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["sessionId": connection.sessionId, "url": url],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return request
    }

    /// Turns the app's answer into the text `gt` prints, or an error carrying
    /// the app's own message.
    public static func interpret(status: Int, body: Data) throws -> String {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
            throw CLIError.io(message ?? "the app answered HTTP \(status)")
        }
        return text
    }

    /// Sends `request` and waits for the answer. Synchronous: a CLI has
    /// nothing else to do meanwhile.
    public static func send(_ request: URLRequest) throws -> (status: Int, body: Data) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(CLIError.io("no answer"))
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data()))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        switch result {
        case .success(let (status, body)):
            return (status, body)
        case .failure(let error):
            throw CLIError.io("could not reach the app's browser gateway: \(error.localizedDescription)")
        }
    }

    /// `gt browser open <url>` end to end. `transport` is swappable for tests.
    public static func open(
        url: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: (URLRequest) throws -> (status: Int, body: Data) = send
    ) throws -> String {
        let connection = try connection(from: environment)
        let request = try openRequest(for: connection, url: url)
        let (status, body) = try transport(request)
        return try interpret(status: status, body: body)
    }
}
