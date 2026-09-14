import SwiftUI
import AppKit
#if DEBUG
import Combine
import DialKit
#endif

// MARK: - Composer style flag (spike, beta.25 hold)
//
// Zero-chrome + single-line composer redesign, behind `ghostties.composerStyle`.
// Sean's decision (2026-09-13): single-line is now the default composer style
// for everyone, and Classic (the pre-single-line shipping composer) stops
// existing as a composer style — removed, not just defaulted away from.
// `.zeroChrome` remains fully intact and reachable via the flag. Unset or
// unrecognized value (including a stale stored `"classic"`) = `.singleLine`.
// `SessionComposerPalette.composerCard` and `SessionComposerOverlay`'s
// vertical placement branch on `ComposerStyle.current()`. The sidebar
// popover (`.anchored` presentation) keeps its own dedicated card
// (`SessionComposerPalette.popoverComposerCard`), selected by presentation,
// not by this style — see `SessionComposerPalette.cardKind(style:
// presentation:)`.

/// Which composer visual style renders. Read once per render pass via
/// `UserDefaults`, same pattern as `ComposerGhostTextField.modelBFieldStorageKey`.
enum ComposerStyle: String {
    case zeroChrome
    case singleLine

    static let storageKey = "ghostties.composerStyle"

    static func current(defaults: UserDefaults = .standard) -> ComposerStyle {
        guard let raw = defaults.string(forKey: storageKey),
              let style = ComposerStyle(rawValue: raw) else {
            return .singleLine
        }
        return style
    }
}

/// Tunes the zero-chrome wash's material by eye:
/// `defaults write com.seansmithdesign.ghostties.dev ghostties.composerZeroChromeMaterial thin`
/// Round 8 (Sean, live look): "I like this [Thin/Regular]. I would say an
/// in between of both of these thin and regular option may be optimal" —
/// `.medium` fills that gap (`.thinMaterial`, but a heavier 0.8 layer
/// opacity than `.thin`'s 0.55), and is now the Release default, replacing
/// `.regular`.
enum ComposerZeroChromeMaterial: String {
    case ultraThin
    case thin
    case medium
    case regular
    case thick

    static let storageKey = "ghostties.composerZeroChromeMaterial"

    static func current(defaults: UserDefaults = .standard) -> ComposerZeroChromeMaterial {
        guard let raw = defaults.string(forKey: storageKey),
              let material = ComposerZeroChromeMaterial(rawValue: raw) else {
            return .medium
        }
        return material
    }

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .medium: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        }
    }

    /// Round 7 (Sean, live look): "I'd like to see more of the background as
    /// well. I think your thin/ultra thin should be much more transparent."
    /// SwiftUI's materials have a fixed internal density independent of
    /// this value, so this is a layer opacity multiplied on top of the
    /// material fill — NOT a material substitution. `.regular`/`.thick`
    /// stay 1.0 (unchanged, Release default) per the brief's explicit scope.
    /// `.medium` (round 8) sits between `.thin` (0.55) and `.regular`
    /// (1.0) at 0.8.
    var layerOpacity: Double {
        switch self {
        case .ultraThin: return 0.35
        case .thin: return 0.55
        case .medium: return 0.8
        case .regular, .thick: return 1.0
        }
    }
}

// MARK: - Rest-state descriptor cycle

/// The rest-state ghost descriptor cycle (zero-chrome + single-line
/// styles): four hints cycled in FIXED order while the field is empty and
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

// MARK: - Blur wash (zero-chrome only)
//
// BLUR FEASIBILITY GATE (brief §2): the shipping composer card
// (`SessionComposerPalette.composerCard`, `.background`) already paints
// `Rectangle().fill(.regularMaterial)` in `.centered` presentation — the
// EXACT same within-window SwiftUI compositing context this wash uses,
// floating over the live terminal surface with no scrim beneath it
// (PR #132, shadow-only elevation). That is standing, shipped proof that
// an in-window `Material` DOES blur the Metal-rendered terminal beneath it
// in this app's actual window/layer setup — `TransparentHostingView` hosts
// both the terminal's `WorkspaceViewContainer` content and the composer
// overlay as sibling layers of the SAME `NSWindow`, and `Material`'s
// default `.withinWindow`-equivalent SwiftUI blending samples that
// window's own composited backing store, not merely other AppKit view
// content. No NSPanel/`NSVisualEffectView(.behindWindow)` fallback is
// needed — the within-window path is proven by existing shipped code, not
// hypothesized. `ComposerBlurCompositingTests` (snapshot) is the
// supporting regression evidence for the specific "dense text + material +
// gradient mask" composition this view adds, not the feasibility
// determination itself.
/// Fix round 2, item 5 (Sean's live look): "I was expecting the no chrome
/// to take over the full screen." Was a 560×112pt patch with a 24pt
/// feathered edge mask behind the field only — deleted, not resized. Now
/// fills whatever bounds its caller proposes (`SessionComposerOverlay`
/// gives it the full window content area, sidebar included, via
/// `.frame(maxWidth: .infinity, maxHeight: .infinity)` at the call site),
/// no shape, no mask, edge to edge. `ComposerZeroChromeMaterial` still
/// selects which material via the tuning key.
struct ComposerZeroChromeWash: View {
    var material: ComposerZeroChromeMaterial
    /// Wash opacity — animated 0→1 on summon per the Timing board; callers
    /// drive this externally so summon/commit/dismiss timing lives in one
    /// place, not this leaf view.
    var revealed: Bool

    /// DEBUG-tunable (session-7 brief, 2026-09-11); defaults to `.current()`
    /// so every pre-existing call site (production and the fixed-`.regular`
    /// calls in `ComposerBlurCompositingTests`) keeps its exact prior
    /// behavior — `.thick`, unchanged — with no call-site edits required.
    var focalBlurStyle: ComposerZeroChromeFocalBlurStyle = .current()

    /// Round 8 (Sean, live look): "Can we set these an animated shader too?
    /// a fog shader with a central focal point." Toggle for the DEBUG
    /// tuning pill's `Fog` picker (`ghostties.composerZeroChromeFog`,
    /// default on); every production call site leaves this `true`.
    var fogEnabled: Bool = true

    /// Whether Reduce Motion is on — freezes `ComposerZeroChromeFogLayer` at
    /// full, static density instead of animating the drift/summon ramp.
    var reduceMotion: Bool = false

    /// Fix round 5 (Sean's live look): "The focal point of the blur should
    /// be where the text is. Fading out slightly but still obscuring
    /// content below." The base layer below still fills edge to edge at
    /// full opacity (unchanged — nothing near the window edge is ever
    /// left un-obscured, and `ComposerBlurCompositingTests
    /// .revealedWashHasNoEdgeFeather` still asserts that at a near-corner
    /// pixel). This second, stronger layer stacks ONLY near
    /// `ComposerZeroChromeFocalBlur`'s center, masked by an elliptical
    /// falloff, so the material reads as strongest where reading would
    /// otherwise be possible and eases off toward the edges — a depth
    /// layer, not a flat frosted sheet. `.off` (`focalBlurStyle`) skips this
    /// second layer entirely, leaving only the base wash.
    ///
    /// KNOWN OFFSCREEN-HARNESS LIMITATION (round 8, flagged for Sean —
    /// not something this spike could safely paper over): compositing the
    /// fog layer's `.colorEffect` shader ANYWHERE in this view's tree —
    /// `ZStack` sibling, `.overlay`, `.drawingGroup()`-isolated or not —
    /// defeats `Material`'s live blur sampling specifically in
    /// `NSHostingView.cacheDisplay`'s OFFSCREEN snapshot path on this
    /// machine (macOS 27 host): `ComposerBlurCompositingTests
    /// .focalCenterDiffersMoreFromRawTextThanEitherCorner` measured
    /// IDENTICAL diffs at the focal center and both corners the instant
    /// `fogEnabled` defaulted true, regardless of where the shader view
    /// sat in the tree. Confirmed NOT a fixture/ordering bug: removing
    /// only the `.colorEffect` call (keeping the same `GeometryReader`/
    /// `TimelineView` structure) restored the expected margin every time.
    /// No amount of restructuring within this view fixed it, so that test
    /// pins `fogEnabled: false` explicitly and documents this exact
    /// finding at its call site — it is NOT evidence the shader is broken
    /// in the real, live-windowed app (materials and Metal shaders both
    /// fundamentally depend on live GPU compositing that `cacheDisplay`'s
    /// software snapshot doesn't fully reproduce), but it IS an open risk
    /// this spike could not verify offscreen. Flag to Sean before ship.
    var body: some View {
        ZStack {
            Rectangle()
                .fill(material.material)
                .opacity(material.layerOpacity)
            if let focalMaterial = ComposerZeroChromeFocalBlur.focalMaterial(for: focalBlurStyle) {
                Rectangle()
                    .fill(focalMaterial)
                    .mask(focalMask)
                    .opacity(focalBlurStyle.layerOpacity)
            }
            if fogEnabled {
                if #available(macOS 14, *) {
                    ComposerZeroChromeFogLayer(revealed: revealed, reduceMotion: reduceMotion)
                }
            }
        }
        .opacity(revealed ? 1 : 0)
    }

    private var focalMask: some View {
        Rectangle()
            .fill(
                EllipticalGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: ComposerZeroChromeFocalBlur.innerStopLocation),
                        .init(color: .clear, location: ComposerZeroChromeFocalBlur.outerStopLocation)
                    ],
                    center: UnitPoint(
                        x: ComposerZeroChromeFocalBlur.centerXFraction,
                        y: ComposerZeroChromeFocalBlur.centerYFraction
                    ),
                    startRadiusFraction: 0,
                    endRadiusFraction: ComposerZeroChromeFocalBlur.reachFraction
                )
            )
    }
}

/// Focal-blur strength, tunable independently of the base wash
/// (`ComposerZeroChromeMaterial`) via the composer's DEBUG-only tuning
/// control (session-7 brief, 2026-09-11). `.off` removes the focal layer
/// entirely — only geometry (`ComposerZeroChromeFocalBlur`'s
/// center/reach/stop constants) stays untouched, per that brief's explicit
/// scope. Default `.thick` matches the value this replaced
/// (`ComposerZeroChromeFocalBlur.focalMaterial`'s old hardcoded
/// `.thickMaterial`) exactly, so Release behavior is unchanged.
enum ComposerZeroChromeFocalBlurStyle: String, CaseIterable {
    case off
    case ultraThin
    case thin
    case regular
    case thick

    static let storageKey = "ghostties.composerZeroChromeFocalBlur"

    /// Round 8 (Sean, live look): default moved from `.thick` to `.regular`
    /// alongside the base material's move to `.medium`.
    static func current(defaults: UserDefaults = .standard) -> ComposerZeroChromeFocalBlurStyle {
        guard let raw = defaults.string(forKey: storageKey),
              let style = ComposerZeroChromeFocalBlurStyle(rawValue: raw) else {
            return .regular
        }
        return style
    }

    var material: Material? {
        switch self {
        case .off: return nil
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        }
    }

    /// Round 7 — same rationale as `ComposerZeroChromeMaterial.layerOpacity`,
    /// applied to the focal layer so a thin/ultraThin focal choice reads
    /// more transparent too. `.off` never renders this layer at all, so its
    /// value here is moot; `.regular`/`.thick` stay 1.0 (unchanged).
    var layerOpacity: Double {
        switch self {
        case .off: return 1.0
        case .ultraThin: return 0.35
        case .thin: return 0.55
        case .regular, .thick: return 1.0
        }
    }
}

/// Focal-blur shaping (fix round 5). Every tunable for the stronger,
/// text-centered layer lives here — nothing else in this file or
/// `SessionComposerOverlay` hardcodes a focal number — so Sean can retune
/// by eye without hunting through view code. The base layer
/// (`ComposerZeroChromeMaterial`, tuned via
/// `ghostties.composerZeroChromeMaterial`) is untouched by this enum; it
/// keeps obscuring the whole wash at full strength regardless of where the
/// focal falloff lands.
enum ComposerZeroChromeFocalBlur {
    /// Resolves the focal layer's material for a given tunable style —
    /// `nil` means "off" (no second layer at all; the base wash still
    /// obscures edge to edge, unchanged). Session-7 brief (2026-09-11):
    /// promoted from the hardcoded `.thickMaterial` constant this used to
    /// be to a DEBUG-tunable knob (`ComposerZeroChromeFocalBlurStyle`,
    /// below) — Release keeps reading the exact same default
    /// (`.thickMaterial`, via `.thick`), byte-identical behavior.
    static func focalMaterial(for style: ComposerZeroChromeFocalBlurStyle) -> Material? {
        style.material
    }

    /// Horizontal focal center, as a fraction of the wash's own width.
    /// Round 10: the composer column is centered in the overlay (see
    /// `ComposerZeroChromeTypography.columnFrame(overlayWidth:)`), so the
    /// window's true middle and the column's own middle now coincide.
    static let centerXFraction: CGFloat = 0.5

    /// Vertical focal center, as a fraction of the wash's own height.
    /// Round 10: matches `ComposerZeroChromeTypography.fieldAnchorFraction`
    /// (0.46) — the typewriter model's last-visible-line anchor — per
    /// Sean's decision.
    static let centerYFraction: CGFloat = 0.46

    /// `EllipticalGradient`'s own reach: how far, as a fraction of the
    /// wash's bounding box, the gradient extends before its stops are
    /// evaluated. 1.0 lets the falloff reach the window's corners rather
    /// than stopping halfway (SwiftUI's own default, 0.5, would clip the
    /// fade well short of the edges on a wide window).
    static let reachFraction: CGFloat = 1.0

    /// Along the gradient (0 = center, 1 = `reachFraction`'s edge), the
    /// focal material is fully opaque up to this location.
    static let innerStopLocation: Double = 0.25

    /// Beyond this location, the focal material has fully faded — only the
    /// base layer remains, so the window edges still read as obscured, not
    /// clear.
    static let outerStopLocation: Double = 0.85
}

// MARK: - Reveal motion (fix round 2)
//
// The Timing board's choreography, restored per the reviewer's exact
// mechanism: a `revealed`-shaped state driven from `SessionComposerOverlay`
// (summon) and `SessionComposerPalette` (commit/dismiss triggers, since
// those actions originate inside the palette), flowing into
// `SessionComposerPalette.zeroChromeComposerCard` as a `Binding` so both
// files can drive the SAME phase. Per-view `.animation(_, value:)` curves
// are COMPUTED from the destination phase (`zeroChromeWashAnimation(for:)`
// / `zeroChromeTextAnimation(for:)` below) rather than one blanket curve,
// which is what lets the wash and text have different durations/delays for
// the SAME phase change, and lets summon/commit/dismiss each have their
// own numbers on the SAME `revealed`-adjacent opacity property. No
// `onAppear` state reset inside the palette, no `AnyTransition` — exactly
// the two things fix round 1 tried and the reviewer ruled out.

/// All four Timing-board transitions this spike implements, as literal
/// constants (not buried in inline `Animation` calls) so
/// `ComposerZeroChromeTimingTests` can assert on the exact ms values
/// without re-deriving them from rendered output.
enum ComposerZeroChromeTiming {
    static let summonWashDuration: Double = 0.14
    /// Round 8 (Sean, live look): "a blended smoking increase to then
    /// reveal the text field input" — the fog now ramps in FIRST
    /// (`summonFogRampDuration`), and the text reveal starts only once that
    /// ramp is mostly settled, so the smoke visibly precedes the text
    /// rather than racing it. 220ms = 320ms fog ramp minus a small
    /// overlap, close enough to "ramp settles, then text" without a dead
    /// gap. Text is 180ms fade (up from 120ms, so it reads as part of the
    /// same "reveal" beat as the fog, not a separate snap) + the existing
    /// 4pt rise (`summonTextOffsetY`, unchanged).
    static let summonTextDuration: Double = 0.18
    static let summonTextDelay: Double = 0.22
    /// Fix round 4, item 1: the summon text transition is opacity 0→1 AND
    /// y 4→0 (Timing board + brief), not opacity-only — this is the
    /// pre-reveal offset the field/ghost/descriptor block starts at while
    /// `revealPhase == .hidden`, animating down to 0 on the SAME
    /// `summonTextDuration`/`summonTextDelay` curve as the opacity fade.
    static let summonTextOffsetY: CGFloat = 4

    /// Round 8: `ComposerZeroChromeFogLayer`'s density/reach ramp, 0→1
    /// ease-in, from the moment the composer reveals — see this enum's
    /// header comment on `summonTextDelay` for how it relates to the text
    /// reveal.
    static let summonFogRampDuration: Double = 0.32

    static let commitTextDuration: Double = 0.10
    static let commitWashDuration: Double = 0.16
    static let commitWashDelay: Double = 0.04
    static let commitTextOffsetY: CGFloat = -6

    static let dismissTextDuration: Double = 0.12
    static let dismissWashDuration: Double = 0.14
    static let dismissWashDelay: Double = 0.02
}

/// Zero-chrome's reveal state machine. `.hidden` is the pre-summon frame
/// (never captured by the offscreen snapshot harness, which always starts
/// callers at `.revealed` — see `SessionComposerPalette
/// .zeroChromeRevealPhaseForTesting`); `.revealed` is the settled state
/// every other style is always in; `.committing`/`.dismissing` are the two
/// exit paths with their own Timing-board numbers.
enum ComposerRevealPhase: Equatable {
    case hidden
    case revealed
    case committing
    case dismissing
}

/// Wash animation curve for a transition INTO `phase` — `nil` under Reduce
/// Motion (instant, no interpolation) or for `.hidden` (nothing to animate
/// into blankness).
func zeroChromeWashAnimation(for phase: ComposerRevealPhase, reduceMotion: Bool) -> Animation? {
    guard !reduceMotion else { return nil }
    switch phase {
    case .hidden: return nil
    case .revealed: return .easeOut(duration: ComposerZeroChromeTiming.summonWashDuration)
    case .committing: return .easeOut(duration: ComposerZeroChromeTiming.commitWashDuration)
        .delay(ComposerZeroChromeTiming.commitWashDelay)
    case .dismissing: return .easeOut(duration: ComposerZeroChromeTiming.dismissWashDuration)
        .delay(ComposerZeroChromeTiming.dismissWashDelay)
    }
}

/// Text (field + status strip) animation curve for a transition INTO
/// `phase` — same Reduce Motion / `.hidden` rules as the wash curve above.
func zeroChromeTextAnimation(for phase: ComposerRevealPhase, reduceMotion: Bool) -> Animation? {
    guard !reduceMotion else { return nil }
    switch phase {
    case .hidden: return nil
    case .revealed: return .easeOut(duration: ComposerZeroChromeTiming.summonTextDuration)
        .delay(ComposerZeroChromeTiming.summonTextDelay)
    case .committing: return .easeIn(duration: ComposerZeroChromeTiming.commitTextDuration)
    case .dismissing: return .easeIn(duration: ComposerZeroChromeTiming.dismissTextDuration)
    }
}

// MARK: - Animated fog shader (round 8)
//
// Sean, live look: "Can we set these an animated shader too? a fog shader
// with a central focal point." / "a blended smoking increase to then
// reveal the text field input." `ComposerZeroChromeFogLayer` is a
// `.colorEffect`-driven Metal shader (`Fog.metal`,
// `composerFogDensity`), full-window, densest around
// `ComposerZeroChromeFocalBlur`'s center, fading toward the edges. It is
// macOS 14+ only (`.colorEffect` needs SwiftUI 5) — `ComposerZeroChromeWash`
// guards its use with `if #available(macOS 14, *)`, so macOS 13 renders
// the exact blur-only wash it always has, per
// `decision_align-to-upstream-degrade-gracefully` (never raise the
// deployment target for a fork feature; degrade instead).

/// `ghostties.composerZeroChromeFog` on/off knob — default on. Boolean
/// storage (unlike the other zero-chrome knobs' raw-string enums) since
/// there's no third state to represent.
enum ComposerZeroChromeFogSetting {
    static let storageKey = "ghostties.composerZeroChromeFog"
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
/// excludes `ComposerStyle` itself and every zero-chrome-only key (base
/// blur, focal blur, fog, alignment) —
/// those aren't single-line keys. A single list, `resetKeys`, is the one
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

/// Full-bleed animated fog, composited over the base/focal blur layers in
/// `ComposerZeroChromeWash`. `allowsHitTesting(false)` throughout (inherited
/// from the wash's own call site) — this view claims no clicks.
@available(macOS 14, *)
struct ComposerZeroChromeFogLayer: View {
    /// Drives the summon ramp: `false` (pre-summon / commit / dismiss)
    /// pauses the `TimelineView` on its current, already-composited frame
    /// so the fade-out rides the SAME external opacity animation
    /// (`ComposerZeroChromeWash`'s `.opacity(revealed ? 1 : 0)`) as every
    /// other layer, rather than snapping to blank — no separate fade-out
    /// mechanism needed here.
    var revealed: Bool

    /// Reduce Motion floor: no ramp, no drift — a single static frame at
    /// full density/reach, rendered once. "If motion is the chrome, Reduce
    /// Motion deletes the interface" (`reference_zero-chrome-prior-art`) —
    /// the fog must never be the thing that disappears under Reduce
    /// Motion; it goes static instead.
    var reduceMotion: Bool

    /// Set once, the instant `revealed` first becomes true (summon) — the
    /// ramp's t=0 reference. This view is freshly constructed per composer
    /// session (no reuse across summons), so `nil` here always means "not
    /// yet summoned."
    @State private var rampStart: Date?

    private static let fogFunction = ShaderFunction(library: .default, name: "composerFogDensity")

    private var fogTint: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if reduceMotion {
                    fogRectangle(size: size, time: 0, ramp: 1)
                } else {
                    TimelineView(.animation(paused: !revealed)) { timeline in
                        let elapsed = rampStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                        let t = min(1, max(0, elapsed / ComposerZeroChromeTiming.summonFogRampDuration))
                        // Ease-in: slow start, fast finish, per the brief.
                        let ramp = t * t
                        fogRectangle(
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            ramp: ramp
                        )
                    }
                }
            }
        }
        .task(id: revealed) {
            guard revealed, !reduceMotion, rampStart == nil else { return }
            rampStart = Date()
        }
        .allowsHitTesting(false)
    }

    /// `ramp` drives BOTH the density and the falloff reach uniforms
    /// together, per the brief ("animate the density/radius uniform") —
    /// the fog visibly spreads outward from the focal center as it
    /// thickens, rather than fading in uniformly everywhere at once.
    private func fogRectangle(size: CGSize, time: TimeInterval, ramp: Double) -> some View {
        Rectangle()
            .fill(fogTint)
            .colorEffect(
                Shader(
                    function: Self.fogFunction,
                    arguments: [
                        .float2(Float(size.width), Float(size.height)),
                        .float(Float(time)),
                        .float2(
                            Float(ComposerZeroChromeFocalBlur.centerXFraction),
                            Float(ComposerZeroChromeFocalBlur.centerYFraction)
                        ),
                        .float(Float(ramp)),
                        .float(Float(max(ramp, 0.001)))
                    ]
                )
            )
    }
}

// MARK: - Zero-chrome type scale (fix round 2, item 8)
//
// Sean, live look: "make the no chrome text larger as well. Almost like a
// functional graphic design layout. more expressive, larger, bolder." A
// strawman he'll tune — every number lives HERE, nowhere else, so tuning
// means editing this enum only. Applies to `.zeroChrome` ONLY; `.singleLine`
// keeps DESIGN.md §3's 15/13/11pt scale untouched.
// `fieldWeight` (`.semibold`) and `fieldSize` (32pt, above DESIGN.md §3's
// 15pt ceiling for a floating surface) are BOTH deviations from DESIGN.md —
// recorded in the PR body under "DESIGN.md follow-ups", not written back
// into DESIGN.md itself (Craft's call, not this spike's).
enum ComposerZeroChromeTypography {
    static let fieldSize: CGFloat = 32
    static let fieldWeight: Font.Weight = .semibold
    static let fieldLineHeight: CGFloat = 44
    static let ghostOpacity: Double = 0.65

    static let rowSize: CGFloat = 20
    static let rowWeight: Font.Weight = .medium
    static let rowLineHeight: CGFloat = 30
    /// Distance from the field's baseline to the first row — NOT the
    /// field/rows `VStack` `spacing:`, which measures box-to-box, not
    /// baseline-to-box; approximated here as the gap between the field's
    /// line box bottom and the row block, since SwiftUI has no direct
    /// baseline-distance API across sibling views without
    /// `alignmentGuide` plumbing this spike doesn't need yet.
    static let rowTopOffset: CGFloat = 24

    static let statusStripSize: CGFloat = 15
    static let statusStripTopOffset: CGFloat = 12

    /// Fallback measure for call sites with no overlay to measure from
    /// (every snapshot test) — `zeroChromeMeasure` in
    /// `SessionComposerPalette` falls back to this when no override is
    /// given. Round 10 no longer clamps `columnFrame`'s own result into
    /// this range (that column is now `columnMaxWidth`-capped directly),
    /// but the fallback constant itself is kept, byte-identical, since
    /// existing call sites reference it.
    static let measureMin: CGFloat = 480
    static let measureMax: CGFloat = 960

    /// Round 10 (Sean's decision, typewriter centered column): the column
    /// is centered horizontally in the overlay, replacing round 8's
    /// off-center `fieldLeadingFraction` (0.38) leading-edge placement.
    static let columnMaxWidth: CGFloat = 640

    /// Clear gutter kept at BOTH the leading and trailing edge — round 8
    /// only guaranteed this at the trailing edge; the centered column
    /// keeps it symmetric.
    static let columnGutter: CGFloat = 48

    /// The column's leading x-offset and width for an overlay of
    /// `overlayWidth` points: `min(columnMaxWidth, overlayWidth -
    /// 2*columnGutter)`, centered — so a narrow overlay still keeps
    /// `columnGutter` clear on both sides rather than clipping into it,
    /// and a wide overlay never grows the column past `columnMaxWidth`.
    static func columnFrame(overlayWidth: CGFloat) -> (leadingX: CGFloat, width: CGFloat) {
        let available = max(0, overlayWidth - 2 * columnGutter)
        let width = min(columnMaxWidth, available)
        let leadingX = (overlayWidth - width) / 2
        return (leadingX, width)
    }

    /// Round 10: replaces round 8's `fieldCenterFraction` (0.5, which
    /// centered the WHOLE field block regardless of line count). The
    /// typewriter model anchors the LAST VISIBLE line's own vertical
    /// center at this fraction of overlay height — earlier lines move up
    /// as the field grows, this one line's position never does. See
    /// `fieldFrame(overlaySize:lineCount:)` below for the exact derivation.
    static let fieldAnchorFraction: CGFloat = 0.46

    /// The field's BOTTOM edge — not its center — is what's actually held
    /// fixed as more lines wrap in; this is the fixed offset added to
    /// `fieldAnchorFraction * overlayHeight` to locate that bottom edge.
    /// Chosen so a single 44pt line's own vertical center still lands
    /// exactly on `fieldAnchorFraction`: bottom == fraction*H + 22, and a
    /// 1-line field's center == bottom - fieldLineHeight/2 == fraction*H +
    /// 22 - 22 == fraction*H.
    static let fieldAnchorBottomOffset: CGFloat = 22

    /// Past this many lines the field scrolls internally instead of
    /// growing further (brief §2/§3).
    static let maxFieldLines: Int = 3

    /// Pure, unit-testable anchor math: given the overlay's own size and
    /// how many lines the field is CURRENTLY showing (clamped to
    /// `maxFieldLines`, floored at 1), returns the field block's top
    /// y-offset and total height. The bottom edge (`top + height`) is
    /// always `fieldAnchorFraction * overlaySize.height +
    /// fieldAnchorBottomOffset` regardless of `lineCount` — growth happens
    /// entirely upward, never downward into the rows below.
    static func fieldFrame(overlaySize: CGSize, lineCount: Int) -> (top: CGFloat, height: CGFloat) {
        let cappedLines = max(1, min(lineCount, maxFieldLines))
        let height = CGFloat(cappedLines) * fieldLineHeight
        let bottom = overlaySize.height * fieldAnchorFraction + fieldAnchorBottomOffset
        return (bottom - height, height)
    }
}

// MARK: - Single-line tuning (round 12, session-7 brief, 2026-09-12)
//
// Sean, live look round 11: the single-line style "isn't landing" for
// zero-chrome, so single-line is the near-term default candidate — but it
// "feels small." These three dials (field text size, row/status text size,
// container width) are Sean-tunable STRAWMEN, not DESIGN.md values — see
// this file's header MARK for why they live behind `@AppStorage` instead of
// a DESIGN.md edit. `.zeroChrome` never reads any of these keys.

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

// MARK: - Zero-chrome alignment (round 12, "one last ditch effort")
//
// Sean, round 11 debrief: the typewriter position "isn't landing" —
// centering the column's own TEXT (not just the column itself, which is
// already centered per round 10) is the one layout variant not yet tried.
// `.left` is the shipped, unchanged default; `.center` centers the typed
// text, caret, ghost suggestion, and wrapped lines together by setting
// `NSTextView.alignment` (which `firstRect(forCharacterRange:)` — the
// single source `ComposerGhostTextField.applyStyles()` already uses to
// place the ghost label in `wrapsAndGrows` mode — follows automatically,
// with NO separate ghost-position math needed for centered text).
enum ComposerZeroChromeAlignment: String, CaseIterable {
    case left
    case center

    static let storageKey = "ghostties.composerZeroChromeAlignment"

    static func current(defaults: UserDefaults = .standard) -> ComposerZeroChromeAlignment {
        guard let raw = defaults.string(forKey: storageKey),
              let alignment = ComposerZeroChromeAlignment(rawValue: raw) else {
            return .left
        }
        return alignment
    }

    var zstackAlignment: Alignment { self == .center ? .center : .leading }
    var frameAlignment: Alignment { self == .center ? .center : .leading }
    var multilineAlignment: TextAlignment { self == .center ? .center : .leading }
    var nsTextAlignment: NSTextAlignment { self == .center ? .center : .left }
}

// MARK: - DEBUG-only live tuning control (session-7 brief, 2026-09-11)
//
// Sean, live look: "a little view control just for me to kinda bounce back
// and forth within that composer... there's gonna be ways and spaces where
// I'm gonna wanna tune more." Compiled ONLY under `#if DEBUG` — every symbol
// in this section is unreachable from a Release build. Hosted by
// `SessionComposerOverlay` in the bottom-trailing corner, for all three
// composer styles.
#if DEBUG
struct ComposerDebugTuningControl: View {
    @AppStorage private var styleRaw: String
    @AppStorage private var materialRaw: String
    @AppStorage private var focalBlurRaw: String
    @AppStorage private var fogEnabled: Bool
    @AppStorage private var zeroChromeAlignmentRaw: String
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
        _styleRaw = AppStorage(wrappedValue: ComposerStyle.singleLine.rawValue, ComposerStyle.storageKey, store: defaults)
        _materialRaw = AppStorage(wrappedValue: ComposerZeroChromeMaterial.medium.rawValue, ComposerZeroChromeMaterial.storageKey, store: defaults)
        _focalBlurRaw = AppStorage(wrappedValue: ComposerZeroChromeFocalBlurStyle.regular.rawValue, ComposerZeroChromeFocalBlurStyle.storageKey, store: defaults)
        _fogEnabled = AppStorage(wrappedValue: true, ComposerZeroChromeFogSetting.storageKey, store: defaults)
        _zeroChromeAlignmentRaw = AppStorage(wrappedValue: ComposerZeroChromeAlignment.left.rawValue, ComposerZeroChromeAlignment.storageKey, store: defaults)
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

    /// Not `private` — `ComposerZeroChromeStyleTests` (`@testable import`)
    /// drives these directly, the same way it drives real keyboard/AX-free
    /// seams elsewhere in this feature, to prove "the control writes the
    /// right key" without simulating a menu click.
    var style: Binding<ComposerStyle> {
        Binding(
            get: { ComposerStyle(rawValue: styleRaw) ?? .singleLine },
            set: { styleRaw = $0.rawValue; onChange() }
        )
    }

    var material: Binding<ComposerZeroChromeMaterial> {
        Binding(
            get: { ComposerZeroChromeMaterial(rawValue: materialRaw) ?? .regular },
            set: { materialRaw = $0.rawValue; onChange() }
        )
    }

    var focalBlur: Binding<ComposerZeroChromeFocalBlurStyle> {
        Binding(
            get: { ComposerZeroChromeFocalBlurStyle(rawValue: focalBlurRaw) ?? .regular },
            set: { focalBlurRaw = $0.rawValue; onChange() }
        )
    }

    /// Round 8: `Fog` on/off knob — not `private`, same testability
    /// pattern as `style`/`material`/`focalBlur` above.
    var fog: Binding<Bool> {
        Binding(
            get: { fogEnabled },
            set: { fogEnabled = $0; onChange() }
        )
    }

    /// Round 12: zero-chrome's "one last ditch effort" alignment knob.
    var zeroChromeAlignment: Binding<ComposerZeroChromeAlignment> {
        Binding(
            get: { ComposerZeroChromeAlignment(rawValue: zeroChromeAlignmentRaw) ?? .left },
            set: { zeroChromeAlignmentRaw = $0.rawValue; onChange() }
        )
    }

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

    /// R14: not `private`, same testability pattern as `fog` above.
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
            Picker("Style", selection: style) {
                Text("Single line").tag(ComposerStyle.singleLine)
                Text("Zero chrome").tag(ComposerStyle.zeroChrome)
            }
            // Base/focal blur only mean anything for `.zeroChrome` — hidden
            // for the other two styles rather than shown disabled.
            if style.wrappedValue == .zeroChrome {
                Picker("Base blur", selection: material) {
                    Text("Ultra thin").tag(ComposerZeroChromeMaterial.ultraThin)
                    Text("Thin").tag(ComposerZeroChromeMaterial.thin)
                    Text("Medium").tag(ComposerZeroChromeMaterial.medium)
                    Text("Regular").tag(ComposerZeroChromeMaterial.regular)
                    Text("Thick").tag(ComposerZeroChromeMaterial.thick)
                }
                Picker("Focal blur", selection: focalBlur) {
                    Text("Off").tag(ComposerZeroChromeFocalBlurStyle.off)
                    Text("Ultra thin").tag(ComposerZeroChromeFocalBlurStyle.ultraThin)
                    Text("Thin").tag(ComposerZeroChromeFocalBlurStyle.thin)
                    Text("Regular").tag(ComposerZeroChromeFocalBlurStyle.regular)
                    Text("Thick").tag(ComposerZeroChromeFocalBlurStyle.thick)
                }
                Picker("Fog", selection: fog) {
                    Text("On").tag(true)
                    Text("Off").tag(false)
                }
                Picker("Alignment", selection: zeroChromeAlignment) {
                    Text("Left").tag(ComposerZeroChromeAlignment.left)
                    Text("Center").tag(ComposerZeroChromeAlignment.center)
                }
            }
            // Session-7 brief: single-line-only dials, same show/hide
            // pattern as the zero-chrome-only pickers above, reordered to
            // match `ComposerDialKitCoordinator.controls(for:)`'s single-
            // line order (Treatment moved up next to Style, glass tint next
            // to it, corner radius after width, ghost gap after Witness,
            // Reset last).
            if style.wrappedValue == .singleLine {
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
        }
        .pickerStyle(.menu)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Swallows every tap on the pill's own padding/background — a tap
        // that reached the wash beneath would dismiss the composer
        // (`SessionComposerOverlay.zeroChromeFullBleedWash`'s own dismiss
        // layer); this control must never do that.
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
    var styleRaw: String
    var materialRaw: String
    var focalBlurRaw: String
    var fogEnabled: Bool
    var alignmentRaw: String
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
        styleRaw: String,
        materialRaw: String,
        focalBlurRaw: String,
        fogEnabled: Bool,
        alignmentRaw: String,
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
        self.styleRaw = styleRaw
        self.materialRaw = materialRaw
        self.focalBlurRaw = focalBlurRaw
        self.fogEnabled = fogEnabled
        self.alignmentRaw = alignmentRaw
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
        case styleRaw, materialRaw, focalBlurRaw, fogEnabled, alignmentRaw
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
    /// Guards against re-entrant `handle(_:)` calls triggered by
    /// `state.configure(controls:)` below. `DialPanelState.values` is
    /// `@Published`, which — per Combine's documented `Published` semantics —
    /// publishes to subscribers (this sink) BEFORE its own backing storage
    /// commits the new value. So while this `handle(_:)` call is still on the
    /// stack, `state.values` reads back the value from BEFORE the user's
    /// change. `configure(controls:)` reads that stale `values` to seed its
    /// renormalization, producing a model with the OLD `styleRaw`, then
    /// assigns it back via `applyInternalValueChange` — which itself
    /// re-publishes and re-enters this sink with that stale, old-style model.
    /// Without this guard, that re-entrant call both persists the old style
    /// back to `UserDefaults` and calls `state.configure` a second time with
    /// the old style's controls, clobbering the correct new-style controls
    /// this very call is in the middle of installing.
    private var isRebuildingControls = false

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
            controls: Self.controls(for: initial.styleRaw),
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
        // See `isRebuildingControls`'s doc comment: `state.configure(...)`
        // below re-enters this method with a stale, old-style model before
        // returning. Bail out immediately so that re-entrant call neither
        // persists the stale model nor reconfigures the controls a second
        // time.
        // See `isRebuildingControls`'s doc comment: `state.configure(...)`
        // below re-enters this method with a stale, old-style model before
        // returning. Bail out immediately so that re-entrant call neither
        // persists the stale model nor reconfigures the controls a second
        // time.
        guard !isRebuildingControls else { return }
        let previous = lastKnownModel
        lastKnownModel = model
        write(from: previous, to: model)
        // Session-7 brief: rebuild the panel's own control list whenever
        // Style changes, rather than showing every knob at once or forking
        // vendored DialKit to add per-control visibility — `configure`
        // (`DialPanelState`, vendored, unmodified) already exists for
        // exactly this ("swap the control list a panel presents"), so no
        // DialKit source edit is needed.
        if model.styleRaw != previous.styleRaw {
            isRebuildingControls = true
            state.configure(controls: Self.controls(for: model.styleRaw))
            isRebuildingControls = false
        }
    }

    /// Session-7 brief §11: "Reset single-line" — the only `.action`
    /// control in this panel, routed here via `DialPanelState`'s
    /// `onAction` (see the `selfBox` doc comment in `init`). Not `private`
    /// — `DialPanelState.triggerAction`, the real trigger path, is
    /// `package`-scoped inside the vendored DialKit package and unreachable
    /// from `ComposerZeroChromeStyleTests` (a different module), so tests
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
            styleRaw: ComposerStyle.current(defaults: defaults).rawValue,
            materialRaw: ComposerZeroChromeMaterial.current(defaults: defaults).rawValue,
            focalBlurRaw: ComposerZeroChromeFocalBlurStyle.current(defaults: defaults).rawValue,
            fogEnabled: defaults.object(forKey: ComposerZeroChromeFogSetting.storageKey) as? Bool ?? true,
            alignmentRaw: ComposerZeroChromeAlignment.current(defaults: defaults).rawValue,
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
        if model.styleRaw != previous.styleRaw {
            defaults.set(model.styleRaw, forKey: ComposerStyle.storageKey)
        }
        if model.materialRaw != previous.materialRaw {
            defaults.set(model.materialRaw, forKey: ComposerZeroChromeMaterial.storageKey)
        }
        if model.focalBlurRaw != previous.focalBlurRaw {
            defaults.set(model.focalBlurRaw, forKey: ComposerZeroChromeFocalBlurStyle.storageKey)
        }
        if model.fogEnabled != previous.fogEnabled {
            defaults.set(model.fogEnabled, forKey: ComposerZeroChromeFogSetting.storageKey)
        }
        if model.alignmentRaw != previous.alignmentRaw {
            defaults.set(model.alignmentRaw, forKey: ComposerZeroChromeAlignment.storageKey)
        }
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

    private static let styleControl = DialControl<ComposerDialKitTuningModel>.select(
        "style", keyPath: \.styleRaw, label: "Style",
        options: [
            DialOption(ComposerStyle.singleLine.rawValue, label: "Single line"),
            DialOption(ComposerStyle.zeroChrome.rawValue, label: "Zero chrome")
        ]
    )

    private static let zeroChromeOnlyControls: [DialControl<ComposerDialKitTuningModel>] = [
        .select(
            "baseBlur", keyPath: \.materialRaw, label: "Base blur",
            options: [
                DialOption(ComposerZeroChromeMaterial.ultraThin.rawValue, label: "Ultra thin"),
                DialOption(ComposerZeroChromeMaterial.thin.rawValue, label: "Thin"),
                DialOption(ComposerZeroChromeMaterial.medium.rawValue, label: "Medium"),
                DialOption(ComposerZeroChromeMaterial.regular.rawValue, label: "Regular"),
                DialOption(ComposerZeroChromeMaterial.thick.rawValue, label: "Thick")
            ]
        ),
        .select(
            "focalBlur", keyPath: \.focalBlurRaw, label: "Focal blur",
            options: [
                DialOption(ComposerZeroChromeFocalBlurStyle.off.rawValue, label: "Off"),
                DialOption(ComposerZeroChromeFocalBlurStyle.ultraThin.rawValue, label: "Ultra thin"),
                DialOption(ComposerZeroChromeFocalBlurStyle.thin.rawValue, label: "Thin"),
                DialOption(ComposerZeroChromeFocalBlurStyle.regular.rawValue, label: "Regular"),
                DialOption(ComposerZeroChromeFocalBlurStyle.thick.rawValue, label: "Thick")
            ]
        ),
        .toggle("fog", keyPath: \.fogEnabled, label: "Fog"),
        .select(
            "alignment", keyPath: \.alignmentRaw, label: "Alignment",
            options: [
                DialOption(ComposerZeroChromeAlignment.left.rawValue, label: "Left"),
                DialOption(ComposerZeroChromeAlignment.center.rawValue, label: "Center")
            ]
        )
    ]

    /// Session-7 brief §"Strawman to build": single-line's own dial order —
    /// Treatment, Glass tint, Width, Corner radius, Field size, Row size,
    /// Shadow (preset + 3 dials), Witness, Ghost size, Ghost gap, Float
    /// vertical, Float horizontal, Float period, Ghost opacity, Beat speed,
    /// Reset — everything AFTER `styleControl`, which every style shows.
    private static let singleLineOnlyControls: [DialControl<ComposerDialKitTuningModel>] = [
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

    /// Session-7 brief: the single place that decides which knobs the panel
    /// shows for a given Style — Zero chrome gets Style + the 4 zero-chrome
    /// dials, Single line gets Style + the 19 single-line dials (round 15
    /// added the Float horizontal dial to round 14's 18, which added 5
    /// Witness dials to round 13's 13). `ComposerDialKitCoordinator.handle`
    /// calls `state.configure(controls:)` (vendored, unmodified
    /// `DialPanelState` API) with this function's result whenever `styleRaw`
    /// changes — that's the whole "conditional visibility" mechanism; no
    /// DialKit source is forked to add a per-control `isHidden`.
    static func controls(for styleRaw: String) -> [DialControl<ComposerDialKitTuningModel>] {
        var items: [DialControl<ComposerDialKitTuningModel>] = [styleControl]
        switch ComposerStyle(rawValue: styleRaw) ?? .singleLine {
        case .zeroChrome:
            items.append(contentsOf: zeroChromeOnlyControls)
        case .singleLine:
            items.append(contentsOf: singleLineOnlyControls)
        }
        return items
    }
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
