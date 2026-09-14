import Foundation

/// Pure decision for whether a Codex session's Ghostties hook is still
/// unapproved — see `CodexHookRegistrar`. Codex skips an untrusted hook
/// SILENTLY, so a session can sit forever with no status reports and no
/// visible reason why until the user approves the hook once in Codex's own
/// review prompt (BACKLOG D2).
///
/// Deliberately stateless: takes the launch time and report state as
/// arguments rather than owning them, so `SessionCoordinator` (the one
/// source of truth for both) can derive the answer per-session without a
/// second persisted flag.
enum CodexHookConfirmation {
    /// How long to wait after launch before flagging silence as
    /// "unconfirmed" rather than "hasn't had a chance to report yet". A
    /// SessionStart hook report, if trusted, arrives within a second or two
    /// of process spawn — 20s comfortably clears normal startup jitter
    /// without leaving the hint up long after a real approval.
    static let graceInterval: TimeInterval = 20

    /// True only while ALL of: this is a Codex session, it was launched
    /// this run (`launchedAt` non-nil), the grace period has elapsed, and it
    /// has never produced a hook report (`hasReported` false). Once a
    /// session reports even once, callers must pass `hasReported: true`
    /// forever after — this function does not remember state across calls.
    static func isHookUnconfirmed(
        isCodexSession: Bool,
        launchedAt: Date?,
        hasReported: Bool,
        now: Date = Date()
    ) -> Bool {
        guard isCodexSession, !hasReported, let launchedAt else { return false }
        return now.timeIntervalSince(launchedAt) >= graceInterval
    }
}
