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
    /// a beat: it flips the sprite on its own clock
    /// (`ComposerWitnessTransition`).
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
/// R3 review fix: `identity` and `beatTrigger` can change in the SAME
/// SwiftUI transaction (launch: `SessionComposerStore.precommit` clears
/// `searchText`, changing `identity`, then `SessionComposerPalette.commit`
/// arms `.launch`, both before the next render). `ComposerWitnessView`
/// delivers both as ONE combined value to ONE `onChange`, and `next(...)`
/// resolves them here in a fixed order: a newly-arming `.launch` always wins
/// outright, ignores any bundled identity change, never flips, and dissolves
/// from `onScreen`. Once locked, `identity` changes are a no-op until a later
/// non-launch beat arrives.
///
/// An identity change flips the sprite (scale x 1 -> 0 -> 1, swapped at the
/// midpoint, `ComposerWitnessFrames.flipTransform`) on its own clock, so a
/// beat arriving mid-flip never restarts it. A second change mid-flip lands
/// on the newest identity without a jump: in the first half the flip keeps
/// running and shows the newest identity at the midpoint; in the second half
/// it restarts at the mirrored time, where the width is the same.
///
/// Sean's decision (2026-09-13), "always have transitions": a Tab accept or
/// unknown branch that arrives bundled with an identity change plays the
/// flip first, then the beat's own frames on the new identity — the beat's
/// frames are held on the new resting grid until the flip ends.
///
/// The open beat is its own transition (the drop): an identity change
/// bundled with it swaps instantly, and it cancels any flip in flight.
enum ComposerWitnessTransition {
    struct ViewState: Equatable {
        var currentBeat: ComposerWitness.Beat
        var displayedIdentity: ComposerWitness.Identity
        var beatFrames: [ComposerWitnessFrames.WitnessFrame]
        var isLaunchLocked: Bool
        /// The identity on screen for the first half of the flip. `nil`
        /// when no flip has run since the last open.
        var flipFrom: ComposerWitness.Identity?
        /// Bumped whenever a flip (re)starts; the view then restarts its
        /// flip clock at `flipStartMs`.
        var flipSeq: Int
        var flipStartMs: Int

        init(
            currentBeat: ComposerWitness.Beat,
            displayedIdentity: ComposerWitness.Identity,
            beatFrames: [ComposerWitnessFrames.WitnessFrame] = [],
            isLaunchLocked: Bool = false,
            flipFrom: ComposerWitness.Identity? = nil,
            flipSeq: Int = 0,
            flipStartMs: Int = 0
        ) {
            self.currentBeat = currentBeat
            self.displayedIdentity = displayedIdentity
            self.beatFrames = beatFrames
            self.isLaunchLocked = isLaunchLocked
            self.flipFrom = flipFrom
            self.flipSeq = flipSeq
            self.flipStartMs = flipStartMs
        }
    }

    /// The identity on screen at `flipElapsedMs` into the flip: the outgoing
    /// one for its first half, else the displayed one.
    static func visibleIdentity(
        state: ViewState,
        flipElapsedMs: Int,
        reduceMotion: Bool
    ) -> ComposerWitness.Identity {
        guard let from = state.flipFrom,
              !ComposerWitnessFrames.flipTransform(elapsedMs: flipElapsedMs, reduceMotion: reduceMotion).showsNewIdentity
        else { return state.displayedIdentity }
        return from
    }

    /// `onScreen` MUST be captured from `state` BEFORE this call, at the
    /// instant `newIdentity`/`newBeat` arrived — exactly what was on screen a
    /// moment ago. A launch dissolve starts from it, never from a named
    /// identity's resting grid. `flipElapsedMs` is the flip clock at that
    /// same instant.
    static func next(
        state: ViewState,
        newIdentity: ComposerWitness.Identity,
        newBeat: ComposerWitness.Beat,
        onScreen: (grid: [String], cellOffsetY: Int),
        flipElapsedMs: Int,
        pixelsFor: (ComposerWitness.Identity) -> [String],
        reduceMotion: Bool,
        seed: Int32
    ) -> ViewState {
        let beatChanged = newBeat != state.currentBeat
        let identityChanged = newIdentity != state.displayedIdentity
        let flipMs = ComposerWitnessFrames.flipDurationMs
        let flipInFlight = state.flipFrom != nil && flipElapsedMs < flipMs

        // Launch always wins outright over any identity change bundled into
        // the same update, and never flips: it dissolves the identity that
        // is on screen. A flip already turning keeps turning to full width,
        // on that same identity.
        if beatChanged, newBeat.kind == .launch {
            let visible = visibleIdentity(state: state, flipElapsedMs: flipElapsedMs, reduceMotion: reduceMotion)
            var launched = state
            launched.currentBeat = newBeat
            launched.displayedIdentity = visible
            launched.flipFrom = state.flipFrom == nil ? nil : visible
            launched.beatFrames = launchDissolveFrames(
                from: onScreen.grid,
                startCellOffsetY: onScreen.cellOffsetY,
                seed: seed
            )
            launched.isLaunchLocked = true
            return launched
        }

        // Launch is terminal: locked, and no fresh beat arrived this
        // update to unlock it — ignore the identity change outright.
        if state.isLaunchLocked, !beatChanged {
            return state
        }

        var updated = state
        updated.isLaunchLocked = false
        let opens = beatChanged && newBeat.kind == .open

        if identityChanged {
            updated.displayedIdentity = newIdentity
            // Frames built on the old identity's silhouette no longer apply.
            updated.beatFrames = []
            if reduceMotion || opens {
                updated.flipFrom = nil
            } else if flipInFlight, flipElapsedMs < flipMs / 2 {
                // Still turning away from `flipFrom`: keep the clock; the
                // newest identity shows at the midpoint.
            } else if flipInFlight {
                // Turning back in on an identity that is now outgoing:
                // restart at the mirrored time, where the width is the same.
                updated.flipFrom = state.displayedIdentity
                updated.flipSeq += 1
                updated.flipStartMs = flipMs - flipElapsedMs
            } else {
                updated.flipFrom = state.displayedIdentity
                updated.flipSeq += 1
                updated.flipStartMs = 0
            }
        }
        if opens {
            updated.flipFrom = nil
        }

        if beatChanged {
            // A fresh, explicit beat (`.open`/`.tabAccept`/`.unknownBranch`
            // — `.launch` already returned above), built on whatever
            // identity is displayed after the identity update above.
            updated.currentBeat = newBeat
            let restingGrid = pixelsFor(updated.displayedIdentity)
            var frames = framesFor(kind: newBeat.kind, targetGrid: restingGrid)
            if identityChanged, updated.flipFrom != nil, !frames.isEmpty {
                // "Always have transitions": the flip plays first, the
                // beat's frames after it.
                let flipNowMs = updated.flipSeq != state.flipSeq ? updated.flipStartMs : flipElapsedMs
                let holdMs = flipMs - flipNowMs
                if holdMs > 0 {
                    frames.insert(ComposerWitnessFrames.WitnessFrame(grid: restingGrid, cellOffsetY: 0, ms: holdMs), at: 0)
                }
            }
            updated.beatFrames = frames
        }

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

    /// A launch dissolve from an ARBITRARY on-screen grid (not necessarily
    /// a named identity's resting grid) straight to empty. Deliberately
    /// skips the normal `buildLaunchFrames`' leading "stretch" wind-up frame
    /// (only sensible starting from a calm resting silhouette) and reuses
    /// the `ComposerWitnessFrames.dither`/`emptyGridLike` primitives
    /// directly.
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
}

/// The sprite view. `TimelineView` wraps ONLY this sprite (never the
/// palette around it — the palette re-parses `query` on every redraw, plan
/// §4), so its clock never forces the whole composer to re-render.
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
    /// Round 14: scales beat time only (tab-accept/error/launch/open drop
    /// and the identity flip) — never the idle ripple/blink/glance clock.
    let beatSpeed: Double
    /// A soft glow in the ghost's own colour, drawn behind the sprite.
    /// Strength 0 draws none.
    let glowRadius: CGFloat
    let glowStrength: Double

    private static let ditherSeed: Int32 = 11

    /// The ENTIRE mutable render state — one value, one pure transition
    /// function (`ComposerWitnessTransition.next`), so there is exactly one
    /// place (the single `onChange` below) that ever writes it.
    @State private var state: ComposerWitnessTransition.ViewState
    @State private var beatStartedAt: Date = .now
    @State private var flipStartedAt: Date = .now
    @State private var mountedAt: Date = .now

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
        glowStrength: Double = ComposerWitnessGlowStrength.defaultStrength
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
        _state = State(initialValue: ComposerWitnessTransition.ViewState(
            currentBeat: .idle,
            displayedIdentity: identity
        ))
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
            let flipElapsedMs = scaledElapsedMs(since: flipStartedAt, now: context.date)
            let idleClockMs = Int(context.date.timeIntervalSince(mountedAt) * 1000)
            let shown = onScreen(
                beatElapsedMs: beatElapsedMs,
                flipElapsedMs: flipElapsedMs,
                idleClockMs: idleClockMs,
                reduceMotion: reduceMotion
            )
            let flip = state.flipFrom == nil
                ? (scaleX: 1.0, showsNewIdentity: true)
                : ComposerWitnessFrames.flipTransform(elapsedMs: flipElapsedMs, reduceMotion: reduceMotion)
            let drop = state.currentBeat.kind == .open
                ? ComposerWitnessFrames.openTransform(elapsedMs: beatElapsedMs, reduceMotion: reduceMotion)
                : .identity
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
            let color = bodyColor(for: shown.identity)
            let glows = glowStrength > 0 && glowRadius > 0
            WitnessSprite(
                grid: shown.grid,
                cellOffsetY: shown.cellOffsetY,
                primaryColor: color
            )
            // Drawn behind the sprite; the cells themselves stay sharp.
            .shadow(color: glows ? color.opacity(glowStrength) : .clear, radius: glows ? glowRadius : 0)
            // Scale 0 is a singular transform; the flip's edge-on instant
            // draws a hairline instead.
            .scaleEffect(x: max(drop.scaleX * flip.scaleX, 0.001), y: drop.scaleY, anchor: .bottom)
            // Snapped so the sprite never rests between pixels.
            .offset(
                x: ComposerWitnessFrames.pixelSnapped(floatOffsetX, scale: displayScale),
                y: ComposerWitnessFrames.pixelSnapped(floatOffsetY + drop.offsetY, scale: displayScale)
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
    }

    /// Round 14: `beatSpeed` scales beat time only (and the flip, which
    /// stands in for the old resolve beat) — the idle ripple/blink/glance
    /// clock (`idleClockMs`, always derived from `mountedAt`) must never go
    /// through this.
    private func scaledElapsedMs(since start: Date, now: Date) -> Int {
        let rawElapsedMs = Int(now.timeIntervalSince(start) * 1000)
        return Int(Double(rawElapsedMs) * beatSpeed)
    }

    /// What is on screen: during a flip's first half, the outgoing
    /// identity's idle loop; otherwise the displayed identity's beat or
    /// idle frame.
    private func onScreen(
        beatElapsedMs: Int,
        flipElapsedMs: Int,
        idleClockMs: Int,
        reduceMotion: Bool
    ) -> (grid: [String], cellOffsetY: Int, identity: ComposerWitness.Identity) {
        let visible = ComposerWitnessTransition.visibleIdentity(
            state: state,
            flipElapsedMs: flipElapsedMs,
            reduceMotion: reduceMotion
        )
        let showsDisplayed = visible == state.displayedIdentity
        let display = ComposerWitnessFrames.displayGrid(
            identityGrid: pixels(for: visible),
            isIdleBeat: !showsDisplayed || state.currentBeat.kind == .idle,
            isLaunchBeat: showsDisplayed && state.currentBeat.kind == .launch,
            beatFrames: showsDisplayed ? state.beatFrames : [],
            beatElapsedMs: beatElapsedMs,
            idleClockMs: idleClockMs,
            reduceMotion: reduceMotion
        )
        return (display.grid, display.cellOffsetY, visible)
    }

    private func apply(_ update: Update) {
        let now = Date.now
        let flipElapsedMs = scaledElapsedMs(since: flipStartedAt, now: now)
        // What was ACTUALLY on screen a moment ago, at the same scaled
        // clocks `body` uses — a launch dissolve starts from this.
        let shown = onScreen(
            beatElapsedMs: scaledElapsedMs(since: beatStartedAt, now: now),
            flipElapsedMs: flipElapsedMs,
            idleClockMs: Int(now.timeIntervalSince(mountedAt) * 1000),
            reduceMotion: false
        )
        let resolved = ComposerWitnessTransition.next(
            state: state,
            newIdentity: update.identity,
            newBeat: update.beat,
            onScreen: (shown.grid, shown.cellOffsetY),
            flipElapsedMs: flipElapsedMs,
            pixelsFor: { pixels(for: $0) },
            reduceMotion: reduceMotion,
            seed: Self.ditherSeed
        )
        // Only reset a clock when its motion ACTUALLY (re)armed — an
        // ignored/no-op update (launch-locked, or a duplicate onAppear/
        // onChange delivery of the same transition) must leave the playing
        // beat's and flip's clocks alone.
        if resolved.currentBeat != state.currentBeat {
            beatStartedAt = now
        }
        if resolved.flipSeq != state.flipSeq {
            let offsetSeconds = Double(resolved.flipStartMs) / 1000 / max(beatSpeed, 0.01)
            flipStartedAt = now.addingTimeInterval(-offsetSeconds)
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

    @Environment(\.displayScale) private var displayScale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.grid == rhs.grid
            && lhs.cellOffsetY == rhs.cellOffsetY
            && lhs.primaryColor == rhs.primaryColor
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
                    guard cell == "X", let color = color(forCell: cell) else { continue }
                    addCell(row: row, col: col, color: color)
                }
            }
            for (row, line) in grid.enumerated() {
                for (col, cell) in line.enumerated() {
                    guard cell == "e" || cell == "l", let color = color(forCell: cell) else { continue }
                    addCell(row: row, col: col, color: color)
                }
            }
            for color in colorOrder {
                guard let path = pathsByColor[color] else { continue }
                context.fill(path, with: .color(color))
            }
        }
    }

    private func color(forCell cell: Character) -> Color? {
        switch cell {
        case "X": return primaryColor
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
