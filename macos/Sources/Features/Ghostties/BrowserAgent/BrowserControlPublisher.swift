#if DEBUG
import Foundation

/// Writes `cdp.json` into the app's state directory so tools outside a
/// Ghostties terminal (the E2E script, for one) can find the gateway. Terminals
/// get the same two values as environment variables instead.
///
/// The directory is injected: callers pass `WorkspacePersistence.directory`,
/// tests pass a temp folder. Nothing here reads the process environment.
struct BrowserControlPublisher {
    let directory: URL

    var fileURL: URL { directory.appendingPathComponent("cdp.json") }

    func publish(endpoint: String, token: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let body: [String: Any] = ["endpoint": endpoint, "token": token, "pid": Int(pid)]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create the file private from the start: the token is a credential.
        let staging = directory.appendingPathComponent("cdp.json.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: staging)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
#endif
