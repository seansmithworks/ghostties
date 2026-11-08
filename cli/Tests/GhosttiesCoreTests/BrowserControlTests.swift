import XCTest
@testable import GhosttiesCore

/// `gt browser open` talks to the app over HTTP; the app side is covered by
/// the macOS suite and the E2E script. These cover everything the CLI decides
/// on its own: whether it can run, the request it builds, and how it reports
/// the app's answer.
final class BrowserControlTests: XCTestCase {
    private let full = [
        "GHOSTTIES_CDP_ENDPOINT": "http://127.0.0.1:5555",
        "GHOSTTIES_BROWSER_TOKEN": "tok",
        "GHOSTTIES_SESSION_ID": "11111111-2222-3333-4444-555555555555",
    ]

    func testNeedsAllThreeVariables() {
        for missing in full.keys {
            var env = full
            env.removeValue(forKey: missing)
            XCTAssertThrowsError(try BrowserControl.connection(from: env), "ran without \(missing)") { error in
                XCTAssertEqual(
                    (error as? CLIError)?.errorDescription,
                    "error: browser control needs a Ghostties Dev terminal"
                )
                XCTAssertEqual((error as? CLIError)?.exitCode, 1)
            }
        }
    }

    func testEmptyValuesCountAsMissing() {
        var env = full
        env["GHOSTTIES_BROWSER_TOKEN"] = ""
        XCTAssertThrowsError(try BrowserControl.connection(from: env))
    }

    func testRequestShape() throws {
        let connection = try BrowserControl.connection(from: full)
        let request = try BrowserControl.openRequest(for: connection, url: "http://127.0.0.1:9/a?b=1")

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5555/ghostties/browser/open")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.timeoutInterval, 20)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["sessionId"], "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(json["url"], "http://127.0.0.1:9/a?b=1")
    }

    func testPrintsTheAppsAnswerOnSuccess() throws {
        let answer = #"{"endpoint":"http://127.0.0.1:5555","targetId":"T","wsUrl":"ws://127.0.0.1:6000/devtools/page/T"}"#
        var seen: URLRequest?
        let out = try BrowserControl.open(url: "about:blank", environment: full) { request in
            seen = request
            return (200, Data((answer + "\n").utf8))
        }

        XCTAssertEqual(out, answer)
        XCTAssertEqual(seen?.url?.path, "/ghostties/browser/open")
    }

    func testReportsTheAppsOwnErrorMessage() {
        XCTAssertThrowsError(
            try BrowserControl.open(url: "file:///etc/passwd", environment: full) { _ in
                (400, Data(#"{"error":"only http, https and about: URLs can be opened"}"#.utf8))
            }
        ) { error in
            XCTAssertEqual(
                (error as? CLIError)?.errorDescription,
                "error: only http, https and about: URLs can be opened"
            )
            XCTAssertEqual((error as? CLIError)?.exitCode, 1)
        }
    }

    func testAnUnreadableErrorStillSaysWhatHappened() {
        XCTAssertThrowsError(
            try BrowserControl.open(url: "about:blank", environment: full) { _ in (502, Data("<html>".utf8)) }
        ) { error in
            XCTAssertEqual((error as? CLIError)?.errorDescription, "error: the app answered HTTP 502")
        }
    }

    func testNothingIsSentWhenTheEnvironmentIsIncomplete() {
        var sent = false
        XCTAssertThrowsError(
            try BrowserControl.open(url: "about:blank", environment: [:]) { _ in sent = true; return (200, Data()) }
        )
        XCTAssertFalse(sent)
    }
}
