import AppKit
import Combine
import SwiftUI
import GhosttiesCore

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

    /// The sidebar ⇄ rail morph's progress: 0 = the expanded sidebar, 1 =
    /// the rail (`SidebarMorphMetrics`). `WorkspaceViewContainer.transitionTo`
    /// writes it, with `width`, inside ONE `withAnimation` on the panel's
    /// curve, so every leaf that reads it (tile, chip, glyph, card, header
    /// height) interpolates on the same frames as the AppKit width.
    /// `applyMorphStep` holds it at any value in between, un-animated.
    @Published var morph: CGFloat

    /// The sidebar's width when expanded (the pinned width, dragged or
    /// clamped). The one tree is laid out at this width at every step of
    /// the morph (`SidebarMorphFrame`); `width` only clips it.
    @Published var expandedWidth: CGFloat

    /// True while a pinned ⇄ rail transition is in flight: rows and headers
    /// take no clicks, drags or drops until it lands.
    @Published var isMorphing = false

    /// True while the rail's hover reveal has the full sidebar out
    /// (`RailHoverReveal`), pushed or over the terminal. Rows show no hover
    /// card then: the reveal is transient, and the card would sit outside it.
    @Published var isOverlaid = false

    /// Flow 05 content choreography (sidebar-presence): which "presentation"
    /// the pinned⇄collapsed row content should render toward — `true` once a
    /// collapse has landed/is landing, `false` once an expand has
    /// landed/is landing. Derived from `morph`. Read unconditionally by
    /// `RecentsRowView` (injected into every sidebar content tree, not just
    /// the transitional one) so steady-state rendering (not mid-transition)
    /// still resolves to the correct static appearance for whichever mode is
    /// settled.
    var isCollapsedPresentation: Bool { morph >= 0.5 }

    /// The collapsed rail's width (`WorkspaceLayout.collapsedRailWidth(in:)`),
    /// kept current in every mode, not only while collapsed. The rail tray
    /// sizes its square pills from it (`RailTrayGeometry`), so it must hold
    /// the rail's width before a collapse starts: `width` reaches the rail
    /// only after `isCollapsedPresentation` has already flipped the tray
    /// vertical, and animates through every width on the way.
    @Published var railWidth: CGFloat = WorkspaceLayout.sidebarRailWidth

    init(width: CGFloat, morph: CGFloat = 0, expandedWidth: CGFloat? = nil) {
        self.width = width
        self.morph = morph
        self.expandedWidth = expandedWidth ?? width
    }
}

/// The sidebar ⇄ rail morph's one clock: the width the spring is driving
/// (`SidebarMotionDriver`).
///
/// AppKit and SwiftUI would each start a clock of their own, and neither
/// can be told when (15–45ms apart, measured), which put the card's edge up
/// to 90pt off the panel's. So the morph plays on the width constraint
/// alone: `SidebarMorphClockAnimation` reads this progress on every frame
/// SwiftUI renders, overshoot included, and lands when the spring settles.
///
/// Progress is measured from `from`, the morph's previous target, not from
/// where the constraint is: SwiftUI plays a new transaction from the old
/// model value, so on a reversal mid-flight (from = the old target) the
/// SwiftUI side starts exactly where the constraint is, with no jump.
@MainActor
final class SidebarMorphClock: Hashable {
    private weak var constraint: NSLayoutConstraint?
    private let from: CGFloat
    private let to: CGFloat
    private var landed = false

    init(constraint: NSLayoutConstraint, from: CGFloat, to: CGFloat) {
        self.constraint = constraint
        self.from = from
        self.to = to
    }

    /// 0 at `from`, 1 at the target, past 1 on an overshoot; nil once
    /// landed.
    var progress: Double? {
        guard !landed, let constraint, from != to else { return nil }
        return Double((constraint.constant - from) / (to - from))
    }

    /// The spring settled, or a newer toggle took over.
    func land() { landed = true }

    nonisolated static func == (lhs: SidebarMorphClock, rhs: SidebarMorphClock) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Plays a SwiftUI transaction at `SidebarMorphClock`'s progress.
@available(macOS 14, *)
struct SidebarMorphClockAnimation: CustomAnimation {
    let clock: SidebarMorphClock

    func animate<V: VectorArithmetic>(value: V, time _: TimeInterval, context _: inout AnimationContext<V>) -> V? {
        guard let progress = MainActor.assumeIsolated({ clock.progress }) else { return nil }
        return value.scaled(by: progress)
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

/// Flow 05 (sidebar-presence) transitional content: cross-fades between the
/// full sidebar content and the collapsed rail, both mounted at once, driven
/// by `model.isCollapsedPresentation`. `@ObservedObject`, same pattern as
/// `SidebarWidthFrame` above — this is the ONE view in the pair that
/// re-evaluates `body` when the model publishes, so the opacity values below
/// are a live binding, not a value snapshotted once at construction time (the
/// mistake this struct exists to avoid: reading `model.isCollapsedPresentation`
/// directly inside `WorkspaceViewContainer.applyCollapseCrossfadeSidebarView`,
/// a plain function, would bake a STATIC opacity into the view graph that
/// never updates on a later `withAnimation` write).
private struct SidebarCollapseCrossfade: View {
    @ObservedObject var model: SidebarWidthModel
    let full: AnyView
    let rail: AnyView

    var body: some View {
        ZStack {
            full.opacity(model.isCollapsedPresentation ? 0 : 1)
            rail.opacity(model.isCollapsedPresentation ? 1 : 0)
        }
    }
}

/// The sidebar hosting view's one root type, in every mode. Only `content`
/// swaps (expanded list, rail, or the Flow 05 cross-fade of both); the tray
/// sits outside it, so `SidebarTray` keeps its identity across those swaps
/// and morphs between its horizontal bar and vertical pill instead of being
/// torn down with one tree and rebuilt with the other. `NSHostingView` keeps
/// the subtree when the new `rootView` wraps the same type.
private struct SidebarHostRoot: View {
    @ObservedObject var model: SidebarWidthModel
    @EnvironmentObject private var store: WorkspaceStore
    let content: AnyView
    /// The tray's axis in a settled mode (`true` = the rail's vertical pill).
    /// `nil` while the pinned⇄collapsed transition is hosted: the axis then
    /// follows `model.isCollapsedPresentation`, which `transitionTo` flips
    /// inside the same `withAnimation` as the content cross-fade, so the
    /// morph rides the Flow 05 curve and lands with the card's width.
    let trayIsVertical: Bool?
    /// False for the task-first view, which has no tray.
    let showsTrayWhenExpanded: Bool
    /// The mode this root was built for. Its
    /// `WorkspaceLayout.sidebarTrailingGutter(for:)` — read live, so the
    /// Window margin dial lands without a rebuild — is what the expanded
    /// list and tray leave out of their own trailing padding.
    let gutterMode: SidebarMode
    /// Re-renders on every dial write; see `SidebarDialTuning.epochKey`.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0

    var body: some View {
        let vertical = trayIsVertical ?? model.isCollapsedPresentation
        let trailingGutter = WorkspaceLayout.sidebarTrailingGutter(for: gutterMode)
        content
            // Leading: the sidebar's content is anchored at its leading
            // edge, so a sub-frame mismatch between the AppKit width and
            // `model.width` mid-morph moves nothing.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The group card measures from the sidebar's leading edge, not
            // the window's: they differ in overlay, where the column sits
            // the window margin in.
            .coordinateSpace(name: ProjectGroupCard.sidebarSpace)
            .overlay(alignment: .bottom) {
                if vertical || showsTrayWhenExpanded {
                    SidebarTray(isVertical: vertical, toggleLabel: toggleLabel, dialEpoch: SidebarDialTuning.epoch(), panelWidth: model.width)
                }
            }
            .environment(\.sidebarTrailingGutter, trailingGutter)
            .environment(\.sidebarRailWidth, model.railWidth)
            .environment(\.trayShadowState, SidebarDialTuning.TrayShadowState(store.sidebarMode))
    }

    /// "Collapse Sidebar" while pinned (the toggle flips full width ↔ rail),
    /// "Expand Sidebar" on the rail, "Open Sidebar" while overlaid — the
    /// overlay's toggle promotes it to pinned.
    private var toggleLabel: String {
        switch store.sidebarMode {
        case .collapsed: return "Expand Sidebar"
        case .overlay: return "Open Sidebar"
        default: return "Collapse Sidebar"
        }
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
/// The sidebar operates in four modes (see `SidebarMode`):
/// - **pinned**: Sidebar pushes terminal right (floating card with shadow/insets).
/// - **collapsed**: Icon-only rail hugging the traffic lights, same card treatment as pinned (Flow 01).
/// - **closed**: Sidebar hidden, terminal fills window flush, traffic lights hidden.
/// - **overlay**: Sidebar floats on top of full-width terminal (hover-to-reveal).
class WorkspaceViewContainer: NSView {
    /// Shadow host for the overlay panel (Flow 01, sidebar-presence §04). No
    /// fill of its own — `masksToBounds` stays false so its shadow isn't
    /// clipped — it exists purely to cast the rightward shadow behind
    /// `sidebarOverlayBackground`'s opaque, corner-clipped content. Named
    /// `backgroundEffectView` from its pre-Flow-01 role as an
    /// `NSVisualEffectView` blur; the reveal overlay is opaque now (supersedes
    /// DESIGN.md §4 "Overlay sidebar" — no background blur), so it's a plain
    /// `NSView`.
    private let backgroundEffectView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let sidebarHostingView: NSView
    /// Exposed for `BaseTerminalController.terminalViewContainer` to reach through.
    private(set) var terminalContainer: TerminalViewContainer
    private let coordinator: SessionCoordinator
    private let ghostty: Ghostty.App
    /// `WorkspaceStore.shared` in the app. Injectable so a test can host a
    /// real container on a persistence-disabled store — the shared one
    /// writes the Dev app's real `workspace.json`.
    private let store: WorkspaceStore

    #if DEBUG
    /// Test-only: the container's own coordinator, for seeding live surfaces.
    var coordinatorForTesting: SessionCoordinator { coordinator }
    /// The sidebar's mount and body counters (`MorphProbe`), read by the
    /// morph gates.
    let morphProbe = MorphProbe()
    var redlineRegistryForTesting: RedlineRegistry { redlineOverlay.registry }

    /// Holds the sidebar at one step of the sidebar ⇄ rail morph, with no
    /// animation: the AppKit width and the SwiftUI width at
    /// lerp(sidebar, rail, `progress`), and `widthModel.morph` at
    /// `progress`. The sidebar mode is left alone. Drives the morph gates
    /// and `GHOSTTIES_CAPTURE_MORPH_STEPS`.
    func applyMorphStep(_ progress: CGFloat) {
        cancelMorphMotion()
        let p = min(max(progress, 0), 1)
        isMorphStepHeld = true
        let width = SidebarMorphMetrics.lerp(widthModel.expandedWidth, WorkspaceLayout.collapsedRailWidth(in: self), p)
        sidebarWidthConstraint.constant = width
        widthModel.width = width
        widthModel.morph = p
        layoutSubtreeIfNeeded()
    }
    #endif

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

    #if DEBUG
    /// DEBUG Redlines overlay (`SidebarRedlines.swift`): spacing bands over
    /// the whole workspace, hidden unless the inspector's Redlines is on.
    private lazy var redlineOverlay = RedlineOverlayView(
        sidebarHost: sidebarHostingView,
        cardHost: terminalShadowHost,
        browserHost: browserShadowHost
    )
    #endif

    /// Diagnostic build/launch info badge — top-right corner of the window,
    /// just left of the DEBUG DialKit collapse pill,
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

    /// Hosting view for the history browser (mock I3), shown over the
    /// terminal inside the canvas card while
    /// `SessionCoordinator.isHistoryPresented` — see
    /// `applyHistoryPresentation()`. The terminal stays mounted underneath,
    /// so closing the browser returns to it untouched.
    private lazy var historyHostingView: NSHostingView<AnyView> = {
        let view = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.sizingOptions = []
        view.wantsLayer = true
        view.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
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
        #if DEBUG
        Self.newSessionOpensComposer(in: Self.composerPreferenceDefaults(fixtureActive: CaptureFixture.isActive))
        #else
        Self.newSessionOpensComposer(in: .standard)
        #endif
    }

    #if DEBUG
    /// Fixture mode reads the throwaway capture suite, never `.standard`.
    static func composerPreferenceDefaults(fixtureActive: Bool) -> UserDefaults {
        CaptureFixture.defaults(fixtureActive: fixtureActive)
    }

    /// Capture-script `pref` op. `nil` removes the key.
    static func setNewSessionOpensComposerForCapture(_ value: Bool?, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: newSessionOpensComposerDefaultsKey)
        } else {
            defaults.removeObject(forKey: newSessionOpensComposerDefaultsKey)
        }
    }
    #endif

    /// The overlay panel's opaque content (Flow 01, sidebar-presence §04):
    /// fill `#1c1c1c`, radius 18, 1pt stroke `#00000026`. Only visible in
    /// overlay mode — hidden in pinned/closed/collapsed, where the sidebar
    /// is transparent chrome instead. `masksToBounds` is true here (to clip
    /// the fill/stroke to the rounded rect), so its own shadow would get
    /// clipped too — the shadow lives on the unclipped `backgroundEffectView`
    /// sibling directly behind it instead.
    private let sidebarOverlayBackground: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alphaValue = 0
        view.isHidden = true
        return view
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

    /// Current sidebar state — always kept in sync with `store.sidebarMode`.
    private var sidebarMode: SidebarMode = .pinned

    /// Last published value of `store.toolbarRowTopAnchorConstant`.
    /// Updated in layout() from the live close-button frame so the SwiftUI
    /// sidebar's own toolbar row (the "+" button) survives macOS version
    /// bumps and upstream titlebar refactors. There's no longer an AppKit
    /// toggle button of our own to anchor to (Flow 01 removed the
    /// terminal-card top bar) — this constant only feeds the publish below.
    private var lastPublishedToolbarRowTopAnchorConstant: CGFloat = 22

    /// True while a sidebar mode-transition animation (`transitionTo` or
    /// `sidebarViewModeChanged`) is in flight. `layout()`'s resize reclamp
    /// must not run while this is true: `sidebarWidthConstraint.animator()`
    /// drives the constraint through intermediate values every frame during
    /// the animation, and reclamping against those mid-flight values would
    /// fight (or outright kill) the open/close animation. Set true right
    /// before `NSAnimationContext.runAnimationGroup` starts, cleared in its
    /// `completionHandler`, GATED by `sidebarTransitionGeneration` below —
    /// see that property's doc comment for why the raw completion closure
    /// alone isn't safe.
    private var isSidebarTransitionAnimating = false

    /// Bumped at the start of every `transitionTo`/`sidebarViewModeChanged`
    /// call; each call's completion handler captures the value it bumped to
    /// and only clears `isSidebarTransitionAnimating` if the counter still
    /// matches when it fires. Flow 05 gave each transition pair its own
    /// duration (180–260ms) instead of one uniform 200ms, which means a
    /// SHORTER transition started shortly after a LONGER one (e.g. full
    /// close at 180ms fired while a 260ms collapse from the previous toggle
    /// is still animating) reliably finishes first. Without this guard, the
    /// stale (superseded) transition's completion handler still fires later
    /// and clears the flag while the newer transition's own animation is
    /// genuinely still live — `layout()`'s resize reclamp then sees
    /// `isSidebarTransitionAnimating == false`, treats the still-animating
    /// constraint as settled, and snaps it directly (no `.animator()`),
    /// fighting the in-flight interpolation and leaving a half-applied mix
    /// of old/new geometry at rest. This is the mechanism behind the
    /// traffic-lights-over-terminal / narrow-card glitch caught in review.
    private var sidebarTransitionGeneration = 0

    /// The in-flight morph's clock (`beginSidebarMorph`), landed by the
    /// transition's completion or by the next morph.
    private var morphClock: SidebarMorphClock?

    /// The sidebar ⇄ rail motion's spring (`SidebarMotionDriver`): every
    /// constraint of a toggle or a hover reveal on one progress value.
    private lazy var motion = SidebarMotionDriver(view: self)

    /// Bounds on the card's leading edge while the spring moves it with the
    /// sidebar: its start and target x. The sidebar's edge may overshoot;
    /// the card's equality to it (priority 999) gives way here, so the
    /// terminal reflows once, not twice.
    private var cardLeadingFloor: NSLayoutConstraint!
    private var cardLeadingCeiling: NSLayoutConstraint!

    // MARK: Rail hover reveal

    /// Decides when the rail reveals the full sidebar and when it collapses
    /// back (`RailHoverReveal`). Fed by `railHoverZone`, item activations,
    /// outside clicks and window focus; plays `setRailRevealed`.
    private lazy var railHover: RailHoverReveal = {
        let reveal = RailHoverReveal()
        reveal.onReveal = { [weak self] in self?.setRailRevealed(true) }
        reveal.onCollapse = { [weak self] in self?.setRailRevealed(false) }
        // Never from a mid-flight width: the reveal captures the rail's
        // width as it starts (`beginRailRevealPresentation`).
        reveal.canReveal = { [weak self] in self.map { !$0.isSidebarTransitionAnimating } ?? false }
        return reveal
    }()

    /// The reveal's target: true from the moment a reveal starts until its
    /// collapse starts. The sidebar presents expanded while it is true,
    /// though the mode stays `.collapsed`.
    private var railRevealTarget = false

    /// True from the start of a reveal until its collapse lands: the sidebar
    /// is drawn over the card on `railRevealBacking`, and the card holds its
    /// x on `shadowHostLeadingToSuperview` instead of following the
    /// sidebar's trailing edge, so it never resizes.
    private var isRailRevealPresented = false

    /// The rail's width when the reveal started: where the card's x comes
    /// from and where the collapse lands, so a reveal always returns to
    /// exactly the rail it left.
    private var railRevealRestingWidth: CGFloat = 0

    /// The style the reveal in progress started with (`RailRevealStyle`,
    /// the "Reveal style" dial). Read once per reveal, so a dial change
    /// never splits a reveal from its collapse.
    private var railRevealStyle: RailRevealStyle = .push

    /// True while an overlay-style reveal is presented: the card holds its x
    /// and the sidebar is drawn over it on `railRevealBacking`.
    private var railRevealOverlays: Bool { isRailRevealPresented && railRevealStyle == .overlay }

    /// The mode the sidebar's geometry is laid out as: pinned while a push
    /// reveal is out, else the real mode.
    private var geometryMode: SidebarMode {
        railRevealTarget && railRevealStyle == .push ? .pinned : sidebarMode
    }

    /// The sidebar's surface while revealed: the chrome fill, out to the
    /// pinned gutter past the sidebar, lifted off the terminal by the
    /// DESIGN.md §6 overlay shadow. At the rail's width, chrome on chrome, it
    /// is invisible, so the reveal grows out of the rail with no seam.
    private let railRevealBacking: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    /// `railRevealBacking`'s reach past the sidebar's trailing edge: 0 on
    /// the rail, the pinned gutter once revealed. Animated with the width.
    private var railRevealBackingGutter: NSLayoutConstraint!

    /// The rail (and, once revealed, the whole revealed panel) as a hover
    /// area. Never takes clicks.
    private let railHoverZone = RailHoverZoneView()

    /// Mouse-down monitor installed while revealed: a click outside the
    /// revealed panel collapses it.
    private var railRevealClickMonitor: Any?

    /// Whether the sidebar draws as the rail: on the rail and not revealed.
    private var presentsRail: Bool { sidebarMode == .collapsed && !railRevealTarget }

    #if DEBUG
    var isRailRevealedForTesting: Bool { railRevealTarget }
    var railHoverForTesting: RailHoverReveal { railHover }
    /// The sidebar's spring, for tests that step it frame by frame.
    var motionForTesting: SidebarMotionDriver { motion }
    #endif

    /// True while `applyCollapseCrossfadeSidebarView` has both
    /// `fullSidebarContent()` and `railSidebarContent()` mounted at once
    /// (Flow 05's pinned⇄collapsed cross-fade). Cleared by `transitionTo`'s
    /// completion handler, which calls `applySidebarView()` to settle back
    /// down to the cheap single-tree steady state. Guards
    /// `applyCollapseCrossfadeSidebarView` against rebuilding
    /// `hostingView.rootView` a second time on a rapid re-toggle mid-flight
    /// — see that method's doc comment.
    private var isCollapseCrossfadeHosted = false

    /// True while `applyMorphStep` holds the sidebar between its modes
    /// (DEBUG captures and gates): `layout()`'s width reclamp would put the
    /// mode's own width back. Any transition releases it.
    private var isMorphStepHeld = false

    /// Test seam: what the pinned rows would render toward right now.
    var isCollapsedPresentationForTesting: Bool { widthModel.isCollapsedPresentation }
    var sidebarModeForTesting: SidebarMode { sidebarMode }
    /// Test seam: the terminal card's and the sidebar's frames.
    var cardFrameForTesting: NSRect { terminalShadowHost.frame }
    var sidebarFrameForTesting: NSRect { sidebarHostingView.frame }
    var sidebarHostingViewForTesting: NSView { sidebarHostingView }
    var sidebarDragHandleFrameForTesting: NSRect { sidebarDragHandle.frame }
    var sidebarDragHandleIsHiddenForTesting: Bool { sidebarDragHandle.isHidden }
    /// Test seam: the live Window margin path, with the margin passed in
    /// rather than written to the shared dial store.
    func applyWindowMarginForTesting(_ inset: CGFloat) { applyWindowMargin(inset) }

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
    /// `WorkspaceLayout.sidebarDragHandleWidth(for:margin:)`; the handle's
    /// trailing edge is pinned to the card, so this alone places it.
    private var sidebarDragHandleWidthConstraint: NSLayoutConstraint!
    private var shadowHostLeadingToSuperview: NSLayoutConstraint!

    /// The sidebar column's leading and bottom insets from the window: 0,
    /// except in overlay, where the column sits the window margin in so the
    /// overlay card around it keeps the terminal card's margin and the
    /// column's contents keep their pinned offsets from the card's edges.
    private var sidebarHostLeadingConstraint: NSLayoutConstraint!
    private var sidebarHostBottomConstraint: NSLayoutConstraint!
    /// The overlay card (`sidebarOverlayBackground`): the window margin off
    /// the window's top, leading and bottom edges, and the pinned gutter
    /// past the sidebar column's trailing edge.
    private var overlayPanelTopConstraint: NSLayoutConstraint!
    private var overlayPanelLeadingConstraint: NSLayoutConstraint!
    private var overlayPanelBottomConstraint: NSLayoutConstraint!
    private var overlayPanelTrailingConstraint: NSLayoutConstraint!
    /// The sidebar drag handle's trailing edge — mutually exclusive, like
    /// the card's leading pair. Pinned/collapsed: on the card's leading
    /// edge. Overlay: on the overlay card's trailing edge, so the handle
    /// fills the pinned gutter inside the card.
    private var sidebarDragHandleTrailingToCard: NSLayoutConstraint!
    private var sidebarDragHandleTrailingToPanel: NSLayoutConstraint!

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

    /// Drag handle on the sidebar's trailing edge for resizing. Pinned, it
    /// sits in the same inset gap the browser drag handle sits in (proven
    /// pattern), just on the other side of the terminal card; on the rail,
    /// which has no gap, it is a strip over the rail's trailing edge
    /// (`WorkspaceLayout.sidebarDragHandleWidth`). Visible when the
    /// sidebar is pinned or collapsed; hidden when closed or overlaid.
    private lazy var sidebarDragHandle: PanelDragHandleView = {
        let handle = PanelDragHandleView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.isHidden = true  // corrected to match initialMode in setup()
        // On the rail the strip overlays the list's trailing edge: scrolling
        // and the list's scroller pass through to the sidebar beneath.
        handle.viewsBeneath = { [weak self] in
            self.map { [$0.sidebarHostingView] } ?? []
        }
        handle.onDragStart = { [weak self] in
            self?.beginSidebarDrag()
        }
        handle.onDrag = { [weak self] delta in
            self?.handleSidebarDrag(delta: delta)
        }
        handle.onDragEnd = { [weak self] in
            self?.endSidebarDrag()
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
        return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    /// `sidebarHostingView`'s appearance: pinned to the overlay fill's
    /// luminance in overlay mode, and nil (follow the window) in every other
    /// mode. (The DEBUG appearance preview sets the whole app's appearance,
    /// so the window carries it here.)
    private var sidebarAppearanceOverride: NSAppearance? {
        return sidebarMode == .overlay
            ? NSAppearance(named: overlayBackgroundIsDark ? .darkAqua : .aqua)
            : nil
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

    /// The focused terminal session's live background color — same accessor
    /// `TerminalWindow.preferredBackgroundColor` uses (`surface.backgroundColor`,
    /// the post-OSC-11 live value, falling back to `derivedConfig.backgroundColor`,
    /// the static theme default) — kept in sync with `observedSurface` by
    /// `rebindFocusedSurfaceTheme()`. `nil` for a browser session or when
    /// nothing is focused yet.
    private var focusedTerminalBackgroundNSColor: NSColor? {
        guard let surface = observedSurface else { return nil }
        return NSColor(surface.backgroundColor ?? surface.derivedConfig.backgroundColor)
    }

    /// Overlay panel fill (Flow 01 §04, Sean's review): matches the focused
    /// terminal session's own background — light over a light terminal
    /// theme, dark over a dark one — rather than following OS appearance.
    /// Falls back to the static canvas token (`canvasPaletteNSColor`) when
    /// no terminal surface is focused, e.g. a browser pane.
    private var overlayBackgroundNSColor: NSColor {
        focusedTerminalBackgroundNSColor ?? canvasPaletteNSColor
    }

    /// Whether `overlayBackgroundNSColor` reads as dark, so the overlay's
    /// SwiftUI content (`sidebarHostingView`) should render its dark-token
    /// (light-on-dark) text/icon set instead of the light-token one — kept
    /// legible against a dark terminal theme even when the OS is in light
    /// mode. Threshold is the standard WCAG-adjacent 0.5 midpoint on
    /// perceptual (ITU-R BT.601) luminance.
    private var overlayBackgroundIsDark: Bool {
        guard let rgb = overlayBackgroundNSColor.usingColorSpace(.deviceRGB) else { return !isLightAppearance }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance < 0.5
    }

    init<ViewModel: TerminalViewModel>(ghostty: Ghostty.App, viewModel: ViewModel, delegate: (any TerminalViewDelegate)? = nil, store: WorkspaceStore = .shared) {
        self.ghostty = ghostty
        self.store = store
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

        // A live Window margin dial change re-applies the card insets.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sidebarDialsChanged),
            name: SidebarDialTuning.didChangeNotification,
            object: nil
        )
    }

    @objc private func sidebarDialsChanged() {
        // Constraints are main-thread only; the panel posts from the main
        // actor, but a selector observer runs on the posting thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.sidebarDialsChanged() }
            return
        }
        applyWindowMargin()
        #if DEBUG
        redlineOverlay.refresh()
        #endif
    }

    /// Re-applies the Window margin dial (`SidebarDialTuning.windowMargin`)
    /// to every card inset constraint, so a live dial change lands without a
    /// mode change or relaunch. The same constants `setup()` and
    /// `applyTransitionConstraints` write; skipped mid-transition, where the
    /// animator owns them — both transition completions call this again, so
    /// a dial change made mid-flight lands when the motion settles.
    private func applyWindowMargin(_ inset: CGFloat = SidebarDialTuning.windowMargin()) {
        guard !isSidebarTransitionAnimating else { return }
        shadowHostTopConstraint.constant = inset
        shadowHostBottomConstraint.constant = -inset
        shadowHostTrailingConstraint.constant = -inset
        shadowHostTrailingToBrowser.constant = -inset
        shadowHostLeadingToSidebar.constant = WorkspaceLayout.sidebarTrailingGutter(for: geometryMode, margin: inset)
        sidebarDragHandleWidthConstraint.constant = WorkspaceLayout.sidebarDragHandleWidth(for: geometryMode, margin: inset)
        // Overlay-revealed, the card holds the x it had on the rail.
        if !railRevealOverlays {
            shadowHostLeadingToSuperview.constant = inset
        }
        if railRevealTarget {
            railRevealBackingGutter.constant = WorkspaceLayout.sidebarTrailingGutter(for: .pinned, margin: inset)
        }
        applyOverlayPanelInsets(inset)
        if sidebarMode == .overlay {
            sidebarHostLeadingConstraint.constant = inset
            sidebarHostBottomConstraint.constant = -inset
        }
        // Overlay collapses the browser to zero insets; leave it there.
        if sidebarMode != .overlay {
            browserShadowHostTopConstraint.constant = inset
            browserShadowHostBottomConstraint.constant = -inset
            browserShadowHostTrailingConstraint.constant = -inset
        }
        // The cards stay concentric with the window corner at the new
        // margin (`WorkspaceLayout.terminalCornerRadius`); their shadow
        // paths follow on the next layout pass.
        let radius = WorkspaceLayout.concentricCornerRadius(margin: inset)
        terminalContainer.layer?.cornerRadius = radius
        terminalShadowHost.layer?.cornerRadius = radius
        historyHostingView.layer?.cornerRadius = radius
        if sidebarMode != .overlay {
            browserShadowHost.layer?.cornerRadius = radius
        }
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    /// The overlay card's frame constants at a window margin. Only visible
    /// in overlay, so they're written outright rather than animated.
    private func applyOverlayPanelInsets(_ inset: CGFloat) {
        overlayPanelTopConstraint.constant = inset
        overlayPanelLeadingConstraint.constant = inset
        overlayPanelBottomConstraint.constant = -inset
        overlayPanelTrailingConstraint.constant = WorkspaceLayout.sidebarTrailingGutter(for: .overlay, margin: inset)
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
        NotificationCenter.default.removeObserver(self, name: .workspaceSelectNextSession, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceSelectPreviousSession, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceFocusSessionAtIndex, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceCloseSession, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceSelectNextProject, object: nil)
        NotificationCenter.default.removeObserver(self, name: .workspaceSelectPreviousProject, object: nil)

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

        // Cmd+Shift+]/[, Cmd+1-9, Cmd+W and Cmd+Ctrl+]/[ — here for the same
        // reason as Cmd+T: the rail unmounts the expanded list that used to
        // observe them.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseSession(_:)),
            name: .workspaceCloseSession,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectNextProject(_:)),
            name: .workspaceSelectNextProject,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectPreviousProject(_:)),
            name: .workspaceSelectPreviousProject,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectNextSession(_:)),
            name: .workspaceSelectNextSession,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectPreviousSession(_:)),
            name: .workspaceSelectPreviousSession,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusSessionAtIndex(_:)),
            name: .workspaceFocusSessionAtIndex,
            object: window
        )

        // If the window is already key when we move into it, freeze immediately.
        if window.isKeyWindow {
            store.freezeSnapshot()
        }

        // Automated CEF browser crash repro (see scripts/debug/cef-repro.sh).
        // Fires `toggleBrowser()` — the exact same entry point the globe button's
        // `#selector(toggleBrowser)` action uses — once the window and view
        // hierarchy are established, so the repro is unattended but otherwise
        // identical to a real click. Gated at runtime (not compile-time) so a
        // Release-signed lab build can also be driven without GUI automation —
        // this is the only way to reproduce against the Release CEF profile.
        WorkspaceViewContainer.triggerDebugAutoOpenBrowserIfNeeded(on: self)

        #if DEBUG
        triggerCaptureLaunchHooksIfNeeded()
        #endif
    }

    #if DEBUG
    /// Capture-rig launch hooks that live on the container because it exists
    /// in every sidebar mode (the sidebar itself is unmounted when closed).
    /// Each calls the action its click or shortcut calls.
    private func triggerCaptureLaunchHooksIfNeeded() {
        if let hook = CaptureFixture.composerHook, CaptureFixture.claimHook("composer") {
            DispatchQueue.main.asyncAfter(deadline: .now() + hook.delay) { [weak self] in
                guard let self else { return }
                switch hook.target {
                case .open:
                    // The tray "+" (`SidebarTrayItems.sidebarTrayItems`).
                    self.presentComposerOverlay(projectBinding: .open)
                case .prefilled(let name):
                    // A project row's "+" (`ProjectDisclosureRow.handleNewSession`).
                    let store = self.store
                    guard let project = store.projects.first(where: { $0.name == name }) else {
                        NSLog("[CaptureFixture] GHOSTTIES_CAPTURE_COMPOSER: no project named \(name)")
                        return
                    }
                    switch ProjectRowNewSession.action(for: project, optionHeld: false, templates: store.templates) {
                    case .openComposer(let binding): self.presentComposerOverlay(projectBinding: binding)
                    case .instantCreate: break
                    }
                }
            }
        }
        if let path = CaptureFixture.scriptPath, let dir = CaptureFixture.harnessStateDir,
           CaptureFixture.claimHook("script") {
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                await CaptureScript.launch(scriptAt: path, host: self, stateDir: dir)
            }
        }
        if let size = CaptureFixture.windowContentSize, CaptureFixture.claimHook("windowSize") {
            // After the window's own restore/default sizing has run.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.window?.setContentSize(size)
            }
        }
        if let seconds = CaptureFixture.sidebarToggleAfter, CaptureFixture.claimHook("sidebarToggle") {
            // Cmd+S (`TerminalController.toggleWorkspaceSidebar`), twice:
            // pinned -> rail, then rail -> pinned.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.toggleSidebar()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 * seconds) { [weak self] in
                self?.toggleSidebar()
            }
        }
        if let seconds = CaptureFixture.railRevealAfter, CaptureFixture.claimHook("railReveal") {
            // A completed hover dwell on the rail.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.sidebarMode == .collapsed else { return }
                self.railHover.revealNow()
            }
        }
        if let steps = CaptureFixture.morphSteps, CaptureFixture.claimHook("morphSteps") {
            // After the window has taken its capture size (0.5s, above).
            let log = CaptureFixture.harnessStateDir?.appendingPathComponent("morph-steps.log")
            if let log { try? Data().write(to: log) }
            let start = Date()
            for index in 0..<steps.count {
                let progress = CGFloat(index) / CGFloat(steps.count - 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(index) * steps.hold) { [weak self] in
                    guard let self else { return }
                    self.applyMorphStep(progress)
                    // Let SwiftUI commit the step before announcing it.
                    DispatchQueue.main.async {
                        guard let log, let handle = try? FileHandle(forWritingTo: log) else { return }
                        handle.seekToEndOfFile()
                        handle.write(Data(String(format: "%d %.4f %.3f\n", index, progress, Date().timeIntervalSince(start)).utf8))
                        try? handle.close()
                    }
                }
            }
        }
        if let seconds = CaptureFixture.sidebarRailClosePinAfter, CaptureFixture.claimHook("sidebarRailClosePin") {
            // Cmd+S (pinned -> rail), Cmd+Shift+S (rail -> closed), then
            // Cmd+Shift+S again (closed -> pinned).
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.toggleSidebar()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 * seconds) { [weak self] in
                self?.toggleSidebarFullyClosed()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 * seconds) { [weak self] in
                self?.toggleSidebarFullyClosed()
            }
        }
    }
    #endif

    /// Fires exactly once per process, guarded by `GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER=1`.
    /// Runtime-gated (was `#if DEBUG`) so it survives into Release builds;
    /// the env var itself is the only thing standing between this and a
    /// production launch triggering it.
    private static var didFireDebugAutoOpenBrowser = false
    private static func triggerDebugAutoOpenBrowserIfNeeded(on container: WorkspaceViewContainer) {
        guard !didFireDebugAutoOpenBrowser else { return }
        guard ProcessInfo.processInfo.environment["GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER"] == "1" else { return }
        didFireDebugAutoOpenBrowser = true
        NSLog("[CEFDiag] GHOSTTIES_DEBUG_AUTO_OPEN_BROWSER set — auto-triggering toggleBrowser() via the globe button's own action.")
        // Dispatch to the next runloop turn so the window is fully key/on-screen
        // before we drive the same path the globe button drives.
        DispatchQueue.main.async { [weak container] in
            container?.toggleBrowser()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard sidebarMode == .pinned || sidebarMode == .closed || sidebarMode == .collapsed else { return }
        // Canvas still follows OS light/dark — it's Ghostties chrome, not
        // terminal content.
        layer?.backgroundColor = canvasBackgroundCGColor
        // Terminal card follows the focused surface's theme when available;
        // the resolver handles the light/dark fallback itself.
        terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
        // Browser card has no theme concept — always the light/dark fallback.
        browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
        railRevealBacking.layer?.backgroundColor = canvasBackgroundCGColor
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
            let inset = SidebarDialTuning.windowMargin()
            return NSSize(
                width: termSize.width + currentSidebarWidth + inset * 2,
                height: termSize.height + inset * 2
            )
        case .collapsed:
            let inset = SidebarDialTuning.windowMargin()
            return NSSize(
                width: termSize.width + WorkspaceLayout.collapsedRailWidth(in: self)
                    + WorkspaceLayout.sidebarTrailingGutter(for: .collapsed, margin: inset) + inset,
                height: termSize.height + inset * 2
            )
        case .closed:
            let inset = SidebarDialTuning.windowMargin()
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
        // Revealed from the rail, the sidebar floats over the card: the
        // cards still share the window with the rail only.
        let sidebarWidth: CGFloat = railRevealOverlays
            ? railRevealRestingWidth
            : (sidebarMode == .pinned || sidebarMode == .collapsed) ? widthModel.width : 0
        let inset = SidebarDialTuning.windowMargin()
        // Three inset slots: leading of terminal, gap between panels, trailing of browser.
        return bounds.width - sidebarWidth - inset * 3
    }

    override func layout() {
        super.layout()
        #if DEBUG
        if !redlineOverlay.isHidden { redlineOverlay.needsDisplay = true }
        #endif

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
        if sidebarMode == .pinned && bounds.width > 0 && !isSidebarTransitionAnimating && !isMorphStepHeld {
            let inset = SidebarDialTuning.windowMargin()
            let maxByAvailableSpace = bounds.width - WorkspaceLayout.terminalMinWidth - inset * 2
            let upperBound = min(WorkspaceLayout.sidebarMaxWidth, max(maxByAvailableSpace, WorkspaceLayout.sidebarMinWidth))
            let reclamped = min(max(currentSidebarWidth, WorkspaceLayout.sidebarMinWidth), upperBound)
            if reclamped != widthModel.width {
                sidebarWidthConstraint.constant = reclamped
                widthModel.width = reclamped
                widthModel.expandedWidth = reclamped
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
        // The shadow lives on `backgroundEffectView` now (see its declaration
        // comment) — a rounded-rect path matching the panel it sits behind,
        // same perf rationale as the two shadow paths above.
        if !backgroundEffectView.bounds.isEmpty {
            backgroundEffectView.layer?.shadowPath = CGPath(
                roundedRect: backgroundEffectView.bounds,
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
        }

        if !railRevealBacking.isHidden && !railRevealBacking.bounds.isEmpty {
            railRevealBacking.layer?.shadowPath = CGPath(rect: railRevealBacking.bounds, transform: nil)
        }

        // Re-derive toolbar row position from live close-button frame.
        // This survives macOS version bumps and upstream titlebar refactors.
        if let constant = WorkspaceLayout.titlebarRowTopAnchorConstant(in: self) {
            if abs(lastPublishedToolbarRowTopAnchorConstant - constant) > 0.5 {
                lastPublishedToolbarRowTopAnchorConstant = constant
            }
            // Publish to SwiftUI sidebar so the + button stays in sync.
            if abs(store.toolbarRowTopAnchorConstant - constant) > 0.5 {
                store.toolbarRowTopAnchorConstant = constant
            }
        }

        // Re-derive the collapsed rail width from the same live button
        // frames — the rail must clear the traffic-light cluster, which can
        // change width across macOS versions and titlebar layout passes
        // (window attach, fullscreen enter/exit). The rail tray's copy
        // (`SidebarWidthModel.railWidth`) tracks it in every mode, animating
        // or not: it is the rail's settled width, never an intermediate one.
        let railWidth = WorkspaceLayout.collapsedRailWidth(in: self)
        if abs(widthModel.railWidth - railWidth) > 0.5 {
            widthModel.railWidth = railWidth
        }
        // The constraint reclamp is skipped mid-transition-animation for the
        // same reason the sidebar resize reclamp above is: the animator
        // drives `sidebarWidthConstraint` through intermediate values every
        // frame, and reclamping against those would fight the open/collapse
        // animation.
        if sidebarMode == .collapsed && !isSidebarTransitionAnimating && !isMorphStepHeld && !isRailRevealPresented {
            if abs(sidebarWidthConstraint.constant - railWidth) > 0.5 {
                sidebarWidthConstraint.constant = railWidth
                widthModel.width = railWidth
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

        // Every settled mode states its own presentation. The crossfade
        // writes this flag mid-animation, but it is the only other writer,
        // so a path that never crossfades (rail -> closed -> pinned) would
        // otherwise leave the previous mode's value behind.
        widthModel.morph = presentsRail ? 1 : 0

        // One view and the Sessions list morph: one tree, hosted the same
        // in both modes, held at the mode's end; the tray follows the
        // model's presentation. The layouts that don't morph (task-first,
        // the Projects tab's tabs layout) host the rail as the same session
        // list held at the rail's end (`SidebarRailColumn`), and crossfade.
        if sidebarBodyMorphs {
            hostingView.rootView = hostRoot(content: fullSidebarContent(), trayIsVertical: nil)
            return
        }
        if presentsRail {
            hostingView.rootView = hostRoot(content: railSidebarContent(), trayIsVertical: true)
            return
        }

        hostingView.rootView = hostRoot(content: fullSidebarContent(), trayIsVertical: false)
    }

    /// Whether the sidebar's current body is one that morphs between the
    /// expanded list and the rail (`SidebarBodyKind.oneViewAccordion`,
    /// `.sessionsList`), rather than crossfading.
    private var sidebarBodyMorphs: Bool {
        guard currentSidebarViewMode != "taskFirst" else { return false }
        let tab = UserDefaults.standard.string(forKey: "ghostties.sidebarTab").flatMap(SidebarTab.init(rawValue:)) ?? .projects
        return SidebarBodyKind.resolve(tab: tab, dial: SidebarDialTuning.projectsLayout()) != .projectsList
    }

    /// Wraps sidebar content in `SidebarHostRoot` — see that type for why
    /// every mode shares one root.
    private func hostRoot(content: AnyView, trayIsVertical: Bool?) -> AnyView {
        let root = SidebarHostRoot(
            model: widthModel,
            content: content,
            trayIsVertical: trayIsVertical,
            showsTrayWhenExpanded: currentSidebarViewMode != "taskFirst",
            // Revealed from the rail, the sidebar lays out as pinned: the
            // card's pinned gap (push) or the backing's gutter (overlay).
            gutterMode: railRevealTarget ? .pinned : sidebarMode
        )
        .environmentObject(store)
        .environmentObject(coordinator)
        #if DEBUG
        return AnyView(root
            .environment(\.redlineRegistry, redlineOverlay.registry)
            .environment(\.morphProbe, morphProbe))
        #else
        return AnyView(root)
        #endif
    }

    /// The rail for the layouts that don't morph (`SidebarRailColumn`):
    /// hosted settled on the rail, and mounted alongside
    /// `fullSidebarContent()` by the cross-fade
    /// (`applyCollapseCrossfadeSidebarView`).
    private func railSidebarContent() -> AnyView {
        let content = SidebarRailColumn()
            .environmentObject(store)
            .environmentObject(coordinator)
            .environmentObject(widthModel)
            .ignoresSafeArea(.container, edges: .top)
        return AnyView(SidebarMorphFrame(model: widthModel, content: content))
    }

    /// The pinned sidebar's content — whichever view mode (project-first/
    /// task-first) is currently selected. Extracted from `applySidebarView()`
    /// for the same reason as `railSidebarContent()` above: the Flow 05
    /// transitional cross-fade needs to mount this alongside the rail, not
    /// swap it out for the rail instantly.
    ///
    /// `.environmentObject(widthModel)` is injected here (new — it wasn't
    /// needed before Flow 05) so `RecentsRowView` can read
    /// `widthModel.isCollapsedPresentation` and run its own label-fade/
    /// glyph-travel choreography without threading a new binding through
    /// `WorkspaceSidebarView` → `RecentsListView` → `RecentsRowView`.
    private func fullSidebarContent() -> AnyView {
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
                .environmentObject(store)
                .environmentObject(sessionDraftStore)
            return AnyView(view)
        } else {
            let content = WorkspaceSidebarView()
                .environmentObject(store)
                .environmentObject(coordinator)
                .environmentObject(widthModel)
                .ignoresSafeArea(.container, edges: .top)
            // Pin to a concrete width via `SidebarMorphFrame` (the expanded
            // width, clipped to the current one) so the nested LazyVStack
            // inside WorkspaceSidebarView receives a definite cross-axis
            // proposal. Without this the hosting view proposes .infinity,
            // which sends LazyVStack.sizeThatFits into infinite measurement
            // recursion — the same root cause fixed for taskFirst in
            // sidebar-layout-hang-v0 (commit 11530667b). The wrapper reads
            // `widthModel` so the user-resizable drag handle continues to
            // work without rebuilding this tree on every tick.
            let view = SidebarMorphFrame(model: widthModel, content: content)
            return AnyView(view)
        }
    }

    /// The one-object pinned ⇄ rail morph (motion spec §1): the sidebar
    /// stays one tree; `morph` and `width` move together in ONE
    /// `withAnimation` played on the spring `transitionTo` runs next
    /// (`SidebarMotionDriver`, read through `SidebarMorphClock`), so the
    /// panel's edge and the card's are on the same frame every frame. Every
    /// leaf interpolates its own size and position from `morph`, and the
    /// labels fade on windows of it (`MorphLabelFade`). Reduce Motion: the
    /// geometry snaps and the labels fade over 120ms. Before macOS 14 (no
    /// `CustomAnimation`) the morph plays an equivalent SwiftUI spring.
    ///
    /// Re-entrant: a second toggle mid-flight writes new targets and lands
    /// the old clock.
    private func beginSidebarMorph(to newMode: SidebarMode, reduceMotion: Bool) {
        guard let hostingView = sidebarHostingView as? NSHostingView<AnyView> else { return }
        coordinator.sessionPopover.dismiss()
        NotificationCenter.default.post(name: .workspaceSidebarWillMorph, object: window)
        isCollapseCrossfadeHosted = false
        // The same tree, rebuilt for the new mode's gutter: every view type
        // matches, so nothing remounts.
        hostingView.rootView = hostRoot(content: fullSidebarContent(), trayIsVertical: nil)

        let railWidth = WorkspaceLayout.collapsedRailWidth(in: self)
        widthModel.railWidth = railWidth
        if newMode == .pinned {
            widthModel.expandedWidth = currentSidebarWidth
        }
        let targetMorph: CGFloat = newMode == .collapsed ? 1 : 0
        let targetWidth = newMode == .collapsed ? railWidth : currentSidebarWidth
        widthModel.isMorphing = true
        if reduceMotion {
            morphClock?.land()
            morphClock = nil
            widthModel.morph = targetMorph
            widthModel.width = targetWidth
        } else if targetMorph == widthModel.morph && targetWidth == widthModel.width {
            // Same destination (Cmd+S pinning a reveal): the running clock
            // keeps playing; a new one would restart it.
        } else {
            let animation = morphClockAnimation(to: targetWidth, collapsing: newMode == .collapsed)
            withAnimation(animation) {
                widthModel.morph = targetMorph
                widthModel.width = targetWidth
            }
        }
    }

    /// The SwiftUI animation that plays a morph on the spring's clock: a new
    /// `SidebarMorphClock` from the model's current (previous) target width
    /// to `targetWidth`, landing the old one. Before macOS 14 (no
    /// `CustomAnimation`) an equivalent SwiftUI spring on its own clock.
    private func morphClockAnimation(to targetWidth: CGFloat, collapsing: Bool) -> Animation {
        morphClock?.land()
        morphClock = nil
        if #available(macOS 14, *) {
            let clock = SidebarMorphClock(constraint: sidebarWidthConstraint, from: widthModel.width, to: targetWidth)
            morphClock = clock
            return Animation(SidebarMorphClockAnimation(clock: clock))
        }
        let spring = WorkspaceLayout.sidebarMorphSpring(collapsing: collapsing)
        return .spring(response: spring.response, dampingFraction: spring.dampingFraction)
    }

    /// Stops a running spring where it is, for an animation that takes the
    /// constraints over (a full close, a view-mode switch, a drag).
    private func cancelMorphMotion() {
        guard motion.isRunning else { return }
        motion.cancel()
        // Its completion won't fire: retire it and clear what it would have.
        sidebarTransitionGeneration += 1
        isSidebarTransitionAnimating = false
        morphClock?.land()
        morphClock = nil
        widthModel.isMorphing = false
        setCardLeadingClamp(nil)
    }

    /// Where the card's leading edge is, from the constraints rather than the
    /// frame (a layout pass behind a spring that is still moving). While the
    /// clamp holds, the sidebar's edge plus gap can overshoot past the card
    /// (the 999 equality is broken), so the card is that sum held inside the
    /// clamp. A retarget's clamp must start here, or lifting the ceiling
    /// snaps the card forward by the overshoot.
    private var cardLeadingFromConstraints: CGFloat {
        let attached = sidebarWidthConstraint.constant + shadowHostLeadingToSidebar.constant
        guard cardLeadingFloor.isActive else { return attached }
        return min(max(attached, cardLeadingFloor.constant), cardLeadingCeiling.constant)
    }

    /// Bounds the card's leading edge to `range` while the spring runs, or
    /// lifts the bounds (nil).
    private func setCardLeadingClamp(_ range: ClosedRange<CGFloat>?) {
        guard let range else {
            cardLeadingFloor.isActive = false
            cardLeadingCeiling.isActive = false
            return
        }
        cardLeadingFloor.constant = range.lowerBound
        cardLeadingCeiling.constant = range.upperBound
        cardLeadingFloor.isActive = true
        cardLeadingCeiling.isActive = true
    }

    /// Flow 05 (sidebar-presence): mounts BOTH `fullSidebarContent()` and
    /// `railSidebarContent()` at once, cross-fading between them via
    /// `widthModel.isCollapsedPresentation`, instead of `applySidebarView()`'s
    /// instant single-tree swap — the fix for "content swaps INSTANTLY"
    /// between the expanded list and the rail. Only used for the
    /// `.pinned`⇄`.collapsed` pair `transitionTo` names; every other pair
    /// (anything through `.closed`/`.overlay`) keeps calling
    /// `applySidebarView()` directly, unchanged.
    ///
    /// Mounted ONLY for the duration of the transition — `transitionTo`'s
    /// completion handler calls `applySidebarView()` to collapse back down
    /// to the cheap single-tree steady state once settled, so the full
    /// (ScrollView + drag/drop + sections) content tree is never kept alive
    /// forever alongside the rail (see `SidebarWidthModel`'s doc comment on
    /// the render-cost history this file already guards against).
    ///
    /// Safe to call again mid-transition (a second toggle before the first
    /// settles): if the cross-fade is already hosted, this only updates
    /// `widthModel.isCollapsedPresentation`'s target inside a fresh
    /// `withAnimation` — it does NOT rebuild `hostingView.rootView` a second
    /// time, so the in-flight SwiftUI animation retargets smoothly from
    /// wherever it currently sits (SwiftUI's own interruptible-transition
    /// behavior — see the `Animation`s in `RecentsRowView`), instead of
    /// snapping and replaying.
    private func applyCollapseCrossfadeSidebarView(previousMode: SidebarMode, newMode: SidebarMode, targetWidth: CGFloat, reduceMotion: Bool) {
        guard let hostingView = sidebarHostingView as? NSHostingView<AnyView> else { return }
        let targetIsCollapsed = newMode == .collapsed

        if !isCollapseCrossfadeHosted {
            // Each tree held at its own end: the fade is the transition.
            let view = SidebarCollapseCrossfade(
                model: widthModel,
                full: AnyView(fullSidebarContent().environment(\.sidebarMorphOverride, 0)),
                rail: railSidebarContent()
            )
            hostingView.rootView = hostRoot(content: AnyView(view), trayIsVertical: nil)
            isCollapseCrossfadeHosted = true
            // Starting presentation is whatever mode we're leaving — set
            // directly (not animated) so the cross-fade animates FROM the
            // correct starting opacities, not from whatever the model was
            // last left at.
            widthModel.morph = previousMode == .collapsed ? 1 : 0
        }

        // The crossfade rides the spring's clock like the morph does.
        let animation = reduceMotion
            ? Animation.easeInOut(duration: WorkspaceLayout.sidebarReducedMotionCrossfadeDuration)
            : morphClockAnimation(to: targetWidth, collapsing: targetIsCollapsed)
        withAnimation(animation) {
            widthModel.morph = targetIsCollapsed ? 1 : 0
        }
    }

    @objc private func sidebarViewModeChanged() {
        // If a Flow 05 pinned⇄collapsed cross-fade happened to be mid-flight
        // (task-first/project-first toggled while the sidebar was also
        // transitioning), `applySidebarView()` below replaces
        // `hostingView.rootView` with a plain single-tree view for the new
        // mode, abandoning the cross-fade — clear the flag here too, or the
        // NEXT collapse-pair transition would wrongly believe a cross-fade
        // is already hosted and skip remounting it.
        isCollapseCrossfadeHosted = false
        cancelMorphMotion()
        // A view-mode switch lands on the settled rail, not a reveal. The
        // bump retires a reveal's pending completion here, at the teardown,
        // rather than relying on the group below to do it.
        railHover.reset()
        if isRailRevealPresented {
            sidebarTransitionGeneration += 1
            endRailRevealPresentation()
        }
        applySidebarView()

        // Update width constraint + intrinsic size to reflect the new mode's
        // sidebar width. Only animate when the sidebar is actually pinned; in
        // closed mode the width is 0, in overlay mode the constraint follows
        // the overlay width which is also driven by currentSidebarWidth.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isSidebarTransitionAnimating = true
        // Shares `sidebarTransitionGeneration` with `transitionTo` — both
        // entry points drive the same `sidebarWidthConstraint`/
        // `isSidebarTransitionAnimating`, so a view-mode toggle that lands
        // mid-`transitionTo` (or vice versa) needs the same guard against a
        // superseded completion handler firing late. See that property's
        // doc comment.
        sidebarTransitionGeneration += 1
        let generation = sidebarTransitionGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            switch sidebarMode {
            case .pinned, .overlay:
                sidebarWidthConstraint.animator().constant = currentSidebarWidth
                widthModel.width = currentSidebarWidth
                widthModel.expandedWidth = currentSidebarWidth
            case .collapsed:
                let railWidth = WorkspaceLayout.collapsedRailWidth(in: self)
                sidebarWidthConstraint.animator().constant = railWidth
                widthModel.width = railWidth
            case .closed:
                break
            }
        }, completionHandler: { [weak self] in
            guard let self, self.sidebarTransitionGeneration == generation else { return }
            self.isSidebarTransitionAnimating = false
            self.applyWindowMargin()
            // The resize reclamp in `layout()` was deferred for the duration of
            // this animation. Force one more layout pass now that the flag is
            // clear, or a window shrink that happened mid-animation may never
            // get re-clamped.
            self.needsLayout = true
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

    /// Toggle sidebar via keyboard shortcut (Cmd+S).
    /// Flips `pinned ↔ collapsed` (Sean, sidebar-presence review) — the
    /// toggle no longer walks all the way to fully closed; it goes from full
    /// width straight to the narrow rail. `closed` is left in the model
    /// (persistence, the hot zone, and the overlay reveal all still work),
    /// but the toggle can no longer reach or leave it — a persisted `closed`
    /// state only exits via the hot zone → overlay → promote-to-pinned path.
    /// Overlay isn't part of the cycle — it's a transient hover state, not
    /// one of the persisted widths — so the toggle promotes it straight to
    /// pinned, same as before Flow 01.
    ///
    /// Extracted to a testable static function, same pattern as
    /// `newSessionOpensComposer(in:)` above — the cycle order is precisely
    /// the kind of thing a silent regression could invert without a test
    /// catching it.
    static func nextSidebarMode(after mode: SidebarMode) -> SidebarMode {
        switch mode {
        case .pinned:    return .collapsed
        case .collapsed: return .pinned
        case .closed:    return .pinned
        case .overlay:   return .pinned
        }
    }

    @objc func toggleSidebar() {
        transitionTo(Self.nextSidebarMode(after: sidebarMode))
    }

    /// Full close ↔ reopen, bound to Cmd+Shift+S. Any visible mode (pinned,
    /// collapsed, overlay) goes to `.closed`; `.closed` reopens to `.pinned`.
    /// This is the toggle's only remaining path back into (and out of)
    /// `.closed` now that `toggleSidebar()`/`nextSidebarMode(after:)` cycle
    /// pinned ↔ collapsed and no longer visit it — the hot-zone reveal
    /// overlay path is unaffected.
    static func nextCloseToggleMode(after mode: SidebarMode) -> SidebarMode {
        mode == .closed ? .pinned : .closed
    }

    @objc func toggleSidebarFullyClosed() {
        transitionTo(Self.nextCloseToggleMode(after: sidebarMode))
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
            } else if let projectId = SessionComposerStore.shared.resolveCascadeProject(workspaceStore: store),
                      let project = store.projects.first(where: { $0.id == projectId }) {
                // Phase 4: use the composer's smart-default cascade instead
                // of an arbitrary `.first` pick (see
                // docs/plans/session-creation-unified.html).
                // Create a new browser session — this will call showBrowserContent,
                // which embeds into the side panel and animates it open.
                _Concurrency.Task { @MainActor in
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

    /// Where the pointer would put the sidebar edge, unclamped — the width
    /// the user is asking for, which can sit below the rail or between the
    /// rail and `sidebarMinWidth`. Non-nil only while a drag is in flight.
    private var sidebarDragPointerWidth: CGFloat?

    /// The pinned width when the drag began, restored if the drag ends up
    /// collapsing to the rail — passing through `sidebarMinWidth` on the
    /// way down must not overwrite the width the toggle expands back to.
    private var sidebarWidthBeforeDrag: CGFloat = 0

    /// Where a sidebar drag lands for a given pointer width: the rail below
    /// the midpoint between the rail and `sidebarMinWidth`, pinned (clamped
    /// to min…upperBound) at or above it — the same collapse point
    /// `NSSplitView` uses, so dragging snaps between rail and expanded in
    /// both directions instead of stopping at the min width.
    static func sidebarDragTarget(
        pointerWidth: CGFloat,
        railWidth: CGFloat,
        upperBound: CGFloat
    ) -> (mode: SidebarMode, width: CGFloat) {
        let snapPoint = (railWidth + WorkspaceLayout.sidebarMinWidth) / 2
        if pointerWidth < snapPoint {
            return (.collapsed, railWidth)
        }
        return (.pinned, min(max(pointerWidth, WorkspaceLayout.sidebarMinWidth), upperBound))
    }

    private func beginSidebarDrag() {
        // A drag takes the width from wherever a toggle's spring has it.
        if motion.isRunning {
            cancelMorphMotion()
            if isCollapseCrossfadeHosted {
                isCollapseCrossfadeHosted = false
                applySidebarView()
            }
        }
        sidebarDragPointerWidth = sidebarWidthConstraint.constant
        sidebarWidthBeforeDrag = currentSidebarWidth
    }

    /// Handle a horizontal drag delta from the sidebar drag handle.
    /// Positive delta = dragging right (sidebar grows), negative = dragging left (sidebar shrinks).
    private func handleSidebarDrag(delta: CGFloat) {
        guard let pointer = sidebarDragPointerWidth.map({ $0 + delta }) else { return }
        sidebarDragPointerWidth = pointer

        // Upper bound: the design-token max, but never wider than leaves room
        // for the terminal's minimum usable width (mirrors the browser drag
        // handle's clamp against `WorkspaceLayout.terminalMinWidth`).
        let inset = SidebarDialTuning.windowMargin()
        let maxByAvailableSpace = bounds.width - WorkspaceLayout.terminalMinWidth - inset * 2
        let upperBound = min(WorkspaceLayout.sidebarMaxWidth, max(maxByAvailableSpace, WorkspaceLayout.sidebarMinWidth))
        // Overlay only resizes: no snapping to the rail, no pinning. It
        // writes the same width pinned uses.
        if sidebarMode == .overlay {
            guard !isSidebarTransitionAnimating else { return }
            applyDraggedSidebarWidth(min(max(pointer, WorkspaceLayout.sidebarMinWidth), upperBound))
            return
        }

        let target = Self.sidebarDragTarget(
            pointerWidth: pointer,
            railWidth: WorkspaceLayout.collapsedRailWidth(in: self),
            upperBound: upperBound
        )

        // Crossing the snap point switches mode through the normal animated
        // transition. Expanding lands at the pointer's width so the edge
        // stays under the cursor; collapsing restores the pre-drag width for
        // the next expand. `transitionTo`'s 0.25s debounce can drop a
        // re-cross; the next drag tick re-evaluates and catches up.
        if target.mode != sidebarMode {
            currentSidebarWidth = target.mode == .pinned ? target.width : sidebarWidthBeforeDrag
            transitionTo(target.mode)
            return
        }

        // Live resize only in pinned mode, and never while the snap
        // animation is driving the width constraint — writing it mid-flight
        // would fight the animator. The next tick after it settles catches up.
        guard target.mode == .pinned, !isSidebarTransitionAnimating else { return }
        applyDraggedSidebarWidth(target.width)
    }

    /// Writes a dragged sidebar width — pinned's and overlay's one path.
    private func applyDraggedSidebarWidth(_ width: CGFloat) {
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
        sidebarWidthConstraint.constant = width
        currentSidebarWidth = width
        widthModel.expandedWidth = width
        widthModel.width = width
    }

    private func endSidebarDrag() {
        sidebarDragPointerWidth = nil
        persistSidebarWidth()
        // The overlay held open through the drag (`mouseExited`). Its hover
        // zone follows the new width, and a drag that ended outside it
        // closes the overlay as any exit does: the exit AppKit may still
        // deliver belongs to the replaced tracking area, so it's ignored.
        guard sidebarMode == .overlay else { return }
        updateTrackingAreas()
        if !pointerIsInOverlayZone {
            // Not debounced: a drag can end within the guard's 0.25s of the
            // overlay opening, and this close must not be dropped.
            transitionTo(.closed, debounced: false)
        }
    }

    /// Whether the pointer is inside the open overlay's hover zone.
    private var pointerIsInOverlayZone: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return WorkspaceLayout.overlayRevealZone(
            in: bounds,
            sidebarWidth: currentSidebarWidth,
            margin: SidebarDialTuning.windowMargin()
        ).contains(point)
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
                wireBrowserFailureState(for: cefView, bridge: bridge)
            }
        }

        _activeBrowserManager = manager
    }

    /// Wires a CEFBrowserView's creation-failure/success callbacks to the
    /// panel's inline empty state, and reflects whatever state the view is
    /// already in (it may have failed before this embed happened, e.g. the
    /// CEF-unavailable stub case notifies asynchronously right after init).
    private func wireBrowserFailureState(for cefView: CEFBrowserView, bridge: BrowserSessionBridge?) {
        let panel = browserPanelView
        bridge?.onCreationFailed = { [weak cefView, weak panel] in
            guard let cefView else { return }
            if cefView.creationFailedDueToPreviousCrash {
                // A prior launch's attempt never cleared the crash sentinel —
                // it almost certainly killed the process before surviving the
                // 3s creation watchdog. Recovery is automatic and one-shot
                // (no button — that is Sean's decision, not a gap): the
                // reset itself clears the sentinel AND acknowledges the
                // launch-time snapshot (CEFBridgeManager
                // .acknowledgePriorLaunchAttemptHandled, called inside
                // -resetProfileDataAndRetry:), so this same-process retry
                // reads as a fresh attempt, not another crash. This notice
                // only reports what already happened.
                panel?.failureStateView.show(
                    message: "The browser didn't come back last time, so old browser data was reset automatically — cookies and logins were set aside, not deleted. Retrying…"
                )
                cefView.resetProfileDataAndRetry { [weak panel] movedToPath, error in
                    if let error {
                        panel?.failureStateView.show(
                            message: "The browser didn't come back last time, and the automatic reset failed: \(error.localizedDescription)"
                        )
                    } else if let movedToPath {
                        panel?.failureStateView.show(
                            message: "The browser didn't come back last time, so old browser data was moved aside automatically to \(movedToPath). Retrying…"
                        )
                    }
                    // No `movedToPath` and no `error` means there was
                    // nothing to move — the sentinel-only case. Leave the
                    // "reset automatically… Retrying…" message from above.
                }
            } else {
                panel?.failureStateView.show(
                    message: "The browser couldn't start. Run scripts/download-cef.sh if this keeps happening."
                )
            }
        }
        bridge?.onCreationSucceeded = { [weak panel] in
            panel?.failureStateView.hide()
        }

        if cefView.creationFailed {
            bridge?.onCreationFailed?()
        } else {
            panel.failureStateView.hide()
        }
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
    /// `debounced: false` skips the oscillation guard, for a transition that
    /// is a deliberate one-off rather than a hover flicker (the close at the
    /// end of an overlay drag).
    private func transitionTo(_ newMode: SidebarMode, debounced: Bool = true) {
        guard newMode != sidebarMode else { return }
        let now = CACurrentMediaTime()
        guard !debounced || now - lastTransitionTime > 0.25 else { return }
        lastTransitionTime = now
        isMorphStepHeld = false
        let previousMode = sidebarMode
        sidebarMode = newMode
        // An overlay drag ends with the overlay: a later overlay must never
        // inherit a drag whose mouse-up was lost (`mouseExited` holds an
        // overlay open while one is in progress).
        if previousMode == .overlay {
            sidebarDragPointerWidth = nil
        }

        // Leaving the rail ends any hover reveal. Cmd+S while revealed pins
        // it: the sidebar is already out at the pinned width, so it stays
        // put. Overlay: the card slides out from under it to its pinned
        // place. Push: already the pinned geometry, so nothing moves. Any
        // other exit tears the reveal down first.
        let pinsReveal = previousMode == .collapsed && newMode == .pinned && isRailRevealPresented
        let pinsOverlayReveal = pinsReveal && railRevealOverlays
        if previousMode == .collapsed {
            railHover.pin()
        }
        if pinsReveal {
            beginPinningRailReveal()
        } else if isRailRevealPresented {
            endRailRevealPresentation()
        }

        // Re-derive the overlay's text/icon legibility override — only
        // overlay mode needs `sidebarHostingView`'s appearance pinned to
        // `overlayBackgroundNSColor`'s luminance; every other mode must
        // clear it and fall back to the OS appearance.
        applyChromeColor()

        let inset = SidebarDialTuning.windowMargin()

        // Content differs by mode (rail vs. full sidebar). The pinned⇄
        // collapsed pair is the only one with content motion. One view and
        // the Sessions list morph: one tree, every element interpolated
        // between its two ends on the panel's curve (`beginSidebarMorph`).
        // The layouts that don't morph cross-fade two trees instead (see
        // `applyCollapseCrossfadeSidebarView`'s doc comment); the
        // timing/reduceMotion args mirror what's computed for the AppKit
        // animation just below, so both stay in lockstep. Every other pair
        // (anything through `.closed`/`.overlay`) keeps the original
        // instant single-tree mount — the brief's "reveal overlay keeps its
        // current animation."
        let isCollapsePair = (previousMode == .pinned && newMode == .collapsed)
            || (previousMode == .collapsed && newMode == .pinned)
        let morphs = isCollapsePair && sidebarBodyMorphs
        if !isCollapsePair || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Not a spring: the duration-curve path (or the Reduce Motion
            // snap) below takes the constraints from wherever a running
            // spring left them.
            cancelMorphMotion()
        }
        if morphs {
            beginSidebarMorph(
                to: newMode,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        } else if isCollapsePair {
            applyCollapseCrossfadeSidebarView(
                previousMode: previousMode,
                newMode: newMode,
                targetWidth: newMode == .collapsed ? WorkspaceLayout.collapsedRailWidth(in: self) : currentSidebarWidth,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        } else {
            isCollapseCrossfadeHosted = false
            applySidebarView()
        }

        // 1. Swap leading constraints before animation.
        switch newMode {
        case .pinned, .collapsed:
            shadowHostLeadingToSuperview.isActive = false
            shadowHostLeadingToSidebar.isActive = true
        case .closed, .overlay:
            shadowHostLeadingToSidebar.isActive = false
            shadowHostLeadingToSuperview.isActive = true
        }
        if newMode == .overlay {
            sidebarDragHandleTrailingToCard.isActive = false
            sidebarDragHandleTrailingToPanel.isActive = true
        } else {
            sidebarDragHandleTrailingToPanel.isActive = false
            sidebarDragHandleTrailingToCard.isActive = true
        }

        // 2. Z-ordering for overlay mode. A pinned reveal keeps the sidebar
        // above the card until the card has slid out from under it.
        if !pinsReveal {
            let overlayZ: CGFloat = newMode == .overlay ? 100 : 0
            sidebarHostingView.layer?.zPosition = overlayZ
        }
        sidebarOverlayBackground.layer?.zPosition = newMode == .overlay ? 99 : 0

        // 3. Toggle isHidden so inactive NSVisualEffectViews leave the compositing tree.
        //    The background material is only visible in overlay mode (floating hover state).
        //    In pinned mode the sidebar is transparent — the window background shows through.
        switch newMode {
        case .pinned, .closed, .collapsed:
            backgroundEffectView.isHidden = true
            sidebarOverlayBackground.isHidden = true
        case .overlay:
            backgroundEffectView.isHidden = false
            sidebarOverlayBackground.isHidden = false
        }

        // Sidebar drag handle: active while pinned or collapsed — dragging
        // snaps between the two — and in overlay, where it only resizes.
        // Hidden in closed mode (sidebar isn't there).
        sidebarDragHandle.isHidden = newMode == .closed

        // 4. Animate constraints, widths, alphas — duration/curve come from
        // the Flow 05 named-transition table (`WorkspaceLayout.
        // sidebarTransitionTiming`), not one generic duration for every mode
        // change. Interruption: `.animator()` proxies on constraints/alpha
        // retarget from whatever AppKit's Auto Layout animation currently
        // has the affected views at (the presentation state), not the
        // original start value — calling `transitionTo` again mid-flight
        // (a second toggle) redirects smoothly instead of snapping to the
        // old end value and replaying. The completion handler below still
        // needs the generation guard (see `sidebarTransitionGeneration`'s
        // doc comment) — retargeting the constraint itself is safe, but a
        // SUPERSEDED transition's own completion firing late is not.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: previousMode, to: newMode)
        isSidebarTransitionAnimating = true
        sidebarTransitionGeneration += 1
        let generation = sidebarTransitionGeneration

        let animationCompletion: () -> Void = { [weak self] in
            guard let self, self.sidebarTransitionGeneration == generation else { return }
            self.isSidebarTransitionAnimating = false
            self.widthModel.isMorphing = false
            self.morphClock?.land()
            self.morphClock = nil
            self.setCardLeadingClamp(nil)
            // A pinned reveal's backing and z-order outlive its motion.
            if !self.isRailRevealPresented { self.hideRailRevealLayers() }
            // A Window margin change made mid-transition was skipped.
            self.applyWindowMargin()
            // Settle the Flow 05 collapse cross-fade (if this transition
            // mounted one) back down to the cheap single-tree steady state —
            // see `applyCollapseCrossfadeSidebarView`'s doc comment on why
            // it's never left mounted permanently.
            if self.isCollapseCrossfadeHosted {
                self.isCollapseCrossfadeHosted = false
                self.applySidebarView()
            }
            // The resize reclamp in `layout()` was deferred for the duration of
            // this animation. Force one more layout pass now that the flag is
            // clear, or a window shrink that happened mid-animation may never
            // get re-clamped.
            self.needsLayout = true
        }

        if reduceMotion {
            // Flow 05 "Reduced motion": drop the translate entirely — layout
            // snaps — and carry the change with a single gentler 120ms
            // opacity cross-fade instead of the full spatial motion.
            //
            // The geometry snap deliberately does NOT go through
            // `NSAnimationContext` at all (not even `duration = 0`):
            // `.animator()` on an `NSLayoutConstraint` inside a zero-duration
            // animation context is a known-fragile combination — AppKit can
            // commit the underlying transaction before every constraint in
            // the batch has been folded into one `layoutIfNeeded()` pass,
            // leaving the view showing a half-applied mix of old/new
            // constants (traffic lights + old sidebar content peeking
            // through a too-narrow card — the exact shape of the bug Sean
            // caught). `animated: false` sets `.constant` directly and the
            // explicit `layoutSubtreeIfNeeded()` right after is the ONE
            // atomic layout pass that guarantees a clean settle. The alpha
            // half still animates on its own 120ms cross-fade.
            applyTransitionConstraints(for: newMode, inset: inset, write: { $0.constant = $1 }, updatesWidthModel: !morphs)
            if pinsReveal && !pinsOverlayReveal { railRevealBackingGutter.constant = 0 }
            layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = WorkspaceLayout.sidebarTransitionAlphaDuration(reduceMotion: true, timing: timing)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                applyTransitionAlphas(for: newMode)
            }, completionHandler: animationCompletion)
            if pinsReveal {
                animateRailRevealShadow(to: 0, duration: WorkspaceLayout.sidebarReducedMotionCrossfadeDuration, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
            }
        } else if isCollapsePair {
            // The sidebar ⇄ rail motion: every constraint on one spring
            // (`SidebarMotionDriver`), the morph's leaves on its clock.
            var targets: [(NSLayoutConstraint, CGFloat)] = []
            applyTransitionConstraints(for: newMode, inset: inset, write: { targets.append(($0, $1)) }, updatesWidthModel: !morphs)
            // Push reveal pinned: its backing (hidden) goes back to the rail.
            if pinsReveal && !pinsOverlayReveal { targets.append((railRevealBackingGutter, 0)) }
            applyTransitionAlphas(for: newMode)
            let targetWidth = targets.first { $0.0 === sidebarWidthConstraint }?.1 ?? sidebarWidthConstraint.constant
            let targetGap = targets.first { $0.0 === shadowHostLeadingToSidebar }?.1 ?? shadowHostLeadingToSidebar.constant
            let cardFrom = cardLeadingFromConstraints
            let cardTo = targetWidth + targetGap
            setCardLeadingClamp(min(cardFrom, cardTo)...max(cardFrom, cardTo))
            let shadowFrom = Double(railRevealBacking.layer?.shadowOpacity ?? 0)
            motion.animate(
                targets,
                spring: WorkspaceLayout.sidebarMorphSpring(collapsing: newMode == .collapsed),
                onFrame: pinsReveal ? { [weak self] p in self?.setRailRevealShadow(shadowFrom * (1 - min(max(p, 0), 1))) } : nil,
                completion: animationCompletion
            )
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = timing.duration
                context.timingFunction = timing.curve.mediaTimingFunction
                applyTransitionConstraints(for: newMode, inset: inset, updatesWidthModel: !morphs)
                applyTransitionAlphas(for: newMode)
            }, completionHandler: animationCompletion)
        }
        // 5. Non-animatable properties.
        switch newMode {
        case .pinned, .collapsed:
            terminalContainer.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            terminalShadowHost.layer?.shadowOpacity = WorkspaceLayout.canvasShadowOpacity
            terminalShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
            browserShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
            browserShadowHost.layer?.shadowOpacity = isBrowserVisible ? WorkspaceLayout.canvasShadowOpacity : 0
            layer?.backgroundColor = canvasBackgroundCGColor
            backgroundEffectView.layer?.shadowOpacity = 0
        case .closed:
            // Sean's closed-state layout call (overrides Flow 05 spec §03's
            // full-bleed/radius-18 card): closed keeps the same 8pt-inset,
            // 12pt-radius floating card as pinned — only the sidebar is
            // gone, no chrome, no traffic lights, no header. Same radius
            // token the pinned state uses, not a distinct "closed" radius.
            terminalContainer.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalContainer.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            terminalShadowHost.layer?.shadowOpacity = WorkspaceLayout.canvasShadowOpacity
            terminalShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
            browserShadowHost.layer?.cornerRadius = WorkspaceLayout.terminalCornerRadius
            browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
            browserShadowHost.layer?.shadowOpacity = isBrowserVisible ? WorkspaceLayout.canvasShadowOpacity : 0
            layer?.backgroundColor = canvasBackgroundCGColor
            backgroundEffectView.layer?.shadowOpacity = 0
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
            // The shadow lives on `backgroundEffectView`, not
            // `sidebarOverlayBackground` — the latter is now the opaque,
            // corner-clipped panel content (Flow 01 §04); a shadow defined on
            // a `masksToBounds` layer gets clipped along with everything
            // else outside its bounds, so it has to live on the unclipped
            // sibling that sits directly behind it.
            backgroundEffectView.layer?.shadowOpacity = 0.5
        }

        // 6. Traffic lights.
        setTrafficLightsHidden(newMode == .closed)

        // 7. Refresh tracking areas. Every mode but a fresh close installs
        // its tracking area immediately; closing delays the 24pt hot zone's
        // activation until the close motion has actually finished (Flow 05:
        // "hidden → 24px at 180ms, step") so a fast mouse can't trigger the
        // reveal overlay while the card is still mid-close.
        if newMode == .closed {
            if let area = activeTrackingArea {
                removeTrackingArea(area)
                activeTrackingArea = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceLayout.closedHotZoneActivationDelay) { [weak self] in
                guard let self, self.sidebarMode == .closed else { return }
                self.updateTrackingAreas()
            }
        } else {
            updateTrackingAreas()
        }

        // 8. Persist (overlay is transient — store persists it as .closed).
        store.updateSidebarMode(newMode)

        invalidateIntrinsicContentSize()
    }

    /// Geometry side of a sidebar transition — widths, insets, constraint
    /// constants. Extracted from `transitionTo` so the normal path (one
    /// animated group covering geometry + alpha together) and the reduced-
    /// motion path (geometry snaps at duration 0, alpha cross-fades
    /// separately over 120ms) share one implementation instead of drifting.
    /// `updatesWidthModel: false` for a morph, which has already written
    /// `widthModel.width` inside its own SwiftUI animation
    /// (`beginSidebarMorph`); writing it here, un-animated, would snap the
    /// SwiftUI side while AppKit glides.
    private func applyTransitionConstraints(for newMode: SidebarMode, inset: CGFloat, write: ((NSLayoutConstraint, CGFloat) -> Void)? = nil, updatesWidthModel: Bool = true) {
        // `.animator()` on an `NSLayoutConstraint` only produces a reliable
        // Auto Layout animation inside a real (non-zero-duration) animation
        // context — an `NSAnimationContext` with `duration = 0` wrapping a
        // batch of `.animator().constant` assignments is a known-fragile
        // combination: AppKit can commit the underlying CATransaction before
        // every constraint in the batch has actually been folded into a
        // single `layoutIfNeeded()` pass, so the view can settle on a
        // half-applied mix of old/new constants instead of cleanly snapping.
        // Reduced motion passes a `write` that sets `.constant` directly,
        // bypassing `.animator()` entirely — `transitionTo`
        // follows with one explicit `layoutSubtreeIfNeeded()` outside any
        // animation context, so the snap is a single atomic layout pass.
        // `write` (the Reduce Motion snap, the spring's target list) takes
        // every value; nil animates through `.animator()`.
        func set(_ constraint: NSLayoutConstraint, _ value: CGFloat) {
            if let write {
                write(constraint, value)
            } else {
                constraint.animator().constant = value
            }
        }

        switch newMode {
        case .pinned:
            set(sidebarWidthConstraint, currentSidebarWidth)
            widthModel.expandedWidth = currentSidebarWidth
            if updatesWidthModel { widthModel.width = currentSidebarWidth }
            set(sidebarHostLeadingConstraint, 0)
            set(sidebarHostBottomConstraint, 0)
            set(shadowHostTopConstraint, inset)
            set(shadowHostLeadingToSidebar, WorkspaceLayout.sidebarTrailingGutter(for: .pinned, margin: inset))
            set(sidebarDragHandleWidthConstraint, WorkspaceLayout.sidebarDragHandleWidth(for: .pinned, margin: inset))
            if !isBrowserVisible {
                set(shadowHostTrailingConstraint, -inset)
            }
            set(shadowHostBottomConstraint, -inset)
            // Reference states 01/02: no terminal-card top bar — no
            // header band, no floating toggle/globe buttons. The sidebar
            // toggle lives in the tray; the globe is reachable via Cmd+B.
            set(terminalTopConstraint, 0)
            // Browser insets match terminal.
            set(browserShadowHostTopConstraint, inset)
            set(browserShadowHostBottomConstraint, -inset)
            set(browserShadowHostTrailingConstraint, -inset)

        case .collapsed:
            let railWidth = WorkspaceLayout.collapsedRailWidth(in: self)
            set(sidebarWidthConstraint, railWidth)
            if updatesWidthModel { widthModel.width = railWidth }
            set(sidebarHostLeadingConstraint, 0)
            set(sidebarHostBottomConstraint, 0)
            set(shadowHostTopConstraint, inset)
            set(shadowHostLeadingToSidebar, WorkspaceLayout.sidebarTrailingGutter(for: .collapsed, margin: inset))
            set(sidebarDragHandleWidthConstraint, WorkspaceLayout.sidebarDragHandleWidth(for: .collapsed, margin: inset))
            if !isBrowserVisible {
                set(shadowHostTrailingConstraint, -inset)
            }
            set(shadowHostBottomConstraint, -inset)
            // Reference states 01/02: no terminal-card top bar (see .pinned above).
            set(terminalTopConstraint, 0)
            // Browser insets match terminal.
            set(browserShadowHostTopConstraint, inset)
            set(browserShadowHostBottomConstraint, -inset)
            set(browserShadowHostTrailingConstraint, -inset)

        case .closed:
            // Sean's closed-state layout call: the card keeps its 8pt
            // margin on ALL sides — only the LEFT inset actually moves,
            // from the rail edge (`shadowHostLeadingToSidebar`) to 8pt off
            // the window edge (`shadowHostLeadingToSuperview`, active in
            // this mode per the leading-constraint swap above). Never full
            // bleed — overrides Flow 05's own "card padding-left 8 → 0."
            set(sidebarWidthConstraint, 0)
            set(sidebarHostLeadingConstraint, 0)
            set(sidebarHostBottomConstraint, 0)
            set(shadowHostTopConstraint, inset)
            set(shadowHostLeadingToSuperview, inset)
            if !isBrowserVisible {
                set(shadowHostTrailingConstraint, -inset)
            }
            set(shadowHostBottomConstraint, -inset)
            set(terminalTopConstraint, 0)
            // Browser insets match terminal.
            set(browserShadowHostTopConstraint, inset)
            set(browserShadowHostBottomConstraint, -inset)
            set(browserShadowHostTrailingConstraint, -inset)

        case .overlay:
            // If browser was visible, swap trailing constraint back to window edge.
            if isBrowserVisible {
                shadowHostTrailingToBrowser.isActive = false
                shadowHostTrailingConstraint.isActive = true
                isBrowserVisible = false
                browserDragHandle.isHidden = true
            }
            set(sidebarWidthConstraint, currentSidebarWidth)
            widthModel.width = currentSidebarWidth
            widthModel.expandedWidth = currentSidebarWidth
            // The pinned sidebar, moved off the window edge by the card
            // margin: same width and gutter as pinned, so the list, chips
            // and tray keep their pinned insets inside the overlay card.
            set(sidebarHostLeadingConstraint, inset)
            set(sidebarHostBottomConstraint, -inset)
            applyOverlayPanelInsets(inset)
            set(sidebarDragHandleWidthConstraint, WorkspaceLayout.sidebarDragHandleWidth(for: .overlay, margin: inset))
            // Terminal floats as a carded, inset canvas — same outer inset
            // as pinned/closed. The sidebar (z-order above the card) floats
            // over its left edge rather than sharing space with it.
            set(shadowHostTopConstraint, inset)
            set(shadowHostLeadingToSuperview, inset)
            set(shadowHostTrailingConstraint, -inset)
            set(shadowHostBottomConstraint, -inset)
            set(terminalTopConstraint, 0)
            // Collapse browser in overlay mode.
            set(browserWidthConstraint, 0)
            set(browserShadowHostTopConstraint, 0)
            set(browserShadowHostBottomConstraint, 0)
            set(browserShadowHostTrailingConstraint, 0)
        }
    }

    /// Opacity side of a sidebar transition — sidebar content and overlay-
    /// background alpha, kept separate from `applyTransitionConstraints` so
    /// reduced motion can animate this half (120ms cross-fade) while the
    /// geometry half snaps instantly.
    private func applyTransitionAlphas(for newMode: SidebarMode) {
        sidebarHostingView.animator().alphaValue = newMode == .closed ? 0 : 1
        sidebarOverlayBackground.animator().alphaValue = newMode == .overlay ? 1 : 0
        if newMode == .overlay {
            browserShadowHost.animator().alphaValue = 0
        }
    }

    // MARK: - Rail Hover Reveal

    /// Plays the rail's hover reveal (`RailHoverReveal.onReveal`/`onCollapse`)
    /// on the Cmd+S toggle's own motion: the same one-tree morph
    /// (`beginSidebarMorph`, or the crossfade for layouts that don't morph),
    /// on the same clock (`SidebarMorphClock`, which reads the width
    /// constraint animated below), with the toggle's timing rows — rail ->
    /// sidebar to reveal, sidebar -> rail to collapse — and its Reduce
    /// Motion path (geometry snaps, labels fade 120ms).
    ///
    /// Push (the default "Reveal style"): exactly the toggle's geometry —
    /// the card's gap to the sidebar animates to the pinned gutter with the
    /// width, so the terminal card narrows as it does on Cmd+S. Overlay: the
    /// card holds its x on its own leading constraint while the sidebar
    /// grows over it (`beginRailRevealPresentation`), so the terminal never
    /// resizes. Either way the mode stays `.collapsed` and nothing is
    /// persisted.
    private func setRailRevealed(_ reveal: Bool) {
        guard sidebarMode == .collapsed, reveal != railRevealTarget else { return }
        if reveal {
            railRevealStyle = SidebarDialTuning.hoverRevealStyle()
            beginRailRevealPresentation()
        }
        railRevealTarget = reveal
        widthModel.isOverlaid = reveal

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let from: SidebarMode = reveal ? .collapsed : .pinned
        let to: SidebarMode = reveal ? .pinned : .collapsed
        let inset = SidebarDialTuning.windowMargin()
        let targetWidth = reveal ? currentSidebarWidth : railRevealRestingWidth
        let targetGutter = reveal ? WorkspaceLayout.sidebarTrailingGutter(for: .pinned, margin: inset) : 0
        let pushes = railRevealStyle == .push
        // Push: the card's gap to the sidebar, rail -> pinned and back.
        let cardGap = WorkspaceLayout.sidebarTrailingGutter(for: to, margin: inset)

        let morphs = sidebarBodyMorphs
        if morphs {
            beginSidebarMorph(to: to, reduceMotion: reduceMotion)
        } else {
            applyCollapseCrossfadeSidebarView(previousMode: from, newMode: to, targetWidth: targetWidth, reduceMotion: reduceMotion)
            if reveal { widthModel.expandedWidth = currentSidebarWidth }
        }

        if reveal { installRailRevealClickMonitor() } else { removeRailRevealClickMonitor() }

        isSidebarTransitionAnimating = true
        sidebarTransitionGeneration += 1
        let generation = sidebarTransitionGeneration
        let completion: () -> Void = { [weak self] in
            guard let self, self.sidebarTransitionGeneration == generation else { return }
            self.isSidebarTransitionAnimating = false
            self.widthModel.isMorphing = false
            self.morphClock?.land()
            self.morphClock = nil
            self.setCardLeadingClamp(nil)
            if !self.railRevealTarget { self.endRailRevealPresentation() }
            if self.isCollapseCrossfadeHosted {
                self.isCollapseCrossfadeHosted = false
                self.applySidebarView()
            }
            self.applyWindowMargin()
            self.needsLayout = true
        }

        let shadowOpacity = reveal && !pushes ? WorkspaceLayout.railRevealShadowOpacity : 0
        if reduceMotion {
            // The toggle's Reduce Motion path: the geometry snaps in one
            // layout pass, only the fades play.
            sidebarWidthConstraint.constant = targetWidth
            railRevealBackingGutter.constant = targetGutter
            if pushes { shadowHostLeadingToSidebar.constant = cardGap }
            if !morphs { widthModel.width = targetWidth }
            layoutSubtreeIfNeeded()
            let fade = WorkspaceLayout.sidebarReducedMotionCrossfadeDuration
            animateRailRevealShadow(to: shadowOpacity, duration: fade, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fade
            }, completionHandler: completion)
        } else {
            // The toggle's spring, on the same driver: a reveal reversing
            // mid-flight retargets from where it is, keeping its velocity.
            var targets: [(NSLayoutConstraint, CGFloat)] = [
                (sidebarWidthConstraint, targetWidth),
                (railRevealBackingGutter, targetGutter),
            ]
            if pushes {
                targets.append((shadowHostLeadingToSidebar, cardGap))
                let cardFrom = cardLeadingFromConstraints
                let cardTo = targetWidth + cardGap
                setCardLeadingClamp(min(cardFrom, cardTo)...max(cardFrom, cardTo))
            }
            if !morphs { widthModel.width = targetWidth }
            let shadowFrom = Double(railRevealBacking.layer?.shadowOpacity ?? 0)
            let shadowTo = Double(shadowOpacity)
            motion.animate(
                targets,
                spring: WorkspaceLayout.sidebarMorphSpring(collapsing: !reveal),
                onFrame: pushes ? nil : { [weak self] p in
                    self?.setRailRevealShadow(shadowFrom + (shadowTo - shadowFrom) * min(max(p, 0), 1))
                },
                completion: completion
            )
        }
    }

    /// Starts a reveal's presentation. Overlay lifts the sidebar over the
    /// card: the card moves from the sidebar's trailing edge to a fixed
    /// leading at the x it already has, so the sidebar can grow over it with
    /// no terminal relayout. Push leaves the card on the sidebar's edge.
    private func beginRailRevealPresentation() {
        guard !isRailRevealPresented else { return }
        isRailRevealPresented = true
        railRevealRestingWidth = sidebarWidthConstraint.constant
        // A temporary reveal is not a resize target.
        sidebarDragHandle.isHidden = true
        guard railRevealStyle == .overlay else { return }
        let cardX = sidebarWidthConstraint.constant + shadowHostLeadingToSidebar.constant
        shadowHostLeadingToSuperview.constant = cardX
        shadowHostLeadingToSidebar.isActive = false
        shadowHostLeadingToSuperview.isActive = true
        railRevealBacking.layer?.backgroundColor = canvasBackgroundCGColor
        railRevealBacking.isHidden = false
        railRevealBacking.layer?.zPosition = 99
        sidebarHostingView.layer?.zPosition = 100
    }

    /// Cmd+S while revealed (`transitionTo`): the reveal becomes the pinned
    /// sidebar. The card goes back on the sidebar's trailing edge at the x
    /// it holds now (a negative gap), which `transitionTo` then animates to
    /// the pinned gutter, so the card slides out from under the panel. The
    /// backing and z-order stay until that lands (`hideRailRevealLayers`).
    /// Push: the card is already on the sidebar's edge at the pinned
    /// gutter, so this only ends the reveal's state.
    private func beginPinningRailReveal() {
        let overlays = railRevealOverlays
        let cardX = shadowHostLeadingToSuperview.constant
        isRailRevealPresented = false
        railRevealTarget = false
        widthModel.isOverlaid = false
        removeRailRevealClickMonitor()
        guard overlays else { return }
        shadowHostLeadingToSidebar.constant = cardX - sidebarWidthConstraint.constant
        shadowHostLeadingToSuperview.isActive = false
        shadowHostLeadingToSidebar.isActive = true
    }

    /// A reveal's collapse landed, or the sidebar left the rail another
    /// way: the card goes back on the sidebar's trailing edge (on the rail)
    /// and the reveal's layers go.
    private func endRailRevealPresentation() {
        guard isRailRevealPresented else { return }
        isRailRevealPresented = false
        railRevealTarget = false
        widthModel.isOverlaid = false
        removeRailRevealClickMonitor()
        if sidebarMode == .collapsed {
            // Already the rail's width when a collapse lands; a view-mode
            // switch mid-reveal snaps it there.
            sidebarWidthConstraint.constant = railRevealRestingWidth
            widthModel.width = railRevealRestingWidth
            shadowHostLeadingToSidebar.constant = WorkspaceLayout.sidebarTrailingGutter(for: .collapsed)
            shadowHostLeadingToSuperview.isActive = false
            shadowHostLeadingToSidebar.isActive = true
            sidebarDragHandle.isHidden = false
        }
        railRevealBackingGutter.constant = 0
        hideRailRevealLayers()
    }

    /// Idempotent: safe from every transition's completion.
    private func hideRailRevealLayers() {
        guard !railRevealBacking.isHidden else { return }
        railRevealBacking.layer?.removeAnimation(forKey: "railRevealShadow")
        railRevealBacking.layer?.shadowOpacity = 0
        railRevealBacking.layer?.zPosition = 0
        railRevealBacking.isHidden = true
        railRevealBackingGutter.constant = 0
        if sidebarMode != .overlay { sidebarHostingView.layer?.zPosition = 0 }
    }

    /// The backing's shadow at one frame of the spring, with no implicit
    /// layer animation.
    private func setRailRevealShadow(_ opacity: Double) {
        guard let layer = railRevealBacking.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "railRevealShadow")
        layer.shadowOpacity = Float(opacity)
        CATransaction.commit()
    }

    /// Reduce Motion: the backing's shadow fades on its own 120ms, so it
    /// is never at full strength on the narrow rail.
    private func animateRailRevealShadow(to opacity: Float, duration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        guard let layer = railRevealBacking.layer else { return }
        let from = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        layer.removeAnimation(forKey: "railRevealShadow")
        layer.shadowOpacity = opacity
        guard duration > 0, from != opacity else { return }
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = timingFunction
        layer.add(animation, forKey: "railRevealShadow")
    }

    /// Whether the pointer is over the rail's own width (where it lands
    /// once a reveal collapses).
    private var pointerIsOverRail: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point) && point.x < WorkspaceLayout.collapsedRailWidth(in: self)
    }

    /// While revealed, a mouse-down anywhere outside the revealed panel
    /// collapses it. The click still goes where it was aimed.
    private func installRailRevealClickMonitor() {
        guard railRevealClickMonitor == nil else { return }
        railRevealClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, event.window === self.window, self.railHover.isRevealed else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if !self.railRevealBacking.frame.contains(point) {
                self.railHover.dismiss(pointerInside: false)
            }
            return event
        }
    }

    private func removeRailRevealClickMonitor() {
        if let monitor = railRevealClickMonitor { NSEvent.removeMonitor(monitor) }
        railRevealClickMonitor = nil
    }

    /// The revealed sidebar is drawn over the card (layer z-order) but sits
    /// below it in the subview order AppKit hit-tests by, so clicks over
    /// the panel are routed to it here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit else { return hit }
        let local = convert(point, from: superview)
        // The overlay card's drag handle sits in the card's gutter, over the
        // terminal card. Only a hit the terminal or browser would otherwise
        // take goes to it; anything layered above them (the composer) keeps
        // its click.
        if sidebarMode == .overlay, !sidebarDragHandle.isHidden,
           sidebarDragHandle.frame.contains(local),
           [terminalShadowHost, browserShadowHost].contains(where: { hit === $0 || hit.isDescendant(of: $0) }) {
            return sidebarDragHandle.hitTest(local) ?? hit
        }
        guard railRevealOverlays else { return hit }
        guard railRevealBacking.frame.contains(local) else { return hit }
        let underPanel = [terminalShadowHost, browserShadowHost, sidebarDragHandle, browserDragHandle]
            .contains { hit === $0 || hit.isDescendant(of: $0) }
        guard underPanel else { return hit }
        return sidebarHostingView.hitTest(local) ?? railRevealBacking
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
            let area = NSTrackingArea(
                rect: WorkspaceLayout.closedRevealZone(in: bounds),
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            activeTrackingArea = area

        case .overlay:
            // Install sidebar zone: covers sidebar width.
            let area = NSTrackingArea(
                rect: WorkspaceLayout.overlayRevealZone(
                    in: bounds,
                    sidebarWidth: currentSidebarWidth,
                    margin: SidebarDialTuning.windowMargin()
                ),
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            activeTrackingArea = area

        case .pinned, .collapsed:
            // No tracking areas needed — decision 2: the rail gets no
            // hover-reveal of its own; the only way back to 244pt from a
            // non-pinned state is the closed-mode hot zone above.
            break
        }
    }

    override func mouseEntered(with event: NSEvent) {
        // Only the closed strip's own tracking area (installed from
        // `WorkspaceLayout.closedRevealZone(in:)`) reveals. Subviews
        // forward their mouseEntered up the responder chain to here — the
        // terminal's SurfaceView calls `super.mouseEntered` from a
        // whole-surface tracking area — so without this check entering
        // the terminal anywhere opened the overlay.
        guard sidebarMode == .closed,
              let area = activeTrackingArea, event.trackingArea === area
        else { return }
        transitionTo(.overlay)
    }

    override func mouseExited(with event: NSEvent) {
        // Same rule: only the overlay's own tracking area closes it, never
        // an exit forwarded up from a subview. A sidebar drag holds it
        // open; `endSidebarDrag` closes it if the drag ends outside.
        guard sidebarMode == .overlay,
              let area = activeTrackingArea, event.trackingArea === area,
              sidebarDragPointerWidth == nil
        else { return }
        transitionTo(.closed)
    }

    // MARK: - Window Focus

    @objc private func windowDidResignKey() {
        // A drag whose mouse-up never arrives (the window lost key mid-drag)
        // ends here, so it can't hold any overlay open later.
        if sidebarDragPointerWidth != nil {
            sidebarDragPointerWidth = nil
            persistSidebarWidth()
        }
        if sidebarMode == .overlay {
            transitionTo(.closed)
        }
        // Rail hover reveal: leaving the window collapses a reveal and
        // cancels a pending dwell.
        if sidebarMode == .collapsed {
            railHover.dismiss(pointerInside: false)
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
        store.releaseSnapshot()
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
        store.freezeSnapshot()
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

    // MARK: - Session Switching Shortcuts (Cmd+Shift+[/], Cmd+1-9)

    /// Cmd+Shift+]. Handled here, not in a sidebar view, for the same reason
    /// as Cmd+T: the container exists in every sidebar mode, while each
    /// sidebar view is only mounted in some (the rail replaces the expanded
    /// list when collapsed), and a shortcut observed by an unmounted view
    /// silently does nothing.
    @objc private func handleSelectNextSession(_ notification: Notification) {
        focusShortcutTarget(coordinator.focusAdjacentLiveSession(offset: 1, in: shortcutSessions()))
    }

    /// Cmd+Shift+[. See `handleSelectNextSession(_:)`.
    @objc private func handleSelectPreviousSession(_ notification: Notification) {
        focusShortcutTarget(coordinator.focusAdjacentLiveSession(offset: -1, in: shortcutSessions()))
    }

    /// Cmd+1..8 focuses the Nth listed session; Cmd+9 always the last.
    /// Out of range is a no-op. See `handleSelectNextSession(_:)`.
    @objc private func handleFocusSessionAtIndex(_ notification: Notification) {
        guard let index = notification.userInfo?["index"] as? Int else { return }
        let sessions = shortcutSessions()
        guard let target = index == 9
            ? WorkspaceSidebarView.lastSession(in: sessions)
            : WorkspaceSidebarView.session(at: index, in: sessions)
        else { return }
        coordinator.focusSession(id: target.id)
        focusShortcutTarget(target)
    }

    /// Cmd+W. See `handleSelectNextSession(_:)` for why it's handled here.
    @objc private func handleCloseSession(_ notification: Notification) {
        coordinator.closeCurrentSessionWithConfirmation()
    }

    /// Next Project (Cmd+Ctrl+]). See `handleSelectNextSession(_:)`.
    @objc private func handleSelectNextProject(_ notification: Notification) {
        selectAdjacentProject(offset: 1)
    }

    /// Previous Project (Cmd+Ctrl+[). See `handleSelectNextSession(_:)`.
    @objc private func handleSelectPreviousProject(_ notification: Notification) {
        selectAdjacentProject(offset: -1)
    }

    /// Moves through the sidebar's projects in visual order, wrapping,
    /// starting from THIS window's project: its active session's project,
    /// else the last selected project, else none (selects the first). The
    /// store is shared by every window, so its selection alone would make
    /// one window step from another's project. Selecting a project focuses
    /// its last session, as a click does, and records it in
    /// `store.lastSelectedProjectId` (the list restores from it on mount);
    /// the list mirrors it via `.workspaceDidSelectProjectFromShortcut`.
    private func selectAdjacentProject(offset: Int) {
        let order = store.flatProjectsInVisualOrder
        guard !order.isEmpty else { return }
        let activeProject = coordinator.activeSessionId.flatMap { id in
            store.sessions.first(where: { $0.id == id })?.projectId
        }
        let target: UUID
        if let current = activeProject ?? store.lastSelectedProjectId,
           let index = order.firstIndex(where: { $0.id == current }) {
            target = order[(index + offset + order.count) % order.count].id
        } else {
            target = order[0].id
        }
        ProjectSelection.select(target, store: store, coordinator: coordinator, window: window)
    }

    /// Lets the Projects tab expand and select the focused session's
    /// project — that selection is the list view's own state.
    private func focusShortcutTarget(_ target: AgentSession?) {
        guard let target else { return }
        NotificationCenter.default.post(
            name: .workspaceDidFocusSessionFromShortcut,
            object: window,
            userInfo: ["projectId": target.projectId]
        )
    }

    /// The sessions the switching shortcuts act on, for this container's
    /// current state.
    private func shortcutSessions() -> [AgentSession] {
        let tab = UserDefaults.standard.string(forKey: "ghostties.sidebarTab").flatMap(SidebarTab.init(rawValue:)) ?? .projects
        return Self.shortcutSessions(
            sidebarMode: sidebarMode,
            sidebarViewMode: currentSidebarViewMode,
            sidebarTab: tab,
            projectsLayout: SidebarProjectsLayout.effective(tab: tab),
            store: store,
            coordinator: coordinator
        )
    }

    /// The live sessions in the order the mounted sidebar lists them, so the
    /// shortcuts always agree with what's on screen:
    /// - collapsed: the rail's rows (`WorkspaceStore.railSessions()`), in
    ///   both view modes — the rail replaces whichever list is otherwise up;
    /// - task-first, or the Projects tab: `sessionsInVisualOrder`;
    /// - the Sessions tab: Pinned then Active, as `RecentsListView` renders.
    /// Pinned, overlay and closed all host the full list, so they share it.
    static func shortcutSessions(
        sidebarMode: SidebarMode,
        sidebarViewMode: String,
        sidebarTab: SidebarTab,
        projectsLayout: SidebarProjectsLayout = .tabs,
        store: WorkspaceStore,
        coordinator: SessionCoordinator
    ) -> [AgentSession] {
        if sidebarMode == .collapsed {
            return store.railSessions(layout: projectsLayout).filter { coordinator.hasLiveSurface(id: $0.id) }
        }
        // One view lists exactly the rail's sessions: Pinned, then Active
        // project by project.
        if sidebarViewMode != "taskFirst" && projectsLayout == .oneView {
            return store.railSessions(layout: .oneView).filter { coordinator.hasLiveSurface(id: $0.id) }
        }
        if sidebarViewMode == "taskFirst" || sidebarTab == .projects {
            return store.sessionsInVisualOrder(coordinator: coordinator)
        }
        return WorkspaceSidebarView.sessionsTabCycleOrder(
            sessions: store.sessions,
            statuses: store.globalStatuses,
            coordinator: coordinator
        )
    }

    /// Opens the centered session composer overlay. Called from Cmd+T
    /// (composer preference on, the default) and the sidebar's "+ New
    /// Session" affordances, which reach this via `coordinator.containerView`.
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

        // Single-composer invariant: there is exactly one composer surface
        // (this overlay) and one `SessionComposerStore` behind it, so a
        // second opener can only re-target and refocus the open composer
        // (`SessionComposerStore.open` resets its state and bumps
        // `focusSearchFieldTrigger`); it can never stack another one.
        //
        // Deferred to the next runloop turn so the install below doesn't run
        // inside the caller's own call stack (e.g. a SwiftUI button action).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let request = SessionComposerRequest(projectBinding: projectBinding)
            self.composerOverlayHostingView.rootView = AnyView(
                SessionComposerOverlay(request: request, centeringModel: self.composerCenteringModel)
                    .environmentObject(store)
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
            SessionComposerStore.shared.open(projectBinding: projectBinding, workspaceStore: store)

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
    /// span the whole terminal. Fades in (F8, Phase 3 review) to match
    /// every other appear-over-content transition in this container
    /// (`transitionTo(_:)`'s 0.2s convention). If the view is still
    /// attached (e.g. mid a dismiss fade-out that this call is
    /// interrupting), just animates it back to fully visible instead of
    /// re-adding it.
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
        // consider `alphaValue`, so without this the full-bounds dismiss layer stays
        // fully clickable for the entire 0.2s fade-out. A click into the
        // terminal to resume typing during that window would otherwise land
        // on the invisible dismiss layer's `.onTapGesture { cancel() }` (eating the
        // click and re-entering dismiss, extending the dead window), and a
        // fast double-click on a template row could fire `commit()` twice —
        // a results row's `Button(action:)` calls `option.action()` directly
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
        let store = self.store
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

        _Concurrency.Task {
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
        addSubview(railRevealBacking)
        addSubview(sidebarHostingView)
        addSubview(sidebarDragHandle)
        addSubview(terminalShadowHost)
        addSubview(browserDragHandle)
        addSubview(browserShadowHost)
        addSubview(buildInfoBadgeHostingView)
        addSubview(railHoverZone)
        #if DEBUG
        addSubview(redlineOverlay)
        NSLayoutConstraint.activate([
            redlineOverlay.topAnchor.constraint(equalTo: topAnchor),
            redlineOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            redlineOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            redlineOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        #endif

        sidebarHostingView.translatesAutoresizingMaskIntoConstraints = false

        // Enable layers for z-ordering in overlay mode.
        sidebarHostingView.wantsLayer = true

        // Shadow host (Flow 01 §04): black, offset (12, 0), blur 16 — cast
        // right, onto the terminal. Opacity is toggled per-mode in
        // `transitionTo` (0 except in overlay, where it's 0.5 ≈ `#00000080`).
        backgroundEffectView.wantsLayer = true
        backgroundEffectView.layer?.shadowColor = NSColor.black.cgColor
        backgroundEffectView.layer?.shadowRadius = 16
        backgroundEffectView.layer?.shadowOffset = CGSize(width: 12, height: 0)

        // Opaque panel content: fills with `overlayBackgroundNSColor` — the
        // focused terminal session's own background (Sean's review — light
        // over a light terminal theme, dark over a dark one), falling back
        // to the static canvas token before a surface is observed. This
        // initial value is immediately superseded by `applyChromeColor()`
        // below, which is the real source of truth and repaints on every
        // session swap and theme reload. Radius 18, 1pt stroke `#00000026`,
        // clipped to the rounded rect.
        sidebarOverlayBackground.wantsLayer = true
        sidebarOverlayBackground.layer?.backgroundColor = overlayBackgroundNSColor.cgColor
        sidebarOverlayBackground.layer?.cornerRadius = 18
        sidebarOverlayBackground.layer?.masksToBounds = true
        sidebarOverlayBackground.layer?.borderWidth = 1
        sidebarOverlayBackground.layer?.borderColor = NSColor.black.withAlphaComponent(CGFloat(0x26) / 255.0).cgColor

        // Rail hover reveal's surface: chrome, with the overlay shadow off
        // until a reveal fades it in (`setRailRevealed`).
        railRevealBacking.wantsLayer = true
        railRevealBacking.layer?.backgroundColor = canvasBackgroundCGColor
        railRevealBacking.layer?.shadowColor = NSColor.black.cgColor
        railRevealBacking.layer?.shadowOpacity = 0
        railRevealBacking.layer?.shadowRadius = WorkspaceLayout.railRevealShadowRadius
        railRevealBacking.layer?.shadowOffset = .zero
        railHoverZone.translatesAutoresizingMaskIntoConstraints = false
        railHoverZone.onHoverChanged = { [weak self] inside in
            // Only the rail reveals; every other mode ignores the zone.
            guard let self, self.sidebarMode == .collapsed else { return }
            if inside { self.railHover.pointerEntered() } else { self.railHover.pointerExited() }
        }

        // Terminal lives inside the shadow host. The host carries the shadow;
        // the terminal clips its own corners via masksToBounds.
        terminalShadowHost.addSubview(terminalContainer)
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false

        // Browser panel lives inside browser shadow host.
        browserPanelView.translatesAutoresizingMaskIntoConstraints = false
        browserShadowHost.addSubview(browserPanelView)

        // Read persisted sidebar mode.
        let initialMode = store.sidebarMode
        self.sidebarMode = initialMode
        let isPinned = initialMode == .pinned
        // Pinned and collapsed both push the terminal right and share space
        // with the sidebar; closed/overlay don't.
        let occupiesSpace = initialMode == .pinned || initialMode == .collapsed
        // All four modes show the floating card with insets — overlay floats
        // the sidebar over the same carded terminal rather than a full-bleed one.
        let hasCardInset = true
        let initialWidth: CGFloat = isPinned ? currentSidebarWidth : (initialMode == .collapsed ? WorkspaceLayout.collapsedRailWidth(in: self) : 0)
        sidebarDragHandle.isHidden = !occupiesSpace

        sidebarWidthConstraint = sidebarHostingView.widthAnchor.constraint(equalToConstant: initialWidth)
        // Overlay is never the launch mode (it persists as closed), so the
        // column starts flush with the window.
        sidebarHostLeadingConstraint = sidebarHostingView.leadingAnchor.constraint(equalTo: leadingAnchor)
        sidebarHostBottomConstraint = sidebarHostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        overlayPanelTopConstraint = sidebarOverlayBackground.topAnchor.constraint(equalTo: topAnchor)
        overlayPanelLeadingConstraint = sidebarOverlayBackground.leadingAnchor.constraint(equalTo: leadingAnchor)
        overlayPanelBottomConstraint = sidebarOverlayBackground.bottomAnchor.constraint(equalTo: bottomAnchor)
        overlayPanelTrailingConstraint = sidebarOverlayBackground.trailingAnchor.constraint(equalTo: sidebarHostingView.trailingAnchor)
        sidebarDragHandleTrailingToCard = sidebarDragHandle.trailingAnchor.constraint(equalTo: terminalShadowHost.leadingAnchor)
        sidebarDragHandleTrailingToPanel = sidebarDragHandle.trailingAnchor.constraint(equalTo: sidebarOverlayBackground.trailingAnchor)

        // Closed launches with the same 8pt card margin as every other
        // mode (Sean's closed-state layout call — see `transitionTo`'s
        // `applyTransitionConstraints(for:.closed:)` doc comment); it is
        // never full bleed.
        let inset: CGFloat = SidebarDialTuning.windowMargin()
        applyOverlayPanelInsets(inset)
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
            equalTo: sidebarHostingView.trailingAnchor,
            constant: WorkspaceLayout.sidebarTrailingGutter(for: initialMode, margin: inset))
        // Just under required: while the spring runs, the card's bounds
        // (`cardLeadingFloor`/`Ceiling`) win over the sidebar's overshoot.
        shadowHostLeadingToSidebar.priority = NSLayoutConstraint.Priority(999)
        cardLeadingFloor = terminalShadowHost.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        cardLeadingCeiling = terminalShadowHost.leadingAnchor.constraint(lessThanOrEqualTo: leadingAnchor)
        shadowHostLeadingToSuperview = terminalShadowHost.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: hasCardInset ? inset : 0)
        shadowHostLeadingToSidebar.isActive = occupiesSpace
        shadowHostLeadingToSuperview.isActive = !occupiesSpace
        sidebarDragHandleWidthConstraint = sidebarDragHandle.widthAnchor.constraint(
            equalToConstant: WorkspaceLayout.sidebarDragHandleWidth(for: initialMode, margin: inset))

        // Terminal top offset inside the shadow host. Reference states 01-04
        // all show no terminal-card top bar, so every mode starts at 0 —
        // terminal content begins at the card's top inset directly.
        terminalTopConstraint = terminalContainer.topAnchor.constraint(
            equalTo: terminalShadowHost.topAnchor, constant: 0)

        railRevealBackingGutter = railRevealBacking.trailingAnchor.constraint(equalTo: sidebarHostingView.trailingAnchor)

        NSLayoutConstraint.activate([
            // Rail hover reveal: the backing spans the sidebar plus its
            // gutter, and the hover zone is exactly the backing.
            railRevealBacking.topAnchor.constraint(equalTo: topAnchor),
            railRevealBacking.leadingAnchor.constraint(equalTo: leadingAnchor),
            railRevealBacking.bottomAnchor.constraint(equalTo: bottomAnchor),
            railRevealBackingGutter,
            railHoverZone.topAnchor.constraint(equalTo: topAnchor),
            railHoverZone.leadingAnchor.constraint(equalTo: leadingAnchor),
            railHoverZone.bottomAnchor.constraint(equalTo: bottomAnchor),
            railHoverZone.trailingAnchor.constraint(equalTo: railRevealBacking.trailingAnchor),

            // The overlay card: the window margin off the window's
            // top/left/bottom edges, like the terminal card, and the pinned
            // gutter past the sidebar column (`applyOverlayPanelInsets`).
            // The shadow host behind it shares its frame.
            overlayPanelTopConstraint,
            overlayPanelLeadingConstraint,
            overlayPanelBottomConstraint,
            overlayPanelTrailingConstraint,
            backgroundEffectView.topAnchor.constraint(equalTo: sidebarOverlayBackground.topAnchor),
            backgroundEffectView.leadingAnchor.constraint(equalTo: sidebarOverlayBackground.leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: sidebarOverlayBackground.trailingAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: sidebarOverlayBackground.bottomAnchor),

            sidebarHostingView.topAnchor.constraint(equalTo: topAnchor),
            sidebarHostLeadingConstraint,
            sidebarHostBottomConstraint,
            sidebarWidthConstraint,

            shadowHostTopConstraint,
            shadowHostBottomConstraint,
            shadowHostTrailingConstraint,

            // Terminal fills the shadow host (top offset reserves title bar space).
            terminalTopConstraint,
            terminalContainer.leadingAnchor.constraint(equalTo: terminalShadowHost.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: terminalShadowHost.trailingAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: terminalShadowHost.bottomAnchor),

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

            // Sidebar drag handle: trailing edge on the card's leading edge,
            // width from `sidebarDragHandleWidthConstraint`. Pinned, that is
            // the sidebar-to-card gap; on the rail (no gap, rail A2) it is a
            // strip over the rail's trailing edge. Never over the card.
            // Hidden in overlay/closed.
            sidebarDragHandle.topAnchor.constraint(equalTo: sidebarHostingView.topAnchor),
            sidebarDragHandle.bottomAnchor.constraint(equalTo: sidebarHostingView.bottomAnchor),
            sidebarDragHandleWidthConstraint,
            sidebarDragHandleTrailingToCard,

            // Build-info badge: top-right corner of the whole window, on top
            // of sidebar and terminal alike. Trailing inset clears the DEBUG
            // DialKit collapse pill (12pt padding + 32pt circle + 8pt gap) that
            // `SessionComposerOverlay` pins to the same corner. Unconstrained
            // width/height — the hosting view sizes to its SwiftUI content
            // (`.fixedSize()`).
            buildInfoBadgeHostingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -52),
            buildInfoBadgeHostingView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
        ])

        // Closed launches at the same card radius as every other mode —
        // Sean's closed-state layout call, see `transitionTo`.
        let initialTerminalRadius: CGFloat = WorkspaceLayout.terminalCornerRadius

        // Terminal floating card: top corners rounded when in card mode (pinned/closed).
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.cornerRadius = hasCardInset ? initialTerminalRadius : 0
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
        terminalShadowHost.layer?.cornerRadius = hasCardInset ? initialTerminalRadius : 0
        terminalShadowHost.layer?.cornerCurve = .continuous
        terminalShadowHost.layer?.backgroundColor = hasCardInset ? cardBackgroundCGColor : nil

        // Browser shadow host — identical layer config to terminal shadow host.
        browserShadowHost.wantsLayer = true
        browserShadowHost.layer?.shadowColor = WorkspaceLayout.canvasShadowColor
        browserShadowHost.layer?.shadowOpacity = 0  // hidden initially
        browserShadowHost.layer?.shadowRadius = WorkspaceLayout.canvasShadowRadius
        browserShadowHost.layer?.shadowOffset = WorkspaceLayout.canvasShadowOffset
        browserShadowHost.layer?.cornerRadius = hasCardInset ? initialTerminalRadius : 0
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
            // Spec §03: no chrome at all — sidebar itself is hidden too.
            sidebarHostingView.alphaValue = 0
        }

        // Dismiss the composer overlay's hosting view whenever the composer
        // store closes (Esc, dismiss-layer click, or a successful commit) — every
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
        // (dismiss-layer click, Escape, everything routed through `cancel()`) would
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

        // Show/hide the history browser in the canvas card. `@Published`
        // emits in `willSet`; the main-queue hop lets the sink read the
        // post-write value (same reasoning as the composer sink above).
        coordinator.$isHistoryPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyHistoryPresentation()
            }
            .store(in: &cancellables)

        // Rail hover reveal: an item opened from the revealed sidebar acts,
        // then the sidebar goes back to the rail. On the rail itself the
        // same click cancels a pending dwell.
        coordinator.sidebarItemActivated
            // After the click has finished acting, not inside its handler.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.sidebarMode == .collapsed else { return }
                self.railHover.dismiss(pointerInside: self.pointerIsOverRail)
            }
            .store(in: &cancellables)
    }

    /// Mounts the history browser over the terminal, inside the canvas card,
    /// while History is selected; unmounts it otherwise. Focus goes to the
    /// browser on open; on close `SessionCoordinator.dismissHistory()` hands
    /// it back to the previously selected session's terminal.
    private func applyHistoryPresentation() {
        if coordinator.isHistoryPresented {
            guard historyHostingView.superview == nil else { return }
            historyHostingView.rootView = AnyView(
                HistoryCanvasHost()
                    .environmentObject(store)
                    .environmentObject(coordinator)
            )
            terminalShadowHost.addSubview(historyHostingView, positioned: .above, relativeTo: terminalContainer)
            NSLayoutConstraint.activate([
                historyHostingView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                historyHostingView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                historyHostingView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                historyHostingView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            ])
            window?.makeFirstResponder(historyHostingView)
        } else {
            guard historyHostingView.superview != nil else { return }
            historyHostingView.removeFromSuperview()
            historyHostingView.rootView = AnyView(EmptyView())
        }
    }

    #if DEBUG
    /// Test seam: whether the history browser is mounted in the canvas.
    var isHistoryBrowserMountedForTesting: Bool { historyHostingView.superview != nil }

    /// Test seam: whether the window's first responder (e.g. the query
    /// field's editor) lives inside the mounted history browser.
    var historyBrowserHasKeyFocusForTesting: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: historyHostingView)
    }
    #endif

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

    /// Repaint the chrome/canvas layers and the reveal overlay panel. The
    /// terminal/browser cards and the outer layer use the static Ghostties
    /// design-system palette (canvas/chrome tone) — terminal theme is
    /// intentionally NOT bound there. The focused-surface Combine
    /// subscription still drives this on session swaps and config changes —
    /// for those three layers it's effectively a no-op repaint with static
    /// tokens, but left in place to preserve the session-swap invalidation
    /// path with minimal churn.
    ///
    /// The reveal overlay panel (`sidebarOverlayBackground`) is the one
    /// layer that IS theme-bound: it always repaints here, in every mode,
    /// with `overlayBackgroundNSColor` — the focused terminal session's own
    /// background (falling back to the static canvas token with no surface
    /// focused, e.g. a browser pane) — so it's already correct the next
    /// time overlay mode shows it, matching light-terminal/light-panel,
    /// dark-terminal/dark-panel (Sean's review). `sidebarHostingView`'s
    /// appearance is overridden to match that same fill's luminance while
    /// overlay mode is active, so its SwiftUI text/icon tokens
    /// (`sectionHeaderForeground(for:)` and friends, which read
    /// `@Environment(\.colorScheme)`) stay legible against it; outside
    /// overlay mode the override is cleared so the sidebar follows the OS
    /// appearance as usual.
    ///
    /// The rest of this function no-ops in overlay mode, which intentionally
    /// clears the card/canvas layers to let the vibrancy material show
    /// through.
    private func applyChromeColor() {
        sidebarOverlayBackground.layer?.backgroundColor = overlayBackgroundNSColor.cgColor
        sidebarHostingView.appearance = sidebarAppearanceOverride
        guard sidebarMode == .pinned || sidebarMode == .closed || sidebarMode == .collapsed else { return }
        terminalShadowHost.layer?.backgroundColor = cardBackgroundCGColor
        browserShadowHost.layer?.backgroundColor = browserCardBackgroundCGColor
        layer?.backgroundColor = canvasBackgroundCGColor
        railRevealBacking.layer?.backgroundColor = canvasBackgroundCGColor
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
    /// Called on mouseDown, before any drag delta. Unused (nil) by the browser handle.
    var onDragStart: (() -> Void)?

    /// Called during mouseDragged with the horizontal delta (positive = rightward).
    var onDrag: ((CGFloat) -> Void)?

    /// Called on mouseUp, after the drag ends. Used by the sidebar handle to
    /// persist the final width; unused (nil) by the browser handle.
    var onDragEnd: (() -> Void)?

    /// Views the handle overlays, topmost first. Scrolling over the handle
    /// is forwarded to the deepest hit view among them, and a click over a
    /// scroller among them falls through to it. Empty for handles that
    /// overlap nothing (the browser handle, the pinned sidebar handle).
    var viewsBeneath: () -> [NSView] = { [] }

    /// Track the last mouse X position during a drag.
    private var lastDragX: CGFloat = 0

    /// The deepest view beneath the handle at `point` (in the superview's
    /// coordinates, the space `hitTest` receives), or nil.
    private func viewBeneath(at point: NSPoint) -> NSView? {
        for view in viewsBeneath() {
            guard let parent = view.superview else { continue }
            if let hit = view.hitTest(parent.convert(point, from: superview)) { return hit }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view = viewBeneath(at: point)
        while let current = view {
            if current is NSScroller { return nil }
            view = current.superview
        }
        return hit
    }

    override func scrollWheel(with event: NSEvent) {
        guard let superview else { return super.scrollWheel(with: event) }
        let point = superview.convert(event.locationInWindow, from: nil)
        if let target = viewBeneath(at: point) {
            target.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

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
        onDragStart?()
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

#if DEBUG
/// Host for the capture script. Each op calls the seam its click or shortcut
/// calls; keys go through `NSWindow.sendEvent`.
extension WorkspaceViewContainer: CaptureScript.Host {
    var isReady: Bool {
        // Fixture seeding is synchronous (`CaptureFixture.makeStore()` builds the
        // store before any window exists), so a key window already means seeded.
        // Don't gate on `!projects.isEmpty`: `VERIFY_FIXTURE_PROJECTS=none` has none.
        window?.isKeyWindow ?? false
    }

    func composerOpen() -> Bool {
        presentComposerOverlay(projectBinding: .open)
        return true
    }

    func rowPlus(project name: String, option: Bool) throws -> Bool {
        let store = self.store
        guard let project = store.projects.first(where: { $0.name == name }) else {
            throw CaptureScript.Failure("rowPlus: no project named '\(name)'")
        }
        // Same route as the row's "+" (`ProjectDisclosureRow.handleNewSession`)
        // and the smoke-hooks launch hook. The sidebar highlight is not moved:
        // that selection is private state in `WorkspaceSidebarView`.
        switch ProjectRowNewSession.action(for: project, optionHeld: option, templates: store.templates) {
        case .openComposer(let binding):
            presentComposerOverlay(projectBinding: binding)
            return true
        case .instantCreate(let template):
            _Concurrency.Task { await coordinator.createQuickSession(for: project, template: template) }
            return false
        }
    }

    func newSession() -> Bool {
        let opens = newSessionOpensComposerPreference
        NotificationCenter.default.post(name: .workspaceNewSession, object: window)
        return opens
    }

    func newSessionInstant() { NotificationCenter.default.post(name: .workspaceNewSessionInstant, object: window) }

    func waitForComposerFocus() async -> Bool {
        func ready() -> Bool {
            window?.firstResponder is ComposerGhostNSTextView && SessionComposerStore.shared.isOpen
        }
        let deadline = Date().addingTimeInterval(CaptureScript.composerFocusTimeout)
        while !ready() {
            guard Date() < deadline else { return false }
            try? await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        // One more beat: the palette's own `onAppear` re-opens the store, and
        // text typed before that lands is wiped. Re-check after it.
        try? await _Concurrency.Task.sleep(for: .milliseconds(100))
        return ready()
    }

    func type(_ text: String) {
        guard let window else { return }
        CaptureScript.type(text, to: window)
    }

    func key(_ spec: CaptureScript.KeySpec) {
        guard let window else { return }
        CaptureScript.send(spec, to: window)
    }

    func setPref(_ value: Bool?) { CaptureScript.applyPref(value) }
}
#endif
