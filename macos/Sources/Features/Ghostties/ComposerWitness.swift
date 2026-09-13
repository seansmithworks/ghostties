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

/// Pure transition logic for an identity change arriving while a beat is
/// mid-playback — extracted out of `ComposerWitnessView.onChange(of:
/// identity)` so it's directly testable without constructing a View.
///
/// R2 review fix 1: a second identity change during a resolve morph (or one
/// landing mid tab/error/open beat) must start its own morph from EXACTLY
/// what's on screen at that instant — chars, cell offset, and per-cell
/// colour — never from the interrupted beat's named target's full base
/// grid (that discarded whatever fraction of the prior morph had already
/// played, producing a visible jump).
///
/// R2 review fix 2: once a `.launch` beat has armed, it's terminal —
/// `identityChanged` returns `nil` (a no-op) for every identity change
/// until the caller reports a later non-launch beat, so the dissolve can
/// never be overridden by a resolve.
enum ComposerWitnessTransition {
    struct ResolvedState {
        var previousIdentity: ComposerWitness.Identity
        var displayedIdentity: ComposerWitness.Identity
        var beatFrames: [ComposerWitnessFrames.WitnessFrame]
        var resolveFromColors: [[Color]]
    }

    static func identityChanged(
        to newIdentity: ComposerWitness.Identity,
        currentDisplayedIdentity: ComposerWitness.Identity,
        currentPreviousIdentity: ComposerWitness.Identity?,
        onScreen: (grid: [String], cellOffsetY: Int, sourceIsB: [[Bool]]?),
        targetGrid: [String],
        isLaunchLocked: Bool,
        colorFor: (ComposerWitness.Identity) -> Color,
        seed: Int32
    ) -> ResolvedState? {
        guard !isLaunchLocked else { return nil }
        guard newIdentity != currentDisplayedIdentity else { return nil }

        let currentColor = colorFor(currentDisplayedIdentity)
        let priorColor = currentPreviousIdentity.map(colorFor) ?? currentColor
        let rows = onScreen.grid.count
        let cols = onScreen.grid.first?.count ?? 0
        let fromColors: [[Color]]
        if let sourceIsB = onScreen.sourceIsB {
            // Already mid-morph: some cells are already painted the
            // (about-to-be-outgoing) target colour, the rest still the
            // older source colour — carry each cell's ACTUAL colour
            // forward rather than collapsing back to a single source.
            fromColors = (0..<rows).map { r in
                (0..<cols).map { c in sourceIsB[r][c] ? currentColor : priorColor }
            }
        } else {
            // Not mid-morph (idle/tab/error/open all show a single
            // identity's colour uniformly) — every on-screen cell is the
            // same colour.
            fromColors = Array(repeating: Array(repeating: currentColor, count: cols), count: rows)
        }

        var frames = ComposerWitnessFrames.buildResolveFrames(
            gridA: onScreen.grid,
            gridB: targetGrid,
            seed: seed
        )
        // A resolve always plays at cellOffsetY 0 — if the interrupted beat
        // had shifted the sprite (e.g. mid tab-accept hop), blend that
        // offset back to 0 across the new morph's frames instead of
        // snapping to 0 on frame one.
        if onScreen.cellOffsetY != 0 {
            let start = onScreen.cellOffsetY
            let n = frames.count
            for i in frames.indices {
                let progress = Double(i + 1) / Double(n)
                frames[i].cellOffsetY = Int((Double(start) * (1 - progress)).rounded())
            }
        }

        return ResolvedState(
            previousIdentity: currentDisplayedIdentity,
            displayedIdentity: newIdentity,
            beatFrames: frames,
            resolveFromColors: fromColors
        )
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

    @State private var currentBeat: ComposerWitness.Beat = .idle
    @State private var beatStartedAt: Date = .now
    @State private var mountedAt: Date = .now
    @State private var beatFrames: [ComposerWitnessFrames.WitnessFrame] = []

    /// The identity actually on screen — the target of a resolve morph the
    /// instant it's detected in `onChange(of: identity)`; `previousIdentity`
    /// keeps the outgoing ghost's colour available for per-source-cell
    /// tinting while that morph's frames play.
    @State private var displayedIdentity: ComposerWitness.Identity
    @State private var previousIdentity: ComposerWitness.Identity?
    /// Per-cell "from" colours for the resolve currently playing, captured
    /// once at arm time by `ComposerWitnessTransition.identityChanged` —
    /// may mix more than one prior ghost's colour when a resolve interrupts
    /// another resolve already in flight. `nil` outside a resolve.
    @State private var resolveFromColors: [[Color]]?
    /// R2 review fix 2: once a `.launch` beat arms this stays `true` until
    /// a later NON-launch beat trigger arrives — while locked, `identity`
    /// changes are ignored outright so launch's terminal empty grid can
    /// never be overridden by a resolve.
    @State private var isLaunchLocked = false

    private let frameSize: CGFloat = 24

    init(identity: ComposerWitness.Identity, beatTrigger: ComposerWitness.Beat, reduceMotion: Bool) {
        self.identity = identity
        self.beatTrigger = beatTrigger
        self.reduceMotion = reduceMotion
        _displayedIdentity = State(initialValue: identity)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.02, paused: reduceMotion)) { context in
            let beatElapsedMs = Int(context.date.timeIntervalSince(beatStartedAt) * 1000)
            let idleClockMs = Int(context.date.timeIntervalSince(mountedAt) * 1000)
            let display = ComposerWitnessFrames.displayGrid(
                identityGrid: pixels(for: displayedIdentity),
                isIdleBeat: currentBeat.kind == .idle,
                isLaunchBeat: currentBeat.kind == .launch,
                beatFrames: beatFrames,
                beatElapsedMs: beatElapsedMs,
                idleClockMs: idleClockMs,
                reduceMotion: reduceMotion
            )
            WitnessSprite(
                grid: display.grid,
                cellOffsetY: display.cellOffsetY,
                primaryColor: bodyColor(for: displayedIdentity),
                secondaryColors: resolveFromColors,
                sourceIsB: display.sourceIsB
            )
        }
        .frame(width: frameSize, height: frameSize)
        .onChange(of: beatTrigger) { newValue in
            isLaunchLocked = newValue.kind == .launch
            currentBeat = newValue
            beatStartedAt = .now
            beatFrames = frames(for: newValue.kind, target: displayedIdentity, source: previousIdentity)
            resolveFromColors = nil
        }
        .onChange(of: identity) { newValue in
            guard newValue != displayedIdentity else { return }
            if reduceMotion {
                guard !isLaunchLocked else { return }
                // Instant swap, no frames, no idle motion.
                displayedIdentity = newValue
                previousIdentity = nil
                currentBeat = .idle
                beatFrames = []
                resolveFromColors = nil
                return
            }
            let now = Date.now
            let onScreen = ComposerWitnessFrames.displayGrid(
                identityGrid: pixels(for: displayedIdentity),
                isIdleBeat: currentBeat.kind == .idle,
                isLaunchBeat: currentBeat.kind == .launch,
                beatFrames: beatFrames,
                beatElapsedMs: Int(now.timeIntervalSince(beatStartedAt) * 1000),
                idleClockMs: Int(now.timeIntervalSince(mountedAt) * 1000),
                reduceMotion: false
            )
            guard let resolved = ComposerWitnessTransition.identityChanged(
                to: newValue,
                currentDisplayedIdentity: displayedIdentity,
                currentPreviousIdentity: previousIdentity,
                onScreen: onScreen,
                targetGrid: pixels(for: newValue),
                isLaunchLocked: isLaunchLocked,
                colorFor: bodyColor(for:),
                seed: Self.ditherSeed
            ) else { return }
            previousIdentity = resolved.previousIdentity
            displayedIdentity = resolved.displayedIdentity
            // `.resolve` is an identity swap, not a replay of `.open` — it
            // must never re-arm the open materialise.
            currentBeat = currentBeat.next(.resolve)
            beatStartedAt = now
            beatFrames = resolved.beatFrames
            resolveFromColors = resolved.resolveFromColors
        }
    }

    private func frames(
        for kind: ComposerWitness.BeatKind,
        target: ComposerWitness.Identity,
        source: ComposerWitness.Identity?
    ) -> [ComposerWitnessFrames.WitnessFrame] {
        let grid = pixels(for: target)
        switch kind {
        case .idle: return []
        case .open: return ComposerWitnessFrames.buildOpenFrames(grid: grid, seed: Self.ditherSeed)
        case .tabAccept: return ComposerWitnessFrames.buildTabFrames(grid: grid)
        case .unknownBranch: return ComposerWitnessFrames.buildErrorFrames(grid: grid)
        case .launch: return ComposerWitnessFrames.buildLaunchFrames(grid: grid, seed: Self.ditherSeed)
        case .resolve:
            let gridA = pixels(for: source ?? target)
            return ComposerWitnessFrames.buildResolveFrames(gridA: gridA, gridB: grid, seed: Self.ditherSeed)
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
