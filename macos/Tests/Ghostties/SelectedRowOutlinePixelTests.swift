import AppKit
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// The resting selected session row, rendered offscreen (card 06, "Drawn
/// outline"): a 1pt `inkSecondary` outline at 0.4 around the row, the
/// selected-row tint inside it, and no stripe on the leading edge.
///
/// Appearance is pinned to Aqua (pixel tests otherwise follow the system's dark
/// mode) and the chrome and tint are read from the same tokens the row draws,
/// so the expectations move with the tokens. Thresholds are derived, not
/// tuned: the stroke is 1pt, so the darkening integrated across the outer 3pt
/// of an edge is `1pt * 0.4 * (tinted chrome - inkSecondary)` whatever the
/// backing scale (at 2x it is two full pixels, at 1x two half pixels). The
/// band is `bandTolerance` either side of that. If the builder's render
/// measures outside it, report the measured margin; do not edit these.
@MainActor
struct SelectedRowOutlinePixelTests {
    private let width: CGFloat = 220
    private let inset: CGFloat = 10
    private let bandTolerance = 0.25
    private let tintTolerance = 0.02

    // MARK: - Harness

    private struct Harness: View {
        @FocusState private var focus: Bool
        @State private var name = ""
        var body: some View {
            RecentsRowView(
                session: AgentSession(
                    id: UUID(uuidString: "9B2A6E10-1234-4A11-8B00-0000000000EE")!,
                    name: "Claude Code 6", templateId: AgentTemplate.claudeCode.id,
                    projectId: UUID(), sortOrder: 0, lastActiveAt: Date(), lastOutputAt: Date(),
                    isNamePinned: true, ghostCharacter: .hex
                ),
                projectName: "atlas-api",
                indicatorState: .inactive,
                isActive: true,
                editingName: $name,
                isRenameFocused: $focus,
                onTap: {}
            )
            .equatable()
        }
    }

    private struct Render {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        /// The row's rect in points, top-left origin.
        let row: CGRect
    }

    private func render() throws -> Render {
        try withDials({ $0.set(0.0, forKey: SidebarDialTuning.lightGlassKeys.chromaticIntensity) }) {
            let rowHeight = SidebarDialTuning.rowHeight()
            let height = rowHeight + 2 * inset
            let chrome = try #require(ChromeTheme.ghostties(.light).chrome.usingColorSpace(.sRGB))
            let hosting = NSHostingView(rootView: Harness()
                .padding(.horizontal, inset)
                .padding(.vertical, inset)
                .environmentObject(SidebarWidthModel(width: width))
                .environmentObject(SessionCoordinator())
                .frame(width: width, height: height, alignment: .top)
                .background(Color(nsColor: chrome)))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return Render(
                rep: rep, scale: CGFloat(rep.pixelsWide) / width,
                row: CGRect(x: inset, y: inset, width: width - 2 * inset, height: rowHeight)
            )
        }
    }

    // MARK: - Pixels

    private typealias RGB = (r: Double, g: Double, b: Double)

    private func rgb(_ c: NSColor) throws -> RGB {
        let s = try #require(c.usingColorSpace(.sRGB))
        return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }

    private func pixel(_ r: Render, x: CGFloat, y: CGFloat) throws -> RGB {
        // Raw bytes, not `colorAt`: `cacheDisplay` tags the bitmap with the display
        // profile, and converting back to sRGB shifts every value (bare chrome reads
        // 0.9504 against the token's 0.9412). The bytes are the sRGB values the row drew.
        let px = Int(x * r.scale), py = Int(y * r.scale)
        let rep = r.rep
        try #require(px >= 0 && px < rep.pixelsWide && py >= 0 && py < rep.pixelsHigh, "no pixel at \(x), \(y)")
        let data = try #require(rep.bitmapData)
        let o = py * rep.bytesPerRow + px * (rep.bitsPerPixel / 8)
        return (Double(data[o]) / 255, Double(data[o + 1]) / 255, Double(data[o + 2]) / 255)
    }

    private func lum(_ c: RGB) -> Double { (c.r + c.g + c.b) / 3 }

    private func over(_ top: RGB, alpha: Double, _ bottom: RGB) -> RGB {
        (top.r * alpha + bottom.r * (1 - alpha), top.g * alpha + bottom.g * (1 - alpha), top.b * alpha + bottom.b * (1 - alpha))
    }

    private var chrome: RGB { get throws { try rgb(ChromeTheme.ghostties(.light).chrome) } }

    /// The chrome under the row's resting tint (tint token at its own alpha).
    private var tinted: RGB {
        get throws {
            let tint = try #require(NSColor(SidebarColors.selectedRowTint(.light)).usingColorSpace(.sRGB))
            return over(try rgb(tint), alpha: Double(tint.alphaComponent), try chrome)
        }
    }

    /// Darkening below `reference`, in luminance, integrated in points along a
    /// line from `from` for `length`pt in `direction`.
    private func darkening(_ r: Render, from: CGPoint, direction: CGVector, length: CGFloat, reference: RGB) throws -> Double {
        let steps = Int(length * r.scale)
        var sum = 0.0
        for i in 0..<steps {
            let d = (CGFloat(i) + 0.5) / r.scale
            let p = try pixel(r, x: from.x + direction.dx * d, y: from.y + direction.dy * d)
            sum += lum(reference) - lum(p)
        }
        return sum / Double(r.scale)
    }

    /// What one 1pt inkSecondary stroke at 0.4 darkens, integrated, over the tinted row.
    private var expectedBand: Double {
        get throws {
            let ink2 = try rgb(ChromeTheme.ghostties(.light).inkSecondary)
            return SelectedRowOutline.strokeWidth * 0.4 * (lum(try tinted) - lum(ink2))
        }
    }

    // MARK: - Tests

    @Test("Resting selected row: a 0.4 inkSecondary outline on all four edges")
    func outlineAroundTheRow() throws {
        let r = try render()
        let expected = try expectedBand
        #expect(expected > 0.02, "the expectation must be measurable, or the gate is vacuous: \(expected)")
        let band: CGFloat = 3
        let mid = CGPoint(x: r.row.midX, y: r.row.midY)
        let edges: [(String, CGPoint, CGVector)] = [
            ("leading", CGPoint(x: r.row.minX, y: mid.y), CGVector(dx: 1, dy: 0)),
            ("trailing", CGPoint(x: r.row.maxX, y: mid.y), CGVector(dx: -1, dy: 0)),
            ("top", CGPoint(x: mid.x, y: r.row.minY), CGVector(dx: 0, dy: 1)),
            ("bottom", CGPoint(x: mid.x, y: r.row.maxY), CGVector(dx: 0, dy: -1)),
        ]
        for (name, start, dir) in edges {
            let got = try darkening(r, from: start, direction: dir, length: band, reference: try tinted)
            #expect(got >= expected * (1 - bandTolerance) && got <= expected * (1 + bandTolerance),
                    "\(name) edge: outline darkening \(got) outside \(expected) +/-\(Int(bandTolerance * 100))%")
        }
    }

    @Test("The outline is inside the row: nothing is drawn outside its bounds")
    func nothingOutsideTheRow() throws {
        let r = try render()
        let expected = try expectedBand
        let mid = CGPoint(x: r.row.midX, y: r.row.midY)
        let outside: [(String, CGPoint, CGVector)] = [
            ("leading", CGPoint(x: r.row.minX, y: mid.y), CGVector(dx: -1, dy: 0)),
            ("top", CGPoint(x: mid.x, y: r.row.minY), CGVector(dx: 0, dy: -1)),
            ("bottom", CGPoint(x: mid.x, y: r.row.maxY), CGVector(dx: 0, dy: 1)),
        ]
        for (name, start, dir) in outside {
            let got = try darkening(r, from: start, direction: dir, length: 3, reference: try chrome)
            #expect(abs(got) < expected * 0.1, "\(name): \(got) of ink outside the row; the outline is inset 1pt inside it")
        }
    }

    @Test("The tint sits inside the outline at the selected-row token")
    func tintInsideTheOutline() throws {
        let r = try render()
        let want = try tinted, bare = try chrome
        #expect(bare.r - want.r > 0.02, "the tint must be distinguishable from the chrome, or this is vacuous")
        // 3.5pt in from the top edge: past the 1.5pt outer edge of the stroke, above the text.
        for fx in [0.25, 0.5, 0.75] {
            let got = try pixel(r, x: r.row.minX + r.row.width * fx, y: r.row.minY + 3.5)
            #expect(abs(got.r - want.r) < tintTolerance && abs(got.g - want.g) < tintTolerance && abs(got.b - want.b) < tintTolerance,
                    "tint at \(fx): \(got) vs \(want)")
        }
    }

    @Test("No accent stripe: the leading edge is no darker than the others")
    func noLeadingStripe() throws {
        let r = try render()
        let mid = CGPoint(x: r.row.midX, y: r.row.midY)
        func edge(_ start: CGPoint, _ dir: CGVector) throws -> Double {
            try darkening(r, from: start, direction: dir, length: 3, reference: try tinted)
        }
        let leading = try edge(CGPoint(x: r.row.minX, y: mid.y), CGVector(dx: 1, dy: 0))
        let others = [
            try edge(CGPoint(x: r.row.maxX, y: mid.y), CGVector(dx: -1, dy: 0)),
            try edge(CGPoint(x: mid.x, y: r.row.minY), CGVector(dx: 0, dy: 1)),
            try edge(CGPoint(x: mid.x, y: r.row.maxY), CGVector(dx: 0, dy: -1)),
        ]
        #expect(leading <= others.max()! * 1.1, "leading edge \(leading) vs top/bottom/trailing \(others): a stripe")
    }
}
