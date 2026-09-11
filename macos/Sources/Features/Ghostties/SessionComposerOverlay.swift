import SwiftUI

/// Centered composer surfaced by Cmd+T (when the `ghostties.newSessionOpensComposer`
/// preference is on, the default) and the sidebar toolbar's "+ New Session"
/// button (Phase 3 of session-creation-unified — replaces the 28-project
/// toolbar cascade, D7). Lifts `SessionComposerPalette` above the terminal
/// by shadow alone — no dimming (Spotlight/Raycast treatment, Sean's call,
/// shadow-only elevation, PR #132 — supersedes the earlier locked "dims the
/// terminal" decision). Ghostties has only two shadow levels and no modal
/// vocabulary otherwise, so the card carries its own elevated shadow
/// (`SessionComposerPalette`, `.centered` presentation, DESIGN.md §6) to
/// read as "on top of" the terminal instead.
///
/// This view still hosts an invisible dismiss layer beneath the card:
/// click-outside-to-dismiss and the a11y dismiss affordance both depend on
/// having something to hit-test against, so the layer survives as
/// `Color.clear` with an explicit `.contentShape` even though it no longer
/// paints anything.
///
/// Hosted by `WorkspaceViewContainer` via the now-internal
/// `TransparentHostingView`. The hosting NSHostingView is pinned to the
/// container's full bounds (not just centerX/centerY) so this view's
/// dismiss layer spans the full terminal, matching where a click should
/// dismiss the composer — a hosting view sized only to the composer card's
/// own bounds would have nothing wider than the card to hit-test against.
/// The card itself is centered and fixed-width via ordinary SwiftUI layout
/// (`ZStack`'s default center alignment + `.frame(width:)` on
/// `SessionComposerPalette`), not AppKit constraints.
struct SessionComposerOverlay: View {
    let request: SessionComposerRequest

    /// Test seam, same pattern as `SessionComposerPalette
    /// .styleOverrideForTesting` — this view's own `body` reads
    /// `ComposerStyle.current()` from `.standard` with no injection at that
    /// call site (deliberate, matching the palette's documented reasoning);
    /// writing the real `UserDefaults.standard` key directly would race
    /// other parallel Swift Testing processes the same way that comment
    /// warns against, so tests that need to force the zero-chrome branch
    /// through THIS view (not just the palette it hosts) pass this instead.
    var styleOverrideForTesting: ComposerStyle? = nil

    /// Test seam, same shape as `SessionComposerPalette`'s own
    /// `revealPhase` constant-binding pattern used by
    /// `revealPhaseConstantRevealedRendersSettled` — bypasses the `.task`
    /// below's one-run-loop-turn summon race so a hermetic offscreen
    /// render can assert on a SETTLED `.revealed` frame deterministically,
    /// with no dependency on Swift Concurrency actually resuming a
    /// suspended `Task` before the test samples pixels.
    var revealPhaseOverrideForTesting: ComposerRevealPhase? = nil

    /// `titlebarBandHeight` is the only field this model still carries (PR
    /// #132 removed `horizontalOffset` — the composer now centers on the
    /// whole window, not the terminal card, so there's no sidebar-width
    /// offset to apply). Still an `@ObservedObject` since
    /// `WorkspaceViewContainer` writes the fullscreen-derived titlebar
    /// height into this same shared model instance live.
    @ObservedObject var centeringModel: ComposerCenteringModel

    @ObservedObject private var composerStore = SessionComposerStore.shared

    /// Fix round 2: zero-chrome's summon/commit/dismiss motion is driven
    /// from HERE — this is the only thing that knows "one frame after
    /// mount" (`.task` below), and `SessionComposerPalette` writes
    /// `.committing`/`.dismissing` into the SAME binding for the two exit
    /// paths that originate inside it (commit, Esc). Starts `.hidden` so
    /// the summon transition has a real 0→1 to animate — unlike fix
    /// round 1's rejected approach, this can never be observed mid-race by
    /// the offscreen snapshot harness, because that harness always passes
    /// its OWN `.constant(.revealed)` override instead of ever
    /// constructing a real `SessionComposerOverlay`.
    @State private var zeroChromeRevealPhase: ComposerRevealPhase = .hidden

    /// Real state when `revealPhaseOverrideForTesting` is nil (every
    /// production call site); a fixed constant binding when it's set, so
    /// the `.task` below's write is a harmless no-op racing nothing a test
    /// cares about.
    private var revealPhaseBinding: Binding<ComposerRevealPhase> {
        if let revealPhaseOverrideForTesting {
            return .constant(revealPhaseOverrideForTesting)
        }
        return $zeroChromeRevealPhase
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { composerStore.isOpen },
            set: { newValue in
                if !newValue { composerStore.cancel() }
            }
        )
    }

    var body: some View {
        // Fix round (finding 4): the earlier version of this file wrapped
        // EVERY style's body in a `GeometryReader` to reach the window
        // height for zero-chrome's 38%-from-top placement — that changed
        // the `.classic`/`.singleLine` view tree from what shipped on
        // `main` (a plain `ZStack`) for no reason those styles need.
        // `GeometryReader` now applies ONLY on the `.zeroChrome` branch;
        // `.classic`/`.singleLine` render the exact, unwrapped `ZStack`
        // this file had before this spike touched it.
        if (styleOverrideForTesting ?? ComposerStyle.current()) == .zeroChrome {
            GeometryReader { geometry in
                let measure = min(
                    max(geometry.size.width * ComposerZeroChromeTypography.measureFraction, ComposerZeroChromeTypography.measureMin),
                    ComposerZeroChromeTypography.measureMax
                )
                zeroChromeFullBleedWash
                    .overlay(alignment: .top) {
                        SessionComposerPalette(
                            isPresented: isPresented,
                            request: request,
                            revealPhase: revealPhaseBinding,
                            zeroChromeMeasureOverride: measure
                        )
                        // Fix round 2, item 8: field top moved from 38% to
                        // 32% of overlay height to leave room for the
                        // taller 32/44pt block.
                        .padding(.top, geometry.size.height * ComposerZeroChromeTypography.fieldTopFraction)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                // Fix round 2 (Timing board, summon): "one frame after the
                // palette mounts" per the reviewer's exact mechanism — a
                // plain synchronous write here would coincide with the
                // FIRST layout pass (same class of race fix round 1's
                // rejected `onAppear` reset hit), so this yields to the
                // run loop once before flipping the phase. `Task.isCancelled`
                // guards a composer that opens and closes within one frame
                // (theoretically possible, cheap to guard).
                guard revealPhaseOverrideForTesting == nil else { return }
                zeroChromeRevealPhase = .hidden
                await Task.yield()
                guard !Task.isCancelled else { return }
                zeroChromeRevealPhase = .revealed
            }
        } else {
            composerZStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Fix round 2, item 5 (Sean's live look): the wash used to be a small
    /// patch rendered INSIDE `SessionComposerPalette`, sized to the field.
    /// Now it fills the whole window content area, sidebar included.
    ///
    /// Fix round 5 (Sean's live look): "The ghostties app should be
    /// blurred" — the wash's VISUAL reach was still excluding the
    /// titlebar band (traffic lights, tab strip), which read as "not
    /// full". The window has `.fullSizeContentView` (`WorkspaceViewContainer
    /// .swift`), so the content view — and this hosting overlay — already
    /// extends under the titlebar; `ComposerZeroChromeWash` below is now a
    /// separate, full-height layer with NO gesture and `.allowsHitTesting
    /// (false)`, so it paints across the whole window without claiming any
    /// clicks. The titlebar-band EXCLUSION lives ONLY on the second,
    /// invisible `VStack` beneath it — the actual dismiss/tap-target layer,
    /// same F7 reasoning `composerZStack` already established (a
    /// full-height tap target would claim the titlebar's drag region and
    /// traffic-light clicks). That invisible layer IS this composer's
    /// dismiss layer: any tap on it that ISN'T consumed first by the
    /// field/rows overlaid on top (SwiftUI routes a tap to the topmost
    /// hit-testable view, so their own gestures/`Button`s win first)
    /// dismisses, matching "outside means anywhere on the wash below the
    /// titlebar band that is not the field or a row."
    ///
    /// Coverage check (`WorkspaceViewContainer.swift`): the traffic lights
    /// are native `NSWindow` chrome, entirely outside any content view —
    /// no SwiftUI layer can ever paint over them, by design (they must
    /// stay clickable and legible regardless). The "+ New Project" /
    /// "New Session" toolbar row (`WorkspaceSidebarView.titlebarToolbar`)
    /// IS plain SwiftUI content, hosted in `sidebarHostingView` — this
    /// wash's own hosting view, `composerOverlayHostingView`, is
    /// `addSubview`'d onto the SAME container AFTER `sidebarHostingView`
    /// (`WorkspaceViewContainer.swift`, `showComposerOverlay`) and pinned
    /// to the container's full bounds, so plain AppKit z-order already
    /// puts it on top — this fix's full-height reach DOES visually cover
    /// that row. The one titlebar element genuinely out of reach is the
    /// native terminal TAB STRIP added via `NSWindow
    /// .addTitlebarAccessoryViewController` (`TerminalWindow.swift` /
    /// `TitlebarTabsTahoeTerminalWindow.swift`) — an actual titlebar
    /// accessory living in the window's non-content chrome, structurally
    /// outside every content-view hierarchy this overlay can reach. No
    /// content-view SwiftUI change can cover it; the smallest fix would be
    /// window-level (e.g. toggling the accessory's own hidden/alpha state
    /// alongside the composer's reveal phase) and is out of this file's
    /// scope.
    private var zeroChromeFullBleedWash: some View {
        let phase = revealPhaseBinding.wrappedValue
        return ZStack {
            ComposerZeroChromeWash(
                material: ComposerZeroChromeMaterial.current(),
                revealed: phase == .revealed
            )
            .animation(
                zeroChromeWashAnimation(for: phase, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
                value: phase
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: centeringModel.titlebarBandHeight)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        zeroChromeRevealPhase = .dismissing
                        composerStore.cancel()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss session composer")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The exact `.classic`/`.singleLine` tree this file shipped with on
    /// `main` before this spike — dismiss layer + centered
    /// `SessionComposerPalette`, unchanged. `.zeroChrome` no longer uses
    /// this at all (see `zeroChromeFullBleedWash` above, which is now its
    /// OWN dismiss layer) — kept exactly as `main` had it for the other
    /// two styles.
    private var composerZStack: some View {
        ZStack {
            // F7 (Phase 3 review): this layer excludes the titlebar band
            // (traffic lights + drag region) rather than covering the full
            // window height — painting a full-height tap target under the
            // titlebar would claim mouse-down there too, so the window
            // couldn't be dragged by its titlebar while the composer was
            // open, and a click up there would dismiss it instead.
            // `Color.clear` no longer dims the terminal (shadow-only
            // treatment), but it still relies on the explicit
            // `.contentShape(Rectangle())` below to act as a tap target —
            // do not remove it.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: centeringModel.titlebarBandHeight)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Fix round 2 (Timing board, click-outside exit) —
                        // only zero-chrome reads `zeroChromeRevealPhase`;
                        // harmless write for `.classic`/`.singleLine`.
                        if ComposerStyle.current() == .zeroChrome {
                            zeroChromeRevealPhase = .dismissing
                        }
                        composerStore.cancel()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss session composer")
                    .accessibilityAddTraits(.isButton)
            }

            if ComposerStyle.current() != .zeroChrome {
                SessionComposerPalette(isPresented: isPresented, request: request)
            }
        }
    }
}
