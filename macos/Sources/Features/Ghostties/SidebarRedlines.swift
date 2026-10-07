import AppKit
import SwiftUI

// MARK: - Redlines (DEBUG-only spacing overlay)
//
// A Figma-style redline layer over the whole workspace, toggled by the
// inspector's "Redlines" control (`SidebarDialTuning.redlinesKey`). Every
// band is MEASURED from real frames — AppKit card frames and SwiftUI frames
// reported through `redlineFrame(_:)` — never echoed from a dial value, so a
// gap nobody configured shows up as a band with its true size. Margins (space
// outside a box) are pink, padding (space inside a box) is blue.
//
// Release compiles the tags to nothing and has no overlay; only the tag ids
// and the no-op modifier below exist outside DEBUG.

/// Ids the sidebar's views report their frames under.
enum RedlineID {
    /// The list column's content, before any padding.
    static let listContent = "list.content"
    /// The list column inside the window margin, after the content paddings.
    static let listInner = "list.inner"
    /// The scrolling list's viewport.
    static let listViewport = "list.viewport"
    /// Both tray capsules together, before the tray's outer margins.
    static let trayGroup = "tray.group"
    /// One tray capsule (its glass); its content is `<id>.content`.
    static func trayPill(_ group: String) -> String { "tray.pill.\(group)" }
    /// One session row, after its own padding; its content is `<id>.content`.
    static func row(_ id: UUID) -> String { "row.\(id.uuidString)" }
}

extension View {
    /// Reports this view's frame to the DEBUG Redlines overlay under `id`
    /// while Redlines is on. A no-op in Release, or when `id` is nil.
    @ViewBuilder
    func redlineFrame(_ id: String?) -> some View {
        #if DEBUG
        if let id {
            modifier(RedlineFrameReporter(id: id))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG

/// One container's reported SwiftUI frames, in its sidebar hosting view's
/// coordinates (SwiftUI `.global`: top-left origin). One per window, injected
/// at the sidebar root, so two windows never overwrite each other's rows.
@MainActor
final class RedlineRegistry {
    private(set) var rects: [String: CGRect] = [:]
    /// Called (coalesced, next run-loop turn) after any frame changes.
    var onChange: (() -> Void)?
    private var changeScheduled = false

    func set(_ id: String, _ rect: CGRect) {
        guard rects[id] != rect else { return }
        rects[id] = rect
        scheduleChange()
    }

    func remove(_ id: String) {
        guard rects.removeValue(forKey: id) != nil else { return }
        scheduleChange()
    }

    private func scheduleChange() {
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.changeScheduled = false
            self.onChange?()
        }
    }
}

private struct RedlineRegistryKey: EnvironmentKey {
    static let defaultValue: RedlineRegistry? = nil
}

extension EnvironmentValues {
    /// The window's `RedlineRegistry`; nil outside a workspace sidebar.
    var redlineRegistry: RedlineRegistry? {
        get { self[RedlineRegistryKey.self] }
        set { self[RedlineRegistryKey.self] = newValue }
    }
}

/// Reports the modified view's `.global` frame while Redlines is on. The
/// reader sits in a background so toggling Redlines never changes the
/// content's identity (a row's hover or rename state survives).
private struct RedlineFrameReporter: ViewModifier {
    let id: String
    @AppStorage(SidebarDialTuning.redlinesKey, store: SidebarDialTuning.store) private var enabled = false
    @Environment(\.redlineRegistry) private var registry

    func body(content: Content) -> some View {
        content.background {
            if enabled, let registry {
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    Color.clear
                        .onAppear { registry.set(id, frame) }
                        .modifier(FrameChangeReporter(frame: frame) { registry.set(id, $0) })
                        .onDisappear { registry.remove(id) }
                }
            }
        }
    }
}

/// `onChange(of:)`'s two-parameter form where it exists (macOS 14); the app's
/// floor is macOS 13, which only has the one-parameter form.
private struct FrameChangeReporter: ViewModifier {
    let frame: CGRect
    let report: (CGRect) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: frame) { _, newFrame in report(newFrame) }
        } else {
            content.onChange(of: frame) { report($0) }
        }
    }
}

/// The overlay itself: a click-through view over the whole workspace that
/// draws the bands. Hidden unless Redlines is on.
final class RedlineOverlayView: NSView {
    let registry = RedlineRegistry()
    private weak var sidebarHost: NSView?
    private weak var cardHost: NSView?
    private weak var browserHost: NSView?

    init(sidebarHost: NSView, cardHost: NSView, browserHost: NSView) {
        self.sidebarHost = sidebarHost
        self.cardHost = cardHost
        self.browserHost = browserHost
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // Above the overlay sidebar (z 100) and the terminal's Metal layer.
        layer?.zPosition = 1000
        registry.onChange = { [weak self] in self?.needsDisplay = true }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Never takes a click, hover or scroll: everything passes through.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Re-reads the toggle and redraws.
    func refresh() {
        isHidden = !SidebarDialTuning.redlines()
        needsDisplay = true
    }

    // MARK: Drawing

    private enum Kind { case margin, padding }

    /// A band measured across x (`horizontal`: its width is the value) or
    /// across y (its height is the value).
    private struct Band {
        let rect: CGRect
        let kind: Kind
        let horizontal: Bool
        var labelled = true
        var showsZero = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, let sidebarHost, let cardHost else { return }
        var bands: [Band] = []

        let sidebar = convert(sidebarHost.bounds, from: sidebarHost)
        let sidebarVisible = sidebar.width > 1 && sidebarHost.alphaValue > 0.01 && !sidebarHost.isHidden
        let card = convert(cardHost.bounds, from: cardHost)
        var trailingCard = card
        if let browserHost, !browserHost.isHidden, browserHost.alphaValue > 0.01, browserHost.bounds.width > 1 {
            let browser = convert(browserHost.bounds, from: browserHost)
            bands.append(Band(rect: CGRect(x: card.maxX, y: card.minY, width: browser.minX - card.maxX, height: card.height), kind: .margin, horizontal: true))
            trailingCard = browser
        }
        // The sidebar shares the window with the card (pinned/rail) when
        // the card starts at or after its trailing edge.
        let sidebarOccupies = sidebarVisible && sidebar.maxX <= card.minX + 0.5

        // Window margin around the card, and the sidebar→card gap.
        if card.width > 1 {
            let span = CGRect(x: card.minX, y: card.minY, width: trailingCard.maxX - card.minX, height: card.height)
            bands.append(Band(rect: CGRect(x: span.minX, y: bounds.minY, width: span.width, height: span.minY - bounds.minY), kind: .margin, horizontal: false))
            bands.append(Band(rect: CGRect(x: span.minX, y: span.maxY, width: span.width, height: bounds.maxY - span.maxY), kind: .margin, horizontal: false))
            bands.append(Band(rect: CGRect(x: span.maxX, y: span.minY, width: bounds.maxX - span.maxX, height: span.height), kind: .margin, horizontal: true))
            let leadingEdge = sidebarOccupies ? sidebar.maxX : bounds.minX
            bands.append(Band(rect: CGRect(x: leadingEdge, y: card.minY, width: card.minX - leadingEdge, height: card.height), kind: .margin, horizontal: true))
        }

        if sidebarVisible {
            let rects = registry.rects.mapValues { $0.offsetBy(dx: sidebar.minX, dy: sidebar.minY) }
            // The next surface to the sidebar's right: the card while they
            // share the window, else the sidebar's own edge.
            let nextSurfaceX = sidebarOccupies ? card.minX : sidebar.maxX
            appendColumnBands(rects, sidebar: sidebar, nextSurfaceX: nextSurfaceX, into: &bands)
            appendTrayBands(rects, sidebar: sidebar, nextSurfaceX: nextSurfaceX, into: &bands)
            appendRowBands(rects, into: &bands)
        }

        for band in bands where band.kind == .margin { fill(band) }
        for band in bands where band.kind == .padding { fill(band) }
        for band in bands where band.labelled { label(band) }
    }

    private func appendColumnBands(_ rects: [String: CGRect], sidebar: CGRect, nextSurfaceX: CGFloat, into bands: inout [Band]) {
        guard let inner = rects[RedlineID.listInner], let content = rects[RedlineID.listContent] else { return }
        // Side bands only over the visible part of the column.
        let viewport = (rects[RedlineID.listViewport] ?? sidebar).intersection(sidebar)
        let visible = inner.intersection(viewport)
        if !visible.isNull, visible.height > 0 {
            let y = visible.minY, h = visible.height
            bands.append(Band(rect: CGRect(x: sidebar.minX, y: y, width: inner.minX - sidebar.minX, height: h), kind: .margin, horizontal: true))
            bands.append(Band(rect: CGRect(x: inner.maxX, y: y, width: nextSurfaceX - inner.maxX, height: h), kind: .margin, horizontal: true))
            bands.append(Band(rect: CGRect(x: inner.minX, y: y, width: content.minX - inner.minX, height: h), kind: .padding, horizontal: true))
            bands.append(Band(rect: CGRect(x: content.maxX, y: y, width: inner.maxX - content.maxX, height: h), kind: .padding, horizontal: true))
        }
        let top = CGRect(x: content.minX, y: inner.minY, width: content.width, height: content.minY - inner.minY)
        if top.intersects(viewport) || top.height < 0.25 {
            bands.append(Band(rect: top, kind: .padding, horizontal: false))
        }
        // List-to-tray gap: the list's bottom edge to the tray's top.
        if let tray = rects[RedlineID.trayGroup] {
            let listBottom = rects[RedlineID.listViewport]?.maxY ?? inner.maxY
            bands.append(Band(rect: CGRect(x: tray.minX, y: listBottom, width: tray.width, height: tray.minY - listBottom), kind: .margin, horizontal: false, showsZero: true))
        }
    }

    private func appendTrayBands(_ rects: [String: CGRect], sidebar: CGRect, nextSurfaceX: CGFloat, into bands: inout [Band]) {
        guard let group = rects[RedlineID.trayGroup] else { return }
        bands.append(Band(rect: CGRect(x: sidebar.minX, y: group.minY, width: group.minX - sidebar.minX, height: group.height), kind: .margin, horizontal: true))
        bands.append(Band(rect: CGRect(x: group.maxX, y: group.minY, width: nextSurfaceX - group.maxX, height: group.height), kind: .margin, horizontal: true))
        bands.append(Band(rect: CGRect(x: group.minX, y: group.maxY, width: group.width, height: sidebar.maxY - group.maxY), kind: .margin, horizontal: false))

        let pills = SidebarTrayGroup.allCases.compactMap { group -> (CGRect, CGRect)? in
            let id = RedlineID.trayPill(group.rawValue)
            guard let pill = rects[id], let content = rects[id + ".content"] else { return nil }
            return (pill, content)
        }
        // Every capsule's padding is drawn; only the first is labelled, so
        // the labels never pile up on the narrow group gap.
        for (index, (pill, content)) in pills.enumerated() {
            let labelled = index == 0
            bands.append(Band(rect: CGRect(x: pill.minX, y: pill.minY, width: content.minX - pill.minX, height: pill.height), kind: .padding, horizontal: true, labelled: labelled))
            bands.append(Band(rect: CGRect(x: content.maxX, y: pill.minY, width: pill.maxX - content.maxX, height: pill.height), kind: .padding, horizontal: true, labelled: false))
            bands.append(Band(rect: CGRect(x: content.minX, y: pill.minY, width: content.width, height: content.minY - pill.minY), kind: .padding, horizontal: false, labelled: labelled))
            bands.append(Band(rect: CGRect(x: content.minX, y: content.maxY, width: content.width, height: pill.maxY - content.maxY), kind: .padding, horizontal: false, labelled: false))
        }
        // Group gap between consecutive capsules, along whichever axis they stack.
        for (a, b) in zip(pills, pills.dropFirst()) {
            let first = a.0, second = b.0
            if abs(first.midY - second.midY) < abs(first.midX - second.midX) {
                let y = max(first.minY, second.minY), h = min(first.maxY, second.maxY) - y
                bands.append(Band(rect: CGRect(x: first.maxX, y: y, width: second.minX - first.maxX, height: h), kind: .margin, horizontal: true))
            } else {
                let x = max(first.minX, second.minX), w = min(first.maxX, second.maxX) - x
                bands.append(Band(rect: CGRect(x: x, y: first.maxY, width: w, height: second.minY - first.maxY), kind: .margin, horizontal: false))
            }
        }
    }

    /// Row leading/trailing padding for the first row fully inside the list's viewport.
    private func appendRowBands(_ rects: [String: CGRect], into bands: inout [Band]) {
        let viewport = rects[RedlineID.listViewport]
        let rows = rects.compactMap { key, outer -> (CGRect, CGRect)? in
            guard key.hasPrefix("row."), !key.hasSuffix(".content"), let content = rects[key + ".content"] else { return nil }
            if let viewport, outer.minY < viewport.minY - 0.5 || outer.maxY > viewport.maxY + 0.5 { return nil }
            return (outer, content)
        }
        guard let (outer, content) = rows.min(by: { $0.0.minY < $1.0.minY }) else { return }
        bands.append(Band(rect: CGRect(x: outer.minX, y: outer.minY, width: content.minX - outer.minX, height: outer.height), kind: .padding, horizontal: true))
        bands.append(Band(rect: CGRect(x: content.maxX, y: outer.minY, width: outer.maxX - content.maxX, height: outer.height), kind: .padding, horizontal: true))
    }

    private static let marginColor = NSColor(srgbRed: 1.0, green: 0.18, blue: 0.55, alpha: 0.38)
    private static let paddingColor = NSColor(srgbRed: 0.15, green: 0.5, blue: 1.0, alpha: 0.38)

    private func value(of band: Band) -> CGFloat {
        band.horizontal ? band.rect.width : band.rect.height
    }

    private func fill(_ band: Band) {
        let v = value(of: band)
        guard v >= 0.25 || band.showsZero else { return }
        var rect = band.rect.standardized
        // A zero band still marks where it sits: a 1pt line.
        if v < 0.25 {
            rect = band.horizontal
                ? CGRect(x: rect.minX - 0.5, y: rect.minY, width: 1, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY - 0.5, width: rect.width, height: 1)
        }
        (band.kind == .margin ? Self.marginColor : Self.paddingColor).setFill()
        rect.fill(using: .sourceOver)
    }

    private func label(_ band: Band) {
        let v = value(of: band)
        guard v >= 0.25 || band.showsZero else { return }
        let rounded = (v * 2).rounded() / 2
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pill = CGRect(
            x: band.rect.standardized.midX - size.width / 2 - 3,
            y: band.rect.standardized.midY - size.height / 2 - 1,
            width: size.width + 6,
            height: size.height + 2
        )
        // A dark pill with white text reads on light and dark chrome alike.
        let tint = band.kind == .margin ? NSColor(srgbRed: 0.55, green: 0.0, blue: 0.25, alpha: 0.9) : NSColor(srgbRed: 0.0, green: 0.22, blue: 0.55, alpha: 0.9)
        tint.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
        string.draw(at: CGPoint(x: pill.minX + 3, y: pill.minY + 1))
    }
}

#endif
