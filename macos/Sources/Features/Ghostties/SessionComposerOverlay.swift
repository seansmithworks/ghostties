import SwiftUI

/// Centered composer surfaced by Cmd+T (when the `ghostties.newSessionOpensComposer`
/// preference is on, the default) and the sidebar toolbar's "+ New Session"
/// button (Phase 3 of session-creation-unified — replaces the 28-project
/// toolbar cascade, D7). Wraps `SessionComposerPalette` in a scrim so the
/// card reads as "on top of" the terminal rather than terminal content
/// itself: Ghostties has only two shadow levels and no modal vocabulary, so
/// the overlay shadow alone (0.20/12/0, applied to the card itself by
/// `SessionComposerPalette` for the `.centered` presentation) isn't enough
/// on a busy dark terminal by itself.
///
/// Scrim: black at 0.25 opacity, dismissed by clicking anywhere on it. This
/// is a locked design decision (docs/plans/session-creation-unified.html,
/// "Yours to decide" — "the centered composer dims the terminal behind it,
/// strawman taken as written") — not a proposal to re-open.
///
/// Hosted by `WorkspaceViewContainer` via the now-internal
/// `TransparentHostingView`. The hosting NSHostingView is pinned to the
/// container's full bounds (not just centerX/centerY) so this view's scrim
/// can actually dim the whole terminal — a hosting view sized only to the
/// composer card's own bounds would have nothing wider than the card to
/// dim against. The card itself is centered and fixed-width via ordinary
/// SwiftUI layout (`ZStack`'s default center alignment + `.frame(width:)`
/// on `SessionComposerPalette`), not AppKit constraints.
struct SessionComposerOverlay: View {
    let request: SessionComposerRequest

    /// Shifts the card's center rightward off the window's center so it
    /// centers on the terminal card instead (Sean's design decision 2,
    /// Phase 3 review) — `WorkspaceViewContainer.terminalCardHorizontalOffset`,
    /// the live sidebar width when pinned, 0 otherwise. Applied as leading
    /// padding on the card only; the scrim stays full-bleed underneath it.
    var horizontalOffset: CGFloat = 0

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
            // F7 (Phase 3 review): the scrim excludes the titlebar band
            // (traffic lights + drag region) rather than covering the full
            // window height. Two problems, one fix: painting a 25%-dimmed
            // rectangle under the titlebar left the traffic lights — which
            // live in the theme frame above this content view — rendering
            // at full brightness inside a dimmed band, and the scrim's own
            // `.contentShape`/`.onTapGesture` claimed mouse-down there too,
            // so the window couldn't be dragged by its titlebar while the
            // composer was open and a click up there dismissed it instead.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: WorkspaceLayout.titlebarSpacerHeight)
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .onTapGesture { composerStore.cancel() }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss session composer")
                    .accessibilityAddTraits(.isButton)
            }

            SessionComposerPalette(isPresented: isPresented, request: request)
                .padding(.leading, horizontalOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
