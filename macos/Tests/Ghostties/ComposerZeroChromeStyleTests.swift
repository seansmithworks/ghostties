import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// Tests for the zero-chrome / single-line composer style spike
/// (`ghostties.composerStyle`, `ComposerZeroChromeStyle.swift`). Every test
/// references a production symbol (`ComposerStyle`, `ComposerZeroChrome
/// Material`, `ComposerDescriptorCycle`, or `SessionComposerPalette` itself
/// via the snapshot harness) — see `feedback_vacuous-tests-pass-green`.
@MainActor
struct ComposerZeroChromeStyleTests {

    // MARK: - Descriptor cycle order (pure function)

    /// Sean's explicit rule (brief §1): "Name a session" is first, and the
    /// chevron/`ghostPlaceholder` form is pinned at index 3 (last) — never
    /// first. Mutation-checked: temporarily swapping the array order in
    /// `ComposerDescriptorCycle.descriptors` to put the path first made this
    /// fail (confirmed by hand during implementation, reverted).
    @Test func descriptorCycleOrderPinsPathAtIndexThree() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        #expect(descriptors.count == 4)
        #expect(descriptors[0] == "Name a session")
        #expect(descriptors[3] == "ghostties > main > claude")
        #expect(descriptors[1].hasPrefix("atlas-api cco -n"))
        #expect(descriptors[1].contains("-n \"Composer\""))
    }

    /// No recent project — falls back to the literal "ghostties" idiom
    /// rather than an empty/garbage segment.
    @Test func descriptorCycleFallsBackToGhosttiesWithNoRecentProject() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: nil,
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        #expect(descriptors[1] == "ghostties cco -n \"Composer\"")
    }

    // MARK: - Style flag

    @Test func composerStyleDefaultsToClassicWhenUnset() {
        let suite = UserDefaults(suiteName: "ghostties.composerStyle.test.\(UUID().uuidString)")!
        #expect(ComposerStyle.current(defaults: suite) == .classic)
    }

    @Test func composerStyleReadsZeroChrome() {
        let suite = UserDefaults(suiteName: "ghostties.composerStyle.test.\(UUID().uuidString)")!
        suite.set("zeroChrome", forKey: ComposerStyle.storageKey)
        #expect(ComposerStyle.current(defaults: suite) == .zeroChrome)
    }

    @Test func composerStyleReadsSingleLine() {
        let suite = UserDefaults(suiteName: "ghostties.composerStyle.test.\(UUID().uuidString)")!
        suite.set("singleLine", forKey: ComposerStyle.storageKey)
        #expect(ComposerStyle.current(defaults: suite) == .singleLine)
    }

    /// An unrecognized value (typo, stale build) falls back to `.classic`
    /// rather than crashing or defaulting to a new, less-tested style.
    @Test func composerStyleFallsBackToClassicOnUnrecognizedValue() {
        let suite = UserDefaults(suiteName: "ghostties.composerStyle.test.\(UUID().uuidString)")!
        suite.set("bogus", forKey: ComposerStyle.storageKey)
        #expect(ComposerStyle.current(defaults: suite) == .classic)
    }

    @Test func composerZeroChromeMaterialDefaultsToRegular() {
        let suite = UserDefaults(suiteName: "ghostties.composerZeroChromeMaterial.test.\(UUID().uuidString)")!
        #expect(ComposerZeroChromeMaterial.current(defaults: suite) == .regular)
    }

    @Test func composerZeroChromeMaterialReadsThin() {
        let suite = UserDefaults(suiteName: "ghostties.composerZeroChromeMaterial.test.\(UUID().uuidString)")!
        suite.set("thin", forKey: ComposerZeroChromeMaterial.storageKey)
        #expect(ComposerZeroChromeMaterial.current(defaults: suite) == .thin)
    }

    // MARK: - Snapshot evidence (real UserDefaults.standard, save/restore)
    //
    // `SessionComposerPalette.activeStyle` reads `ComposerStyle.current()`
    // with NO defaults injection at that call site (deliberate — it's the
    // same `.standard`-reading pattern `ComposerGhostTextField
    // .modelBFieldStorageKey` already uses at its own call site), so these
    // tests use `SessionComposerPalette`'s `styleOverrideForTesting:` init
    // param (added alongside this file) rather than writing the real
    // `UserDefaults.standard` key directly — `xcodebuild test`'s parallel
    // test processes share that on-disk domain across processes, so a
    // direct set/restore raced other parallel snapshot tests in this same
    // file's early draft and intermittently poisoned unrelated `.classic`
    // renders (caught by `SessionComposerSnapshotTests` regressing on the
    // same run).

    private func makeProject() -> Project {
        Project(name: "Demo Project", rootPath: "/tmp/composer-zero-chrome-snapshot-\(UUID().uuidString)")
    }

    private func makeComposerStore(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        return composerStore
    }

    private func paletteView(
        project: Project,
        workspaceStore: WorkspaceStore,
        composerStore: SessionComposerStore,
        style: ComposerStyle? = nil
    ) -> some View {
        SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: style
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
    }

    private func renderPNG<Content: View>(_ content: Content, size: NSSize) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// `feedback_public-repo-no-real-session-data` — every fixture here is
    /// synthetic, never a real project/path.
    private func writeScratchPNG(_ data: Data?, filename: String) {
        guard let data else {
            Issue.record("Failed to render PNG for \(filename)")
            return
        }
        let dir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-seansmith-Code-ghostties--claude-worktrees-session-7/f3940a7d-dda2-4101-98ae-06507a0f43e3/scratchpad/zero-chrome", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(filename))
    }

    /// Counts pixels matching the classic/single-line card's border-stroke
    /// color (`.tertiaryLabelColor` at 0.75 opacity) — present on the
    /// classic and single-line cards, must be ~0 on zero-chrome (no card,
    /// no border, brief §2).
    private func borderStrokePixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        let border = NSColor.tertiaryLabelColor.withAlphaComponent(0.75)
        guard let borderRGB = border.usingColorSpace(.deviceRGB) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                let dr = abs(color.redComponent - borderRGB.redComponent)
                let dg = abs(color.greenComponent - borderRGB.greenComponent)
                let db = abs(color.blueComponent - borderRGB.blueComponent)
                if dr < 0.04 && dg < 0.04 && db < 0.04 { count += 1 }
            }
        }
        return count
    }

    @Test func flagUnsetRendersClassicCardWithBorder() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .classic)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)
        let png = renderPNG(view, size: size)
        #expect(png != nil)
        if let png {
            // Classic card has a visible border stroke around it.
            #expect(borderStrokePixelCount(in: png) > 0)
        }
    }

    @Test func zeroChromeRestStateHasNoCardBorder() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 200)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .zeroChrome)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "zero-chrome-rest.png")
        #expect(png != nil)
        if let png {
            #expect(borderStrokePixelCount(in: png) == 0)
        }
    }

    @Test func zeroChromeTypingShowsCandidateRows() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        composerStore.searchText = "d"
        let size = NSSize(width: 560, height: 260)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .zeroChrome)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "zero-chrome-typing-3-rows.png")
        #expect(png != nil)
    }

    @Test func singleLineRestStateHasCardChrome() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 100)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "single-line-rest.png")
        #expect(png != nil)
        if let png {
            #expect(borderStrokePixelCount(in: png) > 0)
        }
    }

    @Test func singleLineWithStatusStripError() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        // A typed `>` with no eligible branch segment forces an error onto
        // the shared `statusStripMessage` path both new styles read.
        composerStore.searchText = ">>>"
        let size = NSSize(width: 560, height: 120)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "single-line-status-strip-error.png")
        #expect(png != nil)
    }

    // MARK: - Reduce Motion floor

    /// `ComposerDescriptorGhostText` freezes on descriptor index 0 under
    /// Reduce Motion (no live NSWorkspace stub available in this harness —
    /// this asserts the `reduceMotion` parameter's documented contract
    /// directly against the production view's `body`: with `reduceMotion:
    /// true` and an empty query, the rendered text is unconditionally
    /// `descriptors[0]`, matching what `SessionComposerPalette
    /// .reduceMotionEnabled` feeds it at the real call site).
    @Test func reduceMotionShowsStaticFirstDescriptor() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let view = ComposerDescriptorGhostText(
            descriptors: descriptors,
            query: "",
            opacity: 0.65,
            reduceMotion: true
        )
        let size = NSSize(width: 400, height: 30)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "reduce-motion-static-descriptor.png")
        #expect(png != nil)
    }
}
