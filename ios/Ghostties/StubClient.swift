import Foundation

/// In-memory backend with canned replies, so every screen works with no server.
actor StubClient: GhosttiesClient {
    private var desks: [Desk]
    private var projects: [Project]
    private var agents: [Agent]
    private var conversations: [Conversation]
    private var messages: [Message]
    private var asks: [Ask]
    private var listeners: [UUID: AsyncStream<Change>.Continuation] = [:]

    init() {
        desks = StubSeed.desks
        projects = StubSeed.projects
        agents = StubSeed.agents
        conversations = StubSeed.conversations
        messages = StubSeed.messages
        asks = StubSeed.asks
    }

    func listAgents() -> [Agent] { agents }
    func listProjects() -> [Project] { projects }
    func listDesks() -> [Desk] { desks }
    func listConversations() -> [Conversation] { conversations }
    func listMessages(conversationId: String) -> [Message] {
        messages.filter { $0.conversationId == conversationId }
    }
    func listOpenAsks() -> [Ask] { asks.filter { $0.status == .open } }

    func sendMessage(conversationId: String, body: String, clientId: String) -> Message {
        if let existing = messages.first(where: { $0.conversationId == conversationId && $0.clientId == clientId }) {
            return existing
        }
        let sent = StubSeed.message(conversationId, .user, body, clientId: clientId)
        messages.append(sent)
        touch(conversationId)
        emit(.messages(conversationId: conversationId))

        if let agentId = conversations.first(where: { $0.id == conversationId })?.agentId,
           let agent = agents.first(where: { $0.id == agentId }), !agent.status.isGone {
            replyLater(from: agent.id, in: conversationId)
        }
        return sent
    }

    func startConversation(agentId: String, body: String, clientId: String) -> Conversation {
        let conversation = Conversation(
            id: UUID().uuidString, workspaceId: StubSeed.workspace, agentId: agentId,
            title: nil, createdBy: StubSeed.me, lastMessageAt: .now, createdAt: .now
        )
        conversations.append(conversation)
        emit(.conversations)
        _ = sendMessage(conversationId: conversation.id, body: body, clientId: clientId)
        return conversation
    }

    func answerAsk(id: String, answer: AskAnswer) throws -> Ask {
        guard let index = asks.firstIndex(where: { $0.id == id }) else { throw StubError.noSuchAsk }
        asks[index].status = .answered
        asks[index].answer = answer
        asks[index].answeredBy = StubSeed.me
        asks[index].answeredAt = .now
        let ask = asks[index]

        let label = answer.optionId.flatMap { optionId in ask.options.first { $0.id == optionId }?.label }
        var reply = StubSeed.message(ask.conversationId, .user, label ?? answer.text ?? "")
        reply.kind = .answer
        reply.payload.askId = id
        messages.append(reply)
        emit(.messages(conversationId: ask.conversationId))
        emit(.asks)

        if !asks.contains(where: { $0.agentId == ask.agentId && $0.status == .open }) {
            setStatus(ask.agentId, .busy)
        }
        return ask
    }

    nonisolated func changes() -> AsyncStream<Change> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addListener(id, continuation) }
            continuation.onTermination = { _ in Task { await self.removeListener(id) } }
        }
    }

    // MARK: Private

    private func addListener(_ id: UUID, _ continuation: AsyncStream<Change>.Continuation) {
        listeners[id] = continuation
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func emit(_ change: Change) {
        for continuation in listeners.values { continuation.yield(change) }
    }

    private func replyLater(from agentId: String, in conversationId: String) {
        setStatus(agentId, .busy)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await self.deliverReply(from: agentId, in: conversationId)
        }
    }

    private func deliverReply(from agentId: String, in conversationId: String) {
        var reply = StubSeed.message(conversationId, .agent, "Got it. (Stub reply: the cloud backend is not connected yet.)")
        reply.authorAgentId = agentId
        messages.append(reply)
        touch(conversationId)
        emit(.messages(conversationId: conversationId))
        setStatus(agentId, .idle)
    }

    private func touch(_ conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].lastMessageAt = .now
    }

    private func setStatus(_ agentId: String, _ status: AgentStatus) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[index].status = status
        agents[index].lastActivityAt = .now
        emit(.agents)
    }
}

enum StubError: Error { case noSuchAsk }
