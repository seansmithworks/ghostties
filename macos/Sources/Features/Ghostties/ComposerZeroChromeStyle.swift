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
    private static let crossfadeDuration = 0.18

    var body: some View {
        let shownIndex = reduceMotion ? 0 : index
        Group {
            if query.isEmpty, descriptors.indices.contains(shownIndex) {
                Text(descriptors[shownIndex])
                    .id(shownIndex)
                    .transition(.opacity.animation(.easeInOut(duration: Self.crossfadeDuration)))
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
struct ComposerZeroChromeWash: View {
    var material: ComposerZeroChromeMaterial
    /// Wash opacity — animated 0→1 on summon per the Timing board; callers
    /// drive this externally so summon/commit/dismiss timing lives in one
    /// place (the card, not this leaf view).
    var revealed: Bool

    private static let size = CGSize(width: 560, height: 112)
    private static let featherDistance: CGFloat = 24

    var body: some View {
        Rectangle()
            .fill(material.material)
            .frame(width: Self.size.width, height: Self.size.height)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: Self.featherDistance / Self.size.width),
                        .init(color: .black, location: 1 - Self.featherDistance / Self.size.width),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: Self.featherDistance / Self.size.height),
                            .init(color: .black, location: 1 - Self.featherDistance / Self.size.height),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .opacity(revealed ? 1 : 0)
    }
}
