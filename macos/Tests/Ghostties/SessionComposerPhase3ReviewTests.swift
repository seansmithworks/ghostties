import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Regression coverage for the Phase 3 review pass of session-creation-unified
/// (F11). Two things are covered directly:
///
/// - `WorkspaceViewContainer.newSessionOpensComposer(in:)` — the exact
///   absent/true/false resolution the review flagged as "precisely the
///   class of bug this pass was chartered to find."
/// - `SessionComposerStore.resolveCascadeProject(workspaceStore:)` — the
///   smart-default cascade backing both instant-create paths
///   (Cmd+Shift+T, and Cmd+T with the preference off).
@MainActor
struct SessionComposerPhase3ReviewTests {

    // MARK: - Fixtures

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ghostties.phase3review.test.\(UUID().uuidString)")!
    }

    private func makeProject(name: String = "Proj", lastActiveAt: Date? = nil) -> Project {
        Project(name: name, rootPath: "/tmp/\(name)-\(UUID().uuidString)", lastActiveAt: lastActiveAt)
    }

    // MARK: - newSessionOpensComposer(in:)

    @Test func newSessionOpensComposerDefaultsToComposerWhenAbsent() {
        let defaults = makeDefaults()
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == true)
    }

    @Test func newSessionOpensComposerIsComposerWhenExplicitlyTrue() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "ghostties.newSessionOpensComposer")
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == true)
    }

    @Test func newSessionOpensComposerIsInstantWhenExplicitlyFalse() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "ghostties.newSessionOpensComposer")
        #expect(WorkspaceViewContainer.newSessionOpensComposer(in: defaults) == false)
    }

    // MARK: - SessionComposerStore.resolveCascadeProject

    @Test func resolveCascadeProjectReturnsNilWithNoProjects() {
        let store = WorkspaceStore(testingProjects: [], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == nil)
    }

    /// No frontmost-terminal match (no key window in a test process) and no
    /// recorded MRU — falls through to step 3, most-recently-touched.
    @Test func resolveCascadeProjectFallsBackToMostRecentlyTouched() {
        let older = makeProject(name: "Older", lastActiveAt: Date(timeIntervalSince1970: 100))
        let newer = makeProject(name: "Newer", lastActiveAt: Date(timeIntervalSince1970: 200))
        let store = WorkspaceStore(testingProjects: [older, newer], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == newer.id)
    }

    /// A single project with no timestamp still resolves — the cascade's
    /// last-resort `sorted.first` must not silently return nil just because
    /// nothing has a `lastActiveAt` yet.
    @Test func resolveCascadeProjectResolvesSingleProjectWithNoTimestamp() {
        let onlyProject = makeProject(name: "Solo")
        let store = WorkspaceStore(testingProjects: [onlyProject], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        #expect(composerStore.resolveCascadeProject(workspaceStore: store) == onlyProject.id)
    }

    // MARK: - open() idempotency (R10, F4's actual contract)

    /// `WorkspaceViewContainer.presentComposerOverlay` calls `open()`
    /// explicitly rather than relying on `onAppear` re-firing (F4). This
    /// locks the contract that call depends on: a second `open()` while
    /// already open resets `searchText`, sets `focusSearchFieldTrigger` (so
    /// Cmd+T-while-open refocuses the field instead of doing nothing), and
    /// updates `currentProjectBinding` to the new call's binding — fully
    /// testable via the isolated store, no `WorkspaceViewContainer`
    /// construction needed.
    @Test func openWhileAlreadyOpenResetsSearchAndSetsFocusTrigger() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let store = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        composerStore.open(projectBinding: .locked(projectA), workspaceStore: store)
        #expect(composerStore.isOpen == true)
        #expect(composerStore.focusSearchFieldTrigger == false)

        composerStore.searchText = "abc"

        composerStore.open(projectBinding: .locked(projectB), workspaceStore: store)

        #expect(composerStore.isOpen == true)
        #expect(composerStore.searchText == "")
        #expect(composerStore.focusSearchFieldTrigger == true)
        if case .locked(let project) = composerStore.currentProjectBinding {
            #expect(project.id == projectB.id)
        } else {
            Issue.record("expected .locked(projectB) after the second open() call")
        }
    }

    /// The FIRST open() (nothing was open before) must NOT set the refocus
    /// trigger — that's specifically the "re-invoke while already open"
    /// signal, not a general side effect of opening.
    @Test func firstOpenDoesNotSetFocusTrigger() {
        let project = makeProject(name: "Solo")
        let store = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = SessionComposerStore(isolatedForTesting: ())

        composerStore.open(projectBinding: .locked(project), workspaceStore: store)

        #expect(composerStore.focusSearchFieldTrigger == false)
    }

    // MARK: - AppKit accessibility-hidden round trip (R9)
    //
    // `WorkspaceViewContainer.sidebarHostingView`/`terminalShadowHost` are
    // `private` NSViews on a class that needs a live `Ghostty.App` +
    // `TerminalViewModel` to construct — no test in this codebase does that
    // (confirmed by search). This locks the underlying AppKit contract
    // `installComposerOverlayIfNeeded()`/`dismissComposerOverlayIfPresented()`
    // rely on (`setAccessibilityHidden`/`isAccessibilityHidden` round-trip
    // correctly on a plain `NSView`) rather than the exact call site.

    @Test @MainActor func accessibilityHiddenRoundTripsOnPlainNSView() {
        let view = NSView()
        #expect(view.isAccessibilityHidden() == false)

        view.setAccessibilityHidden(true)
        #expect(view.isAccessibilityHidden() == true)

        view.setAccessibilityHidden(false)
        #expect(view.isAccessibilityHidden() == false)
    }

    // MARK: - TransparentHostingView.isHitTestDisabled (R3 verification)
    //
    // Direct, executed proof — not just reasoning from source — that a
    // `TransparentHostingView` with `isHitTestDisabled = true` is actually
    // excluded from hit-testing, and that the default (`false`) behaves
    // exactly like a normal `NSHostingView` otherwise. This is the R3 fix's
    // load-bearing mechanism: `dismissComposerOverlayIfPresented()` sets
    // this flag before the fade-out starts, specifically because
    // `alphaValue` fading does NOT affect hit-testing on its own.

    @Test @MainActor func hitTestDisabledExcludesViewFromHitTesting() {
        // `NSView.hitTest(_:)`'s point argument is in the SUPERVIEW's
        // coordinate system (Apple's documented contract), and an
        // `NSHostingView` needs an actual window + layout pass before its
        // SwiftUI content establishes a real hit-testing region — a bare
        // off-window instance reports no hit region at all regardless of
        // `isHitTestDisabled`, which would make this test vacuously pass on
        // the `false` branch too. A real (offscreen) window + forced layout
        // is what makes this a genuine proof, matching the container's
        // actual usage — `WorkspaceViewContainer` always has a live window
        // by the time it calls `hitTest` on this view.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView = container
        window.orderFrontRegardless()

        let view = TransparentHostingView(rootView: Color.red)
        view.frame = container.bounds
        container.addSubview(view)
        view.layoutSubtreeIfNeeded()

        let centerPoint = NSPoint(x: 50, y: 50)

        // Default: behaves like any other view — the container's hitTest
        // finds it at a point inside its bounds.
        #expect(container.hitTest(centerPoint) === view)

        view.isHitTestDisabled = true
        #expect(container.hitTest(centerPoint) !== view)

        view.isHitTestDisabled = false
        #expect(container.hitTest(centerPoint) === view)

        window.orderOut(nil)
    }
}
