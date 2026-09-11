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
/// Default `.regular` matches the shipping card's own `.regularMaterial`
/// (`SessionComposerPalette.composerCard`'s `.background`), which is the
/// direct proof the blur-feasibility gate rests on — see this file's header
/// comment on `ComposerZeroChromeWash` for the full argument.
enum ComposerZeroChromeMaterial: String {
    case ultraThin
    case thin
    case regular
    case thick

    static let storageKey = "ghostties.composerZeroChromeMaterial"

    static func current(defaults: UserDefaults = .standard) -> ComposerZeroChromeMaterial {
        guard let raw = defaults.string(forKey: storageKey),
              let material = ComposerZeroChromeMaterial(rawValue: raw) else {
            return .regular
        }
        return material
    }

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
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
    var layerOpacity: Double {
        switch self {
        case .ultraThin: return 0.35
        case .thin: return 0.55
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

    static func current(defaults: UserDefaults = .standard) -> ComposerZeroChromeFocalBlurStyle {
        guard let raw = defaults.string(forKey: storageKey),
              let style = ComposerZeroChromeFocalBlurStyle(rawValue: raw) else {
            return .thick
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

    /// Horizontal focal center, as a fraction of the wash's own width —
    /// 0.5 because the composer text block is horizontally centered in the
    /// window (PR #132 removed the sidebar-width sensitive offset).
    static let centerXFraction: CGFloat = 0.5

    /// Vertical focal center, as a fraction of the wash's own height.
    /// `ComposerZeroChromeTypography.fieldTopFraction` (0.42 as of round 7)
    /// is where the FIELD starts; the rows block extends below it, so the
    /// text block's visual center sits a bit lower — approximated here
    /// rather than computed from the live row count (0–3 rows), same class
    /// of approximation as `ComposerZeroChromeTypography.rowTopOffset`'s
    /// own comment. Raised from 0.40 to 0.50 alongside `fieldTopFraction`
    /// so the focal blur follows the "center stage" text block.
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
    static let summonTextDuration: Double = 0.12
    static let summonTextDelay: Double = 0.04
    /// Fix round 4, item 1: the summon text transition is opacity 0→1 AND
    /// y 4→0 (Timing board + brief), not opacity-only — this is the
    /// pre-reveal offset the field/ghost/descriptor block starts at while
    /// `revealPhase == .hidden`, animating down to 0 on the SAME
    /// `summonTextDuration`/`summonTextDelay` curve as the opacity fade.
    static let summonTextOffsetY: CGFloat = 4

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

    /// Measure: 75% of the overlay width, clamped 480–960pt (480pt was the
    /// WHOLE measure at the old 15pt scale — too narrow, ~28 characters, at
    /// 32pt). `SessionComposerOverlay` computes the clamped value from its
    /// own `GeometryReader` and passes it in; call sites with no overlay
    /// (every snapshot test) fall back to `measureMin`.
    static let measureFraction: CGFloat = 0.75
    static let measureMin: CGFloat = 480
    static let measureMax: CGFloat = 960

    /// Field top, as a fraction of overlay height — 42% (round 7, Sean's
    /// live look: "center stage"), not the shared 38%
    /// `SessionComposerOverlay` still uses for its own vertical-placement
    /// constant. Was 32% through round 6; raised to sit the text block at
    /// the window's optical center rather than the upper third.
    static let fieldTopFraction: CGFloat = 0.42
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
        _materialRaw = AppStorage(wrappedValue: ComposerZeroChromeMaterial.regular.rawValue, ComposerZeroChromeMaterial.storageKey, store: defaults)
        _focalBlurRaw = AppStorage(wrappedValue: ComposerZeroChromeFocalBlurStyle.thick.rawValue, ComposerZeroChromeFocalBlurStyle.storageKey, store: defaults)
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
            get: { ComposerZeroChromeFocalBlurStyle(rawValue: focalBlurRaw) ?? .thick },
            set: { focalBlurRaw = $0.rawValue; onChange() }
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
