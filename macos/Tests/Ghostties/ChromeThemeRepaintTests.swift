import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The workspace window repaints when `ChromeThemeStore` publishes a theme:
/// its appearance takes the theme's polarity, the chrome and canvas layers
/// take the theme's colours, and the card keeps its shadow (#240: AppKit
/// zeroes `shadowOpacity` on an appearance change, and a theme change is
/// one).
///
/// Synchronous on purpose: the store is process-wide, so this never spins
/// the run loop (which would let another main-actor test run while a
/// non-Ghostties theme is published) and always restores it before
/// returning.
@MainActor
struct ChromeThemeRepaintTests {
    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func rgb(_ cg: CGColor?) -> [Int] {
        guard let cg, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return [] }
        return [ns.redComponent, ns.greenComponent, ns.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func rgb(_ ns: NSColor) -> [Int] { rgb(ns.cgColor) }

    @Test func aDarkThemeOnALightWindowRepaintsTheChromeAndKeepsTheShadow() throws {
        let store = WorkspaceStore(testingProjects: [])
        store.updateSidebarMode(.pinned)
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel(), store: store)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = container
        defer {
            ChromeThemeStore.shared.reset()
            window.contentView = nil
        }
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let before = try #require(container.cardLayerForTesting?.shadowOpacity)
        #expect(before > 0, "precondition: the pinned card casts a shadow")

        let background = NSColor(srgbRed: 40 / 255, green: 42 / 255, blue: 54 / 255, alpha: 1)
        let foreground = NSColor(srgbRed: 248 / 255, green: 248 / 255, blue: 242 / 255, alpha: 1)
        ChromeThemeStore.shared.update(background: background, foreground: foreground)
        let theme = try #require(ChromeThemeStore.shared.current)
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        #expect(theme.polarity == .dark)
        #expect(container.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                "the window content takes the theme's polarity, not the window's aqua")
        #expect(rgb(container.layer?.backgroundColor) == rgb(theme.chrome), "chrome layer")
        #expect(rgb(container.cardLayerForTesting?.backgroundColor) == rgb(background), "card is the terminal bg")
        let after = container.cardLayerForTesting?.shadowOpacity ?? 0
        #expect(after == before, "card shadowOpacity after the theme change: \(after), was \(before)")
        #expect(rgb(container.cardLayerForTesting?.shadowColor) == rgb(ChromeTheme.ghostties(.dark).shadow))

        // Back to no theme: the window's own appearance and the Ghostties pair.
        ChromeThemeStore.shared.reset()
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        #expect(container.appearance == nil)
        #expect(rgb(container.layer?.backgroundColor) == rgb(ChromeTheme.ghostties(.light).chrome))
        #expect((container.cardLayerForTesting?.shadowOpacity ?? 0) == before)
    }

    /// A reload that leaves the terminal's colours alone publishes nothing.
    @Test func unchangedColoursDoNotRepublish() {
        defer { ChromeThemeStore.shared.reset() }
        let background = NSColor(srgbRed: 40 / 255, green: 42 / 255, blue: 54 / 255, alpha: 1)
        let foreground = NSColor(srgbRed: 248 / 255, green: 248 / 255, blue: 242 / 255, alpha: 1)
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ChromeThemeStore.didChange, object: ChromeThemeStore.shared, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        ChromeThemeStore.shared.update(background: background, foreground: foreground)
        ChromeThemeStore.shared.update(background: background, foreground: foreground)
        #expect(posts == 1)
    }
}
