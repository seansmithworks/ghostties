import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The real `WorkspaceViewContainer`'s teardown paths revert a live theme
/// preview themselves: its own dismiss, and its window closing while it owns
/// the composer. Holds `SharedComposerStoreGate` (the shared store is
/// process-wide) and swaps the store's picker for one with a recording
/// reload hook, so the host app's config is never reloaded.
@MainActor
@Suite(.serialized)
struct ComposerThemePickerTeardownTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private final class Reloads {
        var calls: [GhosttiesThemePicks?] = []
    }

    /// Opens the composer in a real container, previews Gruvbox through a
    /// recording picker, runs `body`, then restores the shared store.
    private func withPreviewingComposer(
        _ body: @MainActor (WorkspaceViewContainer, NSWindow, ComposerThemePickerModel, Reloads) async -> Void
    ) async {
        await withSharedComposerStore {
            let suiteName = "ghostties.tests.themepicker.teardown.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let reloads = Reloads()
            let picker = ComposerThemePickerModel(
                defaults: defaults, reload: { reloads.calls.append($0) },
                appearance: { .dark }, appearanceState: { _ in .ghostties }
            )
            let store = WorkspaceStore(testingProjects: [])
            let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
            let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = container
            container.layoutSubtreeIfNeeded()
            let live = SessionComposerStore.shared.swapThemePickerForTesting(picker)
            defer {
                SessionComposerStore.shared.cancel()
                SessionComposerStore.shared.owningWindow = nil
                SessionComposerStore.shared.swapThemePickerForTesting(live)
                window.contentView = nil
                defaults.removePersistentDomain(forName: suiteName)
            }

            container.presentComposerOverlay(projectBinding: .open)
            let deadline = Date().addingTimeInterval(5)
            while !container.isComposerOverlayPresentedForTesting, Date() < deadline {
                try? await _Concurrency.Task.sleep(for: .milliseconds(20))
            }
            #expect(container.isComposerOverlayPresentedForTesting, "precondition: overlay installed")
            #expect(SessionComposerStore.shared.isOpen, "precondition: composer open")

            picker.sync(text: "theme ", projectNames: [])
            picker.select(5)   // Gruvbox
            #expect(picker.preview.previewing == GhosttiesThemePicks(light: "Gruvbox Light", dark: "Gruvbox Dark"),
                    "precondition: previewing")

            await body(container, window, picker, reloads)
        }
    }

    /// `dismissComposerOverlayIfPresented` (resign-active, a window taking
    /// the composer over) closes the store and reverts directly, and a
    /// second call while the fade runs is a no-op, not a restarted fade.
    @Test func dismissingTheOverlayRevertsThePreviewAndIsIdempotent() async {
        await withPreviewingComposer { container, _, picker, reloads in
            container.dismissComposerOverlayIfPresented()

            #expect(reloads.calls.last == .some(nil), "dismiss must reload the stored picks")
            #expect(picker.preview.previewing == nil)
            #expect(!SessionComposerStore.shared.isOpen)

            let transitions = container.composerOverlayTransitionCountForTesting
            container.dismissComposerOverlayIfPresented()
            // The `$isOpen` sink re-enters the dismiss path on a later turn.
            try? await _Concurrency.Task.sleep(for: .milliseconds(100))
            #expect(container.composerOverlayTransitionCountForTesting == transitions,
                    "a second dismiss restarted the fade")
        }
    }

    /// Closing the window that owns the composer (app still active) reverts
    /// the preview without relying on SwiftUI's `.onDisappear`.
    @Test func closingTheOwningWindowRevertsThePreview() async {
        await withPreviewingComposer { container, window, picker, reloads in
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

            #expect(reloads.calls.last == .some(nil), "window close must reload the stored picks")
            #expect(picker.preview.previewing == nil)
            #expect(!SessionComposerStore.shared.isOpen)
            #expect(!container.isComposerOverlayPresentedForTesting)
        }
    }
}
