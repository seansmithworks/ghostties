import CoreGraphics

/// Pure carrier motion math for Phase C wordmark assembly/erosion.
///
/// No SwiftUI imports — all functions take plain CoreGraphics values so the
/// math is unit-testable without a host app.
enum WordmarkPhysics {

    /// Move `body` one step toward `target` at up to `maxSpeed` px/frame.
    ///
    /// `maxSpeed` is in px/frame at 60 fps. `dt` is wall-clock seconds.
    /// Motion decelerates naturally when close: the body moves `min(distance,
    /// maxSpeed * frameScale)` per tick, so it never overshoots the target.
    static func seekStep(
        body: GhostBody,
        toward target: CGPoint,
        maxSpeed: CGFloat,
        dt: CGFloat
    ) -> GhostBody {
        let dx = target.x - body.position.x
        let dy = target.y - body.position.y
        let distSq = dx * dx + dy * dy
        guard distSq > 1e-9 * 1e-9 else { return body }

        let dist = sqrt(distSq)
        let frameScale = CGFloat(min(dt, 1.0 / 30.0)) * 60.0
        let move = min(dist, maxSpeed * frameScale)
        let nx = dx / dist
        let ny = dy / dist

        var result = body
        result.position.x += nx * move
        result.position.y += ny * move
        return result
    }

    /// Returns true when `body`'s center is within `radius` of `point`.
    static func isWithinRadius(_ body: GhostBody, of point: CGPoint, radius: CGFloat) -> Bool {
        let dx = body.position.x - point.x
        let dy = body.position.y - point.y
        return dx * dx + dy * dy <= radius * radius
    }
}
