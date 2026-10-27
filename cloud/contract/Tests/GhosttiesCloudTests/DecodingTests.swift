import XCTest
@testable import GhosttiesCloud

/// Rows shaped exactly as PostgREST returns them.
final class DecodingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testAgentDecodesSnakeCaseRow() throws {
        let json = """
        {"id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c01","workspace_id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c02",
         "role":"general_manager","name":"GM · ghostties","project_id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c03",
         "parent_agent_id":null,"desk_id":null,"status":"needs_permission","summary":"Wants to run tests",
         "branch":null,"ghost_character":"blinky","last_activity_at":null,"created_at":"2026-10-22T15:00:00Z"}
        """
        let agent = try decoder.decode(Agent.self, from: Data(json.utf8))
        XCTAssertEqual(agent.role, .generalManager)
        XCTAssertEqual(agent.status, .needsPermission)
        XCTAssertTrue(agent.status.needsYou)
        XCTAssertEqual(agent.ghostCharacter, "blinky")
    }

    func testUnknownStatusFallsBackToOffline() throws {
        let status = try decoder.decode([AgentStatus].self, from: Data(#"["sleeping"]"#.utf8))
        XCTAssertEqual(status, [.offline])
    }

    func testAskDecodesOptionsAndPayloadRoundTrips() throws {
        let json = """
        {"id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c04","workspace_id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c02",
         "agent_id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c01","conversation_id":"6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c05",
         "kind":"decision","prompt":"Merge #260?",
         "options":[{"id":"merge","label":"Merge it"},{"id":"hold","label":"Hold","detail":"Leave it open"}],
         "recommended_option_id":"merge","status":"answered","answer":{"option_id":"merge"},
         "answered_by":null,"answered_at":"2026-10-22T15:05:00Z","created_at":"2026-10-22T15:00:00Z"}
        """
        let ask = try decoder.decode(Ask.self, from: Data(json.utf8))
        XCTAssertEqual(ask.options.map(\.id), ["merge", "hold"])
        XCTAssertEqual(ask.answer?.optionId, "merge")

        let payload = try decoder.decode(JSONValue.self, from: Data(#"{"ask_id":"x","n":2,"ok":true}"#.utf8))
        XCTAssertEqual(payload["ask_id"]?.stringValue, "x")
        XCTAssertEqual(payload["ok"], .bool(true))
    }

    func testRPCArgumentsEncodeDatabaseParameterNames() throws {
        let args = RPC.AnswerAsk(askId: UUID(), answer: AskAnswer(optionId: "merge"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(args)) as? [String: Any]
        XCTAssertNotNil(object?["p_ask_id"])
        XCTAssertEqual((object?["p_answer"] as? [String: Any])?["option_id"] as? String, "merge")
    }

    func testWorkspaceChannelMatchesServerTopicFormat() {
        let id = UUID(uuidString: "6F1C0B1E-5A8E-4C1E-9A43-6A2F0D7B1C02")!
        XCTAssertEqual(CloudContract.workspaceChannel(id), "workspace:6f1c0b1e-5a8e-4c1e-9a43-6a2f0d7b1c02")
    }
}
