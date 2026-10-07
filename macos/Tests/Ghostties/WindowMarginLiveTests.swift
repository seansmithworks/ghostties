import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The Window margin dial re-applies the terminal card's insets live: no
/// mode change, no relaunch. Each container runs on its own persistence-
/// disabled store, in a mode the test sets.
@MainActor
struct WindowMarginLiveTests {
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
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        return (container, window)
    }

    private func expectInsets(_ container: WorkspaceViewContainer, _ margin: CGFloat, _ mode: SidebarMode) {
        container.layoutSubtreeIfNeeded()
        let card = container.cardFrameForTesting
        let bounds = container.bounds
        #expect(card.minY - bounds.minY == margin, "bottom inset at \(margin), \(mode)")
        #expect(bounds.maxY - card.maxY == margin, "top inset at \(margin), \(mode)")
        #expect(bounds.maxX - card.maxX == margin, "trailing inset at \(margin), \(mode)")
        if mode == .pinned || mode == .collapsed {
            #expect(card.minX - container.sidebarFrameForTesting.maxX == margin, "sidebar-to-card gap at \(margin), \(mode)")
        } else {
            #expect(card.minX - bounds.minX == margin, "leading inset at \(margin), \(mode)")
        }
    }

    @Test(arguments: [SidebarMode.pinned, .collapsed, .closed])
    func cardInsetsFollowTheMarginOnEverySide(mode: SidebarMode) {
        let (container, window) = makeContainer(mode: mode)
        defer { window.contentView = nil }
        #expect(container.sidebarModeForTesting == mode)
        for margin: CGFloat in [16, 4, SidebarDialTuning.windowMargin()] {
            container.applyWindowMarginForTesting(margin)
            expectInsets(container, margin, mode)
        }
    }

    /// The real path: the dial written to the (isolated) dial store and the
    /// panel's change notification posted. Synchronous on the main actor
    /// from write to removal, so no other main-actor test reads the
    /// temporary value.
    @Test func dialWriteAndNotificationMoveTheCard() {
        let (container, window) = makeContainer(mode: .pinned)
        defer { window.contentView = nil }
        let store = SidebarDialTuning.store
        #expect(store !== UserDefaults.standard, "dial store must be the isolated suite")
        let defaultMargin = SidebarDialTuning.windowMargin()

        store.set(20.0, forKey: SidebarDialTuning.windowMarginKey)
        NotificationCenter.default.post(name: SidebarDialTuning.didChangeNotification, object: nil)
        expectInsets(container, 20, .pinned)

        store.removeObject(forKey: SidebarDialTuning.windowMarginKey)
        NotificationCenter.default.post(name: SidebarDialTuning.didChangeNotification, object: nil)
        expectInsets(container, defaultMargin, .pinned)
    }
}
