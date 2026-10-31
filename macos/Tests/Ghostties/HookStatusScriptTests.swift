import XCTest
@testable import Ghostty

/// Runs the real `ghostties-status.sh` under `/bin/sh` against a temp HOME
/// (never the real `~/.ghostties`), and checks the pending-permission
/// sidecar: PermissionRequest writes it, Notification leaves it alone, every
/// other event deletes it.
final class HookStatusScriptTests: XCTestCase {
    private let sid = "9B2A6E10-1234-4A11-8B00-0000000000E1"
    private var home: URL!

    private var scriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/hooks/ghostties-status.sh")
    }
    private var stateDir: URL { home.appendingPathComponent(".ghostties/state") }
    private var sidecar: URL { stateDir.appendingPathComponent("\(sid).permission.json") }
    private var main: URL { stateDir.appendingPathComponent("\(sid).json") }

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookStatusScript-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    @discardableResult
    private func fire(_ payload: String, arg: String? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path] + (arg.map { [$0] } ?? [])
        process.environment = ["HOME": home.path, "GHOSTTIES_SESSION_ID": sid, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func request(_ tool: String) -> String {
        #"{"hook_event_name":"PermissionRequest","session_id":"c-1","tool_name":"\#(tool)","tool_input":{}}"#
    }
    private let notification = #"{"hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"permission_prompt","session_id":"c-1"}"#

    private func sidecarTool() throws -> String? {
        guard let data = FileManager.default.contents(atPath: sidecar.path) else { return nil }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["hook"] as? [String: Any])?["tool_name"] as? String
    }

    private func mainEvent() throws -> String? {
        guard let data = FileManager.default.contents(atPath: main.path) else { return nil }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["hook"] as? [String: Any])?["hook_event_name"] as? String
    }

    func testPermissionRequestThenNotificationLeavesTheSidecarWithTheTool() throws {
        XCTAssertEqual(try fire(request("Edit")), 0)
        XCTAssertEqual(try sidecarTool(), "Edit")
        XCTAssertEqual(try fire(notification), 0)
        XCTAssertEqual(try mainEvent(), "Notification", "the main file is still last-event-wins")
        XCTAssertEqual(try sidecarTool(), "Edit", "a Notification must not touch the sidecar")
    }

    func testEveryOtherEventDeletesTheSidecar() throws {
        let others = [
            #"{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{}}"#,
            #"{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{}}"#,
            #"{"hook_event_name":"PostToolUse","tool_name":"TodoWrite","tool_input":{}}"#,
            #"{"hook_event_name":"PostToolUseFailure","tool_name":"Edit"}"#,
            #"{"hook_event_name":"PermissionDenied","tool_name":"Edit"}"#,
            #"{"hook_event_name":"UserPromptSubmit","prompt":"go"}"#,
            #"{"hook_event_name":"Stop"}"#,
            #"{"hook_event_name":"SessionEnd"}"#,
        ]
        for other in others {
            try fire(request("Edit"))
            XCTAssertEqual(try sidecarTool(), "Edit", other)
            XCTAssertEqual(try fire(other), 0, other)
            XCTAssertNil(try sidecarTool(), "must delete the sidecar: \(other)")
        }
    }

    func testNotificationWithNoPriorRequestLeavesNoSidecar() throws {
        XCTAssertEqual(try fire(notification), 0)
        XCTAssertEqual(try mainEvent(), "Notification")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testANewRequestReplacesTheSidecar() throws {
        try fire(request("Edit"))
        try fire(notification)
        try fire(request("Bash"))
        XCTAssertEqual(try sidecarTool(), "Bash")
    }

    func testSpacedJSONIsRecognisedToo() throws {
        try fire(#"{"hook_event_name": "PermissionRequest", "tool_name": "Bash"}"#)
        XCTAssertEqual(try sidecarTool(), "Bash")
        try fire(#"{"hook_event_name": "Stop"}"#)
        XCTAssertNil(try sidecarTool())
    }

    func testNoTempFilesAreLeftBehind() throws {
        try fire(request("Edit"))
        try fire(notification)
        let names = try FileManager.default.contentsOfDirectory(atPath: stateDir.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") }, "\(names)")
    }

    func testExitsZeroWhenItCannotWrite() throws {
        // HOME is a file, so mkdir -p fails: still exit 0.
        let blocker = home.appendingPathComponent("blocker")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.environment = ["HOME": blocker.path, "GHOSTTIES_SESSION_ID": sid, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(request("Edit").utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testCodexAgentTagIsStillWritten() throws {
        try fire(#"{"hook_event_name":"Stop"}"#, arg: "codex")
        let data = try XCTUnwrap(FileManager.default.contents(atPath: main.path))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["agent"] as? String, "codex")
    }
}
