import AppKit
import Testing
@testable import Ghostty

@MainActor
struct QuietTestHostTests {
    @Test func hostIsNotARegularApp() {
        #expect(QuietTestHost.isActive)
        #expect(NSApp.activationPolicy() != .regular)
    }

    @Test func workspacePersistenceNeverResolvesDevState() {
        let dir = WorkspacePersistence.directory.standardizedFileURL.path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path
        #expect(!dir.hasPrefix(appSupport + "/Ghostties"))
        #expect(!dir.contains("Ghostties Dev"))
    }

    @Test func orderedFrontWindowsAreParkedOffscreen() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        #expect(!NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "frame \(window.frame)")
    }
}
