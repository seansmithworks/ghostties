import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The two key-window predicates that decide whether Cmd+T / Cmd+W / Cmd+1-9
/// act on a workspace window (contract row K1). The call sites guard on
/// `NSApp.keyWindow`, so "no key window" is the `guard let` before the
/// predicate; the predicates themselves take a non-optional `NSWindow`.
@MainActor
struct WorkspaceWindowPredicateTests {

    private static let modeKey = "ghostties.sidebarViewMode"

    @MainActor private final class StubViewModel: TerminalViewModel {
        @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()
        @Published var commandPaletteIsShowing = false
        var updateOverlayIsVisible: Bool { false }
    }

    private func workspaceWindow() -> NSWindow {
        let container = WorkspaceViewContainer(ghostty: Ghostty.App(), viewModel: StubViewModel())
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = container
        return window
    }

    private func plainWindow(contentView: NSView? = NSView()) -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = contentView
        return window
    }

    /// Hosted tests use the Dev domain as `.standard`; always restore.
    private func withMode(_ mode: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.modeKey)
        defer {
            if let previous { defaults.set(previous, forKey: Self.modeKey) } else { defaults.removeObject(forKey: Self.modeKey) }
        }
        if let mode { defaults.set(mode, forKey: Self.modeKey) } else { defaults.removeObject(forKey: Self.modeKey) }
        body()
    }

    @Test func projectFirstWorkspaceWindowPassesBoth() {
        let window = workspaceWindow()
        withMode("projectFirst") {
            #expect(AppDelegate.isProjectFirstWorkspaceWindow(window))
            #expect(AppDelegate.isWorkspaceWindow(window))
        }
        // Unset defaults to project-first.
        withMode(nil) {
            #expect(AppDelegate.isProjectFirstWorkspaceWindow(window))
        }
    }

    @Test func taskFirstWorkspaceWindowIsWorkspaceButNotProjectFirst() {
        let window = workspaceWindow()
        withMode("taskFirst") {
            #expect(!AppDelegate.isProjectFirstWorkspaceWindow(window))
            #expect(AppDelegate.isWorkspaceWindow(window))
        }
    }

    @Test func plainTerminalWindowFailsBoth() {
        let window = plainWindow()
        withMode("projectFirst") {
            #expect(!AppDelegate.isProjectFirstWorkspaceWindow(window))
            #expect(!AppDelegate.isWorkspaceWindow(window))
        }
    }

    @Test func settingsStyleWindowFailsBoth() {
        // A hosting-view window, like Settings or other SwiftUI-hosted windows.
        let window = plainWindow(contentView: NSHostingView(rootView: Text("Settings")))
        withMode("projectFirst") {
            #expect(!AppDelegate.isProjectFirstWorkspaceWindow(window))
            #expect(!AppDelegate.isWorkspaceWindow(window))
        }
    }

    @Test func windowWithNoContentViewFailsBoth() {
        let window = plainWindow(contentView: nil)
        withMode("projectFirst") {
            #expect(!AppDelegate.isProjectFirstWorkspaceWindow(window))
            #expect(!AppDelegate.isWorkspaceWindow(window))
        }
    }
}
