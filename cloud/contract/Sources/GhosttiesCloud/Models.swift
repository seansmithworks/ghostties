import Foundation

// Swift mirror of cloud/contract/index.ts. Row structs decode what PostgREST
// returns for `select *`; field names map to snake_case columns through
// CodingKeys, so no decoder key strategy is needed. Change index.ts, the
// migration and this file together.

// MARK: - Enums

/// Status and role enums decode unknown raw values to a fallback instead of
/// throwing, so a newer server never breaks an older app's lists.
public enum AgentRole: String, Codable, CaseIterable, Sendable {
    case chiefOfStaff = "chief_of_staff"
    case generalManager = "general_manager"
    case worker

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AgentRole(rawValue: rawValue) ?? .worker
    }
}

/// Same vocabulary as the Mac sidebar's ClaudeStateStore.Kind, plus offline.
public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case busy
    case idle
    case needsInput = "needs_input"
    case needsPermission = "needs_permission"
    case ended
    case offline

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AgentStatus(rawValue: rawValue) ?? .offline
    }

    /// Agents in these states are waiting on a human.
    public var needsYou: Bool { self == .needsInput || self == .needsPermission }
}

public enum DeskKind: String, Codable, CaseIterable, Sendable {
    case mac
    case cloud
}

public enum AuthorKind: String, Codable, CaseIterable, Sendable {
    case user
    case agent
    case system
}

public enum MessageKind: String, Codable, CaseIterable, Sendable {
    case text
    case status
    case ask
    case answer
    case handoff

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = MessageKind(rawValue: rawValue) ?? .text
    }
}

public enum AskKind: String, Codable, CaseIterable, Sendable {
    case question
    case permission
    case decision
}

public enum AskStatus: String, Codable, CaseIterable, Sendable {
    case open
    case answered
    case expired
    case cancelled
}

/// On-disk values from GhosttiesCore.TaskLane. "done" displays as "graveyard".
public enum TaskLane: String, Codable, CaseIterable, Sendable {
    case inbox
    case backlog
    case running
    case needsYou = "needs-you"
    case review
    case done

    public var display: String { self == .done ? "graveyard" : rawValue }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case none
}

public enum PushPlatform: String, Codable, CaseIterable, Sendable {
    case ios
    case macos
    case web
}

public enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
}

// MARK: - Rows

public struct Workspace: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var ownerId: UUID
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

/// A machine that hosts agents: the Mac app, or later a cloud runner.
public struct Desk: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var name: String
    public var kind: DeskKind
    public var appVersion: String?
    public var lastSeenAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case workspaceId = "workspace_id"
        case appVersion = "app_version"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
    }

    public func isOnline(now: Date = Date()) -> Bool {
        guard let lastSeenAt else { return false }
        return now.timeIntervalSince(lastSeenAt) < CloudContract.deskOfflineAfter
    }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var name: String
    /// GhosttiesCore.GhostCharacter raw value.
    public var ghostCharacter: String?
    public var repoUrl: String?
    /// The Mac app's Project.id, so the desk can match rows to local projects.
    public var desktopProjectId: UUID?
    public var lastActiveAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case workspaceId = "workspace_id"
        case ghostCharacter = "ghost_character"
        case repoUrl = "repo_url"
        case desktopProjectId = "desktop_project_id"
        case lastActiveAt = "last_active_at"
        case createdAt = "created_at"
    }
}

public struct Agent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var role: AgentRole
    public var name: String
    /// Nil for the chief of staff; set for general managers and workers.
    public var projectId: UUID?
    /// The general manager or chief of staff this agent reports to.
    public var parentAgentId: UUID?
    /// Where it runs. Nil means not attached to a desk right now.
    public var deskId: UUID?
    public var status: AgentStatus
    /// One line on what it is doing now.
    public var summary: String?
    public var branch: String?
    public var ghostCharacter: String?
    public var lastActivityAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, name, status, summary, branch
        case workspaceId = "workspace_id"
        case projectId = "project_id"
        case parentAgentId = "parent_agent_id"
        case deskId = "desk_id"
        case ghostCharacter = "ghost_character"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
    }
}

public struct Conversation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var agentId: UUID
    public var title: String?
    public var createdBy: UUID?
    public var lastMessageAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case workspaceId = "workspace_id"
        case agentId = "agent_id"
        case createdBy = "created_by"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }
}

public struct Message: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var conversationId: UUID
    public var authorKind: AuthorKind
    public var authorUserId: UUID?
    public var authorAgentId: UUID?
    public var kind: MessageKind
    public var body: String
    /// Kind-specific extras: ask_id for "ask"/"answer", task_id for "handoff".
    public var payload: JSONValue
    /// Generated by the sender for optimistic UI; unique per conversation.
    public var clientId: UUID?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, body, payload
        case workspaceId = "workspace_id"
        case conversationId = "conversation_id"
        case authorKind = "author_kind"
        case authorUserId = "author_user_id"
        case authorAgentId = "author_agent_id"
        case clientId = "client_id"
        case createdAt = "created_at"
    }
}

public struct AskOption: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var label: String
    /// What happens if picked.
    public var detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// `option_id`, `text`, or both. Matches the TS `AskAnswer` union.
public struct AskAnswer: Codable, Hashable, Sendable {
    public var optionId: String?
    public var text: String?

    public init(optionId: String? = nil, text: String? = nil) {
        self.optionId = optionId
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case text
        case optionId = "option_id"
    }
}

/// An agent waiting on a human. Every open ask is a "needs you" item.
public struct Ask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var agentId: UUID
    public var conversationId: UUID
    public var kind: AskKind
    public var prompt: String
    public var options: [AskOption]
    public var recommendedOptionId: String?
    public var status: AskStatus
    public var answer: AskAnswer?
    public var answeredBy: UUID?
    public var answeredAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, prompt, options, status, answer
        case workspaceId = "workspace_id"
        case agentId = "agent_id"
        case conversationId = "conversation_id"
        case recommendedOptionId = "recommended_option_id"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
        case createdAt = "created_at"
    }
}

public struct CloudTask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceId: UUID
    public var projectId: UUID?
    public var agentId: UUID?
    public var title: String
    public var lane: TaskLane
    public var priority: TaskPriority
    public var branch: String?
    public var body: String
    public var source: String?
    public var sourceId: String?
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, lane, priority, branch, body, source
        case workspaceId = "workspace_id"
        case projectId = "project_id"
        case agentId = "agent_id"
        case sourceId = "source_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct PushToken: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var userId: UUID
    public var platform: PushPlatform
    public var token: String
    public var createdAt: Date
    public var lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id, platform, token
        case userId = "user_id"
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
    }
}

// MARK: - RPC arguments (supabase.rpc(name, params:))

public enum RPC {
    public struct SendMessage: Encodable, Sendable {
        public var conversationId: UUID
        public var body: String
        public var clientId: UUID

        public init(conversationId: UUID, body: String, clientId: UUID = UUID()) {
            self.conversationId = conversationId
            self.body = body
            self.clientId = clientId
        }

        public static let name = "send_message"
        enum CodingKeys: String, CodingKey {
            case conversationId = "p_conversation_id"
            case body = "p_body"
            case clientId = "p_client_id"
        }
    }

    public struct StartConversation: Encodable, Sendable {
        public var agentId: UUID
        public var body: String
        public var clientId: UUID
        public var title: String?

        public init(agentId: UUID, body: String, clientId: UUID = UUID(), title: String? = nil) {
            self.agentId = agentId
            self.body = body
            self.clientId = clientId
            self.title = title
        }

        public static let name = "start_conversation"
        enum CodingKeys: String, CodingKey {
            case agentId = "p_agent_id"
            case body = "p_body"
            case clientId = "p_client_id"
            case title = "p_title"
        }
    }

    public struct AnswerAsk: Encodable, Sendable {
        public var askId: UUID
        public var answer: AskAnswer

        public init(askId: UUID, answer: AskAnswer) {
            self.askId = askId
            self.answer = answer
        }

        public static let name = "answer_ask"
        enum CodingKeys: String, CodingKey {
            case askId = "p_ask_id"
            case answer = "p_answer"
        }
    }

    public struct MarkConversationRead: Encodable, Sendable {
        public var conversationId: UUID

        public init(conversationId: UUID) {
            self.conversationId = conversationId
        }

        public static let name = "mark_conversation_read"
        enum CodingKeys: String, CodingKey {
            case conversationId = "p_conversation_id"
        }
    }

    /// APNs device token as hex, or a web push endpoint.
    public struct RegisterPushToken: Encodable, Sendable {
        public var platform: PushPlatform
        public var token: String

        public init(platform: PushPlatform, token: String) {
            self.platform = platform
            self.token = token
        }

        public static let name = "register_push_token"
        enum CodingKeys: String, CodingKey {
            case platform = "p_platform"
            case token = "p_token"
        }
    }

    public struct DeskHeartbeat: Encodable, Sendable {
        public var deskId: UUID
        public var appVersion: String?

        public init(deskId: UUID, appVersion: String? = nil) {
            self.deskId = deskId
            self.appVersion = appVersion
        }

        public static let name = "desk_heartbeat"
        enum CodingKeys: String, CodingKey {
            case deskId = "p_desk_id"
            case appVersion = "p_app_version"
        }
    }
}

// MARK: - Realtime and timing

public enum CloudContract {
    /// Tables that publish postgres_changes; filter by `workspace_id=eq.<id>`.
    public static let realtimeTables = ["messages", "asks", "agents", "conversations", "tasks", "desks"]

    /// Private Broadcast/Presence channel for typing, streamed replies, desk presence.
    public static func workspaceChannel(_ workspaceId: UUID) -> String {
        "workspace:\(workspaceId.uuidString.lowercased())"
    }

    public static let deskHeartbeatInterval: TimeInterval = 30
    public static let deskOfflineAfter: TimeInterval = 90
}
