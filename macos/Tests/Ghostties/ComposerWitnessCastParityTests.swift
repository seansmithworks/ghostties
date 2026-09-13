import Foundation
import Testing
@testable import Ghostty

/// R14 plan §6 test 1 — the composer-only `ComposerWitnessGhost` cast must
/// stay byte-identical to the website's `GHOSTS_DATA` roster
/// (`web/assets/ghost-field.js`) it was ported from. Re-parses the JS file
/// at test time (rather than re-declaring the roster as a second Swift
/// literal to compare against) so a future edit to EITHER side that drifts
/// from the other fails here, not silently.
struct ComposerWitnessCastParityTests {
    private func repoRoot() -> URL {
        // #filePath: .../macos/Tests/Ghostties/ComposerWitnessCastParityTests.swift
        // Ghostties -> Tests -> macos -> repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    private func ghostFieldSource() throws -> String {
        let path = repoRoot().appendingPathComponent("web/assets/ghost-field.js")
        // `#require`: a missing/moved source file must fail this test
        // loudly, not silently pass with zero parsed ghosts.
        guard FileManager.default.fileExists(atPath: path.path) else {
            Issue.record("#require web/assets/ghost-field.js — file not found at \(path.path)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// One parsed `GHOSTS_DATA` entry — only the fields
    /// `ComposerWitnessGhost` actually ports (name, color, pixels).
    private struct ParsedGhost: Equatable {
        let name: String
        let colorHex: String
        let pixels: [String]
    }

    /// Regex-based extraction, scoped to the `GHOSTS_DATA = [ ... ];` array
    /// literal — deliberately naive (no full JS parser) since the source is
    /// hand-formatted, one object per ghost, `name`/`color`/`pixels` always
    /// present in that shape.
    private func parseGhostsData(from source: String) throws -> [ParsedGhost] {
        guard let arrayRange = source.range(of: "var GHOSTS_DATA = ["),
              let endRange = source.range(of: "\n  ];", range: arrayRange.upperBound..<source.endIndex) else {
            Issue.record("could not locate GHOSTS_DATA array literal in ghost-field.js")
            return []
        }
        let body = String(source[arrayRange.upperBound..<endRange.lowerBound])

        // Split into per-object chunks on the `name:` marker.
        let nameMarker = "name: \""
        var ghosts: [ParsedGhost] = []
        var searchRange = body.startIndex..<body.endIndex
        var nameRanges: [Range<String.Index>] = []
        while let range = body.range(of: nameMarker, range: searchRange) {
            nameRanges.append(range)
            searchRange = range.upperBound..<body.endIndex
        }

        for (index, nameRange) in nameRanges.enumerated() {
            let chunkEnd = index + 1 < nameRanges.count ? nameRanges[index + 1].lowerBound : body.endIndex
            let chunk = String(body[nameRange.lowerBound..<chunkEnd])

            guard let name = firstMatch(in: chunk, pattern: "name: \"([a-z]+)\""),
                  let color = firstMatch(in: chunk, pattern: "color: \"(#[0-9a-fA-F]{6})\"") else {
                continue
            }

            guard let pixelsStart = chunk.range(of: "pixels: [") else { continue }
            guard let pixelsEnd = chunk.range(of: "],", range: pixelsStart.upperBound..<chunk.endIndex) else { continue }
            let pixelsBlock = String(chunk[pixelsStart.upperBound..<pixelsEnd.lowerBound])
            let rows = allMatches(in: pixelsBlock, pattern: "\"([Xel.]{12})\"")

            ghosts.append(ParsedGhost(name: name, colorHex: color, pixels: rows))
        }
        return ghosts
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    /// red mutation: change one Swift cell in `ComposerWitnessGhost.flicker`'s
    /// `pixels` (e.g. flip a trailing `.` to `X`) — this test then fails on
    /// the pixel-grid comparison for `flicker`.
    @Test func castMatchesWebsiteGhostFieldVerbatim() throws {
        let source = try ghostFieldSource()
        let parsed = try parseGhostsData(from: source)
        #expect(parsed.count == ComposerWitnessGhost.allCases.count, "GHOSTS_DATA count drifted from ComposerWitnessGhost.allCases")

        for entry in parsed {
            guard let ghost = ComposerWitnessGhost(rawValue: entry.name) else {
                Issue.record("ghost-field.js has a ghost named \"\(entry.name)\" with no matching ComposerWitnessGhost case")
                continue
            }
            #expect(ghost.colorHex.lowercased() == entry.colorHex.lowercased(), "\(entry.name) colorHex drifted")
            #expect(ghost.pixels == entry.pixels, "\(entry.name) pixels drifted")
        }
    }

    /// red mutation: change `EYE_COLOR`/`LIT_COLOR` in `ghost-field.js`
    /// without updating `ComposerWitnessGhost.eyeColorHex`/`litColorHex`.
    @Test func eyeAndLitColorsMatchWebsiteConstants() throws {
        let source = try ghostFieldSource()
        guard let eye = firstMatch(in: source, pattern: "EYE_COLOR = \"(#[0-9a-fA-F]{6})\""),
              let lit = firstMatch(in: source, pattern: "LIT_COLOR = \"(#[0-9a-fA-F]{6})\"") else {
            Issue.record("could not locate EYE_COLOR/LIT_COLOR in ghost-field.js")
            return
        }
        #expect(ComposerWitnessGhost.eyeColorHex.lowercased() == eye.lowercased())
        #expect(ComposerWitnessGhost.litColorHex.lowercased() == lit.lowercased())
    }
}
