import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// On a short window the rail's list scrolls in the region from below the
/// titlebar to the panel's bottom, under the floating tray (Flow 07), with
/// a bottom inset of the tray's reserve so the last tile rests clear of it
/// (Sean's Dev pass, 2026-10-08: a glyph sat above the traffic lights).
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

    @Test func railListScrollsFromTheTitlebarUnderTheTray() throws {
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

        // Runs to the panel's bottom, under the tray (window coordinates
        // run bottom-up).
        #expect(region.minY <= rail.minY + 0.5, "list region bottom \(region.minY) reaches the panel's bottom \(rail.minY)")
        #expect(region.height > 0, "the list region has room")

        // Its content is inset by the tray's reserve at the rail's end, at
        // the rail width the tray sizes its pills from.
        let reserve = MorphTrayReserve.height(progress: 1, railWidth: WorkspaceLayout.collapsedRailWidth(in: container))
        #expect(abs(scrollView.contentInsets.bottom - reserve) <= 0.5,
                "content bottom inset \(scrollView.contentInsets.bottom) is the tray's reserve \(reserve)")

        // So scrolled to the end, the last tile rests above the tray's top.
        let document = try #require(scrollView.documentView)
        let end = document.isFlipped
            ? NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1)
            : NSRect(x: 0, y: 0, width: 1, height: 1)
        for _ in 0..<5 {
            document.scrollToVisible(end)
            container.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let documentBottom = document.convert(document.bounds, to: nil).minY
        let trayTop = rail.minY + reserve
        #expect(documentBottom >= trayTop - 0.5, "content's end \(documentBottom) rests above the tray's top \(trayTop)")

        // The content overflows the region, so it scrolls.
        let content = try #require(scrollView.documentView).frame.height
        let viewport = scrollView.contentView.bounds.height
        #expect(content > viewport, "content \(content) exceeds viewport \(viewport) on a short window")

        // And the rail's width is the rail's: no legacy scroller takes any.
        #expect(!scrollView.hasVerticalScroller || scrollView.scrollerStyle == .overlay,
                "no scroller takes width from the rail")
    }
}
