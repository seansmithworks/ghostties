import Foundation

/// The rows `StubClient` starts with: one workspace, a chief of staff, three
/// general managers (one on an offline desk), two workers, three open asks.
enum StubSeed {
    static let workspace = "ws-personal"
    static let me = "user-sean"

    static func ago(_ minutes: Double) -> Date { Date(timeIntervalSinceNow: -minutes * 60) }

    static func message(
        _ conversationId: String, _ author: AuthorKind, _ body: String,
        clientId: String? = nil, at date: Date = .now
    ) -> Message {
        Message(
            id: UUID().uuidString, workspaceId: workspace, conversationId: conversationId,
            authorKind: author, authorUserId: author == .user ? me : nil, authorAgentId: nil,
            kind: .text, body: body, payload: MessagePayload(), clientId: clientId, createdAt: date
        )
    }

    static let desks: [Desk] = [
        Desk(id: "desk-mbp", workspaceId: workspace, name: "Sean's MacBook Pro", kind: .mac,
             appVersion: "1.4.0", lastSeenAt: .now, createdAt: ago(10_000)),
        Desk(id: "desk-studio", workspaceId: workspace, name: "Studio Mac mini", kind: .mac,
             appVersion: "1.3.2", lastSeenAt: ago(60 * 20), createdAt: ago(10_000)),
    ]

    static let projects: [Project] = [
        Project(id: "proj-ghostties", workspaceId: workspace, name: "ghostties", ghostCharacter: "inky",
                repoUrl: "https://github.com/seansmithworks/ghostties", lastActiveAt: ago(1), createdAt: ago(9_000)),
        Project(id: "proj-site", workspaceId: workspace, name: "website", ghostCharacter: "clyde",
                repoUrl: nil, lastActiveAt: ago(48), createdAt: ago(9_000)),
        Project(id: "proj-renders", workspaceId: workspace, name: "renders", ghostCharacter: "wisp",
                repoUrl: nil, lastActiveAt: ago(60 * 20), createdAt: ago(9_000)),
    ]

    static let agents: [Agent] = [
        agent("agent-cos", .chiefOfStaff, "Chief of Staff", .needsInput, ghost: "blinky",
              summary: "One decision waiting on you", minutes: 2),
        agent("agent-gm-gt", .generalManager, "GM · ghostties", .busy, ghost: "inky", project: "proj-ghostties",
              parent: "agent-cos", summary: "Running Workspace tests on the composer branch", minutes: 1),
        agent("agent-gm-site", .generalManager, "GM · website", .idle, ghost: "clyde", project: "proj-site",
              parent: "agent-cos", summary: "Changelog page shipped", minutes: 48),
        agent("agent-gm-renders", .generalManager, "GM · renders", .offline, ghost: "wisp", project: "proj-renders",
              parent: "agent-cos", desk: "desk-studio", minutes: 60 * 20),
        agent("agent-w1", .worker, "hover-reveal", .busy, ghost: "pinky", project: "proj-ghostties",
              parent: "agent-gm-gt", branch: "fix/hover-reveal-state", minutes: 0),
        agent("agent-w2", .worker, "browser-close", .needsPermission, ghost: "specter", project: "proj-ghostties",
              parent: "agent-gm-gt", branch: "fix/browser-close-confirm", minutes: 1),
    ]

    static let conversations: [Conversation] = [
        Conversation(id: "conv-cos", workspaceId: workspace, agentId: "agent-cos", title: nil,
                     createdBy: me, lastMessageAt: ago(2), createdAt: ago(60)),
        Conversation(id: "conv-gm-gt", workspaceId: workspace, agentId: "agent-gm-gt", title: "Today on ghostties",
                     createdBy: me, lastMessageAt: ago(1), createdAt: ago(30)),
    ]

    static let messages: [Message] = {
        func fromAgent(_ conversation: String, _ agent: String, _ body: String, _ minutes: Double) -> Message {
            var message = StubSeed.message(conversation, .agent, body, at: StubSeed.ago(minutes))
            message.authorAgentId = agent
            return message
        }
        var ask = fromAgent("conv-cos", "agent-cos", "Ship the hover-reveal fix to beta tonight?", 2)
        ask.kind = .ask
        ask.payload.askId = "ask-1"
        return [
            fromAgent("conv-cos", "agent-cos",
                      "Morning. The hover-reveal fix merged overnight, the cloud schema has a first draft, and the website GM is idle.", 30),
            StubSeed.message("conv-cos", .user, "Anything blocked on me?", at: StubSeed.ago(28)),
            ask,
            StubSeed.message("conv-gm-gt", .user, "Where are the composer tests at?", at: StubSeed.ago(10)),
            fromAgent("conv-gm-gt", "agent-gm-gt",
                      "Running now, 212 of 340 done. browser-close wants to run xcodebuild test and is waiting on you.", 1),
        ]
    }()

    static let asks: [Ask] = [
        ask("ask-1", agent: "agent-cos", conversation: "conv-cos", .decision,
            "Ship the hover-reveal fix to beta tonight?", minutes: 2,
            options: [
                AskOption(id: "ship", label: "Ship tonight", detail: "Goes out with the 6pm beta appcast."),
                AskOption(id: "hold", label: "Hold", detail: "Waits for tomorrow's build."),
            ], recommended: "ship"),
        ask("ask-2", agent: "agent-w2", conversation: "conv-gm-gt", .permission,
            "Run `xcodebuild test` on fix/browser-close-confirm?", minutes: 1,
            options: [AskOption(id: "allow", label: "Allow"), AskOption(id: "deny", label: "Deny")],
            recommended: "allow"),
        ask("ask-3", agent: "agent-gm-gt", conversation: "conv-gm-gt", .question,
            "Which theme should the onboarding screenshots use?", minutes: 15),
    ]

    // MARK: Builders

    private static func agent(
        _ id: String, _ role: AgentRole, _ name: String, _ status: AgentStatus, ghost: String,
        project: String? = nil, parent: String? = nil, desk: String = "desk-mbp",
        summary: String? = nil, branch: String? = nil, minutes: Double
    ) -> Agent {
        Agent(id: id, workspaceId: workspace, role: role, name: name, projectId: project,
              parentAgentId: parent, deskId: desk, status: status, summary: summary, branch: branch,
              ghostCharacter: ghost, lastActivityAt: ago(minutes), createdAt: ago(10_000))
    }

    private static func ask(
        _ id: String, agent: String, conversation: String, _ kind: AskKind, _ prompt: String,
        minutes: Double, options: [AskOption] = [], recommended: String? = nil
    ) -> Ask {
        Ask(id: id, workspaceId: workspace, agentId: agent, conversationId: conversation, kind: kind,
            prompt: prompt, options: options, recommendedOptionId: recommended, status: .open,
            answer: nil, answeredBy: nil, answeredAt: nil, createdAt: ago(minutes))
    }
}
