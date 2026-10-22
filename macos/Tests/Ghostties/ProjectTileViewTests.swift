import AppKit
import Foundation
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// `ProjectTileView`, rendered: the project's icon when the store holds one,
/// the monogram when it doesn't, never an icon for `.monogram`, and the two
/// selected looks (an ink ring round an icon, an ink fill for a monogram).
/// The store is a private one over temp directories; the window is pinned
/// to `.aqua`, so ink is black whatever the system appearance.
@MainActor
@Suite(.serialized)
struct ProjectTileViewTests {
    private let size: CGFloat = 40
    /// The frame round the tile: room for the ring (2pt gap + 2pt ring).
    private let frame: CGFloat = 56
    private var tileMinX: CGFloat { (frame - size) / 2 }

    private struct Rig {
        let base: URL
        let store: ProjectIconStore
        let projectId = UUID()
    }

    /// A store holding a solid blue icon for `rig.projectId`, set the way
    /// "Choose…" sets it.
    private func rigWithIcon() async throws -> Rig {
        let base = try ProjectIconFixtures.makeRoot("tile-view")
        let store = ProjectIconStore(
            cacheDirectory: base.appendingPathComponent("cache", isDirectory: true),
            supportDirectory: base.appendingPathComponent("support", isDirectory: true)
        )
        let rig = Rig(base: base, store: store)
        let png = try ProjectIconFixtures.writePNG(base, "icon.png", pixels: 128)
        try await store.setOverride(projectId: rig.projectId, from: png)
        #expect(store.image(for: rig.projectId) != nil, "the store holds the icon")
        return rig
    }

    private func render(_ tile: ProjectTileView) throws -> NSBitmapImageRep {
        let view = tile
            .frame(width: frame, height: frame)
            .background(Color.white)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: frame, height: frame)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let scale = CGFloat(rep.pixelsWide) / frame
        let c = try #require(rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    /// The fixture icon's blue (0.2, 0.4, 0.8).
    private func isIconBlue(_ p: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        p.b - p.r > 0.4
    }

    private func isInk(_ p: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        p.r + p.g + p.b < 0.6
    }

    private func isWhite(_ p: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        p.r + p.g + p.b > 2.85
    }

    /// Inside the tile, clear of the monogram and the corner curve.
    private var fillPoint: (CGFloat, CGFloat) { (tileMinX + 4, frame / 2) }
    /// In the ring: 1pt inside its outer edge, beside the tile.
    private var ringPoint: (CGFloat, CGFloat) { (tileMinX - ProjectTileView.ringGap - ProjectTileView.ringWidth + 1, frame / 2) }

    private func tile(_ rig: Rig?, style: ProjectIconStyle? = nil, selected: Bool) -> ProjectTileView {
        ProjectTileView(
            projectId: rig?.projectId ?? UUID(), iconStyle: style, monogram: "A",
            size: size, textSize: 13, isSelectedProject: selected,
            iconStore: rig?.store ?? ProjectIconStore(
                cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )
    }

    @Test func drawsTheIconWhenTheStoreHasOne() async throws {
        let rig = try await rigWithIcon()
        defer { try? FileManager.default.removeItem(at: rig.base) }
        let rep = try render(tile(rig, selected: false))
        let fill = try pixel(rep, fillPoint.0, fillPoint.1)
        #expect(isIconBlue(fill), "tile fill \(fill) is not the icon's blue")
    }

    @Test func fallsBackToTheMonogramWithNoIcon() throws {
        let rep = try render(tile(nil, selected: false))
        let fill = try pixel(rep, fillPoint.0, fillPoint.1)
        #expect(!isIconBlue(fill) && !isWhite(fill), "tile fill \(fill) is not the monogram's tint")
    }

    @Test func monogramStyleNeverDrawsTheIcon() async throws {
        let rig = try await rigWithIcon()
        defer { try? FileManager.default.removeItem(at: rig.base) }
        let rep = try render(tile(rig, style: .monogram, selected: false))
        let fill = try pixel(rep, fillPoint.0, fillPoint.1)
        #expect(!isIconBlue(fill), "a .monogram tile drew the stored icon (\(fill))")
        // And the monogram is what's drawn there: its tint, not a blank.
        #expect(!isWhite(fill), "a .monogram tile drew nothing (\(fill))")
    }

    @Test func aSelectedIconGetsAnInkRingNotAFill() async throws {
        let rig = try await rigWithIcon()
        defer { try? FileManager.default.removeItem(at: rig.base) }
        let on = try render(tile(rig, selected: true))
        let off = try render(tile(rig, selected: false))
        #expect(isInk(try pixel(on, ringPoint.0, ringPoint.1)), "no ink ring beside a selected icon")
        #expect(isWhite(try pixel(off, ringPoint.0, ringPoint.1)), "a ring beside an unselected icon")
        #expect(isIconBlue(try pixel(on, fillPoint.0, fillPoint.1)), "a selected icon must stay the icon, not ink")
        // The gap between the ring and the tile stays clear.
        #expect(isWhite(try pixel(on, tileMinX - 1, frame / 2)), "the ring's gap is not clear")
    }

    @Test func aSelectedMonogramFillsWithInkAndHasNoRing() throws {
        let on = try render(tile(nil, selected: true))
        #expect(isInk(try pixel(on, fillPoint.0, fillPoint.1)), "a selected monogram is not filled with ink")
        #expect(isWhite(try pixel(on, ringPoint.0, ringPoint.1)), "a selected monogram drew a ring")
    }

    // MARK: - ProjectIconRefresh

    /// The store refreshes a project the first time it is seen and again only
    /// when its root or icon style changes.
    @Test func refreshRunsForNewOrChangedProjectsOnly() {
        let a = Project(name: "a", rootPath: "/tmp/a")
        var b = Project(name: "b", rootPath: "/tmp/b")
        #expect(ProjectIconRefresh.stale([a, b], refreshed: []).map(\.id) == [a.id, b.id], "first sight refreshes all")
        let seen = Set([a, b].map(ProjectIconRefresh.key))
        #expect(ProjectIconRefresh.stale([a, b], refreshed: seen).isEmpty, "nothing changed")
        b.iconStyle = .monogram
        #expect(ProjectIconRefresh.stale([a, b], refreshed: seen).map(\.id) == [b.id], "a style change refreshes")
        var movedA = a
        movedA.rootPath = "/tmp/a2"
        #expect(ProjectIconRefresh.stale([movedA], refreshed: seen).map(\.id) == [a.id], "a root change refreshes")
    }
}
