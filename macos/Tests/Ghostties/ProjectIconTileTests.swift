import XCTest
import SwiftUI
import AppKit
@testable import Ghostty

/// A project icon replaces the monogram inside the existing tile and
/// changes nothing else: the header, tile, name, chevron and count lay out
/// at the same frames with and without an icon, on the sidebar (morph 0) and
/// the rail (morph 1), selected or not. Frames come from the Redlines
/// registry; the icon's ink is checked in pixels so the test can't pass on a
/// tile that never drew it.
@MainActor
final class ProjectIconTileTests: XCTestCase {
    private let width: CGFloat = 260
    private let height: CGFloat = 60

    /// A solid red 128px icon.
    private func redIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 128, height: 128).fill()
        image.unlockFocus()
        return image
    }

    private struct Render {
        var frames: [String: CGRect]
        var bitmap: NSBitmapImageRep
        var scale: CGFloat
    }

    private func render(icon: NSImage?, selected: Bool, morph: CGFloat) -> Render {
        let registry = RedlineRegistry()
        return withDials({
            $0.set(true, forKey: SidebarDialTuning.redlinesKey)
        }) {
            let view = ProjectAccordionHeader(
                name: "harbor", monogram: "HA", count: 3, isCollapsed: false,
                isSelectedProject: selected, icon: icon, redlineID: "header.p", onToggle: {}
            )
            .environmentObject(SidebarWidthModel(width: width))
            .environment(\.sidebarMorphOverride, morph)
            .environment(\.redlineRegistry, registry)
            .frame(width: width, height: height)
            .background(Color.white)
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: view)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return Render(frames: registry.rects, bitmap: rep, scale: CGFloat(rep.pixelsWide) / hosting.bounds.width)
        }
    }

    func testIconLeavesEveryHeaderFrameUnchanged() throws {
        for morph: CGFloat in [0, 1] {
            for selected in [false, true] {
                let plain = render(icon: nil, selected: selected, morph: morph)
                let withIcon = render(icon: redIcon(), selected: selected, morph: morph)
                let label = "morph \(morph), selected \(selected)"
                let tile = try XCTUnwrap(plain.frames["header.p.tile"], "no tile frame in \(plain.frames.keys.sorted()) (\(label))")
                XCTAssertGreaterThan(tile.width, 0, label)
                XCTAssertEqual(Set(plain.frames.keys), Set(withIcon.frames.keys), label)
                for (key, rect) in plain.frames {
                    let other = try XCTUnwrap(withIcon.frames[key])
                    XCTAssertEqual(rect.minX, other.minX, accuracy: 0.01, "\(key) x (\(label))")
                    XCTAssertEqual(rect.minY, other.minY, accuracy: 0.01, "\(key) y (\(label))")
                    XCTAssertEqual(rect.width, other.width, accuracy: 0.01, "\(key) width (\(label))")
                    XCTAssertEqual(rect.height, other.height, accuracy: 0.01, "\(key) height (\(label))")
                }
            }
        }
    }

    /// Not vacuous: the icon is what the tile draws. A point inside the
    /// drawn shape, clear of the monogram's letters, is the icon's red;
    /// without an icon it is not.
    func testIconFillsTheTile() throws {
        let plain = render(icon: nil, selected: false, morph: 0)
        let withIcon = render(icon: redIcon(), selected: false, morph: 0)
        let tile = try XCTUnwrap(withIcon.frames["header.p.tile"])
        func sample(_ r: Render) -> NSColor? {
            r.bitmap.colorAt(x: Int(tile.midX * r.scale), y: Int((tile.midY - tile.height * 0.3) * r.scale))?.usingColorSpace(.sRGB)
        }
        let red = try XCTUnwrap(sample(withIcon))
        // Colour management shifts the pure red a little; red still leads.
        XCTAssertGreaterThan(red.redComponent - red.greenComponent, 0.4, "icon tile: \(red)")
        let mono = try XCTUnwrap(sample(plain))
        XCTAssertLessThan(abs(mono.redComponent - mono.greenComponent), 0.15, "monogram tile: \(mono)")
    }
}
