import Foundation
import Testing
@testable import Ghostty

/// Each fixture session runs its own canned transcript, so selecting a
/// different row shows a different terminal.
struct CaptureFixtureTranscriptTests {

    @Test func everyFixtureSessionHasItsOwnTranscriptWithAlignedBoxes() {
        let scripts = CaptureFixture.sessions.map { CaptureFixture.transcriptScript(forSessionId: $0.id) }
        let fallback = CaptureFixture.transcriptScript(forSessionId: nil)

        for (session, script) in zip(CaptureFixture.sessions, scripts) {
            #expect(CaptureFixture.sessionTranscripts[session.name]?.isEmpty == false, "\(session.name)")
            #expect(script != fallback, "\(session.name) fell back to the new-session transcript")
        }
        #expect(Set(scripts).count == CaptureFixture.sessions.count)

        // Every row of a box is the same cell width, or its right edge breaks.
        for script in scripts {
            var boxWidths: [Int] = []
            for line in Self.printedLines(script) {
                guard let first = line.first, "╭│╰".contains(first) else { continue }
                boxWidths.append(line.count)
                if first == "╰" {
                    #expect(Set(boxWidths).count == 1, "box rows differ in width: \(boxWidths)")
                    boxWidths = []
                }
            }
        }
    }

    /// The visible text of each `printf '…\n'` line, escape sequences removed.
    private static func printedLines(_ script: String) -> [String] {
        script.split(separator: "\n").compactMap { raw -> String? in
            guard raw.hasPrefix("printf '"), raw.hasSuffix("\\n'") else { return nil }
            let body = raw.dropFirst("printf '".count).dropLast("\\n'".count)
            return String(body).replacingOccurrences(of: #"\\033\[[0-9;]*m"#, with: "", options: .regularExpression)
        }
    }
}
