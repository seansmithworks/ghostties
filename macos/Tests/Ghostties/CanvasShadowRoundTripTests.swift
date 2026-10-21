import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// After a light/dark flip the card's shadow must be exactly what a fresh mode
/// transition would install — not just non-zero. Complements the gate in
/// `CanvasShadowAppearanceTests`.
@MainActor
struct CanvasShadowRoundTripTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private struct Shadow: Equatable {
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize
        let color: CGColor?

        init(_ layer: CALayer?) {
            opacity = layer?.shadowOpacity ?? -1
            radius = layer?.shadowRadius ?? -1
            offset = layer?.shadowOffset ?? .zero
            color = layer?.shadowColor
        }
    }

    private func settle(_ container: WorkspaceViewContainer, _ window: NSWindow) {
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        container.layoutSubtreeIfNeeded()
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func flippedShadowEqualsAModeRoundTrip(start: NSAppearance.Name) {
        let store = WorkspaceStore(testingProjects: [])
        store.updateSidebarMode(.pinned)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        defer { window.contentView = nil }

        window.appearance = NSAppearance(named: start)
        settle(container, window)
        window.appearance = NSAppearance(named: start == .aqua ? .darkAqua : .aqua)
        settle(container, window)
        let flipped = Shadow(container.cardLayerForTesting)

        // pinned -> rail -> pinned: the mode transition re-installs the shadow.
        container.toggleSidebar()
        settle(container, window)
        container.toggleSidebar()
        settle(container, window)
        #expect(container.sidebarModeForTesting == .pinned)
        let roundTripped = Shadow(container.cardLayerForTesting)

        #expect(flipped.opacity > 0)
        #expect(flipped == roundTripped, "after flip: \(flipped), after mode round-trip: \(roundTripped)")
    }
}
