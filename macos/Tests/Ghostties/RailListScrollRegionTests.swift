import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// On a short window the rail's list scrolls inside the region between the
/// titlebar and the tray, clipped to it (Sean's Dev pass, 2026-10-08: rows
/// drew under the tray and a glyph sat above the traffic lights).
///
/// Hosts a real `WorkspaceViewContainer` collapsed to the rail, in a short
/// full-size-content window like the app's, on a persistence-disabled
/// `WorkspaceStore` (never `.shared`). Reads the rail's scroll view from the
/// AppKit tree: its frame is the clip region, its document the content.
@MainActor
@Suite(.serialized)
struct RailListScrollRegionTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func makeShortRail(height: CGFloat) -> (WorkspaceViewContainer, NSWindow) {
        let project = Project(name: "p0", rootPath: "~/p0")
        let store = WorkspaceStore(testingProjects: [project])
        for index in 0..<24 {
            let session = store.addSession(name: "s\(index)", templateId: UUID(), projectId: project.id)
            store.updateSessionStatus(id: session.id, status: .running)
        }
        store.updateSidebarMode(.collapsed)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // ARC owns it; `close()` must not release it a second time.
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = container
        window.orderFrontRegardless()
        for _ in 0..<20 {
            container.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return (container, window)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { sub -> [NSScrollView] in
            (sub as? NSScrollView).map { [$0] } ?? scrollViews(in: sub)
        }
    }

    @Test func railListScrollsBetweenTheTitlebarAndTheTray() throws {
        let (container, window) = makeShortRail(height: 500)
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        let host = container.sidebarHostingViewForTesting
        let scrollView = try #require(scrollViews(in: host).first, "the rail's list is in a scroll view")
        let region = scrollView.convert(scrollView.bounds, to: nil)
        let rail = container.convert(container.sidebarFrameForTesting, to: nil)

        // Below the traffic lights.
        let close = try #require(window.standardWindowButton(.closeButton))
        let lights = close.convert(close.bounds, to: nil)
        #expect(region.maxY <= lights.minY, "list region top \(region.maxY) is below the traffic lights' bottom \(lights.minY)")

        // Above the tray (window coordinates run bottom-up).
        let trayTop = rail.minY + SidebarTray.reservedHeight(isVertical: true, railWidth: rail.width)
        #expect(region.minY >= trayTop - 0.5, "list region bottom \(region.minY) is above the tray's top \(trayTop)")
        #expect(region.height > 0, "the list region has room")

        // The content overflows the region, so it scrolls.
        let content = try #require(scrollView.documentView).frame.height
        let viewport = scrollView.contentView.bounds.height
        #expect(content > viewport, "content \(content) exceeds viewport \(viewport) on a short window")

        // And the rail's width is the rail's: no legacy scroller takes any.
        #expect(!scrollView.hasVerticalScroller || scrollView.scrollerStyle == .overlay,
                "no scroller takes width from the rail")
    }
}
