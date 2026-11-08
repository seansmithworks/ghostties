import Foundation
import Testing
@testable import Ghostty

/// The directory is injected; these never touch a real state folder.
struct BrowserControlPublisherTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdp-publisher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func publishesEndpointTokenAndPidPrivately() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let publisher = BrowserControlPublisher(directory: dir)

        try publisher.publish(endpoint: "http://127.0.0.1:5555", token: "abc123", pid: 4242)

        let data = try Data(contentsOf: publisher.fileURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["endpoint"] as? String == "http://127.0.0.1:5555")
        #expect(json["token"] as? String == "abc123")
        #expect(json["pid"] as? Int == 4242)

        let permissions = try FileManager.default.attributesOfItem(atPath: publisher.fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600, "the token file must be owner-only, got \(String(describing: permissions))")
    }

    @Test func publishingAgainReplacesTheFile() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let publisher = BrowserControlPublisher(directory: dir)

        try publisher.publish(endpoint: "http://127.0.0.1:1", token: "old", pid: 1)
        try publisher.publish(endpoint: "http://127.0.0.1:2", token: "new", pid: 2)

        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: publisher.fileURL)) as? [String: Any])
        #expect(json["token"] as? String == "new")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers == ["cdp.json"], "staging files must not be left behind: \(leftovers)")
    }

    @Test func removeDeletesTheFile() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let publisher = BrowserControlPublisher(directory: dir)
        try publisher.publish(endpoint: "http://127.0.0.1:1", token: "t", pid: 1)

        publisher.remove()

        #expect(!FileManager.default.fileExists(atPath: publisher.fileURL.path))
    }
}
