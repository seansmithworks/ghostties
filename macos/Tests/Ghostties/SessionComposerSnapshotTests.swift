import AppKit
import SwiftUI
import Testing
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
    /// Scoped to `y < 100` (backing pixels) — WITHOUT that bound, this
    /// mutant-verified false GREEN on a 0.49 -> 0.03 opacity mutation (the
    /// ghost went near-invisible, but the band count barely dropped)
    /// because `makePlainComposer`'s template ROWS below the field render
    /// their own `.secondary`-styled subtitle text in a nearby luminance
    /// band. Re-measured after the results-well hugging fix
    /// (`ComposerResultsTable` no longer forces a tall well with dead
    /// space, so row content sits much closer to the field): the field's
    /// own ghost text now spans `y` 44-70, the next row-content band starts
    /// at `y` 186 (`debugStep3LongPathPositions` in
    /// `ComposerDesignCallRenderTests`, untracked harness, long-path
    /// fixture). `y < 100` sits between the two with margin on both sides,
    /// at this test's fixed render size (`WorkspaceLayout.composerOverlayWidth
    /// + 16` wide, 420 tall). LIGHT MODE ONLY, same limitation this file's
    /// `darkestGhostPixel` already documents for dark mode.
    private func ghostGrayBandPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: min(100, rep.pixelsHigh), by: 2) {
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
    /// same `y < 100` field region. A single line of ghost text spans a
    /// tight y-range (glyph ascender to descender, ~15-20px at this font
    /// size); a wrap regression back to two stacked lines roughly doubles
    /// it. Returns nil if no matching pixels were found at all.
    private func ghostGrayBandYSpan(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var minY: Int?
        var maxY: Int?
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: min(100, rep.pixelsHigh), by: 2) {
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

}
