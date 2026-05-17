import SwiftUI

/// Ambient ghost-drift layer for an empty terminal surface.
///
/// Sits as the bottom-most child of `Ghostty.SurfaceWrapper`'s ZStack, behind
/// the Metal surface. Visible only while the surface has produced no output
/// and has no title. On first PTY output, fades out over 250ms and the
/// TimelineView dismounts so no frame work continues on active panes.
///
/// Phase A: drift + elastic ghost-ghost collisions + wall reflection.
/// Phase C: "GHOSTTIES" wordmark assembly/erosion cycle, gated behind
///          `ghostties.emptyStatePhysics.wordmark` AppStorage key (off by default).
/// Phase B will add drag/tap. Phase D is a stretch goal.
struct SurfaceEmptyStatePhysics: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    @State private var hasReceivedOutput: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ghostties.emptyStatePhysics.wordmark") private var wordmarkEnabled = false

    private var isEmpty: Bool {
        surfaceView.title.isEmpty && !hasReceivedOutput
    }

    var body: some View {
        Group {
            if isEmpty {
                if reduceMotion {
                    staticArrangement
                } else {
                    livePhysics
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .opacity(isEmpty ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: isEmpty)
        .onReceive(surfaceView.lastOutputSubject) { _ in
            hasReceivedOutput = true
        }
    }

    // MARK: - Live physics

    private var livePhysics: some View {
        GeometryReader { geo in
            PhysicsCanvas(
                bounds: CGRect(origin: .zero, size: geo.size),
                wordmarkEnabled: wordmarkEnabled
            )
        }
    }

    // MARK: - Reduce-Motion static fallback

    private var staticArrangement: some View {
        GeometryReader { geo in
            let paneBounds = CGRect(origin: .zero, size: geo.size)
            let count = 6
            let spacing = geo.size.width / CGFloat(count + 1)
            let y = geo.size.height / 2
            let chars = Array(GhostCharacter.allCases.prefix(count))
            let layout = wordmarkEnabled ? WordmarkLayout(paneBounds: paneBounds) : nil
            ZStack {
                ForEach(Array(chars.enumerated()), id: \.offset) { idx, char in
                    GhostCharacterView(character: char, color: .secondary)
                        .frame(width: 48, height: 48)
                        .opacity(0.18)
                        .position(x: spacing * CGFloat(idx + 1), y: y)
                }
                if let layout {
                    // Reduce Motion (R20): wordmark fully assembled, no animation.
                    Canvas { context, _ in
                        var path = Path()
                        for slot in layout.slotPositions {
                            path.addRect(CGRect(
                                x: slot.x, y: slot.y,
                                width: layout.brickSize, height: layout.brickSize
                            ))
                        }
                        context.fill(path, with: .color(.primary.opacity(0.70)))
                    }
                }
            }
        }
    }
}

/// Hosts the `TimelineView(.animation)` so it lives strictly inside the
/// "visible" branch — dismount when the parent hides this view, no idle frames.
private struct PhysicsCanvas: View {
    let bounds: CGRect
    let wordmarkEnabled: Bool
    @State private var world: PhysicsWorld
    @State private var wordmarkWorld: WordmarkWorld? = nil
    @State private var lastTick: Date? = nil

    init(bounds: CGRect, wordmarkEnabled: Bool) {
        self.bounds = bounds
        self.wordmarkEnabled = wordmarkEnabled
        _world = State(initialValue: PhysicsWorld.initial(in: bounds))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let _ = step(to: timeline.date)
            ZStack {
                // Phase A: ambient ghost drift at ambient opacity.
                ZStack {
                    ForEach(world.bodies) { body in
                        GhostCharacterView(character: body.character, color: body.tint)
                            .frame(width: body.radius * 2, height: body.radius * 2)
                            .position(body.position)
                    }
                }
                .opacity(0.22)

                // Phase C: wordmark pixel layer at full brand opacity.
                if let ww = wordmarkWorld {
                    Canvas { context, _ in
                        var rubblePath = Path()
                        var brandPath = Path()
                        for pixel in ww.pixels {
                            let rect = CGRect(
                                x: pixel.currentPosition.x,
                                y: pixel.currentPosition.y,
                                width: ww.brickSize,
                                height: ww.brickSize
                            )
                            switch pixel.state {
                            case .rubble:
                                rubblePath.addRect(rect)
                            case .inTransit, .placed:
                                brandPath.addRect(rect)
                            }
                        }
                        context.fill(
                            rubblePath,
                            with: .color(.secondary.opacity(WordmarkWorld.rubbleOpacity))
                        )
                        context.fill(
                            brandPath,
                            with: .color(.primary.opacity(ww.brandOpacity))
                        )
                    }
                }
            }
        }
        // R21: cycle resets on pane resize; WordmarkWorld.initial re-scatters rubble.
        .onChange(of: bounds.size) { _ in
            wordmarkWorld = nil
        }
    }

    private func step(to date: Date) {
        let now = date
        let dt: TimeInterval
        if let last = lastTick {
            dt = max(0, now.timeIntervalSince(last))
        } else {
            dt = 1.0 / 60.0
        }
        // SwiftUI complains about state mutation during view update if we
        // mutate synchronously inside the body builder. Defer to next runloop.
        DispatchQueue.main.async {
            lastTick = now

            if wordmarkEnabled, let layout = WordmarkLayout(paneBounds: bounds) {
                if wordmarkWorld == nil {
                    // First activation or post-resize: reset roles, initialize cycle.
                    let reset = world.bodies.map { b -> GhostBody in var x = b; x.role = .drifting; return x }
                    world = PhysicsWorld(bodies: reset)
                    wordmarkWorld = WordmarkWorld.initial(layout: layout, bounds: bounds, bodies: reset)
                }
                if let ww = wordmarkWorld {
                    let (newWW, updatedBodies) = ww.stepped(bodies: world.bodies, dt: dt, bounds: bounds)
                    wordmarkWorld = newWW
                    // Phase A step uses carrier-updated bodies; collision guard in
                    // PhysicsCollision.resolvePair skips non-drifting pairs (R11).
                    world = PhysicsWorld(bodies: updatedBodies).stepped(by: dt, bounds: bounds)
                } else {
                    world = world.stepped(by: dt, bounds: bounds)
                }
            } else {
                if wordmarkWorld != nil {
                    // Deactivating: restore drifting roles before handing back to Phase A.
                    let reset = world.bodies.map { b -> GhostBody in var x = b; x.role = .drifting; return x }
                    world = PhysicsWorld(bodies: reset)
                    wordmarkWorld = nil
                }
                world = world.stepped(by: dt, bounds: bounds)
            }
        }
    }
}
