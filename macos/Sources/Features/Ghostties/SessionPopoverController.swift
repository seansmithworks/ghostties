import AppKit
import Combine
import SwiftUI

/// Published content for the one card a window shows.
@MainActor
final class SessionPopoverModel: ObservableObject {
    @Published var content: SessionPopoverContent?
}

/// Hosting view whose hit-testing covers only the card, not the transparent
/// shadow inset around it — so the inset never swallows clicks meant for the
/// terminal underneath.
final class SessionPopoverHostingView: TransparentHostingView<AnyView> {
    var cardInset: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.insetBy(dx: cardInset, dy: cardInset).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Owns the session popover for one window: hover timing, placement,
/// dismissal, and the live content. One instance per `SessionCoordinator`
/// (`coordinator.sessionPopover`); rows and rail ghosts feed it hover events
/// through `SessionPopoverAnchor`.
///
/// The card is a sibling view added to the window's `WorkspaceViewContainer`
/// (topmost), not a child of the sidebar's hosting view, because it has to
/// overlap the terminal to the sidebar's right.
///
/// Approval content is never cached: every refresh re-derives the whole
/// `SessionPopoverContent` from the current state, so a stale approval
/// cannot outlive its `.needsPermission` state.
@MainActor
final class SessionPopoverController {
    private weak var coordinator: SessionCoordinator?
    private let workspace: WorkspaceStore
    private let claudeState: ClaudeStateStore
    private let model = SessionPopoverModel()

    private var anchors: [UUID: WeakAnchor] = [:]
    private var hosting: SessionPopoverHostingView?
    private var currentSessionId: UUID?
    private weak var currentAnchor: NSView?

    private var hoveredSessionId: UUID?
    /// The anchor view the pointer is over. nil while a hovered row's anchor
    /// has been torn down and not yet replaced — see `unregister`/`register`.
    private weak var hoveredAnchor: NSView?
    private var rowHovered: Bool { hoveredSessionId != nil && hoveredAnchor != nil }
    private var cardHovered = false
    /// A capture forced the card open: hover exit must not dismiss it.
    private var isPinnedOpen = false

    private var showWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?
    /// The single owner of everything that outlives one `present` call: the
    /// 1s timer, the Esc monitor, the store subscription and the window-close
    /// observer. Released by `stopLiveUpdates()`, and by this controller's
    /// own deallocation (its deinit tears the handles down), so no path can
    /// leave a timer or event monitor behind.
    private var liveUpdates: LiveUpdates?
    private var generation = 0

    private struct WeakAnchor { weak var view: NSView? }

    init(
        coordinator: SessionCoordinator?,
        workspace: WorkspaceStore = .shared,
        claudeState: ClaudeStateStore = .shared
    ) {
        self.coordinator = coordinator
        self.workspace = workspace
        self.claudeState = claudeState
    }

    var isVisible: Bool { hosting?.superview != nil && currentSessionId != nil }

    // MARK: - Anchors and hover input

    func register(anchor: NSView, for sessionId: UUID) {
        anchors[sessionId] = WeakAnchor(view: anchor)
        // A row rebuilt under the pointer (e.g. it changed section) tears its
        // anchor down and registers a new one for the same session: the new
        // anchor adopts the open card and the hover.
        if hoveredSessionId == sessionId, hoveredAnchor == nil { hoveredAnchor = anchor }
        if currentSessionId == sessionId {
            currentAnchor = anchor
            DispatchQueue.main.async { [weak self] in self?.replaceCurrentCard() }
        }
    }

    func unregister(anchor: NSView, for sessionId: UUID) {
        if anchors[sessionId]?.view === anchor { anchors[sessionId] = nil }
        // Only the anchor the pointer is actually over can end the hover; a
        // stale or unrelated anchor going away must not dismiss the card.
        guard hoveredAnchor === anchor else { return }
        hoveredAnchor = nil
        scheduleDismiss()
    }

    private func replaceCurrentCard() {
        guard isVisible, let container = coordinator?.containerView else { return }
        placeCard(in: container, animated: false, slideIn: false)
    }

    func rowHoverChanged(sessionId: UUID, anchor: NSView, hovering: Bool) {
        if hovering {
            hoveredSessionId = sessionId
            hoveredAnchor = anchor
            dismissWork?.cancel()
            if isVisible {
                // Moving between rows retargets immediately; the delay is
                // only for the first appearance.
                if currentSessionId != sessionId { present(sessionId: sessionId, anchor: anchor) }
            } else {
                showWork?.cancel()
                let work = DispatchWorkItem { [weak self, weak anchor] in
                    guard let self, let anchor, self.rowHovered else { return }
                    self.present(sessionId: sessionId, anchor: anchor)
                }
                showWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + SessionPopoverLayout.hoverDelay, execute: work)
            }
        } else if hoveredSessionId == sessionId, hoveredAnchor === anchor {
            hoveredSessionId = nil
            hoveredAnchor = nil
            showWork?.cancel()
            scheduleDismiss()
        }
    }

    private func cardHoverChanged(_ hovering: Bool) {
        cardHovered = hovering
        if hovering { dismissWork?.cancel() } else { scheduleDismiss() }
    }

    private func scheduleDismiss() {
        guard isVisible, !isPinnedOpen else { return }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cardHovered else { return }
            // An adopted anchor never got a mouseEntered: confirm the pointer
            // is still over it before letting it hold the card open.
            if self.rowHovered, let anchor = self.hoveredAnchor, !Self.pointerIsInside(anchor) {
                self.hoveredSessionId = nil
                self.hoveredAnchor = nil
            }
            guard !self.rowHovered else { return }
            self.dismiss()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SessionPopoverLayout.dismissGrace, execute: work)
    }

    private static func pointerIsInside(_ view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return view.bounds.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    // MARK: - Actions

    /// Same code path a row click takes.
    private func open() {
        guard let id = currentSessionId else { return }
        coordinator?.focusSession(id: id)
        dismiss()
    }

    func dismiss() {
        showWork?.cancel()
        dismissWork?.cancel()
        isPinnedOpen = false
        hoveredSessionId = nil
        hoveredAnchor = nil
        cardHovered = false
        stopLiveUpdates()
        currentSessionId = nil
        currentAnchor = nil
        model.content = nil
        guard let hosting, hosting.superview != nil else { return }

        generation += 1
        let myGeneration = generation
        hosting.isHitTestDisabled = true
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduce ? SessionPopoverLayout.reducedMotionFadeDuration : SessionPopoverLayout.fadeDuration
            hosting.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak hosting] in
            MainActor.assumeIsolated {
                guard let self, self.generation == myGeneration else { return }
                hosting?.removeFromSuperview()
            }
        })
    }

    // MARK: - Presentation

    private func present(sessionId: UUID, anchor: NSView) {
        guard let container = coordinator?.containerView, anchor.window != nil else { return }
        guard let content = makeContent(for: sessionId) else { return }

        let wasVisible = isVisible
        currentSessionId = sessionId
        currentAnchor = anchor
        model.content = content

        let host = ensureHosting()
        generation += 1
        host.isHitTestDisabled = false
        if host.superview == nil {
            host.alphaValue = 0
            container.addSubview(host, positioned: .above, relativeTo: nil)
        }
        placeCard(in: container, animated: false, slideIn: !wasVisible)
        startLiveUpdates(window: anchor.window)
    }

    private func ensureHosting() -> SessionPopoverHostingView {
        if let hosting { return hosting }
        let root = SessionPopoverCard(
            model: model,
            onOpen: { [weak self] in self?.open() },
            onClose: { [weak self] in self?.dismiss() },
            onHover: { [weak self] in self?.cardHoverChanged($0) }
        )
        let host = SessionPopoverHostingView(rootView: AnyView(root))
        host.cardInset = SessionPopoverLayout.shadowInset
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = true
        hosting = host
        return host
    }

    /// Top-aligned with the hovered row, 8pt right of the sidebar/rail edge,
    /// clamped inside the window.
    private func placeCard(in container: NSView, animated: Bool, slideIn: Bool) {
        guard let host = hosting, let anchor = currentAnchor else { return }
        let inset = SessionPopoverLayout.shadowInset

        host.frame.size = NSSize(width: SessionPopoverLayout.width + inset * 2, height: 2000)
        host.layoutSubtreeIfNeeded()
        let fitted = host.fittingSize
        let height = max(fitted.height, inset * 2 + 60)
        let size = NSSize(width: SessionPopoverLayout.width + inset * 2, height: height)

        let rowRect = container.convert(anchor.bounds, from: anchor)
        let edge = sidebarEdge(of: anchor, in: container) ?? rowRect.maxX
        let margin = SessionPopoverLayout.windowMargin

        var cardX = edge + SessionPopoverLayout.edgeGap
        let cardHeight = size.height - inset * 2
        var cardTop = rowRect.maxY   // non-flipped: top edge of the row
        let bounds = container.bounds
        cardX = min(cardX, bounds.maxX - margin - SessionPopoverLayout.width)
        cardX = max(cardX, bounds.minX + margin)
        cardTop = min(cardTop, bounds.maxY - margin)
        cardTop = max(cardTop, bounds.minY + margin + cardHeight)

        let target = NSRect(
            x: cardX - inset,
            y: cardTop - cardHeight - inset,
            width: size.width,
            height: size.height
        )
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if slideIn || host.alphaValue < 1 {
            if !reduce && slideIn {
                host.frame = target.offsetBy(dx: -SessionPopoverLayout.slideDistance, dy: 0)
            } else {
                host.frame = target
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduce ? SessionPopoverLayout.reducedMotionFadeDuration : SessionPopoverLayout.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
                if !reduce { host.animator().frame = target }
            }
        } else {
            host.frame = target
        }
    }

    /// Right edge of the sidebar/rail: the frame of the container's direct
    /// child that hosts `anchor`.
    private func sidebarEdge(of anchor: NSView, in container: NSView) -> CGFloat? {
        var view: NSView? = anchor
        while let current = view, current.superview !== container { view = current.superview }
        return view?.frame.maxX
    }

    // MARK: - Content

    private func makeContent(for id: UUID) -> SessionPopoverContent? {
        let store = workspace
        guard let session = store.sessions.first(where: { $0.id == id }) else { return nil }
        var title = session.name
        var cwd = claudeState.state(for: id)?.cwd
            ?? store.projects.first { $0.id == session.projectId }?.rootPath
        var approval = claudeState.state(for: id)
        var summary = claudeState.summary(for: id)
        var indicator = store.globalIndicatorStates[id] ?? .inactive
        #if DEBUG
        if let override = CaptureFixture.popoverOverride(for: id) {
            title = override.title
            cwd = override.cwd
            approval = override.approval
            summary = override.summary
            if let forced = override.indicator { indicator = forced }
        }
        #endif
        return SessionPopoverContent.make(
            sessionId: id,
            title: title,
            cwd: cwd,
            agent: session.resume?.agent.rawValue ?? "claude",
            indicator: indicator,
            approval: approval,
            summary: summary,
            fallbackDate: session.displayTimestamp
        )
    }

    /// Re-derive the content from current state. A session that no longer
    /// exists dismisses the card.
    private func refresh() {
        guard let id = currentSessionId else { return }
        guard let content = makeContent(for: id) else { dismiss(); return }
        guard content != model.content else { return }
        model.content = content
        // SwiftUI applies the new content on its next layout pass.
        DispatchQueue.main.async { [weak self] in self?.replaceCurrentCard() }
    }

    /// Whether Esc should be swallowed by the card: only while it is visible
    /// AND the pointer is over it. Anything else goes to the terminal
    /// untouched (Claude Code uses Esc heavily).
    nonisolated static func shouldConsumeEscape(keyCode: UInt16, isVisible: Bool, cardHovered: Bool) -> Bool {
        keyCode == 53 && isVisible && cardHovered
    }

    #if DEBUG
    /// Test seams: drive the content path with no window or GUI.
    func openForTesting(sessionId: UUID) {
        guard let content = makeContent(for: sessionId) else { return }
        currentSessionId = sessionId
        model.content = content
    }
    func refreshForTesting() { refresh() }
    var contentForTesting: SessionPopoverContent? { model.content }
    var currentSessionIdForTesting: UUID? { currentSessionId }
    var isRowHoveredForTesting: Bool { rowHovered }
    var liveUpdatesActiveForTesting: Bool { liveUpdates != nil }
    func startLiveUpdatesForTesting(window: NSWindow?) { startLiveUpdates(window: window) }
    #endif

    private func startLiveUpdates(window: NSWindow?) {
        guard liveUpdates == nil else { return }
        // Poll once a second: indicator state and approval freshness are not
        // change-notified, and the card is only ever open briefly.
        liveUpdates = LiveUpdates(
            window: window,
            didRefresh: claudeState.didRefresh,
            refresh: { [weak self] in MainActor.assumeIsolated { self?.refresh() } },
            // The window is closing under an open card: remove it at once
            // rather than fading it in a window that is going away.
            windowWillClose: { [weak self] in MainActor.assumeIsolated { self?.teardown() } },
            // Esc dismisses only while the pointer is over the card.
            escape: { [weak self] keyCode in
                MainActor.assumeIsolated {
                    guard let self else { return false }
                    let consume = Self.shouldConsumeEscape(
                        keyCode: keyCode, isVisible: self.isVisible, cardHovered: self.cardHovered
                    )
                    if consume { self.dismiss() }
                    return consume
                }
            }
        )
    }

    private func stopLiveUpdates() {
        liveUpdates = nil
    }

    /// Immediate, unanimated removal — the window is going away.
    private func teardown() {
        dismiss()
        generation += 1
        hosting?.removeFromSuperview()
    }

    // MARK: - Capture fixture

    #if DEBUG
    /// `GHOSTTIES_CAPTURE_POPOVER`: open the card for the fixture session
    /// without hovering, and keep it open. Retries briefly because the row's
    /// anchor registers as the sidebar lays out. No-op outside fixture mode.
    func openForCaptureFixtureIfNeeded() {
        guard CaptureFixture.isActive, let id = CaptureFixture.popoverTargetSessionId else { return }
        func attempt(_ remaining: Int) {
            if let anchor = anchors[id]?.view, anchor.window != nil, anchor.bounds.height > 0 {
                isPinnedOpen = true
                present(sessionId: id, anchor: anchor)
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { attempt(remaining - 1) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { attempt(15) }
    }
    #endif
}

// MARK: - Live updates

/// Owns every resource an open card holds beyond its views: the refresh timer,
/// the local Esc monitor, the store subscription and the window-close
/// observer. Creating one starts them; releasing it (explicitly, or when the
/// owning controller deallocates) stops them, so lifetime is a single
/// reference, not a set of paired start/stop calls.
private final class LiveUpdates {
    private var timer: Timer?
    private var keyMonitor: Any?
    private var subscription: AnyCancellable?
    private var closeObserver: NSObjectProtocol?

    init(
        window: NSWindow?,
        didRefresh: PassthroughSubject<Void, Never>,
        refresh: @escaping () -> Void,
        windowWillClose: @escaping () -> Void,
        escape: @escaping (UInt16) -> Bool
    ) {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in refresh() }
        subscription = didRefresh.receive(on: DispatchQueue.main).sink { refresh() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            escape(event.keyCode) ? nil : event
        }
        if let window {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in windowWillClose() }
        }
    }

    deinit {
        timer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
}

// MARK: - Hover anchor

/// Invisible view placed behind a session row / rail ghost. It reports the
/// row's hover to the popover controller and lends it the row's on-screen
/// frame. An AppKit tracking area (not `.onHover`) so the frame comes from the
/// real view, in window coordinates, with no SwiftUI coordinate guessing.
struct SessionPopoverAnchor: NSViewRepresentable {
    let sessionId: UUID
    let controller: SessionPopoverController

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.sessionId = sessionId
        view.controller = controller
        controller.register(anchor: view, for: sessionId)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        if view.sessionId != sessionId {
            controller.unregister(anchor: view, for: view.sessionId)
            view.sessionId = sessionId
            controller.register(anchor: view, for: sessionId)
        }
        view.controller = controller
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        view.controller?.unregister(anchor: view, for: view.sessionId)
    }

    final class AnchorView: NSView {
        var sessionId = UUID()
        weak var controller: SessionPopoverController?
        private var area: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(new)
            area = new
        }

        override func mouseEntered(with event: NSEvent) {
            controller?.rowHoverChanged(sessionId: sessionId, anchor: self, hovering: true)
        }

        override func mouseExited(with event: NSEvent) {
            controller?.rowHoverChanged(sessionId: sessionId, anchor: self, hovering: false)
        }
    }
}

extension View {
    /// Shows the session popover while the pointer rests over this view.
    func sessionPopoverAnchor(sessionId: UUID, controller: SessionPopoverController) -> some View {
        background(SessionPopoverAnchor(sessionId: sessionId, controller: controller))
    }
}
