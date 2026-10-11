import AppKit
import Foundation

/// Rail hover-reveal's timing (Sean, 2026-10-11): on the rail, a pointer
/// that rests over the sidebar for `dwell` reveals the full sidebar over the
/// terminal; leaving it starts `exitGrace`, after which it morphs back.
///
/// Only the decisions live here — when to reveal and when to collapse. The
/// container (`WorkspaceViewContainer`) feeds it pointer and click events
/// while the sidebar is on the rail and plays `onReveal`/`onCollapse` on the
/// same morph the Cmd+S toggle runs. The clock is injected, so tests drive
/// it without sleeping.
@MainActor
final class RailHoverReveal {
    struct Settings: Equatable {
        var isEnabled: Bool
        var dwell: TimeInterval
        var exitGrace: TimeInterval

        /// The live dial values (`SidebarDialTuning`, "Hover reveal").
        static func current(defaults: UserDefaults = SidebarDialTuning.store) -> Settings {
            Settings(
                isEnabled: SidebarDialTuning.hoverRevealEnabled(defaults: defaults),
                dwell: SidebarDialTuning.hoverRevealDwell(defaults: defaults),
                exitGrace: SidebarDialTuning.hoverRevealExitGrace(defaults: defaults)
            )
        }
    }

    enum Phase: Equatable {
        /// On the rail, nothing pending.
        case idle
        /// The pointer is over the rail; the dwell timer is running.
        case dwelling
        /// The full sidebar is out over the terminal and the pointer is on it.
        case revealed
        /// Revealed, the pointer has left; the exit-grace timer is running.
        case leaving
        /// Collapsed by a click while the pointer is still over the rail. No
        /// new dwell starts until the pointer leaves, so a click never
        /// brings the sidebar straight back out.
        case suppressed
    }

    /// Runs `action` after `delay`; the returned closure cancels it.
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> () -> Void

    private(set) var phase: Phase = .idle
    /// Play the rail -> sidebar morph, over the terminal.
    var onReveal: () -> Void = {}
    /// Play the sidebar -> rail morph.
    var onCollapse: () -> Void = {}
    /// Whether a completed dwell may reveal now. False while the sidebar is
    /// still mid-transition (e.g. the Cmd+S collapse onto the rail): the
    /// dwell then re-arms and tries again, rather than revealing from a
    /// half-finished width.
    var canReveal: () -> Bool = { true }

    private let settings: () -> Settings
    private let schedule: Schedule
    private var cancelTimer: (() -> Void)?

    init(settings: @escaping () -> Settings = { .current() }, schedule: @escaping Schedule = RailHoverReveal.mainQueue(after:_:)) {
        self.settings = settings
        self.schedule = schedule
    }

    /// True from the moment the reveal starts until the collapse starts.
    var isRevealed: Bool { phase == .revealed || phase == .leaving }

    /// The pointer entered the sidebar's area (the rail at rest, the whole
    /// revealed panel once out).
    func pointerEntered() {
        switch phase {
        case .idle:
            let current = settings()
            guard current.isEnabled else { return }
            phase = .dwelling
            armDwell(current.dwell)
        case .leaving:
            // Back inside during the grace: stay out.
            cancel()
            phase = .revealed
        case .dwelling, .revealed, .suppressed:
            break
        }
    }

    /// The pointer left the sidebar's area.
    func pointerExited() {
        switch phase {
        case .dwelling:
            // Passed across the rail without resting: nothing happens.
            cancel()
            phase = .idle
        case .revealed:
            let grace = settings().exitGrace
            guard grace > 0 else {
                phase = .idle
                onCollapse()
                return
            }
            phase = .leaving
            arm(after: grace) { [weak self] in
                guard let self, self.phase == .leaving else { return }
                self.phase = .idle
                self.onCollapse()
            }
        case .suppressed:
            phase = .idle
        case .idle, .leaving:
            break
        }
    }

    /// An item in the sidebar was activated, the user clicked outside it, or
    /// the window lost key: collapse now if revealed. A click on the rail
    /// itself also cancels a pending dwell. `pointerInside` says whether the
    /// pointer is still over the sidebar's area.
    func dismiss(pointerInside: Bool) {
        let wasRevealed = isRevealed
        guard wasRevealed || phase == .dwelling else { return }
        cancel()
        phase = pointerInside ? .suppressed : .idle
        if wasRevealed { onCollapse() }
    }

    /// Cmd+S while revealed: the reveal becomes the pinned sidebar. Nothing
    /// here collapses it. Returns whether a reveal was taken over.
    @discardableResult
    func pin() -> Bool {
        let wasRevealed = isRevealed
        reset()
        return wasRevealed
    }

    /// The sidebar left the rail by another route: drop everything, no
    /// callbacks.
    func reset() {
        cancel()
        phase = .idle
    }

    /// Reveal immediately, as a completed dwell would. The capture fixture's
    /// way in, since an agent can't hover.
    func revealNow() {
        cancel()
        guard !isRevealed else { return }
        phase = .revealed
        onReveal()
    }

    private func armDwell(_ dwell: TimeInterval) {
        arm(after: dwell) { [weak self] in
            guard let self, self.phase == .dwelling else { return }
            guard self.canReveal() else {
                self.armDwell(dwell)
                return
            }
            self.phase = .revealed
            self.onReveal()
        }
    }

    private func arm(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        cancelTimer = schedule(delay, action)
    }

    private func cancel() {
        cancelTimer?()
        cancelTimer = nil
    }

    nonisolated static func mainQueue(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }
}

/// The rail's hover area for `RailHoverReveal`: laid out over the sidebar
/// (and, once revealed, the whole revealed panel). Its tracking area follows
/// its frame (`.inVisibleRect`), so the area grows with the reveal and the
/// pointer stays inside it. It never takes clicks.
final class RailHoverZoneView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
