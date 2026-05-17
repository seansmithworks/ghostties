import CoreGraphics

// No SwiftUI imports — pure CoreGraphics math.

// File-local copy of GhostCharacter.parseGrid to avoid touching upstream-sensitive file.
// Source: GhostCharacter.swift — consolidate if parseGrid is ever made internal.
private func parseGrid(_ str: String) -> [[Bool]] {
    str.split(separator: "\n").map { line in
        line.trimmingCharacters(in: .whitespaces).map { $0 == "X" }
    }
}

// MARK: - Glyph data (8 rows × variable cols)

private let glyphG: [[Bool]] = parseGrid("""
    .XXX.
    X....
    X....
    X....
    X.XXX
    X...X
    X...X
    .XXX.
    """)

private let glyphH: [[Bool]] = parseGrid("""
    X...X
    X...X
    X...X
    XXXXX
    X...X
    X...X
    X...X
    X...X
    """)

private let glyphO: [[Bool]] = parseGrid("""
    .XXX.
    X...X
    X...X
    X...X
    X...X
    X...X
    X...X
    .XXX.
    """)

private let glyphS: [[Bool]] = parseGrid("""
    .XXXX
    X....
    X....
    .XXX.
    ....X
    ....X
    ....X
    XXXX.
    """)

private let glyphT: [[Bool]] = parseGrid("""
    XXXXX
    ..X..
    ..X..
    ..X..
    ..X..
    ..X..
    ..X..
    ..X..
    """)

private let glyphI: [[Bool]] = parseGrid("""
    XXX
    .X.
    .X.
    .X.
    .X.
    .X.
    .X.
    XXX
    """)

private let glyphE: [[Bool]] = parseGrid("""
    XXXXX
    X....
    X....
    XXXX.
    X....
    X....
    X....
    XXXXX
    """)

private func letterGrid(for letter: Character) -> [[Bool]] {
    switch letter {
    case "G": return glyphG
    case "H": return glyphH
    case "O": return glyphO
    case "S": return glyphS
    case "T": return glyphT
    case "I": return glyphI
    case "E": return glyphE
    default: return []
    }
}

// MARK: - Layout

private let wordmarkLetters: [Character] = Array("GHOSTTIES")
private let interLetterGap = 1  // columns between letters

/// Computes the slot positions and brick size for the "GHOSTTIES" wordmark.
///
/// All positions are top-left corners of filled brick cells in pane coordinates.
/// `init?(paneBounds:)` returns nil when the pane is narrower than the R18 minimum.
struct WordmarkLayout {
    let brickSize: CGFloat
    let slotPositions: [CGPoint]
    let wordmarkRect: CGRect

    init?(paneBounds: CGRect) {
        guard let tw = WordmarkLayout.targetWidth(for: paneBounds.width) else { return nil }

        let grids = wordmarkLetters.map { letterGrid(for: $0) }
        let rowCount = grids.first?.count ?? 0
        let totalLetterCols = grids.reduce(0) { $0 + ($1.first?.count ?? 0) }
        let totalCols = totalLetterCols + (wordmarkLetters.count - 1) * interLetterGap
        guard totalCols > 0, rowCount > 0 else { return nil }

        let bs = tw / CGFloat(totalCols)
        let wh = bs * CGFloat(rowCount)
        let ox = (paneBounds.width - tw) / 2
        let oy = (paneBounds.height - wh) / 2

        var slots: [CGPoint] = []
        var colOffset = 0
        for grid in grids {
            let colCount = grid.first?.count ?? 0
            for row in 0..<grid.count {
                for col in 0..<colCount {
                    guard grid[row][col] else { continue }
                    slots.append(CGPoint(
                        x: ox + CGFloat(colOffset + col) * bs,
                        y: oy + CGFloat(row) * bs
                    ))
                }
            }
            colOffset += colCount + interLetterGap
        }

        brickSize = bs
        slotPositions = slots
        wordmarkRect = CGRect(x: ox, y: oy, width: tw, height: wh)
    }

    /// Returns the wordmark target width for the given pane width, or nil if the
    /// pane is below the R18 minimum (200 pt wordmark at 60% pane width → pane ≥ 334 pt).
    static func targetWidth(for paneWidth: CGFloat) -> CGFloat? {
        let w = paneWidth * 0.6
        guard w >= 200 else { return nil }
        return min(w, 600)
    }
}
