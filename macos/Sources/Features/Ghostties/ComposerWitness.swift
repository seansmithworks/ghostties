import SwiftUI
import GhosttiesCore

/// R14 "Witness" — one small `ComposerWitnessGhost` standing on the
/// single-line composer card, reacting only to finished events (open,
/// project resolve, Tab accept, unknown branch, launch). Composer-only
/// trial; does not touch `GhostCharacter`'s app-wide ghost system.
enum ComposerWitness {
    /// `GhostCharacter` (24 app ghosts, Pac-Man-shaped/named) -> the 9-ghost
    /// website cast. Exhaustive switch, no `default:` — adding a 25th app
    /// ghost forces a decision here instead of silently falling through.
    /// Buckets (plan §3, colour-confirmed + same-name + rest), no bucket >3:
    ///   flicker: blinky, flicker, jinx (3)
    ///   shade:   pinky, shade (2)
    ///   murk:    inky, gloom, dusk (3)
    ///   haze:    clyde, hex (2)
    ///   specter: specter, wraith, banshee (3)
    ///   wisp:    wisp, drift, mist (3)
    ///   phantom: phantom, haunt, polter (3)
    ///   ember:   ember, spike, fang (3)
    ///   chill:   chill, howl (2)
    static func witnessGhost(for character: GhostCharacter) -> ComposerWitnessGhost {
        switch character {
        case .blinky, .flicker, .jinx: return .flicker
        case .pinky, .shade: return .shade
        case .inky, .gloom, .dusk: return .murk
        case .clyde, .hex: return .haze
        case .specter, .wraith, .banshee: return .specter
        case .wisp, .drift, .mist: return .wisp
        case .phantom, .haunt, .polter: return .phantom
        case .ember, .spike, .fang: return .ember
        case .chill, .howl: return .chill
        }
    }

    /// The Witness's on-screen identity: no stored ghost (or no project at
    /// all, e.g. the composer's empty open state) is a placeholder, never a
    /// random pick — Sean's fork #2, a grey specter silhouette with the
    /// eyes cut out.
    enum Identity: Equatable {
        case placeholder
        case ghost(ComposerWitnessGhost)
    }

    /// Sean's fork #1: the ghost tracks the TYPED project (`commandProject`
    /// — the live command-grammar resolution, `SessionComposerPalette.swift`
    /// `commandProject`), falling back to whatever project the composer was
    /// opened locked/prefilled to (so a locked "+ New Session" composer
    /// shows its ghost immediately, before anything is typed) — plan §2
    /// "Project resolves" / "Open" beats. `.open` (no project at all) and a
    /// resolved project with no stored `ghostCharacter` both collapse to
    /// `.placeholder`.
    static func identity(
        commandProject: Project?,
        binding: SessionComposerRequest.ProjectBinding
    ) -> Identity {
        let project = commandProject ?? boundProject(binding)
        guard let ghost = project?.ghostCharacter else { return .placeholder }
        return .ghost(witnessGhost(for: ghost))
    }

    private static func boundProject(_ binding: SessionComposerRequest.ProjectBinding) -> Project? {
        switch binding {
        case .locked(let project), .prefilled(let project): return project
        case .open: return nil
        }
    }

    // MARK: - Beats (plan §2 event hooks)

    /// A finished-event the Witness reacts to. `.idle` is the resting
    /// state between beats, never sent explicitly.
    enum BeatKind: Equatable {
        case idle
        case open
        case resolve
        case tabAccept
        case unknownBranch
        case launch
    }

    /// `seq` makes every send distinct even when `kind` repeats back to
    /// back (e.g. two Tab accepts in a row) — `ComposerWitnessView` re-arms
    /// its pose clock on `seq` change, not `kind` change alone.
    struct Beat: Equatable {
        var kind: BeatKind
        var seq: Int

        static let idle = Beat(kind: .idle, seq: 0)

        func next(_ kind: BeatKind) -> Beat {
            Beat(kind: kind, seq: seq + 1)
        }
    }
}

/// Pure pose math — no view state, no clock ownership. `elapsed` is seconds
/// since the beat that produced `beat` was armed.
enum ComposerWitnessMotion {
    struct Pose: Equatable {
        var offsetY: CGFloat
        var offsetX: CGFloat
        var opacity: Double
        var eyesOpen: Bool
    }

    /// Idle bob: Sean's fork #3, stepped 1pt at 8Hz (a 125ms step, not a
    /// continuous sine) — matches `TimelineView(.animation(minimumInterval:
    /// 0.125, ...))`'s own cadence in `ComposerWitnessView` so the bob never
    /// looks smoother than the clock actually redraws.
    private static func idleBobOffsetY(elapsed: TimeInterval) -> CGFloat {
        let step = Int(elapsed / 0.125)
        return step.isMultiple(of: 2) ? 0 : -1
    }

    /// Blink: 130ms closed, roughly every 4s — driven off elapsed time
    /// modulo a fixed period so it free-runs independent of beats.
    private static func isBlinking(elapsed: TimeInterval) -> Bool {
        let period: TimeInterval = 4.0
        let phase = elapsed.truncatingRemainder(dividingBy: period)
        return phase < 0.13
    }

    /// `beat`/`beatElapsed` describe the most recent finished-event beat;
    /// `clockElapsed` is free-running time since the view mounted, driving
    /// idle bob/blink so they never restart on a beat that doesn't touch
    /// them (e.g. `.resolve` doesn't reset the blink phase).
    static func pose(
        beat: ComposerWitness.BeatKind,
        beatElapsed: TimeInterval,
        clockElapsed: TimeInterval,
        reduceMotion: Bool
    ) -> Pose {
        let restingY = idleBobOffsetY(elapsed: clockElapsed)
        let blinking = isBlinking(elapsed: clockElapsed)

        if reduceMotion {
            // Plan §4: Reduce Motion holds the resting pose for every beat,
            // instant swap — no bob, no blink, no shake, no lift.
            return Pose(offsetY: 0, offsetX: 0, opacity: 1, eyesOpen: true)
        }

        switch beat {
        case .idle, .resolve:
            // `.resolve` (project swap) is an instant identity swap, not an
            // animated beat of its own — the idle bob/blink continue
            // uninterrupted underneath it.
            return Pose(offsetY: restingY, offsetX: 0, opacity: 1, eyesOpen: !blinking)

        case .open:
            // A small settle-in: starts lifted, eases to rest over 200ms.
            let t = min(beatElapsed / 0.2, 1)
            let offsetY = restingY + (1 - t) * -6
            return Pose(offsetY: offsetY, offsetX: 0, opacity: 1, eyesOpen: !blinking)

        case .tabAccept:
            // Hop: peaks at -10, back to 0 (relative to resting), within
            // 300ms.
            let duration = 0.3
            let t = min(beatElapsed / duration, 1)
            let hop = -10 * sin(t * .pi)
            return Pose(offsetY: restingY + hop, offsetX: 0, opacity: 1, eyesOpen: !blinking)

        case .unknownBranch:
            // Shake: within ±4pt inside 700ms, 0 after.
            let duration = 0.7
            guard beatElapsed < duration else {
                return Pose(offsetY: restingY, offsetX: 0, opacity: 1, eyesOpen: !blinking)
            }
            let cycles = 3.0
            let decay = 1 - (beatElapsed / duration)
            let shakeX = 4 * decay * sin(beatElapsed * cycles * 2 * .pi / duration)
            return Pose(offsetY: restingY, offsetX: shakeX, opacity: 1, eyesOpen: !blinking)

        case .launch:
            // Lift and fade: -40 offset, opacity 0, both reached at 200ms.
            let duration = 0.2
            let t = min(beatElapsed / duration, 1)
            let offsetY = restingY + t * -40
            let opacity = 1 - t
            return Pose(offsetY: offsetY, offsetX: 0, opacity: opacity, eyesOpen: true)
        }
    }
}

/// The 24×24 sprite view. `TimelineView` wraps ONLY this sprite (never the
/// palette around it — the palette re-parses `query` on every redraw, plan
/// §4), so the 8Hz idle-bob clock never forces the whole composer to
/// re-render.
struct ComposerWitnessView: View {
    let identity: ComposerWitness.Identity
    /// Written by the palette on `.open`/`.tabAccept`/`.unknownBranch`/
    /// `.launch`. `.resolve` is detected internally, below, from `identity`
    /// changing — the Witness view is the only thing that knows an
    /// identity change already happened this frame.
    let beatTrigger: ComposerWitness.Beat
    let reduceMotion: Bool

    @State private var currentBeat: ComposerWitness.Beat = .idle
    @State private var beatStartedAt: Date = .now
    @State private var mountedAt: Date = .now

    private let frameSize: CGFloat = 24

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125, paused: reduceMotion)) { context in
            let beatElapsed = context.date.timeIntervalSince(beatStartedAt)
            let clockElapsed = context.date.timeIntervalSince(mountedAt)
            let pose = ComposerWitnessMotion.pose(
                beat: currentBeat.kind,
                beatElapsed: beatElapsed,
                clockElapsed: clockElapsed,
                reduceMotion: reduceMotion
            )
            sprite
                .offset(x: pose.offsetX, y: pose.offsetY)
                .opacity(pose.opacity)
        }
        .frame(width: frameSize, height: frameSize)
        .onChange(of: beatTrigger) { newValue in
            currentBeat = newValue
            beatStartedAt = .now
        }
        .onChange(of: identity) { _ in
            currentBeat = currentBeat.next(.resolve)
            beatStartedAt = .now
        }
    }

    private var pixels: [String] {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.pixels
        case .ghost(let ghost): return ghost.pixels
        }
    }

    private var bodyColor: Color {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.color
        case .ghost(let ghost): return Color(hex: ghost.colorHex)
        }
    }

    @ViewBuilder
    private var sprite: some View {
        // Reduce Motion: instant swap, no blink — `eyesOpen` from `pose` is
        // always `true` there (see `ComposerWitnessMotion.pose`).
        Canvas { context, size in
            let rows = pixels.count
            let cols = pixels.first?.count ?? 0
            guard rows > 0, cols > 0 else { return }
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)
            for (row, line) in pixels.enumerated() {
                for (col, cell) in line.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(col) * cellW,
                        y: CGFloat(row) * cellH,
                        width: cellW.rounded(.up),
                        height: cellH.rounded(.up)
                    )
                    switch cell {
                    case "X":
                        context.fill(Path(rect), with: .color(bodyColor))
                    case "e":
                        let eyeColor = eyesOpenColor
                        context.fill(Path(rect), with: .color(eyeColor))
                    case "l":
                        context.fill(Path(rect), with: .color(Color(hex: ComposerWitnessGhost.litColorHex)))
                    default:
                        continue
                    }
                }
            }
        }
    }

    /// Blinking paints the eye layer body colour (closes the eye), per
    /// plan §4 — the pose's `eyesOpen` flag decides which color the `e`
    /// cells get this frame.
    private var eyesOpenColor: Color {
        // Re-derive from the same clock the sprite's `Canvas` closure
        // already redraws on; `Canvas` has no `context.date`, so this reads
        // the identical `TimelineView` cadence via `Date()` at draw time —
        // acceptable here because the frame that calls this IS the frame
        // `TimelineView` just requested.
        Color(hex: ComposerWitnessGhost.eyeColorHex)
    }
}

/// Sean's fork #2: no stored ghost -> a grey specter silhouette with the
/// eyes cut out (not colored in, not a random ghost).
enum ComposerWitnessPlaceholder {
    static let color = Color(nsColor: .tertiaryLabelColor)
    /// `.specter`'s silhouette with every `e`/`l` cell blanked to `.` — eyes
    /// cut out, no highlight.
    static let pixels: [String] = ComposerWitnessGhost.specter.pixels.map { row in
        String(row.map { $0 == "e" || $0 == "l" ? "." : $0 })
    }
}

private extension Color {
    /// Minimal `#rrggbb` parser — the cast's colors are all opaque 6-digit
    /// hex, verbatim from `ghost-field.js`; no alpha, no shorthand needed.
    init(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
