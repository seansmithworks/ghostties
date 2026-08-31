import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// The Step 2 snapshot harness (Composer UI 11 plan §3, evidence contract
/// §6): mounts `SessionComposerPalette` (`.centered`, isolated fixture
/// stores) in an offscreen `NSWindow` via `NSHostingView` and writes
/// `bitmapImageRepForCachingDisplay` PNGs to
/// `docs/plans/composer-ui-11/evidence/`. Layout evidence only — spacing,
/// type, presence/absence — NOT material/vibrancy fidelity; final visual
/// acceptance is Sean's hands-on pass (plan §6 caveat).
///
/// ALL fixture data is synthetic (fake project name/path, the app's own
/// built-in template set) — this is a public repo, no real session state is
/// ever captured (`feedback_public-repo-no-real-session-data`).
///
/// Uses `SessionComposerStore(isolatedForTesting:)` and
/// `SessionComposerPalette`'s `composerStore:` initializer parameter (added
/// alongside this harness) so nothing here touches the developer's real,
/// persisted UserDefaults — the `.shared` composer store singleton has no
/// other environment-object seam.
@MainActor
struct SessionComposerSnapshotTests {

    private func makeProject() -> Project {
        Project(name: "Demo Project", rootPath: "/tmp/composer-ui-11-snapshot-\(UUID().uuidString)")
    }

    private func evidenceDirectory() -> URL {
        // #filePath: .../macos/Tests/Ghostties/SessionComposerSnapshotTests.swift
        // Four `deletingLastPathComponent()` calls reach the repo root:
        // Ghostties -> Tests -> macos -> repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
            .appendingPathComponent("docs/plans/composer-ui-11/evidence", isDirectory: true)
    }

    /// Renders `content` inside an offscreen, appearance-forced `NSWindow`
    /// and returns a PNG capture. `orderFrontRegardless()` mirrors this
    /// file's existing `hitTestDisabledExcludesViewFromHitTesting` precedent
    /// (`SessionComposerPhase3ReviewTests`) — SwiftUI's dynamic `NSColor`
    /// resolution (`.windowBackgroundColor`, etc.) needs a real window in
    /// the window server to resolve against the forced `appearance`; a
    /// borderless, ordered-out-immediately-after window never takes key or
    /// steals focus from anything the user is doing (no synthetic input is
    /// ever sent — capture only, never driving, per this repo's hard rule).
    private func renderPNG<Content: View>(
        _ content: Content,
        appearance: NSAppearance.Name,
        size: NSSize
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Step 7 only: `ComposerGhostTextField`'s ghost-origin math
    /// (`firstRect(forCharacterRange:)`, A-F5) needs a window to convert
    /// screen coordinates, and its `NSTextView` subclass re-runs
    /// `applyStyles()` the moment `viewDidMoveToWindow()` fires (see that
    /// override's doc comment). Found empirically: in THIS offscreen,
    /// single-shot capture harness, that first `viewDidMoveToWindow` call
    /// lands one layout pass before the text container has generated
    /// glyphs for the just-set `query` text, so the very first ghost
    /// position comes out wrong (measured: pinned to the field's left
    /// edge, overlapping the typed text, in a dedicated debug test written
    /// to chase this down). A second `layoutSubtreeIfNeeded()` pass closes
    /// the gap — confirmed against the same debug test. Every OTHER
    /// snapshot in this file renders pure SwiftUI content with no
    /// `NSViewRepresentable` in it, so this dependency is specific to
    /// Step 7 and this helper is kept separate from `renderPNG` rather
    /// than adding a second layout pass there for content that doesn't
    /// need it.
    private func renderPNGWithExtraLayoutPass<Content: View>(
        _ content: Content,
        appearance: NSAppearance.Name,
        size: NSSize
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
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

    /// Fix 7 (review): six tests below previously asserted only
    /// `#expect(image != nil)` — true for ANY non-zero view, including a
    /// blank card with no rows, no controls, and no empty-state affordance
    /// at all (a `bitmapImageRepForCachingDisplay` capture of a flat
    /// `.regularMaterial` rectangle is still a non-nil PNG). This counts
    /// pixels meaningfully darker (light mode: luminance `< 150`) or
    /// brighter (dark mode: luminance `>= 120`) than a genuinely blank
    /// card+border produces on its own — measured directly against a bare
    /// `RoundedRectangle.stroke` card with no content: 12 such pixels in
    /// light mode, 0 in dark (border-stroke antialiasing only).
    ///
    /// LIMITATION, stated plainly: over the WHOLE image (no `y` bound) this
    /// guards against a genuinely blank card only — it does NOT distinguish
    /// "the results area rendered its content" from "only the field's own
    /// ghost/placeholder text rendered", because that text alone already
    /// clears the threshold (mutant-verified: removing `addProjectRow`
    /// entirely left this passing, see `resultsAreaContainsContent` below
    /// for the fix used where that distinction matters). Used here only for
    /// the DARK-mode captures, where the stronger, row-specific checks
    /// (`selectionHighlightPixelCount`, `resultsAreaContainsContent`) were
    /// not re-validated against dark-mode color math.
    private func containsRenderedContent(in data: Data, isDark: Bool) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                let luminance = (r + g + b) / 3
                if isDark ? luminance >= 120 : luminance < 150 {
                    count += 1
                    if count > 100 { return true }
                }
            }
        }
        return false
    }

    /// Fix 7 (review), step 4 specifically: `containsRenderedContent` above
    /// stayed true against a mutant that deleted `addProjectRow` entirely
    /// (rendered `EmptyView()` instead), because the field's own "Add a
    /// project to begin" ghost text — unrelated to G-F7's empty-state row —
    /// already cleared the threshold. Scoped to `y >= 90` (backing pixels),
    /// the field/results-area boundary re-measured after the results-well
    /// hugging fix (`ComposerResultsTable` no longer forces a tall well
    /// with dead space, so content sits much closer to the field than the
    /// old 280 boundary assumed — remeasured directly against this
    /// fixture: field ghost text spans `y` 44-70, the empty-state row spans
    /// `y` 128-151, `debugStep4ZeroProjectPositions` in
    /// `ComposerDesignCallRenderTests`, untracked harness), so this only
    /// sees the results area, never the field.
    private func resultsAreaContainsContent(in data: Data, isDark: Bool) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 90, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                let luminance = (r + g + b) / 3
                if isDark ? luminance >= 120 : luminance < 150 {
                    count += 1
                    if count > 20 { return true }
                }
            }
        }
        return false
    }

    /// Fix 7 (review): a text-luminance count alone can't distinguish "rows
    /// rendered" from "one line of empty-state copy rendered" — both are
    /// gray text of similar pixel mass, and `containsRenderedContent` above
    /// stayed true against a mutant that zeroed every lane's options,
    /// because the field's own ghost text still cleared its threshold.
    /// This counts pixels tinted toward `Color.accentColor` — the
    /// selection highlight (`Color.accentColor.opacity(0.2)`, `#5B8DEF`)
    /// `onAppear`'s S5 seed ALWAYS paints on row 0 whenever
    /// `flattenedOptions` is non-empty. `b - r > 8` isolates it: neutral
    /// gray text/background/border have `b == r`; the blue accent tint
    /// does not. Mutant-verified directly (see report): forcing every lane
    /// empty dropped this from 9485 to 0 at this exact render size/stride —
    /// LIGHT MODE ONLY (`lane-light`/`plain-light`/`step5-light` all have a
    /// selectable row 0 by construction).
    private func selectionHighlightPixelCount(in data: Data) -> Int {
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

    /// Card-relative scope anchor for `ghostGrayBandPixelCount`/
    /// `ghostGrayBandYSpan` below. Finds the topmost row containing any
    /// opaque pixel (alpha `> 0.5`) — the card's own top edge, since the
    /// window around it is `.clear` (alpha 0) while the card surface
    /// (`.regularMaterial` + border) is opaque. Same technique as
    /// `ComposerCardFitTests.opaqueVerticalExtent` (`composer-ghost-and-well-s2`),
    /// reduced to just the top row since that is all this scope needs.
    ///
    /// This exists because `y < 100` used to be measured from the IMAGE
    /// top, which only worked while the card itself also started near the
    /// image top. `13011dffa` (the results-well hugging fix, this same
    /// branch) made `ComposerResultsTable`'s height cap real — a short
    /// fixture's card is now genuinely shorter than this file's fixed
    /// 420pt render frame, and `renderPNG`/`renderPNGWithExtraLayoutPass`'s
    /// `content.frame(width:height:)` center-aligns a shorter view inside
    /// that larger frame by default. Measured directly (three fixtures,
    /// `docs/plans/composer-ui-11/evidence/`): the card's top edge moved
    /// from backing-pixel `y=16` to `y=192` — a 176px (88pt at this
    /// render's 2x backing scale) downward shift — carrying the ghost
    /// text's own gray-band pixels from `y=44-65` to `y=220-246` with it
    /// (same row-count fingerprint at both positions, just translated).
    /// An absolute band, at ANY fixed number, breaks again the next time
    /// the card's natural height changes; scoping to the card's own
    /// measured top edge survives that.
    private func cardTopEdge(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        for y in 0..<rep.pixelsHigh {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    return y
                }
            }
        }
        return nil
    }

    /// Variant G Pass A: `cardTopEdge`'s mirror, scanning from the image's
    /// bottom row upward for the first opaque pixel — the card's own bottom
    /// edge, same technique/rationale as `cardTopEdge` above. Paired with it
    /// to measure a fixture's total card height
    /// (`emptyLanesRenderNoHeaderOrExtraSpace` below) — a spurious header
    /// rendered for an empty lane (the guard this test exists to catch)
    /// adds real height between top and bottom edge, so no text-recognition
    /// is needed to detect it.
    private func cardBottomEdge(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        for y in stride(from: rep.pixelsHigh - 1, through: 0, by: -1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    return y
                }
            }
        }
        return nil
    }

    /// Fix 7 (review), step 3 specifically: counts pixels in the exact gray
    /// band the 11.1 ghost placeholder renders at rest — was
    /// `Color(nsColor: .labelColor).opacity(0.49)` over the card's
    /// near-white light-mode background, `rgb(149,149,149)`; went to 0.65
    /// for the AA-contrast fix (measured `rgb(115,115,115)`), then to 0.50
    /// (Sean's call, deliberately below AA — see `ComposerQueryField
    /// .ghostPlaceholderOpacity`'s doc comment), which measures
    /// `rgb(147,147,147)` at this same fixture
    /// (`ComposerDesignCallRenderTests.ghost050Evidence`, untracked
    /// harness) — close to the original 0.49 value since 0.50 is nearly
    /// the same alpha. A band (137-157, near-equal channels), not an exact
    /// triple, to tolerate antialiasing at glyph edges.
    ///
    /// This literal is NOT derived from a production symbol — `137-157`
    /// cannot be computed cleanly from `ComposerQueryField
    /// .ghostPlaceholderOpacity`/`ComposerGhostTextField.ghostOpacity`
    /// alone. Both are SwiftUI/AppKit `.opacity`-style alpha multipliers
    /// composited against `labelColor` (itself ~0.85 alpha,
    /// `ComposerGhostTextField.ghostAlpha`'s doc comment) over the card's
    /// dynamic `.regularMaterial` background — reproducing the exact
    /// rendered RGB would require guessing labelColor's own RGB and the
    /// material's effective background RGB at render time, which is a
    /// second hardcoded guess, not fewer. If `ghostOpacity`/
    /// `ghostPlaceholderOpacity` (currently `0.50`) changes, re-measure
    /// this band empirically the same way the 0.49 -> 0.65 -> 0.50 history
    /// above did (`ComposerDesignCallRenderTests`, untracked harness) and
    /// update the two literals below.
    ///
    /// Scoped to `cardTopEdge(in:)...cardTopEdge+100` (backing pixels) —
    /// WITHOUT some upper bound, this mutant-verified false GREEN on a
    /// 0.49 -> 0.03 opacity mutation (the ghost went near-invisible, but
    /// the band count barely dropped) because `makePlainComposer`'s
    /// template ROWS below the field render their own `.secondary`-styled
    /// subtitle text in a nearby luminance band. Card-relative, not image-
    /// relative (see `cardTopEdge(in:)`'s doc comment for why) — measured
    /// directly at both the pre-hugging-fix and post-hugging-fix card
    /// positions: the field's own ghost text sits ~28-54px below the
    /// card's top edge at either position, the next row-content band sits
    /// ~170-180px below it. A 100px window leaves margin on both sides at
    /// either position. LIGHT MODE ONLY, same limitation this file's
    /// `darkestGhostPixel` already documents for dark mode.
    private func ghostGrayBandPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        guard let cardTop = cardTopEdge(in: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: cardTop, to: min(cardTop + 100, rep.pixelsHigh), by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.9 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r >= 137, r <= 157, g >= 137, g <= 157, b >= 137, b <= 157, abs(r - g) < 3, abs(g - b) < 3 {
                    count += 1
                }
            }
        }
        return count
    }

    /// Fix 1 (review, long-path capture): measures the y-range spanned by
    /// the ghost gray-band pixels (`ghostGrayBandPixelCount`'s color test,
    /// same 137-157 luminance band / near-neutral tolerance), scoped to the
    /// same card-relative field region (`cardTopEdge(in:)...cardTopEdge+100`
    /// — see `ghostGrayBandPixelCount`'s doc comment). A single line of
    /// ghost text spans a tight y-range (glyph ascender to descender,
    /// ~15-20px at this font size); a wrap regression back to two stacked
    /// lines roughly doubles it. Returns nil if no matching pixels were
    /// found at all.
    private func ghostGrayBandYSpan(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        guard let cardTop = cardTopEdge(in: data) else { return nil }
        var minY: Int?
        var maxY: Int?
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: cardTop, to: min(cardTop + 100, rep.pixelsHigh), by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.9 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r >= 137, r <= 157, g >= 137, g <= 157, b >= 137, b <= 157, abs(r - g) < 3, abs(g - b) < 3 {
                    minY = min(minY ?? y, y)
                    maxY = max(maxY ?? y, y)
                }
            }
        }
        guard let minY, let maxY else { return nil }
        return maxY - minY
    }

    /// DEFECT 6 fix (review round 2): round 1 added `assertEvidenceMatchesDisk`
    /// (below `writeEvidence` originally) claiming to guard against the
    /// stale-PNG class (`fb09ce9c9`'s PNGs were committed without being
    /// re-rendered from the build that fixed them — two full review rounds
    /// burned catching it by eye). It was tautological: it ran immediately
    /// after `writeEvidence` wrote that exact `Data` to that exact path, so
    /// it could only fail on a filesystem write error — it never touched
    /// the actual root cause (a human committing an OLD png alongside NEW
    /// code) and was applied to only 2 of 16 artifacts in this file.
    /// Removed rather than left as a pretense of coverage.
    ///
    /// PROCESS NOTE, not a test (this genuinely cannot be verified at test
    /// RUN time — a test has no visibility into what gets `git add`ed
    /// after it passes, and no in-process check can distinguish "freshly
    /// rendered" from "rendered in a prior run, never re-generated"): every
    /// commit that changes rendering-affecting production code in
    /// `ComposerGhostTextField.swift` or `SessionComposerPalette.swift`
    /// MUST re-run this file's tests and stage the resulting PNGs under
    /// `docs/plans/composer-ui-11/evidence/` in the SAME commit as the code
    /// change — never carry a PNG forward from a prior commit. Verify with
    /// `git status --short docs/plans/composer-ui-11/evidence/` before
    /// committing: every PNG touched by the code change must show as
    /// modified, not absent from the diff.
    private func writeEvidence(_ data: Data?, filename: String) {
        guard let data else {
            Issue.record("Failed to render PNG for \(filename)")
            return
        }
        let dir = evidenceDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
        } catch {
            Issue.record("Failed to write \(filename): \(error)")
        }
    }

    /// Builds an isolated composer, pre-seeded with one pin and one recent
    /// selection distinct from the pin (so the lane-state PNG shows both a
    /// `.pinned` and a `.recent` row) — `dispatchOverrideForTesting` keeps
    /// `precommit` (used only to exercise the real `recordRecent` write
    /// path) from touching `WorkspaceStore.shared`/a real coordinator.
    private func makeLaneStateComposer(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.dispatchOverrideForTesting = { _, _ in }

        let templates = workspaceStore.templates
        guard templates.count >= 2 else { return composerStore }
        let pinned = templates[0]
        let recent = templates[1]

        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        _ = composerStore.precommit(template: recent, coordinator: SessionCoordinator(), workspaceStore: workspaceStore)

        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        composerStore.togglePin(templateId: pinned.id)

        // Leave it open, ready to mount — matches what `.onAppear` would do
        // on a fresh popover open.
        return composerStore
    }

    private func makePlainComposer(project: Project, workspaceStore: WorkspaceStore) -> SessionComposerStore {
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .locked(project), workspaceStore: workspaceStore)
        return composerStore
    }

    private func paletteView(project: Project, workspaceStore: WorkspaceStore, composerStore: SessionComposerStore) -> some View {
        SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .locked(project)),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
    }

    // MARK: - Lane state (pins + recents)

    @Test func laneStateWithPinsAndRecentsRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makeLaneStateComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step2-lane-state-light.png")
        #expect(light != nil)
        if let light {
            let highlightCount = selectionHighlightPixelCount(in: light)
            #expect(highlightCount > 100, "expected a selected pinned/recent row 0, found \(highlightCount) accent-tinted pixels — a near-blank card would pass a plain text-content check")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step2-lane-state-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected pinned/recent rows to render, got a near-blank card") }
    }

    // MARK: - Plain templates state (no pins, no recents)

    @Test func plainTemplatesStateRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step2-plain-templates-light.png")
        #expect(light != nil)
        if let light {
            let highlightCount = selectionHighlightPixelCount(in: light)
            #expect(highlightCount > 100, "expected a selected template row 0, found \(highlightCount) accent-tinted pixels — a near-blank card would pass a plain text-content check")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step2-plain-templates-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected template rows to render, got a near-blank card") }
    }

    // MARK: - Step 3: rest-state ghost path (11.1)

    /// A fresh, empty-search composer against a resolvable, unlocked
    /// project — `onAppear`'s S5 seed selects the project's default
    /// template, so the ghost placeholder renders the FULL path (rule 1),
    /// comparable side-by-side with `V02Quieted22.dc.html`'s rest state
    /// (one grey, full path, no sub-ranges).
    ///
    /// LIMITATION: this repo's HEAD already has Step 5 (resolution-line
    /// deletion) landed, so this capture necessarily shows the
    /// post-Step-5 layout — there is no pre-deletion build left to render
    /// against. It still evidences Step 3's actual subject, the ghost
    /// path's rendering/opacity, which Step 5 doesn't touch; it just isn't
    /// a capture of "Step 3 layout in isolation" as the original plan
    /// framed it. Do not read the resolution line's absence here as new
    /// information about Step 3.
    @Test func step3RestStateGhostPathRendersLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step3-rest-ghost-path-light.png")
        #expect(light != nil)
        // Fix 7 (review): asserts the ghost actually renders IN the correct
        // gray band (`rgb(147,147,147)` at the shipped 0.50 opacity,
        // measured — see `ghostGrayBandPixelCount`'s doc comment), not just
        // that some PNG came back. The threshold (50) is a wide margin
        // under the actual matching-pixel count at this exact render
        // size/stride, catching a missing/wrong-opacity ghost without being
        // brittle to minor layout drift.
        if let light {
            let bandCount = ghostGrayBandPixelCount(in: light)
            #expect(bandCount > 50, "expected the rest-state ghost's rgb(147,147,147) band, found \(bandCount) matching pixels")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step3-rest-ghost-path-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected the rest-state ghost/card content to render, got a near-blank card") }
    }

    /// Fix 1 (review): a long, realistic resolved path — this repo's own
    /// `ghostties > feat/composer-ui-11 > Orchestrator` is 45 characters,
    /// over the ~42-char field width at `.centered` — used to WRAP to a
    /// second line inside the fixed-height 38pt field before `.lineLimit(1)`/
    /// `.truncationMode(.tail)` were added. Every OTHER fixture in this file
    /// uses `"Demo Project"` + a built-in template name, both under 42
    /// chars, which is why no prior pixel caught it. Pixel-guards it going
    /// forward: the gray-band pixels (the ghost text) must stay within a
    /// SINGLE line's y-span — a regression back to wrapping would spread
    /// them across two stacked lines, roughly doubling the span.
    @Test func step3RestStateGhostPathLongPathTruncatesLightAndDark() {
        let project = Project(
            name: "ghostties-composer-ui-eleven-long-project-name",
            rootPath: "/tmp/composer-ui-11-snapshot-long-\(UUID().uuidString)"
        )
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step3-rest-ghost-long-path-light.png")
        #expect(light != nil)
        if let light {
            let bandCount = ghostGrayBandPixelCount(in: light)
            #expect(bandCount > 50, "expected the long-path ghost's rgb(147,147,147) band, found \(bandCount) matching pixels")
            let ySpan = ghostGrayBandYSpan(in: light)
            #expect(ySpan != nil && ySpan! < 35, "expected the long path to truncate on ONE line (y-span < 35 — single-line antialiasing measured at 26, a wrapped second line would roughly double it), measured span \(String(describing: ySpan)) — a wrap regression spreads the ghost across two stacked lines")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step3-rest-ghost-long-path-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected the long-path ghost/card content to render, got a near-blank card") }
    }

    // MARK: - Step 5: resolution line deleted, trailing controls shown

    /// An UNLOCKED project (`.open`, not `.locked`) so `projectControl`
    /// renders — `trailingControlVisibility`'s locked-hides-projectControl
    /// branch is covered structurally by `SessionComposerTrailingControlTests`,
    /// not a second screenshot. Proves the resolution line is gone (field +
    /// hairline + rows only) and the trailing controls are the field row's
    /// mouse route now.
    @Test func step5LineDeletedShowsTrailingControlsLightAndDark() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step5-line-deleted-light.png")
        #expect(light != nil)
        if let light {
            let highlightCount = selectionHighlightPixelCount(in: light)
            #expect(highlightCount > 100, "expected a selected row 0 (rows survived the resolution-line deletion), found \(highlightCount) accent-tinted pixels")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step5-line-deleted-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected the field/hairline/rows/trailing controls to render, got a near-blank card") }
    }

    // MARK: - Step 3: ghost placeholder opacity

    /// Pins `ComposerQueryField.ghostPlaceholderOpacity` — the production
    /// symbol the overlay `Text` actually renders with — to the shipped
    /// design value, 0.50 (`DESIGN.md` §4, Sean's call looking at the real
    /// build; deliberately below the 0.65 that cleared WCAG AA — see the
    /// constant's own doc comment for the full history and the honest AA
    /// status). Guards against a regression back to the `prompt:` route's
    /// un-honoured `.foregroundColor`, which measured at ~0.83
    /// (`step3-rest-ghost-path-light.png`'s darkest pixel, `rgb(64,64,64)`
    /// against a white ground) — NOT an AA-floor guard; this test would
    /// pass at any deliberately-chosen value equal to the constant.
    @Test func ghostPlaceholderOpacityMatchesDesignSpec() {
        #expect(ComposerQueryField.ghostPlaceholderOpacity == 0.50)
    }

    /// Design-spec pin, NOT an AA guarantee — mirrors
    /// `ComposerGhostTextFieldTests.ghostOpacityMatchesDesignSpec`. The
    /// shipping default field's ghost went 0.49 → 0.65 (cleared WCAG AA
    /// 4.5:1) → 0.50 (Sean's call, does NOT clear AA — measured ≈3.0:1
    /// light mode). This only pins the shipped value so an UNINTENTIONAL
    /// further drift still fails loudly; it does not assert accessibility
    /// compliance. References the production symbol directly, not a
    /// re-declared literal, so a regression away from 0.50 fails this test
    /// instead of silently passing.
    @Test func ghostPlaceholderOpacityDoesNotSilentlyRegress() {
        #expect(
            ComposerQueryField.ghostPlaceholderOpacity == 0.50,
            "ghostPlaceholderOpacity drifted from 0.50, the shipped design value (deliberately below WCAG AA — Sean's call)"
        )
    }

    /// The two ghost-opacity constants (`ComposerQueryField.ghostPlaceholderOpacity`,
    /// model A/shipping default, and `ComposerGhostTextField.ghostOpacity`,
    /// model B/experimental) are deliberately kept in lockstep so the two
    /// fields render the same ghost — see either constant's doc comment.
    /// This is exactly the drift `def5e9cd4` introduced (raised one, not
    /// the other); this test fails the moment they diverge again.
    @Test func ghostOpacityConstantsStayInLockstep() {
        #expect(ComposerQueryField.ghostPlaceholderOpacity == Double(ComposerGhostTextField.ghostOpacity))
    }

    // MARK: - Step 4: zero-project empty state

    /// Zero projects anywhere (`WorkspaceStore(testingProjects: [], ...)`)
    /// — the ghost placeholder falls to "Add a project to begin" (Step 3
    /// rule 3) and the results area renders the "Add project…" row instead
    /// of a dead-end "No matches" (G-F7).
    @Test func step4ZeroProjectEmptyStateRendersLightAndDark() {
        let workspaceStore = WorkspaceStore(testingProjects: [], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "step4-zero-project-light.png")
        #expect(light != nil)
        if let light { #expect(resultsAreaContainsContent(in: light, isDark: false), "expected the 'Add project…' empty-state row to render in the results area, found none") }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "step4-zero-project-dark.png")
        #expect(dark != nil)
        if let dark { #expect(containsRenderedContent(in: dark, isDark: true), "expected the 'Add project…' empty-state row to render, got a near-blank card") }
    }

    // MARK: - Variant G Pass A: section headers, empty-lane guard

    /// `ComposerResultsTable` (Variant G Pass A) renders a visible header
    /// for each of the four lanes (RECENT/TEMPLATES/PROJECTS/COMMAND) but
    /// ONLY when that lane has at least one option — the guard is
    /// `if !section.options.isEmpty` around BOTH the header `Text` and the
    /// row `ForEach`, one shared code path for all four lanes. This reuses
    /// the zero-project fixture (`step4ZeroProjectEmptyStateRendersLightAndDark`'s
    /// setup): with no projects anywhere, ALL FOUR lanes are structurally
    /// empty (`lane1Options`/`lane2Options`/`filteredProjectOptions`/
    /// `commandOptions` all `[]`), so a correct guard renders zero headers
    /// and the card's total measured height (`cardTopEdge`...`cardBottomEdge`)
    /// stays small — just the field, divider, and the single "Add
    /// project…" empty-state row.
    ///
    /// Review round 4, P1-b fix: round 2 measured this fixture WITHOUT
    /// pinning `ComposerGhostTextField.modelBFieldStorageKey`, against a
    /// process-global `UserDefaults.standard` that five OTHER tests in this
    /// file flip `true` for their own duration (same mechanism
    /// `operatorFooterStripRendersWhenOperatorsAreLive` and
    /// `footerStripAbsentWhenOperatorListIsEmpty` below pin against). With
    /// the flag contaminated `true`, this `.centered`/zero-project fixture's
    /// `ghostPlaceholder` returns a non-empty remainder, `hasGhostRemainder`
    /// goes true, and a spurious 26pt (52px at 2x) operator strip renders —
    /// round 2 measured THAT contaminated 275px and wrote it into this
    /// comment as the correct baseline, with a 295 threshold tuned to sit
    /// just above it. The mutant this test exists to catch (a spuriously
    /// rendered section header) was passing green either way.
    ///
    /// Re-measured here with the flag explicitly pinned `false` (this
    /// fixture never uses model B — pinning only removes the shared-global
    /// hazard): correct code measures 223px, matching
    /// `footerStripAbsentWhenOperatorListIsEmpty`'s own measurement of this
    /// identical fixture exactly, as it should — same projects, same
    /// presentation, same empty lanes. Deleting the
    /// `!section.options.isEmpty` guard (`if true`, all 4 lanes render a
    /// header with zero rows beneath it) measures 271px — a 48px growth
    /// for one spurious header, confirming round 2's per-header estimate.
    /// This test's threshold (260) sits with 37px of margin above the
    /// correct build's 223 and 11px below the one-header mutant's 271.
    @Test func emptyLanesRenderNoHeaderOrExtraSpace() {
        // Pin model B off for the duration of this render — see this test's
        // doc comment above and the matching idiom in
        // `operatorFooterStripRendersWhenOperatorsAreLive` below. Without
        // this, a test running concurrently in the same process can
        // transiently leave the global flag `true` here.
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let workspaceStore = WorkspaceStore(testingProjects: [], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "variant-g-empty-lanes-no-header-light.png")
        #expect(light != nil)
        guard let light,
              let top = cardTopEdge(in: light),
              let bottom = cardBottomEdge(in: light)
        else {
            Issue.record("failed to render or measure the card's opaque bounds")
            return
        }
        let height = bottom - top
        #expect(
            height < 260,
            "card measured \(height)px tall (top \(top), bottom \(bottom)) with zero populated lanes — expected under 260px (field + divider + one empty-state row); a single spuriously rendered header for an empty lane measures 271px, past this threshold"
        )
    }

    // MARK: - Step 7: model B ghost field (UNVERIFIED-INTERACTION)

    /// Scans a PNG for its darkest non-black pixel (excludes true black,
    /// which this card never intentionally paints, to avoid a stray
    /// 1px seam/border pixel winning over the actual ghost glyph fill).
    /// Same technique this repo used to catch the `prompt:` route's
    /// un-honoured opacity (`ghostPlaceholderOpacityMatchesDesignSpec`'s
    /// doc comment, `rgb(64,64,64)` measured that way).
    /// The typed text (`"Gho"`, `#1A1A1A` at full opacity) is DARKER than
    /// the ghost (`ComposerGhostTextField.ghostOpacity`, 65% alpha as of
    /// the AA-contrast fix), so a plain "darkest pixel in the whole image"
    /// scan always finds the typed text, not the ghost — verified against
    /// this exact PNG (measured column extents, post review-fix set:
    /// `"Gho"`'s solid fill spans roughly x:1–43, the ghost's spans
    /// roughly x:49–101, at 2x backing scale — a small but real gap
    /// between them, NOT the overlap an earlier revision of this comment
    /// claimed; see `ComposerGhostTextField.applyStyles()`'s fix-5 doc
    /// comment for the honest measurement and why it isn't fully closed.
    /// LIGHT mode only — this per-channel "near-black" heuristic does not
    /// hold in dark mode, where typed text is near-WHITE, not
    /// near-black). This isolates the ghost's region instead: finds the
    /// last column containing a per-channel near-black pixel (each
    /// component `< 60`) — the typed text's own solid fill — then scans
    /// strictly to the right of it for the darkest non-white pixel, which
    /// is the ghost's own solid fill.
    private func darkestGhostPixel(in data: Data) -> (r: Int, g: Int, b: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var lastTypedTextColumn = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r < 60, g < 60, b < 60 { lastTypedTextColumn = x }
            }
        }

        var darkest: (r: Int, g: Int, b: Int)?
        var darkestSum = Int.max
        for x in (lastTypedTextColumn + 3)..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                guard !(r == 255 && g == 255 && b == 255) else { continue }
                let sum = r + g + b
                if sum < darkestSum {
                    darkestSum = sum
                    darkest = (r, g, b)
                }
            }
        }
        return darkest
    }

    /// Step 7 (Composer UI 11 plan §5/§7, evidence contract §6): flag ON,
    /// `ComposerGhostTextField` rendered directly (not through
    /// `SessionComposerPalette` — the flag is default OFF there, and this
    /// evidence targets the field's OWN rendering, not the swap point,
    /// which `ComposerGhostTextFieldTests.flagDefaultsToOff…` already
    /// covers). `query` is `Gho`, `ghostFullPath` is the same shape D-B's
    /// model A source produces — the ghost should render the FULL
    /// remainder `stties > Default > Orchestrator` in grey per
    /// `remainderGhostReturnsTheWholeRemainderNotJustTheCurrentSegment`
    /// (the corrected, Spotlight-inline-completion semantics — not
    /// truncated at the next segment separator).
    ///
    /// UNVERIFIED-INTERACTION: this proves the ghost RENDERS off-screen at
    /// construction time, in an app-hosted, non-key window — nothing about
    /// typing, scrolling, or focus (plan §7's manual key matrix, still
    /// entirely undriven).
    @Test func step7ModelBGhostFieldRendersLightAndDark() {
        let field = ComposerGhostTextField(
            query: .constant("Gho"),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: .constant(false),
            hasSelection: false,
            isPickerOpen: false,
            ghostFullPath: "Ghostties > Default > Orchestrator"
        ) { _ in }
        let view = field.background(Color(nsColor: .windowBackgroundColor))
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth, height: 38)

        let lightData = renderPNGWithExtraLayoutPass(view, appearance: .aqua, size: size)
        writeEvidence(lightData, filename: "step7-modelb-light.png")
        #expect(lightData != nil)

        let darkData = renderPNGWithExtraLayoutPass(view, appearance: .darkAqua, size: size)
        writeEvidence(darkData, filename: "step7-modelb-dark.png")
        #expect(darkData != nil)

        // Ghost pixel measurement (acceptance criterion 5). Fix 7 (review):
        // this used to print either branch and stay green unconditionally —
        // a MISSING ghost (A-F2 reproducing) passed silently. Now asserts
        // presence explicitly. Does NOT hard-assert an exact RGB triple —
        // AppKit font rendering/hinting makes the exact darkest antialiased
        // pixel environment-dependent, and `ComposerGhostTextField.swift`
        // itself is out of scope for this fix set — but DOES assert the
        // pixel is neutral gray (the only property the ghost's own color
        // math can produce, whatever the exact opacity), so a colored or
        // clipped-to-black regression still fails loudly.
        if let lightData {
            let pixel = darkestGhostPixel(in: lightData)
            #expect(pixel != nil, "step7-modelb-light.png: no ghost pixel found — possible A-F2 regression (ghost clipped/missing)")
            if let pixel {
                print("step7-modelb-light.png darkest ghost-region pixel: rgb(\(pixel.r),\(pixel.g),\(pixel.b))")
                #expect(
                    abs(pixel.r - pixel.g) < 3 && abs(pixel.g - pixel.b) < 3,
                    "expected a neutral gray ghost pixel, got rgb(\(pixel.r),\(pixel.g),\(pixel.b))"
                )
            }
        }
    }

    /// Acceptance criterion 1: the worked example. Field is scoped to
    /// project `ghostties`; the user types `bruk`, and the row `Brukas` —
    /// a DIFFERENT project — highlights. The field must read `Bruk`
    /// (typed, solid) + `as > Default > Shell` (ghosted): `Brukas`'s OWN
    /// destination, not `ghostties`'s. `ghostFullPath` here is the literal
    /// string `SessionComposerPalette.destination(for:store:
    /// recentSelections:)` produces for a fixture `Brukas` project with no
    /// `defaultTemplateId`/recent selection
    /// (`SessionComposerModelBGhostSourceTests
    /// .projectWithNoDefaultOrRecentLandsOnTheFirstAvailableTemplate`
    /// proves that function call directly) — this test proves the
    /// RENDERING half, matching this file's existing precedent of
    /// constructing `ComposerGhostTextField` directly rather than
    /// threading the whole `SessionComposerPalette`/`selectedOption`
    /// machinery through an offscreen window.
    ///
    /// Deviation from the brief's literal example, stated plainly: the
    /// branch segment renders `Default`, not `main`. Real git branch data
    /// for a project OTHER than the composer's `currentProject` doesn't
    /// exist anywhere in this store — `SessionComposerStore` caches
    /// `currentBranchAtProjectRoot` for the single scoped project only,
    /// refreshed by an async git call this task does not add (out of
    /// scope: `SessionComposerStore` git/persistence plumbing). `Default`
    /// is the same "no override" fallback `resolutionLineSegments` already
    /// uses elsewhere in this composer, not a new placeholder invented for
    /// this task.
    @Test func workedExampleGhostsADifferentProjectsFullPath() {
        let field = ComposerGhostTextField(
            query: .constant("Bruk"),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: .constant(false),
            hasSelection: true,
            isPickerOpen: false,
            ghostFullPath: "Brukas > Default > Shell"
        ) { _ in }
        let view = field.background(Color(nsColor: .windowBackgroundColor))
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth, height: 38)

        let lightData = renderPNGWithExtraLayoutPass(view, appearance: .aqua, size: size)
        writeEvidence(lightData, filename: "step7-worked-example-bruk-light.png")
        #expect(lightData != nil)

        let darkData = renderPNGWithExtraLayoutPass(view, appearance: .darkAqua, size: size)
        writeEvidence(darkData, filename: "step7-worked-example-bruk-dark.png")
        #expect(darkData != nil)

        if let lightData {
            let pixel = darkestGhostPixel(in: lightData)
            #expect(pixel != nil, "step7-worked-example-bruk-light.png: no ghost pixel found — the field disagreed with the highlighted row, defect 1 regressed")
        }

        // The ghost-computation proof itself (acceptance criterion 1's
        // "field must read" claim, not just "a grey pixel exists
        // somewhere"): construct the same coordinator this rendering used
        // and assert its `currentGhostText` directly.
        let coordinator = field.makeCoordinator()
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = ComposerGhostNSTextView(frame: .zero, textContainer: container)
        coordinator.textView = textView
        coordinator.installGhostLabel(in: textView)
        textView.string = "Bruk"
        coordinator.applyStyles()
        #expect(textView.currentGhostText == "as > Default > Shell")
    }

    // MARK: - Defect 1 class: mounted model B ghost tracks the highlighted
    // row, not `currentProject` (findings ledger F3/F6)

    /// F3's kill, verified directly: `selectedOption` derives from `@State
    /// private var selectedIndex` (`SessionComposerPalette.swift:87`),
    /// written ONLY from `.onAppear` and
    /// `.onChange(of: composerStore.searchText)`. A windowless construction
    /// of `ComposerGhostTextField` — like `workedExampleGhostsADifferentProjectsFullPath`
    /// above, or every test in `ComposerGhostTextFieldTests.swift` — hands
    /// it a literal `ghostFullPath` string and never exercises that binding
    /// chain at all, so it stays green even if `ghostFullPathForModelB`
    /// regressed to ignore `selectedOption` entirely (F6). This mounts the
    /// real `SessionComposerPalette`, flag ON, and drives a real keystroke
    /// through `composerStore.searchText` — the same property
    /// `searchTextBinding`'s setter writes — so the render can only pass if
    /// the whole `.onChange` → `reselectBestMatch()` → `selectedOption` →
    /// `ghostFullPathForModelB` chain is actually wired end to end.
    ///
    /// Deviation from a literal "set `searchText` before mounting": verified
    /// against `SessionComposerStore.open(projectBinding:workspaceStore:)`
    /// — it unconditionally resets `searchText = ""` on EVERY call,
    /// including the one `.onAppear` makes on first mount, so pre-seeding
    /// before the first layout pass is silently wiped the instant
    /// `.onAppear` fires. The chain this defect actually lives in is
    /// `.onAppear` (mount, empty query) THEN
    /// `.onChange(of: composerStore.searchText)` (typing) — this renders
    /// once to let `.onAppear` settle, mutates `searchText` exactly as
    /// `searchTextBinding`'s setter would, spins the run loop briefly so
    /// SwiftUI's Combine-driven update has a turn to reconcile (same
    /// technique as `TaskFileWatcherTests.swift:53`), then renders again.
    private func renderMountedPaletteAfterTyping(
        project: Project,
        workspaceStore: WorkspaceStore,
        composerStore: SessionComposerStore,
        typed: String,
        appearance: NSAppearance.Name,
        size: NSSize
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear

        // NOT `paletteView(...)` — that shared helper hardcodes
        // `.locked(project)`, and a locked composer's `filteredProjectOptions`
        // is unconditionally empty, which would hide `otherProject` from the
        // list this test needs it to appear in. Must match the
        // `.prefilled(currentProject)` binding `composerStore.open(...)`
        // above was called with.
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .prefilled(project)),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        // Settles `.onAppear` — `open()` + the empty-query default
        // selection.
        hosting.layoutSubtreeIfNeeded()

        // The production write path (`searchTextBinding`'s setter) also
        // calls this to disarm a pending chip-undo — matched here so this
        // is the same state transition a real keystroke produces, not a
        // shortcut that skips it.
        composerStore.noteSearchTextEditedByTyping()
        composerStore.searchText = typed
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        // Extra pass, same reason `renderPNGWithExtraLayoutPass` needs one:
        // `ComposerGhostTextField` is an `NSViewRepresentable`, and its
        // `viewDidMoveToWindow`-triggered `applyStyles()` lands one layout
        // pass ahead of the just-changed ghost text having generated glyphs.
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Table-driven over four (scoped project, typed prefix, other project)
    /// rows. The invariant under test, stated once: for any typed text that
    /// matches the highlighted row, the ghost is non-empty and previews
    /// THAT row's destination — never silently empty because the ghost
    /// stayed welded to `currentProject` (defect 1's class). Each row's
    /// "other" project name is chosen to share no substring with any
    /// built-in template title (`Shell`, `Claude Code`, `Orchestrator`,
    /// `Browser`, `Codex`) so `filteredProjectOptions`/`reselectBestMatch()`
    /// ranks it unambiguously above the current project's own template
    /// rows.
    @Test(
        "mounted model B ghost tracks the row a typed prefix highlights, not currentProject",
        arguments: [
            (current: "Ghostties", other: "Brukas", typed: "bruk"),
            (current: "Atlas", other: "Nautilus", typed: "naut"),
            (current: "Zephyr", other: "Cascade", typed: "casc"),
            (current: "Forge", other: "Meridian", typed: "MERID"),
        ]
    )
    @MainActor
    func mountedModelBGhostTracksHighlightedRowAcrossProjects(row: (current: String, other: String, typed: String)) {
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let currentProject = Project(
            name: row.current,
            rootPath: "/tmp/composer-ui-11-defect1-\(row.current)-\(UUID().uuidString)"
        )
        let otherProject = Project(
            name: row.other,
            rootPath: "/tmp/composer-ui-11-defect1-\(row.other)-\(UUID().uuidString)"
        )
        let workspaceStore = WorkspaceStore(testingProjects: [currentProject, otherProject], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        // `.prefilled`, not `.locked` — a locked composer's
        // `filteredProjectOptions` is unconditionally empty
        // (`!isProjectLocked` guard), so `otherProject` could never appear
        // in the list to highlight at all.
        composerStore.open(projectBinding: .prefilled(currentProject), workspaceStore: workspaceStore)

        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)
        let light = renderMountedPaletteAfterTyping(
            project: currentProject,
            workspaceStore: workspaceStore,
            composerStore: composerStore,
            typed: row.typed,
            appearance: .aqua,
            size: size
        )
        writeEvidence(light, filename: "defect1-mounted-\(row.other.lowercased())-light.png")
        #expect(light != nil)
        if let light {
            let bandCount = ghostGrayBandPixelCount(in: light)
            #expect(
                bandCount > 50,
                "typed \"\(row.typed)\" against \(row.other) (scoped to \(row.current)): expected a non-empty ghost in the field's gray band, found \(bandCount) matching pixels — the ghost stayed welded to currentProject instead of following the highlighted row"
            )
        }
    }

    // MARK: - Variant G Pass B: contextual operator footer strip

    /// The operators-live fixture: a locked project with the app's own
    /// built-in template set (`makePlainComposer`) seeds `onAppear`'s
    /// selection at row 0 (`hasSelection`) against more than one option
    /// (`hasMultipleOptions`) — `footerOperators` resolves to `[↵ open,
    /// ↑↓ navigate]`, `⇥`/`⌘Z` absent (model B off by default, no chip
    /// cascade pending). Evidences acceptance criteria 6 (footer renders
    /// at spec) directly; criterion 4 (precedence) is proven at the pure-
    /// function level by `SessionComposerFooterSlotTests` above — no error
    /// and no in-flight template naming compete for the position in this
    /// fixture, so the operator branch is what's under test here.
    ///
    /// Asserts by measured card height (`cardTopEdge`...`cardBottomEdge`),
    /// NOT a divider-line pixel search — an earlier draft of this test
    /// tried scanning for the strip's 1pt `.separatorColor` line by
    /// "near-full-width, near-uniform row," and that signature turned out
    /// to also match blank card background between rows (mutant-verified:
    /// forcing the `.operators` case to render `EmptyView()` still found a
    /// "divider" and still passed). Height is the reliable signal —
    /// mutant-verified directly against THIS fixture: correct code
    /// measures 555px, forcing `.operators` to `EmptyView()` (no strip at
    /// all) measures 503px, a clean 52px (26pt at this render's 2x backing
    /// scale) gap matching the footer's own spec height exactly — matches
    /// review round 2's numbers exactly, re-measured, not just trusted.
    /// Upper-bounded at 580 (25px margin below 555) so a mutant that
    /// over-renders (e.g. a doubled strip) doesn't slip past a lower-bound-
    /// only check.
    ///
    /// KNOWN CAVEAT, re-derived and NOT what review round 2 estimated:
    /// `AgentTemplate.defaults` growing by exactly one row does not survive
    /// this band. Measured directly (temporarily seeding one extra custom
    /// template into this same fixture, then reverted): correct code moves
    /// to 613px, but the NO-STRIP mutant ALSO moves to 561px — inside
    /// 530-580, so that specific (+1 template AND no strip) combination
    /// would pass incorrectly. Review round 4: that framing understates the
    /// risk — the LOUDER half is that correct code itself lands at 613px,
    /// OUTSIDE the 530-580 band. The next person to add a fifth default
    /// template hits a hard RED on entirely correct code before they ever
    /// hit the quieter false-green above; that false red is the one
    /// they'll actually see and have to diagnose. The strip-vs-no-strip gap
    /// stays a constant ~52-58px regardless of template count; growth
    /// shifts the whole pair upward together, not apart, so no single fixed
    /// band survives arbitrary future growth — only a relational assertion
    /// against a live-measured no-operators baseline would. Out of scope
    /// for this pass (asked-for fix was tightening this into a band, not a
    /// rewrite); flagged for whoever touches `AgentTemplate.defaults` next.
    @Test func operatorFooterStripRendersWhenOperatorsAreLive() {
        // Pin model B off for the duration of this render — `isModelBFieldEnabled`
        // reads the process-global `UserDefaults.standard`
        // (`ComposerGhostTextField.modelBFieldStorageKey`), which this file's
        // OTHER model-B tests flip `true` for their own duration (same
        // save/restore idiom, `mountedModelBGhostTracksHighlightedRowAcrossProjects`
        // above) — without this, a test running concurrently in the same
        // process can transiently see `⇥ accept` join the operator set here.
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let view = paletteView(project: project, workspaceStore: workspaceStore, composerStore: composerStore)
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "variant-g-pass-b-footer-live-light.png")
        #expect(light != nil)
        if let light, let top = cardTopEdge(in: light), let bottom = cardBottomEdge(in: light) {
            let height = bottom - top
            #expect(
                height > 530 && height < 580,
                "card measured \(height)px tall (top \(top), bottom \(bottom)) with a live operator footer — expected 530-580px (mutant-verified: 555px with the strip, 503px without; the upper bound guards a mutant that over-renders instead of dropping the strip entirely — see this test's doc comment for the known one-more-default-template caveat this band does NOT survive)"
            )
        } else {
            Issue.record("failed to render or measure the card's opaque bounds")
        }

        let dark = renderPNG(view, appearance: .darkAqua, size: size)
        writeEvidence(dark, filename: "variant-g-pass-b-footer-live-dark.png")
        #expect(dark != nil)
        if let dark {
            #expect(containsRenderedContent(in: dark, isDark: true), "expected the field/rows/footer strip to render, got a near-blank card")
        }
    }

    /// Zero projects anywhere (`step4ZeroProjectEmptyStateRendersLightAndDark`'s
    /// fixture, reused): `flattenedOptions` is empty, so `selectedOption`
    /// is `nil` (`hasSelection` false) and there is nothing to navigate
    /// between (`hasMultipleOptions` false) — `footerOperators` resolves
    /// to `[]`, and `footerSlot` maps that to `.none`. No divider line
    /// should render at all; the card's total measured height should stay
    /// exactly what `emptyLanesRenderNoHeaderOrExtraSpace` (Pass A) already
    /// pins for this same fixture (field + divider + one empty-state row,
    /// under 300px) — a real 26pt strip rendered here would add height
    /// that test doesn't budget for, which is exactly why that test's
    /// still-green status after this pass is itself corroborating
    /// evidence, not just this test.
    @Test func footerStripAbsentWhenOperatorListIsEmpty() {
        // See `operatorFooterStripRendersWhenOperatorsAreLive`'s matching
        // comment — pin model B off so a concurrently-running model-B test
        // can't transiently add `⇥ accept` to this fixture's empty list.
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let workspaceStore = WorkspaceStore(testingProjects: [], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "variant-g-pass-b-footer-empty-light.png")
        #expect(light != nil)
        // Same measured-height technique as
        // `operatorFooterStripRendersWhenOperatorsAreLive` above and Pass
        // A's `emptyLanesRenderNoHeaderOrExtraSpace` — NOT a divider-line
        // pixel search: a blank card region and the strip's own tinted
        // background both render as uniform, full-width bands, so "no
        // uniform band near the bottom" is not a reliable negative signal
        // here (an earlier draft of this test relied on exactly that and
        // was mutant-verified vacuous — see the sibling test's doc
        // comment). Mutant-verified directly against THIS fixture: correct
        // code measures 223px (matches Pass A's own measurement of this
        // same fixture exactly); forcing the `.none` case to render a
        // one-operator strip anyway measures 275px, a 52px (26pt) gap.
        // 250 sits with 27px of margin on both sides — tighter than Pass
        // A's own 300 threshold, which was calibrated against a much
        // larger mutant (a spurious whole SECTION HEADER, not a 26pt
        // strip) and doesn't have enough margin to catch this one.
        guard let light,
              let top = cardTopEdge(in: light),
              let bottom = cardBottomEdge(in: light)
        else {
            Issue.record("failed to render or measure the card's opaque bounds")
            return
        }
        let height = bottom - top
        #expect(
            height < 250,
            "card measured \(height)px tall with an empty operator list (top \(top), bottom \(bottom)) — expected under 250px (mutant-verified: 223px correct, 275px with a spurious strip)"
        )
    }

    /// Review round 2, P1-b regression test: `modelBGhostRemainder`'s guard
    /// used to read `isModelBFieldEnabled` alone, which stays `true` in
    /// `.anchored` even though `.anchored` never mounts model B
    /// (`usesModelBFieldForTesting` — gated to `.centered`, G-F28). With no
    /// projects anywhere, `hasSelection`/`hasMultipleOptions`/
    /// `hasPendingChipUndo` are all false (same fixture as
    /// `footerStripAbsentWhenOperatorListIsEmpty` above), so `⇥ accept` is
    /// the ONLY operator that could ever populate the footer here — and
    /// `.anchored`'s own `ghostPlaceholder` fallback ("Type a project,
    /// branch, and command…") is non-empty regardless of project count, so
    /// the buggy guard produced a non-empty ghost remainder and rendered a
    /// footer strip even in this empty-everything fixture. This can only be
    /// exercised by a real hosted render (`@EnvironmentObject` access
    /// crashes a bare `SessionComposerPalette` construction — see
    /// `ComposerGhostTextFieldTests
    /// .anchoredNeverUsesModelBFieldEvenWithFlagOn`'s doc comment).
    ///
    /// Mutant-verified directly against THIS fixture: correct code measures
    /// 195px; reverting `modelBGhostRemainder`'s guard to
    /// `isModelBFieldEnabled` alone measures 247px, a 52px (26pt at this
    /// render's 2x backing scale) gap — the footer strip's own spec height,
    /// exactly matching the signature the sibling `.centered` tests above
    /// use. 220 sits with 25px of margin on both sides.
    @Test func anchoredNeverAdvertisesAcceptEvenWithModelBFlagOn() {
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let workspaceStore = WorkspaceStore(testingProjects: [], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        composerStore.open(projectBinding: .open, workspaceStore: workspaceStore)
        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .anchored, projectBinding: .open),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.sidebarWidth, height: 420)

        let light = renderPNG(view, appearance: .aqua, size: size)
        writeEvidence(light, filename: "variant-g-anchored-no-accept-light.png")
        #expect(light != nil)
        guard let light,
              let top = cardTopEdge(in: light),
              let bottom = cardBottomEdge(in: light)
        else {
            Issue.record("failed to render or measure the card's opaque bounds")
            return
        }
        let height = bottom - top
        #expect(
            height < 220,
            "card measured \(height)px tall in `.anchored` with the model B flag on and zero projects (top \(top), bottom \(bottom)) — expected under 220px (mutant-verified: 195px correct, 247px with `⇥ accept` wrongly advertised)"
        )
    }

    // MARK: - Review round 2/4, P2: `.anchored` footer coverage

    /// The required width of a set of operator hints rendered at the
    /// footer strip's REAL fonts (10.5pt monospaced, semibold glyph /
    /// regular label — `SessionComposerPalette.operatorFooterStrip`'s own
    /// literal values, not a guess), measured via `NSAttributedString`
    /// sizing against the real system font metrics rather than by
    /// re-implementing the `HStack`'s layout. This is what actually caught
    /// round 2/3's bug: `.lineLimit(1)` makes an over-full strip invisible
    /// to every pixel-based "did it wrap" check (truncation and a
    /// correctly-fit single line render identically in a
    /// rendered/height/wrap sense — only a comparison against the STRING's
    /// own required width catches it).
    ///
    /// `includeLabels: true` matches production in both presentations
    /// (round 5 removed the `.anchored`-only glyph-only gate); `includeLabels:
    /// false` is kept only to mutation-prove the lower-bound checks below —
    /// never rendered by production.
    private func requiredFooterContentWidth(
        operators: [SessionComposerCommandParser.FooterOperatorHint],
        includeLabels: Bool
    ) -> CGFloat {
        let glyphFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        var total: CGFloat = 0
        for (index, op) in operators.enumerated() {
            if index > 0 { total += 11 } // inter-operator `HStack(spacing: 11)` (round 5, was 14)
            total += (op.glyph as NSString).size(withAttributes: [.font: glyphFont]).width
            if includeLabels {
                total += 4 // intra-operator `HStack(spacing: 4)`
                total += (op.label as NSString).size(withAttributes: [.font: labelFont]).width
            }
        }
        return total
    }

    /// `.anchored`'s footer content width: `paletteWidth` (`WorkspaceLayout
    /// .sidebarWidth - 16` = 204pt) minus the strip's own horizontal
    /// padding on both sides. Padding is `SessionComposerPalette
    /// .footerHorizontalPadding` (`private`, not reachable from
    /// `@testable import` — Swift's `private` stays file-scoped regardless)
    /// — its formula (`8` from `ComposerResultsTable.body`'s own
    /// `.padding(8)` + `rowHorizontalPadding`, `8` in `.anchored`) is
    /// hardcoded here instead, same precedent as this file's other
    /// production-constant literals (`WorkspaceLayout.sidebarWidth - 16`
    /// itself, `paletteWidth`'s own doc comment).
    private var anchoredFooterAvailableWidth: CGFloat {
        (WorkspaceLayout.sidebarWidth - 16) - 2 * 16
    }

    /// `.anchored`'s content width (`paletteWidth`, `.anchored` case) is
    /// `WorkspaceLayout.sidebarWidth - 16` = 204pt — every prior footer
    /// snapshot fixture in this file is `.centered` (`composerOverlayWidth`,
    /// much wider), so this is the first fixture to actually render the
    /// operator strip at sidebar width. `⇥ accept` is STRUCTURALLY
    /// UNREACHABLE in `.anchored` (`usesModelBFieldForTesting` gates it to
    /// `.centered`), so this fixture reaches the maximum REAL operator
    /// count in `.anchored` today: three (`↵ open`, `↑↓ navigate`, `⌘Z
    /// undo`) — via two projects (`.prefilled` so `changeProjectChip` can
    /// actually cascade, unlike `.locked`) and the app's own multi-template
    /// default set.
    ///
    /// Review round 5: round 4's "22pt over"/"~190pt required"/"~168pt
    /// available" were all wrong — the first counted three 14pt
    /// inter-operator gaps for three operators (only two exist); the
    /// second and third didn't account for round 4's own
    /// `footerHorizontalPadding` change (16pt in `.anchored`, not the
    /// pre-existing 18pt). Correct: three labeled operators require
    /// 176.14pt at the original 14pt spacing against 172pt actually
    /// available — 4.14pt over, real but small. Round 5 closes it by
    /// tightening `operatorFooterStrip`'s spacing to 11pt (176.14 →
    /// 170.14pt) rather than dropping labels.
    ///
    /// The lower-bound assertion below is mutation-proved by rendering ONE
    /// FEWER operator than what `pendingChipUndo`'s arming actually
    /// produces — temporarily skipping the `changeProjectChip` call below
    /// leaves the strip at two operators (`↵ open`, `↑↓ navigate`) instead
    /// of three, and `renderedInkWidthPt > requiredWidth - 15` (computed
    /// against the real three-operator `requiredWidth`) failed as
    /// expected, catching the case where `pendingChipUndo` silently stops
    /// arming and the test would otherwise still measure ink and pass
    /// green against a strip that's missing an operator. Restored after.
    @Test func anchoredThreeOperatorFooterFitsWithoutTruncation() {
        let project = Project(name: "Demo Project", rootPath: "/tmp/composer-ui-11-anchored-\(UUID().uuidString)")
        let otherProject = Project(name: "Other Project", rootPath: "/tmp/composer-ui-11-anchored-other-\(UUID().uuidString)")
        let workspaceStore = WorkspaceStore(testingProjects: [project, otherProject], testingSessions: [])
        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)

        let view = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .anchored, projectBinding: .prefilled(project)),
            composerStore: composerStore
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.sidebarWidth, height: 420)

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
        // Settles `.onAppear` — `SessionComposerPalette.onAppear` calls
        // `composerStore.open(...)` itself, which resets `pendingChipUndo`
        // to `nil` (`open(projectBinding:workspaceStore:)`'s own reset) —
        // arming the chip-undo BEFORE this mount, as an earlier draft of
        // this test did, gets silently wiped the instant the view appears.
        // `hasSelection`/`hasMultipleOptions` come for free from this same
        // `.onAppear` (row-0 seed against >1 built-in template).
        hosting.layoutSubtreeIfNeeded()
        composerStore.changeProjectChip(to: otherProject.id, currentlyShown: project.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let rep0 = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("failed to render `.anchored` three-operator fixture")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep0)
        let light = rep0.representation(using: .png, properties: [:])
        writeEvidence(light, filename: "variant-g-anchored-three-operators-light.png")
        #expect(light != nil)
        guard let light else {
            Issue.record("failed to render `.anchored` three-operator fixture")
            return
        }
        // The strip has NO `.lineLimit`/`.truncationMode` (flagged as a
        // real gap by the review) — if the three chords overflow
        // `paletteWidth`, SwiftUI's default behavior for an HStack of
        // fixed-size `Text` children with a trailing `Spacer(minLength: 0)`
        // is to let the LAST child (the `Spacer`) collapse to 0 and the
        // overflowing content EXTEND PAST the card's own right edge rather
        // than wrap or clip — a right-edge opacity check catches that:
        // scans the footer's own 26pt band (bottom of the card) for opaque
        // content beyond `paletteWidth`'s right edge, which would only be
        // possible if the strip's content pushed past its parent's bounds.
        guard let bottom = cardBottomEdge(in: light) else {
            Issue.record("failed to measure card bottom edge")
            return
        }
        guard let rep = NSBitmapImageRep(data: light) else {
            Issue.record("failed to decode PNG")
            return
        }
        // The card's own right edge (opaque `.regularMaterial` background),
        // NOT the render canvas edge — the card sits inset within an 8pt
        // shake-clearance gutter on each side (`paletteWidth`'s doc
        // comment), so a naive "did ink reach the canvas edge" check would
        // never trip even with real overflow.
        var cardRightEdge: Int?
        for x in stride(from: rep.pixelsWide - 1, through: 0, by: -1) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    cardRightEdge = x
                    break
                }
            }
            if cardRightEdge != nil { break }
        }
        guard let cardRightEdge else {
            Issue.record("failed to measure the card's right edge")
            return
        }
        let scale = CGFloat(rep.pixelsWide) / size.width
        let footerHeightPx = Int(26 * scale)
        let footerTop = max(0, bottom - footerHeightPx + 2)
        var rightmostInk: Int?
        // A wrapped-to-2-lines strip (this test's original draft caught
        // this ONLY by screenshot, not by the rightmost-ink-stays-inside-
        // the-card check below, which stays true even while wrapped:
        // wrapping keeps ink horizontally inside the card, it just
        // corrupts the strip vertically) spans roughly double a single
        // 10.5pt line's own ink height — measuring the ink's own
        // topmost-to-bottommost extent (not a fixed third-band split,
        // which false-positived against tall glyphs like `↑↓`/`⌘`'s
        // natural ascender height) survives glyph-height variance while
        // still catching the wrap.
        var inkTop: Int?, inkBottom: Int?, leftmostInk: Int?
        for y in stride(from: footerTop, through: bottom, by: 1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let luminance = Int(((color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255).rounded())
                if luminance <= 160 {
                    rightmostInk = max(rightmostInk ?? x, x)
                    leftmostInk = min(leftmostInk ?? x, x)
                    inkTop = min(inkTop ?? y, y)
                    inkBottom = max(inkBottom ?? y, y)
                }
            }
        }
        guard let rightmostInk, let leftmostInk, let inkTop, let inkBottom else {
            Issue.record("found no ink in the footer band — expected `↵ open ↑↓ navigate ⌘Z undo`")
            return
        }
        #expect(
            rightmostInk < cardRightEdge,
            "rightmost footer ink at backing x=\(rightmostInk), card's own right edge at x=\(cardRightEdge) — three operators overflowed the card's own right edge (paletteWidth has no lineLimit/truncationMode to contain it)"
        )
        let inkHeight = inkBottom - inkTop
        #expect(
            inkHeight < Int(18 * scale),
            "footer ink spans \(inkHeight)px tall (single-line `↑↓`/`⌘` glyphs measured ~13px at this fixture's 2x scale) — a label wrapped onto a second line instead of truncating on one"
        )

        // Review round 4, P1-a: the ACTUAL truncation-detection check.
        // Round 2/3's version stopped here — both checks above stay true
        // under `.lineLimit(1)` ellipsis truncation (ink stays inside the
        // card's right edge, and truncated text still renders on one
        // line), which is exactly why the original bug shipped green. This
        // compares the footer's REAL RENDERED ink width against the
        // required width computed from real font metrics for the three
        // labeled operators `.anchored` actually renders (round 5:
        // glyph+label in both presentations, tightened spacing) — an
        // upper bound catches a regression that widens the content (e.g.
        // spacing reverting to 14pt), and a lower bound catches a
        // regression that shrinks it (e.g. a dropped operator, or labels
        // silently disappearing again).
        let threeLiveOperators: [SessionComposerCommandParser.FooterOperatorHint] = [
            .init(glyph: "↵", label: "open"),
            .init(glyph: "↑↓", label: "navigate"),
            .init(glyph: "⌘Z", label: "undo")
        ]
        let requiredWidth = requiredFooterContentWidth(operators: threeLiveOperators, includeLabels: true)
        let renderedInkWidthPt = CGFloat(rightmostInk - leftmostInk) / scale
        #expect(
            requiredWidth < anchoredFooterAvailableWidth,
            "three labeled operators require \(requiredWidth)pt, `.anchored`'s footer has \(anchoredFooterAvailableWidth)pt available — content would be truncated"
        )
        #expect(
            renderedInkWidthPt < requiredWidth + 15,
            "rendered footer ink spans \(renderedInkWidthPt)pt, but three labeled operators require only \(requiredWidth)pt (15pt anti-aliasing/kerning slack) — content wider than spec is rendering"
        )
        #expect(
            renderedInkWidthPt > requiredWidth - 15,
            "rendered footer ink spans \(renderedInkWidthPt)pt, but three labeled operators require \(requiredWidth)pt (15pt anti-aliasing/kerning slack) — content narrower than spec is rendering, e.g. a dropped operator or labels missing"
        )
    }

    /// Review round 5: round 4's version of this test asserted that four
    /// operators (glyph-only) fit `.anchored`'s footer width. That premise
    /// is gone — round 5 removed the glyph-only gate, so `.anchored` now
    /// always renders glyph+label, and four LABELED operators genuinely do
    /// not fit (230.4pt required against 172pt available, even at the
    /// tightened 11pt spacing). That's fine specifically because four is
    /// provably unreachable: `⇥ accept` requires `usesModelBFieldForTesting`,
    /// which is hardcoded to `.centered` only
    /// (`SessionComposerPalette.usesModelBFieldForTesting`) — no
    /// `AppStorage` flag or state can make it true in `.anchored`. This
    /// test now asserts THAT structural guarantee directly, on a real
    /// `SessionComposerPalette(request:.anchored)` instance, with the flag
    /// forced on to prove the presentation check (not the flag) is what's
    /// gating it.
    @Test func anchoredCannotReachFourOperators() {
        let key = ComposerGhostTextField.modelBFieldStorageKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(true, forKey: key) // force the flag ON — proves `.anchored` alone blocks it
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        let suiteName = "ghostties.sessionComposerStore.test.\(UUID().uuidString)"
        let composerStore = SessionComposerStore(isolatedForTesting: suiteName)
        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .anchored, projectBinding: .open),
            composerStore: composerStore
        )
        #expect(
            !palette.usesModelBFieldForTesting,
            "`.anchored` must never mount the model-B field, or `⇥ accept` becomes a 4th footer operator and the strip (172pt available, 230pt required at 4 labeled operators) overflows — see the doc comment above"
        )

        // Corroborating evidence: even if the structural guard above were
        // ever removed, the arithmetic itself makes 4 labeled operators
        // provably not fit — documents WHY the guard matters, not a claim
        // production defends against it by layout.
        let fourOperators: [SessionComposerCommandParser.FooterOperatorHint] = [
            .init(glyph: "↵", label: "open"),
            .init(glyph: "⇥", label: "accept"),
            .init(glyph: "↑↓", label: "navigate"),
            .init(glyph: "⌘Z", label: "undo")
        ]
        let requiredWidth = requiredFooterContentWidth(operators: fourOperators, includeLabels: true)
        #expect(
            requiredWidth > anchoredFooterAvailableWidth,
            "four labeled operators measure \(requiredWidth)pt against `.anchored`'s \(anchoredFooterAvailableWidth)pt available — expected this to overflow (confirming the structural guard above is load-bearing, not redundant)"
        )
    }

    // MARK: - Review round 4, P2: `writeError` must not stay hidden behind `isAddingTemplate`

    /// Scans for `.systemRed` ink anywhere in the card — the ONLY red
    /// content this composer ever paints is the `writeError`/typed-branch
    /// error text (`SessionComposerPalette`'s `.error(let message)` footer
    /// branch) and the no-match shake border, which this fixture never
    /// triggers (no Return is ever sent). A wide per-channel gap (red
    /// channel clearly dominant over green/blue) distinguishes it from the
    /// UI's other warm-neutral tones (labels, terracotta accents elsewhere
    /// in the app are not present in this view at all).
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

    /// Review round 4, P2 fix: the precedence swap (round 2) correctly
    /// made `isAddingTemplate` win the footer slot over `writeError` for
    /// the COMMON case (a live text field must never be evicted by a stale
    /// resolution message). The gap it opened: an async worktree create
    /// that OUTLIVES the user moving on to "+ New template…" sets
    /// `writeError` well after `isAddingTemplate` went true, and — without
    /// this fix — that error stays permanently hidden behind the naming
    /// field until the user commits or cancels the template, at which
    /// point `cancel()`/`commitNewTemplate()` silently discards it. Net:
    /// no worktree, no error ever shown, wrong cwd.
    ///
    /// Mounts with `initialIsAddingTemplateForTesting: true` (this bug's
    /// only reachable starting state — `isAddingTemplate` is private
    /// `@State`, see that init parameter's doc comment for why this is the
    /// only route in), confirms the footer shows NO red ink yet (the
    /// naming field, correctly, still owns the slot with no error present),
    /// then calls `composerStore.rejectUnresolvedBranch(token:)` directly
    /// (same synchronous `writeError` write path the async worktree-create
    /// timeout uses, `SessionComposerStore.swift:1187`, without waiting on
    /// a real 10s timeout) and re-renders — the fix means the error now
    /// wins the footer slot and its red text appears.
    @Test func isAddingTemplateClearsWhenAWriteErrorArrives() {
        let project = makeProject()
        let workspaceStore = WorkspaceStore(testingProjects: [project], testingSessions: [])
        let composerStore = makePlainComposer(project: project, workspaceStore: workspaceStore)
        let palette = SessionComposerPalette(
            isPresented: .constant(true),
            request: SessionComposerRequest(presentation: .centered, projectBinding: .prefilled(project)),
            composerStore: composerStore,
            initialIsAddingTemplateForTesting: true
        )
        .environmentObject(workspaceStore)
        .environmentObject(SessionCoordinator())
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth + 16, height: 420)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: palette.frame(width: size.width, height: size.height))
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
        let beforeData = before.representation(using: .png, properties: [:])
        writeEvidence(beforeData, filename: "variant-g-adding-template-before-error-light.png")
        #expect(beforeData != nil)
        if let beforeData {
            #expect(
                !containsRedInk(in: beforeData),
                "expected no red error ink while only `isAddingTemplate` is true (nothing has failed yet)"
            )
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
        writeEvidence(afterData, filename: "variant-g-adding-template-after-error-light.png")
        #expect(afterData != nil)
        guard let afterData else { return }
        #expect(
            containsRedInk(in: afterData),
            "expected `writeError`'s red error text to win the footer slot once it arrives — instead it stayed hidden behind `isAddingTemplate`, exactly the silent-wrong-cwd bug this fix closes"
        )
    }

}
