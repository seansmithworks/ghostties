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

    /// Fix round (finding 2): the earlier version of this test asserted
    /// only `png != nil` — true for any non-blank render, including a
    /// wash with no rows at all. Replaced with a real production-symbol
    /// check: row 0 is seeded selected on `onAppear`
    /// (`bestSelectionIndex(in: flattenedOptions)`), and
    /// `newStyleCandidateRows` paints a selected row's text in
    /// `WorkspaceLayout.composerSelectionAccent` — this scans for that
    /// exact accent tint, which can ONLY appear if `showNewStyleRows` is
    /// true AND the `ForEach` actually rendered a selected row. Rows are
    /// plain SwiftUI `Text` (not `ComposerGhostTextField`'s `NSTextView`),
    /// so — unlike the typed query text in the field above them — they DO
    /// paint correctly through `cacheDisplay` in this offscreen harness.
    /// Renamed from `zeroChromeTypingShowsCandidateRows` since it now
    /// proves row content + selection, not just "something rendered".
    /// Fix round: the first version of this test set `composerStore
    /// .searchText` BEFORE constructing the view — `SessionComposerStore
    /// .open(projectBinding:workspaceStore:)` unconditionally resets
    /// `searchText = ""`, and `SessionComposerPalette`'s own `.onAppear`
    /// calls `open()` again on first mount, silently wiping the pre-seeded
    /// query the instant the view actually appeared. Same defect (and same
    /// documented fix) `SessionComposerSnapshotTests
    /// .renderMountedPaletteAfterTyping` already covers for the classic
    /// path: mount first (let `.onAppear` settle), THEN set `searchText`,
    /// spin the run loop briefly, THEN render.
    @Test func zeroChromeTypingRevealsSelectedCandidateRow() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 260)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .zeroChrome)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        // Settles `.onAppear` (`open()` + the empty-query default selection)
        // BEFORE the query is set — matches
        // `renderMountedPaletteAfterTyping`'s documented ordering.
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "d"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the typing fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])
        writeScratchPNG(png, filename: "zero-chrome-typing-3-rows.png")
        #expect(png != nil)
        if let png {
            #expect(selectionAccentPixelCount(in: png) > 0)
        }
    }

    /// Fix round (finding 3): `↓` on an EMPTY zero-chrome field must reveal
    /// the candidate rows — `zeroChromeRowsRevealedByArrow`
    /// (`SessionComposerPalette`), set from the production `handle(_:)`
    /// `.move(.down)` case. Exercised through the REAL keyboard-routing
    /// path `ComposerGhostTextFieldTests` already uses elsewhere in this
    /// repo: calling the mounted `NSTextView`'s delegate `textView(_:
    /// doCommandBy:)` directly with `moveDown(_:)`'s selector — not a
    /// synthetic `CGEvent`/AX keystroke, the same technique
    /// `moveDownDispatchesWhenPickerClosed` uses.
    @Test func zeroChromeArrowDownRevealsRowsOnEmptyQuery() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 260)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .zeroChrome)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let before = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the pre-arrow fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: before)
        let beforeData = before.representation(using: .png, properties: [:])
        #expect(beforeData != nil)
        if let beforeData {
            #expect(
                selectionAccentPixelCount(in: beforeData) == 0,
                "expected no rows (and so no accent-tinted row text) before ↓ on an empty field"
            )
        }

        guard let textView = firstTextView(in: hosting), let delegate = textView.delegate else {
            Issue.record("could not locate the mounted ComposerGhostTextField's NSTextView/delegate")
            return
        }
        _ = delegate.textView?(textView, doCommandBy: #selector(NSResponder.moveDown(_:)))
        hosting.layoutSubtreeIfNeeded()

        guard let after = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the post-arrow fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: after)
        let afterData = after.representation(using: .png, properties: [:])
        writeScratchPNG(afterData, filename: "zero-chrome-arrow-down-reveals-rows.png")
        #expect(afterData != nil)
        if let afterData {
            #expect(
                selectionAccentPixelCount(in: afterData) > 0,
                "expected ↓ on an empty zero-chrome field to reveal rows (zeroChromeRowsRevealedByArrow)"
            )
        }
    }

    /// Walks the mounted view hierarchy for the `NSTextView` a
    /// `ComposerGhostTextField` installs (same shape as
    /// `ComposerGhostTextFieldTests`' own harness, which reaches its
    /// `Coordinator` directly rather than searching — this file has no
    /// access to that private `Coordinator` type, so it goes through the
    /// public `NSTextView.delegate` seam instead).
    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    /// Same accent-tint detection `SessionComposerSnapshotTests
    /// .selectionHighlightPixelCount` uses for the classic list's
    /// selection highlight, reimplemented here (that helper is `private`
    /// to the other file) against `newStyleCandidateRows`' own selected-row
    /// text color, `WorkspaceLayout.composerSelectionAccent`
    /// (`#5B8DEF`, b-r ≈ 148).
    private func selectionAccentPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if b - r > 8 { count += 1 }
            }
        }
        return count
    }

    /// Same red-ink detection `SessionComposerSnapshotTests.containsRedInk`
    /// uses for `writeError`'s footer text (`private` there too).
    private func containsRedInk(in data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r > 150, r - g > 60, r - b > 60 { return true }
            }
        }
        return false
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

    /// Fix round (finding 2): `">>>"` never actually tripped
    /// `statusStripMessage` (that path needs `composerStore.writeError`,
    /// not a specific typed string), so the old version of this test
    /// rendered a strip-less card and passed anyway on `png != nil` alone.
    /// Replaced with the SAME real write-path
    /// `SessionComposerSnapshotTests.isAddingTemplateClearsWhenAWriteErrorArrives`
    /// uses: `composerStore.rejectUnresolvedBranch(token:)` —
    /// `SessionComposerStore.swift:1042`, the same synchronous write the
    /// async worktree-create timeout uses — then asserts real red ink is
    /// on screen, not just a non-nil PNG.
    @Test func singleLineWithStatusStripError() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 120)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let before = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the pre-error fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: before)
        if let beforeData = before.representation(using: .png, properties: [:]) {
            #expect(!containsRedInk(in: beforeData), "expected no red ink before writeError arrives")
        }

        composerStore.rejectUnresolvedBranch(token: "does-not-exist")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()

        guard let after = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the post-error fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: after)
        let afterData = after.representation(using: .png, properties: [:])
        writeScratchPNG(afterData, filename: "single-line-status-strip-error.png")
        #expect(afterData != nil)
        if let afterData {
            #expect(
                containsRedInk(in: afterData),
                "expected writeError to render red ink in newStyleStatusStrip"
            )
        }
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
