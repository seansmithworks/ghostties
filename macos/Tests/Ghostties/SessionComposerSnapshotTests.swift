import AppKit
import SwiftUI
import Testing
import GhosttiesCore
@testable import Ghostty

/// The Step 2 snapshot harness (Composer UI 11 plan §3, evidence contract
/// §6): mounts `SessionComposerPalette` (isolated fixture
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

    /// `windowAppearance`/`ambientAppearance` test arguments name an
    /// `NSAppearance.Name` as a plain string (`"aqua"`/`"darkAqua"`) — same
    /// shape as `ComposerSingleLineStyleTests.appearanceName`, kept local to
    /// this file rather than shared (private, `@testable` structs don't
    /// share test-file internals).
    private func appearanceName(_ key: String) -> NSAppearance.Name {
        key == "darkAqua" ? .darkAqua : .aqua
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

    // MARK: - Lane state (pins + recents)

    // MARK: - Plain templates state (no pins, no recents)

    // MARK: - Step 3: rest-state ghost path (11.1)

    // MARK: - Step 5 / ultra-minimal: resolution line AND trailing controls gone

    // MARK: - Variant G Pass C: chevron removed, projects live in results at rest

    // MARK: - Composer variant G: rest-state lane cap

    /// Acceptance criterion 2: the cap is rest-state only — once the user
    /// types a query that matches every project, all of them render, not
    /// just the first 3. Same 6-project fixture, blank query (capped at 3)
    /// vs. a typed query matching all 6 (uncapped): the typed render must
    /// be measurably taller.
    /// Rewritten off rendered-height fixtures: the popover's own 220pt
    /// results-list cap (unrelated to `applyRestStateCap`) clips BOTH the
    /// blank- and typed-query renders to the same 553px, so `typedHeight -
    /// blankHeight > 40` could never observe the lane actually uncapping —
    /// it was measuring the popover's outer scroll clip, not the lane. Sean's
    /// acceptance criterion is about lane membership, not pixels; asserting
    /// directly on `applyRestStateCap` — the exact pure function
    /// `lane2Options`/the projects lane both call — proves the cap/uncap
    /// behavior without a render at all.
    @Test func typingUncapsTheProjectsLaneBeyondThree() {
        let options = (0..<6).map { index in
            ComposerOption(
                id: UUID(),
                title: "Zulu Project \(index)",
                subtitle: nil,
                leadingIcon: nil,
                action: {}
            )
        }

        let capped = SessionComposerPalette.applyRestStateCap(to: options, query: "")
        #expect(capped.count == 3, "expected a blank query to cap the lane at 3, got \(capped.count)")

        let uncapped = SessionComposerPalette.applyRestStateCap(to: options, query: "zulu")
        #expect(uncapped.count == 6, "expected a non-blank query matching every option to leave the lane uncapped, got \(uncapped.count)")
    }

    // MARK: - Step 3: ghost placeholder opacity

    /// Pins `ComposerGhostTextField.ghostPlaceholderOpacity` — the production
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
        #expect(ComposerGhostTextField.ghostPlaceholderOpacity == 0.50)
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
            ComposerGhostTextField.ghostPlaceholderOpacity == 0.50,
            "ghostPlaceholderOpacity drifted from 0.50, the shipped design value (deliberately below WCAG AA — Sean's call)"
        )
    }

    /// The two ghost-opacity constants (`ComposerGhostTextField.ghostPlaceholderOpacity`
    /// and `ComposerGhostTextField.ghostOpacity`) are deliberately kept in lockstep so the two
    /// fields render the same ghost — see either constant's doc comment.
    /// This is exactly the drift `def5e9cd4` introduced (raised one, not
    /// the other); this test fails the moment they diverge again.
    @Test func ghostOpacityConstantsStayInLockstep() {
        #expect(ComposerGhostTextField.ghostPlaceholderOpacity == Double(ComposerGhostTextField.ghostOpacity))
    }

    // MARK: - Step 4: zero-project empty state

    // MARK: - Variant G Pass A: section headers, empty-lane guard

    // MARK: - Step 7: ghost field (UNVERIFIED-INTERACTION)

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
    @Test func step7GhostFieldRendersLightAndDark() {
        let field = ComposerGhostTextField(
            query: .constant("Gho"),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: .constant(false),
            hasSelection: false,
            ghostFullPath: "Ghostties > Default > Orchestrator"
        ) { _ in }
        let view = field.background(Color(nsColor: .windowBackgroundColor))
        let size = NSSize(width: WorkspaceLayout.composerOverlayWidth, height: 38)

        let lightData = renderPNGWithExtraLayoutPass(view, appearance: .aqua, size: size)
        writeEvidence(lightData, filename: "step7-ghost-field-light.png")
        #expect(lightData != nil)

        let darkData = renderPNGWithExtraLayoutPass(view, appearance: .darkAqua, size: size)
        writeEvidence(darkData, filename: "step7-ghost-field-dark.png")
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
            #expect(pixel != nil, "step7-ghost-field-light.png: no ghost pixel found — possible A-F2 regression (ghost clipped/missing)")
            if let pixel {
                print("step7-ghost-field-light.png darkest ghost-region pixel: rgb(\(pixel.r),\(pixel.g),\(pixel.b))")
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
    /// (`SessionComposerGhostSourceTests
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
}
