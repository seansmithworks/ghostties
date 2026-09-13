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

/// Pure transition logic for `ComposerWitnessView` — the ENTIRE decision
/// point for what a combined `identity`/`beatTrigger` update does, so the
/// view is a thin shell (one `onChange`, one call here) and the logic is
/// directly testable without constructing a View.
///
/// R2 review fix 1: a second identity change during a resolve morph (or one
/// landing mid tab/error/open beat) must start its own morph from EXACTLY
/// what's on screen at that instant — chars, cell offset, and per-cell
/// colour — never from the interrupted beat's named target's full base
/// grid (that discarded whatever fraction of the prior morph had already
/// played, producing a visible jump).
///
/// R3 review fix: `identity` and `beatTrigger` can change in the SAME
/// SwiftUI transaction (launch: `SessionComposerStore.precommit` clears
/// `searchText`, changing `identity`, then `SessionComposerPalette.commit`
/// arms `.launch`, both before the next render) — two separate `onChange`
/// handlers had no defined order for that case, so which one SwiftUI
/// happened to run first decided whether launch dissolved the right ghost.
/// `ComposerWitnessView` now delivers both as ONE combined value to ONE
/// `onChange`, and `next(state:newIdentity:newBeat:...)` resolves them here,
/// in a fixed order: a newly-arming `.launch` always wins outright, ignores
/// any bundled identity change, and dissolves from `onScreen` — never
/// rebuilt from `displayedIdentity`. Once locked, `identity` changes are a
/// no-op until a later non-launch beat arrives.
enum ComposerWitnessTransition {
    struct ViewState: Equatable {
        var currentBeat: ComposerWitness.Beat
        var displayedIdentity: ComposerWitness.Identity
        var previousIdentity: ComposerWitness.Identity?
        var beatFrames: [ComposerWitnessFrames.WitnessFrame]
        /// Per-cell "from" colours for the resolve/dissolve currently
        /// playing — may mix more than one prior ghost's colour when a
        /// morph interrupts another morph already in flight. `nil` outside
        /// a resolve/dissolve.
        var resolveFromColors: [[Color]]?
        var isLaunchLocked: Bool
    }

    /// `onScreen` MUST be captured (via `ComposerWitnessFrames.displayGrid`)
    /// from `state` BEFORE this call, at the instant `newIdentity`/`newBeat`
    /// arrived — exactly what was on screen a moment ago (chars, offset,
    /// per-cell colour provenance). Every morph/dissolve this produces
    /// starts from that capture, never from a named identity's resting
    /// grid.
    static func next(
        state: ViewState,
        newIdentity: ComposerWitness.Identity,
        newBeat: ComposerWitness.Beat,
        onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?),
        pixelsFor: (ComposerWitness.Identity) -> [String],
        colorFor: (ComposerWitness.Identity) -> Color,
        reduceMotion: Bool,
        seed: Int32
    ) -> ViewState {
        let beatChanged = newBeat != state.currentBeat
        let identityChanged = newIdentity != state.displayedIdentity

        // Launch always wins outright over any identity change bundled
        // into the same update — dissolves from exactly what's on screen,
        // never rebuilt from `displayedIdentity`. This is the fix: the bug
        // was launch reading whatever `displayedIdentity` an
        // already-applied identity swap had just written.
        if beatChanged, newBeat.kind == .launch {
            return ViewState(
                currentBeat: newBeat,
                displayedIdentity: state.displayedIdentity,
                previousIdentity: state.previousIdentity,
                beatFrames: launchDissolveFrames(
                    from: onScreen.grid,
                    startCellOffsetY: onScreen.cellOffsetY,
                    seed: seed
                ),
                resolveFromColors: onScreenColors(
                    onScreen: onScreen,
                    current: colorFor(state.displayedIdentity),
                    prior: state.previousIdentity.map(colorFor)
                ),
                isLaunchLocked: true
            )
        }

        // Launch is terminal: locked, and no fresh beat arrived this
        // update to unlock it — ignore the identity change outright.
        if state.isLaunchLocked, !beatChanged {
            return state
        }

        var displayed = state.displayedIdentity
        var previous = state.previousIdentity
        var frames = state.beatFrames
        var colors = state.resolveFromColors
        var beat = state.currentBeat

        if identityChanged {
            if reduceMotion {
                displayed = newIdentity
                previous = nil
                beat = .idle
                frames = []
                colors = nil
            } else {
                let currentColor = colorFor(state.displayedIdentity)
                let priorColor = state.previousIdentity.map(colorFor) ?? currentColor
                colors = onScreenColors(onScreen: onScreen, current: currentColor, prior: priorColor)
                var resolveFrames = ComposerWitnessFrames.buildResolveFrames(
                    gridA: onScreen.grid,
                    gridB: pixelsFor(newIdentity),
                    seed: seed
                )
                blendOffset(&resolveFrames, from: onScreen.cellOffsetY)
                frames = resolveFrames
                previous = state.displayedIdentity
                displayed = newIdentity
                // `.resolve` is an identity swap, not a replay of `.open` —
                // it must never re-arm the open materialise.
                beat = beat.next(.resolve)
            }
        }

        if beatChanged {
            // A fresh, explicit beat trigger (`.open`/`.tabAccept`/
            // `.unknownBranch` — `.launch` already returned above). Rearms
            // from whatever identity is displayed AFTER the identity
            // update immediately above, a fixed, deterministic order for
            // the rare case both change in the same update.
            beat = newBeat
            frames = framesFor(
                kind: newBeat.kind,
                targetGrid: pixelsFor(displayed),
                sourceGrid: previous.map(pixelsFor),
                seed: seed
            )
            colors = nil
        }

        return ViewState(
            currentBeat: beat,
            displayedIdentity: displayed,
            previousIdentity: previous,
            beatFrames: frames,
            resolveFromColors: colors,
            isLaunchLocked: false
        )
    }

    private static func framesFor(
        kind: ComposerWitness.BeatKind,
        targetGrid: [String],
        sourceGrid: [String]?,
        seed: Int32
    ) -> [ComposerWitnessFrames.WitnessFrame] {
        switch kind {
        case .idle: return []
        case .open: return ComposerWitnessFrames.buildOpenFrames(grid: targetGrid, seed: seed)
        case .tabAccept: return ComposerWitnessFrames.buildTabFrames(grid: targetGrid)
        case .unknownBranch: return ComposerWitnessFrames.buildErrorFrames(grid: targetGrid)
        case .launch: return ComposerWitnessFrames.buildLaunchFrames(grid: targetGrid, seed: seed)
        case .resolve:
            return ComposerWitnessFrames.buildResolveFrames(gridA: sourceGrid ?? targetGrid, gridB: targetGrid, seed: seed)
        }
    }

    /// A resolve/dissolve always plays at cellOffsetY 0 by construction —
    /// if the interrupted beat had shifted the sprite (e.g. mid tab-accept
    /// hop), blend that offset back to 0 across the new frames instead of
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
    /// a named identity's resting grid — could be mid-morph) straight to
    /// empty. Deliberately skips the normal `buildLaunchFrames`' leading
    /// "stretch" wind-up frame (only sensible starting from a calm resting
    /// silhouette) and reuses the untouched `ComposerWitnessFrames.dither`/
    /// `emptyGridLike` primitives directly — `ComposerWitnessFrames.swift`
    /// itself stays unmodified.
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
            return ComposerWitnessFrames.WitnessFrame(grid: d.grid, cellOffsetY: blended + drift, ms: stepMs, sourceIsB: nil)
        }
    }

    private static func onScreenColors(
        onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?),
        current: Color,
        prior: Color?
    ) -> [[Color]] {
        let rows = onScreen.grid.count
        let cols = onScreen.grid.first?.count ?? 0
        guard let sourceIsB = onScreen.sourceIsB else {
            // Not mid-morph (idle/tab/error/open all show a single
            // identity's colour uniformly) — every on-screen cell is the
            // same colour.
            return Array(repeating: Array(repeating: current, count: cols), count: rows)
        }
        // Already mid-morph: some cells are already painted the
        // (about-to-be-outgoing) target colour, the rest still the older
        // source colour — carry each cell's ACTUAL colour forward rather
        // than collapsing back to a single source.
        let priorColor = prior ?? current
        return (0..<rows).map { r in
            (0..<cols).map { c in sourceIsB[r][c] ? current : priorColor }
        }
    }
}

/// The 24×24 sprite view. `TimelineView` wraps ONLY this sprite (never the
/// palette around it — the palette re-parses `query` on every redraw, plan
/// §4), so its clock never forces the whole composer to re-render.
struct ComposerWitnessView: View {
    let identity: ComposerWitness.Identity
    /// Written by the palette on `.open`/`.tabAccept`/`.unknownBranch`/
    /// `.launch`. `.resolve` is detected internally, below, from `identity`
    /// changing — the Witness view is the only thing that knows an
    /// identity change already happened this frame.
    let beatTrigger: ComposerWitness.Beat
    let reduceMotion: Bool

    private static let ditherSeed: Int32 = 11

    /// The ENTIRE mutable render state — one value, one pure transition
    /// function (`ComposerWitnessTransition.next`), so there is exactly one
    /// place (the single `onChange` below) that ever writes it.
    @State private var state: ComposerWitnessTransition.ViewState
    @State private var beatStartedAt: Date = .now
    @State private var mountedAt: Date = .now

    private let frameSize: CGFloat = 24

    init(identity: ComposerWitness.Identity, beatTrigger: ComposerWitness.Beat, reduceMotion: Bool) {
        self.identity = identity
        self.beatTrigger = beatTrigger
        self.reduceMotion = reduceMotion
        _state = State(initialValue: ComposerWitnessTransition.ViewState(
            currentBeat: .idle,
            displayedIdentity: identity,
            previousIdentity: nil,
            beatFrames: [],
            resolveFromColors: nil,
            isLaunchLocked: false
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
            let beatElapsedMs = Int(context.date.timeIntervalSince(beatStartedAt) * 1000)
            let idleClockMs = Int(context.date.timeIntervalSince(mountedAt) * 1000)
            let display = ComposerWitnessFrames.displayGrid(
                identityGrid: pixels(for: state.displayedIdentity),
                isIdleBeat: state.currentBeat.kind == .idle,
                isLaunchBeat: state.currentBeat.kind == .launch,
                beatFrames: state.beatFrames,
                beatElapsedMs: beatElapsedMs,
                idleClockMs: idleClockMs,
                reduceMotion: reduceMotion
            )
            WitnessSprite(
                grid: display.grid,
                cellOffsetY: display.cellOffsetY,
                primaryColor: bodyColor(for: state.displayedIdentity),
                secondaryColors: state.resolveFromColors,
                sourceIsB: display.sourceIsB
            )
        }
        .frame(width: frameSize, height: frameSize)
        .onChange(of: currentUpdate) { newValue in
            let now = Date.now
            // What was ACTUALLY on screen a moment ago — every morph or
            // dissolve `next(...)` produces starts from this, never from a
            // named identity's resting grid.
            let onScreen = ComposerWitnessFrames.displayGrid(
                identityGrid: pixels(for: state.displayedIdentity),
                isIdleBeat: state.currentBeat.kind == .idle,
                isLaunchBeat: state.currentBeat.kind == .launch,
                beatFrames: state.beatFrames,
                beatElapsedMs: Int(now.timeIntervalSince(beatStartedAt) * 1000),
                idleClockMs: Int(now.timeIntervalSince(mountedAt) * 1000),
                reduceMotion: false
            )
            let resolved = ComposerWitnessTransition.next(
                state: state,
                newIdentity: newValue.identity,
                newBeat: newValue.beat,
                onScreen: onScreen,
                pixelsFor: { pixels(for: $0) },
                colorFor: { bodyColor(for: $0) },
                reduceMotion: reduceMotion,
                seed: Self.ditherSeed
            )
            // Only reset the beat clock when a beat ACTUALLY armed (by
            // `seq`) — an ignored update (launch-locked) must leave the
            // already-playing dissolve's clock alone.
            if resolved.currentBeat != state.currentBeat {
                beatStartedAt = now
            }
            state = resolved
        }
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

/// The sprite Canvas, isolated as its own `Equatable` view so SwiftUI skips
/// repainting when the displayed frame hasn't actually changed — the only
/// thing `TimelineView`'s clock should force is a diff, not a guaranteed
/// redraw every tick.
private struct WitnessSprite: View, Equatable {
    let grid: [String]
    let cellOffsetY: Int
    let primaryColor: Color
    /// Per-cell "from" colours for a resolve morph — `nil` outside a
    /// resolve, in which case every non-primary cell just falls back to
    /// `primaryColor` (see `color(forCell:row:col:)`).
    let secondaryColors: [[Color]]?
    let sourceIsB: [[Bool]]?

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
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)
            for (row, line) in grid.enumerated() {
                for (col, cell) in line.enumerated() {
                    guard let color = color(forCell: cell, row: row, col: col) else { continue }
                    let rect = CGRect(
                        x: CGFloat(col) * cellW,
                        y: (CGFloat(row) + CGFloat(cellOffsetY)) * cellH,
                        width: cellW.rounded(.up),
                        height: cellH.rounded(.up)
                    )
                    context.fill(Path(rect), with: .color(color))
                }
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
