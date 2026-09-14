// IDE-ONLY: not currently exercised in CI macos job (build-only).
// Run via Xcode Cmd+U or xcodebuild test locally.
import XCTest
@testable import Ghostty

/// Persistence round-trip tests for `AgentSession`, including the
/// `isNamePinned` migration path — this PR added that field, so a
/// pre-existing `workspace.json` (no `isNamePinned` key at all) must still
/// load without error.
final class AgentSessionCodableTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let original = AgentSession(
            id: UUID(),
            name: "Refactoring the auth module",
            templateId: UUID(),
            projectId: UUID(),
            sortOrder: 2,
            lastActiveAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOutputAt: Date(timeIntervalSince1970: 1_700_000_500),
            isNamePinned: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.lastOutputAt, original.lastOutputAt, "lastOutputAt must actually reach disk, not just decode-equal a nil default")
    }

    /// A legacy `workspace.json` predates `isNamePinned` entirely — the
    /// custom decoder must default it to `false` rather than failing to
    /// decode the whole file.
    func testLegacyJSONWithoutIsNamePinnedKeyDecodes() throws {
        let id = UUID()
        let templateId = UUID()
        let projectId = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Session 1",
            "templateId": "\(templateId.uuidString)",
            "projectId": "\(projectId.uuidString)"
        }
        """
        let data = Data(json.utf8)

        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Session 1")
        XCTAssertEqual(decoded.templateId, templateId)
        XCTAssertEqual(decoded.projectId, projectId)
        XCTAssertNil(decoded.sortOrder)
        XCTAssertNil(decoded.lastActiveAt)
        XCTAssertNil(decoded.lastOutputAt, "legacy sessions with no lastOutputAt key must decode to nil, not fail or default to now()")
        XCTAssertFalse(decoded.isNamePinned, "legacy sessions with no isNamePinned key must default to false")
        XCTAssertNil(decoded.resume, "legacy sessions with no resume key must decode to nil, not fail")
    }

    /// A `workspace.json` written before `AgentResume` existed (this PR) —
    /// same shape as `testLegacyJSONWithoutIsNamePinnedKeyDecodes` but named
    /// for the acceptance criterion this feature adds: old workspace.json
    /// decodes unchanged.
    func testOldWorkspaceJSONWithoutResumeKeyDecodes() throws {
        let id = UUID()
        let templateId = UUID()
        let projectId = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Pre-resume session",
            "templateId": "\(templateId.uuidString)",
            "projectId": "\(projectId.uuidString)",
            "sortOrder": 3,
            "isNamePinned": true,
            "isPinned": true
        }
        """
        let decoded = try JSONDecoder().decode(AgentSession.self, from: Data(json.utf8))

        XCTAssertNil(decoded.resume)
        XCTAssertEqual(decoded.sortOrder, 3)
        XCTAssertTrue(decoded.isNamePinned)
        XCTAssertTrue(decoded.isPinned)
    }

    func testResumeRoundTrips() throws {
        let original = AgentSession(
            id: UUID(),
            name: "Resumable",
            templateId: UUID(),
            projectId: UUID(),
            resume: AgentResume(
                agent: .claude,
                sessionId: "claude-session-1",
                transcriptPath: "/tmp/t.jsonl",
                cwd: "/Users/sean/proj",
                launcher: "cco"
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)

        XCTAssertEqual(decoded.resume, original.resume)
    }
}
