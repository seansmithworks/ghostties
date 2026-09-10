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

    var body: some View {
        let shownIndex = reduceMotion ? 0 : index
        // Fix round 2 (found chasing item 3/8's typing snapshots, NOT one
        // of the coordinator's numbered items — a real regression the new
        // snapshots surfaced): a `.transition()` here (tried first, for
        // item-to-item crossfading) applies to ANY removal of this view,
        // including the query-non-empty removal — the instant the user
        // types, this whole block should vanish immediately (brief §1:
        // "stops the instant the field has any text"), but a `.transition`
        // fades it out over 180ms instead, and a single-frame offscreen
        // capture mid-fade (or the real app's first ~180ms of typing)
        // showed the descriptor still fully opaque, overlapping the
        // candidate rows underneath it. `.animation(nil, value:
        // query.isEmpty)` was tried next and did NOT suppress it — a
        // `.transition`'s own embedded `.animation(...)` is independent of
        // the ambient `.animation(_, value:)` modifier. Landed on no
        // `.transition` at all: item-to-item cycling now snaps instead of
        // crossfading (a real, accepted motion regression, flagged in the
        // PR) rather than risk a second wrong mechanism this late.
        Group {
            if query.isEmpty, descriptors.indices.contains(shownIndex) {
                Text(descriptors[shownIndex])
                    .id(shownIndex)
            }
        }
        .foregroundStyle(Color(nsColor: .labelColor).opacity(opacity))
        .task(id: reduceMotion) {
            index = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.holdNanoseconds)
                if Task.isCancelled { return }
                guard query.isEmpty else { continue }
                index = (index + 1) % descriptors.count
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

    var body: some View {
        Rectangle()
            .fill(material.material)
            .opacity(revealed ? 1 : 0)
    }
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

    /// Field top, as a fraction of overlay height — 32%, not the shared
    /// 38% `SessionComposerOverlay` still uses for its own vertical-
    /// placement constant, to leave room for the taller block.
    static let fieldTopFraction: CGFloat = 0.32
}
