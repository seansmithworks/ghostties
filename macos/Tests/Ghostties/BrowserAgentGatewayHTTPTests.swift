import Foundation
import Testing
@testable import Ghostty

/// The gateway's HTTP side against a stub browser: `/json/*` is proxied with
/// every address rewritten, `/json/new` is refused, and the control route
/// needs the token. The stub is another `BrowserAgentHTTP.Server` serving what
/// Chromium would. No CEF.
@Suite(.serialized)
struct BrowserAgentGatewayHTTPTests {
    private func startStubBrowser() throws -> BrowserAgentHTTP.Server {
        var stubPort = 0
        let server = BrowserAgentHTTP.Server { request, respond in
            let ws = "ws://127.0.0.1:\(stubPort)/devtools"
            switch request.path {
            case "/json/version":
                respond(.json(200, ["Browser": "Chrome/144", "webSocketDebuggerUrl": "\(ws)/browser/abc"]))
            case "/json/list", "/json":
                let list = [["id": "A", "type": "page", "webSocketDebuggerUrl": "\(ws)/page/A"]]
                let data = try! JSONSerialization.data(withJSONObject: list, options: [.withoutEscapingSlashes])
                respond(.init(status: 200, body: data))
            default:
                respond(.json(404, [:]))
            }
        }
        stubPort = try #require(server.start())
        return server
    }

    private func get(_ url: String, headers: [String: String] = [:]) async throws -> (Int, Data) {
        var request = URLRequest(url: URL(string: url)!)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    @Test func versionAndListAreRewrittenToGatewayRoutes() async throws {
        let stub = try startStubBrowser()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        #expect(gateway.start(publishingTo: nil))
        let base = try #require(gateway.endpoint)

        let (status, versionData) = try await get("\(base)/json/version")
        #expect(status == 200)
        let version = String(decoding: versionData, as: UTF8.self)
        #expect(!version.contains("\(stub.port)"), "the browser's own port leaked: \(version)")
        let browserPort = try #require(gateway.routePort(forPath: "/devtools/browser/abc"))
        #expect(version.contains("ws://127.0.0.1:\(browserPort)/devtools/browser/abc"))

        // Playwright's connectOverCDP asks for the trailing-slash spelling.
        let (slashStatus, _) = try await get("\(base)/json/version/")
        #expect(slashStatus == 200)

        let (_, listData) = try await get("\(base)/json/list")
        let list = String(decoding: listData, as: UTF8.self)
        #expect(!list.contains("\(stub.port)"), "the browser's own port leaked: \(list)")
        let pagePort = try #require(gateway.routePort(forPath: "/devtools/page/A"))
        #expect(list.contains("ws://127.0.0.1:\(pagePort)/devtools/page/A"))
    }

    @Test func jsonNewIsRefused() async throws {
        let stub = try startStubBrowser()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        gateway.start(publishingTo: nil)
        let base = try #require(gateway.endpoint)

        let (status, data) = try await get("\(base)/json/new?about:blank")
        #expect(status == 403)
        #expect(String(decoding: data, as: UTF8.self).contains("gt browser open"))
    }

    @Test func aForeignHostHeaderIsRefused() async throws {
        let stub = try startStubBrowser()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        gateway.start(publishingTo: nil)
        let base = try #require(gateway.endpoint)

        let (status, _) = try await get("\(base)/json/version", headers: ["Host": "rebind.example:80"])
        #expect(status == 403)
    }

    @Test func controlRouteNeedsTheToken() async throws {
        let stub = try startStubBrowser()
        defer { stub.stop() }
        let gateway = BrowserAgentGateway(upstreamPort: { stub.port })
        defer { gateway.stop() }
        gateway.start(publishingTo: nil)
        let base = try #require(gateway.endpoint)
        let session = UUID()
        gateway.openHandler = { id, url in .json(200, ["sessionId": id.uuidString, "url": url]) }

        func post(token: String?) async throws -> Int {
            var request = URLRequest(url: URL(string: "\(base)/ghostties/browser/open")!)
            request.httpMethod = "POST"
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.httpBody = Data(#"{"sessionId":"\#(session.uuidString)","url":"http://127.0.0.1/"}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        }

        #expect(try await post(token: nil) == 401)
        #expect(try await post(token: "wrong") == 401)
        #expect(try await post(token: gateway.token) == 200)
    }

    /// A hosted test run launches the real app, whose coordinators would start
    /// the shared gateway and publish cdp.json into the real state directory
    /// (overwriting, and on stop deleting, a running Dev's). Under XCTest the
    /// gateway only runs when a test starts one explicitly.
    @Test func theAppDoesNotAutoStartTheGatewayUnderXCTest() {
        #expect(!BrowserAgentGateway.shouldAutoStart(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"], xctestLoaded: false))
        #expect(!BrowserAgentGateway.shouldAutoStart(environment: [:], xctestLoaded: true))
        #expect(BrowserAgentGateway.shouldAutoStart(environment: [:], xctestLoaded: false))
        #expect(!BrowserAgentGateway.shouldAutoStart(), "this hosted run is under XCTest")
        #expect(BrowserAgentGateway.shared.endpoint == nil, "something started the shared gateway during a test run")
    }

    @Test func startPublishesAndStopRemovesCdpJson() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gateway = BrowserAgentGateway(upstreamPort: { 0 })

        #expect(gateway.start(publishingTo: dir))
        let file = dir.appendingPathComponent("cdp.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(json["endpoint"] as? String == gateway.endpoint)
        #expect(json["token"] as? String == gateway.token)

        gateway.stop()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
