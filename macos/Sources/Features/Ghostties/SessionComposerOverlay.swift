import SwiftUI

/// Centered composer surfaced by Cmd+T (when the `ghostties.newSessionOpensComposer`
/// preference is on, the default) and the sidebar toolbar's "+ New Session"
/// button (Phase 3 of session-creation-unified — replaces the 28-project
/// toolbar cascade, D7). Lifts `SessionComposerPalette` above the terminal
/// by shadow alone — no dimming (Spotlight/Raycast treatment, Sean's call,
/// shadow-only elevation, PR #132 — supersedes the earlier locked "dims the
/// terminal" decision). Ghostties has only two shadow levels and no modal
/// vocabulary otherwise, so the card carries its own elevated shadow
/// (`SessionComposerPalette`, DESIGN.md §6) to
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

    /// Test seam for the DEBUG tuning control's `@AppStorage` reads/writes
    /// below: production leaves this `nil` and reads real
    /// `UserDefaults.standard`; a test injects an isolated suite so it never
    /// races other parallel Swift Testing processes reading/writing the same
    /// keys (a real, previously-hit failure mode here).
    private let composerDefaultsForTesting: UserDefaults?

    init(
        request: SessionComposerRequest,
        defaultsForTesting: UserDefaults? = nil,
        centeringModel: ComposerCenteringModel
    ) {
        self.request = request
        self.composerDefaultsForTesting = defaultsForTesting
        self.centeringModel = centeringModel
    }

    /// `titlebarBandHeight` is the only field this model still carries (PR
    /// #132 removed `horizontalOffset` — the composer now centers on the
    /// whole window, not the terminal card, so there's no sidebar-width
    /// offset to apply). Still an `@ObservedObject` since
    /// `WorkspaceViewContainer` writes the fullscreen-derived titlebar
    /// height into this same shared model instance live.
    @ObservedObject var centeringModel: ComposerCenteringModel

    @ObservedObject private var composerStore = SessionComposerStore.shared

    private var isPresented: Binding<Bool> {
        Binding(
            get: { composerStore.isOpen },
            set: { newValue in
                if !newValue { composerStore.cancel() }
            }
        )
    }

    var body: some View {
        composerZStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        // DEBUG-only live tuning control (session-7 brief, 2026-09-11).
        // Compiled out of Release entirely; every symbol it touches lives
        // inside this `#if DEBUG` block. `isMarketingCaptureFixtureActive`
        // hides it whenever the marketing capture rig is running.
        .overlay(alignment: .topTrailing) {
            // `ComposerDialKitHost` (inside `ComposerDebugTuningControl`'s
            // macOS-14 branch) owns staying narrow and out of the way.
            if !Self.isMarketingCaptureFixtureActive {
                ComposerDebugTuningControl(
                    defaults: composerDefaultsForTesting ?? .standard,
                    onChange: { composerStore.focusSearchFieldTrigger = true }
                )
                .padding(12)
            }
        }
        #endif
    }

    #if DEBUG
    /// Mirrors `CaptureFixture`'s exact gate (`GHOSTTIES_CAPTURE_FIXTURE=1`
    /// in the launch environment) so the tuning control stays out of
    /// marketing captures. Not `private` — tests assert on this directly,
    /// the exact gate `body` checks above, rather than trying to prove a
    /// `Picker`'s absence via fragile AppKit-backing hierarchy
    /// introspection.
    static var isMarketingCaptureFixtureActive: Bool {
        ProcessInfo.processInfo.environment["GHOSTTIES_CAPTURE_FIXTURE"] == "1"
    }
    #endif

    /// Dismiss layer + centered `SessionComposerPalette`.
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
                        composerStore.cancel()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss session composer")
                    .accessibilityAddTraits(.isButton)
            }

            SessionComposerPalette(
                isPresented: isPresented,
                request: request,
                tuningDefaultsForTesting: composerDefaultsForTesting
            )
        }
    }
}
