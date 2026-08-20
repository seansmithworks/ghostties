import AppKit
import Combine
import SwiftUI

/// Observable width holder for the sidebar's SwiftUI `.frame(width:)` pin.
/// Owned by `WorkspaceViewContainer` and updated by the drag handler on every
/// `mouseDragged` tick. Isolating the width behind this tiny model lets only
/// `SidebarWidthFrame` (below) re-render on drag — not the entire sidebar
/// subtree, which previously got rebuilt (new WorkspaceSidebarView/
/// TaskSidebarView, 4 `.environmentObject` calls, `AnyView` reassignment) via
/// `applySidebarView()` on every tick at 60-120Hz. That subtree has a
/// documented render-cost history (two shipped 100%-CPU beachball incidents).
///
/// INVARIANT: `width` must always be an explicit finite value — never
/// `.infinity` or 0. Only ever initialized/written from `currentSidebarWidth`,
/// which already clamps to the design tokens (see sidebar-layout-hang-v0).
@MainActor
final class SidebarWidthModel: ObservableObject {
    @Published var width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }
}

/// Observable model backing the composer overlay's titlebar hit-test band.
/// PR #132 removed `horizontalOffset` — the composer
/// now centers on the whole window instead of the terminal card, so there is
/// no sidebar-width offset left to track.
@MainActor
final class ComposerCenteringModel: ObservableObject {
    /// Height of the dismiss layer's titlebar-band exclusion (F7's
    /// fullscreen follow-up, Phase 3 review round 2). Defaults to
    /// `WorkspaceLayout.titlebarSpacerHeight`, the traffic-light band the
    /// dismiss layer excludes to keep window dragging working — but there's
    /// no titlebar to protect in fullscreen, so that band was left
    /// unclaimed for no reason. `WorkspaceViewContainer.windowDidEnterOrExitFullScreen()`
    /// writes 0 on entering fullscreen and restores the token on exit.
    @Published var titlebarBandHeight: CGFloat = WorkspaceLayout.titlebarSpacerHeight
}

/// Wraps sidebar content in a `.frame(width:)` pin driven by `SidebarWidthModel`
/// instead of a captured constant. Only this thin wrapper observes width
/// changes, so the wrapped `content`'s identity — and the identity of
/// everything inside it — is preserved across drag ticks.
private struct SidebarWidthFrame<Content: View>: View {
    @ObservedObject var model: SidebarWidthModel
    let content: Content

    var body: some View {
        content
            .frame(width: model.width)
            .frame(maxHeight: .infinity)
    }
}

/// An NSView that contains the workspace sidebar alongside the existing terminal view.
/// This replaces TerminalViewContainer as the window's contentView.
///
/// The sidebar is a SwiftUI view hierarchy (disclosure list) embedded in an
/// NSHostingView. The terminal side is the standard TerminalViewContainer, untouched.
/// Both are arranged via Auto Layout with an animated sidebar width constraint.
///
/// This container also creates and owns the `SessionCoordinator`, which bridges
/// the sidebar's SwiftUI world to the terminal controller's AppKit world.
///
/// ## Sidebar State Machine
///
/// The sidebar operates in three modes (see `SidebarMode`):
/// - **pinned**: Sidebar pushes terminal right (floating card with shadow/insets).
/// - **closed**: Sidebar hidden, terminal fills window flush, traffic lights hidden.
/// - **overlay**: Sidebar floats on top of full-width terminal (hover-to-reveal).
class WorkspaceViewContainer: NSView {
    private let backgroundEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let sidebarHostingView: NSView
    /// Exposed for `BaseTerminalController.terminalViewContainer` to reach through.
    private(set) var terminalContainer: TerminalViewContainer
    private let coordinator: SessionCoordinator
    private let ghostty: Ghostty.App

    /// v0 task-first sidebar store. Loads `.ghostties/tasks/*.md` fixtures once.
    /// Instantiated lazily on first access (always on the main thread via AppKit
    /// view lifecycle) so the store survives view-mode toggling.
    private lazy var taskStore: TaskStore = TaskStore()

    /// Session-hybrid: tracks anonymous terminal sessions that haven't been
    /// promoted to tasks. Lives alongside `taskStore`; both feed the ACTIVE
    /// zone. Lazy so it only materializes for task-first mode.
    private lazy var sessionDraftStore: SessionDraftStore = SessionDraftStore()

    /// UserDefaults key for the v0 sidebar view mode feature toggle. Mirrors the
    /// `@AppStorage` key used in SwiftUI contexts so both layers observe the
    /// same value. Values: `"projectFirst"` (default) or `"taskFirst"`.
    private static let sidebarViewModeDefaultsKey = "ghostties.sidebarViewMode"

    /// Read the current sidebar view mode from UserDefaults. Defaults to
    /// project-first if the key is missing or holds an unknown value.
    private var currentSidebarViewMode: String {
        let raw = UserDefaults.standard.string(forKey: Self.sidebarViewModeDefaultsKey) ?? "projectFirst"
        return raw == "taskFirst" ? "taskFirst" : "projectFirst"
    }

    /// Per-mode sidebar widths, drag-resizable. Initialized once from
    /// UserDefaults (`ghostties.sidebarWidth.{projectFirst,taskFirst}`),
    /// falling back to the design tokens when no persisted value exists.
    /// `currentSidebarWidth` is the single read/write accessor for these —
    /// the drag handler writes through it during a drag so the AppKit width
    /// constraint and the SwiftUI `.frame(width:)` pin never diverge.
    private var projectFirstSidebarWidth: CGFloat =
        WorkspaceViewContainer.persistedSidebarWidth(forMode: "projectFirst")
    private var taskFirstSidebarWidth: CGFloat =
        WorkspaceViewContainer.persistedSidebarWidth(forMode: "taskFirst")

    /// UserDefaults key for a given view mode's persisted sidebar width.
    private static func sidebarWidthDefaultsKey(forMode mode: String) -> String {
        mode == "taskFirst" ? "ghostties.sidebarWidth.taskFirst" : "ghostties.sidebarWidth.projectFirst"
    }

    /// Read a view mode's persisted sidebar width, falling back to the design
    /// token when unset. Persisted values are re-clamped to the current
    /// min/max tokens in case those tokens changed since the value was saved.
    private static func persistedSidebarWidth(forMode mode: String) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: sidebarWidthDefaultsKey(forMode: mode))
        guard stored > 0 else {
            return mode == "taskFirst" ? WorkspaceLayout.taskSidebarWidth : WorkspaceLayout.sidebarWidth
        }
        return min(max(CGFloat(stored), WorkspaceLayout.sidebarMinWidth), WorkspaceLayout.sidebarMaxWidth)
    }

    /// Resolved sidebar width for the current view mode.
    private var currentSidebarWidth: CGFloat {
        get {
            currentSidebarViewMode == "taskFirst" ? taskFirstSidebarWidth : projectFirstSidebarWidth
        }
        set {
            if currentSidebarViewMode == "taskFirst" {
                taskFirstSidebarWidth = newValue
            } else {
                projectFirstSidebarWidth = newValue
            }
        }
    }

    /// Observable width model backing the SwiftUI sidebar's `.frame(width:)`
    /// pin (via `SidebarWidthFrame`, below). Every site that changes the
    /// sidebar's width also writes this model so the AppKit constraint, the
    /// stored per-mode width, and the SwiftUI frame stay in lockstep. Lazily
    /// created so it reads `currentSidebarWidth` after `self` is fully
    /// initialized; first touched in `applySidebarView()` during `init`.
    private lazy var widthModel = SidebarWidthModel(width: currentSidebarWidth)

    /// Shadow host wraps the terminal container so the drop shadow renders
    /// outside `masksToBounds` clipping. The shadow host carries the shadow;
    /// the inner terminal container clips its corners.
    private let terminalShadowHost: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Shadow host for the browser panel — identical layer config to terminalShadowHost.
    private let browserShadowHost: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// The browser panel content (navigation bar + content area placeholder).
    private let browserPanelView = BrowserPanelView()

    /// Diagnostic build/launch info badge — bottom-left corner of the window,
    /// click-to-copy. `@AppStorage`-gated; sizes itself to its content so it
    /// never intercepts clicks outside its own bounds. See `BuildInfoBadgeView.swift`.
    private let buildInfoBadgeHostingView: NSHostingView<BuildInfoBadgeView> = {
        let view = NSHostingView(rootView: BuildInfoBadgeView())
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Hosting view for the centered session composer overlay (Phase 3 of
    /// session-creation-unified). Added as a subview only while
    /// `SessionComposerStore.shared.isOpen` is true — see
    /// `presentComposerOverlay(projectBinding:)` and the `isOpen` subscription
    /// in `setup()`. Pinned to the container's full bounds so
    /// `SessionComposerOverlay`'s dismiss layer can span the whole terminal;
    /// not touched by `layout()`.
    private lazy var composerOverlayHostingView: TransparentHostingView<AnyView> = {
        let view = TransparentHostingView<AnyView>(rootView: AnyView(EmptyView()))
        view.translatesAutoresizingMaskIntoConstraints = false
        // F9 (Phase 3 review): matches `sidebarHostingView` — this view is
        // pinned by four edge constraints, so its own intrinsic-size
        // reporting is unused work.
        view.sizingOptions = []
        return view
    }()

    /// UserDefaults key for the Cmd+T preference — composer (default) vs.
    /// instant create. Mirrors `Ghostty.Config.autoUpdateChannel`'s
    /// resolution pattern (`ghostties.autoUpdateChannel`): a plain
    /// `UserDefaults.standard` read, since this container is an AppKit
    /// `NSView` and can't use the `@AppStorage` property wrapper directly.
    /// Documented in `SettingsView.swift` beside the update-channel line.
    private static let newSessionOpensComposerDefaultsKey = "ghostties.newSessionOpensComposer"

    /// Whether Cmd+T opens the composer overlay (true, the default) or
    /// creates a session instantly with no UI (false). Unset defaults to
    /// composer per the locked decision in session-creation-unified.
    ///
    /// Extracted to a testable static function (F11, Phase 3 review) taking
    /// an explicit `UserDefaults` — this exact absent/true/false resolution
    /// is precisely the class of bug the review pass was chartered to catch,
    /// so it's covered directly rather than only through the instance
    /// property below.
    static func newSessionOpensComposer(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: newSessionOpensComposerDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: newSessionOpensComposerDefaultsKey)
    }

    private var newSessionOpensComposerPreference: Bool {
        Self.newSessionOpensComposer(in: .standard)
    }

    /// Sidebar material backing for overlay mode. In pinned mode the shared
    /// `backgroundEffectView` already covers the sidebar area, so this is hidden.
    /// In overlay mode it provides the .sidebar material behind the hosting view
    /// with a right-edge shadow to separate from terminal content.
    private let sidebarOverlayBackground: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alphaValue = 0
        view.isHidden = true
        return view
    }()

    /// Session name centered at the top of the terminal card (titlebar region).
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Sidebar toggle button in the terminal card's titlebar region (top-left).
    /// Placed here (not in the sidebar) so it's accessible when the sidebar is closed.
    private lazy var sidebarToggleButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "sidebar.left",
            accessibilityDescription: "Toggle Sidebar"
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 13, weight: .medium
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(toggleSidebar)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityIdentifier("sidebarToggleButton")
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }()

    /// Browser toggle button in the terminal card's titlebar region (top-right).
    /// Globe icon — tinted with accent color when browser is visible.
    private lazy var browserToggleButton: NSButton = {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "globe",
            accessibilityDescription: "Toggle Browser"
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 13, weight: .medium
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(toggleBrowser)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityIdentifier("browserToggleButton")
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }()

    /// Weak reference to the window whose fullscreen observers are currently registered.
    private weak var fullScreenObservedWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    /// Cancellables scoped to the currently-observed focused surface. Cleared and
    /// repopulated every time the active session changes so we only listen to the
    /// one surface driving the chrome color.
    private var observedSurfaceCancellables = Set<AnyCancellable>()

    /// Weak reference to the surface whose theme is currently driving the card
    /// background. Held weakly so a torn-down surface doesn't pin memory; we
    /// also cancel our subscription whenever the active session changes.
    private weak var observedSurface: Ghostty.SurfaceView?

    /// Current sidebar state — always kept in sync with `WorkspaceStore.shared.sidebarMode`.
    private var sidebarMode: SidebarMode = .pinned

    /// Stored constraint for the sidebar toggle button's vertical position.
    /// Updated in layout() from the live close-button frame so the toolbar row
    /// survives macOS version bumps and upstream titlebar refactors.
    private var sidebarToggleCenterYConstraint: NSLayoutConstraint!

    /// True while a sidebar mode-transition animation (`transitionTo` or
    /// `sidebarViewModeChanged`) is in flight. `layout()`'s resize reclamp
    /// must not run while this is true: `sidebarWidthConstraint.animator()`
    /// drives the constraint through intermediate values every frame during
    /// the animation, and reclamping against those mid-flight values would
    /// fight (or outright kill) the open/close animation. Set true right
    /// before `NSAnimationContext.runAnimationGroup` starts, cleared in its
    /// `completionHandler`.
    private var isSidebarTransitionAnimating = false

    /// Stored constraints for animating sidebar show/hide and terminal insets.
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var shadowHostTopConstraint: NSLayoutConstraint!
    private var shadowHostTrailingConstraint: NSLayoutConstraint!
    private var shadowHostBottomConstraint: NSLayoutConstraint!

    /// Top offset of the terminal inside the shadow host, reserving space
    /// for the title bar in pinned mode.
    private var terminalTopConstraint: NSLayoutConstraint!

    /// Dual leading constraints — mutually exclusive.
    /// `.pinned`: terminal leading follows sidebar trailing (pushed right).
    /// `.closed`/`.overlay`: terminal leading follows superview leading (full-width).
    private var shadowHostLeadingToSidebar: NSLayoutConstraint!
    private var shadowHostLeadingToSuperview: NSLayoutConstraint!

    /// Whether the browser panel is currently visible (expanded).
    private var isBrowserVisible = false

    /// Fraction of the resizable width (terminal + browser) that the browser gets.
    /// Range 0.0–1.0; default comes from `WorkspaceLayout.browserSplitRatio`.
    /// Updated when the user drags the divider; used by `layout()` to keep
    /// the split proportional during window resizes.
    private var browserSplitRatio: CGFloat = WorkspaceLayout.browserSplitRatio

    /// Drag handle between terminal and browser cards for resizing.
    private lazy var browserDragHandle: PanelDragHandleView = {
        let handle = PanelDragHandleView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.isHidden = true  // shown only when browser panel is visible
        handle.onDrag = { [weak self] delta in
            self?.handleBrowserDrag(delta: delta)
        }
        return handle
    }()

    /// Drag handle on the sidebar's trailing edge for resizing. Sits in the
    /// same 8pt inset gap the browser drag handle sits in (proven pattern),
    /// just on the other side of the terminal card. Visible only when the
    /// sidebar is pinned; hidden when closed or overlaid.
    private lazy var sidebarDragHandle: PanelDragHandleView = {
        let handle = PanelDragHandleView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.isHidden = true  // corrected to match initialMode in setup()
        handle.onDrag = { [weak self] delta in
            self?.handleSidebarDrag(delta: delta)
        }
        handle.onDragEnd = { [weak self] in
            self?.persistSidebarWidth()
        }
        return handle
    }()

    /// Browser shadow host constraints for the 3-column layout.
    private var browserWidthConstraint: NSLayoutConstraint!
    private var browserShadowHostTopConstraint: NSLayoutConstraint!
    private var browserShadowHostBottomConstraint: NSLayoutConstraint!
    private var browserShadowHostTrailingConstraint: NSLayoutConstraint!
    /// Terminal trailing to browser leading (8pt gap when browser is visible).
    private var shadowHostTrailingToBrowser: NSLayoutConstraint!

    /// Tracking area for hover detection. Only one is active at a time.
    private var activeTrackingArea: NSTrackingArea?

    private var isLightAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    /// Canvas palette color for the current OS appearance. The canvas layer
    /// covers the terminal card background (internal header strip + card rim
    /// around the GPU-rendered terminal area). Owned by the Ghostties design
    /// system — intentionally independent of terminal theme.
    private var canvasPaletteNSColor: NSColor {
        isLightAppearance
            ? WorkspaceLayout.canvasBackgroundLight
            : WorkspaceLayout.canvasBackgroundDark
    }

    /// Chrome palette color for the current OS appearance. The chrome layer
    /// covers the left sidebar column and the gutter padding around the
    /// terminal card. Owned by the Ghostties design system — intentionally
    /// independent of terminal theme.
    private var chromePaletteNSColor: NSColor {
        isLightAppearance
            ? WorkspaceLayout.chromeBackgroundLight
            : WorkspaceLayout.chromeBackgroundDark
    }

    /// Terminal card background — the canvas layer. Always the Ghostties
    /// canvas palette; terminal theme is intentionally NOT bound here. The
    /// terminal content area inside the card is still painted by GhosttyKit
    /// (its theme system owns that rectangle).
    private var cardBackgroundCGColor: CGColor {
        canvasPaletteNSColor.cgColor
    }

    /// Browser card background — unified with the terminal card's canvas
    /// palette so the two card types read as the same design-system layer.
    private var browserCardBackgroundCGColor: CGColor {
        canvasPaletteNSColor.cgColor
    }

    /// Outer workspace canvas behind the sidebar and the gutter around the
    /// terminal card — the chrome layer. Always the Ghostties chrome palette;
    /// terminal theme is intentionally NOT bound here.
    private var canvasBackgroundCGColor: CGColor {
        chromePaletteNSColor.cgColor
    }

    init<ViewModel: TerminalViewModel>(ghostty: Ghostty.App, viewModel: ViewModel, delegate: (any TerminalViewDelegate)? = nil) {
        self.ghostty = ghostty
        self.terminalContainer = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: viewModel, delegate: delegate)
        }

        self.coordinator = SessionCoordinator(ghostty: ghostty)

        #if DEBUG
        if let stress = ProcessInfo.processInfo.environment["GHOSTTIES_STRESS_SESSIONS"],
           let n = Int(stress), n > 0 {
            coordinator.injectStressLoad(count: n)
        }
        #endif

        // Start with a placeholder root; `applySidebarView()` will install the
        // correct view (project-first vs task-first) during setup. We use
        // AnyView so the hosting view's generic type is fixed across the
        // feature-toggle swap.
        let hostingView = TransparentHostingView(rootView: AnyView(EmptyView()))
        // Auto Layout controls the sidebar width; disable intrinsic size reporting
        // to avoid unnecessary layout computation from the hosting view.
        hostingView.sizingOptions = []
        self.sidebarHostingView = hostingView

        super.init(frame: .zero)

        // Session-hybrid: give the coordinator a weak handle to the draft store
        // so spawn/close events can register + GC draft rows in the sidebar.
        // Touching the lazy here materializes the store before the first spawn
        // — the coordinator's weak reference takes it from there.
        self.coordinator.sessionDraftStore = self.sessionDraftStore

        setup()
        applySidebarView()

        // Observe view-mode toggle so the container swaps sidebars without
        // requiring a window rebuild.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarViewModeChanged),
            name: .workspaceSidebarViewModeChanged,
            object: nil
        )

        // Blocker 3 (Phase 3 review round 3): the composer overlay's
        // "dismiss on leaving the app" behavior now observes
        // `NSApplication.didResignActiveNotification` directly, replacing
        // the `NSApp.isActive` check that used to live inline in
        // `windowDidResignKey()` — that check was asserted, not observed,
        // to hold at the point a WINDOW resigns key, and a window resigning
        // key is not the same event as the app deactivating. App-wide, not
        // window-scoped, so registered once here rather than per-window in
        // `viewDidMoveToWindow()`; `object: nil` is correct since there's
        // only one `NSApp`.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Clean up previous window's observers (handles view moving between windows).
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willEnterFullScreenNotification, object: fullScreenObservedWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: fullScreenObservedWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: fullScreenObservedWindow)
        NotificationCenter.default.removeObserver(self, name: .workspaceNewSession, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceNewSessionInstant, object: nil)

        guard let window = window else { return }
        // Give the coordinator a reference to this view so it can discover
        // the window controller through the responder chain.
        coordinator.containerView = self

        // The workspace sidebar replaces the native tab bar — sessions are the new "tabs".
        // Disallow native tabbing to prevent a visual conflict (tab bar + sidebar).
        window.tabbingMode = .disallowed

        // Extend content under titlebar — traffic lights appear inside the sidebar panel.
        window.styleMask.insert(.fullSizeContentView)

        // Apply initial traffic light visibility.
        setTrafficLightsHidden(sidebarMode == .closed)

        // Auto-dismiss overlay when window loses focus + release the sidebar's
        // freeze snapshot so the next focus shows fresh section bucketing.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        // Freeze the sidebar's section layout while the window is active so the
        // user's currently-focused project doesn't shift under bursty agent output.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )

        // Re-measure toolbar row when fullscreen transitions change the titlebar geometry.
        // willEnter fires before AppKit takes a snapshot for the animation, preventing
        // a single-frame glitch during the enter-fullscreen transition.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterOrExitFullScreen),
            name: NSWindow.willEnterFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterOrExitFullScreen),
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterOrExitFullScreen),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
        fullScreenObservedWindow = window

        // Cmd+T (Phase 3 of session-creation-unified). Moved here from
        // `WorkspaceSidebarView` (D2 fix) so the container — present
        // regardless of which sidebar view mode is currently mounted —
        // always receives it, rather than only whichever SwiftUI sidebar
        // view happens to observe it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceNewSession(_:)),
            name: .workspaceNewSession,
            object: window
        )

        // Cmd+Shift+T ("New Session (Instant)", Phase 3) — always creates
        // immediately, ignoring the Cmd+T preference entirely.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceNewSessionInstant(_:)),
            name: .workspaceNewSessionInstant,
            object: window
        )

        // If the window is already key when we move into it, freeze immediately.
        if window.isKeyWindow {
            WorkspaceStore.shared.freezeSnapshot()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard sidebarMode == .pinned || sidebarMode == .closed else { return }
        // Canvas still follows OS light/dark — it's Ghostties chrome, not
        // terminal content.
        layer?.backgroundColor = canvasBackgroundCGColor
        // Terminal card follows the focused surface's theme when available;
        // the resolver handles the light/dark fallback itself.
        terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
        // Browser card has no theme concept — always the light/dark fallback.
        browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
    }

    /// Zero out safe area insets so Auto Layout constraints measure from
    /// the actual window edge, not the titlebar-offset safe area.
    /// Without this, `topAnchor` is shifted down by ~28pt (titlebar height)
    /// and our `terminalTopInset` constant has no visible effect.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var intrinsicContentSize: NSSize {
        let termSize = terminalContainer.intrinsicContentSize
        guard termSize.width != NSView.noIntrinsicMetric else { return termSize }
        switch sidebarMode {
        case .pinned:
            let inset = WorkspaceLayout.terminalInset
            return NSSize(
                width: termSize.width + currentSidebarWidth + inset * 2,
                height: termSize.height + inset * 2
            )
        case .closed:
            let inset = WorkspaceLayout.terminalInset
            return NSSize(
                width: termSize.width + inset * 2,
                height: termSize.height + inset * 2
            )
        case .overlay:
            return termSize
        }
    }

    /// Total horizontal space available to the terminal + browser combined.
    /// Subtracts sidebar (when pinned) and the three inset gaps (leading, gap, trailing).
    ///
    /// Reads `widthModel.width` — the sidebar's applied width while pinned —
    /// rather than `currentSidebarWidth` (the user's desired width). The two
    /// can diverge once the resize reclamp in `layout()` shrinks the applied
    /// width below the desired one without touching the desired value (see
    /// that reclamp's doc comment); the browser math needs the real width the
    /// sidebar currently occupies on screen, not the user's stored preference.
    /// Note: `widthModel.width` is stale in closed/overlay mode (it isn't
    /// written when transitioning to `.closed`), which is fine because both
    /// consumers here gate on `sidebarMode == .pinned` anyway.
    private var resizableWidth: CGFloat {
        let sidebarWidth = sidebarMode == .pinned ? widthModel.width : 0
        let inset = WorkspaceLayout.terminalInset
        // Three inset slots: leading of terminal, gap between panels, trailing of browser.
        return bounds.width - sidebarWidth - inset * 3
    }

    override func layout() {
        super.layout()

        // Re-clamp the sidebar width when the window shrinks. The sidebar
        // previously never re-clamped on resize, so a sidebar sitting near
        // its max could exceed the available space once the window got
        // small enough. Pinned mode only — closed mode is always width 0,
        // and overlay floats over the terminal rather than sharing its
        // space. Runs BEFORE the browser split clamp below: the browser
        // math reads `resizableWidth`, which reads the sidebar's live
        // applied width, so the sidebar must be settled first or the
        // browser gets one frame of stale width.
        //
        // `bounds.width > 0` guard: during teardown, tab merge/detach, and
        // fullscreen intermediates `bounds.width` can transiently be 0,
        // which would drive `maxByAvailableSpace` deeply negative and
        // collapse the sidebar to `sidebarMinWidth`.
        //
        // `currentSidebarWidth` is the user's DESIRED width (the only
        // in-memory record of what they dragged to — see its doc comment);
        // it is never written here, only read. Only the applied
        // width — `sidebarWidthConstraint.constant` / `widthModel.width` —
        // is clamped. This mirrors the browser panel's own split: the
        // desired value (`browserSplitRatio`) is untouched by its resize
        // clamp below, only the applied `browserWidthConstraint.constant`
        // is. Without this separation, shrinking the window below the
        // user's chosen width permanently overwrites their preference —
        // regrowing the window would never restore it.
        //
        // Guard witness is `widthModel.width`, not the animated
        // `sidebarWidthConstraint.constant`: `transitionTo`/
        // `sidebarViewModeChanged` drive that constraint through animator()
        // over ~0.2s, so mid-animation it holds transient intermediate
        // values every frame. Comparing against those would make this
        // block "correct" the constraint back to its target on every
        // frame, fighting (or fully overriding) the open animation. We
        // also bail outright while a mode-transition animation is in
        // flight — the animation itself is already driving the constraint
        // to the right place.
        if sidebarMode == .pinned && bounds.width > 0 && !isSidebarTransitionAnimating {
            let inset = WorkspaceLayout.terminalInset
            let maxByAvailableSpace = bounds.width - WorkspaceLayout.terminalMinWidth - inset * 2
            let upperBound = min(WorkspaceLayout.sidebarMaxWidth, max(maxByAvailableSpace, WorkspaceLayout.sidebarMinWidth))
            let reclamped = min(max(currentSidebarWidth, WorkspaceLayout.sidebarMinWidth), upperBound)
            if reclamped != widthModel.width {
                sidebarWidthConstraint.constant = reclamped
                widthModel.width = reclamped
            }
        }

        // Keep the terminal/browser split proportional when the window resizes.
        if isBrowserVisible {
            let available = resizableWidth
            let maxBrowser = available - WorkspaceLayout.terminalMinWidth
            let desired = available * browserSplitRatio
            let clamped = min(max(desired, WorkspaceLayout.browserMinWidth), max(maxBrowser, WorkspaceLayout.browserMinWidth))
            browserWidthConstraint.constant = clamped
        }

        // Explicit shadow paths eliminate per-frame offscreen rendering.
        // Without these, Core Animation rasterizes the entire layer to compute
        // the shadow shape every frame — expensive for a terminal that redraws at 60fps.
        //
        // `bounds.isEmpty` guard: mirrors the resize reclamp's `bounds.width > 0`
        // guard above — during animated constraint changes (mode transitions,
        // teardown, fullscreen intermediates) a shadow host's bounds can
        // transiently be zero-size. Once an explicit shadowPath is set, Core
        // Animation uses it exclusively; installing a zero-rect path renders no
        // shadow at all, silently, until a later layout pass rebuilds it from
        // settled bounds. Skipping leaves the previously-installed path in
        // place, which is strictly better than a dead one.
        if !terminalShadowHost.bounds.isEmpty {
            terminalShadowHost.layer?.shadowPath = CGPath(
                roundedRect: terminalShadowHost.bounds,
                cornerWidth: WorkspaceLayout.terminalCornerRadius,
                cornerHeight: WorkspaceLayout.terminalCornerRadius,
                transform: nil
            )
        }
        if !browserShadowHost.bounds.isEmpty {
            browserShadowHost.layer?.shadowPath = CGPath(
                roundedRect: browserShadowHost.bounds,
                cornerWidth: WorkspaceLayout.terminalCornerRadius,
                cornerHeight: WorkspaceLayout.terminalCornerRadius,
                transform: nil
            )
        }
        sidebarOverlayBackground.layer?.shadowPath = CGPath(
            rect: sidebarOverlayBackground.bounds,
            transform: nil
        )

        // Re-derive toolbar row position from live close-button frame.
        // This survives macOS version bumps and upstream titlebar refactors.
        if let constant = WorkspaceLayout.titlebarRowTopAnchorConstant(in: self) {
            if abs(sidebarToggleCenterYConstraint.constant - constant) > 0.5 {
                sidebarToggleCenterYConstraint.constant = constant
            }
            // Publish to SwiftUI sidebar so the + button stays in sync.
            if abs(WorkspaceStore.shared.toolbarRowTopAnchorConstant - constant) > 0.5 {
                WorkspaceStore.shared.toolbarRowTopAnchorConstant = constant
            }
        }

    }

    // MARK: - Sidebar View Mode (v0 feature toggle)

    /// Build the correct sidebar SwiftUI view for the current view mode and
    /// install it on the hosting view. Called once during setup and again each
    /// time the view-mode toggle fires a `workspaceSidebarViewModeChanged`
    /// notification. Both branches share the same titlebar spacer so the
    /// traffic-light region stays consistent across modes.
    private func applySidebarView() {
        guard let hostingView = sidebarHostingView as? NSHostingView<AnyView> else { return }

        let mode = currentSidebarViewMode
        if mode == "taskFirst" {
            let content = VStack(spacing: 0) {
                // Reserve space for the window's traffic lights so the NEEDS YOU
                // header doesn't render behind them.
                Color.clear.frame(height: WorkspaceLayout.titlebarSpacerHeight)
                TaskSidebarView(
                    taskStore: taskStore,
                    sessionDraftStore: sessionDraftStore
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Pin to a concrete width via `SidebarWidthFrame` so the nested
            // LazyStacks inside the three zones receive a definite cross-axis
            // proposal. Without this the hosting view proposed .infinity,
            // which sent LazyVStack.sizeThatFits into an infinite measurement
            // recursion (see fix/sidebar-layout-hang-v0). The wrapper reads
            // `widthModel` (initialized from `currentSidebarWidth`) so the
            // drag handler can update the width without rebuilding this tree.
            let view = SidebarWidthFrame(model: widthModel, content: content)
                .ignoresSafeArea(.container, edges: .top)
                // Row clicks in TaskRowView reach back into the terminal via the
                // coordinator and look up a matching project via WorkspaceStore.
                // The store is observed so the row sees a current projects list.
                .environmentObject(taskStore)
                .environmentObject(coordinator)
                .environmentObject(WorkspaceStore.shared)
                .environmentObject(sessionDraftStore)
            hostingView.rootView = AnyView(view)
        } else {
            let content = WorkspaceSidebarView()
                .environmentObject(WorkspaceStore.shared)
                .environmentObject(coordinator)
                .ignoresSafeArea(.container, edges: .top)
            // Pin to a concrete width via `SidebarWidthFrame` so the nested
            // LazyVStack inside WorkspaceSidebarView receives a definite
            // cross-axis proposal. Without this the hosting view proposes
            // .infinity, which sends LazyVStack.sizeThatFits into infinite
            // measurement recursion — the same root cause fixed for taskFirst
            // in sidebar-layout-hang-v0 (commit 11530667b). The wrapper reads
            // `widthModel` so the user-resizable drag handle continues to
            // work without rebuilding this tree on every tick.
            let view = SidebarWidthFrame(model: widthModel, content: content)
            hostingView.rootView = AnyView(view)
        }
    }

    @objc private func sidebarViewModeChanged() {
        applySidebarView()

        // Update width constraint + intrinsic size to reflect the new mode's
        // sidebar width. Only animate when the sidebar is actually pinned; in
        // closed mode the width is 0, in overlay mode the constraint follows
        // the overlay width which is also driven by currentSidebarWidth.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isSidebarTransitionAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            switch sidebarMode {
            case .pinned, .overlay:
                sidebarWidthConstraint.animator().constant = currentSidebarWidth
                widthModel.width = currentSidebarWidth
            case .closed:
                break
            }
        }, completionHandler: { [weak self] in
            self?.isSidebarTransitionAnimating = false
            // The resize reclamp in `layout()` was deferred for the duration of
            // this animation. Force one more layout pass now that the flag is
            // clear, or a window shrink that happened mid-animation may never
            // get re-clamped.
            self?.needsLayout = true
        })
        updateTrackingAreas()
        invalidateIntrinsicContentSize()
    }

    // MARK: - Traffic Lights

    private func setTrafficLightsHidden(_ hidden: Bool) {
        guard let window = window else { return }
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = hidden
        }
    }

    // MARK: - Sidebar State Machine

    /// Toggle sidebar via keyboard shortcut (Cmd+Shift+E).
    @objc func toggleSidebar() {
        switch sidebarMode {
        case .pinned:  transitionTo(.closed)
        case .closed:  transitionTo(.pinned)
        case .overlay: transitionTo(.pinned)  // promote overlay to pinned
        }
    }

    // MARK: - Browser Toggle

    /// Toggle browser panel visibility via keyboard shortcut (Cmd+B) or globe button.
    /// Shows the browser as a side panel next to the terminal (Dia Browser style).
    /// If no browser session exists yet, creates one via the coordinator.
    @objc func toggleBrowser() {
        if isBrowserVisible {
            // Collapse the side panel.
            animateBrowserPanel(visible: false)
        } else {
            // Ensure we have a browser session with a CEFBrowserView.
            // Check for an existing live browser session first.
            let existingManager: BrowserTabManager? = coordinator.browserManagers.values.first { manager in
                coordinator.browserManagers.contains { (id, m) in
                    m === manager && coordinator.statuses[id]?.isAlive == true
                }
            }

            if let manager = existingManager {
                embedBrowserInPanel(manager)
                animateBrowserPanel(visible: true)
            } else if let project = WorkspaceStore.shared.projects.first {
                // Create a new browser session — this will call showBrowserContent,
                // which embeds into the side panel and animates it open.
                Task { @MainActor in
                    await coordinator.createQuickSession(for: project, template: .browser)
                }
            }
        }
    }

    /// Animate the browser side panel open or closed.
    private func animateBrowserPanel(visible: Bool) {
        isBrowserVisible = visible

        // Swap trailing constraints: terminal trails to browser or to window edge.
        if visible {
            shadowHostTrailingConstraint.isActive = false
            shadowHostTrailingToBrowser.isActive = true
        } else {
            shadowHostTrailingToBrowser.isActive = false
            shadowHostTrailingConstraint.isActive = true
        }

        // Show/hide the drag handle with the browser panel.
        browserDragHandle.isHidden = !visible

        // Update globe button tint: accent color when open, secondary when closed.
        browserToggleButton.contentTintColor = visible
            ? WorkspaceLayout.waitingTerracottaNS
            : .secondaryLabelColor

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            if visible {
                // Expand browser using the stored split ratio.
                let available = resizableWidth
                let maxBrowser = available - WorkspaceLayout.terminalMinWidth
                let desired = available * browserSplitRatio
                let browserWidth = min(max(desired, WorkspaceLayout.browserMinWidth), max(maxBrowser, WorkspaceLayout.browserMinWidth))
                browserWidthConstraint.animator().constant = browserWidth
                browserShadowHost.animator().alphaValue = 1
            } else {
                // Collapse browser.
                browserWidthConstraint.animator().constant = 0
                browserShadowHost.animator().alphaValue = 0
            }
        }

        // Shadow + corner radius (non-animatable).
        browserShadowHost.layer?.shadowOpacity = visible ? WorkspaceLayout.canvasShadowOpacity : 0

        invalidateIntrinsicContentSize()
    }

    /// Handle a horizontal drag delta from the browser drag handle.
    /// Negative delta = dragging left (browser grows), positive = dragging right (browser shrinks).
    private func handleBrowserDrag(delta: CGFloat) {
        // Available space for terminal + browser combined.
        let totalResizable = resizableWidth

        // Current browser width and proposed new width.
        let currentBrowserWidth = browserWidthConstraint.constant
        // Dragging left (negative delta) grows the browser.
        let proposedBrowserWidth = currentBrowserWidth - delta

        // Minimum terminal width — ensure terminal never gets too narrow.
        // Clamp: browser must be >= browserMinWidth and terminal must be >= terminalMinWidth.
        let maxBrowserWidth = totalResizable - WorkspaceLayout.terminalMinWidth
        let clampedWidth = min(max(proposedBrowserWidth, WorkspaceLayout.browserMinWidth), max(maxBrowserWidth, WorkspaceLayout.browserMinWidth))

        browserWidthConstraint.constant = clampedWidth

        // Persist the ratio so the split scales proportionally on window resize.
        if totalResizable > 0 {
            browserSplitRatio = clampedWidth / totalResizable
        }
    }

    /// Handle a horizontal drag delta from the sidebar drag handle.
    /// Positive delta = dragging right (sidebar grows), negative = dragging left (sidebar shrinks).
    private func handleSidebarDrag(delta: CGFloat) {
        let proposed = sidebarWidthConstraint.constant + delta

        // Upper bound: the design-token max, but never wider than leaves room
        // for the terminal's minimum usable width (mirrors the browser drag
        // handle's clamp against `WorkspaceLayout.terminalMinWidth`).
        let inset = WorkspaceLayout.terminalInset
        let maxByAvailableSpace = bounds.width - WorkspaceLayout.terminalMinWidth - inset * 2
        let upperBound = min(WorkspaceLayout.sidebarMaxWidth, max(maxByAvailableSpace, WorkspaceLayout.sidebarMinWidth))
        let clamped = min(max(proposed, WorkspaceLayout.sidebarMinWidth), upperBound)

        // Single source of truth: writing through `currentSidebarWidth` updates
        // the same stored value `applySidebarView()` reads when it next runs,
        // and writing `widthModel.width` updates the live SwiftUI
        // `.frame(width:)` pin (via `SidebarWidthFrame`) without rebuilding the
        // sidebar view tree — so the AppKit constraint, the stored width, and
        // the SwiftUI frame never diverge (the layout-loop landmine this pin
        // exists to prevent). Deliberately does NOT call `applySidebarView()`:
        // that reconstructs the whole sidebar SwiftUI tree (WorkspaceSidebarView/
        // TaskSidebarView + environment objects) and was previously invoked on
        // every mouseDragged tick at 60-120Hz — the sidebar subtree has a
        // documented render-cost history (two shipped 100%-CPU beachballs).
        sidebarWidthConstraint.constant = clamped
        currentSidebarWidth = clamped
        widthModel.width = clamped
    }

    /// Persist the drag-resized width to this view mode's UserDefaults key.
    /// Called from `sidebarDragHandle.onDragEnd` (mouseUp) only — not on every
    /// drag tick — to avoid excessive UserDefaults writes.
    private func persistSidebarWidth() {
        let key = Self.sidebarWidthDefaultsKey(forMode: currentSidebarViewMode)
        UserDefaults.standard.set(Double(currentSidebarWidth), forKey: key)
    }

    /// Embed a browser manager's active tab view into `browserPanelView.contentArea`.
    private func embedBrowserInPanel(_ manager: BrowserTabManager) {
        // Remove any existing content from the panel's content area.
        for subview in browserPanelView.contentArea.subviews {
            subview.removeFromSuperview()
        }

        // Wire the navigation bar actions.
        let navBar = browserPanelView.navigationBar
        navBar.backButton.target = self
        navBar.backButton.action = #selector(browserGoBack)
        navBar.forwardButton.target = self
        navBar.forwardButton.action = #selector(browserGoForward)
        navBar.reloadButton.target = self
        navBar.reloadButton.action = #selector(browserReload)
        navBar.devToolsButton.target = self
        navBar.devToolsButton.action = #selector(browserToggleDevTools)
        navBar.urlField.delegate = self

        // Wire the tab bar to this manager.
        browserPanelView.tabBar.tabManager = manager

        // Wire the bridge to this navigation bar.
        let bridge = coordinator.bridge(for: manager)
        bridge?.navigationBar = navBar

        // Embed the active tab's browser view.
        if let activeTabId = manager.activeTabId,
           let browserView = manager.browserViews[activeTabId] {
            browserView.translatesAutoresizingMaskIntoConstraints = false
            browserPanelView.contentArea.addSubview(browserView)
            NSLayoutConstraint.activate([
                browserView.topAnchor.constraint(equalTo: browserPanelView.contentArea.topAnchor),
                browserView.leadingAnchor.constraint(equalTo: browserPanelView.contentArea.leadingAnchor),
                browserView.trailingAnchor.constraint(equalTo: browserPanelView.contentArea.trailingAnchor),
                browserView.bottomAnchor.constraint(equalTo: browserPanelView.contentArea.bottomAnchor),
            ])
            // Force layout so CEFBrowserView gets its real size, then tell CEF to resize.
            browserPanelView.contentArea.layoutSubtreeIfNeeded()
            if let cefView = browserView as? CEFBrowserView {
                cefView.setFrameSize(browserPanelView.contentArea.bounds.size)
            }
        }

        _activeBrowserManager = manager
    }

    // MARK: - Browser Session Content

    /// Show a browser session's content in the side panel (terminal stays visible).
    /// Called by SessionCoordinator when switching to or creating a browser session.
    func showBrowserContent(_ manager: BrowserTabManager, bridge: BrowserSessionBridge?) {
        embedBrowserInPanel(manager)

        // Wire the bridge if provided (overrides the one found in embedBrowserInPanel).
        if let bridge = bridge {
            bridge.navigationBar = browserPanelView.navigationBar
        }

        // Open the side panel if it isn't already visible.
        if !isBrowserVisible {
            animateBrowserPanel(visible: true)
        }
    }

    /// Restore terminal-only display (collapse browser side panel).
    /// Called by SessionCoordinator when switching from a browser session to a terminal session.
    func showTerminalContent() {
        // Terminal is always visible in side-by-side mode, so nothing to un-hide.
        // Collapse the browser panel if it's open.
        if isBrowserVisible {
            animateBrowserPanel(visible: false)
        }
        _activeBrowserManager = nil
    }

    /// Weak reference to the active browser manager for navigation actions.
    private weak var _activeBrowserManager: BrowserTabManager?

    /// The CEFBrowserView for the active tab, if any.
    private var activeCEFView: CEFBrowserView? {
        guard let tabId = _activeBrowserManager?.activeTabId else { return nil }
        return _activeBrowserManager?.browserViews[tabId] as? CEFBrowserView
    }

    @objc private func browserGoBack() {
        guard let view = activeCEFView else { return }
        view.goBack()
    }

    @objc private func browserGoForward() {
        guard let view = activeCEFView else { return }
        view.goForward()
    }

    @objc private func browserReload() {
        guard let view = activeCEFView else { return }
        if view.isLoading {
            view.stopLoading()
        } else {
            view.reload()
        }
    }

    @objc private func browserToggleDevTools() {
        guard let view = activeCEFView else { return }

        if browserPanelView.isDevToolsVisible {
            // Close inline DevTools and collapse the panel area.
            view.closeDevTools()
            browserPanelView.hideDevTools()
        } else {
            // Expand the inline DevTools area, then tell CEF to render into it.
            browserPanelView.showDevTools()
            view.showInlineDevTools(browserPanelView.devToolsArea)
        }
    }

    /// Minimum interval between transitions to prevent rapid oscillation
    /// (e.g. mouse hovering at the overlay/closed boundary).
    private var lastTransitionTime: CFTimeInterval = 0

    /// Centralized state transition. All sidebar mode changes go through here.
    private func transitionTo(_ newMode: SidebarMode) {
        guard newMode != sidebarMode else { return }
        let now = CACurrentMediaTime()
        guard now - lastTransitionTime > 0.25 else { return }
        lastTransitionTime = now
        sidebarMode = newMode

        let inset = WorkspaceLayout.terminalInset

        // 1. Swap leading constraints before animation.
        switch newMode {
        case .pinned:
            shadowHostLeadingToSuperview.isActive = false
            shadowHostLeadingToSidebar.isActive = true
        case .closed, .overlay:
            shadowHostLeadingToSidebar.isActive = false
            shadowHostLeadingToSuperview.isActive = true
        }

        // 2. Z-ordering for overlay mode.
        let overlayZ: CGFloat = newMode == .overlay ? 100 : 0
        sidebarHostingView.layer?.zPosition = overlayZ
        sidebarOverlayBackground.layer?.zPosition = newMode == .overlay ? 99 : 0

        // 3. Toggle isHidden so inactive NSVisualEffectViews leave the compositing tree.
        //    The background material is only visible in overlay mode (floating hover state).
        //    In pinned mode the sidebar is transparent — the window background shows through.
        switch newMode {
        case .pinned:
            backgroundEffectView.isHidden = true
            sidebarOverlayBackground.isHidden = true
        case .closed:
            backgroundEffectView.isHidden = true
            sidebarOverlayBackground.isHidden = true
        case .overlay:
            backgroundEffectView.isHidden = false
            sidebarOverlayBackground.isHidden = false
        }

        // Sidebar drag handle: only active while the sidebar is pinned. Hidden
        // in closed mode (sidebar isn't there) and in overlay mode (transient
        // hover state — not a resize target).
        sidebarDragHandle.isHidden = newMode != .pinned

        // 4. Animate constraints, widths, alphas.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isSidebarTransitionAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            switch newMode {
            case .pinned:
                sidebarWidthConstraint.animator().constant = currentSidebarWidth
                widthModel.width = currentSidebarWidth
                sidebarHostingView.animator().alphaValue = 1
                shadowHostTopConstraint.animator().constant = inset
                shadowHostLeadingToSidebar.animator().constant = inset
                if !isBrowserVisible {
                    shadowHostTrailingConstraint.animator().constant = -inset
                }
                shadowHostBottomConstraint.animator().constant = -inset
                terminalTopConstraint.animator().constant = WorkspaceLayout.terminalTitleBarHeight
                titleLabel.animator().alphaValue = 1
                sidebarToggleButton.animator().alphaValue = 1
                browserToggleButton.animator().alphaValue = 1
                sidebarOverlayBackground.animator().alphaValue = 0
                // Browser insets match terminal.
                browserShadowHostTopConstraint.animator().constant = inset
                browserShadowHostBottomConstraint.animator().constant = -inset
                browserShadowHostTrailingConstraint.animator().constant = -inset

            case .closed:
                sidebarWidthConstraint.animator().constant = 0
                sidebarHostingView.animator().alphaValue = 0
                shadowHostTopConstraint.animator().constant = inset
                shadowHostLeadingToSuperview.animator().constant = inset
                if !isBrowserVisible {
                    shadowHostTrailingConstraint.animator().constant = -inset
                }
                shadowHostBottomConstraint.animator().constant = -inset
                terminalTopConstraint.animator().constant = WorkspaceLayout.terminalTitleBarHeight
                titleLabel.animator().alphaValue = 1
                sidebarToggleButton.animator().alphaValue = 1
                browserToggleButton.animator().alphaValue = 1
                sidebarOverlayBackground.animator().alphaValue = 0
                // Browser insets match terminal.
                browserShadowHostTopConstraint.animator().constant = inset
                browserShadowHostBottomConstraint.animator().constant = -inset
                browserShadowHostTrailingConstraint.animator().constant = -inset

            case .overlay:
                // If browser was visible, swap trailing constraint back to window edge.
                if isBrowserVisible {
                    shadowHostTrailingToBrowser.isActive = false
                    shadowHostTrailingConstraint.isActive = true
                    isBrowserVisible = false
                    browserToggleButton.contentTintColor = .secondaryLabelColor
                    browserDragHandle.isHidden = true
                }
                sidebarWidthConstraint.animator().constant = currentSidebarWidth
                widthModel.width = currentSidebarWidth
                sidebarHostingView.animator().alphaValue = 1
                // Terminal floats as a carded, inset canvas — same outer inset
                // as pinned/closed. The sidebar (z-order above the card) floats
                // over its left edge rather than sharing space with it.
                shadowHostTopConstraint.animator().constant = inset
                shadowHostLeadingToSuperview.animator().constant = inset
                shadowHostTrailingConstraint.animator().constant = -inset
                shadowHostBottomConstraint.animator().constant = -inset
                // Title row stays hidden in overlay — unchanged from before.
                terminalTopConstraint.animator().constant = 0
                titleLabel.animator().alphaValue = 0
                sidebarToggleButton.animator().alphaValue = 0
                browserToggleButton.animator().alphaValue = 0
                sidebarOverlayBackground.animator().alphaValue = 1
                // Collapse browser in overlay mode.
                browserWidthConstraint.animator().constant = 0
                browserShadowHost.animator().alphaValue = 0
                browserShadowHostTopConstraint.animator().constant = 0
                browserShadowHostBottomConstraint.animator().constant = 0
                browserShadowHostTrailingConstraint.animator().constant = 0
            }
        }, completionHandler: { [weak self] in
            self?.isSidebarTransitionAnimating = false
            // The resize reclamp in `layout()` was deferred for the duration of
            // this animation. Force one more layout pass now that the flag is
            // clear, or a window shrink that happened mid-animation may never
            // get re-clamped.
            self?.needsLayout = true
        })
        // 5. Non-animatable properties.
        switch newMode {
        case .pinned:
            terminalContainer.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            terminalShadowHost.layer?.shadowOpacity = WorkspaceLayout.canvasShadowOpacity
            terminalShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
            browserShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
            browserShadowHost.layer?.shadowOpacity = isBrowserVisible ? WorkspaceLayout.canvasShadowOpacity : 0
            layer?.backgroundColor = canvasBackgroundCGColor
            sidebarOverlayBackground.layer?.shadowOpacity = 0
        case .closed:
            terminalContainer.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            terminalShadowHost.layer?.shadowOpacity = WorkspaceLayout.canvasShadowOpacity
            terminalShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
            browserShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
            browserShadowHost.layer?.shadowOpacity = isBrowserVisible ? WorkspaceLayout.canvasShadowOpacity : 0
            layer?.backgroundColor = canvasBackgroundCGColor
            sidebarOverlayBackground.layer?.shadowOpacity = 0
        case .overlay:
            // Same carded canvas treatment as pinned/closed — the terminal
            // always reads as a floating card, even while the sidebar hovers.
            terminalContainer.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            terminalShadowHost.layer?.shadowOpacity = WorkspaceLayout.canvasShadowOpacity
            terminalShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
            // Browser panel is force-collapsed on entry to overlay (see above);
            // leave its own card styling untouched.
            browserShadowHost.layer?.cornerRadius = 0
            browserShadowHost.layer?.backgroundColor = nil
            browserShadowHost.layer?.shadowOpacity = 0
            layer?.backgroundColor = canvasBackgroundCGColor
            // The sidebar keeps its own separate shadow — it still genuinely
            // floats over the terminal card, distinct from the card's shadow.
            sidebarOverlayBackground.layer?.shadowOpacity = 0.2
        }

        // 6. Traffic lights.
        setTrafficLightsHidden(newMode == .closed)

        // 7. Refresh tracking areas.
        updateTrackingAreas()

        // 8. Persist (overlay is transient — store persists it as .closed).
        WorkspaceStore.shared.updateSidebarMode(newMode)

        invalidateIntrinsicContentSize()
    }

    // MARK: - Hover Tracking

    override func updateTrackingAreas() {
        // Remove existing tracking area.
        if let area = activeTrackingArea {
            removeTrackingArea(area)
            activeTrackingArea = nil
        }

        super.updateTrackingAreas()

        switch sidebarMode {
        case .closed:
            // Install trigger zone: thin strip at left edge.
            let triggerRect = CGRect(
                x: 0, y: 0,
                width: WorkspaceLayout.overlayTriggerWidth,
                height: bounds.height
            )
            let area = NSTrackingArea(
                rect: triggerRect,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            activeTrackingArea = area

        case .overlay:
            // Install sidebar zone: covers sidebar width.
            let sidebarRect = CGRect(
                x: 0, y: 0,
                width: currentSidebarWidth,
                height: bounds.height
            )
            let area = NSTrackingArea(
                rect: sidebarRect,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            activeTrackingArea = area

        case .pinned:
            // No tracking areas needed.
            break
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if sidebarMode == .closed {
            transitionTo(.overlay)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if sidebarMode == .overlay {
            transitionTo(.closed)
        }
    }

    // MARK: - Window Focus

    @objc private func windowDidResignKey() {
        if sidebarMode == .overlay {
            transitionTo(.closed)
        }
        // Blocker 3 (Phase 3 review round 3): the composer-dismiss clause
        // that used to live here is gone. Round 2's `NSApp.isActive` gate
        // had two problems: (1) `SessionCoordinator`/this container is
        // per-window, so gating a PER-WINDOW resign-key notification doesn't
        // distinguish "another Ghostties window took key" (should NOT
        // dismiss this window's overlay — no bug here, working as intended)
        // from "the app itself was deactivated" (should dismiss, but this
        // notification alone can't tell); and worse, with the gate in place
        // clicking window B never dismissed window A's overlay either,
        // reopening round 1's original two-window finding. (2) `NSApp
        // .isActive` inside a window-resign-key handler is ASSERTED, not
        // observed to actually be accurate at that point in AppKit's
        // documented ordering (`willResignActive` -> window resigns key ->
        // `didResignActive`) — if it still read `true` there, the gate was
        // always false and dismiss-on-leave-app was silently dead code, a
        // revert of F5 nobody would have noticed. Fixed by not inferring
        // app-deactivation from a window notification at all — see
        // `applicationDidResignActive()` below, which observes
        // `NSApplication.didResignActiveNotification` directly, and the
        // per-overlay `owningWindow` ownership check in
        // `presentComposerOverlay`/`dismissComposerOverlayIfPresented` that
        // makes each container ignore dismiss signals for an overlay it
        // doesn't own — together these replace both halves of what this
        // clause tried to do, correctly, without reintroducing the
        // per-container-store refactor rejected in round 2 as too large.
        // Sidebar smart-sections freeze-on-focus (plan unit 4):
        // window blur is treated as the primary release trigger. The next time
        // the window becomes key we'll re-freeze with the (potentially changed)
        // layout, and SwiftUI animates the diff via `sectionSignature`.
        //
        // Implementation note: we're using window-level key-state via
        // `NSWindowDelegate`-style notifications rather than SwiftUI's
        // `.focused()` because the sidebar is hosted in an `NSHostingView`
        // (not an `NSHostingController`), and its rows aren't text-input
        // focusable — `.focused()` doesn't fire reliably for tap-target rows
        // in a hosting view. The window-key signal is coarser but bulletproof:
        // any time the user is interacting with this window, the sidebar's
        // bucketing is frozen.
        WorkspaceStore.shared.releaseSnapshot()
    }

    /// Blocker 3 (Phase 3 review round 3): the genuine "user left the app"
    /// dismiss for the composer overlay — see the registration comment in
    /// `init` and the removed-clause comment in `windowDidResignKey()`
    /// above for what this replaces and why. Every container independently
    /// receives this (one `NSApp`, `object: nil`); `dismissComposerOverlayIfPresented()`
    /// already self-guards on `superview != nil`, so only the window(s)
    /// that actually have an installed overlay do anything.
    @objc private func applicationDidResignActive() {
        dismissComposerOverlayIfPresented()
    }

    @objc private func windowDidBecomeKey() {
        // Sidebar smart-sections freeze-on-focus (plan unit 4):
        // freeze the section layout while this window is the user's focus.
        // No-op if already frozen — `freezeSnapshot()` guards against clobber.
        WorkspaceStore.shared.freezeSnapshot()
    }

    @objc private func windowDidEnterOrExitFullScreen() {
        // Fullscreen transitions reposition the traffic lights. Trigger a layout
        // pass so titlebarRowTopAnchorConstant re-reads the new close-button frame.
        needsLayout = true
        // F7 follow-up (Phase 3 review round 2): no titlebar to protect in
        // fullscreen, so the composer overlay's dismiss layer shouldn't leave
        // that band unclaimed there.
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        composerCenteringModel.titlebarBandHeight = isFullScreen ? 0 : WorkspaceLayout.titlebarSpacerHeight
    }

    // MARK: - Session Composer Overlay (Phase 3)

    /// Cmd+T. Opens the composer overlay by default; creates a session
    /// instantly (no UI) when `ghostties.newSessionOpensComposer` is off —
    /// both paths use the same smart-default cascade (D1: no more "nothing
    /// selected" guard).
    @objc private func handleWorkspaceNewSession(_ notification: Notification) {
        if newSessionOpensComposerPreference {
            presentComposerOverlay(projectBinding: .open)
        } else {
            instantCreateSession()
        }
    }

    /// Cmd+Shift+T. Always creates instantly — the Cmd+T preference is
    /// never consulted here.
    @objc private func handleWorkspaceNewSessionInstant(_ notification: Notification) {
        instantCreateSession()
    }

    /// Opens the centered session composer overlay. Called from Cmd+T
    /// (composer preference on, the default) and the sidebar toolbar's
    /// "+ New Session" button (`NewSessionToolbarButton`, which reaches this
    /// via `coordinator.containerView`).
    func presentComposerOverlay(projectBinding: SessionComposerRequest.ProjectBinding) {
        // Blocker 3 (Phase 3 review round 3): if a DIFFERENT window
        // currently owns an open composer, dismiss its overlay first — this
        // window is about to become the sole owner of
        // `SessionComposerStore.shared`'s state. Without this, two windows
        // could each install their own overlay against the same shared
        // store, each visibly showing whichever window opened last.
        if let currentOwner = SessionComposerStore.shared.owningWindow,
           currentOwner !== window,
           let ownerContainer = currentOwner.contentView as? WorkspaceViewContainer {
            ownerContainer.dismissComposerOverlayIfPresented()
        }
        SessionComposerStore.shared.owningWindow = window

        // F5 (Phase 3 review): single-presentation invariant — the centered
        // overlay always wins over any open per-row anchored popover, since
        // both share the one `SessionComposerStore` singleton's state and a
        // second opener silently defeats the popover's `.locked` write-path
        // enforcement otherwise. `ProjectDisclosureRow` observes this and
        // closes its own popover.
        NotificationCenter.default.post(name: .workspaceComposerOverlayWillPresent, object: window)

        // R2 (Phase 3 review round 2): the post above sets `showingTemplatePicker
        // = false` synchronously in any open row, but the popover's CONTENT
        // teardown — firing its `onChange(of: isPresented)` / `onDisappear`,
        // both of which call `composerStore.cancel()` — was NOT proven to
        // run within this same call stack. Opening/installing the overlay
        // synchronously right after the post let a `cancel()` from that
        // teardown (whenever it actually lands) clobber `isOpen` back to
        // `false` immediately after we set it, killing the just-presented
        // overlay one frame in (and, while both were briefly alive, leaving
        // the old `.locked` popover visibly showing a `currentProjectBinding`
        // this call had already overwritten — the wrong-project write F5 was
        // supposed to close).
        //
        // Blocker 1 (Phase 3 review round 3): deferring this half to the
        // next runloop turn does NOT, by itself, guarantee the popover's
        // deferred teardown (if it is in fact deferred — see the
        // `$isOpen` sink's comment in `setup()`) lands BEFORE this block
        // rather than after; the relative order of two independently
        // GCD-queued `DispatchQueue.main.async` blocks competing with
        // SwiftUI's own internal update scheduling is not something either
        // system's public contract guarantees, and this repo could not
        // resolve it empirically (see that same sink comment). The actual
        // fix for the race is on the OTHER end: the `$isOpen` sink re-checks
        // the LIVE `isOpen` value before dismissing, instead of trusting a
        // possibly-stale emitted one, which makes the outcome correct
        // regardless of which block runs first. This deferral is kept as
        // belt-and-braces — it still avoids doing the open/install work
        // inside the same call stack as the `.willPresent` post — but is
        // NOT the mechanism that makes this race-safe; do not treat it as
        // load-bearing on its own.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let request = SessionComposerRequest(presentation: .centered, projectBinding: projectBinding)
            self.composerOverlayHostingView.rootView = AnyView(
                SessionComposerOverlay(request: request, centeringModel: self.composerCenteringModel)
                    .environmentObject(WorkspaceStore.shared)
                    .environmentObject(self.coordinator)
            )

            // F4 (Phase 3 review): OBSERVED, not assumed — a scratch probe
            // (NSHostingView, remove+re-add vs. rootView-reassign-only) showed
            // `onAppear` reliably re-fires on a genuine remove+re-add of the
            // hosting view, but does NOT re-fire when `rootView` is merely
            // reassigned while the subview stays installed. That second case
            // is exactly "Cmd+T while the overlay is already open"
            // (`installComposerOverlayIfNeeded()` below is a no-op then), so
            // `SessionComposerPalette.onAppear`'s call to
            // `SessionComposerStore.open(...)` is not a reliable signal for
            // it. Call `open()` explicitly here instead — it's idempotent,
            // and when the store was already open this also sets
            // `focusSearchFieldTrigger`, so Cmd+T while open refocuses the
            // search field rather than doing nothing.
            SessionComposerStore.shared.open(projectBinding: projectBinding, workspaceStore: WorkspaceStore.shared)

            // F7 follow-up: correct even if the composer opens while
            // already fullscreen, not just on a later enter/exit transition.
            let isFullScreen = self.window?.styleMask.contains(.fullScreen) ?? false
            self.composerCenteringModel.titlebarBandHeight = isFullScreen ? 0 : WorkspaceLayout.titlebarSpacerHeight
            self.installComposerOverlayIfNeeded()
        }
    }

    private lazy var composerCenteringModel = ComposerCenteringModel()

    /// Guards the fade-out `removeFromSuperview()` in
    /// `dismissComposerOverlayIfPresented()` against a fast re-open
    /// (Escape immediately followed by Cmd+T) — bumped on every
    /// install/dismiss call so a dismiss's deferred completion handler can
    /// detect it was superseded and skip yanking the freshly re-presented
    /// overlay back out mid-animation.
    private var composerOverlayTransitionGeneration = 0

    /// Adds the composer overlay hosting view as a subview, pinned to the
    /// container's full bounds — not `layout()` — so its dismiss layer can
    /// span the whole terminal. Fades in (F8, Phase 3 review) to match every other
    /// appear-over-content transition in this container (`transitionTo(_:)`'s
    /// 0.2s convention). If the view is still attached (e.g. mid a dismiss
    /// fade-out that this call is interrupting), just animates it back to
    /// fully visible instead of re-adding it.
    private func installComposerOverlayIfNeeded() {
        composerOverlayTransitionGeneration += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // R3 (Phase 3 review round 2): re-enable hit-testing on (re-)present
        // — a fast dismiss-then-reopen can land here while a previous
        // dismiss's fade-out (see below) had it disabled.
        composerOverlayHostingView.isHitTestDisabled = false
        // R9 (Phase 3 review round 2): hide the sidebar and terminal from
        // VoiceOver navigation while the overlay is up. `NSView` conforms to
        // `NSAccessibilityProtocol` and exposes `setAccessibilityHidden(_:)`
        // directly — SwiftUI's `.accessibilityAddTraits(.isModal)` would be
        // a no-op here (the sidebar/terminal are separate `NSView`s in a
        // different hosting tree, so `.isModal` has nothing to hide),
        // confirmed by this round's reviewer, not "fixed" with it.
        //
        // Blocker 2 (Phase 3 review round 3): moved ABOVE the early-return
        // guard below, matching `isHitTestDisabled` right above — both must
        // apply on the "already installed, just re-animate to visible" path
        // too (Escape immediately followed by Cmd+T, landing inside the
        // fade window), or the sidebar/terminal are left VoiceOver-navigable
        // behind a live modal with no correction. Restored unconditionally
        // in `dismissComposerOverlayIfPresented()`, matching this call site.
        sidebarHostingView.setAccessibilityHidden(true)
        terminalShadowHost.setAccessibilityHidden(true)

        guard composerOverlayHostingView.superview == nil else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0 : 0.2
                composerOverlayHostingView.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                // Blocker 2: the early-return path used to skip this
                // entirely, so VO focus never moved into the composer on a
                // fast re-present even though it was visible on screen again.
                self?.postComposerLayoutChanged()
            })
            return
        }

        composerOverlayHostingView.alphaValue = 0
        addSubview(composerOverlayHostingView)
        NSLayoutConstraint.activate([
            composerOverlayHostingView.topAnchor.constraint(equalTo: topAnchor),
            composerOverlayHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            composerOverlayHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            composerOverlayHostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.2
            composerOverlayHostingView.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.postComposerLayoutChanged()
        })
    }

    /// R9/F10 (Phase 3 review round 2, deduplicated in round 3 — both
    /// `installComposerOverlayIfNeeded()` branches need it now, Blocker 2):
    /// posting `.layoutChanged` before the fade-in and before SwiftUI has
    /// laid out the reassigned `rootView` announced a change without moving
    /// VO focus into the new content (no `NSAccessibilityUIElementsKey`) —
    /// deferred to the fade-in's completion, with the hosting view itself
    /// as the target element so VO actually moves there.
    private func postComposerLayoutChanged() {
        NSAccessibility.post(
            element: composerOverlayHostingView,
            notification: .layoutChanged,
            userInfo: [.uiElements: [composerOverlayHostingView as Any]]
        )
    }

    /// Removes the composer overlay hosting view. No-op if not installed.
    /// Fades out (F8) to match `installComposerOverlayIfNeeded()`'s fade-in,
    /// and restores first responder to the focused terminal surface
    /// immediately (F3, Phase 3 review) — `removeFromSuperview()` alone
    /// hands first responder back to the WINDOW, not the terminal, the same
    /// failure mode already solved for the command palette
    /// (`TerminalCommandPaletteView.onChange(of: isPresented)`) and inline
    /// tab-title editing (`TerminalWindow.tabTitleEditor(_:didFinishEditing:)`).
    /// Without this, Escape (or any other dismiss) leaves the terminal
    /// keyboard-dead until the user clicks it.
    private func dismissComposerOverlayIfPresented() {
        guard composerOverlayHostingView.superview != nil else { return }

        // Blocker 3 (Phase 3 review round 3): clear ownership if this
        // window was the owner, so the next `presentComposerOverlay` call
        // (from any window) doesn't think a dismissed overlay is still live
        // elsewhere.
        if SessionComposerStore.shared.owningWindow === window {
            SessionComposerStore.shared.owningWindow = nil
        }

        // R3 (Phase 3 review round 2): disable hit-testing FIRST, before the
        // fade starts — `NSView.hitTest(_:)` skips HIDDEN views but does not
        // consider `alphaValue`, so without this the full-bounds scrim stays
        // fully clickable for the entire 0.2s fade-out. A click into the
        // terminal to resume typing during that window would otherwise land
        // on the invisible scrim's `.onTapGesture { cancel() }` (eating the
        // click and re-entering dismiss, extending the dead window), and a
        // fast double-click on a template row could fire `commit()` twice —
        // `ComposerRow`'s `Button(action:)` calls `option.action()` directly
        // and never reads `selectedIndex`, so the keyboard path's
        // double-Return guard doesn't cover it.
        composerOverlayHostingView.isHitTestDisabled = true

        // R9 (Phase 3 review round 2): restore VoiceOver navigation into the
        // sidebar and terminal — the counterpart to the hide in
        // `installComposerOverlayIfNeeded()`.
        sidebarHostingView.setAccessibilityHidden(false)
        terminalShadowHost.setAccessibilityHidden(false)

        // R4 (Phase 3 review round 2): only steal first responder back to
        // the terminal if THIS window is actually key. `makeFirstResponder`
        // doesn't steal key across windows, but `windowDidResignKey` calls
        // this too — without the guard, every resign-key with the composer
        // open would call `makeFirstResponder` on a window that just lost
        // key status, which (via `BaseTerminalController`'s window-delegate
        // `syncFocusToSurfaceTree()`, wired at nib-load and so running
        // BEFORE this container's later `viewDidMoveToWindow` registration)
        // re-sets `ghostty_surface_set_focus(surface, true)` on a non-key
        // window: a blinking cursor in an inactive window, `SecureInput`
        // scoped active while the app is inactive, and — with DECSET 1004
        // (Claude Code's TUI, vim, tmux) — an inverted pty focus report that
        // never self-corrects, because `SurfaceView_AppKit.focusDidChange`
        // early-returns when `self.focused` already matches on the way back.
        if window?.isKeyWindow == true,
           let controller = window?.windowController as? BaseTerminalController,
           let focusedSurface = controller.focusedSurface {
            window?.makeFirstResponder(focusedSurface)
        }

        composerOverlayTransitionGeneration += 1
        let myGeneration = composerOverlayTransitionGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.2
            composerOverlayHostingView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.composerOverlayTransitionGeneration == myGeneration else { return }
            self.composerOverlayHostingView.removeFromSuperview()
        })
    }

    /// Instant session creation — Cmd+Shift+T (always) and Cmd+T when the
    /// `ghostties.newSessionOpensComposer` preference is off. Resolves the
    /// same smart-default cascade the composer uses, then creates directly
    /// with the project's default template (falling back to `.shell`), with
    /// no UI. Mirrors the deleted
    /// `WorkspaceSidebarView.createNewSessionForSelectedProject()`, but uses
    /// the cascade pick instead of the sidebar's `selectedProjectId`.
    private func instantCreateSession() {
        let store = WorkspaceStore.shared
        guard let projectId = SessionComposerStore.shared.resolveCascadeProject(workspaceStore: store),
              let project = store.projects.first(where: { $0.id == projectId }) else { return }

        let template: AgentTemplate
        if let defaultId = project.defaultTemplateId,
           let defaultTemplate = store.templates.first(where: { $0.id == defaultId }) {
            template = defaultTemplate
        } else {
            template = AgentTemplate.shell
        }

        // F1 (Phase 3 review): without this, a session created via the
        // cascade pick into a collapsed project spawns with no visible
        // sidebar row — see `WorkspaceLayout.workspaceDidCreateSessionInProject`.
        NotificationCenter.default.post(
            name: .workspaceDidCreateSessionInProject,
            object: window,
            userInfo: ["projectId": project.id]
        )

        Task {
            await coordinator.createQuickSession(for: project, template: template)
        }
    }

    // MARK: - Layout

    private func setup() {
        // Canvas layer — the warm background visible behind the floating card.
        wantsLayer = true

        // Z-order: background material → overlay background → sidebar → sidebar drag handle → terminal → browser drag handle → browser → build-info badge (topmost).
        addSubview(backgroundEffectView)
        addSubview(sidebarOverlayBackground)
        addSubview(sidebarHostingView)
        addSubview(sidebarDragHandle)
        addSubview(terminalShadowHost)
        addSubview(browserDragHandle)
        addSubview(browserShadowHost)
        addSubview(buildInfoBadgeHostingView)

        sidebarHostingView.translatesAutoresizingMaskIntoConstraints = false

        // Enable layers for z-ordering in overlay mode.
        sidebarHostingView.wantsLayer = true
        sidebarOverlayBackground.wantsLayer = true
        sidebarOverlayBackground.layer?.shadowColor = NSColor.black.cgColor
        sidebarOverlayBackground.layer?.shadowRadius = 6
        sidebarOverlayBackground.layer?.shadowOffset = CGSize(width: 2, height: 0)

        // Terminal lives inside the shadow host. The host carries the shadow;
        // the terminal clips its own corners via masksToBounds.
        terminalShadowHost.addSubview(terminalContainer)
        terminalShadowHost.addSubview(titleLabel)
        terminalShadowHost.addSubview(sidebarToggleButton)
        terminalShadowHost.addSubview(browserToggleButton)
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false

        // Browser panel lives inside browser shadow host.
        browserPanelView.translatesAutoresizingMaskIntoConstraints = false
        browserShadowHost.addSubview(browserPanelView)

        // Read persisted sidebar mode.
        let initialMode = WorkspaceStore.shared.sidebarMode
        self.sidebarMode = initialMode
        let isPinned = initialMode == .pinned
        // All three modes show the floating card with insets — overlay floats
        // the sidebar over the same carded terminal rather than a full-bleed one.
        let hasCardInset = true
        let initialWidth: CGFloat = isPinned ? currentSidebarWidth : 0
        sidebarDragHandle.isHidden = !isPinned

        sidebarWidthConstraint = sidebarHostingView.widthAnchor.constraint(equalToConstant: initialWidth)

        let inset: CGFloat = hasCardInset ? WorkspaceLayout.terminalInset : 0
        // Inset constraints target the shadow host, not the terminal directly.
        shadowHostTopConstraint = terminalShadowHost.topAnchor.constraint(
            equalTo: topAnchor, constant: inset)
        // Terminal trailing to window edge (active when browser is hidden).
        shadowHostTrailingConstraint = terminalShadowHost.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: hasCardInset ? -inset : 0)
        shadowHostBottomConstraint = terminalShadowHost.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: hasCardInset ? -inset : 0)

        // Terminal trailing to browser leading (active when browser is visible).
        shadowHostTrailingToBrowser = terminalShadowHost.trailingAnchor.constraint(
            equalTo: browserShadowHost.leadingAnchor, constant: -inset)
        shadowHostTrailingToBrowser.isActive = false

        // Browser shadow host constraints — starts hidden (width 0, alpha 0).
        browserWidthConstraint = browserShadowHost.widthAnchor.constraint(equalToConstant: 0)
        browserShadowHostTopConstraint = browserShadowHost.topAnchor.constraint(
            equalTo: topAnchor, constant: inset)
        browserShadowHostBottomConstraint = browserShadowHost.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: hasCardInset ? -inset : 0)
        browserShadowHostTrailingConstraint = browserShadowHost.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: hasCardInset ? -inset : 0)

        // Dual leading constraints (mutually exclusive).
        shadowHostLeadingToSidebar = terminalShadowHost.leadingAnchor.constraint(
            equalTo: sidebarHostingView.trailingAnchor, constant: inset)
        shadowHostLeadingToSuperview = terminalShadowHost.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: hasCardInset ? inset : 0)
        shadowHostLeadingToSidebar.isActive = isPinned
        shadowHostLeadingToSuperview.isActive = !isPinned

        // Terminal top offset inside the shadow host — reserves title bar space
        // when pinned or closed (those two card modes show title + toggle
        // button). Overlay is carded now too, but keeps its title row hidden
        // (unchanged from before this pass), so it's keyed on mode, not
        // `hasCardInset`.
        let titlebarInset: CGFloat = initialMode != .overlay ? WorkspaceLayout.terminalTitleBarHeight : 0
        terminalTopConstraint = terminalContainer.topAnchor.constraint(
            equalTo: terminalShadowHost.topAnchor, constant: titlebarInset)

        // 22 is the initial guess before the window appears (breathingRoomBelowChrome is now 0);
        // updated each layout() pass from the live close-button frame.
        sidebarToggleCenterYConstraint = sidebarToggleButton.centerYAnchor
            .constraint(equalTo: topAnchor, constant: 22)

        NSLayoutConstraint.activate([
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: sidebarHostingView.trailingAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Overlay background tracks sidebar width via trailing edge.
            sidebarOverlayBackground.topAnchor.constraint(equalTo: topAnchor),
            sidebarOverlayBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarOverlayBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarOverlayBackground.trailingAnchor.constraint(equalTo: sidebarHostingView.trailingAnchor),

            sidebarHostingView.topAnchor.constraint(equalTo: topAnchor),
            sidebarHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarHostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarWidthConstraint,

            shadowHostTopConstraint,
            shadowHostBottomConstraint,
            shadowHostTrailingConstraint,

            // Terminal fills the shadow host (top offset reserves title bar space).
            terminalTopConstraint,
            terminalContainer.leadingAnchor.constraint(equalTo: terminalShadowHost.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: terminalShadowHost.trailingAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: terminalShadowHost.bottomAnchor),

            // Sidebar toggle button — anchored to window top, not the terminal card.
            // The terminal card (terminalShadowHost) sits ~387pt below the window top in the
            // full layout, so terminalShadowHost.topAnchor is the wrong reference. Anchor
            // directly to self.topAnchor + constant so the toggle sits on the same horizontal
            // row as the traffic lights. The constant is updated from the live close-button
            // frame in layout() — 22 is just the initial guess before the window appears.
            sidebarToggleButton.leadingAnchor.constraint(
                equalTo: terminalShadowHost.leadingAnchor, constant: 8),
            sidebarToggleCenterYConstraint,

            // Browser toggle button at top-right of the terminal card titlebar.
            browserToggleButton.trailingAnchor.constraint(
                equalTo: terminalShadowHost.trailingAnchor, constant: -8),
            browserToggleButton.centerYAnchor.constraint(
                equalTo: sidebarToggleButton.centerYAnchor),

            // Title label centered in the titlebar region, vertically aligned
            // with the sidebar toggle button.
            titleLabel.centerXAnchor.constraint(equalTo: terminalShadowHost.centerXAnchor),
            titleLabel.centerYAnchor.constraint(
                equalTo: sidebarToggleButton.centerYAnchor),

            // Browser shadow host — positioned to the right of the terminal.
            browserShadowHostTopConstraint,
            browserShadowHostBottomConstraint,
            browserShadowHostTrailingConstraint,
            browserWidthConstraint,

            // Browser panel fills its shadow host.
            browserPanelView.topAnchor.constraint(equalTo: browserShadowHost.topAnchor),
            browserPanelView.leadingAnchor.constraint(equalTo: browserShadowHost.leadingAnchor),
            browserPanelView.trailingAnchor.constraint(equalTo: browserShadowHost.trailingAnchor),
            browserPanelView.bottomAnchor.constraint(equalTo: browserShadowHost.bottomAnchor),

            // Drag handle sits in the 8pt gap between terminal and browser.
            browserDragHandle.topAnchor.constraint(equalTo: terminalShadowHost.topAnchor),
            browserDragHandle.bottomAnchor.constraint(equalTo: terminalShadowHost.bottomAnchor),
            browserDragHandle.leadingAnchor.constraint(equalTo: terminalShadowHost.trailingAnchor),
            browserDragHandle.trailingAnchor.constraint(equalTo: browserShadowHost.leadingAnchor),

            // Sidebar drag handle sits in the 8pt gap between sidebar and terminal
            // (same gap the shadowHostLeadingToSidebar inset constant reserves).
            // In overlay mode `shadowHostLeadingToSuperview` is active instead, so
            // this leading/trailing pair can resolve to a hidden negative-width
            // frame — harmless, since the handle is hidden in overlay mode anyway.
            sidebarDragHandle.topAnchor.constraint(equalTo: sidebarHostingView.topAnchor),
            sidebarDragHandle.bottomAnchor.constraint(equalTo: sidebarHostingView.bottomAnchor),
            sidebarDragHandle.leadingAnchor.constraint(equalTo: sidebarHostingView.trailingAnchor),
            sidebarDragHandle.trailingAnchor.constraint(equalTo: terminalShadowHost.leadingAnchor),

            // Build-info badge: bottom-left corner of the whole window, on top
            // of sidebar and terminal alike. Unconstrained width/height — the
            // hosting view sizes to its SwiftUI content (`.fixedSize()`).
            buildInfoBadgeHostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            buildInfoBadgeHostingView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // Terminal floating card: top corners rounded when in card mode (pinned/closed).
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.cornerRadius = hasCardInset ? WorkspaceLayout.terminalCornerRadius : 0
        terminalContainer.layer?.cornerCurve = .continuous
        terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        terminalContainer.layer?.masksToBounds = true

        // Configure shadow on the host layer. Must happen after addSubview so the
        // layer exists (wantsLayer in a property closure may not create it in time).
        terminalShadowHost.wantsLayer = true
        terminalShadowHost.layer?.shadowColor = WorkspaceLayout.canvasShadowColor
        terminalShadowHost.layer?.shadowOpacity = hasCardInset ? WorkspaceLayout.canvasShadowOpacity : 0
        terminalShadowHost.layer?.shadowRadius = WorkspaceLayout.canvasShadowRadius
        terminalShadowHost.layer?.shadowOffset = WorkspaceLayout.canvasShadowOffset

        // Card background behind the title bar region. No masksToBounds — shadow
        // must render outside the layer bounds.
        terminalShadowHost.layer?.cornerRadius = hasCardInset ? WorkspaceLayout.terminalCornerRadius : 0
        terminalShadowHost.layer?.cornerCurve = .continuous
        terminalShadowHost.layer?.backgroundColor = hasCardInset ? cardBackgroundCGColor : nil

        // Browser shadow host — identical layer config to terminal shadow host.
        browserShadowHost.wantsLayer = true
        browserShadowHost.layer?.shadowColor = WorkspaceLayout.canvasShadowColor
        browserShadowHost.layer?.shadowOpacity = 0  // hidden initially
        browserShadowHost.layer?.shadowRadius = WorkspaceLayout.canvasShadowRadius
        browserShadowHost.layer?.shadowOffset = WorkspaceLayout.canvasShadowOffset
        browserShadowHost.layer?.cornerRadius = hasCardInset ? WorkspaceLayout.terminalCornerRadius : 0
        browserShadowHost.layer?.cornerCurve = .continuous
        browserShadowHost.layer?.backgroundColor = hasCardInset ? browserCardBackgroundCGColor : nil
        browserShadowHost.layer?.masksToBounds = false
        browserShadowHost.alphaValue = 0  // hidden initially

        // Canvas background — visible behind the floating card in pinned and closed modes.
        layer?.backgroundColor = hasCardInset ? canvasBackgroundCGColor : nil

        // Background material is only visible in overlay (floating hover) mode.
        // In pinned mode the sidebar is transparent; in closed mode it's hidden entirely.
        backgroundEffectView.isHidden = true
        if initialMode == .closed {
            sidebarHostingView.alphaValue = 0
        } else if initialMode == .overlay {
            titleLabel.alphaValue = 0
            sidebarToggleButton.alphaValue = 0
            browserToggleButton.alphaValue = 0
        }

        // Dismiss the composer overlay's hosting view whenever the composer
        // store closes (Esc, scrim click, or a successful commit) — every
        // close path funnels through `SessionComposerStore.isOpen`, so this
        // is the single place the subview teardown needs to live (Phase 3).
        //
        // F9 (Phase 3 review) — LOAD-BEARING DEPENDENCY: this sink only
        // fires reliably because `@Published` re-emits `willSet` on every
        // assignment, even one that doesn't change the value. `cancel()`
        // sets `isOpen = false` unconditionally, including when it's
        // already `false` — if `isOpen`'s setter ever grows an equality
        // guard (`didSet`-style "optimization" to skip redundant publishes),
        // a cancel that lands while `isOpen` is already `false` would
        // silently stop reaching this sink — the subview would stay
        // installed until the next `applicationDidResignActive()` (app
        // deactivation) or the next cross-window takeover in
        // `presentComposerOverlay` (the other two dismiss paths, as of
        // Blocker 3 below — `windowDidResignKey` no longer dismisses the
        // composer at all) rather than closing when the user actually
        // asked. Do not add that guard.
        //
        // Blocker 1 (Phase 3 review round 3): `.receive(on: DispatchQueue.main)`
        // is ALWAYS an async hop for Combine's `DispatchQueue` scheduler —
        // it never runs inline even when already on the main thread — so
        // this closure acts on a value EMITTED at some earlier moment, not
        // necessarily the CURRENT one. `presentComposerOverlay`'s deferred
        // install (see its own comment) races a dismiss enqueued by a
        // teardown `cancel()` from the popover it's replacing; which of the
        // two GCD-queued blocks actually runs first is not something either
        // Combine's public contract or SwiftUI's internal update scheduling
        // guarantees — SwiftUI doesn't document whether a state-driven
        // `onChange`/`onDisappear` fires synchronously within the same call
        // stack as the mutation that triggers it, or is deferred to a later
        // run-loop pass relative to a plain `DispatchQueue.main.async` block,
        // and this was not resolved empirically (a scratch popover-teardown
        // probe was inconclusive — the popover never actually presented in
        // a headless test process). Re-reading the LIVE value here instead
        // of trusting the emitted one makes the outcome ordering-independent:
        // if a stale `false` is processed after `presentComposerOverlay`
        // already reopened the store, this now no-ops instead of tearing
        // the fresh overlay back down.
        //
        // FRAGILITY (Phase 3 review round 4) — `.receive(on: DispatchQueue.main)`
        // below is NOT decorative; the live re-read above depends on it.
        // `@Published` emits in `willSet`, i.e. BEFORE the stored property
        // is actually updated — the closure below only sees the post-write
        // value because the scheduler's async hop guarantees this closure
        // runs strictly after the assignment that triggered it has already
        // landed. Remove `.receive(on:)` as a "simplification" and this
        // sink would run synchronously from within `willSet`, so
        // `!SessionComposerStore.shared.isOpen` would read the PRE-`willSet`
        // value (`true`, the value being replaced, not the `false` being
        // set) — the guard above would then always fail, and every dismiss
        // (scrim click, Escape, everything routed through `cancel()`) would
        // die silently. Keep the hop.
        SessionComposerStore.shared.$isOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !SessionComposerStore.shared.isOpen else { return }
                // Blocker 3 (Phase 3 review round 3): only the window that
                // currently owns the composer acts on a dismiss signal —
                // otherwise a `cancel()` triggered by window B's activity
                // (or a stale emission) could tear down window A's
                // unrelated, still-open overlay. `dismissComposerOverlayIfPresented()`
                // already self-guards on `superview != nil`, so this is
                // largely redundant defense-in-depth, but explicit rather
                // than relying on that guard alone to keep this correct.
                guard SessionComposerStore.shared.owningWindow == nil
                    || SessionComposerStore.shared.owningWindow === self.window
                else { return }
                self.dismissComposerOverlayIfPresented()
            }
            .store(in: &cancellables)

        // Bind title label to the active session name.
        coordinator.$activeSessionId
            .combineLatest(WorkspaceStore.shared.$sessions)
            .map { activeId, sessions -> String in
                guard let id = activeId,
                      let session = sessions.first(where: { $0.id == id })
                else { return "" }
                return session.name
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.titleLabel.stringValue = name
            }
            .store(in: &cancellables)

        // Bind the terminal card background to the focused surface's theme so
        // the chrome matches the terminal instead of the hardcoded palette.
        // Mirrors TerminalWindow.syncAppearance() — same "focused surface drives
        // window color" rule, applied to our card instead of the window itself.
        coordinator.$activeSessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebindFocusedSurfaceTheme()
            }
            .store(in: &cancellables)
        // Initial bind so we pick up whatever surface exists at launch before
        // the publisher fires.
        rebindFocusedSurfaceTheme()
    }

    // MARK: - Focused Surface Theme Binding

    /// Resubscribe to the focused surface's `$derivedConfig` whenever the
    /// active session changes. Cancels any prior subscription, looks up the
    /// new focused surface via the terminal controller, and both applies the
    /// current theme color immediately and listens for future theme updates
    /// (e.g. user edits config, OS appearance swap flips the auto-theme).
    private func rebindFocusedSurfaceTheme() {
        observedSurfaceCancellables.removeAll()

        let surface = focusedSurfaceForActiveSession()
        observedSurface = surface

        // Apply immediately so the card doesn't wait for the next publisher
        // emission. Skip the repaint in overlay mode where the card is hidden
        // and its background was explicitly cleared.
        applyChromeColor()

        guard let surface else { return }

        surface.$derivedConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak surface] _ in
                // Guard: only repaint if this surface is still the one we're
                // observing. A stale emission from a replaced surface would
                // otherwise overwrite the new theme.
                guard let self, let surface, self.observedSurface === surface
                else { return }
                self.applyChromeColor()
            }
            .store(in: &observedSurfaceCancellables)
    }

    /// Look up the focused surface for the currently active session, falling
    /// back to the session tree's first surface when the controller doesn't
    /// yet have a focused surface (e.g. right after session creation).
    /// Returns nil for browser sessions or when no session is active.
    private func focusedSurfaceForActiveSession() -> Ghostty.SurfaceView? {
        guard let activeId = coordinator.activeSessionId else { return nil }
        // Browser sessions have no surface (and no theme).
        if coordinator.browserManagers[activeId] != nil { return nil }
        // Prefer the controller's live focused surface — that's what
        // TerminalWindow.syncAppearance uses too, so our chrome stays aligned
        // with the window background even when the user moves focus across
        // splits within the same session.
        if let controller = window?.windowController as? BaseTerminalController,
           let focused = controller.focusedSurface {
            return focused
        }
        // Fall back to the first surface in the stored tree.
        return coordinator.sessionTrees[activeId]?.first
    }

    /// Repaint the chrome and canvas layers with the current Ghostties design-
    /// system palette (static, not theme-bound). The card + browser use the
    /// canvas tone; the outer layer uses the chrome tone. The focused-surface
    /// Combine subscription still drives this on session swaps and config
    /// changes — after the theme-unbind refactor it's effectively a no-op
    /// repaint with static tokens, but left in place to preserve the
    /// session-swap invalidation path with minimal churn.
    ///
    /// No-op in overlay mode, which intentionally clears all layers to let
    /// the vibrancy material show through.
    private func applyChromeColor() {
        guard sidebarMode == .pinned || sidebarMode == .closed else { return }
        terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
        browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
        layer?.backgroundColor = canvasBackgroundCGColor
    }
}

// MARK: - Browser URL Field Delegate

extension WorkspaceViewContainer: NSTextFieldDelegate {
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        true
    }

    /// Handle Enter key in the browser URL field.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            guard let field = control as? NSTextField else { return false }
            var urlString = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty else { return true }

            // Add https:// if no scheme present.
            if !urlString.contains("://") {
                urlString = "https://\(urlString)"
            }

            // Only allow http, https, and about schemes.
            let lower = urlString.lowercased()
            guard lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("about:") else {
                NSLog("[WorkspaceViewContainer] Blocked URL with disallowed scheme: %@", urlString)
                return true
            }

            activeCEFView?.loadURL(urlString)
            // Resign first responder so keyboard goes back to the browser.
            field.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}

// MARK: - Transparent Hosting View

/// NSHostingView subclass that doesn't draw the default window background.
/// Used for the sidebar so it's transparent in pinned mode — the window
/// background shows through. The overlay NSVisualEffectView provides
/// material only in hover mode.
///
/// Internal (not `private`) since Phase 3 of session-creation-unified hosts
/// the session composer overlay through it too — kept in this file rather
/// than moved, so the composer overlay's own view code stays out of this
/// 85 KB file.
class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    /// When `true`, this view (and everything inside it) is excluded from
    /// hit-testing even though it's still on screen (R3, Phase 3 review
    /// round 2). `NSView.hitTest(_:)` skips HIDDEN views but does not
    /// consider `alphaValue` — a view fading out via `.animator().alphaValue`
    /// stays fully clickable for the whole animation unless something like
    /// this exists. Opt-in and off by default so the sidebar's own use of
    /// this class (which doesn't fade the same way) is unaffected.
    var isHitTestDisabled = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHitTestDisabled ? nil : super.hitTest(point)
    }
}

// MARK: - Panel Drag Handle

/// Invisible drag handle used for both the terminal/browser divider and the
/// sidebar/terminal divider. Changes the cursor to a left-right resize arrow
/// on hover and reports horizontal drag deltas via the `onDrag` closure.
private class PanelDragHandleView: NSView {
    /// Called during mouseDragged with the horizontal delta (positive = rightward).
    var onDrag: ((CGFloat) -> Void)?

    /// Called on mouseUp, after the drag ends. Used by the sidebar handle to
    /// persist the final width; unused (nil) by the browser handle.
    var onDragEnd: (() -> Void)?

    /// Track the last mouse X position during a drag.
    private var lastDragX: CGFloat = 0

    /// Tracking area for cursor changes on hover.
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Transparent — the handle is invisible but responds to mouse events.
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let area = hoverTrackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastDragX
        lastDragX = currentX
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}
