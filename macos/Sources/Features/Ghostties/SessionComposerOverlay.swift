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
/// The card is centered horizontally and top-anchored vertically via
/// ordinary SwiftUI layout, not AppKit constraints: its field's top edge
/// sits at `SessionComposerPalette.fieldTopY` (a third of the way down by
/// default) in every layout, and everything else grows downward from it.
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

    /// The window's width, for cards that size to it (the theme grid).
    @State private var availableWidth: CGFloat?

    var body: some View {
        composerZStack
            .environment(\.composerAvailableWidth, availableWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { availableWidth = geo.size.width }
                        .onChange(of: geo.size.width) { availableWidth = $0 }
                }
            )
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
                    defaults: composerDefaultsForTesting ?? AppDefaults.store,
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

    /// Dismiss layer + top-anchored `SessionComposerPalette`. The palette is
    /// an overlay of the full-size dismiss layer, aligned at the top, so a
    /// taller card (Resume list, theme grid, status strip) grows downward
    /// and can never shift the field.
    private var composerZStack: some View {
        GeometryReader { geo in
            let fieldTopY = SessionComposerPalette.fieldTopY(
                containerHeight: geo.size.height,
                titlebarBand: centeringModel.titlebarBandHeight,
                defaults: composerDefaultsForTesting ?? AppDefaults.store
            )
            dismissLayer
                .overlay(alignment: .top) {
                    SessionComposerPalette(
                        isPresented: isPresented,
                        request: request,
                        tuningDefaultsForTesting: composerDefaultsForTesting,
                        containerFit: ComposerContainerFit(
                            size: geo.size,
                            titlebarBand: centeringModel.titlebarBandHeight,
                            fieldTopY: fieldTopY
                        )
                    )
                    .padding(.top, fieldTopY - SessionComposerPalette.shakeClearance)
                }
                .coordinateSpace(name: ComposerContainerFit.coordinateSpace)
        }
    }

    private var dismissLayer: some View {
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
    }
}

/// The window the composer sits in, as the overlay measured it: what the
/// palette needs to keep the ghost and the list inside it.
struct ComposerContainerFit: Equatable {
    /// The overlay's coordinate space: y 0 is the window's top edge.
    static let coordinateSpace = "ghostties.composerOverlay"

    var size: CGSize
    var titlebarBand: CGFloat
    /// The y of the field card's top edge (`SessionComposerPalette.fieldTopY`).
    var fieldTopY: CGFloat
}

/// Where the composer's field card sits vertically. Pure geometry, no view
/// state, so the clamp is testable without rendering.
enum ComposerVerticalAnchor {
    /// Room left under a full Resume list when the window is short.
    static let defaultBottomMargin: CGFloat = 24

    /// The most height the list under the field may take: from its top
    /// edge (`listTopY`, from the container's top) down to `bottomMargin`
    /// above the container's bottom, less the card's own `listInset` under
    /// the list. Never negative.
    static func listHeightLimit(
        containerHeight: CGFloat,
        listTopY: CGFloat,
        listInset: CGFloat,
        bottomMargin: CGFloat
    ) -> CGFloat {
        max(containerHeight - bottomMargin - listInset - listTopY, 0)
    }

    /// The y of the field card's top edge, from the top of a container
    /// `containerHeight` tall: `fraction` of the height, on a whole point.
    /// A short container moves it up only as far as needed to keep the
    /// field and a full list (`fieldHeight + listHeight`) above
    /// `bottomMargin`. It never goes above `titlebarBand`, and it stays low
    /// enough for the ghost (`ghostClearance` above the card) to clear the
    /// band whenever the field and list still fit; when both can't hold,
    /// the list wins.
    static func fieldTopY(
        containerHeight: CGFloat,
        fraction: CGFloat,
        titlebarBand: CGFloat,
        ghostClearance: CGFloat,
        fieldHeight: CGFloat,
        listHeight: CGFloat,
        bottomMargin: CGFloat
    ) -> CGFloat {
        let lowestThatFits = containerHeight - bottomMargin - fieldHeight - listHeight
        var y = min(containerHeight * fraction, lowestThatFits)
        y = max(y, min(titlebarBand + ghostClearance, lowestThatFits))
        // Rounding down only ever moves the card up, so the list still fits.
        return max(y.rounded(.down), titlebarBand.rounded(.up))
    }
}
