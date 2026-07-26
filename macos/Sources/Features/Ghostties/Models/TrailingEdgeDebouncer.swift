import Foundation

/// A trailing-edge debounce primitive: `signal(_:)` cancels any pending fire
/// and reschedules a new one `interval` seconds out. The passed-in `action`
/// only actually runs once no further `signal(_:)` call has arrived within
/// that window — and it always runs the closure supplied by the LATEST
/// `signal(_:)` call, evaluated at fire time, never a snapshot captured
/// earlier.
///
/// This exists specifically for `SessionCoordinator`'s Claude Code → sidebar
/// name sync. `surface.title` is not updated synchronously when the terminal
/// sets a new title — it commits ~75ms later via `SurfaceView_AppKit`'s
/// title-coalescing timer — so sampling it at signal time (the previous
/// "check elapsed, act now" throttle) reads a stale value for any title
/// change spaced more than the throttle window apart, which is the normal
/// case. Waiting for signals to go quiet for a full `interval` guarantees the
/// eventual read happens long after that 75ms commit, and bounds fires to at
/// most one per `interval` of quiet per debouncer instance — see
/// `project_perf-activity-invalidation-storm.md` for why an unthrottled write
/// on this exact signal path is a shipped production incident, not a
/// hypothetical.
///
/// Deliberately not `@MainActor` and not generic over anything — callers are
/// responsible for main-actor isolation inside their `action` closure (see
/// `SessionCoordinator`'s `MainActor.assumeIsolated` usage). Kept as a plain
/// class (not an actor) so it can be constructed and driven directly in unit
/// tests without any Task/async ceremony.
final class TrailingEdgeDebouncer {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var pendingWorkItem: DispatchWorkItem?

    init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    /// Reset the timer. `action` runs after `interval` seconds unless another
    /// `signal(_:)` (or `cancel()`) arrives first.
    func signal(_ action: @escaping () -> Void) {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    /// Cancel any pending fire without scheduling a new one.
    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
