import SwiftUI

/// Centered composer surfaced by Cmd+T (when the `ghostties.newSessionOpensComposer`
/// preference is on, the default) and the sidebar toolbar's "+ New Session"
/// button (Phase 3 of session-creation-unified — replaces the 28-project
/// toolbar cascade, D7). Wraps `SessionComposerPalette` in a scrim so the
/// card reads as "on top of" the terminal rather than terminal content
/// itself: Ghostties has only two shadow levels and no modal vocabulary, so
/// the overlay shadow alone (0.20/12/0) isn't enough on a busy dark
/// terminal.
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
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { composerStore.cancel() }

            SessionComposerPalette(isPresented: isPresented, request: request)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
