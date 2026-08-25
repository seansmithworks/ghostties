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
    /// already cleared the threshold. Scoped to `y >= 280`, the same
    /// field/results-area boundary `ghostGrayBandPixelCount` establishes
    /// (rows there measured at `y` 332-519; the field is `y` 195-212), so
    /// this only sees the results area, never the field.
    private func resultsAreaContainsContent(in data: Data, isDark: Bool) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 280, to: rep.pixelsHigh, by: 2) {
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
    /// band the 11.1 ghost placeholder renders at rest —
    /// `Color(nsColor: .labelColor).opacity(0.49)` over the card's
    /// near-white light-mode background measures `rgb(149,149,149)`
    /// (measured directly against this test's own render: 1656 matching
    /// pixels at a 2px sample stride, `r == 149` at the sample coordinates,
    /// all at `y` 195-212). A band (140-160, near-equal channels), not an
    /// exact triple, to tolerate antialiasing at glyph edges.
    ///
    /// Scoped to `y < 280` — WITHOUT that bound, this mutant-verified false
    /// GREEN on a 0.49 -> 0.03 opacity mutation (the ghost went
    /// near-invisible, but the band count barely dropped) because
    /// `makePlainComposer`'s template ROWS below the field render their own
    /// `.secondary`-styled subtitle text in the SAME 140-160 luminance band
    /// (measured: 274 leftover matches, all at `y` 332-519 — the row list,
    /// not the field). `y < 280` sits between the two with margin on both
    /// sides, at this test's fixed render size (`WorkspaceLayout.composerOverlayWidth
    /// + 16` wide, 420 tall). LIGHT MODE ONLY, same limitation this file's
    /// `darkestGhostPixel` already documents for dark mode.
    private func ghostGrayBandPixelCount(in data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: min(280, rep.pixelsHigh), by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.9 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r >= 140, r <= 160, g >= 140, g <= 160, b >= 140, b <= 160, abs(r - g) < 3, abs(g - b) < 3 {
                    count += 1
                }
            }
        }
        return count
    }

    /// Fix 1 (review, long-path capture): measures the y-range spanned by
    /// the ghost gray-band pixels (`ghostGrayBandPixelCount`'s color test,
    /// same 140-160 luminance band / near-neutral tolerance), scoped to the
    /// same `y < 280` field region. A single line of ghost text spans a
    /// tight y-range (glyph ascender to descender, ~15-20px at this font
    /// size); a wrap regression back to two stacked lines roughly doubles
    /// it. Returns nil if no matching pixels were found at all.
    private func ghostGrayBandYSpan(in data: Data) -> Int? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        var minY: Int?
        var maxY: Int?
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: min(280, rep.pixelsHigh), by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.9 else { continue }
                let r = Int((color.redComponent * 255).rounded())
                let g = Int((color.greenComponent * 255).rounded())
                let b = Int((color.blueComponent * 255).rounded())
                if r >= 140, r <= 160, g >= 140, g <= 160, b >= 140, b <= 160, abs(r - g) < 3, abs(g - b) < 3 {
                    minY = min(minY ?? y, y)
                    maxY = max(maxY ?? y, y)
                }
            }
        }
        guard let minY, let maxY else { return nil }
        return maxY - minY
    }

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

    /// Fix 8 (review): the stale-PNG class (`fb09ce9c9`'s PNGs were
    /// committed without being re-rendered from the build that fixed
    /// them — two full review rounds burned catching it by eye) is not a
    /// "the file is old" problem this test can detect at RUN time (a test
    /// can't know what a human will commit after it passes). What it CAN
    /// guarantee: this suite's own PASS/FAIL never depends on trusting the
    /// on-disk PNG's content — every pixel assertion above (`ghostGrayBandPixelCount`,
    /// `selectionHighlightPixelCount`, `darkestGhostPixel`) reads the
    /// FRESH in-memory render, never the file. This asserts the converse
    /// half explicitly: immediately after a write, the bytes on disk
    /// byte-for-byte match what was just rendered — catching a write-side
    /// failure (a stale file left in place by a failed/partial write) fail
    /// loudly instead of silently leaving a mismatched artifact for the
    /// next reviewer to eyeball.
    private func assertEvidenceMatchesDisk(_ data: Data, filename: String) {
        let url = evidenceDirectory().appendingPathComponent(filename)
        guard let onDisk = try? Data(contentsOf: url) else {
            Issue.record("Evidence file \(filename) missing on disk immediately after write")
            return
        }
        #expect(onDisk == data, "\(filename) on disk does not match the freshly rendered image — stale/partial write")
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
        if let light { assertEvidenceMatchesDisk(light, filename: "step3-rest-ghost-path-light.png") }
        // Fix 7 (review): asserts the ghost actually renders IN the correct
        // gray band (`rgb(149,149,149)`, measured — see
        // `ghostGrayBandPixelCount`'s doc comment), not just that some PNG
        // came back. 1656 matching pixels measured at this exact render
        // size/stride; the threshold (50) is a wide margin under that,
        // catching a missing/wrong-opacity ghost without being brittle to
        // minor layout drift.
        if let light {
            let bandCount = ghostGrayBandPixelCount(in: light)
            #expect(bandCount > 50, "expected the rest-state ghost's rgb(149,149,149) band, found \(bandCount) matching pixels")
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
            #expect(bandCount > 50, "expected the long-path ghost's rgb(149,149,149) band, found \(bandCount) matching pixels")
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
    /// symbol the overlay `Text` actually renders with — to the `DESIGN.md`
    /// §4 target (`#1A1A1A7E`, 0x7E/0xFF ≈ 0.49). Guards against a
    /// regression back to the `prompt:` route's un-honoured
    /// `.foregroundColor`, which measured at ~0.83 (`step3-rest-ghost-path-
    /// light.png`'s darkest pixel, `rgb(64,64,64)` against a white ground).
    @Test func ghostPlaceholderOpacityMatchesDesignSpec() {
        #expect(ComposerQueryField.ghostPlaceholderOpacity == 0.49)
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
    /// the ghost (49% alpha), so a plain "darkest pixel in the whole image"
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
    /// model A source produces — the active-segment ghost should render
    /// `stties` in grey per `activeSegmentGhostTruncatesAtNextSeparator`.
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
        if let lightData { assertEvidenceMatchesDisk(lightData, filename: "step7-modelb-light.png") }

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

}
