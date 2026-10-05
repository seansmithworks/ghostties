import SwiftUI
import AppKit
#if DEBUG
import Combine
import DialKit
#endif

// The single-line composer's support code: the rest-state descriptor cycle,
// the Witness ghost's dials, the live tuning dials (`ComposerSingleLineTuning`
// and friends), and the DEBUG-only DialKit panel that drives them. There is
// exactly one composer; a stale stored `ghostties.composerStyle` value
// (`zeroChrome` or otherwise) is never read.

// MARK: - Rest-state descriptor cycle

/// The rest-state ghost descriptor cycle (single-line composer): four hints
/// cycled in FIXED order while the field is empty and
/// focused. Order is Sean's explicit rule (brief, §1): the chevron/path
/// form (`ghostPlaceholder`) must never render first — it is pinned at
/// index 3 (the 4th and last item). `descriptors(mostRecentProjectName
/// :ghostPlaceholderPath:)` is a pure function so its ordering invariant is
/// unit-testable without mounting any SwiftUI view.
enum ComposerDescriptorCycle {
    static func descriptors(mostRecentProjectName: String?, ghostPlaceholderPath: String) -> [String] {
        let idiomProject = mostRecentProjectName ?? "ghostties"
        return [
            "Name a session",
            "\(idiomProject) cco -n \"Composer\"",
            "Tab completes · ↓ next match · Return launches",
            ghostPlaceholderPath
        ]
    }
}

/// Crossfades through `descriptors` every 2.6s while `query` is empty,
/// restarting at item 0 on every appearance (summon). Reduce Motion (per
/// the caller's `reduceMotion` flag) freezes it on item 0 statically — no
/// timer runs, no crossfade — the "cycle disabled" floor from the brief's
/// §2 Reduce Motion rule.
struct ComposerDescriptorGhostText: View {
    let descriptors: [String]
    let query: String
    let opacity: Double
    let reduceMotion: Bool

    @State private var index = 0

    private static let holdNanoseconds: UInt64 = 2_600_000_000

    /// Fix round 3, item 2: the Timing board's crossfade between cycle
    /// items, 180ms. Fix round 2 landed with NO `.transition()` at all
    /// (item-to-item cycling snapped) after two wrong mechanisms: a
    /// `.transition(.opacity.animation(.easeInOut(duration: 0.18)))` baked
    /// the animation directly onto the transition, so it fired on EVERY
    /// removal of this view — including the query-non-empty removal, which
    /// must be instant — and `.animation(nil, value: query.isEmpty)`
    /// couldn't suppress it (a transition's own embedded `.animation(...)`
    /// is independent of the ambient `.animation(_, value:)` modifier).
    /// The fix here keeps `.transition(.opacity)` with NO baked animation —
    /// a transition with no active animation in its transaction doesn't
    /// animate at all, so the query-driven removal (never wrapped in
    /// `withAnimation` by anything in this subtree) stays instant — and
    /// animates ONLY the index swap by wrapping that one state mutation in
    /// an explicit `withAnimation(.easeInOut(duration: crossfadeDuration))`
    /// at its single call site below. `.animation(nil, value: query.isEmpty)`
    /// is kept as a second, explicit guard on the same edge (this time
    /// effective, since there's no baked-in override left for it to lose
    /// to).
    static let crossfadeDuration: TimeInterval = 0.18

    var body: some View {
        let shownIndex = reduceMotion ? 0 : index
        Group {
            if query.isEmpty, descriptors.indices.contains(shownIndex) {
                Text(descriptors[shownIndex])
                    .id(shownIndex)
                    .transition(.opacity)
            }
        }
        .animation(nil, value: query.isEmpty)
        .foregroundStyle(Color(nsColor: .labelColor).opacity(opacity))
        .task(id: reduceMotion) {
            index = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.holdNanoseconds)
                if Task.isCancelled { return }
                guard query.isEmpty else { continue }
                withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
                    index = (index + 1) % descriptors.count
                }
            }
        }
    }
}

/// R14: the Witness ghost toggle (`ComposerWitnessView`, single-line +
/// centered only). Default ON — unset key reads `true`, matching every
/// other toggle in this file's `defaults.object(forKey:) as? Bool ??`
/// pattern.
enum ComposerWitnessSetting {
    static let storageKey = "ghostties.composerWitness"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? true
    }
}

/// Session-7 brief: the gap between the Witness sprite's bottom edge and the
/// single-line card's top edge — today it's flush (the sprite is 24pt tall,
/// `singleLineComposerCard`'s overlay offset is a hardcoded `y: -24`). The
/// overlay's actual offset becomes `y: -(24 + gap)`; this enum only owns the
/// dial, not the offset math (that stays in `SessionComposerPalette
/// .singleLineComposerCard`, next to the sprite-height constant it composes
/// with).
enum ComposerWitnessGap {
    static let storageKey = "ghostties.composerWitnessGap"
    /// Round 15 (Sean's DialKit Copy output): Sean's Dev-tuned gap, up from 5.
    static let defaultGap: CGFloat = 6
    static let range: ClosedRange<Double> = 0...12

    static func gap(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: storageKey) as? Double
        return CGFloat(stored ?? Double(defaultGap))
    }
}

/// Round 14 (session-7 live-look round): the Witness sprite's size, in
/// points — the sprite grid is a fixed 12×12 (`ComposerWitnessGhost.pixels`),
/// so this is the whole sprite's edge length, cell size `size/12`. Step 6
/// keeps every one of the 12 grid cells a whole Retina pixel at every step.
enum ComposerWitnessSize {
    static let storageKey = "ghostties.composerWitnessSize"
    /// Round 15 (Sean's DialKit Copy output): Sean's Dev-tuned size, up
    /// from 24 — cell size 2.5pt (5px), a whole Retina pixel.
    static let defaultSize: CGFloat = 30
    static let range: ClosedRange<Double> = 12...48

    static func size(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: storageKey) as? Double
        return CGFloat(stored ?? Double(defaultSize))
    }
}

/// Round 14: the Witness's idle vertical bob amplitude, in points. Runs
/// continuously, including during beats
/// (`ComposerWitnessFrames.floatOffset`), driven by the same idle clock the
/// blink/glance/ripple loop already uses. Round 15 (Sean's DialKit Copy
/// output): default up from 0 (off) to 2 — the bob is now on by default.
enum ComposerWitnessFloatAmplitude {
    static let storageKey = "ghostties.composerWitnessFloatAmplitude"
    static let defaultAmplitude: Double = 2
    static let range: ClosedRange<Double> = 0...4

    static func amplitude(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: storageKey) as? Double ?? defaultAmplitude
    }
}

/// Round 14: the float bob's full period, in seconds.
enum ComposerWitnessFloatPeriod {
    static let storageKey = "ghostties.composerWitnessFloatPeriod"
    static let defaultPeriod: Double = 3
    static let range: ClosedRange<Double> = 1.5...6

    static func period(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: storageKey) as? Double ?? defaultPeriod
    }
}

/// Round 15 (Sean's DialKit Copy output): the Witness's idle sideways sway
/// amplitude, in points — reuses `ComposerWitnessFloatPeriod` at HALF
/// frequency (no separate period dial), so combined with the vertical bob
/// it traces a lazy figure-8 rather than a diagonal line.
/// (`ComposerWitnessFrames.floatOffsetX`).
enum ComposerWitnessFloatHorizontal {
    static let storageKey = "ghostties.composerWitnessFloatHorizontal"
    static let defaultAmplitude: Double = 2
    static let range: ClosedRange<Double> = 0...4

    static func amplitude(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: storageKey) as? Double ?? defaultAmplitude
    }
}

/// Round 14: the Witness's overall opacity — one dial applied to the whole
/// sprite view, not per-colour.
enum ComposerWitnessOpacity {
    static let storageKey = "ghostties.composerWitnessOpacity"
    static let defaultOpacity: Double = 1.0
    static let range: ClosedRange<Double> = 0.2...1.0

    static func opacity(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: storageKey) as? Double ?? defaultOpacity
    }
}

/// Round 14: scales beat time only (tab-accept/error/resolve/launch/open) —
/// never the idle ripple/blink/glance clock. 1.0 matches today's speed.
enum ComposerWitnessBeatSpeed {
    static let storageKey = "ghostties.composerWitnessBeatSpeed"
    static let defaultSpeed: Double = 1.0
    static let range: ClosedRange<Double> = 0.5...2.0

    static func speed(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: storageKey) as? Double ?? defaultSpeed
    }
}

/// Session-7 brief §11: "Reset single-line" clears every single-line-only
/// key back to its code default — field size, row size, width, corner
/// radius, shadow preset + its three derived dials, treatment, glass tint,
/// Witness, ghost gap, ghost size, float amplitude, float horizontal
/// amplitude, float period, ghost opacity, and beat speed. Deliberately
/// excludes the legacy `ghostties.composerStyle` key. A single list,
/// `resetKeys`, is the one
/// place both `ComposerDialKitCoordinator`'s reset action and the legacy
/// pill's fallback button read from, so the two can't drift on which keys
/// "reset" covers.
enum ComposerSingleLineReset {
    static var resetKeys: [String] {
        [
            ComposerSingleLineTuning.fieldSizeStorageKey,
            ComposerSingleLineTuning.rowSizeStorageKey,
            ComposerSingleLineTuning.widthStorageKey,
            ComposerSingleLineTuning.cornerRadiusStorageKey,
            ComposerSingleLineShadowPreset.storageKey,
            ComposerSingleLineShadowDials.radiusStorageKey,
            ComposerSingleLineShadowDials.yOffsetStorageKey,
            ComposerSingleLineShadowDials.opacityStorageKey,
            ComposerSingleLineTreatment.storageKey,
            ComposerSingleLineGlassTint.storageKey,
            ComposerWitnessGap.storageKey,
            ComposerWitnessSetting.storageKey,
            ComposerWitnessSize.storageKey,
            ComposerWitnessFloatAmplitude.storageKey,
            ComposerWitnessFloatHorizontal.storageKey,
            ComposerWitnessFloatPeriod.storageKey,
            ComposerWitnessOpacity.storageKey,
            ComposerWitnessBeatSpeed.storageKey
        ]
    }

    static func reset(defaults: UserDefaults = .standard) {
        for key in resetKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Single-line tuning (round 12, session-7 brief, 2026-09-12)
//
// Sean, live look round 11: single-line "feels small." These three dials (field text size, row/status text size,
// container width) are Sean-tunable STRAWMEN, not DESIGN.md values — see
// this file's header MARK for why they live behind `@AppStorage` instead of
// a DESIGN.md edit.

/// `.singleLine`'s field text size, row/status text size, and container
/// width — each independently tunable. Container height and horizontal/
/// vertical padding SCALE from `fieldSize` (`lineHeight`/`verticalPadding`/
/// `horizontalPadding` below) rather than being separate dials, so tuning
/// text size alone can't desync the two — exactly the class of bug a
/// second, uncoupled "container height" dial would invite.
enum ComposerSingleLineTuning {
    static let fieldSizeStorageKey = "ghostties.composerSingleLineFieldSize"
    static let rowSizeStorageKey = "ghostties.composerSingleLineRowSize"
    static let widthStorageKey = "ghostties.composerSingleLineWidth"
    static let cornerRadiusStorageKey = "ghostties.composerSingleLineCornerRadius"

    /// Strawman defaults (brief §2, round 12, "feels small" → bigger):
    /// 15→22pt field text, 13→16pt row/status text, 512→680pt width. The
    /// PRIOR fixed constants (15pt field, 11pt status, 512pt width) are
    /// preserved as the dial's floor, not deleted — Sean can dial back down
    /// to them live.
    ///
    /// Round 13b: Sean tuned these live on an HTML bench mirroring this
    /// code 1pt = 1px and landed on 28pt field / 18pt row / 688pt width.
    /// Round 14 (session-7, live-look round): Sean tuned field size and
    /// width further in Dev (`defaults read
    /// com.seansmithdesign.ghostties.dev`) — field size down to 24pt,
    /// width down to 640pt (a step-8 position from the 480pt floor, same
    /// as round 13b's 688pt). Row size is untouched.
    static let defaultFieldSize: CGFloat = 24
    static let defaultRowSize: CGFloat = 18
    static let defaultWidth: CGFloat = 640
    /// Round 14 (session-7): Sean's Dev-tuned corner radius, up from round
    /// 13b's 10 (the prior `.anchored` card radius).
    static let defaultCornerRadius: CGFloat = 16

    static let fieldSizeRange: ClosedRange<Double> = 15...28
    static let rowSizeRange: ClosedRange<Double> = 11...20
    static let widthRange: ClosedRange<Double> = 480...760
    static let cornerRadiusRange: ClosedRange<Double> = 6...20

    static func fieldSize(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: fieldSizeStorageKey) as? Double
        return CGFloat(stored ?? Double(defaultFieldSize))
    }

    static func rowSize(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: rowSizeStorageKey) as? Double
        return CGFloat(stored ?? Double(defaultRowSize))
    }

    static func width(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: widthStorageKey) as? Double
        return CGFloat(stored ?? Double(defaultWidth))
    }

    static func cornerRadius(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: cornerRadiusStorageKey) as? Double
        return CGFloat(stored ?? Double(defaultCornerRadius))
    }

    /// Preserves the shipped 15pt→38pt relationship (a fixed +23pt) rather
    /// than a fresh ratio — at the old 15pt default this returns exactly 38,
    /// the byte-identical prior constant.
    static func lineHeight(fieldSize: CGFloat) -> CGFloat { fieldSize + 23 }

    /// Preserves the shipped 15pt→(8pt vertical / 16pt horizontal) padding
    /// ratio — scales proportionally with `fieldSize` off that same 15pt
    /// anchor.
    static func verticalPadding(fieldSize: CGFloat) -> CGFloat { 8 * (fieldSize / 15) }
    static func horizontalPadding(fieldSize: CGFloat) -> CGFloat { 16 * (fieldSize / 15) }
}

/// Shadow preset for `.singleLine` (brief §3). Each preset writes tasteful
/// strawman values into the three underlying dials
/// (`ComposerSingleLineShadowDials`) so Sean can pick a starting point, then
/// keep tuning those same three dials by hand without the preset silently
/// overwriting his edits on every render (a preset only WRITES on
/// selection, never re-applies on read).
enum ComposerSingleLineShadowPreset: String, CaseIterable {
    case none
    case soft
    case lifted
    case long
    case custom

    static let storageKey = "ghostties.composerSingleLineShadowPreset"

    /// Round 13b: Sean's tuned defaults (64pt radius, 48pt y, 0.24 opacity)
    /// match none of the three fixed presets, so the fallback here resolves
    /// from the actual dial values (`resolved(radius:yOffset:opacity:)`)
    /// rather than a hardcoded `.soft` — a hardcoded fallback would mislabel
    /// his shadow "Soft" in the picker while it renders as something else
    /// entirely.
    static func current(defaults: UserDefaults = .standard) -> ComposerSingleLineShadowPreset {
        guard let raw = defaults.string(forKey: storageKey),
              let preset = ComposerSingleLineShadowPreset(rawValue: raw) else {
            return resolved(
                radius: ComposerSingleLineShadowDials.radius(defaults: defaults),
                yOffset: ComposerSingleLineShadowDials.yOffset(defaults: defaults),
                opacity: ComposerSingleLineShadowDials.opacity(defaults: defaults)
            )
        }
        return preset
    }

    var dialValues: (radius: CGFloat, yOffset: CGFloat, opacity: Double) {
        switch self {
        case .none: return (0, 0, 0)
        case .soft: return (WorkspaceLayout.composerModalShadowRadius, WorkspaceLayout.composerModalShadowYOffset, WorkspaceLayout.composerModalShadowOpacity)
        case .lifted: return (32, 16, 0.30)
        case .long: return (48, 32, 0.22)
        case .custom: return (48, 32, 0.10)
        }
    }

    /// Which fixed preset (if any) the given dial values match — `.custom`
    /// when they match none. Pure function, same pattern as
    /// `ComposerSingleLineBackgroundChoice.resolve` below.
    static func resolved(radius: CGFloat, yOffset: CGFloat, opacity: Double) -> ComposerSingleLineShadowPreset {
        for preset: ComposerSingleLineShadowPreset in [.none, .soft, .lifted, .long] {
            let values = preset.dialValues
            if values.radius == radius, values.yOffset == yOffset, values.opacity == opacity {
                return preset
            }
        }
        return .custom
    }
}

/// The three shadow dials a preset seeds — independently tunable afterward.
/// `current` reads the live dial values (defaulting to `.soft`'s, the
/// shipped look, when nothing has been written yet).
enum ComposerSingleLineShadowDials {
    static let radiusStorageKey = "ghostties.composerSingleLineShadowRadius"
    static let yOffsetStorageKey = "ghostties.composerSingleLineShadowYOffset"
    static let opacityStorageKey = "ghostties.composerSingleLineShadowOpacity"

    /// Round 13b's fallbacks were 64/48/0.24. Round 14 (session-7): Sean's
    /// Dev-tuned 48/32/0.10 — still literal constants (not `.soft`'s
    /// values) — `ComposerSingleLineShadowPreset.resolved` reads these same
    /// fallbacks when nothing is stored, so a literal here avoids a
    /// circular dependency between the dials and the preset enum.
    static func radius(defaults: UserDefaults = .standard) -> CGFloat {
        guard let stored = defaults.object(forKey: radiusStorageKey) as? Double else {
            return 48
        }
        return CGFloat(stored)
    }

    static func yOffset(defaults: UserDefaults = .standard) -> CGFloat {
        guard let stored = defaults.object(forKey: yOffsetStorageKey) as? Double else {
            return 32
        }
        return CGFloat(stored)
    }

    static func opacity(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: opacityStorageKey) as? Double ?? 0.10
    }

    /// Writes a preset's three values into the dials — the picker's only
    /// action; the dials themselves are what every render actually reads.
    static func apply(_ preset: ComposerSingleLineShadowPreset, defaults: UserDefaults = .standard) {
        let values = preset.dialValues
        defaults.set(Double(values.radius), forKey: radiusStorageKey)
        defaults.set(Double(values.yOffset), forKey: yOffsetStorageKey)
        defaults.set(values.opacity, forKey: opacityStorageKey)
    }
}

/// `.singleLine`'s chrome treatment (brief §4): `.material` is the shipped
/// `.regularMaterial` + `windowBackgroundColor` blend, unchanged; `.glass`
/// uses AppKit's real Liquid Glass API, `NSGlassEffectView` — SwiftUI has no
/// `glassEffect` modifier in this SDK (checked directly against
/// `MacOSX26.5.sdk`'s `SwiftUI.swiftinterface`: only `GlassButtonStyle`/
/// `GlassProminentButtonStyle` exist there); `NSGlassEffectView` is the
/// SAME class `TerminalViewContainer.swift` already ships behind, gated the
/// same way (`#if compiler(>=6.2)` + `@available(macOS 26.0, *)`). See
/// `ComposerLiquidGlassBackground` below for the `NSViewRepresentable`
/// wrapper and `SessionComposerPalette.singleLineComposerCard`'s call site
/// for the macOS-26-and-below fallback (`.material`, always —
/// `decision_align-to-upstream-degrade-gracefully`: never raise the floor
/// for a fork feature).
enum ComposerSingleLineTreatment: String, CaseIterable {
    case material
    case glass

    static let storageKey = "ghostties.composerSingleLineTreatment"

    /// Round 13b: default is `.glass` (Sean's tuned pick) — the macOS-26
    /// availability gate and `.material` degrade-gracefully fallback live at
    /// the `ComposerSingleLineBackgroundChoice.resolve` call site below, not
    /// here.
    static func current(defaults: UserDefaults = .standard) -> ComposerSingleLineTreatment {
        guard let raw = defaults.string(forKey: storageKey),
              let treatment = ComposerSingleLineTreatment(rawValue: raw) else {
            return .glass
        }
        return treatment
    }
}

/// `.singleLine`'s Liquid Glass tint (session-7 brief §3): the hardcoded
/// `.windowBackgroundColor` tint `singleLineComposerCard` always passed to
/// `NSGlassEffectView` made the glass read as a flat opaque panel rather than
/// translucent — `.none` passes `nil` (`NSGlassEffectView.tintColor` is a
/// nullable `NSColor?`, per the AppKit header) so the glass shows through
/// untinted. Only meaningful when `ComposerSingleLineTreatment.glass` is
/// actually resolved (see `ComposerSingleLineBackgroundChoice`); `.material`
/// never reads this.
enum ComposerSingleLineGlassTint: String, CaseIterable {
    case none
    case windowBackground

    static let storageKey = "ghostties.composerSingleLineGlassTint"

    static func current(defaults: UserDefaults = .standard) -> ComposerSingleLineGlassTint {
        guard let raw = defaults.string(forKey: storageKey),
              let tint = ComposerSingleLineGlassTint(rawValue: raw) else {
            return .none
        }
        return tint
    }

    var nsColor: NSColor? {
        switch self {
        case .none: return nil
        case .windowBackground: return .windowBackgroundColor
        }
    }
}

/// Which background layer `.singleLine` actually paints, given the picked
/// treatment AND whether `NSGlassEffectView` is available at runtime. Pulled
/// out as a pure function (rather than inlining `treatment == .glass, #available(...)`
/// at the call site alone) SPECIFICALLY so the fallback rule is unit-testable
/// without needing to fake the OS version at runtime — `glassAvailable` is
/// the one thing a test can set directly; `SessionComposerPalette
/// .isGlassTreatmentAvailable` is the only production call site that
/// resolves it from a real `#available` check.
enum ComposerSingleLineBackgroundChoice: Equatable {
    case glass
    case material

    static func resolve(treatment: ComposerSingleLineTreatment, glassAvailable: Bool) -> ComposerSingleLineBackgroundChoice {
        (treatment == .glass && glassAvailable) ? .glass : .material
    }
}

#if compiler(>=6.2)
/// Thin `NSViewRepresentable` wrapper around `NSGlassEffectView`
/// (`TerminalViewContainer.TerminalGlassView`'s same underlying class) so
/// `.singleLine`'s SwiftUI card can use it as a `.background(...)` layer.
/// macOS 26+ only, matching the class itself.
@available(macOS 26.0, *)
struct ComposerLiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    /// `nil` renders untinted glass (`ComposerSingleLineGlassTint.none`) —
    /// `NSGlassEffectView.tintColor` is itself a nullable `NSColor?`.
    var tintColor: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.tintColor = tintColor
    }
}
#endif

// MARK: - DEBUG-only live tuning control (session-7 brief, 2026-09-11)
//
// Sean, live look: "a little view control just for me to kinda bounce back
// and forth within that composer... there's gonna be ways and spaces where
// I'm gonna wanna tune more." Compiled ONLY under `#if DEBUG` — every symbol
// in this section is unreachable from a Release build. Hosted by
// `SessionComposerOverlay` in the top-trailing corner.
#if DEBUG
struct ComposerDebugTuningControl: View {
    @AppStorage private var singleLineFieldSize: Double
    @AppStorage private var singleLineRowSize: Double
    @AppStorage private var singleLineWidth: Double
    @AppStorage private var singleLineCornerRadius: Double
    @AppStorage private var singleLineShadowPresetRaw: String
    @AppStorage private var singleLineShadowRadius: Double
    @AppStorage private var singleLineShadowYOffset: Double
    @AppStorage private var singleLineShadowOpacity: Double
    @AppStorage private var singleLineTreatmentRaw: String
    @AppStorage private var singleLineGlassTintRaw: String
    @AppStorage private var witnessEnabled: Bool
    @AppStorage private var witnessGap: Double
    @AppStorage private var witnessSize: Double
    @AppStorage private var witnessFloatAmplitude: Double
    @AppStorage private var witnessFloatHorizontalAmplitude: Double
    @AppStorage private var witnessFloatPeriod: Double
    @AppStorage private var witnessOpacity: Double
    @AppStorage private var witnessBeatSpeed: Double

    /// Round 12: kept so `ComposerSingleLineShadowDials.apply` writes to the
    /// SAME `UserDefaults` instance this control's own `@AppStorage`
    /// properties read from (production `.standard`, or a test's isolated
    /// suite) — never a second, un-synced write target.
    private let defaults: UserDefaults

    /// Called after any knob write, so the caller can return keyboard focus
    /// to the composer's search field — this control must never leave focus
    /// stranded on itself.
    var onChange: () -> Void

    /// `defaults` mirrors every other test seam in this feature
    /// (`styleOverrideForTesting`, etc.): production leaves it `.standard`;
    /// a test injects an isolated suite so it never races other parallel
    /// Swift Testing processes reading/writing the same keys.
    init(defaults: UserDefaults = .standard, onChange: @escaping () -> Void = {}) {
        _singleLineFieldSize = AppStorage(wrappedValue: Double(ComposerSingleLineTuning.defaultFieldSize), ComposerSingleLineTuning.fieldSizeStorageKey, store: defaults)
        _singleLineRowSize = AppStorage(wrappedValue: Double(ComposerSingleLineTuning.defaultRowSize), ComposerSingleLineTuning.rowSizeStorageKey, store: defaults)
        _singleLineWidth = AppStorage(wrappedValue: Double(ComposerSingleLineTuning.defaultWidth), ComposerSingleLineTuning.widthStorageKey, store: defaults)
        _singleLineCornerRadius = AppStorage(wrappedValue: Double(ComposerSingleLineTuning.defaultCornerRadius), ComposerSingleLineTuning.cornerRadiusStorageKey, store: defaults)
        _singleLineShadowPresetRaw = AppStorage(wrappedValue: ComposerSingleLineShadowPreset.custom.rawValue, ComposerSingleLineShadowPreset.storageKey, store: defaults)
        _singleLineShadowRadius = AppStorage(wrappedValue: Double(ComposerSingleLineShadowPreset.custom.dialValues.radius), ComposerSingleLineShadowDials.radiusStorageKey, store: defaults)
        _singleLineShadowYOffset = AppStorage(wrappedValue: Double(ComposerSingleLineShadowPreset.custom.dialValues.yOffset), ComposerSingleLineShadowDials.yOffsetStorageKey, store: defaults)
        _singleLineShadowOpacity = AppStorage(wrappedValue: ComposerSingleLineShadowPreset.custom.dialValues.opacity, ComposerSingleLineShadowDials.opacityStorageKey, store: defaults)
        _singleLineTreatmentRaw = AppStorage(wrappedValue: ComposerSingleLineTreatment.glass.rawValue, ComposerSingleLineTreatment.storageKey, store: defaults)
        _singleLineGlassTintRaw = AppStorage(wrappedValue: ComposerSingleLineGlassTint.none.rawValue, ComposerSingleLineGlassTint.storageKey, store: defaults)
        _witnessEnabled = AppStorage(wrappedValue: true, ComposerWitnessSetting.storageKey, store: defaults)
        _witnessGap = AppStorage(wrappedValue: Double(ComposerWitnessGap.defaultGap), ComposerWitnessGap.storageKey, store: defaults)
        _witnessSize = AppStorage(wrappedValue: Double(ComposerWitnessSize.defaultSize), ComposerWitnessSize.storageKey, store: defaults)
        _witnessFloatAmplitude = AppStorage(wrappedValue: ComposerWitnessFloatAmplitude.defaultAmplitude, ComposerWitnessFloatAmplitude.storageKey, store: defaults)
        _witnessFloatHorizontalAmplitude = AppStorage(wrappedValue: ComposerWitnessFloatHorizontal.defaultAmplitude, ComposerWitnessFloatHorizontal.storageKey, store: defaults)
        _witnessFloatPeriod = AppStorage(wrappedValue: ComposerWitnessFloatPeriod.defaultPeriod, ComposerWitnessFloatPeriod.storageKey, store: defaults)
        _witnessOpacity = AppStorage(wrappedValue: ComposerWitnessOpacity.defaultOpacity, ComposerWitnessOpacity.storageKey, store: defaults)
        _witnessBeatSpeed = AppStorage(wrappedValue: ComposerWitnessBeatSpeed.defaultSpeed, ComposerWitnessBeatSpeed.storageKey, store: defaults)
        self.defaults = defaults
        self.onChange = onChange
    }

    /// Not `private` — `ComposerSingleLineStyleTests` (`@testable import`)
    /// drives these directly, the same way it drives real keyboard/AX-free
    /// seams elsewhere in this feature, to prove "the control writes the
    /// right key" without simulating a menu click.
    var singleLineFieldSizeBinding: Binding<Double> {
        Binding(get: { singleLineFieldSize }, set: { singleLineFieldSize = $0; onChange() })
    }

    var singleLineRowSizeBinding: Binding<Double> {
        Binding(get: { singleLineRowSize }, set: { singleLineRowSize = $0; onChange() })
    }

    var singleLineWidthBinding: Binding<Double> {
        Binding(get: { singleLineWidth }, set: { singleLineWidth = $0; onChange() })
    }

    var singleLineCornerRadiusBinding: Binding<Double> {
        Binding(get: { singleLineCornerRadius }, set: { singleLineCornerRadius = $0; onChange() })
    }

    /// Round 12: selecting a preset WRITES the three shadow dials once
    /// (`ComposerSingleLineShadowDials.apply`) — it does not stay "live
    /// bound" to the preset afterward, so tuning a dial post-selection
    /// never gets silently overwritten by this picker re-asserting itself.
    var singleLineShadowPreset: Binding<ComposerSingleLineShadowPreset> {
        Binding(
            get: { ComposerSingleLineShadowPreset(rawValue: singleLineShadowPresetRaw) ?? .soft },
            set: { newValue in
                singleLineShadowPresetRaw = newValue.rawValue
                ComposerSingleLineShadowDials.apply(newValue, defaults: defaults)
                let values = newValue.dialValues
                singleLineShadowRadius = Double(values.radius)
                singleLineShadowYOffset = Double(values.yOffset)
                singleLineShadowOpacity = values.opacity
                onChange()
            }
        )
    }

    var singleLineShadowRadiusBinding: Binding<Double> {
        Binding(get: { singleLineShadowRadius }, set: { singleLineShadowRadius = $0; onChange() })
    }

    var singleLineShadowYOffsetBinding: Binding<Double> {
        Binding(get: { singleLineShadowYOffset }, set: { singleLineShadowYOffset = $0; onChange() })
    }

    var singleLineShadowOpacityBinding: Binding<Double> {
        Binding(get: { singleLineShadowOpacity }, set: { singleLineShadowOpacity = $0; onChange() })
    }

    var singleLineTreatment: Binding<ComposerSingleLineTreatment> {
        Binding(
            get: { ComposerSingleLineTreatment(rawValue: singleLineTreatmentRaw) ?? .material },
            set: { singleLineTreatmentRaw = $0.rawValue; onChange() }
        )
    }

    var singleLineGlassTint: Binding<ComposerSingleLineGlassTint> {
        Binding(
            get: { ComposerSingleLineGlassTint(rawValue: singleLineGlassTintRaw) ?? .none },
            set: { singleLineGlassTintRaw = $0.rawValue; onChange() }
        )
    }

    /// R14: not `private`, same testability pattern as the bindings above.
    var witness: Binding<Bool> {
        Binding(get: { witnessEnabled }, set: { witnessEnabled = $0; onChange() })
    }

    var witnessGapBinding: Binding<Double> {
        Binding(get: { witnessGap }, set: { witnessGap = $0; onChange() })
    }

    var witnessSizeBinding: Binding<Double> {
        Binding(get: { witnessSize }, set: { witnessSize = $0; onChange() })
    }

    var witnessFloatAmplitudeBinding: Binding<Double> {
        Binding(get: { witnessFloatAmplitude }, set: { witnessFloatAmplitude = $0; onChange() })
    }

    var witnessFloatHorizontalAmplitudeBinding: Binding<Double> {
        Binding(get: { witnessFloatHorizontalAmplitude }, set: { witnessFloatHorizontalAmplitude = $0; onChange() })
    }

    var witnessFloatPeriodBinding: Binding<Double> {
        Binding(get: { witnessFloatPeriod }, set: { witnessFloatPeriod = $0; onChange() })
    }

    var witnessOpacityBinding: Binding<Double> {
        Binding(get: { witnessOpacity }, set: { witnessOpacity = $0; onChange() })
    }

    var witnessBeatSpeedBinding: Binding<Double> {
        Binding(get: { witnessBeatSpeed }, set: { witnessBeatSpeed = $0; onChange() })
    }

    /// Session-7 brief §11: clears every single-line key
    /// (`ComposerSingleLineReset.resetKeys`) back to its code default, then
    /// re-reads each `@AppStorage` property from the now-empty keys so the
    /// pill reflects the reset immediately — `@AppStorage` doesn't notice an
    /// external `removeObject` on its own store reference until the next
    /// read, so each property is reassigned explicitly here rather than
    /// left to redraw on its own.
    func resetSingleLine() {
        ComposerSingleLineReset.reset(defaults: defaults)
        singleLineFieldSize = Double(ComposerSingleLineTuning.defaultFieldSize)
        singleLineRowSize = Double(ComposerSingleLineTuning.defaultRowSize)
        singleLineWidth = Double(ComposerSingleLineTuning.defaultWidth)
        singleLineCornerRadius = Double(ComposerSingleLineTuning.defaultCornerRadius)
        let preset = ComposerSingleLineShadowPreset.current(defaults: defaults)
        singleLineShadowPresetRaw = preset.rawValue
        singleLineShadowRadius = Double(ComposerSingleLineShadowDials.radius(defaults: defaults))
        singleLineShadowYOffset = Double(ComposerSingleLineShadowDials.yOffset(defaults: defaults))
        singleLineShadowOpacity = ComposerSingleLineShadowDials.opacity(defaults: defaults)
        singleLineTreatmentRaw = ComposerSingleLineTreatment.current(defaults: defaults).rawValue
        singleLineGlassTintRaw = ComposerSingleLineGlassTint.current(defaults: defaults).rawValue
        witnessEnabled = ComposerWitnessSetting.isEnabled(defaults: defaults)
        witnessGap = Double(ComposerWitnessGap.gap(defaults: defaults))
        witnessSize = Double(ComposerWitnessSize.size(defaults: defaults))
        witnessFloatAmplitude = ComposerWitnessFloatAmplitude.amplitude(defaults: defaults)
        witnessFloatHorizontalAmplitude = ComposerWitnessFloatHorizontal.amplitude(defaults: defaults)
        witnessFloatPeriod = ComposerWitnessFloatPeriod.period(defaults: defaults)
        witnessOpacity = ComposerWitnessOpacity.opacity(defaults: defaults)
        witnessBeatSpeed = ComposerWitnessBeatSpeed.speed(defaults: defaults)
        onChange()
    }

    /// Round 12: a labeled `Slider` row, the DEBUG pill's stand-in for a
    /// continuous dial (`Picker` only fits discrete choices, used
    /// everywhere else in this control). Round 13 replaces this with a real
    /// `DialKit` panel (`ComposerDialKitHost` below) on macOS 14+; this row
    /// stays as the macOS 13 fallback body only (`decision_align-to-
    /// upstream-degrade-gracefully` — DialKit itself needs macOS 14).
    @ViewBuilder
    private func dialRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Slider(value: value, in: range)
                .frame(width: 90)
            Text(String(format: format, value.wrappedValue))
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// Round 13: real DialKit (vendored `macos/Packages/DialKit`, v0.3) is
    /// the tuning surface on macOS 14+, per Sean's explicit ask — round 12's
    /// slider rows were a substitute the review rejected. DialKit's SwiftUI
    /// surface (`DialPanelView.swift`) uses the two-parameter
    /// `.onChange(of:) { _, new in }` form throughout, which is a macOS
    /// 14/iOS 17 SDK API, not just a deployment-target nicety — so this
    /// branch, not a lowered package platform, is what keeps the app's
    /// macOS 13 floor intact (`decision_align-to-upstream-degrade-
    /// gracefully`). Below 14, the ORIGINAL round-12 picker/slider pill
    /// (`legacyBody`) is the fallback — core function (every knob still
    /// reachable) survives on the floor OS; only the nicer dial surface is
    /// macOS-14-and-up.
    var body: some View {
        if #available(macOS 14, *) {
            ComposerDialKitHost(defaults: defaults, onChange: onChange)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Treatment", selection: singleLineTreatment) {
                Text("Material").tag(ComposerSingleLineTreatment.material)
                Text("Liquid Glass").tag(ComposerSingleLineTreatment.glass)
            }
            Picker("Glass tint", selection: singleLineGlassTint) {
                Text("None").tag(ComposerSingleLineGlassTint.none)
                Text("Window background").tag(ComposerSingleLineGlassTint.windowBackground)
            }
            dialRow("Width", value: singleLineWidthBinding, range: ComposerSingleLineTuning.widthRange, format: "%.0fpt")
            dialRow("Corner radius", value: singleLineCornerRadiusBinding, range: ComposerSingleLineTuning.cornerRadiusRange, format: "%.0fpt")
            dialRow("Field size", value: singleLineFieldSizeBinding, range: ComposerSingleLineTuning.fieldSizeRange, format: "%.0fpt")
            dialRow("Row size", value: singleLineRowSizeBinding, range: ComposerSingleLineTuning.rowSizeRange, format: "%.0fpt")
            Picker("Shadow", selection: singleLineShadowPreset) {
                Text("None").tag(ComposerSingleLineShadowPreset.none)
                Text("Soft").tag(ComposerSingleLineShadowPreset.soft)
                Text("Lifted").tag(ComposerSingleLineShadowPreset.lifted)
                Text("Long").tag(ComposerSingleLineShadowPreset.long)
                Text("Custom").tag(ComposerSingleLineShadowPreset.custom)
            }
            dialRow("Shadow radius", value: singleLineShadowRadiusBinding, range: 0...64, format: "%.0f")
            dialRow("Shadow length", value: singleLineShadowYOffsetBinding, range: 0...64, format: "%.0f")
            dialRow("Shadow opacity", value: singleLineShadowOpacityBinding, range: 0...0.6, format: "%.2f")
            Picker("Witness", selection: witness) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
            dialRow("Ghost size", value: witnessSizeBinding, range: ComposerWitnessSize.range, format: "%.0fpt")
            dialRow("Ghost gap", value: witnessGapBinding, range: ComposerWitnessGap.range, format: "%.0fpt")
            dialRow("Float vertical", value: witnessFloatAmplitudeBinding, range: ComposerWitnessFloatAmplitude.range, format: "%.1fpt")
            dialRow("Float horizontal", value: witnessFloatHorizontalAmplitudeBinding, range: ComposerWitnessFloatHorizontal.range, format: "%.1fpt")
            dialRow("Float period", value: witnessFloatPeriodBinding, range: ComposerWitnessFloatPeriod.range, format: "%.1fs")
            dialRow("Ghost opacity", value: witnessOpacityBinding, range: ComposerWitnessOpacity.range, format: "%.2f")
            dialRow("Beat speed", value: witnessBeatSpeedBinding, range: ComposerWitnessBeatSpeed.range, format: "%.2f×")
            Button("Reset single-line") { resetSingleLine() }
        }
        .pickerStyle(.menu)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Swallows every tap on the pill's own padding/background — a tap
        // that reached the dismiss layer beneath would close the composer;
        // this control must never do that.
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

// MARK: - Round 13: real DialKit tuning panel (macOS 14+)
//
// Vendored MIT-licensed source, `macos/Packages/DialKit` (v0.3, unmodified —
// `DialKit`'s own `Package.swift` still declares `.macOS(.v14)`; SwiftPM/
// Xcode enforce that as a per-call-site availability requirement on a
// consumer with a LOWER deployment target, exactly like any other macOS
// 14-only API, rather than refusing to link — so every symbol below is
// wrapped in `@available(macOS 14, *)`/`if #available(macOS 14, *)` instead
// of the package itself being patched down to `.v13`.
@available(macOS 14, *)
struct ComposerDialKitTuningModel: Codable, Equatable {
    var singleLineFieldSize: Double
    var singleLineRowSize: Double
    var singleLineWidth: Double
    var singleLineCornerRadius: Double
    private var shadowPresetRawStorage: String
    var shadowRadius: Double
    var shadowYOffset: Double
    var shadowOpacity: Double
    var treatmentRaw: String
    var glassTintRaw: String
    var witnessEnabled: Bool
    var witnessGap: Double
    var witnessSize: Double
    var witnessFloatAmplitude: Double
    var witnessFloatHorizontalAmplitude: Double
    var witnessFloatPeriod: Double
    var witnessOpacity: Double
    var witnessBeatSpeed: Double

    /// The `shadowPreset` `.select` control (in `ComposerDialKitCoordinator
    /// .controls`) writes through this keyPath via DialKit's generic
    /// `{ model, newValue in model[keyPath: keyPath] = newValue }` setter,
    /// which then assigns the WHOLE mutated model to `state.values` in a
    /// single call (`DialControlNode.resolve`'s `.select` case, vendored,
    /// unread here). Expanding the preset into the three derived dials
    /// INSIDE this setter — rather than after, in the coordinator's
    /// `state.$values` sink — means that single outer assignment already
    /// carries the derived dials, so nothing needs to re-enter or reassign
    /// `state.values` at all. See `ComposerDialKitCoordinator.handle` for
    /// why a second, later write to `state.values` from inside its own
    /// change sink cannot be made to stick synchronously.
    var shadowPresetRaw: String {
        get { shadowPresetRawStorage }
        set {
            shadowPresetRawStorage = newValue
            // `.custom` has no fixed dial values of its own — it is the
            // label for "whatever the three dials currently read," so
            // selecting it must leave them exactly where the user hand-
            // tuned them. Deriving from `.custom.dialValues` here would
            // snap a hand-tuned shadow to that placeholder triple on every
            // selection (the bug this guard fixes).
            guard let preset = ComposerSingleLineShadowPreset(rawValue: newValue),
                  preset != .custom else { return }
            let values = preset.dialValues
            shadowRadius = Double(values.radius)
            shadowYOffset = Double(values.yOffset)
            shadowOpacity = values.opacity
        }
    }

    init(
        singleLineFieldSize: Double,
        singleLineRowSize: Double,
        singleLineWidth: Double,
        singleLineCornerRadius: Double,
        shadowPresetRaw: String,
        shadowRadius: Double,
        shadowYOffset: Double,
        shadowOpacity: Double,
        treatmentRaw: String,
        glassTintRaw: String,
        witnessEnabled: Bool,
        witnessGap: Double,
        witnessSize: Double,
        witnessFloatAmplitude: Double,
        witnessFloatHorizontalAmplitude: Double,
        witnessFloatPeriod: Double,
        witnessOpacity: Double,
        witnessBeatSpeed: Double
    ) {
        self.singleLineFieldSize = singleLineFieldSize
        self.singleLineRowSize = singleLineRowSize
        self.singleLineWidth = singleLineWidth
        self.singleLineCornerRadius = singleLineCornerRadius
        // Direct storage assignment, NOT the computed setter above: the
        // caller (`ComposerDialKitCoordinator.readModel`) already reads
        // `shadowRadius`/`shadowYOffset`/`shadowOpacity` independently from
        // `UserDefaults`, so re-deriving them from `shadowPresetRaw` here
        // would discard an independently-tuned dial that happens to not
        // match its labeled preset (round 13b's "custom" case).
        self.shadowPresetRawStorage = shadowPresetRaw
        self.shadowRadius = shadowRadius
        self.shadowYOffset = shadowYOffset
        self.shadowOpacity = shadowOpacity
        self.treatmentRaw = treatmentRaw
        self.glassTintRaw = glassTintRaw
        self.witnessEnabled = witnessEnabled
        self.witnessGap = witnessGap
        self.witnessSize = witnessSize
        self.witnessFloatAmplitude = witnessFloatAmplitude
        self.witnessFloatHorizontalAmplitude = witnessFloatHorizontalAmplitude
        self.witnessFloatPeriod = witnessFloatPeriod
        self.witnessOpacity = witnessOpacity
        self.witnessBeatSpeed = witnessBeatSpeed
    }

    private enum CodingKeys: String, CodingKey {
        case singleLineFieldSize, singleLineRowSize, singleLineWidth, singleLineCornerRadius
        case shadowPresetRawStorage = "shadowPresetRaw"
        case shadowRadius, shadowYOffset, shadowOpacity, treatmentRaw, glassTintRaw
        case witnessEnabled, witnessGap
        case witnessSize, witnessFloatAmplitude, witnessFloatHorizontalAmplitude, witnessFloatPeriod, witnessOpacity, witnessBeatSpeed
    }
}

/// Owns the `DialPanelState` and mirrors every change back into the same
/// `@AppStorage` keys `ComposerDebugTuningControl`/production reads —
/// `DialPanelState` is its own source of truth while the panel is open, so
/// this is a one-way "panel changed → write UserDefaults" sync, not a
/// two-way live binding; UserDefaults is always re-read on next launch,
/// matching every other knob in this file.
///
/// Round-13 review finding #2: writing the WHOLE model on every emission let
/// one open panel clobber a key a second panel (or the legacy pill, or a raw
/// `defaults write`) had just changed but this panel's own snapshot hadn't
/// seen. Fix is diff-based: `write(from:to:)` only calls `defaults.set` for
/// fields that actually moved between the previous and current emission of
/// `state.values` — since nothing external ever mutates `state.values`
/// itself, any field difference between two consecutive emissions is by
/// construction a change the user just made IN THIS PANEL, so a field this
/// panel never touched is never re-persisted, however stale this panel's
/// last-known value for it is. No `UserDefaults.didChangeNotification`/KVO
/// observer is needed for that guarantee — it would only add a live-refresh
/// nicety, not fix the clobber, and risks its own panel ⇄ defaults loop.
@available(macOS 14, *)
@MainActor
final class ComposerDialKitCoordinator: ObservableObject {
    let state: DialPanelState<ComposerDialKitTuningModel>
    private var cancellable: AnyCancellable?
    private let defaults: UserDefaults
    private let onChange: () -> Void
    private var lastKnownModel: ComposerDialKitTuningModel
    init(defaults: UserDefaults, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        let initial = Self.readModel(defaults: defaults)
        lastKnownModel = initial
        // `DialPanelState.onAction` is set once, at construction, and
        // needs to call back into this coordinator's `handleAction` — but
        // `self` isn't a valid class instance yet at this point in `init`
        // (Swift forbids capturing `self` in a closure before every stored
        // property is assigned). `selfBox` is a tiny already-fully-formed
        // object the closure can capture instead; `self` is dropped into it
        // once `state`/`cancellable` are both set below.
        let selfBox = ComposerDialKitCoordinatorBox()
        state = DialPanelState(
            name: "Composer Tuning",
            initial: initial,
            controls: Self.controls,
            onAction: { path in selfBox.coordinator?.handleAction(path) }
        )
        // `DialPanelState.init` normalizes `initial` against each control's
        // range/step (e.g. rounds a width to the nearest 10) BEFORE storing
        // it as `state.values` — capturing `lastKnownModel` from the
        // pre-normalization `initial` instead of the panel's own
        // (possibly-rounded) `state.values` left `lastKnownModel` off by
        // whatever a control rounded away. `write(from:to:)` then diffed
        // that phantom drift as a real user edit on the very first
        // unrelated change and clobbered a key nobody touched. Round 13b's
        // 688pt width default (not a multiple of the width dial's 10pt
        // step; round 14 changed the default to 640pt, also not a multiple
        // of 10) is what exposed this — round 12's 680pt default happened
        // to already be a multiple of 10.
        lastKnownModel = state.values
        cancellable = state.$values
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handle(newValue)
            }
        selfBox.coordinator = self
    }

    /// Round-13 review finding #1: the `shadowPreset` `.select` control only
    /// ever wrote `shadowPresetRaw` — none of `ComposerSingleLineShadowPreset`'s
    /// three derived dial values (mirroring the legacy pill's
    /// `singleLineShadowPreset` binding, which calls
    /// `ComposerSingleLineShadowDials.apply` on every selection) — so picking
    /// a preset here left the three sliders, and the persisted keys they
    /// write, exactly where they were.
    ///
    /// Round-13c found that deriving the three dials HERE, inside this sink,
    /// and reassigning them back onto `state.values` doesn't work: `@Published`
    /// publishes in `willSet`, before its backing storage commits, so a
    /// synchronous reassignment from inside this sink re-enters the still-
    /// in-flight outer setter, which then overwrites the reassignment with
    /// its own (stale, un-derived) value the moment it returns. A queued
    /// `DispatchQueue.main.async` reassignment "fixed" that by landing after
    /// the outer setter returned, but left the model briefly inconsistent
    /// (persisted keys already had the derived dials; the panel's own
    /// sliders didn't, for one runloop turn) and was fragile to any other
    /// main-queue write landing in between.
    ///
    /// Round-13d fixes this structurally instead: `ComposerDialKitTuningModel
    /// .shadowPresetRaw` is a computed property whose setter derives and
    /// writes the three dials as part of the SAME model mutation. The
    /// `.select` control's generic keyPath setter (`DialControlNode.resolve`,
    /// vendored DialKit) calls that computed setter, then performs its one
    /// and only `state.values = updated` assignment — already carrying the
    /// derived dials. This sink never needs to write `state.values` at all;
    /// it only diffs and persists whatever arrived.
    private func handle(_ model: ComposerDialKitTuningModel) {
        let previous = lastKnownModel
        lastKnownModel = model
        write(from: previous, to: model)
    }

    /// Session-7 brief §11: "Reset single-line" — the only `.action`
    /// control in this panel, routed here via `DialPanelState`'s
    /// `onAction` (see the `selfBox` doc comment in `init`). Not `private`
    /// — `DialPanelState.triggerAction`, the real trigger path, is
    /// `package`-scoped inside the vendored DialKit package and unreachable
    /// from `ComposerSingleLineStyleTests` (a different module), so tests
    /// call this directly instead, the same testability pattern as
    /// `ComposerDebugTuningControl.style`/`witness` above.
    func handleAction(_ path: String) {
        guard path == Self.resetActionPath else { return }
        resetSingleLine()
    }

    /// Clears every single-line key in `UserDefaults`
    /// (`ComposerSingleLineReset.resetKeys`), then re-reads the model from
    /// those now-empty keys and pushes it straight into `state.values` so
    /// the panel's own sliders/pickers reflect the reset on the same frame
    /// — `write(from:to:)` is a no-op here because `lastKnownModel` is set
    /// to the fresh model BEFORE `state.values` is reassigned, so the
    /// diff it would compute is empty and it never re-writes the keys this
    /// just cleared.
    private func resetSingleLine() {
        ComposerSingleLineReset.reset(defaults: defaults)
        let freshModel = Self.readModel(defaults: defaults)
        lastKnownModel = freshModel
        state.values = freshModel
        onChange()
    }

    private static func readModel(defaults: UserDefaults) -> ComposerDialKitTuningModel {
        ComposerDialKitTuningModel(
            singleLineFieldSize: Double(ComposerSingleLineTuning.fieldSize(defaults: defaults)),
            singleLineRowSize: Double(ComposerSingleLineTuning.rowSize(defaults: defaults)),
            singleLineWidth: Double(ComposerSingleLineTuning.width(defaults: defaults)),
            singleLineCornerRadius: Double(ComposerSingleLineTuning.cornerRadius(defaults: defaults)),
            shadowPresetRaw: ComposerSingleLineShadowPreset.current(defaults: defaults).rawValue,
            shadowRadius: Double(ComposerSingleLineShadowDials.radius(defaults: defaults)),
            shadowYOffset: Double(ComposerSingleLineShadowDials.yOffset(defaults: defaults)),
            shadowOpacity: ComposerSingleLineShadowDials.opacity(defaults: defaults),
            treatmentRaw: ComposerSingleLineTreatment.current(defaults: defaults).rawValue,
            glassTintRaw: ComposerSingleLineGlassTint.current(defaults: defaults).rawValue,
            witnessEnabled: ComposerWitnessSetting.isEnabled(defaults: defaults),
            witnessGap: Double(ComposerWitnessGap.gap(defaults: defaults)),
            witnessSize: Double(ComposerWitnessSize.size(defaults: defaults)),
            witnessFloatAmplitude: ComposerWitnessFloatAmplitude.amplitude(defaults: defaults),
            witnessFloatHorizontalAmplitude: ComposerWitnessFloatHorizontal.amplitude(defaults: defaults),
            witnessFloatPeriod: ComposerWitnessFloatPeriod.period(defaults: defaults),
            witnessOpacity: ComposerWitnessOpacity.opacity(defaults: defaults),
            witnessBeatSpeed: ComposerWitnessBeatSpeed.speed(defaults: defaults)
        )
    }

    /// Persists only the fields where `to` differs from `from` — see the
    /// coordinator doc comment above for why a full-model write is the bug.
    private func write(from previous: ComposerDialKitTuningModel, to model: ComposerDialKitTuningModel) {
        guard previous != model else { return }
        if model.singleLineFieldSize != previous.singleLineFieldSize {
            defaults.set(model.singleLineFieldSize, forKey: ComposerSingleLineTuning.fieldSizeStorageKey)
        }
        if model.singleLineRowSize != previous.singleLineRowSize {
            defaults.set(model.singleLineRowSize, forKey: ComposerSingleLineTuning.rowSizeStorageKey)
        }
        if model.singleLineWidth != previous.singleLineWidth {
            defaults.set(model.singleLineWidth, forKey: ComposerSingleLineTuning.widthStorageKey)
        }
        if model.singleLineCornerRadius != previous.singleLineCornerRadius {
            defaults.set(model.singleLineCornerRadius, forKey: ComposerSingleLineTuning.cornerRadiusStorageKey)
        }
        if model.shadowPresetRaw != previous.shadowPresetRaw {
            defaults.set(model.shadowPresetRaw, forKey: ComposerSingleLineShadowPreset.storageKey)
        }
        if model.shadowRadius != previous.shadowRadius {
            defaults.set(model.shadowRadius, forKey: ComposerSingleLineShadowDials.radiusStorageKey)
        }
        if model.shadowYOffset != previous.shadowYOffset {
            defaults.set(model.shadowYOffset, forKey: ComposerSingleLineShadowDials.yOffsetStorageKey)
        }
        if model.shadowOpacity != previous.shadowOpacity {
            defaults.set(model.shadowOpacity, forKey: ComposerSingleLineShadowDials.opacityStorageKey)
        }
        if model.treatmentRaw != previous.treatmentRaw {
            defaults.set(model.treatmentRaw, forKey: ComposerSingleLineTreatment.storageKey)
        }
        if model.glassTintRaw != previous.glassTintRaw {
            defaults.set(model.glassTintRaw, forKey: ComposerSingleLineGlassTint.storageKey)
        }
        if model.witnessEnabled != previous.witnessEnabled {
            defaults.set(model.witnessEnabled, forKey: ComposerWitnessSetting.storageKey)
        }
        if model.witnessGap != previous.witnessGap {
            defaults.set(model.witnessGap, forKey: ComposerWitnessGap.storageKey)
        }
        if model.witnessSize != previous.witnessSize {
            defaults.set(model.witnessSize, forKey: ComposerWitnessSize.storageKey)
        }
        if model.witnessFloatAmplitude != previous.witnessFloatAmplitude {
            defaults.set(model.witnessFloatAmplitude, forKey: ComposerWitnessFloatAmplitude.storageKey)
        }
        if model.witnessFloatHorizontalAmplitude != previous.witnessFloatHorizontalAmplitude {
            defaults.set(model.witnessFloatHorizontalAmplitude, forKey: ComposerWitnessFloatHorizontal.storageKey)
        }
        if model.witnessFloatPeriod != previous.witnessFloatPeriod {
            defaults.set(model.witnessFloatPeriod, forKey: ComposerWitnessFloatPeriod.storageKey)
        }
        if model.witnessOpacity != previous.witnessOpacity {
            defaults.set(model.witnessOpacity, forKey: ComposerWitnessOpacity.storageKey)
        }
        if model.witnessBeatSpeed != previous.witnessBeatSpeed {
            defaults.set(model.witnessBeatSpeed, forKey: ComposerWitnessBeatSpeed.storageKey)
        }
        onChange()
    }

    /// Session-7 brief: path of the single `.action` control — checked by
    /// `handleAction` against `DialResolvedControl.path`'s value for an
    /// unprefixed (not-in-a-group) control, which equals its own `path`.
    private static let resetActionPath = "resetSingleLine"

    /// Session-7 brief §"Strawman to build": the panel's dial order —
    /// Treatment, Glass tint, Width, Corner radius, Field size, Row size,
    /// Shadow (preset + 3 dials), Witness, Ghost size, Ghost gap, Float
    /// vertical, Float horizontal, Float period, Ghost opacity, Beat speed,
    /// Reset.
    static let controls: [DialControl<ComposerDialKitTuningModel>] = [
        .select(
            "treatment", keyPath: \.treatmentRaw, label: "Treatment",
            options: [
                DialOption(ComposerSingleLineTreatment.material.rawValue, label: "Material"),
                DialOption(ComposerSingleLineTreatment.glass.rawValue, label: "Liquid Glass")
            ]
        ),
        .select(
            "glassTint", keyPath: \.glassTintRaw, label: "Glass tint",
            options: [
                DialOption(ComposerSingleLineGlassTint.none.rawValue, label: "None"),
                DialOption(ComposerSingleLineGlassTint.windowBackground.rawValue, label: "Window background")
            ]
        ),
        // R13c: the width range's inferred step (10, since the range
        // spans 280pt: `DialTypes.dialInferredStep`) doesn't divide
        // evenly from `widthRange.lowerBound` (480) to Sean's tuned
        // width default — `dialRound` would nudge an off-step default
        // the instant the panel opened. 8 does: round 14's 640pt default
        // is still an exact step-8 position ((640 - 480) % 8 == 0), same
        // as round 13b's 688pt, so the dial never nudges it, while still
        // giving 35 steps across the 280pt range (finer than the
        // inferred 10pt, still usable).
        .slider(
            "singleLineWidth", keyPath: \.singleLineWidth, label: "Width",
            range: ComposerSingleLineTuning.widthRange, step: 8, unit: "pt"
        ),
        .slider(
            "singleLineCornerRadius", keyPath: \.singleLineCornerRadius, label: "Corner radius",
            range: ComposerSingleLineTuning.cornerRadiusRange, unit: "pt"
        ),
        .slider(
            "singleLineFieldSize", keyPath: \.singleLineFieldSize, label: "Field size",
            range: ComposerSingleLineTuning.fieldSizeRange, unit: "pt"
        ),
        .slider(
            "singleLineRowSize", keyPath: \.singleLineRowSize, label: "Row size",
            range: ComposerSingleLineTuning.rowSizeRange, unit: "pt"
        ),
        .select(
            "shadowPreset", keyPath: \.shadowPresetRaw, label: "Shadow",
            options: [
                DialOption(ComposerSingleLineShadowPreset.none.rawValue, label: "None"),
                DialOption(ComposerSingleLineShadowPreset.soft.rawValue, label: "Soft"),
                DialOption(ComposerSingleLineShadowPreset.lifted.rawValue, label: "Lifted"),
                DialOption(ComposerSingleLineShadowPreset.long.rawValue, label: "Long"),
                DialOption(ComposerSingleLineShadowPreset.custom.rawValue, label: "Custom")
            ]
        ),
        .slider("shadowRadius", keyPath: \.shadowRadius, label: "Shadow radius", range: 0...64),
        .slider("shadowYOffset", keyPath: \.shadowYOffset, label: "Shadow length", range: 0...64),
        .slider("shadowOpacity", keyPath: \.shadowOpacity, label: "Shadow opacity", range: 0...0.6),
        .toggle("witness", keyPath: \.witnessEnabled, label: "Witness"),
        .slider(
            "witnessSize", keyPath: \.witnessSize, label: "Ghost size",
            range: ComposerWitnessSize.range, step: 6, unit: "pt"
        ),
        .slider(
            "witnessGap", keyPath: \.witnessGap, label: "Ghost gap",
            range: ComposerWitnessGap.range, unit: "pt"
        ),
        .slider(
            "witnessFloatAmplitude", keyPath: \.witnessFloatAmplitude, label: "Float vertical",
            range: ComposerWitnessFloatAmplitude.range, step: 0.5, unit: "pt"
        ),
        .slider(
            "witnessFloatHorizontalAmplitude", keyPath: \.witnessFloatHorizontalAmplitude, label: "Float horizontal",
            range: ComposerWitnessFloatHorizontal.range, step: 0.5, unit: "pt"
        ),
        .slider(
            "witnessFloatPeriod", keyPath: \.witnessFloatPeriod, label: "Float period",
            range: ComposerWitnessFloatPeriod.range, step: 0.5, unit: "s"
        ),
        .slider(
            "witnessOpacity", keyPath: \.witnessOpacity, label: "Ghost opacity",
            range: ComposerWitnessOpacity.range, step: 0.05
        ),
        .slider(
            "witnessBeatSpeed", keyPath: \.witnessBeatSpeed, label: "Beat speed",
            range: ComposerWitnessBeatSpeed.range, step: 0.25, unit: "×"
        ),
        .action(resetActionPath, label: "Reset single-line")
    ]

}

/// A separate, already-fully-initialized object `ComposerDialKitCoordinator
/// .init` hands its `onAction` closure instead of capturing `self` — Swift
/// forbids capturing `self` in a closure before every stored property of a
/// class is assigned, but `DialPanelState.onAction` can only be supplied at
/// construction time (it's an immutable `let`, no post-init setter). The box
/// itself is a normal, fully-formed instance the moment it's created, so
/// capturing IT is legal; `coordinator` is filled in at the very end of
/// `init`, once `self` is safe to hand out.
@available(macOS 14, *)
@MainActor
private final class ComposerDialKitCoordinatorBox {
    weak var coordinator: ComposerDialKitCoordinator?
}

/// Hosts DialKit **inline** (Session-7 brief, 2026-09-13) inside a narrow
/// container we own — the vendored `.drawer` mode used to render at
/// container-width-minus-inset (`dialResolvedDrawerWidth`), which covered
/// the single-line composer card. `.inline` mode (`DialRoot.swift`) has no
/// drawer chrome and no width opinion of its own beyond the panel's fixed
/// 280pt (`DialPanelContainer.expandedPanel`, vendored, not ours to
/// resize); everything about NOT covering the composer — width, corner
/// anchor, max height, collapse — is this wrapper's job.
///
/// `@StateObject` keeps `ComposerDialKitCoordinator` (and the
/// `DialPanelState` it owns) alive for this view's identity; letting it
/// deinit would unregister the panel from `DialStore.shared` and the panel
/// would vanish.
@available(macOS 14, *)
private struct ComposerDialKitHost: View {
    @StateObject private var coordinator: ComposerDialKitCoordinator

    /// UI-chrome state (not a composer tuning value — never round-trips
    /// through `ComposerDialKitCoordinator.write(from:to:)`), but stored in
    /// the SAME injected `defaults` the coordinator uses rather than
    /// `UserDefaults.standard`. `feedback-test-run-never-touch-real-
    /// defaults-domain` (`agent-build.md` Gotchas, 2026-09-10): a hardcoded
    /// `.standard` store here would make any future test of the collapse
    /// control write into the real app domain. `defaultsForTesting` at the
    /// `SessionComposerOverlay` call site already gives tests a throwaway
    /// store; this key rides along on it for free.
    static let collapsedDefaultsKey = "ghostties.composerDialKitPanelCollapsed"

    /// DESIGN.md §5: 320pt is a 4pt-scale multiple (80 × 4) and comfortably
    /// exceeds DialKit's own fixed 280pt panel width, leaving the container
    /// itself as the thing with headroom, not the panel content. The
    /// top-trailing edge inset (DESIGN.md §5 spacing scale `md`, 12pt) is
    /// applied at the call site's existing `.padding(12)`
    /// (`SessionComposerOverlay.swift`) — not duplicated here.
    private static let panelWidth: CGFloat = 320

    @AppStorage private var isCollapsed: Bool

    init(defaults: UserDefaults, onChange: @escaping () -> Void) {
        _coordinator = StateObject(wrappedValue: ComposerDialKitCoordinator(defaults: defaults, onChange: onChange))
        _isCollapsed = AppStorage(wrappedValue: false, Self.collapsedDefaultsKey, store: defaults)
    }

    var body: some View {
        // `GeometryReader` reads the space this control's own `.overlay`
        // slot has available (already reduced by the `.padding(12)` the
        // call site applies — see `SessionComposerOverlay.swift`), so the
        // scroll viewport below caps at "available height," not a fixed
        // guess. An empty-space `VStack` with no background over most of
        // its bounds does not intercept clicks on macOS, so this does not
        // create a click-blocking layer over the composer beneath it.
        GeometryReader { geometry in
            VStack(alignment: .trailing, spacing: 8) {
                collapseControl
                if !isCollapsed {
                    ScrollView(showsIndicators: false) {
                        DialRoot(mode: .inline)
                    }
                    .frame(maxHeight: max(0, geometry.size.height - collapsedControlReservedHeight))
                }
            }
            .frame(width: Self.panelWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    /// Collapse-control height (32pt circle) + the `VStack`'s 8pt spacing —
    /// subtracted from the available height so the scroll viewport below it
    /// never gets pushed past the container's own bottom edge.
    private var collapsedControlReservedHeight: CGFloat { 40 }

    private var collapseControl: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            Image(systemName: isCollapsed ? "slider.horizontal.3" : "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(white: 0.13)))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
    }
}
#endif
