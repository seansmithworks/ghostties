import AppKit
import GhosttiesCore
import SwiftUI
import Testing
@testable import Ghostty

/// The selected-row mix at rest, on pixels (contract
/// `docs/plans/selected-row-mix-contract.md`, "Pixel gate"):
///
/// 1. The resting selected row: a 1pt `inkSecondary` outline at 0.4 round the
///    row over the selected-row tint, no leading stripe, in light AND dark.
/// 2. The active-group card in the sidebar list and on the rail: the flat
///    beta.26 fill (`RailProjectColumn.columnFill`, white at 45% light / 4%
///    dark over the chrome), keeping `inkSecondary` at AA on it.
///
/// Raw bitmap bytes, never `colorAt(...).usingColorSpace`: `cacheDisplay` tags
/// the bitmap with the display profile and the conversion shifts every value.
/// Appearance is pinned per test (pixel tests otherwise follow system dark
/// mode). Every expectation is derived from the tokens the views draw with
/// (`ChromeTheme.active`), so the gate moves with the tokens, not with a
/// hand-tuned number. If a build measures outside a band, report the
/// measurement; do not edit the band.
@MainActor
struct SelectedRowMixPixelTests {
    // MARK: - Pixels

    private typealias RGB = (r: Double, g: Double, b: Double)

    private struct Render {
        let rep: NSBitmapImageRep
        let scale: CGFloat
    }

    private func rgb(_ c: NSColor) throws -> RGB {
        let s = try #require(c.usingColorSpace(.sRGB))
        return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }

    private func pixel(_ r: Render, x: CGFloat, y: CGFloat) throws -> RGB {
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

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        WCAG.contrastRatio(
            WCAG.relativeLuminance(r: a.r, g: a.g, b: a.b),
            WCAG.relativeLuminance(r: b.r, g: b.g, b: b.b)
        )
    }

    private func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? .nan : s[s.count / 2]
    }

    private func appearance(_ scheme: ColorScheme) -> NSAppearance.Name { scheme == .dark ? .darkAqua : .aqua }

    private func theme(_ scheme: ColorScheme) -> ChromeTheme { ChromeTheme.active(scheme) }

    private func snapshot<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, background: NSColor? = nil) throws -> Render {
        let chrome = background ?? theme(scheme).chrome
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: chrome))
            .environment(\.colorScheme, scheme))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance(scheme))
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return Render(rep: rep, scale: CGFloat(rep.pixelsWide) / size.width)
    }

    // MARK: - 1. Resting selected row (light and dark)

    private struct RowHarness: View {
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

    private let rowWidth: CGFloat = 220
    private let rowInset: CGFloat = 10

    private func renderRow(_ scheme: ColorScheme) throws -> (Render, CGRect) {
        try withDials({ $0.set(0.0, forKey: SidebarDialTuning.lightGlassKeys.chromaticIntensity) }) {
            let rowHeight = SidebarDialTuning.rowHeight()
            let size = CGSize(width: rowWidth, height: rowHeight + 2 * rowInset)
            let view = RowHarness()
                .padding(.horizontal, rowInset)
                .padding(.vertical, rowInset)
                .environmentObject(SidebarWidthModel(width: rowWidth))
                .environmentObject(SessionCoordinator())
            let r = try snapshot(view, size: size, scheme: scheme, background: rowBase(scheme))
            return (r, CGRect(x: rowInset, y: rowInset, width: rowWidth - 2 * rowInset, height: rowHeight))
        }
    }

    /// What the resting row sits on. In dark the selected session's project
    /// always holds the group card, so the row renders over the card's fill
    /// flattened onto the chrome; light stays on the bare chrome.
    private func rowBase(_ scheme: ColorScheme) -> NSColor {
        let chrome = theme(scheme).chrome
        guard scheme == .dark, let c = chrome.usingColorSpace(.sRGB) else { return chrome }
        let a = CGFloat(RailProjectColumn.columnFillOpacity(scheme))
        return NSColor(srgbRed: c.redComponent * (1 - a) + a, green: c.greenComponent * (1 - a) + a,
                       blue: c.blueComponent * (1 - a) + a, alpha: 1)
    }

    /// The row's base under the resting tint.
    private func tinted(_ scheme: ColorScheme) throws -> RGB {
        let tint = try #require(NSColor(SidebarColors.selectedRowTint(scheme)).usingColorSpace(.sRGB))
        return over(try rgb(tint), alpha: Double(tint.alphaComponent), try rgb(rowBase(scheme)))
    }

    /// |change| from `reference` in luminance, integrated in points along a line.
    private func ink(_ r: Render, from: CGPoint, direction: CGVector, length: CGFloat, reference: RGB) throws -> Double {
        let steps = Int(length * r.scale)
        var sum = 0.0
        for i in 0..<steps {
            let d = (CGFloat(i) + 0.5) / r.scale
            sum += abs(lum(try pixel(r, x: from.x + direction.dx * d, y: from.y + direction.dy * d)) - lum(reference))
        }
        return sum / Double(r.scale)
    }

    /// One 1pt `inkSecondary` stroke at the resting 0.4 (contract: `restOutlineOpacity`;
    /// a literal so this suite measures on a build without `SelectedRowMix`), integrated.
    private func expectedStroke(_ scheme: ColorScheme) throws -> Double {
        0.4 * abs(lum(try rgb(theme(scheme).inkSecondary)) - lum(try tinted(scheme)))
    }

    @Test("Resting selected row: 0.4 inkSecondary outline on all four edges, light and dark", arguments: [ColorScheme.light, .dark])
    func restingRowOutline(scheme: ColorScheme) throws {
        let (r, row) = try renderRow(scheme)
        let want = try expectedStroke(scheme)
        #expect(want > 0.02, "\(scheme): the stroke must be measurable or the gate is vacuous (\(want))")
        let mid = CGPoint(x: row.midX, y: row.midY)
        let edges: [(String, CGPoint, CGVector)] = [
            ("leading", CGPoint(x: row.minX, y: mid.y), CGVector(dx: 1, dy: 0)),
            ("trailing", CGPoint(x: row.maxX, y: mid.y), CGVector(dx: -1, dy: 0)),
            ("top", CGPoint(x: mid.x, y: row.minY), CGVector(dx: 0, dy: 1)),
            ("bottom", CGPoint(x: mid.x, y: row.maxY), CGVector(dx: 0, dy: -1)),
        ]
        var got: [Double] = []
        for (name, start, dir) in edges {
            let v = try ink(r, from: start, direction: dir, length: 3, reference: try tinted(scheme))
            got.append(v)
            #expect(v >= want * 0.75 && v <= want * 1.25, "\(scheme) \(name) edge: \(v) outside \(want) +/-25%")
        }
        // No accent stripe: the leading edge carries no more ink than the others.
        #expect(got[0] <= got[1...].max()! * 1.1, "\(scheme): leading \(got[0]) vs \(Array(got[1...])): a stripe")
    }

    @Test("Resting selected row: the tint fills inside the outline at the token, light and dark", arguments: [ColorScheme.light, .dark])
    func restingRowTint(scheme: ColorScheme) throws {
        let (r, row) = try renderRow(scheme)
        let want = try tinted(scheme), bare = try rgb(rowBase(scheme))
        let gap = abs(lum(bare) - lum(want))
        // Half the tint's own step, capped at 0.02: a row drawn without the
        // tint always lands outside it (dark's flat card leaves a 0.017 step).
        let tolerance = min(0.02, gap / 2)
        #expect(gap > 0.01, "\(scheme): tint indistinguishable from its base (card in dark, chrome in light); gate vacuous (\(gap))")
        for fx in [0.25, 0.5, 0.75] {
            let got = try pixel(r, x: row.minX + row.width * fx, y: row.minY + 3.5)
            #expect(abs(got.r - want.r) < tolerance && abs(got.g - want.g) < tolerance && abs(got.b - want.b) < tolerance,
                    "\(scheme) tint at \(fx): \(got) vs \(want)")
        }
    }

    // MARK: - 2. Active-group card (sidebar list and rail, light and dark)

    private let atlas = Project(name: "atlas-api", rootPath: "~/Code/atlas-api")
    private let field = Project(name: "fieldwork", rootPath: "~/Code/fieldwork")
    private let listWidth: CGFloat = 260

    /// atlas-api holds a1 (selected), a2, a3; fieldwork holds f1.
    private func fixture() -> (WorkspaceStore, [AgentSession]) {
        let sessions = ["a1", "a2", "a3"].enumerated().map { i, n in
            AgentSession(name: n, templateId: AgentTemplate.claudeCode.id, projectId: atlas.id, sortOrder: i,
                         lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true, ghostCharacter: .hex)
        } + [AgentSession(name: "f1", templateId: AgentTemplate.claudeCode.id, projectId: field.id, sortOrder: 3,
                          lastActiveAt: Date(), lastOutputAt: Date(), isNamePinned: true, ghostCharacter: .hex)]
        let store = WorkspaceStore(
            testingProjects: [atlas, field], testingSessions: sessions,
            hasShownPinMigrationNotice: true, hasDismissedPinMigrationNotice: true
        )
        for s in sessions {
            store.updateSessionStatus(id: s.id, status: .running)
            store.updateIndicatorState(id: s.id, state: .idle)
        }
        return (store, sessions)
    }

    private func railWidth() throws -> CGFloat {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        let close = try #require(window.standardWindowButton(.closeButton))
        let zoom = try #require(window.standardWindowButton(.zoomButton))
        return WorkspaceLayout.collapsedRailWidth(
            zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX,
            leadingInset: close.convert(close.bounds, to: nil).minX
        )
    }

    /// The list (sidebar) or rail column with a1 selected, or with nothing
    /// selected (no card), same layout otherwise.
    private func renderGroups(rail: Bool, selected: Bool, scheme: ColorScheme) throws -> (Render, CGFloat) {
        try withDials({ $0.set(0.0, forKey: SidebarDialTuning.lightGlassKeys.chromaticIntensity) }) {
            let (store, sessions) = fixture()
            let coordinator = SessionCoordinator()
            coordinator.setActiveSessionIdForTesting(selected ? sessions[0].id : nil)
            let width = rail ? try railWidth() : listWidth
            let size = CGSize(width: width, height: 420 + (rail ? SidebarTray.reservedHeight(isVertical: true) : 0))
            let content: AnyView = rail
                ? AnyView(SidebarRailColumn().asRail(width: width).environmentObject(store).environmentObject(coordinator))
                : AnyView(RecentsListView(previewDragState: SessionDragState())
                    .environmentObject(store).environmentObject(coordinator)
                    .environmentObject(SidebarWidthModel(width: width)))
            return (try snapshot(content, size: size, scheme: scheme), width)
        }
    }

    private struct CardProbe {
        /// Card lift over the bare render, luminance, median over the card's lower body.
        let lift: Double
        /// The card's colour under the header (its top fifth, below the edge), median.
        let top: RGB
        let runHeight: CGFloat
    }

    /// Down the line at `x`: the longest run where the selected render differs
    /// from the unselected one is the card (it holds the selected row; the
    /// rest of the run is card over chrome). Lift is read on its lower 40%
    /// (the unselected rows a2, a3, 4pt clear of the bottom edge); the top
    /// colour on its 6-20% band (the header, clear of the top edge).
    private func probeCard(_ on: Render, _ off: Render, x: CGFloat, height: CGFloat) throws -> CardProbe? {
        let n = Int(height * on.scale)
        var best: Range<Int>? = nil, start: Int? = nil
        for i in 0...n {
            let differs: Bool
            if i < n {
                let y = (CGFloat(i) + 0.5) / on.scale
                differs = abs(lum(try pixel(on, x: x, y: y)) - lum(try pixel(off, x: x, y: y))) > 0.008
            } else { differs = false }
            if differs, start == nil { start = i }
            if !differs, let s = start {
                if best == nil || (i - s) > best!.count { best = s..<i }
                start = nil
            }
        }
        guard let run = best, run.count > Int(60 * on.scale) else { return nil }
        let top = CGFloat(run.lowerBound) / on.scale, h = CGFloat(run.count) / on.scale
        var lifts: [Double] = []
        var y = top + h * 0.6
        while y < top + h - 4 {
            lifts.append(lum(try pixel(on, x: x, y: y)) - lum(try pixel(off, x: x, y: y)))
            y += 1 / on.scale
        }
        var tops: [RGB] = []
        y = top + h * 0.06
        while y < top + h * 0.2 {
            tops.append(try pixel(on, x: x, y: y))
            y += 1 / on.scale
        }
        let byLum = tops.sorted { lum($0) < lum($1) }
        return CardProbe(lift: median(lifts), top: byLum[byLum.count / 2], runHeight: h)
    }

    /// The card's body lift over the chrome, in luminance: white at
    /// `columnFillOpacity` (the flat beta.26 fill). 10% slack each side.
    private func liftBand(_ scheme: ColorScheme) throws -> ClosedRange<Double> {
        let chrome = lum(try rgb(theme(scheme).chrome))
        let lift = RailProjectColumn.columnFillOpacity(scheme) * (1 - chrome)
        return (lift * 0.9)...(lift * 1.1)
    }

    private func cardCase(rail: Bool, scheme: ColorScheme) throws {
        let label = "\(rail ? "rail" : "sidebar") \(scheme)"
        let (on, width) = try renderGroups(rail: rail, selected: true, scheme: scheme)
        let (off, _) = try renderGroups(rail: rail, selected: false, scheme: scheme)
        let height = CGFloat(on.rep.pixelsHigh) / on.scale
        // Sidebar: the card's trailing body, clear of row text. Rail: the
        // column's 4pt ring beside the 40pt tile and chips, 2pt in from its edge.
        let x = rail ? width / 2 + RailProjectTile.size(.rail) / 2 + 2 : listWidth * 0.72
        let probe = try #require(try probeCard(on, off, x: x, height: height), "\(label): no active-group card found down x=\(x)")
        let band = try liftBand(scheme)
        #expect(band.contains(probe.lift), "\(label): card lift \(probe.lift) outside the flat-fill band \(band)")
        // Muted text (project name, count, subtitles) stays AA on the card's brightest body.
        let ink2 = try rgb(theme(scheme).inkSecondary)
        let ratio = contrast(ink2, probe.top)
        #expect(ratio >= 4.5, "\(label): inkSecondary on the card's top \(probe.top) is \(ratio):1, below AA")
    }

    @Test("Active-group card in the sidebar list: the flat fill and AA for muted text", arguments: [ColorScheme.light, .dark])
    func sidebarCard(scheme: ColorScheme) throws {
        try cardCase(rail: false, scheme: scheme)
    }

    @Test("Active-group card (column) on the rail: the flat fill and AA for muted text", arguments: [ColorScheme.light, .dark])
    func railCard(scheme: ColorScheme) throws {
        try cardCase(rail: true, scheme: scheme)
    }
}
