import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The Window margin dial re-applies the terminal card's insets live: no
/// mode change, no relaunch. The margin is passed through the container's
/// seam, never written to the shared dial store, so parallel tests that read
/// the dial are untouched.
@MainActor
struct WindowMarginLiveTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    @Test func cardInsetsFollowTheMarginOnEverySide() {
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel())
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        // The shared store's sidebar mode is whatever an earlier test left;
        // the card's leading edge is measured from the sidebar when it
        // shares the window, else from the window edge.
        let mode = container.sidebarModeForTesting

        for margin: CGFloat in [16, 4, SidebarDialTuning.windowMargin()] {
            container.applyWindowMarginForTesting(margin)
            container.layoutSubtreeIfNeeded()
            let card = container.cardFrameForTesting
            let sidebar = container.sidebarFrameForTesting
            let bounds = container.bounds
            #expect(card.minY - bounds.minY == margin, "bottom inset at \(margin)")
            #expect(bounds.maxY - card.maxY == margin, "top inset at \(margin)")
            #expect(bounds.maxX - card.maxX == margin, "trailing inset at \(margin)")
            if mode == .pinned || mode == .collapsed {
                #expect(card.minX - sidebar.maxX == margin, "sidebar-to-card gap at \(margin)")
            } else {
                #expect(card.minX - bounds.minX == margin, "leading inset at \(margin), \(mode)")
            }
        }
    }
}
