import Foundation
import Observation

/// The app's one source of truth: rows from the client, kept current by its
/// change stream, plus the device's own not-yet-echoed messages.
@MainActor @Observable
final class AppStore {
    private(set) var agents: [Agent] = []
    private(set) var projects: [Project] = []
    private(set) var desks: [Desk] = []
    private(set) var conversations: [Conversation] = []
    /// Open asks, newest first.
    private(set) var openAsks: [Ask] = []
    private(set) var messages: [String: [Message]] = [:]
    /// Sent from this device and not yet echoed back, by agent id.
    private(set) var pending: [String: [Message]] = [:]
    var lastError: String?

    @ObservationIgnored private let client: any GhosttiesClient

    init(client: any GhosttiesClient = StubClient()) {
        self.client = client
    }

    /// Loads everything, then follows the change stream until cancelled.
    func run() async {
        await reload(.agents)
        await reload(.projects)
        await reload(.desks)
        await reload(.conversations)
        await reload(.asks)
        for await change in client.changes() {
            await reload(change)
        }
    }

    func agent(_ id: String) -> Agent? { agents.first { $0.id == id } }

    /// The agent's most recently active conversation.
    func latestConversation(for agentId: String) -> Conversation? {
        conversations
            .filter { $0.agentId == agentId }
            .max { ($0.lastMessageAt ?? $0.createdAt) < ($1.lastMessageAt ?? $1.createdAt) }
    }

    /// Server messages plus this device's pending ones, oldest first.
    func thread(agentId: String, conversationId: String?) -> [Message] {
        let server = conversationId.flatMap { messages[$0] } ?? []
        let echoed = Set(server.compactMap(\.clientId))
        let local = (pending[agentId] ?? []).filter { !echoed.contains($0.clientId ?? "") }
        return (server + local).sorted { $0.createdAt < $1.createdAt }
    }

    func loadMessages(_ conversationId: String) async {
        await reload(.messages(conversationId: conversationId))
    }

    /// Sends into `conversationId`, or starts a conversation when there is none.
    func send(_ body: String, to agentId: String, in conversationId: String?) async {
        let clientId = UUID().uuidString.lowercased()
        var local = StubSeed.message(conversationId ?? "", .user, body, clientId: clientId)
        local.id = clientId
        pending[agentId, default: []].append(local)
        do {
            if let conversationId {
                _ = try await client.sendMessage(conversationId: conversationId, body: body, clientId: clientId)
            } else {
                let conversation = try await client.startConversation(agentId: agentId, body: body, clientId: clientId)
                await reload(.conversations)
                await loadMessages(conversation.id)
            }
        } catch {
            pending[agentId]?.removeAll { $0.clientId == clientId }
            lastError = "Couldn't send: \(error.localizedDescription)"
        }
    }

    func answer(_ ask: Ask, with answer: AskAnswer) async {
        do {
            _ = try await client.answerAsk(id: ask.id, answer: answer)
        } catch {
            lastError = "Couldn't answer: \(error.localizedDescription)"
        }
    }

    private func reload(_ change: Change) async {
        do {
            switch change {
            case .agents: agents = try await client.listAgents()
            case .projects: projects = try await client.listProjects()
            case .desks: desks = try await client.listDesks()
            case .conversations: conversations = try await client.listConversations()
            case .asks:
                openAsks = try await client.listOpenAsks().sorted { $0.createdAt > $1.createdAt }
            case let .messages(conversationId):
                messages[conversationId] = try await client.listMessages(conversationId: conversationId)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
