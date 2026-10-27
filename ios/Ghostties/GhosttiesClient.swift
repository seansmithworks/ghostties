import Foundation

/// A row changed in one of these tables. The store reloads what it covers.
enum Change: Sendable {
    case agents, asks, conversations, projects, desks
    case messages(conversationId: String)
}

/// Everything the app needs from the backend, one method per contract RPC or
/// table read. `StubClient` implements it in memory today; a Supabase client
/// (`rpc` for writes, Realtime `postgres_changes` for `changes()`) replaces it
/// without touching a view.
protocol GhosttiesClient: Sendable {
    func listAgents() async throws -> [Agent]
    func listProjects() async throws -> [Project]
    func listDesks() async throws -> [Desk]
    func listConversations() async throws -> [Conversation]
    func listMessages(conversationId: String) async throws -> [Message]
    /// Open asks only: the "needs you" list.
    func listOpenAsks() async throws -> [Ask]

    /// RPC `send_message`. Idempotent on (conversationId, clientId).
    func sendMessage(conversationId: String, body: String, clientId: String) async throws -> Message
    /// RPC `start_conversation`: opens a conversation and sends the first message.
    func startConversation(agentId: String, body: String, clientId: String) async throws -> Conversation
    /// RPC `answer_ask`.
    func answerAsk(id: String, answer: AskAnswer) async throws -> Ask

    func changes() -> AsyncStream<Change>
}
