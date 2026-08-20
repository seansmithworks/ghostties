import SwiftUI

/// Centered composer surfaced by Cmd+T (when the `ghostties.newSessionOpensComposer`
/// preference is on, the default) and the sidebar toolbar's "+ New Session"
/// button (Phase 3 of session-creation-unified — replaces the 28-project
/// toolbar cascade, D7). Lifts `SessionComposerPalette` above the terminal by
/// shadow alone — no dimming (Spotlight/Raycast treatment, Sean's call,
/// `fix/composer-shadow-no-scrim`, supersedes the earlier locked "dims the
/// terminal" decision). Ghostties has only two shadow levels and no modal
/// vocabulary otherwise, so the card carries its own elevated shadow
/// (`SessionComposerPalette`, `.centered` presentation, DESIGN.md §6) to read
/// as "on top of" the terminal instead.
///
/// This view still hosts an invisible full-bleed layer beneath the card:
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

    /// `titlebarBandHeight` is the only field this model still carries
    /// (`fix/composer-shadow-no-scrim` removed `horizontalOffset` — the
    /// composer now centers on the whole window, not the terminal card, so
    /// there's no sidebar-width offset to apply). Still an `@ObservedObject`
    /// since `WorkspaceViewContainer` writes the fullscreen-derived titlebar
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
        ZStack {
            // F7 (Phase 3 review): this layer excludes the titlebar band
            // (traffic lights + drag region) rather than covering the full
            // window height — painting a full-height tap target under the
            // titlebar would claim mouse-down there too, so the window
            // couldn't be dragged by its titlebar while the composer was
            // open, and a click up there would dismiss it instead.
            // `Color.clear` no longer dims the terminal (shadow-only
            // treatment), but it still needs the explicit `.contentShape`
            // below — an unstyled `Color.clear` doesn't hit-test on its own.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: centeringModel.titlebarBandHeight)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { composerStore.cancel() }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss session composer")
                    .accessibilityAddTraits(.isButton)
            }

            SessionComposerPalette(isPresented: isPresented, request: request)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
