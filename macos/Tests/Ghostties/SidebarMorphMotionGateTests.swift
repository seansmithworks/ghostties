import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// The gates for the sidebar ⇄ rail keyframe pass (spec: D1, D2, defects 2–5,
/// the collapse/expand timings and Reduce Motion). Written before the fix:
/// each test asserts the spec value and is RED at the pre-fix head unless its
/// doc comment says it already holds. Pure timing/metric functions and view
/// model values only; no pixel captures.
///
/// Seams the builder must add (the tests below reference them by these exact
/// names, so they fail to compile until they exist):
/// - `RailCountBadge.style(selected:colorScheme:)` -> `RailCountBadge.Style { fill: Color, text: Color }`
/// - `MorphTrayReserve.height(progress:railWidth:)` -> CGFloat, continuous in progress
/// - `SidebarLabelCascade.indices(rowsPerSection:)` -> `[(header: Int, rows: [Int])]`, uncapped
/// - `WorkspaceLayout.sidebarLabelDriftTravel(appearing:reduceMotion:)` -> CGFloat
/// - `SidebarMorphMetrics.trailingClusterWidth(resting:progress:)` -> CGFloat
/// - `WorkspaceLayout.morphFadeWindow(element:direction:reduceMotion:)` -> `MorphFadeWindow`
///   (`start`, `end` in seconds; `scaleFrom`, `scaleTo`), with
///   `SidebarMorphElement { trailingCluster, names, badge }` and
///   `SidebarMorphDirection { collapse, expand }`
/// - `WorkspaceLayout.sidebarGeometryDuration(reduceMotion:timing:)` -> TimeInterval
@MainActor
struct SidebarMorphMotionGateTests {
    // MARK: - Helpers

    private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    private func luminance(_ color: Color) -> Double {
        let c = rgb(color)
        let lin = { (v: Double) in v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    private func close(_ a: Color, hex: UInt32, tolerance: Double = 0.03) -> Bool {
        let c = rgb(a)
        return abs(c.r - Double((hex >> 16) & 0xFF) / 255) <= tolerance
            && abs(c.g - Double((hex >> 8) & 0xFF) / 255) <= tolerance
            && abs(c.b - Double(hex & 0xFF) / 255) <= tolerance
    }

    // MARK: - D1: header height fixed at 40

    /// RED: the dials give 32 (sidebar, `max(30, 32)`) and 40 (rail), so the
    /// header reflows 32 -> 40 across the morph.
    @Test func headerHeightIsFortyAtEveryProgress() {
        let dials = withDials { SidebarMorphMetrics.Dials.current() }
        #expect(dials.sidebarHeaderHeight == 40, "sidebar header \(dials.sidebarHeaderHeight)")
        #expect(dials.railHeaderHeight == 40, "rail header \(dials.railHeaderHeight)")
        for p in [CGFloat(0), 0.5, 1] {
            let h = SidebarMorphMetrics.lerp(dials.sidebarHeaderHeight, dials.railHeaderHeight, p)
            #expect(h == 40, "header height at morph \(p): \(h)")
        }
    }

    // MARK: - D2: quiet-tint count badge

    /// RED (compile): needs the `RailCountBadge.style` seam. Fill is an
    /// opaque faint tint (light ~ ink 14% over #D3CDCA, dark ~ ink 12% over
    /// #3D3C3C), text is textSecondary (#636363 / #9A9A9A), and the fill is
    /// separable from the selected tile's ink fill.
    @Test func countBadgeIsTheQuietTint() {
        for selected in [false, true] {
            for (scheme, fillHex, textHex) in [
                (ColorScheme.light, UInt32(0xBAB4B1), UInt32(0x636363)),
                (ColorScheme.dark, UInt32(0x525252), UInt32(0x9A9A9A)),
            ] {
                let style = RailCountBadge.style(selected: selected, colorScheme: scheme)
                let tag = "selected=\(selected) \(scheme)"
                #expect(close(style.fill, hex: fillHex, tolerance: 0.04), "fill \(rgb(style.fill)) (\(tag))")
                #expect(close(style.text, hex: textHex), "text \(rgb(style.text)) (\(tag))")
                let ink = RailProjectTile.ink(scheme)
                #expect(contrast(style.fill, ink) >= 3, "fill vs the selected tile's ink: \(contrast(style.fill, ink)) (\(tag))")
                #expect(contrast(style.text, style.fill) >= 2.5, "number vs fill: \(contrast(style.text, style.fill)) (\(tag))")
            }
        }
    }

    // MARK: - Defect 2: tray reserve does not jump at collapse t=0

    /// RED (compile): `MorphTrayReserve` keys on `morph >= 0.5` and `morph`
    /// is written to its target at t=0, so the reserve jumps. The seam is
    /// continuous: the sidebar value at 0, the rail value at 1, in between
    /// strictly between.
    @Test func trayReserveFollowsProgressContinuously() {
        let railWidth = WorkspaceLayout.sidebarRailWidth
        let horizontal = SidebarTray.reservedHeight(isVertical: false, railWidth: railWidth)
        let vertical = SidebarTray.reservedHeight(isVertical: true, railWidth: railWidth)
        #expect(MorphTrayReserve.height(progress: 0, railWidth: railWidth) == horizontal, "reserve at t=0 must be the sidebar's")
        #expect(MorphTrayReserve.height(progress: 1, railWidth: railWidth) == vertical)
        let mid = MorphTrayReserve.height(progress: 0.5, railWidth: railWidth)
        #expect(mid > min(horizontal, vertical) && mid < max(horizontal, vertical), "mid-morph reserve \(mid) between \(horizontal) and \(vertical)")
        let early = MorphTrayReserve.height(progress: 0.05, railWidth: railWidth)
        #expect(abs(early - horizontal) < abs(vertical - horizontal) * 0.25, "reserve at 5% jumped to \(early)")
    }

    // MARK: - Defect 3: one continuous cascade

    /// RED: today `expandLabelDelay` is 100 + 12·min(i, 8) ms.
    @Test func expandDelayIs90Plus16CappedAtFive() {
        for i in 0..<10 {
            let expected = 0.090 + 0.016 * Double(min(i, 5))
            #expect(abs(WorkspaceLayout.expandLabelDelay(rowIndex: i) - expected) < 0.0005, "delay(\(i)) = \(WorkspaceLayout.expandLabelDelay(rowIndex: i))")
        }
    }

    /// RED: the expand fade is 140ms today.
    @Test func expandFadeDurationIs120ms() {
        #expect(abs(WorkspaceLayout.sidebarRowLabelExpandFadeDuration - 0.120) < 0.0005)
    }

    /// RED (compile): one index runs through every section and header, in
    /// reading order, instead of resetting per section.
    @Test func cascadeIndexIsContinuousAcrossSectionsAndHeaders() {
        let out = SidebarLabelCascade.indices(rowsPerSection: [2, 3, 1])
        #expect(out.map(\.header) == [0, 3, 7])
        #expect(out.map(\.rows) == [[1, 2], [4, 5, 6], [8]])
    }

    // MARK: - Defect 4: drift on collapse only

    /// RED (compile): expand 0, collapse 4pt (left), Reduce Motion never.
    @Test func labelDriftIsZeroOnExpandAndFourOnCollapse() {
        #expect(WorkspaceLayout.sidebarLabelDriftTravel(appearing: true, reduceMotion: false) == 0)
        #expect(WorkspaceLayout.sidebarLabelDriftTravel(appearing: false, reduceMotion: false) == -4)
        #expect(WorkspaceLayout.sidebarLabelDriftTravel(appearing: false, reduceMotion: true) == 0)
    }

    // MARK: - Defect 5: trailing count is not clipped mid-fade

    /// RED (compile): the count/chevron cluster keeps its resting width for
    /// the whole fade (0–60ms ~ progress 0 to 0.25).
    @Test func trailingClusterKeepsItsRestingWidthDuringTheFade() {
        for p in [CGFloat(0), 0.1, 0.25, 0.5] {
            #expect(SidebarMorphMetrics.trailingClusterWidth(resting: 36, progress: p) == 36, "clipped to \(SidebarMorphMetrics.trailingClusterWidth(resting: 36, progress: p)) at morph \(p)")
        }
    }

    // MARK: - Timings

    /// RED (compile): collapse count+chevron 0–60, names 0–90, badge 110–270
    /// with scale 0.9 -> 1.
    @Test func collapseTimings() {
        let cluster = WorkspaceLayout.morphFadeWindow(element: .trailingCluster, direction: .collapse, reduceMotion: false)
        #expect(abs(cluster.start - 0) < 0.0005 && abs(cluster.end - 0.060) < 0.0005, "cluster \(cluster.start)–\(cluster.end)")
        let names = WorkspaceLayout.morphFadeWindow(element: .names, direction: .collapse, reduceMotion: false)
        #expect(abs(names.start - 0) < 0.0005 && abs(names.end - 0.090) < 0.0005, "names \(names.start)–\(names.end)")
        let badge = WorkspaceLayout.morphFadeWindow(element: .badge, direction: .collapse, reduceMotion: false)
        #expect(abs(badge.start - 0.110) < 0.0005 && abs(badge.end - 0.270) < 0.0005, "badge \(badge.start)–\(badge.end)")
        #expect(badge.scaleFrom == 0.9 && badge.scaleTo == 1)
    }

    /// RED (compile): expand badge out 0–50ms.
    @Test func expandBadgeFadesOutIn50ms() {
        let badge = WorkspaceLayout.morphFadeWindow(element: .badge, direction: .expand, reduceMotion: false)
        #expect(abs(badge.start - 0) < 0.0005 && abs(badge.end - 0.050) < 0.0005, "badge \(badge.start)–\(badge.end)")
    }

    // MARK: - Reduce Motion

    /// RED (compile): geometry snaps (0); every fade is 120ms.
    @Test func reduceMotionSnapsGeometryAndFadesIn120ms() {
        for timing in [
            WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed),
            WorkspaceLayout.sidebarTransitionTiming(from: .collapsed, to: .pinned),
        ] {
            #expect(WorkspaceLayout.sidebarGeometryDuration(reduceMotion: true, timing: timing) == 0)
            #expect(WorkspaceLayout.sidebarGeometryDuration(reduceMotion: false, timing: timing) == timing.duration)
        }
        for element in [SidebarMorphElement.trailingCluster, .names, .badge] {
            for direction in [SidebarMorphDirection.collapse, .expand] {
                let w = WorkspaceLayout.morphFadeWindow(element: element, direction: direction, reduceMotion: true)
                #expect(abs((w.end - w.start) - 0.120) < 0.0005, "\(element) \(direction) fades \(w.end - w.start)")
            }
        }
    }

    /// Already GREEN: the existing Reduce Motion cross-fade is 120ms.
    @Test func reduceMotionCrossfadeAlreadyHolds() {
        let timing = WorkspaceLayout.sidebarTransitionTiming(from: .pinned, to: .collapsed)
        #expect(WorkspaceLayout.sidebarTransitionAlphaDuration(reduceMotion: true, timing: timing) == 0.12)
    }
}
