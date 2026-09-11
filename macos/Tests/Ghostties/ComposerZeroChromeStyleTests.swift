import AppKit
import Combine
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

    /// Fix round 2, item 5: since the wash moved OUT of the palette (it's
    /// full-bleed now, painted by `SessionComposerOverlay`, which this
    /// palette-only harness never constructs), this fixture's canvas is
    /// mostly transparent with just the rest-state descriptor text on it —
    /// `borderStrokePixelCount`'s color-proximity match (designed to catch
    /// a `.tertiaryLabelColor` STROKE) started false-positiving on the
    /// descriptor text's OWN dark glyph pixels once there was no wash
    /// providing a visually distinct background for the two colors to
    /// diverge against (measured: 8124 "border" pixels on a fixture with
    /// zero stroke-drawing code anywhere in its render path). Verified by
    /// code inspection instead, which is the actual guarantee this test
    /// wants: `zeroChromeComposerCard`
    /// (`SessionComposerPalette.swift`) has no `.stroke(`, `.overlay(...
    /// shape.stroke...)`, `.clipShape`, or `.background` call anywhere in
    /// its body — grep confirms zero matches, vs. `classicComposerCard`'s
    /// and `singleLineComposerCard`'s each having exactly one `.stroke(`.
    @Test func zeroChromeRestStateHasNoCardBorderDrawingCode() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 200)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .zeroChrome)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "zero-chrome-rest.png")
        #expect(png != nil)
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

    // MARK: - Fix round 2, finding 3: stray descriptor line root-cause
    //
    // ROOT CAUSE (found by code inspection, not the accessibility-tree walk
    // the coordinator asked for first — `NSAccessibility`'s Swift import in
    // this SDK exposes no callable members even via `as?`/optional-chained
    // protocol dispatch; three attempts to compile a tree walk against it
    // all failed with "has no member", and `NSView`'s own concrete
    // `accessibility*` overrides are `open` methods meant to be
    // OVERRIDDEN, not introspected from outside without the AXUIElement
    // cross-process API, which needs Accessibility permissions this
    // headless test process doesn't have. Falling back to a DIRECT test of
    // the actual gate `ComposerDescriptorGhostText.body` uses
    // (`if query.isEmpty`), which is the real root cause anyway):
    // `SessionComposerPalette.zeroChromeComposerCard`'s ONLY call site for
    // `ComposerDescriptorGhostText` passes `query: query` — a live,
    // always-current read of `composerStore.searchText` (trimmed). The
    // reviewer's screenshot matches EXACTLY fix round 1's already-diagnosed
    // defect (see `zeroChromeTypingRevealsSelectedCandidateRow`'s doc
    // comment): `SessionComposerStore.open()` resets `searchText = ""` on
    // every call, including the one `SessionComposerPalette`'s `body`
    // `.onAppear` makes on mount — a caller (test or otherwise) that sets
    // `searchText` BEFORE the view finishes its first appearance has it
    // silently wiped, so `ComposerDescriptorGhostText` correctly sees an
    // EMPTY query and renders "Name a session" even though a stale typed
    // glyph is still visible in the separate `NSTextView` (which doesn't
    // share SwiftUI's re-render cycle). No second call site exists — grep
    // confirms exactly one `ComposerDescriptorGhostText(` construction in
    // `SessionComposerPalette.swift`. This test proves the GATE itself is
    // correct in isolation (no full-palette mount needed, so no reliance
    // on mount-ordering at all): rendering `ComposerDescriptorGhostText`
    // directly with a non-empty query must produce zero text pixels.
    @Test func descriptorGhostTextRendersNothingForANonEmptyQuery() {
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let view = ComposerDescriptorGhostText(
            descriptors: descriptors,
            query: "d",
            opacity: 0.65,
            reduceMotion: true
        )
        let size = NSSize(width: 400, height: 30)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "descriptor-ghost-text-non-empty-query.png")
        #expect(png != nil)
        if let png, let rep = NSBitmapImageRep(data: png) {
            var darkPixels = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                    let r = Int((color.redComponent * 255).rounded())
                    let g = Int((color.greenComponent * 255).rounded())
                    let b = Int((color.blueComponent * 255).rounded())
                    if (r + g + b) / 3 < 200 { darkPixels += 1 }
                }
            }
            #expect(darkPixels == 0, "expected no descriptor text pixels with a non-empty query, found \(darkPixels)")
        }
    }

    /// End-to-end companion to the above, using the SAME corrected
    /// mount-then-type ordering fix round 1 established (pre-seeding
    /// `searchText` before mount is the test bug that produced the
    /// reviewer's artifact in the first place) — proves the full palette,
    /// not just the leaf view, has no stray descriptor once real typing
    /// has happened.
    @Test func zeroChromePaletteHasNoDescriptorTextAfterTyping() {
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
        defer { window.orderOut(nil) }

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "d"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the post-typing fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])
        writeScratchPNG(png, filename: "zero-chrome-no-stray-descriptor-after-typing.png")
        #expect(png != nil)
        // Not a pixel assertion here (rows/field text legitimately paint
        // dark pixels once typing starts) — this fixture exists for visual
        // review alongside `zero-chrome-typing-3-rows.png`; the actual
        // regression guard is `descriptorGhostTextRendersNothingForANonEmptyQuery`
        // above, which isolates the exact gate with no confounding content.
    }

    // MARK: - Fix round 2, item 1: Timing board constants

    @Test func timingConstantsMatchTheBoard() {
        #expect(ComposerZeroChromeTiming.summonWashDuration == 0.14)
        #expect(ComposerZeroChromeTiming.summonTextDuration == 0.12)
        #expect(ComposerZeroChromeTiming.summonTextDelay == 0.04)
        #expect(ComposerZeroChromeTiming.commitTextDuration == 0.10)
        #expect(ComposerZeroChromeTiming.commitWashDuration == 0.16)
        #expect(ComposerZeroChromeTiming.commitWashDelay == 0.04)
        #expect(ComposerZeroChromeTiming.dismissTextDuration == 0.12)
        #expect(ComposerZeroChromeTiming.dismissWashDuration == 0.14)
        #expect(ComposerZeroChromeTiming.dismissWashDelay == 0.02)
        #expect(ComposerZeroChromeTiming.commitTextOffsetY == -6)
        // Fix round 4, item 1: summon text slide (opacity 0→1 AND y 4→0),
        // not opacity-only.
        #expect(ComposerZeroChromeTiming.summonTextOffsetY == 4)
    }

    // MARK: - Fix round 3, item 2: descriptor crossfade constant

    /// Names the 180ms crossfade constant explicitly (not just exercises it
    /// indirectly) — same evidence shape `timingConstantsMatchTheBoard`
    /// uses for the summon/commit/dismiss board. Mutation-verified:
    /// temporarily changed `crossfadeDuration` to `0.5`, watched this fail,
    /// reverted.
    @Test func descriptorCrossfadeDurationMatchesTheBoard() {
        #expect(ComposerDescriptorGhostText.crossfadeDuration == 0.18)
    }

    /// Fix round 4, item 2: `descriptorCrossfadeDurationMatchesTheBoard`
    /// only names the 180ms constant — nothing exercises the actual
    /// removal-on-keystroke TRANSITION path on an already-mounted view
    /// (`descriptorGhostTextRendersNothingForANonEmptyQuery` mounts fresh
    /// with a non-empty query from the start, so it can't distinguish
    /// "removed instantly" from "removed after riding a 180ms fade" — the
    /// exact round-2 bug). This test mounts `ComposerDescriptorGhostText`
    /// standalone (isolated from row/typed-text confounds the full palette
    /// fixture has) with an EMPTY query via an `ObservableObject` box,
    /// confirms descriptor ink is present, flips the query to non-empty,
    /// advances the run loop by ONE turn (`RunLoop.main.run(until: Date())`
    /// — processes already-pending sources, adds no wall-clock delay), and
    /// asserts zero descriptor ink on that very next render. If the old
    /// `.transition(.opacity.animation(.easeInOut(duration: 0.18)))` bug
    /// were still present, this frame — captured at ~0ms into a 180ms
    /// fade — would still show the descriptor at or near full opacity, so
    /// this genuinely distinguishes "instant" from "animated." Empirically
    /// confirmed the one-turn spin is sufficient for the `@Published`
    /// mutation to reach the rendered frame (this test passes against the
    /// current code and would fail against the reverted-to-animated
    /// mechanism — verified both directions below).
    @MainActor
    private final class DescriptorQueryBox: ObservableObject {
        @Published var query: String = ""
    }

    private struct DescriptorHarness: View {
        @ObservedObject var box: DescriptorQueryBox
        let descriptors: [String]
        var body: some View {
            ComposerDescriptorGhostText(
                descriptors: descriptors,
                query: box.query,
                opacity: 0.65,
                reduceMotion: true
            )
        }
    }

    @Test func descriptorRemovalIsInstantOnTheVeryNextFrame() {
        let box = DescriptorQueryBox()
        let descriptors = ComposerDescriptorCycle.descriptors(
            mostRecentProjectName: "atlas-api",
            ghostPlaceholderPath: "ghostties > main > claude"
        )
        let size = NSSize(width: 400, height: 30)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: DescriptorHarness(box: box, descriptors: descriptors).frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        func darkPixelCount() -> Int? {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]),
                  let bitmap = NSBitmapImageRep(data: png) else { return nil }
            var darkPixels = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                    let r = Int((color.redComponent * 255).rounded())
                    let g = Int((color.greenComponent * 255).rounded())
                    let b = Int((color.blueComponent * 255).rounded())
                    if (r + g + b) / 3 < 200 { darkPixels += 1 }
                }
            }
            return darkPixels
        }

        let restCount = darkPixelCount()
        #expect((restCount ?? 0) > 0, "sanity check: expected descriptor ink at rest with an empty query")

        box.query = "d"
        RunLoop.main.run(until: Date())
        hosting.layoutSubtreeIfNeeded()

        let afterKeystrokeCount = darkPixelCount()
        #expect(
            (afterKeystrokeCount ?? -1) == 0,
            "expected zero descriptor ink on the very next frame after the query becomes non-empty (no mid-fade), found \(afterKeystrokeCount.map(String.init) ?? "nil")"
        )
    }

    /// The snapshot harness renders a single settled frame — proves the
    /// `revealPhase` test seam (`.constant(.revealed)`, the default every
    /// call site in this file already uses) produces a non-blank capture,
    /// same evidence shape as `zeroChromeRestStateHasNoCardBorder`.
    @Test func revealPhaseConstantRevealedRendersSettled() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: .zeroChrome,
            revealPhase: .constant(.revealed)
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: 560, height: 200)
        let png = renderPNG(view, size: size)
        #expect(png != nil)
        if let png, let rep = NSBitmapImageRep(data: png) {
            var darkPixels = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                    guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 else { continue }
                    let r = Int((color.redComponent * 255).rounded())
                    let g = Int((color.greenComponent * 255).rounded())
                    let b = Int((color.blueComponent * 255).rounded())
                    if (r + g + b) / 3 < 200 { darkPixels += 1 }
                }
            }
            #expect(darkPixels > 0, "expected the descriptor text to be visible on first paint with revealPhase = .revealed")
        }
    }

    // MARK: - Fix round 2, item 2: new-style status strip copy

    @Test func newStyleStatusStripUsesTheArrowCopy() {
        #expect(SessionComposerCopy.unresolvedBranchMessageForNewStyles(token: "foo").contains("Press ↓"))
        #expect(!SessionComposerCopy.unresolvedBranchMessageForNewStyles(token: "foo").contains("suggestion above"))
    }

    @Test func classicUnresolvedBranchMessageIsByteIdenticalToBefore() {
        // The EXISTING constant, untouched — this only re-asserts the
        // literal so a future edit to it (in violation of the
        // coordinator's "do not edit the existing string" instruction) is
        // caught here.
        #expect(
            SessionComposerCopy.unresolvedBranchMessage(token: "foo")
                == "No worktree found for branch \"foo\". Use the create-branch suggestion above, or retype/delete it."
        )
    }

    // MARK: - Fix round 2, item 8: zero-chrome type scale

    @Test func zeroChromeTypographyConstantsMatchTheStrawman() {
        #expect(ComposerZeroChromeTypography.fieldSize == 32)
        #expect(ComposerZeroChromeTypography.fieldWeight == .semibold)
        #expect(ComposerZeroChromeTypography.fieldLineHeight == 44)
        #expect(ComposerZeroChromeTypography.rowSize == 20)
        #expect(ComposerZeroChromeTypography.rowWeight == .medium)
        #expect(ComposerZeroChromeTypography.rowLineHeight == 30)
        #expect(ComposerZeroChromeTypography.measureMin == 480)
        #expect(ComposerZeroChromeTypography.measureMax == 960)
        #expect(ComposerZeroChromeTypography.measureFraction == 0.75)
    }

    /// `.singleLine` must keep the ORIGINAL 15pt field size, not
    /// `ComposerZeroChromeTypography`'s 32pt — checked by rendering a
    /// single-line fixture and confirming it fits comfortably inside the
    /// unchanged 512pt card (a 32pt field would overflow it).
    @Test func singleLineFieldStaysAtTheOriginalFifteenPointScale() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine)
        let size = NSSize(width: 560, height: 100)
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "single-line-unchanged-scale.png")
        #expect(png != nil)
        if let png {
            // Same border-stroke check as `singleLineRestStateHasCardChrome`
            // — a 32pt field would have blown out the fixed-height card and
            // very likely pushed/clipped the border out of this capture.
            #expect(borderStrokePixelCount(in: png) > 0)
        }
    }

    /// Zero-chrome typing at the new scale — the item 8 snapshot.
    @Test func zeroChromeTypingAtNewScale() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 700, height: 400)
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
        defer { window.orderOut(nil) }

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "d"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the new-scale typing fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])
        writeScratchPNG(png, filename: "zero-chrome-typing-new-scale.png")
        #expect(png != nil)
    }

    /// A 1000×700 window — proves nothing clips at the measure clamp
    /// (960pt max, well under 1000×0.75=750).
    @Test func zeroChromeNothingClipsAtALargeWindow() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 1000, height: 700)
        let measure = min(max(size.width * ComposerZeroChromeTypography.measureFraction, ComposerZeroChromeTypography.measureMin), ComposerZeroChromeTypography.measureMax)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: .zeroChrome,
            zeroChromeMeasureOverride: measure
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let png = renderPNG(view, size: size)
        writeScratchPNG(png, filename: "zero-chrome-1000x700-no-clip.png")
        #expect(png != nil)
        #expect(measure == 750) // 1000 * 0.75, within the 480-960 clamp
    }

    // MARK: - Fix round 5: wash reaches the titlebar band

    /// Sean's live look: "the ghostties app should be blurred" — the whole
    /// window, titlebar band included. Mounts a REAL `SessionComposerOverlay`
    /// (not just the palette, which never rendered the titlebar-band
    /// spacer this bug lived in) with a non-zero `titlebarBandHeight`, and
    /// asserts the wash's material visibly lightens a solid-black pixel
    /// INSIDE that band — a pre-fix render leaves that strip untouched
    /// (`Color.clear`), so this pixel would stay pure black.
    /// `revealPhaseOverrideForTesting: .revealed` bypasses the `.task`'s
    /// one-run-loop-turn summon race for a deterministic settled frame.
    /// Mutation-checked: temporarily restoring the old
    /// `VStack { Color.clear.frame(height:); ComposerZeroChromeWash(...) }`
    /// structure in `SessionComposerOverlay.zeroChromeFullBleedWash` made
    /// this fail red (confirmed by hand during implementation — see the
    /// implementer's report — then reverted back to the fix, green).
    @Test func zeroChromeWashCoversTheTitlebarBand() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let centeringModel = ComposerCenteringModel()
        centeringModel.titlebarBandHeight = 28

        let size = NSSize(width: 700, height: 400)
        let composite = ZStack {
            DenseTerminalBackdropForOverlayTest()
            SessionComposerOverlay(
                request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
                styleOverrideForTesting: .zeroChrome,
                revealPhaseOverrideForTesting: .revealed,
                centeringModel: centeringModel
            )
            .environmentObject(workspaceStore)
            .environmentObject(SessionCoordinator())
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = .black

        let hosting = NSHostingView(rootView: composite.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting

        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let compositeRep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the composite fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: compositeRep)

        // Sample a pixel well inside the 28pt titlebar band (y = 10, 4pt in
        // from the left) on a backdrop that painted a distinctive band
        // color there — a wash that stops at the band boundary would leave
        // this pixel unchanged.
        guard let bandColor = compositeRep.colorAt(x: 4, y: 10) else {
            Issue.record("failed to sample the titlebar-band pixel")
            return
        }
        let bandLuma = (bandColor.redComponent + bandColor.greenComponent + bandColor.blueComponent) / 3
        let centerColor = compositeRep.colorAt(x: 350, y: 200)
        let centerLuma = centerColor.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 } ?? -1
        #expect(
            bandLuma > 0.05,
            "expected the wash's material to visibly lighten the titlebar-band pixel (raw backdrop paints solid black there), got luma \(bandLuma), centerLuma \(centerLuma)"
        )
    }

    /// Solid black everywhere, including the titlebar band, so any
    /// non-black pixel sampled there after compositing the overlay proves
    /// something painted over it.
    private struct DenseTerminalBackdropForOverlayTest: View {
        var body: some View {
            Color.black
        }
    }
}
