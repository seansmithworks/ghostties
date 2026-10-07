import XCTest
import SwiftUI
@testable import Ghostty

/// Pixel coverage for `HistoryBrowserView`, rendered in light and dark the
/// same way `SessionRowGlyphSlotTests` does (appearance pinned on the
/// window, so the result doesn't follow the system setting).
@MainActor
final class HistoryBrowserRenderTests: XCTestCase {
    static let size = NSSize(width: 760, height: 460)

    /// ~12 invented sessions, newest first after sorting; a mix of
    /// inactive/archived and two pinned.
    static func fixture(now: Date = Date()) -> [HistoryEntry] {
        let rows: [(String, String, Double, Bool, Bool)] = [
            ("atlas-api", "migrate auth tokens", 2, false, true),
            ("harbor", "stripe webhook retry", 5, false, false),
            ("fieldwork", "offline sync spike", 26, false, false),
            ("lumen", "hero image crops", 50, true, false),
            ("orchard-web", "composer tab inserts space", 75, true, true),
            ("tidepool", "cart totals rounding", 100, true, false),
            ("harbor", "release notes draft", 150, true, false),
            ("atlas-api", "rate limit headers", 200, true, false),
            ("lumen", "job board scraper", 260, true, false),
            ("fieldwork", "map tile cache", 340, true, false),
            ("orchard-web", "case study: checkout", 420, true, false),
            ("tidepool", "flaky snapshot test", 520, true, false),
        ]
        return rows.enumerated().map { i, r in
            HistoryEntry(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i))!,
                projectName: r.0, title: r.1,
                lastActiveAt: now.addingTimeInterval(-r.2 * 3600 - 60),
                isArchived: r.3, isPinned: r.4
            )
        }
    }

    static func render(entries: [HistoryEntry], appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let view = HistoryBrowserView(entries: entries, onResume: { _ in }, onTogglePin: { _ in }, onClose: {})
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Number of pixels in the x-range (points) whose colour passes `test`.
    /// Assertions go by hue (blue-dominant / red-dominant), not exact RGB:
    /// the cached bitmap's colour space shifts exact values by ~30/255.
    private func count(_ rep: NSBitmapImageRep, xRange: ClosedRange<CGFloat>? = nil, where test: (NSColor) -> Bool) -> Int {
        let scale = CGFloat(rep.pixelsWide) / Self.size.width
        let xs = xRange.map { Int($0.lowerBound * scale)...min(Int($0.upperBound * scale), rep.pixelsWide - 1) } ?? 0...(rep.pixelsWide - 1)
        var n = 0
        for y in 0..<rep.pixelsHigh {
            for x in xs {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if test(c) { n += 1 }
            }
        }
        return n
    }

    /// The selection accent (#5B8DEF) is the only strongly blue ink.
    private let isAccentBlue: (NSColor) -> Bool = { $0.blueComponent - $0.redComponent > 0.3 }
    /// Archived amber is the only strongly warm ink.
    private let isAmber: (NSColor) -> Bool = { $0.redComponent - $0.blueComponent > 0.3 }

    func testRendersCardBackgroundSelectionBarAndArchivedAmberInBothAppearances() throws {
        var corners: [NSColor] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let rep = try XCTUnwrap(Self.render(entries: Self.fixture(), appearance: appearance))
            corners.append(try XCTUnwrap(rep.colorAt(x: rep.pixelsWide - 2, y: 2)?.usingColorSpace(.sRGB)))
            // The selection bar sits in the leading inset (x 12-15pt), one row tall.
            XCTAssertGreaterThan(count(rep, xRange: 8...20, where: isAccentBlue), 20, "selection bar (\(appearance))")
            XCTAssertEqual(count(rep, xRange: 20...200, where: isAccentBlue), 0, "no match emphasis with an empty query (\(appearance))")
            XCTAssertGreaterThan(count(rep, where: isAmber), 200, "archived amber (\(appearance))")
        }
        // Light card is light, dark card is dark.
        XCTAssertGreaterThan(corners[0].brightnessComponent, 0.9)
        XCTAssertLessThan(corners[1].brightnessComponent, 0.3)
    }

    func testEmptyAndPopulatedRendersDiffer() throws {
        let empty = try XCTUnwrap(Self.render(entries: [], appearance: .aqua))
        let full = try XCTUnwrap(Self.render(entries: Self.fixture(), appearance: .aqua))
        XCTAssertNotEqual(empty.tiffRepresentation, full.tiffRepresentation)
        XCTAssertEqual(count(empty, xRange: 8...20, where: isAccentBlue), 0, "no selection bar with no history")
    }
}
