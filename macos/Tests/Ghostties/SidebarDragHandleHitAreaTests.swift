import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The sidebar drag handle stays grabbable whatever gap sits between the
/// sidebar and the canvas card. Rail A2 removed that gap in collapsed mode,
/// so the handle needs a hit strip of its own: the rail's trailing 8pt,
/// ending exactly at the card's leading edge, never over the card.
@MainActor
struct SidebarDragHandleHitAreaTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func makeContainer(mode: SidebarMode) -> (WorkspaceViewContainer, NSWindow) {
        let store = WorkspaceStore(testingProjects: [])
        store.updateSidebarMode(mode)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.contentView = container
        return (container, window)
    }

    @Test func collapsedHandleIsAnEightPointStripEndingAtTheCard() {
        let (container, window) = makeContainer(mode: .collapsed)
        defer { window.contentView = nil }
        container.layoutSubtreeIfNeeded()
        for margin: CGFloat in [16, 4, SidebarDialTuning.windowMargin()] {
            container.applyWindowMarginForTesting(margin)
            container.layoutSubtreeIfNeeded()
            let handle = container.sidebarDragHandleFrameForTesting
            let card = container.cardFrameForTesting
            let rail = container.sidebarFrameForTesting
            #expect(!container.sidebarDragHandleIsHiddenForTesting, "handle shown on the rail")
            #expect(handle.width == 8, "handle width at margin \(margin): \(handle.width)")
            #expect(handle.maxX == card.minX, "handle ends at the card's leading edge at margin \(margin): \(handle.maxX) vs \(card.minX)")
            #expect(!handle.intersects(card), "handle never overlaps the card at margin \(margin)")
            #expect(handle.minX >= rail.minX && handle.maxX <= rail.maxX, "handle sits inside the rail at margin \(margin)")
        }
    }

    /// Pinned is unchanged: the handle fills the window-margin gap between
    /// the sidebar and the card.
    @Test func pinnedHandleFillsTheSidebarToCardGap() {
        let (container, window) = makeContainer(mode: .pinned)
        defer { window.contentView = nil }
        container.layoutSubtreeIfNeeded()
        for margin: CGFloat in [16, 4, SidebarDialTuning.windowMargin()] {
            container.applyWindowMarginForTesting(margin)
            container.layoutSubtreeIfNeeded()
            let handle = container.sidebarDragHandleFrameForTesting
            #expect(handle.minX == container.sidebarFrameForTesting.maxX, "handle starts at the sidebar edge at margin \(margin)")
            #expect(handle.maxX == container.cardFrameForTesting.minX, "handle ends at the card at margin \(margin)")
            #expect(handle.width == margin, "handle width = margin \(margin)")
        }
    }
}
