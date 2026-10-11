import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// Rail -> closed -> pinned never runs the pinned<->rail crossfade, which used
/// to be the only writer of `isCollapsedPresentation`, so the flag stayed
/// `true` and the settled pinned rows rendered faded labels.
@MainActor
struct SidebarSettledPresentationTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    /// `transitionTo` ignores a second request inside 0.25s.
    private func settle() async {
        try? await _Concurrency.Task.sleep(nanoseconds: 400_000_000)
    }

    @Test func railThenClosedThenPinnedSettlesWithFullLabels() async {
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel())
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        #expect(container.sidebarModeForTesting == .pinned)

        container.toggleSidebar()
        await settle()
        #expect(container.sidebarModeForTesting == .collapsed)
        #expect(container.isCollapsedPresentationForTesting)

        container.toggleSidebarFullyClosed()
        await settle()
        #expect(container.sidebarModeForTesting == .closed)

        container.toggleSidebarFullyClosed()
        await settle()
        #expect(container.sidebarModeForTesting == .pinned)
        #expect(!container.isCollapsedPresentationForTesting)
    }
}
