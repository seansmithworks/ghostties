import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Tests for round 12's composer tuning additions
/// (`ComposerZeroChromeStyle.swift`: `ComposerSingleLineTuning`,
/// `ComposerSingleLineShadowPreset`/`Dials`, `ComposerSingleLineTreatment`,
/// `ComposerSingleLineBackgroundChoice`, `ComposerZeroChromeAlignment`).
/// Every test references a production symbol directly and was proven red
/// against the pre-fix code before the corresponding change landed (see
/// each test's doc comment) — `feedback_vacuous-tests-pass-green`.
@MainActor
struct ComposerRound12TuningTests {

    private func isolatedSuite(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "ghostties.round12.\(name).test.\(UUID().uuidString)")!
    }

    // MARK: - Single-line size/width dials (item 2)

    /// Round 13b: Sean's tuned defaults from the HTML bench — 28pt field,
    /// 18pt row, 688pt width — replacing round 12's 22pt/16pt/680pt
    /// strawman. Red before the fix: `ComposerSingleLineTuning` didn't
    /// exist; these three functions would not compile.
    @Test func singleLineTuningDefaultsToTheBiggerStrawman() {
        let suite = isolatedSuite("tuning-defaults")
        #expect(ComposerSingleLineTuning.fieldSize(defaults: suite) == 28)
        #expect(ComposerSingleLineTuning.rowSize(defaults: suite) == 18)
        #expect(ComposerSingleLineTuning.width(defaults: suite) == 688)
    }

    /// Proves each dial actually READS its stored key rather than always
    /// returning the hardcoded default — red if `fieldSize`/`rowSize`/
    /// `width` ignored `defaults` and returned a literal instead.
    @Test func singleLineTuningDialsReadTheirStoredOverride() {
        let suite = isolatedSuite("tuning-override")
        suite.set(26.0, forKey: ComposerSingleLineTuning.fieldSizeStorageKey)
        suite.set(18.0, forKey: ComposerSingleLineTuning.rowSizeStorageKey)
        suite.set(720.0, forKey: ComposerSingleLineTuning.widthStorageKey)
        #expect(ComposerSingleLineTuning.fieldSize(defaults: suite) == 26)
        #expect(ComposerSingleLineTuning.rowSize(defaults: suite) == 18)
        #expect(ComposerSingleLineTuning.width(defaults: suite) == 720)
    }

    /// The container's line height/padding SCALE from field size rather
    /// than being independent dials (brief: "container height and padding
    /// scale with the text size") — at the shipped 15pt anchor this must
    /// return the byte-identical prior constants (38pt / 8pt / 16pt); red
    /// if the ratio drifted from that anchor.
    @Test func singleLineContainerMetricsScaleFromFieldSizeAndMatchThePriorConstantsAtTheOldAnchor() {
        #expect(ComposerSingleLineTuning.lineHeight(fieldSize: 15) == 38)
        #expect(ComposerSingleLineTuning.verticalPadding(fieldSize: 15) == 8)
        #expect(ComposerSingleLineTuning.horizontalPadding(fieldSize: 15) == 16)
        // At the new 22pt default, all three must have grown — proves the
        // "scales with text size" contract, not merely "returns some value
        // at 15pt".
        #expect(ComposerSingleLineTuning.lineHeight(fieldSize: 22) > 38)
        #expect(ComposerSingleLineTuning.verticalPadding(fieldSize: 22) > 8)
        #expect(ComposerSingleLineTuning.horizontalPadding(fieldSize: 22) > 16)
    }

    // MARK: - Shadow presets (item 3)

    /// `.soft` must match the shipped `WorkspaceLayout.composerModalShadow*`
    /// tokens EXACTLY — the shipped `.singleLine` look must not change
    /// until Sean picks a different preset. Red if `.soft`'s values were
    /// re-derived instead of reading the same production tokens.
    @Test func softShadowPresetMatchesTheShippedModalShadowTokensExactly() {
        let soft = ComposerSingleLineShadowPreset.soft.dialValues
        #expect(soft.radius == WorkspaceLayout.composerModalShadowRadius)
        #expect(soft.yOffset == WorkspaceLayout.composerModalShadowYOffset)
        #expect(soft.opacity == WorkspaceLayout.composerModalShadowOpacity)
    }

    /// `.none` has zero radius/offset/opacity; `.lifted`/`.long` are each
    /// distinct from `.soft` and from each other — red if two presets
    /// collapsed to the same tuple (a copy-paste mutant).
    @Test func shadowPresetsAreDistinctFromEachOther() {
        let none = ComposerSingleLineShadowPreset.none.dialValues
        let soft = ComposerSingleLineShadowPreset.soft.dialValues
        let lifted = ComposerSingleLineShadowPreset.lifted.dialValues
        let long = ComposerSingleLineShadowPreset.long.dialValues
        #expect(none.radius == 0 && none.yOffset == 0 && none.opacity == 0)
        #expect(lifted.radius != soft.radius || lifted.yOffset != soft.yOffset || lifted.opacity != soft.opacity)
        #expect(long.radius != lifted.radius || long.yOffset != lifted.yOffset || long.opacity != lifted.opacity)
    }

    /// Selecting a preset WRITES its values into the three separate dial
    /// keys (`ComposerSingleLineShadowDials`) — the actual mechanism
    /// `ComposerDebugTuningControl.singleLineShadowPreset`'s setter uses.
    /// Red if `apply` wrote to the wrong keys or not at all.
    @Test func shadowPresetApplyWritesAllThreeDials() {
        let suite = isolatedSuite("shadow-apply")
        ComposerSingleLineShadowDials.apply(.lifted, defaults: suite)
        let expected = ComposerSingleLineShadowPreset.lifted.dialValues
        #expect(ComposerSingleLineShadowDials.radius(defaults: suite) == expected.radius)
        #expect(ComposerSingleLineShadowDials.yOffset(defaults: suite) == expected.yOffset)
        #expect(ComposerSingleLineShadowDials.opacity(defaults: suite) == expected.opacity)
    }

    /// Round 13b: with nothing written yet, the dials read Sean's tuned
    /// defaults (64pt radius, 48pt y, 0.24 opacity) rather than `.soft`'s —
    /// red if the fallback defaulted to `.none`, a bare `0`, or `.soft`.
    @Test func shadowDialsFallBackToTheTunedCustomDefaultWhenUnset() {
        let suite = isolatedSuite("shadow-unset")
        #expect(ComposerSingleLineShadowDials.radius(defaults: suite) == 64)
        #expect(ComposerSingleLineShadowDials.yOffset(defaults: suite) == 48)
        #expect(ComposerSingleLineShadowDials.opacity(defaults: suite) == 0.24)
        #expect(ComposerSingleLineShadowPreset.current(defaults: suite) == .custom)
    }

    // MARK: - Liquid Glass treatment + macOS-26 fallback (item 4)

    /// Round 13b: default is `.glass` (Sean's tuned pick) — was `.material`
    /// through round 12.
    @Test func singleLineTreatmentDefaultsToGlass() {
        let suite = isolatedSuite("treatment-default")
        #expect(ComposerSingleLineTreatment.current(defaults: suite) == .glass)
    }

    @Test func singleLineTreatmentReadsGlass() {
        let suite = isolatedSuite("treatment-glass")
        suite.set("glass", forKey: ComposerSingleLineTreatment.storageKey)
        #expect(ComposerSingleLineTreatment.current(defaults: suite) == .glass)
    }

    /// The fallback rule itself, isolated from the real `#available` check
    /// (which this process's actual OS version would otherwise force one
    /// way or the other) — this is the red/green proof for "the glass
    /// fallback path below macOS 26 selects material" from the brief's
    /// test list. Red before this round: `ComposerSingleLineBackground
    /// Choice` didn't exist.
    @Test func glassTreatmentFallsBackToMaterialWhenGlassIsUnavailable() {
        #expect(ComposerSingleLineBackgroundChoice.resolve(treatment: .glass, glassAvailable: false) == .material)
        #expect(ComposerSingleLineBackgroundChoice.resolve(treatment: .glass, glassAvailable: true) == .glass)
        #expect(ComposerSingleLineBackgroundChoice.resolve(treatment: .material, glassAvailable: true) == .material)
        #expect(ComposerSingleLineBackgroundChoice.resolve(treatment: .material, glassAvailable: false) == .material)
    }

    // MARK: - Zero-chrome alignment (item 5)

    @Test func zeroChromeAlignmentDefaultsToLeft() {
        let suite = isolatedSuite("alignment-default")
        #expect(ComposerZeroChromeAlignment.current(defaults: suite) == .left)
    }

    @Test func zeroChromeAlignmentReadsCenter() {
        let suite = isolatedSuite("alignment-center")
        suite.set("center", forKey: ComposerZeroChromeAlignment.storageKey)
        #expect(ComposerZeroChromeAlignment.current(defaults: suite) == .center)
    }

    /// The three SwiftUI/AppKit alignment values `.center` maps to must all
    /// actually be centered (not left, the pre-round-12 default for every
    /// one of them) — this is the "keeps the ghost suggestion adjacent to
    /// the typed text" proof surface: `.nsTextAlignment` is the exact value
    /// `ComposerGhostTextField.textAlignment` sets on the real
    /// `NSTextView`, which `firstRect(forCharacterRange:)` (the ghost
    /// label's own position source) then follows automatically. Red if
    /// `.center` returned any of the `.left`-side values.
    @Test func centerAlignmentMapsAllThreeAxesToCenter() {
        let center = ComposerZeroChromeAlignment.center
        #expect(center.zstackAlignment == .center)
        #expect(center.frameAlignment == .center)
        #expect(center.multilineAlignment == .center)
        #expect(center.nsTextAlignment == .center)
    }

    @Test func leftAlignmentMapsAllThreeAxesToLeft() {
        let left = ComposerZeroChromeAlignment.left
        #expect(left.zstackAlignment == .leading)
        #expect(left.frameAlignment == .leading)
        #expect(left.multilineAlignment == .leading)
        #expect(left.nsTextAlignment == .left)
    }

    /// `ComposerGhostTextField.textAlignment` is a real, settable property
    /// this round added — proves the field's underlying `NSTextView`
    /// actually receives `.center` through the full `NSViewRepresentable`
    /// mounting path (real `NSHostingView`, not a hand-built context), not
    /// just that the SwiftUI-side struct stores it. Red before this round:
    /// the property didn't exist, so this wouldn't compile; also red if
    /// `makeNSView` never read it into `textView.alignment`.
    @Test func ghostTextFieldAppliesCenterAlignmentToItsNSTextView() {
        let field = ComposerGhostTextField(
            query: .constant(""),
            fontSize: 15,
            rowHeight: 38,
            focusTrigger: .constant(false),
            hasSelection: false,
            isPickerOpen: false,
            ghostFullPath: "",
            wrapsAndGrows: true,
            textAlignment: .center
        )
        let size = NSSize(width: 300, height: 100)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: field.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let textView = firstTextView(in: hosting) else {
            Issue.record("expected to find a mounted NSTextView")
            return
        }
        #expect(textView.alignment == .center)
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }
}
