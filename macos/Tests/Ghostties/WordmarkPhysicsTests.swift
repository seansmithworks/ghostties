import XCTest
import CoreGraphics
import SwiftUI
@testable import Ghostty

final class WordmarkPhysicsTests: XCTestCase {
    private let eps: CGFloat = 1e-6

    // MARK: - WordmarkLayout

    func testTargetWidthThreshold() {
        // R18: pane width 333 → 333*0.6 = 199.8 < 200 → nil
        XCTAssertNil(WordmarkLayout.targetWidth(for: 333))
        // pane width 334 → 334*0.6 = 200.4 ≥ 200 → non-nil
        XCTAssertNotNil(WordmarkLayout.targetWidth(for: 334))
    }

    func testTargetWidthClamped() {
        // R18: max wordmark width is 600
        let tw = WordmarkLayout.targetWidth(for: 1200)
        XCTAssertNotNil(tw)
        XCTAssertEqual(tw!, 600, accuracy: eps)
    }

    func testLayoutReturnsNilForNarrowPane() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 400)
        XCTAssertNil(WordmarkLayout(paneBounds: narrow))
    }

    func testLayoutSlotCountMatchesFilledPixels() {
        // "GHOSTTIES" has 141 filled pixels across all letter grids.
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let layout = WordmarkLayout(paneBounds: bounds)
        XCTAssertNotNil(layout)
        XCTAssertEqual(layout!.slotPositions.count, 141)
    }

    func testLayoutIsDeterministic() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let a = WordmarkLayout(paneBounds: bounds),
              let b = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        XCTAssertEqual(a.slotPositions.count, b.slotPositions.count)
        for (pa, pb) in zip(a.slotPositions, b.slotPositions) {
            XCTAssertEqual(pa.x, pb.x, accuracy: eps)
            XCTAssertEqual(pa.y, pb.y, accuracy: eps)
        }
    }

    func testLayoutSlotsWithinWordmarkRect() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        let bs = layout.brickSize
        let rect = layout.wordmarkRect.insetBy(dx: -eps, dy: -eps)
        for slot in layout.slotPositions {
            XCTAssertTrue(rect.contains(CGPoint(x: slot.x, y: slot.y)),
                "Slot \(slot) outside wordmark rect \(layout.wordmarkRect)")
            XCTAssertTrue(rect.contains(CGPoint(x: slot.x + bs, y: slot.y + bs)),
                "Slot bottom-right outside wordmark rect")
        }
    }

    func testLayoutWordmarkCenteredHorizontally() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        XCTAssertEqual(layout.wordmarkRect.midX, bounds.midX, accuracy: 1.0)
    }

    func testLayoutWordmarkCenteredVertically() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        XCTAssertEqual(layout.wordmarkRect.midY, bounds.midY, accuracy: 1.0)
    }

    // MARK: - WordmarkPhysics seek motion

    func testSeekStepMovesAtMaxSpeed() {
        // Body 100 pt from target, maxSpeed 1.3, dt=1/60 → moves exactly 1.3 pt.
        let body = makeBody(x: 0, y: 0)
        let target = CGPoint(x: 100, y: 0)
        let result = WordmarkPhysics.seekStep(body: body, toward: target, maxSpeed: 1.3, dt: 1.0/60.0)
        XCTAssertEqual(result.position.x, 1.3, accuracy: eps)
        XCTAssertEqual(result.position.y, 0, accuracy: eps)
    }

    func testSeekStepDoesNotOvershooot() {
        // Body 0.5 pt from target → clamps to distance, ends at target.
        let body = makeBody(x: 99.5, y: 0)
        let target = CGPoint(x: 100, y: 0)
        let result = WordmarkPhysics.seekStep(body: body, toward: target, maxSpeed: 1.3, dt: 1.0/60.0)
        XCTAssertEqual(result.position.x, 100, accuracy: eps)
    }

    func testSeekStepAtTargetIsNoOp() {
        let body = makeBody(x: 50, y: 50)
        let target = CGPoint(x: 50, y: 50)
        let result = WordmarkPhysics.seekStep(body: body, toward: target, maxSpeed: 1.3, dt: 1.0/60.0)
        XCTAssertEqual(result.position.x, 50, accuracy: eps)
        XCTAssertEqual(result.position.y, 50, accuracy: eps)
    }

    func testSeekStepReachesTarget() {
        // Body 200 pt away at maxSpeed 1.3 should reach target within ceil(200/1.3)=154 frames.
        var body = makeBody(x: 0, y: 0)
        let target = CGPoint(x: 200, y: 0)
        for _ in 0..<154 {
            body = WordmarkPhysics.seekStep(body: body, toward: target, maxSpeed: 1.3, dt: 1.0/60.0)
        }
        XCTAssertEqual(body.position.x, 200, accuracy: eps)
    }

    func testIsWithinRadiusTrue() {
        let body = makeBody(x: 5, y: 0)
        XCTAssertTrue(WordmarkPhysics.isWithinRadius(body, of: .zero, radius: 10))
    }

    func testIsWithinRadiusFalse() {
        let body = makeBody(x: 15, y: 0)
        XCTAssertFalse(WordmarkPhysics.isWithinRadius(body, of: .zero, radius: 10))
    }

    // MARK: - Collision exemption (R11)

    func testCollisionExemptForApproachingAndDrifting() {
        // One approaching, one drifting, overlapping head-on → positions and velocities unchanged.
        let a = makeBody(x: 0, y: 0, dx: 0.4, dy: 0, role: .approaching(pixelIndex: 0))
        let b = makeBody(x: 18, y: 0, dx: -0.4, dy: 0, role: .drifting)
        let (a2, b2) = PhysicsCollision.resolvePair(a, b)
        XCTAssertEqual(a2.velocity.dx, a.velocity.dx, accuracy: eps)
        XCTAssertEqual(b2.velocity.dx, b.velocity.dx, accuracy: eps)
        XCTAssertEqual(a2.position.x, a.position.x, accuracy: eps)
        XCTAssertEqual(b2.position.x, b.position.x, accuracy: eps)
    }

    func testCollisionExemptForTwoFerrying() {
        // Two ferrying ghosts on intersecting paths pass through each other (AE3).
        let a = makeBody(x: 0, y: 0, dx: 0.4, dy: 0,
                         role: .ferrying(pixelIndex: 0, targetPosition: CGPoint(x: 200, y: 0)))
        let b = makeBody(x: 18, y: 0, dx: -0.4, dy: 0,
                         role: .ferrying(pixelIndex: 1, targetPosition: CGPoint(x: -200, y: 0)))
        let (a2, b2) = PhysicsCollision.resolvePair(a, b)
        XCTAssertEqual(a2.velocity.dx, a.velocity.dx, accuracy: eps)
        XCTAssertEqual(b2.velocity.dx, b.velocity.dx, accuracy: eps)
    }

    func testCollisionResolvesForTwoDriftingBodies() {
        // Two drifting bodies colliding head-on should exchange velocities (existing behavior).
        let a = makeBody(x: 0, y: 0, dx: 0.4, dy: 0, role: .drifting)
        let b = makeBody(x: 18, y: 0, dx: -0.4, dy: 0, role: .drifting)
        let (a2, b2) = PhysicsCollision.resolvePair(a, b)
        XCTAssertLessThan(a2.velocity.dx, 0)
        XCTAssertGreaterThan(b2.velocity.dx, 0)
    }

    // MARK: - WordmarkWorld carrier cap (R10b)

    func testCarrierCapNeverExceeds3() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        var ww = WordmarkWorld.initial(layout: layout, bounds: bounds, bodies: makeSevenBodies(in: bounds))
        var bodies = makeSevenBodies(in: bounds)

        for _ in 0..<1000 {
            let (newWW, newBodies) = ww.stepped(bodies: bodies, dt: 1.0/60.0, bounds: bounds)
            ww = newWW
            bodies = newBodies
            let carrierCount = bodies.filter { $0.role != .drifting }.count
            XCTAssertLessThanOrEqual(carrierCount, WordmarkWorld.maxCarriers)
        }
    }

    func testCarrierCapWhenAlreadyFull() {
        // With 3 carriers already active, no additional carriers should be assigned.
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        var bodies = makeSevenBodies(in: bounds)
        // Manually assign 3 carriers.
        bodies[0].role = .approaching(pixelIndex: 0)
        bodies[1].role = .approaching(pixelIndex: 1)
        bodies[2].role = .approaching(pixelIndex: 2)

        var pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            let rubblePos = CGPoint(x: CGFloat.random(in: 50...100), y: CGFloat.random(in: 50...100))
            return WordmarkPixel(
                index: idx, slotPosition: slot,
                rubblePosition: rubblePos, currentPosition: rubblePos,
                displayOpacity: WordmarkWorld.rubbleOpacity, state: .rubble
            )
        }
        // First 3 pixels are inTransit (claimed by the 3 carriers above).
        pixels[0].state = .inTransit(carrierId: bodies[0].id)
        pixels[1].state = .inTransit(carrierId: bodies[1].id)
        pixels[2].state = .inTransit(carrierId: bodies[2].id)

        let ww = WordmarkWorld(
            phase: .assembling, pixels: pixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (_, updatedBodies) = ww.stepped(bodies: bodies, dt: 1.0/60.0, bounds: bounds)
        let carrierCount = updatedBodies.filter { $0.role != .drifting }.count
        XCTAssertLessThanOrEqual(carrierCount, WordmarkWorld.maxCarriers)
    }

    func testNoCarriersAssignedWhenNoRubblePixels() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        let bodies = makeSevenBodies(in: bounds)  // all drifting
        // All pixels placed — nothing to pick up.
        let pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            WordmarkPixel(
                index: idx, slotPosition: slot,
                rubblePosition: slot, currentPosition: slot,
                displayOpacity: 0.70, state: .placed
            )
        }
        let ww = WordmarkWorld(
            phase: .assembling, pixels: pixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (_, updatedBodies) = ww.stepped(bodies: bodies, dt: 1.0/60.0, bounds: bounds)
        let carrierCount = updatedBodies.filter { $0.role != .drifting }.count
        XCTAssertEqual(carrierCount, 0)
    }

    // MARK: - WordmarkWorld cycle phases

    func testCycleTransitionsToHoldingWhenAllPixelsPlaced() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        // All pixels already placed.
        let pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            WordmarkPixel(
                index: idx, slotPosition: slot,
                rubblePosition: slot, currentPosition: slot,
                displayOpacity: 0.70, state: .placed
            )
        }
        let ww = WordmarkWorld(
            phase: .assembling, pixels: pixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (newWW, _) = ww.stepped(bodies: makeSevenBodies(in: bounds), dt: 1.0/60.0, bounds: bounds)
        if case .holding = newWW.phase {
            // OK
        } else {
            XCTFail("Expected .holding, got \(newWW.phase)")
        }
    }

    func testHoldingTransitionsToErodingAfterDuration() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        let pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            WordmarkPixel(
                index: idx, slotPosition: slot,
                rubblePosition: slot, currentPosition: slot,
                displayOpacity: 0.70, state: .placed
            )
        }
        // Start just below hold threshold.
        let holdDuration = 4.0
        var ww = WordmarkWorld(
            phase: .holding(elapsed: holdDuration - 0.01), pixels: pixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect,
            holdDuration: holdDuration
        )
        let (newWW, _) = ww.stepped(bodies: makeSevenBodies(in: bounds), dt: 1.0/60.0, bounds: bounds)
        if case .eroding = newWW.phase {
            // OK
        } else {
            XCTFail("Expected .eroding, got \(newWW.phase)")
        }
    }

    func testErodingTransitionsToAssemblingWhenAllRubble() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        // All pixels already rubble.
        let pixels = layout.slotPositions.enumerated().map { idx, slot -> WordmarkPixel in
            let rubblePos = CGPoint(x: 50, y: CGFloat(idx) * 2 + 50)
            return WordmarkPixel(
                index: idx, slotPosition: slot,
                rubblePosition: rubblePos, currentPosition: rubblePos,
                displayOpacity: WordmarkWorld.rubbleOpacity, state: .rubble
            )
        }
        let ww = WordmarkWorld(
            phase: .eroding, pixels: pixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (newWW, _) = ww.stepped(bodies: makeSevenBodies(in: bounds), dt: 1.0/60.0, bounds: bounds)
        if case .assembling = newWW.phase {
            // OK
        } else {
            XCTFail("Expected .assembling, got \(newWW.phase)")
        }
    }

    func testErodingRescattersRubbleOnReset() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        let slotPos = layout.slotPositions[0]
        // One pixel at its slot position (rubble at slot — unusual but valid for test).
        let pixel = WordmarkPixel(
            index: 0, slotPosition: slotPos,
            rubblePosition: slotPos, currentPosition: slotPos,
            displayOpacity: WordmarkWorld.rubbleOpacity, state: .rubble
        )
        let ww = WordmarkWorld(
            phase: .eroding, pixels: [pixel],
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (newWW, _) = ww.stepped(bodies: makeSevenBodies(in: bounds), dt: 1.0/60.0, bounds: bounds)
        // Rubble positions should now be scattered outside wordmark rect.
        let newPos = newWW.pixels[0].currentPosition
        let exclusion = layout.wordmarkRect.insetBy(dx: -layout.brickSize, dy: -layout.brickSize)
        XCTAssertFalse(
            exclusion.intersects(CGRect(x: newPos.x, y: newPos.y, width: layout.brickSize, height: layout.brickSize)),
            "Re-scattered rubble overlaps wordmark rect"
        )
    }

    func testDepositSetsPixelPlaced() {
        // A ferrying ghost within depositRadius of its target should deposit the pixel.
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        guard let layout = WordmarkLayout(paneBounds: bounds) else {
            return XCTFail("Layout should not be nil")
        }
        let slotPos = layout.slotPositions[0]
        // Ghost is 3 pt from slotPos (within depositRadius=8).
        var body = makeBody(x: slotPos.x + 3, y: slotPos.y)
        body.role = .ferrying(pixelIndex: 0, targetPosition: slotPos)

        let pixel = WordmarkPixel(
            index: 0, slotPosition: slotPos,
            rubblePosition: CGPoint(x: 50, y: 50),
            currentPosition: CGPoint(x: slotPos.x + 3, y: slotPos.y),
            displayOpacity: 0.70,
            state: .inTransit(carrierId: body.id)
        )
        let otherPixels = layout.slotPositions.dropFirst().enumerated().map { idx, slot -> WordmarkPixel in
            WordmarkPixel(
                index: idx + 1, slotPosition: slot,
                rubblePosition: CGPoint(x: 50, y: CGFloat(idx + 1) * 3 + 50),
                currentPosition: CGPoint(x: 50, y: CGFloat(idx + 1) * 3 + 50),
                displayOpacity: WordmarkWorld.rubbleOpacity, state: .rubble
            )
        }
        let ww = WordmarkWorld(
            phase: .assembling, pixels: [pixel] + otherPixels,
            brickSize: layout.brickSize, wordmarkRect: layout.wordmarkRect
        )
        let (newWW, _) = ww.stepped(bodies: [body], dt: 1.0/60.0, bounds: bounds)

        if case .placed = newWW.pixels[0].state {
            // OK
        } else {
            XCTFail("Expected pixel[0] to be .placed, got \(newWW.pixels[0].state)")
        }
        XCTAssertEqual(newWW.pixels[0].displayOpacity, newWW.brandOpacity, accuracy: eps)
    }

    // MARK: - Helpers

    private func makeBody(
        x: CGFloat, y: CGFloat,
        dx: CGFloat = 0, dy: CGFloat = 0,
        r: CGFloat = 10,
        role: GhostRole = .drifting
    ) -> GhostBody {
        GhostBody(
            id: UUID(),
            position: CGPoint(x: x, y: y),
            velocity: CGVector(dx: dx, dy: dy),
            radius: r,
            character: .blinky,
            tint: .secondary,
            role: role
        )
    }

    private func makeSevenBodies(in bounds: CGRect) -> [GhostBody] {
        let xs: [CGFloat] = [50, 100, 150, 200, 350, 400, 450]
        let ys: [CGFloat] = [50, 450, 100, 400, 150, 350, 250]
        return zip(xs, ys).map { x, y in makeBody(x: x, y: y) }
    }
}
