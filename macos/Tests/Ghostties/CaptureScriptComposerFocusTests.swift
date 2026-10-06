import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// A script's `type` right after `composer.open` must land in the composer's
/// field. The overlay installs on a later runloop turn and the field takes
/// first responder one turn after that, so the runner has to wait. Uses a
/// real `WorkspaceViewContainer`, not a fake host.
@MainActor
@Suite(.serialized)
struct CaptureScriptComposerFocusTests {

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    /// Runs `composer.open` then `type` through the real runner and returns
    /// what reached the composer's search text.
    private func typedText() async -> String {
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel())
        let window = KeyableWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        window.orderFrontRegardless()
        window.makeKey()
        container.layoutSubtreeIfNeeded()

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString)")
        defer {
            SessionComposerStore.shared.cancel()
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: dir)
        }
        await CaptureScript.Runner(host: container, stateDir: dir).run([.composerOpen, .type("switchboard")])
        // Let any late delivery land before reading.
        try? await _Concurrency.Task.sleep(for: .milliseconds(300))
        return SessionComposerStore.shared.searchText
    }

    /// `SessionComposerStore.shared` is process-wide and `ComposerFlowTests.x2`
    /// opens and cancels it concurrently, which can close this test's composer
    /// mid-run. That interference is transient; a missing focus wait loses the
    /// text on every attempt. So: wait for the store to be free, and pass if
    /// any of three attempts lands the whole text.
    @Test func typeAfterComposerOpenLandsInTheField() async {
        var last = ""
        for _ in 0..<3 {
            for _ in 0..<150 where SessionComposerStore.shared.isOpen {
                try? await _Concurrency.Task.sleep(for: .milliseconds(20))
            }
            last = await typedText()
            if last == "switchboard" { break }
        }
        #expect(last == "switchboard")
    }
}
