import Foundation

/// Inline approve/deny for a bounded permission prompt.
///
/// KEY SENDING IS NOT IMPLEMENTED HERE. It is gated on Sean's keypress spike
/// (agents must not run it; classifier-blocked). C3 supplies the real `send`
/// closure over `Ghostty.Surface.sendKeyEvent` (NOT `sendText`, which is a
/// paste, not a keypress).
///
/// Mapping rule for that closure: Approve = "1"/Enter per the spike. Deny MUST
/// be Esc, never "2" -- "2" is "Yes, and don't ask again", which grants a
/// permanent permission.
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
    static func make(toolName: String, input: ToolInputSummary?) -> String {
        let detail = input?.command ?? input?.filePath ?? input?.firstArgument ?? input?.description ?? ""
        return "\(toolName)\u{1F}\(detail)"
    }

    static func make(_ state: ClaudeState) -> String {
        make(toolName: state.structuredPrompt?.toolName ?? "", input: state.structuredPrompt?.toolInput)
    }
}

enum ApprovalOutcome: Equatable {
    case sent
    case disabled
    case stale
    case wrongSurface
}

/// Off by default; the buttons stay hidden/inert until C3 flips this on.
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
    /// (decision, surfaceId). Supplied by C3; never a stub that types.
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
