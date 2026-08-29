import Foundation

/// One of 24 pixel-art ghost characters assignable to a project.
///
/// Each case owns a 12×12 boolean grid that defines its silhouette.
/// `drawPath(in:)` (see `GhostCharacter+Drawing.swift`) renders the grid as
/// filled rectangles within a SwiftUI `Path`, producing crisp vector art at
/// any size. At a 20pt render size each "pixel" is ~1.67pt — sharp at @2x
/// Retina.
public enum GhostCharacter: String, CaseIterable, Codable {
    case blinky
    case pinky
    case inky
    case clyde
    case specter
    case wisp
    case phantom
    case shade
    case haunt
    case wraith
    case banshee
    case polter
    case ember
    case gloom
    case spike
    case drift
    case hex
    case chill
    case fang
    case flicker
    case mist
    case howl
    case jinx
    case dusk

    /// 12×12 boolean grid defining the ghost's silhouette.
    /// `true` = filled pixel, `false` = transparent.
    public var pixelGrid: [[Bool]] { Self.grids[self]! }

    /// Pre-computed grids for all characters (parsed once from compact string data).
    private static let grids: [GhostCharacter: [[Bool]]] = {
        var g: [GhostCharacter: [[Bool]]] = [:]
        g[.blinky] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX.XX..XX.XX
            X...X..X...X
            """)
        g[.pinky] = parseGrid("""
            ....XXXX....
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .X..XXXX..X.
            .X..XXXX..X.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXX..XX..XXX
            X..........X
            """)
        g[.inky] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XXX....XXX.
            .XXX....XXX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            X.XX.XX.XX.X
            X..X....X..X
            """)
        g[.clyde] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX..XXXX..XX
            XX..XXXX..XX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXX.XXXX.XXX
            X....XX....X
            """)
        g[.specter] = parseGrid("""
            ...XXXXXX...
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX..XXXX..XX
            X...XXXX...X
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX..XXXX..XX
            X....XX....X
            """)
        g[.wisp] = parseGrid("""
            ....XXXX....
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXX..XX..XXX
            XXX..XX..XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .XXXXXXXXXX.
            .XXXXXXXXXX.
            ..XX.XX.XX..
            ...X....X...
            """)
        g[.phantom] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XXX..X..XXXX
            XXX..X..XXXX
            XXXXXXXXXXXX
            XXXX....XXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            X.XXX..XXX.X
            X..X....X..X
            """)
        g[.shade] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XX..XXXX..XX
            XX..XXXX..XX
            XXXXX..XXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX.XXXXXX.XX
            X...X..X...X
            """)
        g[.haunt] = parseGrid("""
            ...XXXXXX...
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            X..XXXXXX..X
            X..XXXXXX..X
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXX..XX..XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXX..XX..XXX
            X..........X
            """)
        g[.wraith] = parseGrid("""
            ....XXXX....
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX..XXXX..XX
            XX..XXXX..XX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .XXXXXXXXXX.
            ..XXX..XXX..
            ...X....X...
            """)
        g[.banshee] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            X...XXXX...X
            X...XXXX...X
            XXXXXXXXXXXX
            XXX......XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX..XXXX..XX
            X....XX....X
            """)
        g[.polter] = parseGrid("""
            ...XXXXXX...
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XXX..XX..XXX
            XXX..XX..XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXX....XXXX
            X..........X
            """)
        g[.ember] = parseGrid("""
            ....XXXX....
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .XXXXXXXXXX.
            .XX.XXXX.XX.
            ..X..XX..X..
            .....XX.....
            """)
        g[.gloom] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX..XXXX..XX
            XX..XXXX..XX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            X.XX.XX.XX.X
            X..X....X..X
            """)
        g[.spike] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            X.XXXXXXXX.X
            X..XXXXXX..X
            X...XXXX...X
            """)
        g[.drift] = parseGrid("""
            .....XXXXX..
            ...XXXXXXXX.
            ..XXXXXXXXXX
            .XXXXXXXXXXX
            .XX..XX..XXX
            .XX..XX..XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXX.
            .XXXX..XXX..
            ...XX....X..
            """)
        g[.hex] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX.XX..XX.XX
            XX.XX..XX.XX
            XXXXXXXXXXXX
            XXX.XX.XXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .X.XX..XX.X.
            ....X..X....
            """)
        g[.chill] = parseGrid("""
            ....XXXX....
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XXX..XX..XXX
            XXX..XX..XXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .XXXXXXXXXX.
            ..XXXXXXXX..
            ....XXXX....
            """)
        g[.fang] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX.X....X.XX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX.XX..XX.XX
            X...X..X...X
            """)
        g[.flicker] = parseGrid("""
            .....XX.....
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            .XXXXXXXXXX.
            .XXXXXXXXXX.
            ..XXXXXXXX..
            ..XXXXXXXX..
            ...XX..XX...
            ....X..X....
            """)
        g[.mist] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XX..XXXX..XX
            XX..XXXX..XX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            .XXXXXXXXXX.
            ..XXX..XXX..
            ...XX..XX...
            """)
        g[.howl] = parseGrid("""
            ...XXXXXX...
            .XXXXXXXXXX.
            .XXXXXXXXXX.
            .XX..XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXX......XXX
            XX........XX
            XXX......XXX
            XXXXXXXXXXXX
            XX.XX..XX.XX
            X..........X
            """)
        g[.jinx] = parseGrid("""
            ...XXXXXX...
            ..XXXXXXXX..
            .XXXXXXXXXX.
            .XXX.XX..XX.
            .XXX.XX..XX.
            .XX..XX..XX.
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXX.XXXX.XXX
            X....XX....X
            """)
        g[.dusk] = parseGrid("""
            ..XXXXXXXX..
            .XXXXXXXXXX.
            XXXXXXXXXXXX
            XXX..XXXXXXX
            XX...XXXXXXX
            XXX..XXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XXXXXXXXXXXX
            XX..XXXX..XX
            X....XX....X
            """)
        return g
    }()

    /// Parse a compact grid string ("X" = filled, "." = empty) into a boolean matrix.
    private static func parseGrid(_ str: String) -> [[Bool]] {
        str.split(separator: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).map { $0 == "X" }
        }
    }

    /// Pick a random ghost not present in `used`. Once all 24 are already in
    /// use, degrades to a deterministic least-used round-robin (ties broken by
    /// `allCases` order) instead of a uniform random pick — a uniform pick
    /// over all 24 would include visible duplicates and get uniformly worse
    /// forever as the list (`sessions`/`projects`) keeps growing.
    ///
    /// `used` is a multiset (duplicates preserved), not a `Set` — the
    /// duplicate counts are exactly what the round-robin fallback needs to
    /// find the least-used ghost once every ghost is taken at least once.
    public static func randomUnused(excluding used: [GhostCharacter]) -> GhostCharacter {
        let usedSet = Set(used)
        let available = allCases.filter { !usedSet.contains($0) }
        if let pick = available.randomElement() {
            return pick
        }
        let counts = Dictionary(grouping: used, by: { $0 }).mapValues(\.count)
        return allCases.min { lhs, rhs in
            (counts[lhs] ?? 0) < (counts[rhs] ?? 0)
        } ?? allCases[0]
    }
}
