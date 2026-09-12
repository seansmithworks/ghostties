import SwiftUI
import AppKit

// MARK: - Composer style flag (spike, beta.25 hold)
//
// Zero-chrome + single-line composer redesign, behind `ghostties.composerStyle`.
// Unset or unrecognized value = `.classic`, the shipping composer, with ZERO
// visual or behavioral change on that path — every classic render call site
// stays exactly as it was before this file existed; only `SessionComposerPalette
// .composerCard` and `SessionComposerOverlay`'s vertical placement branch on
// `ComposerStyle.current()`.

/// Which composer visual style renders. Read once per render pass via
/// `UserDefaults`, same pattern as `ComposerGhostTextField.modelBFieldStorageKey`.
enum ComposerStyle: String {
    case classic
    case zeroChrome
    case singleLine

    static let storageKey = "ghostties.composerStyle"

    static func current(defaults: UserDefaults = .standard) -> ComposerStyle {
        guard let raw = defaults.string(forKey: storageKey),
              let style = ComposerStyle(rawValue: raw) else {
            return .classic
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
    /// Round 8: the composer column itself moved off-center (leading edge
    /// at `ComposerZeroChromeTypography.fieldLeadingFraction`, 0.38), but
    /// Sean's brief keeps the focal blur's own center pinned at the
    /// window's true middle regardless.
    static let centerXFraction: CGFloat = 0.5

    /// Vertical focal center, as a fraction of the wash's own height.
    /// Round 8: the FIELD line's vertical center now sits at exactly
    /// `ComposerZeroChromeTypography.fieldCenterFraction` (0.5) — this
    /// stays 0.50 to match, per Sean's brief ("Keep the focal center at
    /// x 0.5, y 0.5").
    static let centerYFraction: CGFloat = 0.50

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
// means editing this enum only. Applies to `.zeroChrome` ONLY;
// `.singleLine`/`.classic` keep DESIGN.md §3's 15/13/11pt scale untouched.
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

    /// Measure floor/ceiling in points (480pt was the WHOLE measure at the
    /// old 15pt scale — too narrow, ~28 characters, at 32pt; 960pt caps it
    /// from reading as a full-width paragraph on a wide window). Round 8
    /// replaced the old centered 75%-of-width measure with
    /// `columnFrame(overlayWidth:)` below, which still clamps into this
    /// same 480–960 range. Call sites with no overlay (every snapshot test)
    /// fall back to `measureMin`.
    static let measureMin: CGFloat = 480
    static let measureMax: CGFloat = 960

    /// Round 8 (Sean, live look): "I'd like the composer text position to
    /// be centered in the screen but left aligned still" — the column's
    /// leading edge sits just left of the window's horizontal middle,
    /// extending rightward (long prompts grow right, not into both
    /// margins). Replaces the centered 75%-of-width measure.
    static let fieldLeadingFraction: CGFloat = 0.38

    /// Clear gutter kept at the overlay's trailing (right) edge once the
    /// column reaches `measureMax`.
    static let columnTrailingGutter: CGFloat = 48

    /// Fraction of overlay height where the FIELD LINE's own vertical
    /// center sits — round 8 carries "center stage" further than round 7's
    /// block-top placement: the field's optical center, not just the top
    /// of the field+rows block, now sits at the window's true middle. Rows
    /// hang below it, unaffected by this constant.
    static let fieldCenterFraction: CGFloat = 0.5

    /// The column's leading x-offset and width for an overlay of
    /// `overlayWidth` points: leading edge at `fieldLeadingFraction`,
    /// extending to `measureMax` while keeping `columnTrailingGutter` clear
    /// at the right edge. If that leaves less than `measureMin`, the
    /// minimum wins and the leading edge moves left (still keeping the
    /// trailing gutter) rather than shrinking the column further.
    static func columnFrame(overlayWidth: CGFloat) -> (leadingX: CGFloat, width: CGFloat) {
        let proposedLeading = overlayWidth * fieldLeadingFraction
        let available = overlayWidth - proposedLeading - columnTrailingGutter
        guard available >= measureMin else {
            let leadingX = max(0, overlayWidth - columnTrailingGutter - measureMin)
            return (leadingX, measureMin)
        }
        return (proposedLeading, min(available, measureMax))
    }
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

    /// Called after any knob write, so the caller can return keyboard focus
    /// to the composer's search field — this control must never leave focus
    /// stranded on itself.
    var onChange: () -> Void

    /// `defaults` mirrors every other test seam in this feature
    /// (`styleOverrideForTesting`, etc.): production leaves it `.standard`;
    /// a test injects an isolated suite so it never races other parallel
    /// Swift Testing processes reading/writing the same keys.
    init(defaults: UserDefaults = .standard, onChange: @escaping () -> Void = {}) {
        _styleRaw = AppStorage(wrappedValue: ComposerStyle.classic.rawValue, ComposerStyle.storageKey, store: defaults)
        _materialRaw = AppStorage(wrappedValue: ComposerZeroChromeMaterial.medium.rawValue, ComposerZeroChromeMaterial.storageKey, store: defaults)
        _focalBlurRaw = AppStorage(wrappedValue: ComposerZeroChromeFocalBlurStyle.regular.rawValue, ComposerZeroChromeFocalBlurStyle.storageKey, store: defaults)
        _fogEnabled = AppStorage(wrappedValue: true, ComposerZeroChromeFogSetting.storageKey, store: defaults)
        self.onChange = onChange
    }

    /// Not `private` — `ComposerZeroChromeStyleTests` (`@testable import`)
    /// drives these directly, the same way it drives real keyboard/AX-free
    /// seams elsewhere in this feature, to prove "the control writes the
    /// right key" without simulating a menu click.
    var style: Binding<ComposerStyle> {
        Binding(
            get: { ComposerStyle(rawValue: styleRaw) ?? .classic },
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Style", selection: style) {
                Text("Classic").tag(ComposerStyle.classic)
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
#endif
