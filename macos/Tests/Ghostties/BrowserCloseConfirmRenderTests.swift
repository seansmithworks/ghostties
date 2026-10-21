// PR-asset helper (lives on pr-assets/browser-close-confirm only, never on the PR branch).
import XCTest
import AppKit
import GhosttiesCore
@testable import Ghostty

@MainActor
final class BrowserCloseConfirmRenderTests: XCTestCase {
    func testRenderCloseBrowserAlert() throws {
        let coordinator = SessionCoordinator()
        let id = UUID()
        coordinator.seedBrowserSessionForTesting(id: id)
        defer {
            WorkspaceStore.shared.removeSessionStatus(id: id)
            WorkspaceStore.shared.removeIndicatorState(id: id)
        }
        var captured: (String, String)?
        coordinator.confirmCloseOverrideForTesting = { m, i, _ in captured = (m, i) }
        coordinator.stopSessionWithConfirmation(id: id)
        let (message, info) = try XCTUnwrap(captured)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "Close Browser")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.layout()
        let window = alert.window
        window.layoutIfNeeded()
        let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
        let scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
            pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: "/Users/seansmith/Code/ghostties/.claude/worktrees/agent-aab72813f406d9894/docs/pr-assets/browser-close-confirm/close-browser-alert.png")
        try png.write(to: out)
    }
}
