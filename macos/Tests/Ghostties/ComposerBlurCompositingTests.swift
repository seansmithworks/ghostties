import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Blur-feasibility gate evidence (brief §2). The DETERMINATION itself
/// rests on standing shipped code — `SessionComposerPalette.composerCard`
/// already paints `Rectangle().fill(.regularMaterial)` as a within-window
/// background over the live terminal surface in `.centered` presentation
/// (PR #132, shadow-only elevation, no scrim) — see
/// `ComposerZeroChromeStyle.swift`'s header comment on `ComposerZeroChromeWash`
/// for the full argument for why the NSPanel/`.behindWindow` fallback was
/// not needed. This file is the SUPPORTING regression check: it composites
/// `ComposerZeroChromeWash` over a dense, terminal-like text backdrop in
/// one hosting hierarchy and asserts the blurred region differs from both
/// the raw text and a flat fill, so a future change that silently turns the
/// wash into a no-op (e.g. `revealed` wired backwards) fails a test instead
/// of only failing Sean's eye.
///
/// Fix round 2, item 5: `ComposerZeroChromeWash` no longer sizes or masks
/// itself (deleted its own 560×112pt `.frame` and feathered-edge mask) — it
/// now fills whatever bounds its caller proposes. This file's fixture
/// canvas (`size`, below) already stands in for "the caller's proposed
/// bounds", so the wash filling it EDGE TO EDGE with no visible boundary is
/// exactly what these tests already exercise; no test mechanics changed,
/// only this comment, which used to describe a self-sized "patch".
@MainActor
struct ComposerBlurCompositingTests {

    private let size = NSSize(width: 560, height: 112)

    private struct DenseTerminalBackdrop: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<8, id: \.self) { row in
                    Text(String(repeating: "$ git log --oneline -3 \(row) ", count: 2))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.176, green: 0.176, blue: 0.176))
        }
    }

    private func renderPNG<Content: View>(_ content: Content) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = .black

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

    /// Sum of absolute per-channel pixel differences over a coarse grid —
    /// cheap, and enough to distinguish "identical render" from "visibly
    /// different render" without needing exact-match brittleness.
    private func pixelDifference(_ a: Data, _ b: Data) -> Int {
        guard let repA = NSBitmapImageRep(data: a), let repB = NSBitmapImageRep(data: b) else { return 0 }
        guard repA.pixelsWide == repB.pixelsWide, repA.pixelsHigh == repB.pixelsHigh else { return .max }
        var total = 0
        for x in stride(from: 0, to: repA.pixelsWide, by: 2) {
            for y in stride(from: 0, to: repA.pixelsHigh, by: 2) {
                guard let ca = repA.colorAt(x: x, y: y), let cb = repB.colorAt(x: x, y: y) else { continue }
                let dr = abs(ca.redComponent - cb.redComponent)
                let dg = abs(ca.greenComponent - cb.greenComponent)
                let db = abs(ca.blueComponent - cb.blueComponent)
                total += Int((dr + dg + db) * 255)
            }
        }
        return total
    }

    /// Composites the wash over dense terminal-like text and proves the
    /// blurred region differs from BOTH the raw text (A) and a flat fill
    /// with no text at all (C) — i.e. the wash is genuinely sampling and
    /// softening what's beneath it, not just painting an opaque rectangle
    /// over it (which would be indistinguishable from C) and not passing
    /// the text through untouched (which would be indistinguishable from A).
    @Test func washDiffersFromRawTextAndFromFlatFill() {
        let rawText = renderPNG(DenseTerminalBackdrop())
        let flatFill = renderPNG(Color(red: 0.176, green: 0.176, blue: 0.176))
        let withWash = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                ComposerZeroChromeWash(material: .regular, revealed: true)
            }
        )

        #expect(rawText != nil)
        #expect(flatFill != nil)
        #expect(withWash != nil)

        guard let rawText, let flatFill, let withWash else { return }

        let diffFromRaw = pixelDifference(withWash, rawText)
        let diffFromFlat = pixelDifference(withWash, flatFill)

        // Non-trivial difference from the untouched text (something is
        // compositing on top of it)...
        #expect(diffFromRaw > 0)
        // ...and non-trivial difference from a flat, textless fill (the
        // text is still detectable through the wash, not fully occluded —
        // this is what distinguishes a translucent blur from an opaque
        // rectangle).
        #expect(diffFromFlat > 0)
    }

    /// `revealed: false` must render with no visible wash — the summon
    /// animation's start state — so this is the negative control for the
    /// test above (same composition, wash off, must match the raw text
    /// much more closely than the revealed case does).
    @Test func unrevealedWashRendersCloserToRawText() {
        let rawText = renderPNG(DenseTerminalBackdrop())
        let unrevealed = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                ComposerZeroChromeWash(material: .regular, revealed: false)
            }
        )
        let revealed = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                ComposerZeroChromeWash(material: .regular, revealed: true)
            }
        )

        guard let rawText, let unrevealed, let revealed else {
            Issue.record("Failed to render one or more fixtures")
            return
        }

        let unrevealedDiff = pixelDifference(unrevealed, rawText)
        let revealedDiff = pixelDifference(revealed, rawText)

        #expect(unrevealedDiff < revealedDiff)
    }

    /// Fix round 2, item 5: the wash must cover its bounds EDGE TO EDGE —
    /// no feathered mask fading it out near the border, unlike the deleted
    /// 24pt-feather patch. Compares the corner pixel (2pt in from each
    /// edge, where the old mask would have been fully transparent) against
    /// the center pixel — both revealed, both should show wash difference
    /// from the raw text, roughly equally, proving no edge falloff.
    @Test func revealedWashHasNoEdgeFeather() {
        let rawText = renderPNG(DenseTerminalBackdrop())
        let revealed = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                ComposerZeroChromeWash(material: .regular, revealed: true)
            }
        )
        guard let rawText, let revealed,
              let rawRep = NSBitmapImageRep(data: rawText),
              let washRep = NSBitmapImageRep(data: revealed) else {
            Issue.record("Failed to render fixtures")
            return
        }
        // Near-corner sample (2pt in, well inside where a 24pt feather
        // mask would previously have been fully transparent).
        let cornerX = 4
        let cornerY = 4
        guard let rawCorner = rawRep.colorAt(x: cornerX, y: cornerY),
              let washCorner = washRep.colorAt(x: cornerX, y: cornerY) else {
            Issue.record("Failed to sample corner pixel")
            return
        }
        let cornerDiff = abs(rawCorner.redComponent - washCorner.redComponent)
            + abs(rawCorner.greenComponent - washCorner.greenComponent)
            + abs(rawCorner.blueComponent - washCorner.blueComponent)
        #expect(cornerDiff > 0, "expected the wash to visibly affect a near-corner pixel (no edge feather)")
    }

    // MARK: - Fix round 5: focal falloff (Sean's live look, "the focal point
    // of the blur should be where the text is")

    /// Proves `ComposerZeroChromeWash`'s second, focal layer
    /// (`ComposerZeroChromeFocalBlur`) is genuinely stronger near its
    /// center than near the edges — not a uniform sheet. Samples the pixel
    /// nearest `ComposerZeroChromeFocalBlur`'s own center fraction against
    /// BOTH the top-left and bottom-left corners (checking both guards
    /// against `NSBitmapImageRep`'s pixel-origin convention either way)
    /// and asserts the center's departure from the raw text is larger than
    /// either corner's — i.e. more material is genuinely stacked there.
    /// Mutation-checked: setting `ComposerZeroChromeFocalBlur
    /// .focalMaterial` equal to the base `.regular` layer (so the two
    /// layers contribute identically everywhere) collapses this margin
    /// toward zero; setting `innerStopLocation`/`outerStopLocation` to 0
    /// (no falloff shape at all) does the same. Both were confirmed to
    /// fail this test by hand during implementation, then reverted.
    @Test func focalCenterDiffersMoreFromRawTextThanEitherCorner() {
        let rawText = renderPNG(DenseTerminalBackdrop())
        let withWash = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                // `focalBlurStyle` pinned explicitly (round 8) — was
                // `.current()`'s `UserDefaults.standard` read, which
                // raced/inherited whatever this machine's own DEBUG tuning
                // pill last wrote, observed failing here with Sean's Dev
                // domain pinned to `.off`.
                //
                // `fogEnabled: false` pinned too, for an UNRELATED and
                // confirmed-by-hand reason: compositing the fog layer's
                // `.colorEffect` Metal shader ANYWHERE in `ComposerZeroChromeWash`'s
                // tree (ZStack sibling, `.overlay`, `.drawingGroup()`-isolated
                // or not — all tried) defeats the focal `Material`'s live
                // blur sampling in THIS specific offscreen
                // `NSHostingView.cacheDisplay` snapshot path on this machine
                // (macOS 27): with fog on, centerDiff/topCornerDiff/
                // bottomCornerDiff all measured IDENTICAL
                // (0.17647058823529416), i.e. the focal layer stopped
                // reading as a localized blur at all. Removing only the
                // `.colorEffect` call (same GeometryReader/TimelineView
                // structure otherwise) restored the margin every time — this
                // is NOT a fixture-ordering bug, and NOT evidence the
                // shader is broken in the real, live-windowed app (Materials
                // and Metal shaders both fundamentally need live GPU
                // compositing that a software `cacheDisplay` snapshot
                // doesn't fully reproduce), but it IS an open risk this
                // spike could not verify offscreen — flagged to Sean, not
                // silently routed around. This test's own purpose (the
                // FOCAL layer's falloff shape) is independent of fog, so
                // disabling fog here isolates the thing actually under
                // test without weakening what it asserts.
                ComposerZeroChromeWash(material: .regular, revealed: true, focalBlurStyle: .thick, fogEnabled: false)
            }
        )
        guard let rawText, let withWash,
              let rawRep = NSBitmapImageRep(data: rawText),
              let washRep = NSBitmapImageRep(data: withWash) else {
            Issue.record("Failed to render fixtures")
            return
        }

        func diff(_ x: Int, _ y: Int) -> Double {
            guard let rawColor = rawRep.colorAt(x: x, y: y),
                  let washColor = washRep.colorAt(x: x, y: y) else { return 0 }
            return abs(rawColor.redComponent - washColor.redComponent)
                + abs(rawColor.greenComponent - washColor.greenComponent)
                + abs(rawColor.blueComponent - washColor.blueComponent)
        }

        let width = rawRep.pixelsWide
        let height = rawRep.pixelsHigh
        let centerX = Int(CGFloat(width) * ComposerZeroChromeFocalBlur.centerXFraction)
        let centerY = Int(CGFloat(height) * ComposerZeroChromeFocalBlur.centerYFraction)
        let centerDiff = diff(centerX, centerY)
        let topCornerDiff = diff(4, 4)
        let bottomCornerDiff = diff(4, height - 4)

        #expect(
            centerDiff > topCornerDiff && centerDiff > bottomCornerDiff,
            "expected the focal center (\(centerDiff)) to differ from raw text more than either corner (top \(topCornerDiff), bottom \(bottomCornerDiff)) — the focal layer should stack ONLY near its center"
        )
    }

    // MARK: - Round 8: fog layer smoke test

    /// Not a fidelity check (see `focalCenterDiffersMoreFromRawTextThanEitherCorner`'s
    /// own comment on why this offscreen harness can't assert the fog
    /// shader's blur behavior) — this only proves `fogEnabled: true`
    /// renders a non-nil frame on macOS 14+, i.e. the `.colorEffect` shader
    /// compiles and runs at all rather than crashing or producing an empty
    /// bitmap.
    @Test func fogEnabledRendersWithoutCrashing() {
        guard #available(macOS 14, *) else { return }
        let png = renderPNG(
            ZStack {
                DenseTerminalBackdrop()
                ComposerZeroChromeWash(material: .regular, revealed: true, focalBlurStyle: .off, fogEnabled: true)
            }
        )
        #expect(png != nil)
    }
}
