import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// Gate: the terminal card's drop shadow must survive a light/dark flip.
/// The shadow is set directly on the layer-backed `terminalShadowHost` only
/// in mode transitions; an appearance change must not strip it.
@MainActor
struct CanvasShadowAppearanceTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func settle(_ container: WorkspaceViewContainer, _ window: NSWindow) {
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        container.layoutSubtreeIfNeeded()
    }

    @Test func pinnedCardShadowSurvivesAnAppearanceFlip() {
        let store = WorkspaceStore(testingProjects: [])
        store.updateSidebarMode(.pinned)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        defer { window.contentView = nil }

        window.appearance = NSAppearance(named: .aqua)
        settle(container, window)
        let layer = container.cardLayerForTesting
        #expect(layer != nil)
        let before = layer?.shadowOpacity ?? 0
        #expect(before > 0, "precondition: pinned card casts a shadow before the flip")

        window.appearance = NSAppearance(named: .darkAqua)
        settle(container, window)
        let after = container.cardLayerForTesting?.shadowOpacity ?? 0
        #expect(after > 0, "card shadowOpacity after flipping aqua to darkAqua: \(after), was \(before)")
    }
}
