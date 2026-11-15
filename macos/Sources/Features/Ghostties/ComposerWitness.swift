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
    /// state between beats, never sent explicitly. An identity change is not
    /// a beat: the view blends the old ghost into the new one on its own
    /// (`ComposerWitnessTransition`), and the flip is the ghost's own habit
    /// (`ComposerWitnessFrames.selfFlipElapsedMs`), tied to neither.
    enum BeatKind: Equatable {
        case idle
        case open
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

/// Pure transition logic for `ComposerWitnessView` — the ENTIRE decision
/// point for what a combined `identity`/`beatTrigger` update does, so the
/// view is a thin shell (one `onChange`, one call here) and the logic is
/// directly testable without constructing a View.
///
/// An identity change (the typed project changed) blends: the ghost on
/// screen dithers into the new one over `buildResolveFrames`, each cell
/// keeping the colour it had. It never flips. A second change mid-blend
/// starts its own blend from EXACTLY what is on screen at that instant —
/// chars, cell offset and per-cell colour — never from a named identity's
/// resting grid.
///
/// R3 review fix: `identity` and `beatTrigger` can change in the SAME
/// SwiftUI transaction (launch: `SessionComposerStore.precommit` clears
/// `searchText`, changing `identity`, then `SessionComposerPalette.commit`
/// arms `.launch`, both before the next render). `ComposerWitnessView`
/// delivers both as ONE combined value to ONE `onChange`, and `next(...)`
/// resolves them here in a fixed order: a newly-arming `.launch` always wins
/// outright, ignores any bundled identity change, and dissolves from
/// `onScreen`. Once locked, `identity` changes are a no-op until a later
/// non-launch beat arrives.
///
/// Sean's decision (2026-09-13), "always have transitions": a Tab accept or
/// unknown branch that arrives bundled with an identity change plays the
/// blend first, then the beat's own frames on the new identity, as one
/// sequence.
///
/// The open beat is its own transition (the drop): an identity change
/// bundled with it swaps instantly.
enum ComposerWitnessTransition {
    struct ViewState: Equatable {
        /// The last beat the palette sent. An identity change never
        /// rewrites it, so a later update can tell a fresh beat from one
        /// already played.
        var currentBeat: ComposerWitness.Beat
        var displayedIdentity: ComposerWitness.Identity
        /// The identity a blend in flight is leaving. `nil` outside one.
        var previousIdentity: ComposerWitness.Identity?
        var beatFrames: [ComposerWitnessFrames.WitnessFrame]
        /// Bumped whenever `beatFrames` is rebuilt; the view then restarts
        /// its frame clock.
        var framesSeq: Int
        /// Per-cell "from" colours for the blend or dissolve now playing —
        /// may mix more than one prior ghost's colour when a blend
        /// interrupts another. `nil` outside one.
        var resolveFromColors: [[Color]]?
        var isLaunchLocked: Bool

        init(
            currentBeat: ComposerWitness.Beat,
            displayedIdentity: ComposerWitness.Identity,
            previousIdentity: ComposerWitness.Identity? = nil,
            beatFrames: [ComposerWitnessFrames.WitnessFrame] = [],
            framesSeq: Int = 0,
            resolveFromColors: [[Color]]? = nil,
            isLaunchLocked: Bool = false
        ) {
            self.currentBeat = currentBeat
            self.displayedIdentity = displayedIdentity
            self.previousIdentity = previousIdentity
            self.beatFrames = beatFrames
            self.framesSeq = framesSeq
            self.resolveFromColors = resolveFromColors
            self.isLaunchLocked = isLaunchLocked
        }
    }

    typealias OnScreen = (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?)

    /// `onScreen` MUST be captured (via `ComposerWitnessFrames.displayGrid`)
    /// from `state` BEFORE this call, at the instant `newIdentity`/`newBeat`
    /// arrived — exactly what was on screen a moment ago (chars, offset,
    /// per-cell colour provenance). Every blend or dissolve this produces
    /// starts from that capture.
    static func next(
        state: ViewState,
        newIdentity: ComposerWitness.Identity,
        newBeat: ComposerWitness.Beat,
        onScreen: OnScreen,
        pixelsFor: (ComposerWitness.Identity) -> [String],
        colorFor: (ComposerWitness.Identity) -> Color,
        reduceMotion: Bool,
        seed: Int32
    ) -> ViewState {
        let beatChanged = newBeat != state.currentBeat
        let identityChanged = newIdentity != state.displayedIdentity

        // Launch always wins outright over any identity change bundled into
        // the same update: it dissolves exactly what is on screen, never a
        // ghost rebuilt from the identity that was about to swap in.
        if beatChanged, newBeat.kind == .launch {
            var launched = state
            launched.currentBeat = newBeat
            launched.beatFrames = launchDissolveFrames(
                from: onScreen.grid,
                startCellOffsetY: onScreen.cellOffsetY,
                seed: seed
            )
            launched.framesSeq += 1
            launched.resolveFromColors = onScreenColors(
                onScreen: onScreen,
                current: colorFor(state.displayedIdentity),
                prior: state.previousIdentity.map(colorFor)
            )
            launched.isLaunchLocked = true
            return launched
        }

        // Launch is terminal: locked, and no fresh beat arrived this
        // update to unlock it — ignore the identity change outright. And
        // an update that changes nothing is a no-op.
        if !beatChanged, state.isLaunchLocked || !identityChanged {
            return state
        }

        var updated = state
        updated.isLaunchLocked = false
        updated.currentBeat = newBeat
        let opens = beatChanged && newBeat.kind == .open
        // The blend plays only when there is motion to give it and the open
        // drop isn't already the transition.
        let blends = identityChanged && !reduceMotion && !opens

        var frames: [ComposerWitnessFrames.WitnessFrame] = []
        if identityChanged {
            updated.displayedIdentity = newIdentity
            if blends {
                let currentColor = colorFor(state.displayedIdentity)
                let priorColor = state.previousIdentity.map(colorFor) ?? currentColor
                updated.resolveFromColors = onScreenColors(onScreen: onScreen, current: currentColor, prior: priorColor)
                frames = ComposerWitnessFrames.buildResolveFrames(
                    gridA: onScreen.grid,
                    gridB: pixelsFor(newIdentity),
                    seed: seed
                )
                blendOffset(&frames, from: onScreen.cellOffsetY)
                updated.previousIdentity = state.displayedIdentity
            } else {
                updated.previousIdentity = nil
                updated.resolveFromColors = nil
            }
        }

        if beatChanged {
            // A fresh, explicit beat (`.open`/`.tabAccept`/`.unknownBranch`
            // — `.launch` already returned above), built on whatever
            // identity is displayed after the identity update above.
            let hopFrames = framesFor(kind: newBeat.kind, targetGrid: pixelsFor(updated.displayedIdentity))
            if blends {
                // "Always have transitions": the blend plays first, then
                // the beat's own frames on the new, settled grid.
                frames += hopFrames
            } else {
                frames = hopFrames
                updated.previousIdentity = nil
                updated.resolveFromColors = nil
            }
        }

        updated.beatFrames = frames
        updated.framesSeq += 1
        return updated
    }

    /// The open beat has no grid frames: its drop is a transform
    /// (`ComposerWitnessFrames.openTransform`) over the idle loop.
    private static func framesFor(
        kind: ComposerWitness.BeatKind,
        targetGrid: [String]
    ) -> [ComposerWitnessFrames.WitnessFrame] {
        switch kind {
        case .idle, .open, .launch: return []
        case .tabAccept: return ComposerWitnessFrames.buildTabFrames(grid: targetGrid)
        case .unknownBranch: return ComposerWitnessFrames.buildErrorFrames(grid: targetGrid)
        }
    }

    /// A blend always plays at cellOffsetY 0 by construction — if the
    /// interrupted beat had shifted the sprite (e.g. mid tab-accept hop),
    /// blend that offset back to 0 across the new frames instead of
    /// snapping to 0 on frame one.
    private static func blendOffset(_ frames: inout [ComposerWitnessFrames.WitnessFrame], from start: Int) {
        guard start != 0, !frames.isEmpty else { return }
        let n = frames.count
        for i in frames.indices {
            let progress = Double(i + 1) / Double(n)
            frames[i].cellOffsetY = Int((Double(start) * (1 - progress)).rounded())
        }
    }

    /// A launch dissolve from an ARBITRARY on-screen grid (not necessarily
    /// a named identity's resting grid — could be mid-blend) straight to
    /// empty. Deliberately skips the normal `buildLaunchFrames`' leading
    /// "stretch" wind-up frame (only sensible starting from a calm resting
    /// silhouette) and reuses the `ComposerWitnessFrames.dither`/
    /// `emptyGridLike` primitives directly.
    private static func launchDissolveFrames(
        from grid: [String],
        startCellOffsetY: Int,
        seed: Int32
    ) -> [ComposerWitnessFrames.WitnessFrame] {
        let empty = ComposerWitnessFrames.emptyGridLike(grid)
        let steps = 4
        let stepMs = 50
        return (1...steps).map { step in
            let progress = Double(step) / Double(steps)
            let d = ComposerWitnessFrames.dither(gridA: grid, gridB: empty, progress: progress, seed: seed)
            let blended = Int((Double(startCellOffsetY) * (1 - progress)).rounded())
            let drift = -Int(progress.rounded())
            return ComposerWitnessFrames.WitnessFrame(grid: d.grid, cellOffsetY: blended + drift, ms: stepMs)
        }
    }

    private static func onScreenColors(onScreen: OnScreen, current: Color, prior: Color?) -> [[Color]] {
        let rows = onScreen.grid.count
        let cols = onScreen.grid.first?.count ?? 0
        guard let sourceIsB = onScreen.sourceIsB else {
            // Not mid-blend: every on-screen cell is the same colour.
            return Array(repeating: Array(repeating: current, count: cols), count: rows)
        }
        // Already mid-blend: some cells are painted the (about-to-be-
        // outgoing) target colour, the rest still the older source colour —
        // carry each cell's ACTUAL colour forward.
        let priorColor = prior ?? current
        return (0..<rows).map { r in
            (0..<cols).map { c in sourceIsB[r][c] ? current : priorColor }
        }
    }
}

/// The sprite view. `TimelineView` wraps ONLY this sprite (never the
/// palette around it — the palette re-parses `query` on every redraw, plan
/// §4), so its clock never forces the whole composer to re-render, and
/// nothing here can delay typing.
struct ComposerWitnessView: View {
    let identity: ComposerWitness.Identity
    /// Written by the palette on `.open`/`.tabAccept`/`.unknownBranch`/
    /// `.launch`. An identity change is detected internally, below — the
    /// Witness view is the only thing that knows one already happened this
    /// frame.
    let beatTrigger: ComposerWitness.Beat
    let reduceMotion: Bool
    /// Round 14 (session-7): the sprite's edge length in points — the grid
    /// itself is always the fixed 12×12 `ComposerWitnessGhost.pixels`, so
    /// this is the whole `frameSize`; `WitnessSprite` derives cell size as
    /// `size/12` from it (`cellW`/`cellH` below, already computed from the
    /// frame size and the grid's own column/row count).
    let size: CGFloat
    /// Round 14: idle vertical bob amplitude, in points. 0 is off.
    let floatAmplitude: Double
    /// Round 15: idle sideways sway amplitude, in points — half the
    /// vertical bob's frequency, reusing `floatPeriod` (no separate period
    /// dial). 0 is off.
    let floatHorizontalAmplitude: Double
    /// Round 14: the float bob's full period, in seconds.
    let floatPeriod: Double
    /// Round 14: applied as one `.opacity` on the whole sprite, not per
    /// colour.
    let opacity: Double
    /// Round 14: scales beat time only (tab-accept/error/blend/launch, the
    /// open drop and each flip) — never the idle ripple/blink/glance clock,
    /// the wait between idle flips, or the tip.
    let beatSpeed: Double
    /// A soft glow in the ghost's own colour, drawn behind the sprite.
    /// Strength 0 draws none.
    let glowRadius: CGFloat
    let glowStrength: Double
    /// Short windows: the ghost lies on its side beside the field, a
    /// quarter turn clockwise (head toward the field), `lyingTravel` away
    /// from where it stands (`ComposerWitnessSideways`).
    let isLying: Bool
    let lyingTravel: CGSize

    private static let ditherSeed: Int32 = 11

    /// The ENTIRE mutable render state — one value, one pure transition
    /// function (`ComposerWitnessTransition.next`), so there is exactly one
    /// place (the single `onChange` below) that ever writes it.
    @State private var state: ComposerWitnessTransition.ViewState
    @State private var beatStartedAt: Date = .now
    /// When the open beat last armed: the clock for the drop, the landing
    /// flip and the idle flips after it. `nil` until the composer opens.
    @State private var openedAt: Date?
    @State private var mountedAt: Date = .now
    /// The tip: where it started from (0 standing ... 1 lying) and when.
    @State private var tipFrom: Double
    @State private var tipStartedAt: Date = .distantPast

    @Environment(\.displayScale) private var displayScale

    init(
        identity: ComposerWitness.Identity,
        beatTrigger: ComposerWitness.Beat,
        reduceMotion: Bool,
        size: CGFloat = ComposerWitnessSize.defaultSize,
        floatAmplitude: Double = ComposerWitnessFloatAmplitude.defaultAmplitude,
        floatHorizontalAmplitude: Double = ComposerWitnessFloatHorizontal.defaultAmplitude,
        floatPeriod: Double = ComposerWitnessFloatPeriod.defaultPeriod,
        opacity: Double = ComposerWitnessOpacity.defaultOpacity,
        beatSpeed: Double = ComposerWitnessBeatSpeed.defaultSpeed,
        glowRadius: CGFloat = ComposerWitnessGlowRadius.defaultRadius,
        glowStrength: Double = ComposerWitnessGlowStrength.defaultStrength,
        isLying: Bool = false,
        lyingTravel: CGSize = .zero
    ) {
        self.identity = identity
        self.beatTrigger = beatTrigger
        self.reduceMotion = reduceMotion
        self.size = size
        self.floatAmplitude = floatAmplitude
        self.floatHorizontalAmplitude = floatHorizontalAmplitude
        self.floatPeriod = floatPeriod
        self.opacity = opacity
        self.beatSpeed = beatSpeed
        self.glowRadius = glowRadius
        self.glowStrength = glowStrength
        self.isLying = isLying
        self.lyingTravel = lyingTravel
        _state = State(initialValue: ComposerWitnessTransition.ViewState(
            currentBeat: .idle,
            displayedIdentity: identity
        ))
        // Mounts already in place: a tip only ever plays on a change.
        _tipFrom = State(initialValue: isLying ? 1 : 0)
    }

    /// `identity` and `beatTrigger` can change in the SAME SwiftUI
    /// transaction (see `ComposerWitnessTransition`'s doc) — combining them
    /// into one Equatable value delivered to ONE `onChange` means SwiftUI
    /// can never deliver them as two independently-ordered updates.
    private struct Update: Equatable {
        var identity: ComposerWitness.Identity
        var beat: ComposerWitness.Beat
    }

    private var currentUpdate: Update {
        Update(identity: identity, beat: beatTrigger)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.02, paused: reduceMotion)) { context in
            let beatElapsedMs = scaledElapsedMs(since: beatStartedAt, now: context.date)
            let idleClockMs = Int(context.date.timeIntervalSince(mountedAt) * 1000)
            let display = displayGrid(beatElapsedMs: beatElapsedMs, idleClockMs: idleClockMs, reduceMotion: reduceMotion)
            let sinceOpenMs = openedAt.map { Int(context.date.timeIntervalSince($0) * 1000) }
            // The drop runs on the open clock, not the beat clock, so a
            // blend or Tab accept arriving mid-drop never replays or cuts it.
            let drop = sinceOpenMs.map {
                ComposerWitnessFrames.openTransform(elapsedMs: Int(Double($0) * beatSpeed), reduceMotion: reduceMotion)
            } ?? .identity
            // The flip is the ghost's own: once as it lands, then an idle
            // habit while the composer stays open. Nothing else starts one.
            let flipElapsedMs = state.isLaunchLocked ? nil : sinceOpenMs.flatMap {
                ComposerWitnessFrames.selfFlipElapsedMs(sinceOpenMs: $0, beatSpeed: beatSpeed, reduceMotion: reduceMotion)
            }
            let flipScaleX = flipElapsedMs.map {
                ComposerWitnessFrames.flipScaleX(elapsedMs: $0, reduceMotion: reduceMotion)
            } ?? 1
            let tip = tipPosition(now: context.date, toward: isLying)
            // Round 14: the float bob is applied here, as an `.offset`
            // transform on the sprite, never a layout/frame change — it
            // runs off `idleClockMs`, not the beat clock, so it never
            // pauses during a beat; the beat's own `cellOffsetY` hop
            // (already baked into `WitnessSprite`'s Canvas draw) stacks on
            // top of it untouched.
            let floatOffsetY = ComposerWitnessFrames.floatOffset(
                clockMs: idleClockMs,
                amplitude: floatAmplitude,
                periodMs: floatPeriod * 1000,
                reduceMotion: reduceMotion
            )
            // Round 15: the sideways sway, off the same idle clock, at half
            // the vertical bob's frequency (see `floatOffsetX`'s doc) —
            // combined with `floatOffsetY` via a single `.offset(x:y:)`.
            let floatOffsetX = ComposerWitnessFrames.floatOffsetX(
                clockMs: idleClockMs,
                amplitude: floatHorizontalAmplitude,
                periodMs: floatPeriod * 1000,
                reduceMotion: reduceMotion
            )
            let color = bodyColor(for: state.displayedIdentity)
            let glows = glowStrength > 0 && glowRadius > 0
            WitnessSprite(
                grid: display.grid,
                cellOffsetY: display.cellOffsetY,
                primaryColor: color,
                secondaryColors: state.resolveFromColors,
                sourceIsB: display.sourceIsB
            )
            // Drawn behind the sprite; the cells themselves stay sharp.
            .shadow(color: glows ? color.opacity(glowStrength) : .clear, radius: glows ? glowRadius : 0)
            // Scale 0 is a singular transform; the flip's edge-on instant
            // draws a hairline instead.
            .scaleEffect(x: max(drop.scaleX * flipScaleX, 0.001), y: drop.scaleY, anchor: .bottom)
            // The tip turns the ghost about its own centre, after the flip
            // and squash, so those stay the ghost's own (about its body
            // axis and feet) when it lies down. At rest it is exactly 0 or
            // a quarter turn, which maps the pixel grid onto itself.
            .rotationEffect(.degrees(ComposerWitnessSideways.lyingAngleDegrees * tip))
            // Float, drop and tip travel are in screen space. Snapped so
            // the sprite never rests between pixels.
            .offset(
                x: ComposerWitnessFrames.pixelSnapped(floatOffsetX + lyingTravel.width * tip, scale: displayScale),
                y: ComposerWitnessFrames.pixelSnapped(
                    floatOffsetY + drop.offsetY + lyingTravel.height * tip,
                    scale: displayScale
                )
            )
            .opacity(drop.opacity)
        }
        .frame(width: size, height: size)
        .opacity(opacity)
        // R4 review: `onChange` never fires for the value a view mounts
        // with — the palette arms `.open` from its OWN `onAppear`, which can
        // run before OR after this view's subtree is inserted. Feed the
        // mount-time value through the SAME `apply(_:)` this view's
        // `onChange` uses — `next(...)` is a no-op when its inputs already
        // match `state`, so whichever of `onAppear`/`onChange` runs first
        // does the real work and the other can never double-play it.
        .onAppear {
            apply(currentUpdate)
        }
        .onChange(of: currentUpdate) { newValue in
            apply(newValue)
        }
        .onChange(of: isLying) { nowLying in
            // Start from wherever the ghost is, so a tip that turns round
            // mid-way never jumps.
            let now = Date.now
            tipFrom = tipPosition(now: now, toward: !nowLying)
            tipStartedAt = now
        }
    }

    /// 0 standing ... 1 lying, at `now`, for a tip heading `toward` lying
    /// (or standing).
    private func tipPosition(now: Date, toward lying: Bool) -> Double {
        ComposerWitnessFrames.tipPosition(
            from: tipFrom,
            to: lying ? 1 : 0,
            elapsedMs: Int(min(now.timeIntervalSince(tipStartedAt), 3600) * 1000),
            reduceMotion: reduceMotion
        )
    }

    /// Round 14: `beatSpeed` scales beat time only — the idle ripple/blink/
    /// glance clock (`idleClockMs`, always derived from `mountedAt`) must
    /// never go through this.
    private func scaledElapsedMs(since start: Date, now: Date) -> Int {
        let rawElapsedMs = Int(now.timeIntervalSince(start) * 1000)
        return Int(Double(rawElapsedMs) * beatSpeed)
    }

    private func displayGrid(
        beatElapsedMs: Int,
        idleClockMs: Int,
        reduceMotion: Bool
    ) -> ComposerWitnessTransition.OnScreen {
        ComposerWitnessFrames.displayGrid(
            identityGrid: pixels(for: state.displayedIdentity),
            // A blend's frames play whatever beat the palette last sent.
            isIdleBeat: state.beatFrames.isEmpty,
            isLaunchBeat: state.isLaunchLocked,
            beatFrames: state.beatFrames,
            beatElapsedMs: beatElapsedMs,
            idleClockMs: idleClockMs,
            reduceMotion: reduceMotion
        )
    }

    private func apply(_ update: Update) {
        let now = Date.now
        // What was ACTUALLY on screen a moment ago, at the same scaled
        // clock `body` uses — every blend or dissolve starts from this.
        let onScreen = displayGrid(
            beatElapsedMs: scaledElapsedMs(since: beatStartedAt, now: now),
            idleClockMs: Int(now.timeIntervalSince(mountedAt) * 1000),
            reduceMotion: false
        )
        let resolved = ComposerWitnessTransition.next(
            state: state,
            newIdentity: update.identity,
            newBeat: update.beat,
            onScreen: onScreen,
            pixelsFor: { pixels(for: $0) },
            colorFor: { bodyColor(for: $0) },
            reduceMotion: reduceMotion,
            seed: Self.ditherSeed
        )
        // Only reset a clock when its motion ACTUALLY (re)armed — an
        // ignored/no-op update (launch-locked, or a duplicate onAppear/
        // onChange delivery of the same transition) must leave the playing
        // frames' clock alone.
        if resolved.framesSeq != state.framesSeq {
            beatStartedAt = now
        }
        // Only the open beat starts the drop and the flips; a project
        // change never does.
        if resolved.currentBeat != state.currentBeat, resolved.currentBeat.kind == .open {
            openedAt = now
        }
        state = resolved
    }

    private func pixels(for identity: ComposerWitness.Identity) -> [String] {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.pixels
        case .ghost(let ghost): return ghost.pixels
        }
    }

    private func bodyColor(for identity: ComposerWitness.Identity) -> Color {
        switch identity {
        case .placeholder: return ComposerWitnessPlaceholder.color
        case .ghost(let ghost): return Color(hex: ghost.colorHex)
        }
    }
}

/// Pure geometry for one Witness grid cell, pixel-snapped so adjacent cells
/// share an exact edge at any grid size and any display scale — no gaps,
/// no overlaps.
enum WitnessSpriteGeometry {
    static func cellRect(
        row: Int,
        col: Int,
        rows: Int,
        cols: Int,
        size: CGSize,
        cellOffsetY: Int,
        scale: CGFloat
    ) -> CGRect {
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        let colF = CGFloat(col)
        let rowF = CGFloat(row) + CGFloat(cellOffsetY)
        let x0 = (colF * cellW * scale).rounded() / scale
        let x1 = ((colF + 1) * cellW * scale).rounded() / scale
        let y0 = (rowF * cellH * scale).rounded() / scale
        let y1 = ((rowF + 1) * cellH * scale).rounded() / scale
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// The sprite Canvas, isolated as its own `Equatable` view so SwiftUI skips
/// repainting when the displayed frame hasn't actually changed — the only
/// thing `TimelineView`'s clock should force is a diff, not a guaranteed
/// redraw every tick.
///
/// Cells are grouped by resolved colour and each colour is filled with a
/// single `Path` built from pixel-snapped, edge-sharing rects
/// (`WitnessSpriteGeometry.cellRect`). Filling each colour exactly once
/// avoids double-painting semi-transparent colours at the seams — the
/// previous per-cell fill with `.rounded(.up)` widths overlapped by up to
/// 0.5pt at some grid sizes, which double-applied alpha and showed as a
/// mesh of darker grid lines.
private struct WitnessSprite: View, Equatable {
    let grid: [String]
    let cellOffsetY: Int
    let primaryColor: Color
    /// Per-cell "from" colours for a blend — `nil` outside one, in which
    /// case every body cell is `primaryColor` (see `color(forCell:row:col:)`).
    let secondaryColors: [[Color]]?
    let sourceIsB: [[Bool]]?

    @Environment(\.displayScale) private var displayScale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.grid == rhs.grid
            && lhs.cellOffsetY == rhs.cellOffsetY
            && lhs.primaryColor == rhs.primaryColor
            && lhs.secondaryColors == rhs.secondaryColors
            && lhs.sourceIsB == rhs.sourceIsB
    }

    var body: some View {
        Canvas { context, size in
            let rows = grid.count
            let cols = grid.first?.count ?? 0
            guard rows > 0, cols > 0 else { return }
            // Two passes: body cells ("X") first, then eyes/lit ("e"/"l")
            // second, so a shared edge can never flip a highlight pixel
            // back to body colour. Within each pass, cells are grouped by
            // resolved colour into one Path per colour and filled once —
            // snapped cells never overlap, so within-pass order doesn't
            // matter, but the two-pass split keeps highlights on top.
            var pathsByColor: [Color: Path] = [:]
            var colorOrder: [Color] = []
            func addCell(row: Int, col: Int, color: Color) {
                let rect = WitnessSpriteGeometry.cellRect(
                    row: row,
                    col: col,
                    rows: rows,
                    cols: cols,
                    size: size,
                    cellOffsetY: cellOffsetY,
                    scale: displayScale
                )
                if pathsByColor[color] == nil {
                    pathsByColor[color] = Path()
                    colorOrder.append(color)
                }
                pathsByColor[color]?.addRect(rect)
            }
            for (row, line) in grid.enumerated() {
                for (col, cell) in line.enumerated() {
                    guard cell == "X", let color = color(forCell: cell, row: row, col: col) else { continue }
                    addCell(row: row, col: col, color: color)
                }
            }
            for (row, line) in grid.enumerated() {
                for (col, cell) in line.enumerated() {
                    guard cell == "e" || cell == "l", let color = color(forCell: cell, row: row, col: col) else { continue }
                    addCell(row: row, col: col, color: color)
                }
            }
            for color in colorOrder {
                guard let path = pathsByColor[color] else { continue }
                context.fill(path, with: .color(color))
            }
        }
    }

    private func color(forCell cell: Character, row: Int, col: Int) -> Color? {
        let fromB = sourceIsB?[row][col] ?? true
        let bodyColor = fromB ? primaryColor : (secondaryColors?[row][col] ?? primaryColor)
        switch cell {
        case "X": return bodyColor
        case "e": return Color(hex: ComposerWitnessGhost.eyeColorHex)
        case "l": return Color(hex: ComposerWitnessGhost.litColorHex)
        default: return nil
        }
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
