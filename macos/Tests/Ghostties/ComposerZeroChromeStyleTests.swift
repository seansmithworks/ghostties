import AppKit
import Combine
import SwiftUI
import Testing
import GhosttiesCore
import DialKit
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

    /// Round 8 (Sean, live look): default moved from `.regular` to
    /// `.medium` — the "in between thin and regular" option.
    @Test func composerZeroChromeMaterialDefaultsToMedium() {
        let suite = UserDefaults(suiteName: "ghostties.composerZeroChromeMaterial.test.\(UUID().uuidString)")!
        #expect(ComposerZeroChromeMaterial.current(defaults: suite) == .medium)
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

    /// R15b: shared canvas width for the single-line render tests below,
    /// derived instead of hardcoded. Must contain the card at its widest
    /// tunable width plus the palette's own shake-clearance padding, with
    /// the Witness ghost (offset above the card) still on-canvas:
    ///   `ComposerSingleLineTuning.widthRange.upperBound` (760pt, the
    ///     widest the width dial goes)
    /// + 16pt (`body`'s `.padding(8)` per side, `SessionComposerPalette
    ///     .swift` ~289 — the shake-clearance inset wrapping the card)
    /// + 24pt margin (covers the Witness's `.offset(x: 20, y: -24)` above
    ///     the card's top-leading corner, plus rounding slack)
    /// = 800pt — same value round 15 hardcoded, now provable instead of
    /// guessed, and correct across the whole width dial rather than just
    /// today's 688pt default.
    private static let derivedRenderCanvasWidth =
        CGFloat(ComposerSingleLineTuning.widthRange.upperBound) + 16 + 24

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
        style: ComposerStyle? = nil,
        tuningDefaults: UserDefaults? = nil
    ) -> some View {
        SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: style,
            tuningDefaultsForTesting: tuningDefaults
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
        // R15: 560pt was sized for the pre-R13b 512pt default width. The
        // isolated suite below has no stored width override, so it resolves
        // `ComposerSingleLineTuning.defaultWidth` (688pt, round-13b's tuned
        // default) — a 560pt-wide capture puts both border-stroke edges
        // off-canvas, sampling nothing but interior card fill. R15b: see
        // `derivedRenderCanvasWidth` for why 800pt is the right value, not
        // just a wider guess.
        let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 100)
        // Step 0 (R14): isolated suite, treatment pinned to `.material` — the
        // stroke this test asserts on only renders in the material branch of
        // `singleLineComposerCard`; `.glass` has no `.stroke(` at all. Reading
        // real `UserDefaults.standard` here (the R13 gap) let this test pass
        // for the wrong reason whenever `.glass` fell back to material by
        // availability rather than by explicit treatment.
        let suite = UserDefaults(suiteName: "ghostties.composerZeroChrome.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine, tuningDefaults: suite)
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

    // MARK: - R14: Witness ghost pixels (plan §6 test 6 — RUN OWED, Dev is open)

    /// Counts pixels close to `ComposerWitnessGhost.flicker`'s `colorHex`
    /// (`#ff3b3b`) — reuses `containsRedInk`'s tolerance band (that band
    /// was tuned for exactly this kind of saturated red, and `.blinky`'s
    /// mapped witness IS `.flicker`).
    private func flickerRedPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r > 150, r - g > 60, r - b > 60 { count += 1 }
            }
        }
        return count
    }

    /// `.locked` project with `.blinky` (-> `.flicker`, red) so the sprite's
    /// body color is unambiguous against the card's neutral chrome. Extra
    /// 40pt of canvas ABOVE the card's own frame — the Witness overlay sits
    /// at `.offset(x: 20, y: -24)` from `.topLeading`, poking up past the
    /// card's top edge (plan §1); a tight frame would clip exactly the
    /// pixels this test looks for. Reduce Motion is NOT overridden here
    /// (no live `NSWorkspace` stub in this harness, matching
    /// `reduceMotionShowsStaticFirstDescriptor`'s documented limitation) —
    /// this reads whatever Reduce Motion setting is actually live, which is
    /// why this test's run (not just its build) is owed until Dev closes:
    /// an offscreen render can otherwise land on a blank first frame before
    /// `TimelineView` ever fires (`SessionComposerPalette.swift` `:2037-
    /// 2042`'s documented trap).
    private func witnessFixture(witnessEnabled: Bool) -> (view: some View, size: NSSize) {
        let project = Project(name: "Demo", rootPath: "/tmp/composer-witness-pixels-\(UUID().uuidString)", ghostCharacter: .blinky)
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerWitness.pixels.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        suite.set(witnessEnabled, forKey: ComposerWitnessSetting.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine, tuningDefaults: suite)
        // R15: same root cause as `singleLineRestStateHasCardChrome` — the
        // isolated suite resolves the 688pt round-13b width default. `body`
        // centers `composerCard` inside `renderPNG`'s outer `.frame`, so at
        // 560pt the 704pt (688 + 16pt shake padding) card is clipped ~72pt
        // on each side; the Witness overlay at `.offset(x: 20, y: -24)` from
        // the card's topLeading lands off-canvas to the left regardless of
        // the toggle, which is why the ON assertion failed and the OFF
        // twin passed for the wrong reason (nothing to find either way).
        // R15b: see `derivedRenderCanvasWidth` for why 800pt is the right
        // value, not just a wider guess.
        return (view, NSSize(width: Self.derivedRenderCanvasWidth, height: 140))
    }

    /// red mutation: gate `showsWitness` on `false` unconditionally — this
    /// test then fails (0 flicker-red pixels with the toggle on).
    @Test func witnessGhostPixelsPresentAboveCardWhenToggleOn() {
        let fixture = witnessFixture(witnessEnabled: true)
        let png = renderPNG(fixture.view, size: fixture.size)
        writeScratchPNG(png, filename: "witness-toggle-on.png")
        #expect(png != nil)
        if let png {
            #expect(flickerRedPixelCount(in: png) > 0, "expected the Witness ghost's flicker-red pixels above the card with the toggle on")
        }
    }

    /// red mutation: gate `showsWitness` on `true` unconditionally — this
    /// test then fails (flicker-red pixels present even with the toggle
    /// off).
    @Test func witnessGhostPixelsAbsentWhenToggleOff() {
        let fixture = witnessFixture(witnessEnabled: false)
        let png = renderPNG(fixture.view, size: fixture.size)
        writeScratchPNG(png, filename: "witness-toggle-off.png")
        #expect(png != nil)
        if let png {
            #expect(flickerRedPixelCount(in: png) == 0, "expected no flicker-red pixels with the Witness toggle off")
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
        // Round 8: text now waits for the fog's smoke-build to mostly
        // settle before revealing (was 0.12s duration / 0.04s delay).
        #expect(ComposerZeroChromeTiming.summonTextDuration == 0.18)
        #expect(ComposerZeroChromeTiming.summonTextDelay == 0.22)
        #expect(ComposerZeroChromeTiming.summonFogRampDuration == 0.32)
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
        // Round 10: replaced the round-8 off-center "center stage" column
        // (leading-edge fraction) with a centered column.
        #expect(ComposerZeroChromeTypography.columnMaxWidth == 640)
        #expect(ComposerZeroChromeTypography.columnGutter == 48)
        #expect(ComposerZeroChromeTypography.fieldAnchorFraction == 0.46)
        #expect(ComposerZeroChromeTypography.fieldAnchorBottomOffset == 22)
        #expect(ComposerZeroChromeTypography.maxFieldLines == 3)
    }

    /// Round 10: `columnFrame(overlayWidth:)` centers a 640pt column with
    /// 48pt gutters both sides at a wide overlay (1600pt: x 480, w 640 —
    /// the brief's own worked example), and shrinks to fit — still
    /// centered, gutters intact — on a narrower one (600pt: w 504, x 48,
    /// which is exactly centered since `(600 - 504) / 2 == 48`).
    @Test func columnFrameAtTwoWidths() {
        let wide = ComposerZeroChromeTypography.columnFrame(overlayWidth: 1600)
        #expect(wide.width == 640)
        #expect(wide.leadingX == 480)

        let narrow = ComposerZeroChromeTypography.columnFrame(overlayWidth: 600)
        #expect(narrow.width == 504) // 600 - 2*48
        #expect(narrow.leadingX == 48) // (600 - 504) / 2
    }

    /// A degenerate overlay narrower than twice the gutter must never go
    /// negative — width floors at 0, and the column stays centered (x ==
    /// half the overlay).
    @Test func columnFrameNeverGoesNegativeOnADegenerateOverlay() {
        let column = ComposerZeroChromeTypography.columnFrame(overlayWidth: 40)
        #expect(column.width == 0)
        #expect(column.leadingX == 20)
    }

    /// Round 10: pure anchor math — the field's BOTTOM edge
    /// (`top + height`) must equal `0.46*H + 22` at 1, 2, and 3 lines, and
    /// the height must cap at `maxFieldLines` (3) even when asked for 5.
    @Test func fieldFrameHoldsTheBottomEdgeFixedAsLinesGrow() {
        let overlaySize = CGSize(width: 1200, height: 800)
        let expectedBottom = 800 * ComposerZeroChromeTypography.fieldAnchorFraction
            + ComposerZeroChromeTypography.fieldAnchorBottomOffset

        for lineCount in 1...3 {
            let frame = ComposerZeroChromeTypography.fieldFrame(overlaySize: overlaySize, lineCount: lineCount)
            #expect(frame.height == CGFloat(lineCount) * ComposerZeroChromeTypography.fieldLineHeight)
            #expect(abs((frame.top + frame.height) - expectedBottom) < 0.001)
        }

        let overflowing = ComposerZeroChromeTypography.fieldFrame(overlaySize: overlaySize, lineCount: 5)
        #expect(overflowing.height == CGFloat(ComposerZeroChromeTypography.maxFieldLines) * ComposerZeroChromeTypography.fieldLineHeight)
        #expect(abs((overflowing.top + overflowing.height) - expectedBottom) < 0.001)
    }

    /// `.singleLine` must keep the ORIGINAL 15pt field size, not
    /// `ComposerZeroChromeTypography`'s 32pt — checked by rendering a
    /// single-line fixture and confirming it fits comfortably inside the
    /// unchanged 512pt card (a 32pt field would overflow it).
    @Test func singleLineFieldStaysAtTheOriginalFifteenPointScale() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        // Step 0 (R14): same isolated-suite/material pin as
        // `singleLineRestStateHasCardChrome` — see that test's comment.
        let suite = UserDefaults(suiteName: "ghostties.composerZeroChrome.test.\(UUID().uuidString)")!
        suite.set(ComposerSingleLineTreatment.material.rawValue, forKey: ComposerSingleLineTreatment.storageKey)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore, style: .singleLine, tuningDefaults: suite)
        // R15: see `singleLineRestStateHasCardChrome`'s comment — the
        // isolated suite resolves the 688pt round-13b width default, not
        // the pre-R13b 512pt this canvas was originally sized for. R15b:
        // see `derivedRenderCanvasWidth` for why 800pt is the right value.
        let size = NSSize(width: Self.derivedRenderCanvasWidth, height: 100)
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
    /// (960pt max, well under `columnFrame`'s centered-column result).
    @Test func zeroChromeNothingClipsAtALargeWindow() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 1000, height: 700)
        let measure = ComposerZeroChromeTypography.columnFrame(overlayWidth: size.width).width
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
        #expect(measure == 640) // min(640, 1000 - 2*48) — the centered column's own max width
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

        // Round 7: was reading real `.standard` (this xctest bundle IS
        // `com.seansmithdesign.ghostties.dev` — the same domain Sean's own
        // DEBUG tuning pill writes into on this machine, currently pinned to
        // `ultraThin` per the in-flight memo). This test asserts the DEFAULT
        // wash's coverage, not whatever material Sean last tuned by eye —
        // an isolated empty suite resolves both knobs to their `.regular`/
        // `.thick` defaults, same seam `overlayResolvedStyleFollowsInjectedDefaultsWrite`
        // already uses. Round 7's ultraThin/thin transparency (0.35/0.55)
        // made this pre-existing hermeticity gap visible: `ultraThin` alone
        // still cleared the >0.05 threshold, `ultraThin` × 0.35 opacity
        // didn't.
        let isolatedDefaults = UserDefaults(suiteName: "ghostties.zeroChromeTitlebarBand.test.\(UUID().uuidString)")!
        let size = NSSize(width: 700, height: 400)
        let composite = ZStack {
            DenseTerminalBackdropForOverlayTest()
            SessionComposerOverlay(
                request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
                styleOverrideForTesting: .zeroChrome,
                revealPhaseOverrideForTesting: .revealed,
                defaultsForTesting: isolatedDefaults,
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

    // MARK: - B1: rows must fade with the field, not outlive it

    /// `showNewStyleRows` tracks query/arrow state only, not `revealPhase` —
    /// pre-fix, rows stayed fully painted on `.committing`/`.dismissing`
    /// even though the field+status stack above them faded via its own
    /// `revealPhase`-gated `.opacity`. Mounts with a non-empty query (so
    /// `showNewStyleRows` is true) and `revealPhase: .constant(.committing)`
    /// directly (same injection seam `revealPhaseConstantRevealedRendersSettled`
    /// uses) — against the unfixed code this renders a visible selected-row
    /// accent tint despite the phase never being `.revealed`; the fix gates
    /// the rows block on the same phase check the text block already had.
    @Test func zeroChromeRowsFadeOutDuringCommitPhase() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let size = NSSize(width: 560, height: 260)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: .zeroChrome,
            revealPhase: .constant(.committing)
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

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
            Issue.record("failed to render the committing-phase fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])
        writeScratchPNG(png, filename: "zero-chrome-rows-committing-phase.png")
        #expect(png != nil)
        if let png {
            #expect(
                selectionAccentPixelCount(in: png) == 0,
                "expected rows to be faded out (opacity 0) while revealPhase == .committing, even though showNewStyleRows is true"
            )
        }
    }

    // MARK: - B2: a failed commit must restore revealPhase to .revealed

    /// Drives a REAL commit through the keyboard path (`insertNewline:` on
    /// the mounted `NSTextView`, same technique
    /// `zeroChromeArrowDownRevealsRowsOnEmptyQuery` uses for `moveDown:`) —
    /// not a call to the private `commit(template:)`. Calls `composerStore
    /// .createWorktree(named:in:)` (same fixture-free call
    /// `SessionComposerWorktreeLaunchTests` uses — the underlying `git
    /// worktree add` fails harmlessly in the background against the
    /// synthetic non-repo path this test's `makeProject()` always uses;
    /// nothing here waits on or asserts its outcome) immediately before
    /// firing Return, with no intervening `RunLoop` spin — `isCreatingWorktree`
    /// is set `true` SYNCHRONOUSLY before that call returns (`SessionComposerStore
    /// .swift:1104`), so `precommit`'s guard at `SessionComposerStore
    /// .swift:723-726` fails and returns `false` with `writeError` set,
    /// without ever touching the (still fully valid, still fully rendered)
    /// project or row list — unlike removing the project, this doesn't
    /// collapse `selectedOption` out from under the same synchronous Return
    /// that's supposed to observe the failure. Pre-fix, `revealPhase` is set
    /// to `.committing` before `precommit` runs and never restored on this
    /// failure path, leaving the composer open but invisible. Reads
    /// `revealPhase.wrappedValue` back through an `ObservableObject` box
    /// bound in, and `composerStore.writeError` directly.
    @MainActor
    private final class RevealPhaseBox: ObservableObject {
        @Published var phase: ComposerRevealPhase = .revealed
    }

    @Test func failedCommitRestoresRevealPhaseToRevealed() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let box = RevealPhaseBox()
        let phaseBinding = Binding<ComposerRevealPhase>(
            get: { box.phase },
            set: { box.phase = $0 }
        )
        let size = NSSize(width: 560, height: 260)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: .zeroChrome,
            revealPhase: phaseBinding
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

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
        // A second pass, matching `zeroChromeTypingRevealsSelectedCandidateRow`'s
        // documented ordering: `onAppear` seeds `selectedIndex` synchronously,
        // but `ComposerGhostTextField`'s `hasSelection` is an `NSViewRepresentable`
        // param — it only reaches the Coordinator on `updateNSView`, which needs
        // this second layout pass to have actually run before Return is simulated.
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let textView = firstTextView(in: hosting), let delegate = textView.delegate else {
            Issue.record("could not locate the mounted ComposerGhostTextField's NSTextView/delegate")
            return
        }

        // Arms `isCreatingWorktree` synchronously (set before this call
        // returns) — the git op itself runs in the background against a
        // non-repo synthetic path and is never awaited or asserted here.
        composerStore.createWorktree(named: "test-branch", in: project)
        #expect(composerStore.isCreatingWorktree, "sanity check: expected isCreatingWorktree armed before Return")

        _ = delegate.textView?(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(composerStore.writeError != nil, "expected precommit to fail and set writeError")
        #expect(
            box.phase == .revealed,
            "expected revealPhase restored to .revealed after a failed commit, got \(box.phase)"
        )
    }

    // MARK: - Round 7: the OTHER commit-time failure arm must also restore revealPhase

    /// Open finding from the zero-chrome in-flight memo:
    /// `resolveCommitWorktreePathForCommit`'s `.failure` arm in
    /// `commit(template:)` (`SessionComposerPalette.swift`) returned early
    /// without restoring `revealPhase` to `.revealed` — the same bug class
    /// as B2 above, but on the sibling switch a few lines later. Reachable
    /// even though both switches read the SAME `typedBranchResolution`
    /// computed property with no intervening keystroke: `SessionComposerStore
    /// .selectedProjectId`'s `didSet` synchronously clears `worktreesProjectId`
    /// (`cascadeProjectChange`) the instant `commit(template:)`'s own
    /// mid-function write resolves a NEWLY-typed project into
    /// `selectedProjectId` — so a typed `"<project B> > <branch> > <idiom>"`
    /// that resolved cleanly against B's PRE-populated cache on the FIRST
    /// read (passing the earlier `.unresolved`/`.pending` guard) reads
    /// `.pending` on the SECOND read, once that write has fired and wiped
    /// the cache out from under it. Project B's worktree cache is populated
    /// directly via `refreshWorktrees` here (the same call production makes,
    /// just not routed through the view's 300ms-debounced `.onChange` —
    /// bypassing that debounce is what keeps this test deterministic rather
    /// than racing a `Task.sleep`).
    @Test func failedTypedProjectCommitRestoresRevealPhaseToRevealed() async {
        let repoA = Self.makeThrowawayRepo()
        let repoB = Self.makeThrowawayRepo()
        defer {
            Self.cleanup(repoA)
            Self.cleanup(repoB)
        }
        let projectA = Project(name: "projecta", rootPath: repoA)
        let projectB = Project(name: "projectb", rootPath: repoB)
        let workspaceStore = WorkspaceStore(testingProjects: [projectA, projectB], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .prefilled(projectA), workspaceStore: workspaceStore)
        #expect(composerStore.selectedProjectId == projectA.id, "setup failed: .prefilled must pre-select A")

        let box = RevealPhaseBox()
        let phaseBinding = Binding<ComposerRevealPhase>(
            get: { box.phase },
            set: { box.phase = $0 }
        )
        let size = NSSize(width: 560, height: 260)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .prefilled(projectA)),
            composerStore: composerStore,
            styleOverrideForTesting: .zeroChrome,
            revealPhase: phaseBinding
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

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
        // `zeroChromeTypingRevealsSelectedCandidateRow`'s documented
        // ordering; setting a full command string before mount left
        // `commandProject`/`selectedIndex` unseeded and Return committed
        // into project A's own ad-hoc path instead of resolving B at all.
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        // Mounting fires its own `.onAppear` `open()`/refresh cycle for A,
        // asynchronously, racing anything called right after `layoutSubtreeIfNeeded()`
        // returns. Settle to A first (absorbing that race), THEN settle to
        // B (the project the text below types) — retrying each
        // `refreshWorktrees` call until it actually sticks, since a single
        // call can still lose to an in-flight competing refresh for the
        // other project. Production populates B's cache the same way, via
        // the view's own 300ms-debounced `commandProjectRefreshTask`; this
        // just does it deterministically instead of racing that timer.
        func settleWorktrees(to projectId: UUID, path: String) async {
            for _ in 0..<40 where composerStore.worktreesProjectId != projectId {
                await composerStore.refreshWorktrees(for: path, projectId: projectId)
                if composerStore.worktreesProjectId == projectId { return }
                try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
            }
        }
        await settleWorktrees(to: projectA.id, path: repoA)
        await settleWorktrees(to: projectB.id, path: repoB)
        #expect(composerStore.worktreesProjectId == projectB.id, "sanity check: expected B's cache populated before typing")

        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = "projectb > main > cco"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let textView = firstTextView(in: hosting), let delegate = textView.delegate else {
            Issue.record("could not locate the mounted ComposerGhostTextField's NSTextView/delegate")
            return
        }

        _ = delegate.textView?(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(composerStore.selectedProjectId == projectB.id, "sanity check: expected the typed project to have won by commit time")
        #expect(
            box.phase == .revealed,
            "expected revealPhase restored to .revealed after the .failure arm fired, got \(box.phase)"
        )
    }

    // MARK: - DEBUG-only tuning control (session-7 brief, 2026-09-11)

    /// Isolated suite per test, matching this file's own documented reason
    /// for never touching `.standard` directly (racing other parallel Swift
    /// Testing processes).
    /// Same throwaway-repo helper as `SessionComposerBranchLaunchTests` —
    /// duplicated rather than shared across test targets/files, matching
    /// this codebase's existing per-file convention for this exact helper.
    private static func makeThrowawayRepo() -> String {
        let unresolvedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("ghostties-zero-chrome-branch-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: unresolvedPath, withIntermediateDirectories: true)
        let path = realPath(unresolvedPath)

        func run(_ args: [String]) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = args
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }

        run(["git", "-C", path, "init", "-q", "-b", "main"])
        run(["git", "-C", path, "-c", "user.email=test@ghostties.test", "-c", "user.name=Ghostties Test",
             "commit", "-q", "--allow-empty", "-m", "init"])
        return path
    }

    private static func realPath(_ path: String) -> String {
        guard let cPath = realpath(path, nil) else { return path }
        defer { free(cPath) }
        return String(cString: cPath)
    }

    private static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeTuningDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ghostties.composerDebugTuning.test.\(UUID().uuidString)")!
    }

    /// "The control writes the right key" — drives the (non-`private`,
    /// `@testable`-reachable) bindings directly rather than simulating a
    /// menu click, same no-AX-driving shape this file already uses for
    /// keyboard events. Covers all three knobs' storage keys in one test.
    @Test func debugTuningControlWritesTheRightKeys() {
        let defaults = makeTuningDefaults()
        var changeCount = 0
        let control = ComposerDebugTuningControl(defaults: defaults, onChange: { changeCount += 1 })

        control.style.wrappedValue = .zeroChrome
        #expect(defaults.string(forKey: ComposerStyle.storageKey) == "zeroChrome")

        control.material.wrappedValue = .thin
        #expect(defaults.string(forKey: ComposerZeroChromeMaterial.storageKey) == "thin")

        control.focalBlur.wrappedValue = .off
        #expect(defaults.string(forKey: ComposerZeroChromeFocalBlurStyle.storageKey) == "off")

        control.fog.wrappedValue = false
        #expect(defaults.bool(forKey: ComposerZeroChromeFogSetting.storageKey) == false)

        #expect(changeCount == 4, "expected onChange to fire once per knob write, got \(changeCount)")
    }

    /// Round 8: `ComposerZeroChromeFocalBlurStyle.current()`'s own default
    /// (unset key) moved from `.thick` to `.regular`, alongside the base
    /// material's move to `.medium` (Sean's live look).
    @Test func focalBlurStyleDefaultsToRegular() {
        let defaults = makeTuningDefaults()
        #expect(ComposerZeroChromeFocalBlurStyle.current(defaults: defaults) == .regular)
    }

    @Test func focalBlurStyleOffProducesNoMaterial() {
        #expect(ComposerZeroChromeFocalBlur.focalMaterial(for: .off) == nil)
        #expect(ComposerZeroChromeFocalBlur.focalMaterial(for: .thick) != nil)
    }

    /// "The overlay's resolved style/material follows it" — writes directly
    /// to the SAME injected suite `SessionComposerOverlay(defaultsForTesting:)`
    /// reads via `@AppStorage`, then re-renders and confirms the view
    /// switched from the classic bordered card to the zero-chrome branch
    /// (no border-stroke drawing code, `zeroChromeRestStateHasNoCardBorderDrawingCode`'s
    /// same reasoning) — proving observation, not just a one-time read.
    @Test func overlayResolvedStyleFollowsInjectedDefaultsWrite() {
        let defaults = makeTuningDefaults()
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let centeringModel = ComposerCenteringModel()
        let size = NSSize(width: 700, height: 400)

        let view = SessionComposerOverlay(
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            revealPhaseOverrideForTesting: .revealed,
            defaultsForTesting: defaults,
            centeringModel: centeringModel
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

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
            Issue.record("failed to render the pre-write fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: before)
        if let beforeData = before.representation(using: .png, properties: [:]) {
            #expect(borderStrokePixelCount(in: beforeData) > 0, "expected the default (.classic) style to render a bordered card")
        }

        defaults.set(ComposerStyle.zeroChrome.rawValue, forKey: ComposerStyle.storageKey)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        guard let after = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render the post-write fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: after)
        let afterData = after.representation(using: .png, properties: [:])
        writeScratchPNG(afterData, filename: "overlay-follows-injected-defaults-write.png")
        #expect(afterData != nil)
        if let afterData {
            #expect(
                borderStrokePixelCount(in: afterData) == 0,
                "expected writing ComposerStyle.zeroChrome into the injected suite to switch the LIVE overlay to the zero-chrome (borderless) branch"
            )
        }
    }

    /// The fixture-hiding gate itself: `GHOSTTIES_CAPTURE_FIXTURE=1` in the
    /// launch environment must hide the control entirely — the marketing
    /// capture rig builds Debug, so a screenshot must never show it. Asserts
    /// directly on `SessionComposerOverlay.isMarketingCaptureFixtureActive`
    /// — the EXACT gate `body`'s `.overlay(alignment: .bottomTrailing)`
    /// checks before ever constructing `ComposerDebugTuningControl` — rather
    /// than hunting for a `Picker`'s AppKit backing view: `.menu`-style
    /// `Picker`s don't reliably materialize an `NSPopUpButton` inside an
    /// offscreen, non-key `NSHostingView` (confirmed empirically: a full
    /// subview-hierarchy dump of a mounted, capture-inactive overlay showed
    /// zero AppKit picker/button/menu classes anywhere, only the field's own
    /// `NSTextView` machinery — an artifact of this specific offscreen
    /// harness, not evidence the production control fails to render in a
    /// real, key window).
    @Test func debugTuningControlGateReflectsCaptureFixtureEnvVar() {
        unsetenv("GHOSTTIES_CAPTURE_FIXTURE")
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == false)

        setenv("GHOSTTIES_CAPTURE_FIXTURE", "1", 1)
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == true)

        unsetenv("GHOSTTIES_CAPTURE_FIXTURE")
        #expect(SessionComposerOverlay.isMarketingCaptureFixtureActive == false)
    }

    // MARK: - Round 10: typewriter centered column, field wraps

    /// Plain reference box for building `Binding`s in these `ComposerGhostTextField`
    /// mount tests, without SwiftUI `@State` (unavailable outside a `View`).
    private final class ValueBox<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// Mounts the PRODUCTION `ComposerGhostTextField` (`wrapsAndGrows: true`)
    /// at the 640pt column width with the exact long prompt from the round-10
    /// brief and proves it actually wraps (line count >= 2, via
    /// `ComposerGhostNSTextView.wrappedLineCount`, TextKit's own line-fragment
    /// count) with no horizontal scroll offset — the start of the text is
    /// never clipped. Proven to fail on the OLD single-line configuration
    /// during implementation: temporarily removing the `wrapsAndGrows`
    /// branch in `ComposerGhostTextField.makeNSView` and re-running this
    /// test alone reported `wrappedLineCount == 1` (red); restoring the
    /// branch returns it to green.
    @Test func wrappingFieldAtColumnWidthNeverClipsTheStartOfALongPrompt() {
        let longPrompt = "brukas cco -n \"testing the naming set up for this stuff and\""
        let queryBox = ValueBox(longPrompt)
        let focusBox = ValueBox(false)
        let heightBox = ValueBox<CGFloat>(ComposerZeroChromeTypography.fieldLineHeight)

        let field = ComposerGhostTextField(
            query: Binding(get: { queryBox.value }, set: { queryBox.value = $0 }),
            fontSize: ComposerZeroChromeTypography.fieldSize,
            fontWeight: .semibold,
            rowHeight: ComposerZeroChromeTypography.fieldLineHeight,
            focusTrigger: Binding(get: { focusBox.value }, set: { focusBox.value = $0 }),
            hasSelection: false,
            isPickerOpen: false,
            ghostFullPath: "",
            wrapsAndGrows: true,
            measuredHeight: Binding(get: { heightBox.value }, set: { heightBox.value = $0 })
        ) { _ in }

        let size = NSSize(width: 640, height: 200)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: field.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let scrollView = firstScrollView(in: hosting),
              let textView = scrollView.documentView as? ComposerGhostNSTextView else {
            Issue.record("expected a mounted ComposerGhostNSTextView")
            return
        }
        #expect(textView.wrappedLineCount >= 2)
        #expect(scrollView.contentView.bounds.origin.x == 0)
        #expect(textView.string.hasPrefix("brukas"))
    }

    /// `.classic`/`.singleLine` never set `wrapsAndGrows` — asserts the
    /// PRODUCTION default (`wrapsAndGrows: false`) keeps the field's
    /// original horizontally-scrolling single-line `NSTextContainer`/
    /// `NSTextView` configuration, unaffected by the round-10 wrap branch.
    @Test func defaultConfigurationStaysSingleLineAndHorizontallyScrolling() {
        let queryBox = ValueBox("")
        let focusBox = ValueBox(false)
        let field = ComposerGhostTextField(
            query: Binding(get: { queryBox.value }, set: { queryBox.value = $0 }),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: Binding(get: { focusBox.value }, set: { focusBox.value = $0 }),
            hasSelection: false,
            isPickerOpen: false,
            ghostFullPath: ""
        ) { _ in }

        let size = NSSize(width: 512, height: 60)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: field.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let scrollView = firstScrollView(in: hosting),
              let textView = scrollView.documentView as? ComposerGhostNSTextView,
              let textContainer = textView.textContainer else {
            Issue.record("expected a mounted single-line ComposerGhostNSTextView")
            return
        }
        #expect(textContainer.widthTracksTextView == false)
        #expect(textView.isHorizontallyResizable == true)
        #expect(textView.isVerticallyResizable == false)
    }

    // MARK: - Round 13 review finding: prove the palette actually consumes ComposerSingleLineTuning

    /// Round 12 added `ComposerSingleLineTuning` and wired `.singleLine`'s
    /// `newStyleFieldFontSize`/`newStyleFieldWidth` (`SessionComposerPalette`)
    /// to read it, but nothing mounted the real card and checked the
    /// rendered field against a NON-default tuning — every existing
    /// `.singleLine` render used the untouched defaults, so a typo in the
    /// wiring (e.g. hardcoding 15/512 instead of reading the dial) would
    /// have passed every other test in this file silently. This mounts
    /// `SessionComposerPalette`'s real `singleLineComposerCard` with an
    /// isolated `UserDefaults` suite (`tuningDefaultsForTesting`, added
    /// alongside this test — same test-seam shape as
    /// `styleOverrideForTesting`) holding tuning values distinct from both
    /// `ComposerSingleLineTuning`'s defaults (round 13b: 28pt/688pt) AND the
    /// pre-round-12 fixed constants (15pt/512pt), then asserts the MOUNTED
    /// NSTextView's real `font.pointSize` and enclosing `NSScrollView`'s
    /// frame width against those injected values — not against the tuning
    /// enum's own getters, which would only prove the enum reads its own
    /// keys back, not that the view reads the enum. Red/green proof
    /// performed 2026-09-12: temporarily hardcoded
    /// `newStyleFieldFontSize`/`newStyleFieldWidth`'s `.singleLine` cases to
    /// 15/512 — failed with "expected the mounted field's font to reflect
    /// the injected tuning (26.0pt), got Optional(15.0)"; reverted and
    /// confirmed green (`xcodebuild test`, this test only, exit 0).
    @Test func singleLineCardRendersInjectedTuningNotDefaults() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeComposerStore(project: project, workspaceStore: workspaceStore)
        let suite = UserDefaults(suiteName: "ghostties.composerSingleLineTuning.test.\(UUID().uuidString)")!

        let injectedFieldSize: Double = 26
        let injectedWidth: Double = 740
        suite.set(injectedFieldSize, forKey: ComposerSingleLineTuning.fieldSizeStorageKey)
        suite.set(injectedWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        let size = NSSize(width: 900, height: 300)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore,
            styleOverrideForTesting: .singleLine,
            tuningDefaultsForTesting: suite
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())

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

        guard let textView = firstTextView(in: hosting) else {
            Issue.record("expected a mounted NSTextView for the .singleLine card")
            return
        }
        #expect(
            textView.font?.pointSize == CGFloat(injectedFieldSize),
            "expected the mounted field's font to reflect the injected tuning (\(injectedFieldSize)pt), got \(String(describing: textView.font?.pointSize))"
        )

        guard let scrollView = firstScrollView(in: hosting) else {
            Issue.record("expected a mounted NSScrollView for the .singleLine card")
            return
        }
        #expect(
            abs(scrollView.frame.width - CGFloat(injectedWidth)) < 0.5,
            "expected the mounted field's width to reflect the injected tuning (\(injectedWidth)pt), got \(scrollView.frame.width)"
        )

        // Sanity: the injected values are NOT the enum's own defaults, so
        // this test can't pass by accident just because the palette reads
        // ANY value off `ComposerSingleLineTuning` — it has to read the
        // ISOLATED suite specifically.
        #expect(injectedFieldSize != Double(ComposerSingleLineTuning.defaultFieldSize))
        #expect(injectedWidth != Double(ComposerSingleLineTuning.defaultWidth))
    }

    // MARK: - Round 13 review findings: DialKit tuning coordinator

    /// Finding #1: the `shadowPreset` `.select` control only ever wrote
    /// `shadowPresetRaw` — none of the preset's derived radius/length/opacity,
    /// unlike the legacy pill's binding which calls
    /// `ComposerSingleLineShadowDials.apply`. Names the production
    /// coordinator/model directly (not a re-implementation) so a regression
    /// that goes back to writing only the raw key fails this.
    ///
    /// Round 13d: `ComposerDialKitTuningModel.shadowPresetRaw` is now a
    /// computed property whose setter derives and assigns the three shadow
    /// dials as part of the SAME model mutation, so `coordinator.state
    /// .values.shadowPresetRaw = ...` below produces a single, already-
    /// derived `state.values` write with no reentrant reassignment from the
    /// coordinator's `$values` sink — the write is synchronous, no runloop
    /// turn to wait out.
    @available(macOS 14, *)
    @Test func dialKitShadowPresetSelectionWritesAllThreeDialsAndUpdatesModel() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.preset.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        coordinator.state.values.shadowPresetRaw = ComposerSingleLineShadowPreset.lifted.rawValue

        let expected = ComposerSingleLineShadowPreset.lifted.dialValues

        // The panel's own model reflects the derived dials immediately, so
        // the sliders redraw with the preset's numbers, not the old ones.
        #expect(coordinator.state.values.shadowRadius == Double(expected.radius))
        #expect(coordinator.state.values.shadowYOffset == Double(expected.yOffset))
        #expect(coordinator.state.values.shadowOpacity == expected.opacity)

        // The persisted keys — what `ComposerSingleLineShadowDials` and every
        // render actually read — carry the same derived values.
        #expect(suite.string(forKey: ComposerSingleLineShadowPreset.storageKey) == ComposerSingleLineShadowPreset.lifted.rawValue)
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.radiusStorageKey) as? Double == Double(expected.radius))
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.yOffsetStorageKey) as? Double == Double(expected.yOffset))
        #expect(suite.object(forKey: ComposerSingleLineShadowDials.opacityStorageKey) as? Double == expected.opacity)
    }

    /// Finding #2: the coordinator used to write its ENTIRE model on every
    /// change, so a panel whose own snapshot of an unrelated key was stale
    /// would silently stomp that key back to its stale value the moment the
    /// user touched anything else in the panel. This changes an unrelated
    /// field on the coordinator, then simulates a second actor (another open
    /// panel, the legacy pill, or a raw `defaults write`) changing a key this
    /// coordinator never touched, in the SAME isolated suite, and asserts
    /// that a further coordinator-driven write leaves the externally-changed
    /// key alone. Red/green proof performed 2026-09-12: temporarily added an
    /// unconditional `defaults.set(model.singleLineWidth, forKey: ...)`
    /// ahead of the diff-based writes in `write(from:to:)` — failed with "a
    /// write for one field must not clobber a key this panel didn't touch"
    /// (690.0 != 999.0); reverted and confirmed green (`xcodebuild test`,
    /// this test only, exit 0). Note: this proof also surfaced and fixed a
    /// separate real bug in `ComposerDialKitCoordinator.init` — see that
    /// init's doc comment — where `lastKnownModel` captured the coordinator's
    /// pre-normalization `initial` instead of the panel's own (rounded)
    /// `state.values`, exposed by round 13b's 688pt width default (not a
    /// multiple of the width dial's 10pt step).
    @available(macOS 14, *)
    @Test func dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.stale.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        // A second actor changes a key this coordinator has never touched —
        // its in-memory model still holds the OLD value for this key.
        let externalWidth = 999.0
        suite.set(externalWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        // This coordinator now changes an UNRELATED field.
        coordinator.state.values.focalBlurRaw = ComposerZeroChromeFocalBlurStyle.thick.rawValue

        #expect(suite.string(forKey: ComposerZeroChromeFocalBlurStyle.storageKey) == ComposerZeroChromeFocalBlurStyle.thick.rawValue)
        #expect(
            suite.object(forKey: ComposerSingleLineTuning.widthStorageKey) as? Double == externalWidth,
            "a write for one field must not clobber a key this panel didn't touch"
        )
    }

    // MARK: - R14: Witness toggle (plan §6 test 7, mirrors
    // dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact above)

    /// red mutation: change `write(from:to:)`'s witness-key branch to also
    /// write `ComposerSingleLineTuning.widthStorageKey` (or any other key)
    /// — the "only its key" assertion below then fails.
    @available(macOS 14, *)
    @Test func dialKitWitnessToggleWritesOnlyItsKey() {
        let suite = UserDefaults(suiteName: "ghostties.dialKitCoordinator.witness.test.\(UUID().uuidString)")!
        let coordinator = ComposerDialKitCoordinator(defaults: suite, onChange: {})

        // A second actor changes an unrelated key this coordinator has
        // never touched — proves the witness write is diff-based, same
        // guarantee `dialKitCoordinatorWriteLeavesExternallyChangedKeyIntact`
        // proves for `singleLineWidth`.
        let externalWidth = 999.0
        suite.set(externalWidth, forKey: ComposerSingleLineTuning.widthStorageKey)

        coordinator.state.values.witnessEnabled = false

        #expect(suite.object(forKey: ComposerWitnessSetting.storageKey) as? Bool == false)
        #expect(
            suite.object(forKey: ComposerSingleLineTuning.widthStorageKey) as? Double == externalWidth,
            "the witness toggle write must not clobber a key this panel didn't touch"
        )
    }
}
