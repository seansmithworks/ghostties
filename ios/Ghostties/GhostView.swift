import SwiftUI

/// The Mac app's 12×12 pixel ghost, filled with `color`, crisp at any size.
struct GhostView: View {
    var character: String?
    var size: CGFloat = 24
    var color: Color = Theme.ink

    var body: some View {
        let grid = character.flatMap { GhostGrids.all[$0] } ?? GhostGrids.all["blinky"] ?? []
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 12
            var path = Path()
            for (row, line) in grid.enumerated() {
                for (col, char) in line.enumerated() where char == "X" {
                    path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
