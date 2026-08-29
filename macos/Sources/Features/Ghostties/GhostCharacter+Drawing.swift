import SwiftUI
import GhosttiesCore

/// SwiftUI rendering support for `GhostCharacter`.
///
/// Split out of `Models/GhostCharacter.swift` so that enum, which is
/// otherwise pure data, can move into `GhosttiesCore` without dragging
/// SwiftUI through `Project`'s dependency graph.
extension GhostCharacter {
    /// Render the pixel grid as a SwiftUI `Path` within the given rectangle.
    ///
    /// Builds the path from a cached unit-square (1×1) path via
    /// `CGAffineTransform` scaling — benchmarked at the real 14×14 render size
    /// with the real `.blinky` grid (108 filled cells): building the path from
    /// scratch every call costs 7.862 µs vs `Circle()`'s 0.030 µs (264×).
    /// Reusing a cached unit path and scaling it is ~9.5× cheaper and has no
    /// behavior change — same filled cells, same crisp-at-any-size rendering.
    func drawPath(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let unit = Self.unitPaths[self] ?? Path()
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)
        return unit.applying(transform)
    }

    /// One 1×1 (unit square) `Path` per character, built once from `pixelGrid` —
    /// the basis `drawPath(in:)` scales via `CGAffineTransform` on every call
    /// instead of rebuilding ~108 `addRect` calls from scratch each time.
    fileprivate static let unitPaths: [GhostCharacter: Path] = {
        var paths: [GhostCharacter: Path] = [:]
        for character in GhostCharacter.allCases {
            let grid = character.pixelGrid
            let rows = grid.count
            let cols = grid.first?.count ?? 0
            guard rows > 0, cols > 0 else {
                paths[character] = Path()
                continue
            }
            let cellW = 1.0 / CGFloat(cols)
            let cellH = 1.0 / CGFloat(rows)
            var path = Path()
            for row in 0..<rows {
                for col in 0..<cols {
                    guard grid[row][col] else { continue }
                    let x = CGFloat(col) * cellW
                    let y = CGFloat(row) * cellH
                    path.addRect(CGRect(x: x, y: y, width: cellW, height: cellH))
                }
            }
            paths[character] = path
        }
        return paths
    }()
}
