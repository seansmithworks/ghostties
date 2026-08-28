// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Coverage for `ClaudeStateStore.derive(from:)` (pure mapping) and
/// `ClaudeStateStore`'s staleness/robustness rules. Fixtures are JSON
/// strings built from the exact key sets measured in
/// `docs/plans/session-row-status/gate-evidence.md`, decoded through the
/// real `ClaudeHookWrapper`/`ClaudeHookPayload` types — never a
/// hand-written guess at the decoded shape.
@MainActor
final class ClaudeStateStoreTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Returns nil (after an `XCTFail`) rather than trapping, so one bad
    /// fixture fails the single test that used it instead of crashing the
    /// whole `xcodebuild test` run with no result bundle.
    private func wrapper(_ json: String) -> ClaudeHookWrapper? {
        guard let decoded = try? JSONDecoder().decode(ClaudeHookWrapper.self, from: Data(json.utf8)) else {
            XCTFail("fixture JSON failed to decode as ClaudeHookWrapper: \(json)")
            return nil
        }
        return decoded
    }

    private func fixture(ghosttiesSessionId: String = "9B2A6E10-1234-4A11-8B00-000000000001",
                          updatedAt: Int = 1_700_000_000,
                          hook: String) -> ClaudeHookWrapper? {
        wrapper(#"""
        {"ghosttiesSessionId":"\#(ghosttiesSessionId)","updatedAt":\#(updatedAt),"hook":\#(hook)}
        """#)
    }

    // MARK: - derive(from:) mapping

    func testDerivesBusyFromPreToolUse() {
        guard let w = fixture(hook: #"""
        {"cwd":"/Users/sean/proj","hook_event_name":"PreToolUse","effort":"medium","permission_mode":"default","prompt_id":"p1","session_id":"claude-1","tool_input":{},"tool_name":"Bash","tool_use_id":"tu-1","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .busy)
        XCTAssertEqual(state?.claudeSessionId, "claude-1")
        XCTAssertEqual(state?.cwd, "/Users/sean/proj")
    }

    func testDerivesIdleFromStop() {
        guard let w = fixture(hook: #"""
        {"background_tasks":[],"cwd":"/tmp","effort":"medium","hook_event_name":"Stop","last_assistant_message":"done","permission_mode":"default","prompt_id":"p1","session_crons":[],"session_id":"claude-2","stop_hook_active":false,"transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .idle)
    }

    func testDerivesNeedsPermissionFromPermissionRequest() {
        guard let w = fixture(hook: #"""
        {"cwd":"/tmp","effort":"medium","hook_event_name":"PermissionRequest","permission_mode":"default","permission_suggestions":[],"prompt_id":"p1","session_id":"claude-3","tool_input":{},"tool_name":"Write","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .needsPermission)
        XCTAssertEqual(state?.structuredPrompt?.toolName, "Write")
        XCTAssertNil(
            state?.structuredPrompt?.toolUseId,
            "PermissionRequest carries no tool_use_id, and the preceding PreToolUse's id is already overwritten (last-event-wins)"
        )
    }

    func testDerivesNeedsPermissionFromNotificationPermissionPrompt() {
        guard let w = fixture(hook: #"""
        {"cwd":"/tmp","hook_event_name":"Notification","message":"needs permission","notification_type":"permission_prompt","prompt_id":"p1","session_id":"claude-4","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .needsPermission)
    }

    func testDerivesNeedsInputFromNotificationIdlePrompt() {
        guard let w = fixture(hook: #"""
        {"cwd":"/tmp","hook_event_name":"Notification","message":"idle","notification_type":"idle_prompt","prompt_id":"p1","session_id":"claude-5","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .needsInput)
    }

    func testDerivesEndedFromSessionEnd() {
        guard let w = fixture(hook: #"""
        {"cwd":"/tmp","hook_event_name":"SessionEnd","prompt_id":"p1","reason":"other","session_id":"claude-6","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        let state = ClaudeStateStore.derive(from: w)
        XCTAssertEqual(state?.state, .ended)
    }

    func testUnknownNotificationTypeIsIgnored() {
        guard let w = fixture(hook: #"""
        {"cwd":"/tmp","hook_event_name":"Notification","message":"?","notification_type":"something_unmapped","prompt_id":"p1","session_id":"claude-7","transcript_path":"/tmp/t.jsonl"}
        """#) else { return }
        XCTAssertNil(ClaudeStateStore.derive(from: w))
    }

    // MARK: - Store-level staleness / robustness (real directory, temp dir only)

    private func makeTempStore() -> (store: ClaudeStateStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ClaudeStateStore(directoryURL: dir)
        return (store, dir)
    }

    private func writeFixtureFile(id: UUID, dir: URL, updatedAt: Int, hookEventName: String = "Stop") {
        let json = #"""
        {"ghosttiesSessionId":"\#(id.uuidString)","updatedAt":\#(updatedAt),"hook":{"cwd":"/tmp","hook_event_name":"\#(hookEventName)","session_id":"claude-x"}}
        """#
        try? json.write(to: dir.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
    }

    func testStateOlderThanThirtyMinutesIsIgnored() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = UUID()
        let old = Int(Date().addingTimeInterval(-40 * 60).timeIntervalSince1970)
        writeFixtureFile(id: id, dir: dir, updatedAt: old)
        store.refreshForTesting()

        XCTAssertNil(store.state(for: id), "a state file older than 30 minutes must be ignored, falling through to today's heuristics")
    }

    func testMalformedFileDoesNotBreakRefresh() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let goodId = UUID()
        writeFixtureFile(id: goodId, dir: dir, updatedAt: Int(Date().timeIntervalSince1970))

        let badId = UUID()
        try? "{ not valid json at all".write(
            to: dir.appendingPathComponent("\(badId.uuidString).json"),
            atomically: true,
            encoding: .utf8
        )

        store.refreshForTesting()

        XCTAssertNotNil(store.state(for: goodId), "a malformed sibling file must not prevent a valid file from being decoded")
        XCTAssertNil(store.state(for: badId))
    }
}
