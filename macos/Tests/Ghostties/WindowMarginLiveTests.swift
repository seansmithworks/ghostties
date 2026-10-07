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

    private func makeContainer(mode: SidebarMode, realChrome: Bool = false) -> (WorkspaceViewContainer, NSWindow) {
        let store = WorkspaceStore(testingProjects: [])
        store.updateSidebarMode(mode)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: realChrome ? [.titled, .closable, .miniaturizable, .resizable] : [.titled],
                              backing: .buffered, defer: true)
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
        if mode == .pinned {
            #expect(card.minX - container.sidebarFrameForTesting.maxX == margin, "sidebar-to-card gap at \(margin), \(mode)")
        } else if mode == .collapsed {
            // Rail A2: the rail adds no margin on its trailing side. The
            // trailing gap is already the rail's own leadingInset, so the
            // card butts the rail column.
            #expect(card.minX - container.sidebarFrameForTesting.maxX == 0, "rail-to-card gap at \(margin), \(mode)")
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

    // MARK: - Rail A2 spacing (collapsed rail only)

    /// The stock traffic-light cluster as the container sees it:
    /// `closeMinX` is the leading inset, `zoomMaxX` the cluster's far edge.
    private func clusterInContainer(_ container: WorkspaceViewContainer, _ window: NSWindow) throws -> (closeMinX: CGFloat, zoomMaxX: CGFloat) {
        let close = try #require(window.standardWindowButton(.closeButton))
        let zoom = try #require(window.standardWindowButton(.zoomButton))
        return (close.convert(close.bounds, to: container).minX, zoom.convert(zoom.bounds, to: container).maxX)
    }

    /// The canvas card's leading edge sits at `zoomMaxX + leadingInset`, the
    /// same on every Window margin: the rail's trailing side adds no margin
    /// or gutter. Top/right/bottom keep following the dial.
    @Test func collapsedCardLeadingEdgeIsZoomMaxPlusLeadingInset() throws {
        let (container, window) = makeContainer(mode: .collapsed, realChrome: true)
        defer { window.contentView = nil }
        container.layoutSubtreeIfNeeded()
        let cluster = try clusterInContainer(container, window)
        let expectedX = cluster.zoomMaxX + cluster.closeMinX
        for margin: CGFloat in [16, 4, SidebarDialTuning.windowMargin()] {
            container.applyWindowMarginForTesting(margin)
            container.layoutSubtreeIfNeeded()
            let card = container.cardFrameForTesting
            #expect(card.minX == expectedX, "card leading x at margin \(margin): expected \(expectedX) (zoom.maxX \(cluster.zoomMaxX) + leadingInset \(cluster.closeMinX)), got \(card.minX)")
            #expect(container.bounds.maxX - card.maxX == margin, "trailing inset at \(margin)")
            #expect(container.bounds.maxY - card.maxY == margin, "top inset at \(margin)")
            #expect(card.minY - container.bounds.minY == margin, "bottom inset at \(margin)")
        }
    }

    /// Rail content centre == cluster centre, which with the card rule above
    /// equals the rail column's centre. The rail has no trailing gutter.
    @Test func collapsedRailCentreIsTheClusterCentreWithNoTrailingGutter() throws {
        let (container, window) = makeContainer(mode: .collapsed, realChrome: true)
        defer { window.contentView = nil }
        container.layoutSubtreeIfNeeded()
        let cluster = try clusterInContainer(container, window)
        let sidebar = container.sidebarFrameForTesting
        #expect(sidebar.midX == (cluster.closeMinX + cluster.zoomMaxX) / 2, "rail centre \(sidebar.midX) vs cluster centre \((cluster.closeMinX + cluster.zoomMaxX) / 2)")
        #expect(WorkspaceLayout.sidebarTrailingGutter(for: .collapsed) == 0, "the rail adds no trailing gutter")
        #expect(WorkspaceLayout.sidebarTrailingGutter(for: .pinned) == SidebarDialTuning.windowMargin(), "pinned keeps its gutter")
    }
}
