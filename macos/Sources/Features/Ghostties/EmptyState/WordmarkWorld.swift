import CoreGraphics

// MARK: - Supporting types

enum PixelState: Equatable {
    case rubble
    case inTransit(carrierId: UUID)
    case placed
}

struct WordmarkPixel {
    let index: Int
    let slotPosition: CGPoint
    var rubblePosition: CGPoint
    var currentPosition: CGPoint
    var displayOpacity: Double
    var state: PixelState
}

enum WordmarkCyclePhase {
    case assembling
    case holding(elapsed: TimeInterval)
    case eroding
}

// MARK: - WorldmarkWorld

/// Pure value-type model for the Phase C wordmark assembly/erosion cycle.
///
/// Owns cycle phase, pixel states, and carrier role assignments. Each call to
/// `stepped(bodies:dt:bounds:)` returns a new world and an updated bodies array.
/// `PhysicsCanvas` calls this before `PhysicsWorld.stepped` so carrier positions
/// are set before wall reflection and drifter collision run.
struct WordmarkWorld {
    var phase: WordmarkCyclePhase
    var pixels: [WordmarkPixel]
    let holdDuration: TimeInterval
    let brickSize: CGFloat
    let wordmarkRect: CGRect
    let brandOpacity: Double

    static let rubbleOpacity: Double = 0.22
    static let maxCarriers: Int = 3
    static let maxCarrierSpeed: CGFloat = 1.3   // px/frame at 60 fps
    static let pickupRadius: CGFloat = 12.0      // pt
    static let depositRadius: CGFloat = 8.0      // pt
    // Per-ghost, per-frame probability of being assigned as a carrier.
    // Carriers get assigned within a few frames of phase entry; actual travel
    // is slow (seek speed) so the animation reads as patient even with fast assignment.
    static let carrierProbability: Double = 0.15

    init(
        phase: WordmarkCyclePhase,
        pixels: [WordmarkPixel],
        brickSize: CGFloat,
        wordmarkRect: CGRect,
        holdDuration: TimeInterval = 4.0,
        brandOpacity: Double = 0.70
    ) {
        self.phase = phase
        self.pixels = pixels
        self.holdDuration = holdDuration
        self.brickSize = brickSize
        self.wordmarkRect = wordmarkRect
        self.brandOpacity = brandOpacity
    }

    // MARK: - Factory

    /// Initialize a fresh assembling cycle. Scatters all pixels as rubble outside
    /// the wordmark rect and resets all ghost roles to `.drifting`.
    static func initial(layout: WordmarkLayout, bounds: CGRect, bodies: [GhostBody]) -> WordmarkWorld {
        let pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            let rubblePos = randomRubblePosition(
                in: bounds, excluding: layout.wordmarkRect, brickSize: layout.brickSize
            )
            return WordmarkPixel(
                index: idx,
                slotPosition: slot,
                rubblePosition: rubblePos,
                currentPosition: rubblePos,
                displayOpacity: rubbleOpacity,
                state: .rubble
            )
        }
        return WordmarkWorld(
            phase: .assembling,
            pixels: pixels,
            brickSize: layout.brickSize,
            wordmarkRect: layout.wordmarkRect
        )
    }

    // MARK: - Step

    /// Advance the wordmark simulation by `dt` seconds.
    ///
    /// Returns the new world state and updated ghost bodies. Carrier bodies have
    /// their positions moved toward targets; drifter positions are unchanged
    /// (PhysicsWorld.stepped applies their drift after this call).
    func stepped(bodies: [GhostBody], dt: TimeInterval, bounds: CGRect) -> (WordmarkWorld, [GhostBody]) {
        let dtClamped = min(dt, 1.0 / 30.0)
        var ww = self
        var updatedBodies = bodies

        // 1. Process existing carrier states: move, pickup, deposit.
        for i in 0..<updatedBodies.count {
            switch updatedBodies[i].role {
            case .approaching(let pixelIndex):
                guard pixelIndex < ww.pixels.count else {
                    updatedBodies[i].role = .drifting
                    continue
                }
                let target = ww.pixels[pixelIndex].currentPosition
                updatedBodies[i] = WordmarkPhysics.seekStep(
                    body: updatedBodies[i], toward: target,
                    maxSpeed: WordmarkWorld.maxCarrierSpeed, dt: CGFloat(dtClamped)
                )
                if WordmarkPhysics.isWithinRadius(updatedBodies[i], of: target, radius: WordmarkWorld.pickupRadius) {
                    let ferryTarget: CGPoint
                    if case .assembling = ww.phase {
                        ferryTarget = ww.pixels[pixelIndex].slotPosition
                    } else {
                        // Eroding: generate scatter position now; store as new rubblePosition.
                        let scatter = WordmarkWorld.randomRubblePosition(
                            in: bounds, excluding: ww.wordmarkRect, brickSize: ww.brickSize
                        )
                        ww.pixels[pixelIndex].rubblePosition = scatter
                        ferryTarget = scatter
                    }
                    updatedBodies[i].role = .ferrying(pixelIndex: pixelIndex, targetPosition: ferryTarget)
                    ww.pixels[pixelIndex].state = .inTransit(carrierId: updatedBodies[i].id)
                    ww.pixels[pixelIndex].currentPosition = updatedBodies[i].position
                    ww.pixels[pixelIndex].displayOpacity = ww.brandOpacity

                }

            case .ferrying(let pixelIndex, let ferryTarget):
                guard pixelIndex < ww.pixels.count else {
                    updatedBodies[i].role = .drifting
                    continue
                }
                updatedBodies[i] = WordmarkPhysics.seekStep(
                    body: updatedBodies[i], toward: ferryTarget,
                    maxSpeed: WordmarkWorld.maxCarrierSpeed, dt: CGFloat(dtClamped)
                )
                // Pixel travels with the carrier.
                ww.pixels[pixelIndex].currentPosition = updatedBodies[i].position

                if WordmarkPhysics.isWithinRadius(updatedBodies[i], of: ferryTarget, radius: WordmarkWorld.depositRadius) {
                    switch ww.phase {
                    case .assembling, .holding:
                        ww.pixels[pixelIndex].state = .placed
                        ww.pixels[pixelIndex].currentPosition = ferryTarget
                        ww.pixels[pixelIndex].displayOpacity = ww.brandOpacity
                    case .eroding:
                        ww.pixels[pixelIndex].state = .rubble
                        ww.pixels[pixelIndex].currentPosition = ferryTarget
                        ww.pixels[pixelIndex].rubblePosition = ferryTarget
                        ww.pixels[pixelIndex].displayOpacity = WordmarkWorld.rubbleOpacity
                    }
                    updatedBodies[i].role = .drifting
                }

            case .drifting:
                break
            }
        }

        // 2. Assign new carriers (up to maxCarriers total active).
        let activeCount = updatedBodies.filter { $0.role != .drifting }.count
        let openSlots = WordmarkWorld.maxCarriers - activeCount

        if openSlots > 0 {
            let candidateIndices: [Int]
            switch ww.phase {
            case .assembling:
                candidateIndices = ww.pixels.indices.filter {
                    if case .rubble = ww.pixels[$0].state { return true }
                    return false
                }
            case .eroding:
                candidateIndices = ww.pixels.indices.filter {
                    if case .placed = ww.pixels[$0].state { return true }
                    return false
                }
            case .holding:
                candidateIndices = []
            }

            if !candidateIndices.isEmpty {
                var pool = candidateIndices.shuffled()
                var remaining = openSlots
                for i in 0..<updatedBodies.count {
                    guard remaining > 0, !pool.isEmpty else { break }
                    guard updatedBodies[i].role == .drifting else { continue }
                    if Double.random(in: 0..<1) < WordmarkWorld.carrierProbability {
                        updatedBodies[i].role = .approaching(pixelIndex: pool.removeFirst())
                        remaining -= 1
                    }
                }
            }
        }

        // 3. Advance cycle phase.
        switch ww.phase {
        case .assembling:
            if ww.pixels.allSatisfy({ if case .placed = $0.state { return true }; return false }) {
                ww.phase = .holding(elapsed: 0)
            }
        case .holding(let elapsed):
            let newElapsed = elapsed + dtClamped
            ww.phase = newElapsed >= ww.holdDuration ? .eroding : .holding(elapsed: newElapsed)
        case .eroding:
            if ww.pixels.allSatisfy({ if case .rubble = $0.state { return true }; return false }) {
                // Re-scatter rubble positions for next assembly.
                for i in 0..<ww.pixels.count {
                    let pos = WordmarkWorld.randomRubblePosition(
                        in: bounds, excluding: ww.wordmarkRect, brickSize: ww.brickSize
                    )
                    ww.pixels[i].rubblePosition = pos
                    ww.pixels[i].currentPosition = pos
                }
                ww.phase = .assembling
            }
        }

        return (ww, updatedBodies)
    }

    // MARK: - Helpers

    static func randomRubblePosition(in bounds: CGRect, excluding rect: CGRect, brickSize: CGFloat) -> CGPoint {
        let margin = brickSize
        let safe = bounds.insetBy(dx: margin, dy: margin)
        guard safe.width > 0, safe.height > 0 else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        // Expand exclusion zone by one brick so rubble doesn't overlap wordmark edge.
        let exclusion = rect.insetBy(dx: -margin, dy: -margin)
        for _ in 0..<100 {
            let x = CGFloat.random(in: safe.minX...safe.maxX)
            let y = CGFloat.random(in: safe.minY...safe.maxY)
            let candidate = CGRect(x: x, y: y, width: brickSize, height: brickSize)
            if !exclusion.intersects(candidate) {
                return CGPoint(x: x, y: y)
            }
        }
        // Fallback: corner area outside wordmark.
        return CGPoint(
            x: safe.minX + CGFloat.random(in: 0...max(brickSize * 3, safe.width * 0.1)),
            y: safe.minY + CGFloat.random(in: 0...max(brickSize * 3, safe.height * 0.1))
        )
    }
}
