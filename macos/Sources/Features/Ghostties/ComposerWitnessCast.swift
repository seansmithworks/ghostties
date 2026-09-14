import Foundation

/// The composer-only "Witness" ghost cast (R14) — a single small ghost that
/// stands on the single-line composer card and reacts to finished events
/// only (open / project-resolve / Tab-accept / unknown-branch / launch).
///
/// Ported VERBATIM from the website's `GHOSTS_DATA` roster
/// (`web/assets/ghost-field.js`) — same 9 names, same hex colors, same
/// 12×12 `pixels` grids, char-for-char. `ComposerWitnessCastParityTests`
/// re-parses that file and asserts equality against this enum so the two
/// can never silently drift.
///
/// This is a NEW, composer-only cast — it does not touch, replace, or
/// reference `GhostCharacter` (the 24 app ghosts, `GhostCharacter.swift`,
/// still Pac-Man-shaped/named per `reference_pacman-trademark-exposure`).
/// See `ComposerWitness.swift` for the `GhostCharacter -> ComposerWitnessGhost`
/// mapping that lets a project's existing app ghost pick one of these 9.
enum ComposerWitnessGhost: String, CaseIterable {
    case flicker
    case shade
    case murk
    case haze
    case specter
    case wisp
    case phantom
    case ember
    case chill

    /// Hex color, verbatim from `GHOSTS_DATA[*].color` in `ghost-field.js`.
    var colorHex: String {
        switch self {
        case .flicker: return "#ff3b3b"
        case .shade: return "#ff8ec8"
        case .murk: return "#3ee8ff"
        case .haze: return "#ff9f3b"
        case .specter: return "#c34bff"
        case .wisp: return "#c8ff3b"
        case .phantom: return "#6b4bff"
        case .ember: return "#ff6b3b"
        case .chill: return "#3bffe8"
        }
    }

    /// 12×12 pixel grids, verbatim from `GHOSTS_DATA[*].pixels` in
    /// `ghost-field.js`. `X` = body cell (painted `colorHex`), `e` = eye
    /// cell (painted `eyeColorHex`; a blink turns the cell to `X` in the
    /// grid data itself — see `ComposerWitnessFrames.blinkGrid`), `l` =
    /// lit/highlight cell (painted `litColorHex`), `.` = empty.
    var pixels: [String] {
        switch self {
        case .flicker:
            return [
                "....X..X....",
                ".....XX.....",
                "..XXXXXXXX..",
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "XX.ee..ee.XX",
                "XX.ee..ee.XX",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "XX.XX..XX.XX"
            ]
        case .shade:
            return [
                "..XXXXXXXX..",
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "X.eeeeeeee.X",
                "X.eeeeeeee.X",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "XXXXXXXXXXXX",
                "XX.XX..XX.XX",
                "XX.XX..XX.XX"
            ]
        case .murk:
            return [
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "X.eXXXXXXe.X",
                "X.eeXXXXee.X",
                "X.XXXXXXXX.X",
                "XXXXXXXXXXXX",
                "X..........X",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                ".X.X.XX.X.X.",
                ".X.X.XX.X.X."
            ]
        case .haze:
            return [
                "...XXXXXX...",
                "..XlXXXXlX..",
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "XX.ee..ee.XX",
                "XXXXXXXXXXXX",
                "XlXXXXXXXXlX",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "XlXXXXXXXXlX",
                "XX.XX..XX.XX",
                "XX.XX..XX.XX"
            ]
        case .specter:
            return [
                ".....l......",
                ".....X......",
                ".....X......",
                "..XXXXXXXX..",
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "XX.eeeeee.XX",
                "XX.eeeeee.XX",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "XX.XX..XX.XX"
            ]
        case .wisp:
            return [
                "....XXXX....",
                "...XXXXXX...",
                "X.XXXXXXXX.X",
                "XX.X.ee.ee.X",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "...XXXXXX...",
                "...XXXXXX...",
                "..XXXXXXXX..",
                ".XX.XXXX.XX.",
                "....l..l....",
                ".....ll....."
            ]
        case .phantom:
            return [
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "XXXXXXXXXXXX",
                "X.ee....ee.X",
                "X.ee....ee.X",
                "XXXXXXXXXXXX",
                "X..XXXXXX..X",
                "XXXXXXXXXXXX",
                "X..X....X..X",
                "XXXXXXXXXXXX",
                "XX.XX..XX.XX",
                "XX.XX..XX.XX"
            ]
        case .ember:
            return [
                "..XXXXXXXX..",
                ".XXXXXXXXXX.",
                "XXXXXXXXXXXX",
                "XX.ee..ee.XX",
                "XXXXXXXXXXXX",
                "X.XXXXXXXX.X",
                "X.XllllllX.X",
                "X.XllllllX.X",
                "X.XXXXXXXX.X",
                "XXXXXXXXXXXX",
                "XX.XX..XX.XX",
                "X..X....X..X"
            ]
        case .chill:
            return [
                "...XXXXXX...",
                "..XXXXXXXX..",
                "X.XXXXXXXX.X",
                "XX.X.ee.ee.X",
                "X.XXXXXXXX.X",
                "XXXXXXXXXXXX",
                "X.X.X..X.X.X",
                "XXXXXXXXXXXX",
                "X.X.X..X.X.X",
                "XXXXXXXXXXXX",
                "XX.XX..XX.XX",
                ".X.X.XX.X.X."
            ]
        }
    }

    /// Verbatim from `EYE_COLOR` in `ghost-field.js`.
    static let eyeColorHex = "#0d0b12"
    /// Verbatim from `LIT_COLOR` in `ghost-field.js`.
    static let litColorHex = "#fffbe8"
}
