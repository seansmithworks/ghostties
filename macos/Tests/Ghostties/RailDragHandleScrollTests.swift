import AppKit
import Combine
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// The collapsed rail's 8pt resize strip overlays the list's trailing edge.
/// It must not eat trackpad scrolling or the overlay scroller there.
@MainActor
struct RailDragHandleScrollTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func makeScrollableRail() -> (WorkspaceViewContainer, NSWindow) {
        let project = Project(id: UUID(), name: "Proj", rootPath: "/tmp/proj")
        let template = AgentTemplate.defaults[0]
        let sessions: [AgentSession] = (0..<60).map {
            var s = AgentSession(name: "session \($0)", templateId: template.id, projectId: project.id)
            s.isPinned = true  // Pinned rows always render in the rail
            return s
        }
        let store = WorkspaceStore(testingProjects: [project], testingSessions: sessions)
        store.updateSidebarMode(.collapsed)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        for _ in 0..<20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            container.layoutSubtreeIfNeeded()
        }
        return (container, window)
    }

    private func scrollEvent(atWindowPoint p: NSPoint) -> NSEvent {
        let probe = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0)!
        probe.location = .zero
        let base = NSEvent(cgEvent: probe)!.locationInWindow
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0)!
        cg.location = CGPoint(x: p.x - base.x, y: base.y - p.y)
        return NSEvent(cgEvent: cg)!
    }

    /// A point inside the strip, mid-height, in the container's coordinates
    /// (the container fills the window content view).
    /// SwiftUI's rail list has no NSScrollView in the AppKit tree and ignores
    /// synthesized wheel events outside a live window, so the rail's scrollable
    /// content is stood in for by a view covering the sidebar that records the
    /// wheel events it receives, plus an overlay NSScroller on its trailing
    /// edge, which is what an AppKit scroll view puts under the strip.
    private final class WheelSpy: NSView {
        var wheelEvents = 0
        override func scrollWheel(with event: NSEvent) { wheelEvents += 1 }
    }

    private func installRailStandIn(in container: WorkspaceViewContainer) -> (WheelSpy, NSScroller) {
        let host = container.sidebarHostingViewForTesting
        let spy = WheelSpy(frame: host.bounds)
        spy.autoresizingMask = [.width, .height]
        host.addSubview(spy)
        let scroller = NSScroller(frame: NSRect(x: host.bounds.maxX - 12, y: 0, width: 12, height: host.bounds.height / 2))
        scroller.scrollerStyle = .overlay
        scroller.isEnabled = true
        scroller.knobProportion = 0.3
        scroller.autoresizingMask = [.minXMargin]
        spy.addSubview(scroller)
        return (spy, scroller)
    }

    private func stripPoint(_ container: WorkspaceViewContainer) -> NSPoint {
        let h = container.sidebarDragHandleFrameForTesting
        return NSPoint(x: h.midX, y: h.midY)
    }

    @Test func scrollWheelOverTheStripReachesTheRail() throws {
        let (container, window) = makeScrollableRail()
        defer { window.contentView = nil }
        let (spy, _) = installRailStandIn(in: container)
        let p = stripPoint(container)
        let target = try #require(container.hitTest(container.convert(p, to: container.superview)))
        #expect(target !== spy, "the strip, not the rail, takes the wheel (got \(type(of: target)))")
        target.scrollWheel(with: scrollEvent(atWindowPoint: container.convert(p, to: nil)))
        #expect(spy.wheelEvents == 1, "scroll over the strip reached the rail exactly once (target \(type(of: target)))")
    }

    @Test func hitTestOverTheRailScrollerReturnsTheScroller() throws {
        let (container, window) = makeScrollableRail()
        defer { window.contentView = nil }
        let (_, scroller) = installRailStandIn(in: container)
        let inScroller = scroller.convert(NSPoint(x: scroller.bounds.midX, y: scroller.bounds.midY), to: container)
        #expect(container.sidebarDragHandleFrameForTesting.contains(inScroller), "scroller lies under the strip")
        let hit = try #require(container.hitTest(container.convert(inScroller, to: container.superview)))
        #expect(hit === scroller, "hit is the scroller, got \(type(of: hit))")
    }

    /// Away from the scroller the strip still owns clicks and drags.
    @Test func stripStillTakesDragsAwayFromTheScroller() throws {
        let (container, window) = makeScrollableRail()
        defer { window.contentView = nil }
        _ = installRailStandIn(in: container)
        let strip = container.sidebarDragHandleFrameForTesting
        let q = NSPoint(x: strip.midX, y: strip.maxY - 10)  // upper half, scroller is in the lower half
        let hit = try #require(container.hitTest(container.convert(q, to: container.superview)))
        #expect(hit.frame == strip, "hit is the drag handle, got \(type(of: hit)) \(hit.frame)")
    }
}
