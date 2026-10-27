import Foundation

/// Inline approve/deny for a bounded permission prompt.
///
/// Keys are real keypresses via `Ghostty.Surface.sendKeyEvent`, never
/// `sendText` (a bracketed paste, which Claude's menu ignores). Sean's spike
/// decided the bytes: "1" approves, Esc cancels. Enter is never used (it takes
/// whatever row is highlighted). Menu options 2 ("always allow") and 3
/// ("switch to auto mode") are never sent.
enum ApprovalDecision: Equatable {
    case approve
    case deny
}

/// What the user was looking at when they tapped. The guard compares this to
/// the live state, so a tap on a prompt that has since moved on sends nothing.
struct ApprovalTarget: Equatable {
    let sessionId: UUID
    /// `ClaudeState.updatedAt` of the prompt that was shown.
    let updatedAt: Date
    /// The surface the UI intends to type into.
    let surfaceId: UUID
    /// `ApprovalFingerprint` of the prompt shown. `updatedAt` is whole seconds
    /// and PermissionRequest has no tool_use_id, so two prompts in one second
    /// are told apart by what they ask to run.
    let fingerprint: String
}

enum ApprovalFingerprint {
    static func make(toolName: String, input: ToolInputSummary?, message: String? = nil) -> String {
        let detail = input?.command ?? input?.filePath ?? input?.firstArgument ?? input?.description ?? ""
        return [toolName, detail, input?.digest ?? "", message ?? ""].joined(separator: "\u{1F}")
    }

    static func make(_ state: ClaudeState) -> String {
        make(toolName: state.structuredPrompt?.toolName ?? "", input: state.structuredPrompt?.toolInput,
             message: state.structuredPrompt?.message)
    }
}

enum ApprovalOutcome: Equatable {
    case sent
    case disabled
    case stale
    case wrongSurface
}

/// Off by default; the buttons stay hidden/inert until the flag is turned on.
enum ApprovalFlag {
    static let defaultsKey = "ghostties.inlineApprovals"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}

@MainActor
protocol ApprovalResponder {
    func respond(_ decision: ApprovalDecision, to target: ApprovalTarget) -> ApprovalOutcome
}

/// The shipped default: does nothing.
struct NoOpApprovalResponder: ApprovalResponder {
    func respond(_ decision: ApprovalDecision, to target: ApprovalTarget) -> ApprovalOutcome { .disabled }
}

/// Guards, then delegates to an injected `send`. Re-reads state immediately
/// before sending and requires the target surface to be the session's own.
@MainActor
struct GuardedApprovalResponder: ApprovalResponder {
    let isEnabled: () -> Bool
    let currentState: (UUID) -> ClaudeState?
    /// The surface that belongs to this session (nil if it has none).
    let ownSurface: (UUID) -> UUID?
    /// (decision, surfaceId). See `ApprovalKeys` for the real delivery.
    let send: (ApprovalDecision, UUID) -> Void

    func respond(_ decision: ApprovalDecision, to target: ApprovalTarget) -> ApprovalOutcome {
        guard isEnabled() else { return .disabled }
        guard let live = currentState(target.sessionId),
              live.state == .needsPermission,
              live.updatedAt == target.updatedAt,
              ApprovalFingerprint.make(live) == target.fingerprint,
              live.structuredPrompt?.toolName != "AskUserQuestion" else { return .stale }
        guard ownSurface(target.sessionId) == target.surfaceId else { return .wrongSurface }
        send(decision, target.surfaceId)
        return .sent
    }
}

/// Anything that takes a key event; `Ghostty.Surface` in the app, a fake in tests.
@MainActor
protocol ApprovalKeySink {
    func sendKeyEvent(_ event: Ghostty.Input.KeyEvent)
}

extension Ghostty.Surface: ApprovalKeySink {}

/// The one place a decision becomes keys.
enum ApprovalKeys {
    /// Approve = "1" ("1. Yes"). Deny = Esc. Nothing else is ever produced.
    static func event(for decision: ApprovalDecision, action: Ghostty.Input.Action = .press) -> Ghostty.Input.KeyEvent {
        switch decision {
        case .approve:
            return Ghostty.Input.KeyEvent(key: .digit1, action: action, text: action == .press ? "1" : nil,
                                          unshiftedCodepoint: 0x31)
        case .deny:
            return Ghostty.Input.KeyEvent(key: .escape, action: action)
        }
    }

    @MainActor
    static func deliver(_ decision: ApprovalDecision, to sink: some ApprovalKeySink) {
        sink.sendKeyEvent(event(for: decision, action: .press))
        sink.sendKeyEvent(event(for: decision, action: .release))
    }
}
