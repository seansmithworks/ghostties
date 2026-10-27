import Foundation
import Testing
@testable import Ghostty

struct BrowserAgentHTTPTests {
    private func parse(_ text: String) -> BrowserAgentHTTP.Parse {
        BrowserAgentHTTP.parse(Data(text.utf8))
    }

    @Test func parsesAGet() {
        let result = parse("GET /json/version?x=1 HTTP/1.1\r\nHost: 127.0.0.1:5555\r\nAccept: */*\r\n\r\n")
        #expect(result == .request(.init(
            method: "GET", path: "/json/version",
            headers: ["host": "127.0.0.1:5555", "accept": "*/*"], body: Data()
        )))
    }

    @Test func parsesAPostWithABody() {
        let body = #"{"url":"http://a/"}"#
        let result = parse("POST /ghostties/browser/open HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\nAuthorization: Bearer t\r\n\r\n\(body)")
        guard case .request(let request) = result else {
            Issue.record("expected a request, got \(result)")
            return
        }
        #expect(request.method == "POST")
        #expect(request.headers["authorization"] == "Bearer t")
        #expect(String(decoding: request.body, as: UTF8.self) == body)
    }

    @Test func waitsForTheRestOfTheHeadAndBody() {
        #expect(parse("GET /json HTTP/1.1\r\nHost: x") == .incomplete)
        #expect(parse("POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc") == .incomplete)
    }

    @Test func rejectsWhatItDoesNotSpeak() {
        #expect(parse("GARBAGE\r\n\r\n") == .malformed)
        #expect(parse("POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == .malformed)
        #expect(parse("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n") == .malformed)
        #expect(parse("GET /x HTTP/1.1\r\nno-colon-here\r\n\r\n") == .malformed)
    }

    @Test func rejectsOversizedBodiesAndHeads() {
        #expect(parse("POST /x HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n") == .tooLarge)
        let giant = "GET /x HTTP/1.1\r\n" + String(repeating: "A: b\r\n", count: 6000)
        #expect(parse(giant) == .tooLarge)
    }

    @Test func serializesWithLengthAndClose() {
        let response = BrowserAgentHTTP.Response.json(403, ["error": "no"])
        let text = String(decoding: BrowserAgentHTTP.serialize(response), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
        #expect(text.contains("Content-Length: 14\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix(#"{"error":"no"}"#))
    }
}
