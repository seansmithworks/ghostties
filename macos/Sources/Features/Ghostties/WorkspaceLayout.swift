import AppKit
import Foundation
import SwiftUI

/// Four-state sidebar visibility model.
///
/// - `pinned`: Sidebar open, terminal pushed right (floating card).
/// - `closed`: Sidebar hidden, terminal fills window flush.
/// - `overlay`: Sidebar floats on top of full-width terminal (hover-to-reveal).
/// - `collapsed`: Sidebar shown as a narrow icon-only rail (Flow 01, sidebar-presence).
///
/// `Codable` by `Int` raw value and persisted in `WorkspaceStore` — new cases
/// must always be APPENDED, never renumbered, or an old `workspace.json`
/// decodes into the wrong mode.
enum SidebarMode: Int, Codable {
    case pinned
    case closed
    case overlay
    case collapsed
}

/// Shared layout constants for the workspace sidebar.
enum WorkspaceLayout {
    /// Width of the sidebar panel (Flow 01: 220 → 244; option D,
    /// 2026-10-09: 256, the canvas card at 256 + the 8pt window margin).
    static let sidebarWidth: CGFloat = 256

    /// Minimum width of the collapsed icon-only rail — a floor, not the
    /// applied width. Sized only so the 40pt vertical tray pill (32pt
    /// buttons + 4pt pill padding each side) fits with breathing room. The
    /// applied width is `collapsedRailWidth(in:)` below, which hugs the
    /// window's traffic-light cluster (Sean, sidebar-presence review round
    /// 3: the fixed 128pt rail read too wide). Not drag-resizable, unlike
    /// `sidebarWidth`. Content (glyph rows, tray pill) stays centered in
    /// whatever width is applied.
    static let sidebarRailWidth: CGFloat = 60

    /// Pure width calculation for the collapsed rail: hugs the macOS
    /// traffic-light cluster — the cluster's rightmost edge (zoom button
    /// `maxX`) plus a trailing gap equal to its leading inset (close button
    /// `minX`), both in the same coordinate space, so the cluster sits
    /// visually centered in the rail. Native (AppKit-default) inset lands
    /// around ~94pt on macOS 26. Never returns less than `sidebarRailWidth`,
    /// so a narrow or unusual cluster never squeezes the tray pill.
    static func collapsedRailWidth(zoomButtonMaxX: CGFloat, leadingInset: CGFloat, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        max(sidebarRailWidth, zoomButtonMaxX + leadingInset + SidebarDialTuning.railExtraWidth(defaults: defaults))
    }

    /// Pure fullscreen check shared by `titlebarRowTopAnchorConstant(in:)`
    /// and `collapsedRailWidth(in:)` — both need to special-case fullscreen
    /// (no titlebar row, traffic lights hidden), and this factors the check
    /// out of the live `NSView`/`NSWindow` lookup so it's independently
    /// testable without a real window.
    static func isFullScreenLayout(styleMask: NSWindow.StyleMask) -> Bool {
        styleMask.contains(.fullScreen)
    }

    /// Live collapsed-rail width for the window containing `view`, derived
    /// from the real traffic-light button frames. Callers should recompute
    /// wherever `titlebarRowTopAnchorConstant(in:)` above is already
    /// recomputed — window attach, fullscreen enter/exit, and titlebar
    /// layout passes — since both derive from the same button geometry.
    /// In fullscreen (traffic lights hidden, mirroring
    /// `titlebarRowTopAnchorConstant`'s early return) returns the
    /// `sidebarRailWidth` floor directly rather than measuring hidden
    /// buttons. Also returns the floor before the window is on-screen or if
    /// the buttons aren't available (mirrors `titlebarRowTopAnchorConstant`'s
    /// guard, but returns a floor instead of nil since a rail width is
    /// always needed, even in the fallback).
    static func collapsedRailWidth(in view: NSView) -> CGFloat {
        if let styleMask = view.window?.styleMask, isFullScreenLayout(styleMask: styleMask) {
            return sidebarRailWidth
        }
        guard let win = view.window,
              let close = win.standardWindowButton(.closeButton),
              let zoom = win.standardWindowButton(.zoomButton),
              close.window === win, zoom.window === win else {
            return sidebarRailWidth
        }
        let closeInView = close.convert(close.bounds, to: view)
        let zoomInView = zoom.convert(zoom.bounds, to: view)
        return collapsedRailWidth(zoomButtonMaxX: zoomInView.maxX, leadingInset: closeInView.minX)
    }

    /// Width of the task-first sidebar panel (Concept F).
    /// Wider than `sidebarWidth` to accommodate the hero row's two-line typography.
    /// v0 feature toggle — selected via the `ghostties.sidebarViewMode` @AppStorage flag.
    static let taskSidebarWidth: CGFloat = 280

    /// Minimum width the user can drag the sidebar to (either view mode).
    /// First-pass value — tunable.
    static let sidebarMinWidth: CGFloat = 180

    /// Maximum width the user can drag the sidebar to (either view mode).
    /// First-pass value — tunable.
    static let sidebarMaxWidth: CGFloat = 480

    /// Width of the centered session composer overlay's card (Phase 3 of
    /// session-creation-unified). Wider than `sidebarWidth` since it floats
    /// free of the sidebar column instead of popping out of it.
    static let composerOverlayWidth: CGFloat = 360

    /// Shadow opacity for the centered composer card (shadow-only elevation, PR #132
    /// — with the scrim removed, the card's own shadow is the only thing
    /// separating it from the terminal, so it needs to read heavier than the
    /// old scrim-backed 0.20).
    static let composerModalShadowOpacity: Double = 0.30

    /// Shadow blur radius for the centered composer card. Paired with
    /// `composerModalShadowOpacity` above.
    static let composerModalShadowRadius: CGFloat = 24

    /// Shadow Y offset for the centered composer card. Paired with
    /// `composerModalShadowOpacity`/`composerModalShadowRadius` above.
    static let composerModalShadowYOffset: CGFloat = 8

    /// Breadcrumb project chip background, resting state (composer
    /// breadcrumb spec, Slice A). Named token rather than an ad-hoc
    /// `Color.secondary.opacity(0.15)` inlined at the call site (DESIGN.md
    /// review finding) — same rationale as `activeRowLight`/`activeRowDark`
    /// below: one place to retune the chip's surface color from.
    static let composerChipBackground = Color.secondary.opacity(0.15)

    /// Breadcrumb project chip background while its inline picker is open.
    /// Paired with `composerChipBackground` above.
    static let composerChipBackgroundActive = Color.secondary.opacity(0.25)

    /// Height reserved at top for window traffic light controls.
    static let titlebarSpacerHeight: CGFloat = 28

    /// Offset between traffic-light centerline and our toolbar row (toggle, +, title).
    /// Zero = exact alignment with traffic lights (Dia Browser style, confirmed correct).
    static let breathingRoomBelowChrome: CGFloat = 0

    /// Returns the Auto Layout `topAnchor + constant` that places an element's centerY
    /// on the unified toolbar row — co-planar with the traffic lights.
    /// Returns nil before the window is on-screen or if the button isn't available.
    /// Call from NSView.layout() or window-delegate hooks, not from init.
    static func titlebarRowTopAnchorConstant(in view: NSView) -> CGFloat? {
        // In fullscreen, there is no titlebar row — content extends edge-to-edge.
        // Return 0 so toolbar buttons park at the top edge (they will be hidden
        // by the fullscreen chrome).
        if let styleMask = view.window?.styleMask, isFullScreenLayout(styleMask: styleMask) {
            return 0
        }
        guard let win = view.window,
              let close = win.standardWindowButton(.closeButton),
              close.window === win else { return nil }
        let closeInView = close.convert(close.bounds, to: view)
        // closeInView.midY is in AppKit unflipped coords (larger = visually higher).
        // "Below" traffic lights = smaller Y in unflipped coords.
        let rowY_unflipped = closeInView.midY - breathingRoomBelowChrome
        // topAnchor + N = N pts below visual top; visual top = bounds.height (unflipped).
        return view.bounds.height - rowY_unflipped
    }

    /// Height of the session-name title bar inside the terminal card.
    static let terminalTitleBarHeight: CGFloat = 28

    /// The window's own corner radius. Sean (2026-10-11): the main window is
    /// 20, so the inset cards and tray pills are 20 − 8 = 12 (the 16
    /// measured on 2026-10-08 read too tight).
    static let windowCornerRadius: CGFloat = 20

    /// Radii nest (Sean, 2026-10-11): a surface inset `inset` from its
    /// parent surface's edges is concentric with the parent's corner — its
    /// radius is the parent's less the inset, clamped at 0. The one rule for
    /// every card, pill and chip.
    static func concentricRadius(parent: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, parent - inset)
    }

    /// A surface whose parent is the window, inset `margin` from its edges:
    /// the terminal, browser, History and overlay cards, and the tray pills
    /// outside overlay.
    static func concentricCornerRadius(margin: CGFloat) -> CGFloat {
        concentricRadius(parent: windowCornerRadius, inset: margin)
    }

    /// The corner of the surface the tray pills sit in. Overlay: the
    /// overlay card (itself the window margin in from the window). Every
    /// other mode: the window — the pinned sidebar and the rail draw no
    /// card around the tray.
    static func trayParentCornerRadius(for mode: SidebarMode, margin: CGFloat) -> CGFloat {
        mode == .overlay ? concentricCornerRadius(margin: margin) : windowCornerRadius
    }

    /// Corner radius on the floating terminal panel (all four corners), and
    /// every card that shares its inset (browser, History): concentric with
    /// the window at the live window margin.
    static var terminalCornerRadius: CGFloat {
        concentricCornerRadius(margin: SidebarDialTuning.windowMargin())
    }

    /// Shadow color applied to canvas shadow hosts (terminal + browser cards).
    static let canvasShadowColor: CGColor = NSColor.black.cgColor

    /// Shadow blur radius applied to canvas shadow hosts.
    static let canvasShadowRadius: CGFloat = 8

    /// Shadow offset applied to canvas shadow hosts (slight downward cast).
    static let canvasShadowOffset: CGSize = CGSize(width: 0, height: -2)

    /// Shadow opacity applied to canvas shadow hosts when the card is visible.
    static let canvasShadowOpacity: Float = 0.15

    /// The closed-sidebar hover bar's shadow (beta.26, Sean): the canvas
    /// card's own shadow, so the bar floating over the terminal reads as
    /// one more card in the same stack. Cast rightward onto the canvas.
    static let hoverBarShadowColor: CGColor = canvasShadowColor
    static let hoverBarShadowRadius: CGFloat = canvasShadowRadius
    static let hoverBarShadowOpacity: Float = canvasShadowOpacity

    /// Inset around the terminal panel when sidebar is visible (floating card effect).
    /// The design uses 8pt on all four sides (top, bottom, left, right).
    /// The compiled default of the "Window margin" dial — read it through
    /// `SidebarDialTuning.windowMargin()`, which also drives the sidebar's
    /// outer edge, so every outer gutter in the window stays one value.
    static let terminalInset: CGFloat = 8

    /// Width of the invisible hover trigger strip at the left edge (closed mode).
    /// Flow 01 (sidebar-presence): 10 → 24 — the hot zone is invisible in the
    /// app; the `#ffffff08` fill on the design canvas is a diagram device only.
    static let overlayTriggerWidth: CGFloat = 24

    /// The closed-mode reveal strip: `overlayTriggerWidth` wide at the
    /// leading edge, full height. The one definition of the zone: the
    /// container installs its closed-mode tracking area from it, and only
    /// that area's own events reveal the sidebar.
    static func closedRevealZone(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: overlayTriggerWidth, height: bounds.height)
    }

    /// The open overlay's hover zone: from the window's leading edge to the
    /// overlay card's trailing edge — the window margin the card sits off
    /// the window, the sidebar column, and the pinned gutter past it
    /// (`sidebarTrailingGutter(for: .overlay)`). Full height.
    static func overlayRevealZone(in bounds: CGRect, sidebarWidth: CGFloat, margin: CGFloat) -> CGRect {
        let width = margin + sidebarWidth + sidebarTrailingGutter(for: .overlay, margin: margin)
        return CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
    }

    /// Minimum width for the browser panel when visible.
    static let browserMinWidth: CGFloat = 320

    /// Default split ratio for terminal vs browser (terminal gets this fraction).
    static let browserSplitRatio: CGFloat = 0.5

    /// Background for expanded project group container (dark mode).
    static let expandedContainerDark = Color(white: 0.16)

    /// Background for expanded project group container (light mode).
    static let expandedContainerLight = Color.white

    /// Background for active session row (dark mode): 6% white.
    static let activeRowDark = Color.white.opacity(0.06)

    /// Background for active session row (light mode): 4% black.
    static let activeRowLight = Color.black.opacity(0.04)

    /// The highlighted row in the Cmd+T composer's lists (Resume, A4's start
    /// column), and its key caps. Heavier than `activeRowLight/Dark`: the
    /// composer floats over live terminal output, not the quiet sidebar.
    static let composerRowSelectedLight = Color.black.opacity(0.06)
    static let composerRowSelectedDark = Color.white.opacity(0.10)

    /// Chrome background (light mode). Covers the left sidebar column and the
    /// gutter padding around the terminal card. The outer of the two Ghostties
    /// design-system layers — warm pink-cream, independent of terminal theme.
    static let chromeBackgroundLight = NSColor(red: 0xF0 / 255.0, green: 0xE9 / 255.0, blue: 0xE6 / 255.0, alpha: 1)

    /// Chrome background (dark mode). See `chromeBackgroundLight`.
    static let chromeBackgroundDark = NSColor(white: 0.14, alpha: 1)

    /// Canvas background (light mode). Covers the terminal card background
    /// (internal header strip + card rim around the GPU-rendered terminal).
    /// Slightly lighter and cooler than chrome — the inner of the two
    /// Ghostties design-system layers. Also independent of terminal theme;
    /// the terminal content area itself is painted by GhosttyKit.
    static let canvasBackgroundLight = NSColor(red: 0xFA / 255.0, green: 0xF7 / 255.0, blue: 0xF3 / 255.0, alpha: 1)

    /// Canvas background (dark mode). Slightly lighter than chrome dark, still
    /// warm. See `canvasBackgroundLight`.
    static let canvasBackgroundDark = NSColor(white: 0.18, alpha: 1)

    /// The closed-sidebar hover bar's fill (beta.26, Sean): the pinned
    /// sidebar's chrome, so the sidebar looks the same revealed as pinned.
    /// Follows the OS appearance, not the terminal theme.
    static func hoverBarFill(isDark: Bool) -> NSColor {
        isDark ? chromeBackgroundDark : chromeBackgroundLight
    }

    /// Border (dark mode): DESIGN.md `darkBorder` #2a2a2a, a hairline one
    /// step above the dark chrome. The tray glass's dark rim.
    static let borderDark = NSColor(red: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0, alpha: 1)

    /// Terracotta/warm rust accent used as a brand/UI accent (pin notices, callout
    /// cards, task-row highlights, browser-toggle tint). #c97350
    /// NOTE: This is NOT the session-status "waiting" color — see `statusYourTurnBlue`.
    static let waitingTerracotta = Color(red: 0.788, green: 0.451, blue: 0.314)

    /// NSColor variant of `waitingTerracotta` for AppKit layers (e.g. button tints).
    static let waitingTerracottaNS = NSColor(red: 0.788, green: 0.451, blue: 0.314, alpha: 1)

    /// Minimum width for the terminal panel when browser is visible.
    static let terminalMinWidth: CGFloat = 300

    // MARK: - Session Status-Dot Colors

    /// Session status dot: "your turn" / waiting for input. Calm muted blue #5B8DEF.
    /// Replaces the former terracotta — convention-led: blue = it's your move.
    static let statusYourTurnBlue = Color(red: 0x5B / 255.0, green: 0x8D / 255.0, blue: 0xEF / 255.0)

    /// NSColor variant of `statusYourTurnBlue` for AppKit/menu-bar layers.
    static let statusYourTurnBlueNS = NSColor(red: 0x5B / 255.0, green: 0x8D / 255.0, blue: 0xEF / 255.0, alpha: 1)

    /// Session status dot: "needs a decision" / urgent attention required.
    /// Electric gold #FFC400 — loud, convention-led: yellow/gold = decide now.
    /// Replaces the former purple.
    static let statusNeedsDecisionGold = Color(red: 0xFF / 255.0, green: 0xC4 / 255.0, blue: 0x00 / 255.0)

    /// NSColor variant of `statusNeedsDecisionGold` for AppKit/menu-bar layers.
    static let statusNeedsDecisionGoldNS = NSColor(red: 0xFF / 255.0, green: 0xC4 / 255.0, blue: 0x00 / 255.0, alpha: 1)

    /// Session status dot: long-running / still working but taking a while.
    /// Redder/deeper orange #F97316 — clearly distinct from the electric gold used
    /// for needsDecision. Reads as "still going, heads up" vs. "act now."
    static let statusLongRunningOrange = Color(red: 0xF9 / 255.0, green: 0x73 / 255.0, blue: 0x16 / 255.0)

    /// NSColor variant of `statusLongRunningOrange` for AppKit/menu-bar layers.
    static let statusLongRunningOrangeNS = NSColor(red: 0xF9 / 255.0, green: 0x73 / 255.0, blue: 0x16 / 255.0, alpha: 1)

    /// Purple accent (legacy — kept for reference only, no longer used for status dots).
    /// Previously used for "needs attention" indicator state. #A855F7
    /// @deprecated Use `statusNeedsDecisionGold` for session status indicators.
    static let needsAttentionPurple = Color(red: 0.659, green: 0.333, blue: 0.969)

    /// Composer results-list selection accent — the selected-row fill and
    /// per-character search-match highlight in the composer's results list,
    /// replacing the system `Color.accentColor`. Deliberately
    /// shares its hex (#5B8DEF) with `statusYourTurnBlue`, a known collision
    /// Sean has accepted for now rather than reusing that status-named token
    /// directly (composer selection isn't a session status). Scheduled for
    /// design-system review — change this one token, not the call sites.
    static let composerSelectionAccent = Color(red: 0x5B / 255.0, green: 0x8D / 255.0, blue: 0xEF / 255.0)

    // MARK: - Activity / Section Foregrounds

    /// Foreground color for a project's ghost icon when the project has recent
    /// activity (within 24h) but no live active session. Reads as "alive but not
    /// running" — full-strength label, same weight as a body label.
    static let activityNormalForeground = Color.primary

    /// Foreground color for a project's ghost icon when the project is idle
    /// (no live active session and nothing within the past 24h). Reads as "in
    /// the long tail" — quietest tier above pure invisible.
    static let activityMutedForeground = Color(.tertiaryLabelColor)

    /// Secondary/muted text foreground (light mode). DESIGN.md `textSecondary`.
    /// A fixed value, not a system dynamic color — `NSColor.tertiaryLabelColor`
    /// (25% opacity) fails WCAG 4.5:1 for low-emphasis UI text against every
    /// backdrop it renders on. `#6b6b6b` (DESIGN.md's original documented
    /// value) still falls short at 4.44:1 on chrome and 4.08:1 on the
    /// `activeRowLight` tint — the two backdrops most of this text actually
    /// sits on. `#5E5E5E` (beta.26, sidebar contrast option 2) clears 4.5:1
    /// with margin on chrome and on the project group card
    /// (`RailProjectColumn.columnFill`). See
    /// `docs/audits/sidebar-contrast-audit.md`.
    static let textSecondaryLight = Color(red: 0x5E / 255.0, green: 0x5E / 255.0, blue: 0x5E / 255.0)

    /// Secondary/muted text foreground (dark mode). See `textSecondaryLight`.
    static let textSecondaryDark = Color(red: 0xA6 / 255.0, green: 0xA6 / 255.0, blue: 0xA6 / 255.0)

    /// Foreground for the small section-header labels in the sidebar
    /// ("Pinned", "Active Now", "Recent", "All Projects"). Muted by design so
    /// the project rows themselves stay the dominant visual. Uses the fixed
    /// `textSecondary` token (not `tertiaryLabelColor`) because this text must
    /// clear WCAG 4.5:1.
    static func sectionHeaderForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? textSecondaryDark : textSecondaryLight
    }

    /// An empty project's header and rail monogram in the one-view sidebar
    /// (Sean, 2026-10-08: shown dimmed, count 0). The `textSecondary` token
    /// (beta.26: was `tertiaryLabelColor`, which failed 4.5:1), resolved per
    /// appearance. The quiet comes from the tile: a live project's monogram
    /// is primary ink, an empty one's is this secondary grey.
    static let emptyProjectForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(textSecondaryDark)
            : NSColor(textSecondaryLight)
    })

    /// Foreground for the smaller in-row session group headers ("Active",
    /// "Recent", "Idle") inside an expanded project. One tier quieter than the
    /// top-level section headers since they're nested. Same `textSecondary`
    /// token as `sectionHeaderForeground` — both must clear 4.5:1.
    static func sessionGroupHeaderForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? textSecondaryDark : textSecondaryLight
    }

    // MARK: - Sidebar Icon Column

    /// Width of the icon column shared by section headers (pin/bolt/clock/grid)
    /// and project rows (ghost icon). Both icons live in a fixed-width frame
    /// with `.center` alignment so their x-centers align vertically when
    /// scanning the list. The label/name text begins after this column plus
    /// `sidebarIconLabelSpacing`, so section LABEL text and project NAME text
    /// also left-align.
    static let sidebarIconColumnWidth: CGFloat = 16

    /// Horizontal gap between the icon column and the text label/name in a
    /// sidebar row or section header.
    static let sidebarIconLabelSpacing: CGFloat = 10

    /// Leading padding applied to the outermost HStack of both section headers
    /// and project rows. Combined with `sidebarIconColumnWidth` this yields the
    /// common x-position for icons and labels.
    static let sidebarRowLeadingPadding: CGFloat = 8

    /// Render size of the per-session ghost glyph in `RecentsRowView` (Sessions
    /// tab). Smaller than `sidebarIconColumnWidth` — the ghost sits centered
    /// inside that column, not filling it.
    static let sessionGhostSize: CGFloat = 16

    /// Padding between the session popover card's edge and its content. The
    /// card used to nest a grey block (14pt inner padding) inside a 10pt
    /// inset; with the block gone, content keeps the same 24pt it sat at.
    static let sessionPopoverContentPadding: CGFloat = 24

    // MARK: - Sidebar DialKit Tunables (sidebar-presence, session-8 brief)
    //
    // Named constants lifted from prior inline literals so `SidebarDialTuning`
    // (see `SidebarDialKit.swift`) has a single default to read for each —
    // never re-derive a literal at a second call site. Grouped by the same
    // sections the DialKit panel presents them in.

    /// `RecentsRowView` row height. With the 4pt inter-row gap
    /// (`recentsRowGap`) below, the row-to-row pitch is 52pt. See `RecentsRowView.body`'s `.frame(height:)` comment.
    static let recentsRowHeight: CGFloat = 48

    /// Inter-row gap in the Sessions tab's section `VStack`
    /// (`RecentsListView.sectionsContent`).
    static let recentsRowGap: CGFloat = 4

    /// Session name / inline-rename field text size in `RecentsRowView`.
    static let recentsRowTitleSize: CGFloat = 14

    /// Project-name subtitle text size in `RecentsRowView`.
    static let recentsRowSubtitleSize: CGFloat = 11

    /// The expanded list's row and header trailing padding: option D's 16pt
    /// label padding plus its 4pt group padding.
    static let recentsRowTrailingPadding: CGFloat = 20

    /// The expanded list's row and header leading padding, before the 30pt
    /// tile/glyph column (option D's group padding). The legacy
    /// `sidebarRowLeadingPadding` (8) still sets the Projects tab's rows.
    static let recentsRowLeadingPadding: CGFloat = 4

    /// The selected project's group card in the expanded list (option D):
    /// 6pt, inset from the tile and chips on all four sides. Read it through
    /// `SidebarDialTuning.groupCardInset()`.
    static let sidebarGroupCardInset: CGFloat = 6

    /// Top padding of the scrollable list content in both sidebar tabs
    /// (`WorkspaceSidebarView`'s Projects `LazyVStack` and `RecentsListView`'s
    /// Sessions `sectionsContent` — both currently `.padding(.vertical, 4)`,
    /// split here into a dialable top value; bottom stays the fixed 4pt this
    /// replaces).
    static let sidebarContentPaddingTop: CGFloat = 0

    /// INNER leading padding of the scrollable list content (both tabs and
    /// the rail), inside the window margin (`SidebarDialTuning.windowMargin`)
    /// that already sets the content's outer edge. 0 = content sits at the
    /// window margin, the same gutter as the terminal card's.
    static let sidebarContentPaddingLeading: CGFloat = 0

    /// INNER trailing padding of the scrollable list content, inside the
    /// window-margin gutter to the next surface (`sidebarTrailingGutter`
    /// plus `SidebarDialTuning.contentColumnTrailingPadding`).
    static let sidebarContentPaddingTrailing: CGFloat = 0

    /// Space outside the sidebar column's trailing edge before the next
    /// visible surface: the one source for the sidebar-to-card gap, read by
    /// both the card's leading constraint and the column's own padding.
    /// Pinned: the window margin (the gap the sidebar drag handle sits in),
    /// so that much of a visible trailing inset is already there and the
    /// column pads only the rest. Without this the expanded list and tray
    /// sat 8pt from the window edge but 16pt from the card. Collapsed (rail
    /// A2): 0, the card butts the rail, whose own width already ends a
    /// `leadingInset` past the traffic lights (`collapsedRailWidth`).
    /// Overlay: the same as pinned — the overlay card is the pinned sidebar
    /// presented over the terminal, so its column keeps the pinned gutter
    /// and the card's trailing edge sits that far past the column
    /// (`overlayRevealZone`). Closed: no sidebar, 0.
    static func sidebarTrailingGutter(for mode: SidebarMode, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        sidebarTrailingGutter(for: mode, margin: SidebarDialTuning.windowMargin(defaults: defaults))
    }

    /// `sidebarTrailingGutter(for:)` at an explicit window margin.
    static func sidebarTrailingGutter(for mode: SidebarMode, margin: CGFloat) -> CGFloat {
        mode == .pinned || mode == .overlay ? margin : 0
    }

    /// Hit width of the sidebar drag handle on the rail: a strip over the
    /// rail's trailing edge, ending at the card's leading edge. Rail A2 has
    /// no sidebar-to-card gap for the handle to fill, and the tray capsules'
    /// window-margin inset (`RailTrayGeometry`) already leaves this strip clear.
    static let railDragHandleHitWidth: CGFloat = 8

    /// Width of the sidebar drag handle, whose trailing edge always sits on
    /// the card's leading edge. Pinned: the sidebar-to-card gap it sits in
    /// (`sidebarTrailingGutter`). Collapsed: `railDragHandleHitWidth`, over
    /// the rail, so the handle never depends on the gap. Overlay: the same
    /// gutter as pinned, between the column and the overlay card's edge.
    /// Closed: 0 (the handle is hidden there).
    static func sidebarDragHandleWidth(for mode: SidebarMode, margin: CGFloat) -> CGFloat {
        switch mode {
        case .pinned, .overlay: return sidebarTrailingGutter(for: mode, margin: margin)
        case .collapsed: return railDragHandleHitWidth
        case .closed: return 0
        }
    }

    /// Extra top padding on the bottom tray, opening a gap between the list
    /// above and the tray below. 0 = today's flush layout (the list's
    /// `Spacer` already pushes the tray to the bottom).
    static let sidebarListToTrayGap: CGFloat = 0

    /// Added on top of `collapsedRailWidth`'s computed hug width — parked
    /// tuning knob (Sean, sidebar-presence review round 3: "the fixed 128pt
    /// rail read too wide," resolved by hugging the traffic lights instead).
    /// 0 = today's hug formula, unmodified. Does not change the hug formula
    /// itself; only adds headroom on top of it.
    static let railExtraWidth: CGFloat = 0

    // MARK: - Source-dot colors

    /// Source-dot color for shell-spawned tasks. Muted sage — existing token,
    /// kept consistent with the `statusSymbolColor` sage used in `TaskRowView`.
    static let sourceDotShell = Color(red: 0.541, green: 0.663, blue: 0.416)

    /// Source-dot color for Linear-originated tasks. Desaturated indigo.
    static let sourceDotLinear = Color(red: 0.431, green: 0.416, blue: 0.682)

    /// Source-dot color for GitHub-originated tasks. Neutral graphite.
    static let sourceDotGitHub = Color(red: 0.541, green: 0.541, blue: 0.561)

    /// Source-dot color for Sentry-originated tasks. Muted plum.
    static let sourceDotSentry = Color(red: 0.604, green: 0.431, blue: 0.557)

    /// Source-dot color when source is unknown. System tertiary label.
    static let sourceDotUnknown = Color(nsColor: .tertiaryLabelColor)

    /// Muted red for CI failure state — distinct from terracotta.
    static let ciFailColor = Color(nsColor: .systemRed).opacity(0.7)

    // MARK: - Sidebar Transition Motion (Flow 05, sidebar-presence)

    /// Named easing curve for a sidebar transition. Kept as an enum (not a
    /// raw `CAMediaTimingFunction`) so `SidebarTransitionTiming` stays
    /// `Equatable` and the timing table below is directly unit-testable.
    enum SidebarTransitionCurveKind: Equatable {
        /// iOS drawer curve — cubic-bezier(0.32, 0.72, 0, 1) (Ionic).
        /// Almost all the distance is covered in the first third, then it
        /// coasts to a stop — panels feel pushed, not dragged. Used for
        /// collapse, expand, and reopen.
        case drawer

        /// Full-close curve — cubic-bezier(0.23, 1, 0.32, 1). Closing runs
        /// against opening because there's nothing left to read on the way
        /// out — the exit should never make the user wait.
        case close

        /// The pre-Flow-05 generic curve (`.easeInEaseOut`), kept only for
        /// transition pairs the Flow 05 motion spec doesn't name (overlay
        /// reveal/dismiss) — "keeps its current animation," per brief.
        case legacyEaseInOut

        var mediaTimingFunction: CAMediaTimingFunction {
            switch self {
            case .drawer:
                return CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            case .close:
                return CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            case .legacyEaseInOut:
                return CAMediaTimingFunction(name: .easeInEaseOut)
            }
        }

        /// SwiftUI-side equivalent of `mediaTimingFunction` above, for the
        /// content cross-fade (`SidebarWidthModel.isCollapsedPresentation`)
        /// that runs alongside — but independently of — the AppKit
        /// `NSAnimationContext`/`CAMediaTimingFunction` pair that drives the
        /// width constraint. Same control points; SwiftUI has no notion of
        /// `CAMediaTimingFunction` to share directly.
        var swiftUIAnimation: (Double, Double, Double, Double)? {
            switch self {
            case .drawer:
                return (0.32, 0.72, 0, 1)
            case .close:
                return (0.23, 1, 0.32, 1)
            case .legacyEaseInOut:
                return nil
            }
        }
    }

    /// One row of the Flow 05 timing table: how long a `from → to` sidebar
    /// mode transition takes and which curve it plays on.
    struct SidebarTransitionTiming: Equatable {
        let duration: TimeInterval
        let curve: SidebarTransitionCurveKind
    }

    /// The Flow 05 motion spec's named transition table, as a pure
    /// `from → to` lookup (Sean's canvas, "Flow 05 · Collapse and close"),
    /// for the transitions that are not the sidebar ⇄ rail morph: full
    /// close 180ms on the steeper `close` curve, reopen 240ms on `drawer`.
    /// The pinned ⇄ collapsed pair (the Cmd+S toggle and the hover reveal)
    /// has no duration: it runs on the spring (`sidebarMorphSpring`), and
    /// falls to the default row here only for Reduce Motion's crossfade
    /// length. Pairs the spec doesn't name (anything routing through
    /// `.overlay`) keep the pre-Flow-05 generic 200ms `legacyEaseInOut`.
    static func sidebarTransitionTiming(from: SidebarMode, to: SidebarMode) -> SidebarTransitionTiming {
        switch (from, to) {
        case (_, .closed):
            return SidebarTransitionTiming(duration: 0.18, curve: .close)
        case (.closed, .pinned), (.closed, .collapsed):
            return SidebarTransitionTiming(duration: 0.24, curve: .drawer)
        default:
            return SidebarTransitionTiming(duration: 0.2, curve: .legacyEaseInOut)
        }
    }

    // MARK: - Springs (the sidebar ⇄ rail morph)

    /// Rail -> sidebar (the Cmd+S expand and the hover reveal): a visible
    /// overshoot (~4.6% of the travel), Sean's "bounce/spring ... fluidity"
    /// (2026-10-11); 0.15 (~0.6%) read as no bounce at all. The top of
    /// emil's 0.1–0.3 "keep bounce subtle".
    static let sidebarMorphOpenSpring = SidebarSpring(response: 0.35, bounce: 0.3)

    /// Sidebar -> rail: crisper, and no overshoot — motion-standards:
    /// "overshoot belongs to entrances only; never bounce a close".
    static let sidebarMorphCollapseSpring = SidebarSpring(response: 0.30, bounce: 0)

    /// The morph's spring for this direction, from the "Morph springs" dials.
    static func sidebarMorphSpring(collapsing: Bool, defaults: UserDefaults = SidebarDialTuning.store) -> SidebarSpring {
        collapsing
            ? SidebarSpring(response: SidebarDialTuning.motionCollapseResponse(defaults: defaults),
                            bounce: SidebarDialTuning.motionCollapseBounce(defaults: defaults))
            : SidebarSpring(response: SidebarDialTuning.motionOpenResponse(defaults: defaults),
                            bounce: SidebarDialTuning.motionOpenBounce(defaults: defaults))
    }


    /// Reduced-motion crossfade duration replacing every translation-based
    /// sidebar transition (Flow 05 "Reduced motion": drop the translate,
    /// cross-fade the two widths over 120ms — gentler, never zero).
    static let sidebarReducedMotionCrossfadeDuration: TimeInterval = 0.12

    /// Pure reduced-motion path selection: which alpha duration a sidebar
    /// transition should actually play. Extracted so the reduce-motion
    /// branch `transitionTo` takes is covered directly, not only implied by
    /// the two duration constants it picks between.
    static func sidebarTransitionAlphaDuration(reduceMotion: Bool, timing: SidebarTransitionTiming) -> TimeInterval {
        reduceMotion ? sidebarReducedMotionCrossfadeDuration : timing.duration
    }

    /// Delay before the closed-state 24pt hot zone starts accepting hover
    /// (Flow 05: "hot zone hidden → 24px at 180ms, step") — installed only
    /// once the full-close animation has actually finished, not the instant
    /// the toggle fires, so a fast mouse can't trigger the reveal overlay
    /// before the card has reached the edge.
    static let closedHotZoneActivationDelay: TimeInterval = 0.18

    /// Rail hover-reveal (`RailHoverReveal`): how long the pointer rests on
    /// the rail before the full sidebar reveals over the terminal, and how
    /// long after it leaves the revealed sidebar before it morphs back.
    /// Dial defaults ("Hover reveal" in the Sidebar panel).
    static let railHoverRevealDwell: TimeInterval = 1.2
    static let railHoverRevealExitGrace: TimeInterval = 0.3

    /// The revealed sidebar's lift off the terminal it covers: DESIGN.md §6
    /// "Overlay" (0.20, radius 12, no offset).
    static let railRevealShadowOpacity: Float = 0.20
    static let railRevealShadowRadius: CGFloat = 12

    // MARK: - Label choreography (keyframe spec, sidebar ⇄ rail)
    //
    // Every fade is a window of the morph's progress (0 = sidebar, 1 =
    // rail), not of time, so it plays on the spring's clock: it overshoots
    // and reverses with the panel, and a toggle reversing mid-flight walks
    // each label back from exactly where it is.

    /// How far a label drifts left as it fades out (toward the rail); it
    /// drifts back as it fades in.
    static let sidebarRowLabelCollapseTravel: CGFloat = -4

    /// The expand cascade's step: each label in reading order (headers
    /// included, `SidebarLabelCascade`) arrives this much later in the
    /// expand's travel, capped at the sixth.
    static let sidebarLabelCascadeStep: CGFloat = 0.05

    /// A name's fade, as a share of the travel.
    static let sidebarLabelFadeSpan: CGFloat = 0.25

    /// The progress window over which `element` fades: fully shown below
    /// `start`, gone above `end` (the badge the other way round). Names: the
    /// first label's window ends at 0.5, each later one 0.05 lower to the
    /// sixth, so on the way out of the rail they arrive in reading order and
    /// all have landed at 0. The count and chevron go a little sooner and
    /// arrive a little later. The folded count badge shows over 0.55–0.85,
    /// growing 0.9 → 1. Reduce Motion: the whole 0–1 for every element, no
    /// cascade and no scale — the morph's progress then moves over the
    /// 120ms crossfade, so each fade takes all of it.
    static func morphFadeWindow(element: SidebarMorphElement, staggerIndex: Int = 0, reduceMotion: Bool = false) -> MorphFadeWindow {
        if reduceMotion { return MorphFadeWindow(start: 0, end: 1) }
        let end = 0.5 - sidebarLabelCascadeStep * CGFloat(min(max(staggerIndex, 0), 5))
        switch element {
        case .names:
            return MorphFadeWindow(start: end - sidebarLabelFadeSpan, end: end)
        case .trailingCluster:
            return MorphFadeWindow(start: end - sidebarLabelFadeSpan, end: end - 0.05)
        case .badge:
            return MorphFadeWindow(start: 0.55, end: 0.85, scaleFrom: 0.9, scaleTo: 1)
        }
    }

    /// `element`'s opacity at morph `progress`.
    static func morphFadeOpacity(element: SidebarMorphElement, progress: CGFloat, staggerIndex: Int = 0, reduceMotion: Bool = false) -> Double {
        let window = morphFadeWindow(element: element, staggerIndex: staggerIndex, reduceMotion: reduceMotion)
        let t = Double(min(max((progress - window.start) / (window.end - window.start), 0), 1))
        return element == .badge ? t : 1 - t
    }

    /// A label's drift at `opacity`: none shown, the full travel hidden.
    /// Reduce Motion: none.
    static func sidebarLabelDrift(opacity: Double, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : sidebarRowLabelCollapseTravel * CGFloat(1 - opacity)
    }
}

/// The parts of the sidebar ⇄ rail morph that fade on their own windows of
/// its progress (`WorkspaceLayout.morphFadeWindow`).
enum SidebarMorphElement {
    /// A project header's chevron and session count.
    case trailingCluster
    /// Project and session names (and a row's subtitle).
    case names
    /// A folded project's count badge on its rail tile.
    case badge
}

/// One element's fade: `start` and `end` as morph progress (0 = sidebar,
/// 1 = rail), and the scale it grows from and to over the same window.
struct MorphFadeWindow: Equatable {
    var start: CGFloat
    var end: CGFloat
    var scaleFrom: CGFloat = 1
    var scaleTo: CGFloat = 1
}

/// The expand cascade's order (keyframe spec, defect 3): one index running
/// through every section in reading order, each section's header first,
/// then its rows, so the cascade never restarts at a new project.
enum SidebarLabelCascade {
    /// Each section's header index and its rows' indices, from `start`
    /// (the labels above the first section). Uncapped:
    /// `WorkspaceLayout.morphFadeWindow` caps the step.
    static func indices(rowsPerSection: [Int], start: Int = 0) -> [(header: Int, rows: [Int])] {
        var next = start
        return rowsPerSection.map { count in
            let header = next
            let rows = Array((header + 1)..<(header + 1 + max(count, 0)))
            next = header + 1 + max(count, 0)
            return (header, rows)
        }
    }
}

// MARK: - Animation Tokens (D18)

extension Animation {
    /// 180ms cubic-bezier(0.2, 0.7, 0.2, 1) — inline panel reveals
    /// (composer, triage card, graveyard expansion).
    /// Use as the `value:` animation on the enclosing container,
    /// or pair with `AnyTransition` for asymmetric entry/exit.
    static var sidebarPush: Animation {
        .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18)
    }

    /// 140ms ease-in — inline panel collapses.
    /// Matches the removal side of every asymmetric push transition in D18.
    static var sidebarCollapse: Animation {
        .easeIn(duration: 0.14)
    }

    /// Spatial-stability row migration (D18 grammar).
    /// Same curve as `sidebarPush` — used on `withAnimation` wrappers
    /// when a task migrates between lanes.
    static var sidebarRowMigration: Animation {
        .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18)
    }

    /// Reduced-motion fallback — opacity crossfade at 200ms (D19).
    /// Replace any spatial animation with this when
    /// `@Environment(\.accessibilityReduceMotion)` is true.
    static var sidebarReducedMotion: Animation {
        .easeInOut(duration: 0.2)
    }
}

// MARK: - Workspace Notifications

extension Notification.Name {
    /// Posted by TerminalController for Next Project (Cmd+Ctrl+]). The
    /// notification object is the originating NSWindow. Observed by
    /// `WorkspaceViewContainer`, in every sidebar mode.
    static let workspaceSelectNextProject = Notification.Name("com.seansmithdesign.ghostties.workspace.selectNextProject")

    /// Posted by TerminalController for Previous Project (Cmd+Ctrl+[). The
    /// notification object is the originating NSWindow. Observed by
    /// `WorkspaceViewContainer`, in every sidebar mode.
    static let workspaceSelectPreviousProject = Notification.Name("com.seansmithdesign.ghostties.workspace.selectPreviousProject")

    /// Posted by TerminalController when the user presses Cmd+Shift+]. The
    /// notification object is the originating NSWindow. `WorkspaceViewContainer`
    /// observes this, in every sidebar mode, to cycle focus forward through
    /// live sessions in the order the mounted sidebar lists them.
    static let workspaceSelectNextSession = Notification.Name("com.seansmithdesign.ghostties.workspace.selectNextSession")

    /// Posted by TerminalController when the user presses Cmd+Shift+[. The
    /// notification object is the originating NSWindow. `WorkspaceViewContainer`
    /// observes this, in every sidebar mode, to cycle focus backward through
    /// live sessions in the order the mounted sidebar lists them.
    static let workspaceSelectPreviousSession = Notification.Name("com.seansmithdesign.ghostties.workspace.selectPreviousSession")

    /// Posted by TerminalController when the user presses Cmd+Shift+] in
    /// task-first sidebar mode. The notification object is the originating
    /// NSWindow. `TaskSidebarView` observes this to move the task-cycling
    /// cursor forward through the rendered zone order.
    static let workspaceSelectNextTask = Notification.Name("com.seansmithdesign.ghostties.workspace.selectNextTask")

    /// Posted by TerminalController when the user presses Cmd+Shift+[ in
    /// task-first sidebar mode. The notification object is the originating
    /// NSWindow. `TaskSidebarView` observes this to move the task-cycling
    /// cursor backward through the rendered zone order.
    static let workspaceSelectPreviousTask = Notification.Name("com.seansmithdesign.ghostties.workspace.selectPreviousTask")

    /// Posted by WorkspaceStore just before a project is removed.
    /// userInfo contains "projectId" (UUID). Coordinators observe this to close
    /// running sessions before the store deletes the project's records.
    static let workspaceProjectWillBeRemoved = Notification.Name("com.seansmithdesign.ghostties.workspace.projectWillBeRemoved")

    /// Posted by TerminalController when the user presses Cmd+T. The
    /// notification object is the originating NSWindow. Observed by
    /// `WorkspaceViewContainer` (Phase 3 of session-creation-unified — moved
    /// from `WorkspaceSidebarView` so both sidebar view modes receive it,
    /// D2), which opens the composer overlay or creates instantly depending
    /// on the `ghostties.newSessionOpensComposer` preference.
    static let workspaceNewSession = Notification.Name("com.seansmithdesign.ghostties.workspace.newSession")

    /// Posted by TerminalController when the user presses Cmd+Shift+T
    /// ("New Session (Instant)", Phase 3). The notification object is the
    /// originating NSWindow. Unlike `workspaceNewSession` above, this
    /// ALWAYS creates a session immediately with no UI — it ignores the
    /// `ghostties.newSessionOpensComposer` preference entirely.
    static let workspaceNewSessionInstant = Notification.Name("com.seansmithdesign.ghostties.workspace.newSessionInstant")

    /// Posted by `WorkspaceViewContainer.instantCreateSession()` and
    /// `SessionComposerPalette.commit(template:)` right after a session is
    /// created (F1 fix, Phase 3 review). The notification object is the
    /// originating NSWindow; `userInfo["projectId"]` carries the `UUID` of
    /// the project the session was created in. `WorkspaceSidebarView`
    /// observes this to auto-expand that project — without it, a session
    /// created via the cascade pick (Cmd+T, Cmd+Shift+T, or a composer
    /// commit) into a collapsed project spawns with no visible row anywhere.
    static let workspaceDidCreateSessionInProject = Notification.Name("com.seansmithdesign.ghostties.workspace.didCreateSessionInProject")

    /// Posted by AppDelegate's Cmd+W local-event monitor, project-first
    /// workspace mode only (see `AppDelegate.isProjectFirstWorkspaceWindow(_:)`).
    /// The notification object is the originating NSWindow.
    /// `WorkspaceViewContainer` observes this, in every sidebar mode, and
    /// calls `SessionCoordinator.closeCurrentSessionWithConfirmation()`.
    static let workspaceCloseSession = Notification.Name("com.seansmithdesign.ghostties.workspace.closeSession")

    /// Posted by AppDelegate's Cmd+1-9 local-event monitor, project-first
    /// workspace mode only. The notification object is the originating
    /// NSWindow; `userInfo["index"]` carries the digit pressed (1-9, where 9
    /// always means "last visible session", not literally the 9th).
    /// `WorkspaceViewContainer` resolves the index against whichever list the
    /// mounted sidebar renders (the rail's rows when collapsed).
    static let workspaceFocusSessionAtIndex = Notification.Name("com.seansmithdesign.ghostties.workspace.focusSessionAtIndex")

    /// Posted by `WorkspaceViewContainer` after Cmd+Shift+[/] or Cmd+1-9
    /// focuses a session. The notification object is the window;
    /// `userInfo["projectId"]` is the session's project `UUID`.
    /// `WorkspaceSidebarView` observes this to expand and select that
    /// project on the Projects tab.
    static let workspaceDidFocusSessionFromShortcut = Notification.Name("com.seansmithdesign.ghostties.workspace.didFocusSessionFromShortcut")

    /// Posted by `WorkspaceViewContainer` after Next/Previous Project moves
    /// the selection. The notification object is the window;
    /// `userInfo["projectId"]` is the selected project's `UUID`.
    /// `WorkspaceSidebarView` observes this to expand and select it.
    static let workspaceDidSelectProjectFromShortcut = Notification.Name("com.seansmithdesign.ghostties.workspace.didSelectProjectFromShortcut")

    /// Posted by MenuBarDropdownView when the user clicks a session row.
    /// userInfo contains "sessionId" (UUID). SessionCoordinators observe this
    /// to focus the tapped session and bring its window to the front.
    static let menuBarFocusSession = Notification.Name("com.seansmithdesign.ghostties.menuBar.focusSession")

    /// Posted when the user toggles the sidebar view mode (project-first ↔ task-first).
    /// WorkspaceViewContainer instances observe this to swap the hosted SwiftUI view
    /// and update the sidebar width. v0 feature toggle.
    static let workspaceSidebarViewModeChanged = Notification.Name("com.seansmithdesign.ghostties.workspace.sidebarViewModeChanged")

    /// Posted by `TerminalController.showProjectsView` / `showSessionsView` after
    /// writing the new tab value to UserDefaults. `@AppStorage` handles the SwiftUI
    /// side automatically; this notification is available for AppKit observers.
    static let workspaceSidebarTabChanged = Notification.Name("com.seansmithdesign.ghostties.workspace.sidebarTabChanged")
    /// Posted by `WorkspaceViewContainer` as the sidebar starts to morph
    /// between the expanded list and the rail; the object is the window.
    /// The list cancels a rename in progress.
    static let workspaceSidebarWillMorph = Notification.Name("com.seansmithdesign.ghostties.workspace.sidebarWillMorph")

    /// Posted by `AppDelegate`'s ⌘⇧N local-event monitor and by any code path
    /// that wants to open the new-task composer. `NewTaskComposerStore.shared`
    /// observes this to call `open(workspaceStore:)`.
    ///
    /// The notification object is the originating `NSWindow` (may be nil when
    /// the monitor fires with no key window).
    static let openNewTaskComposer = Notification.Name("com.seansmithdesign.ghostties.workspace.openNewTaskComposer")

    /// Posted by AppDelegate when the `Return` menu item fires (U11).
    /// The notification object is the focused task's id `String`.
    /// `TaskRowView` instances that own the focused task observe this and call
    /// `RowClickRouter.shared.handleRowClick` through their existing SwiftUI
    /// environment, preserving correct window-scoped coordinator references.
    static let ghosttiesActivateFocusedTaskRow = Notification.Name("com.seansmithdesign.ghostties.activateFocusedTaskRow")
}

private struct SidebarTrailingGutterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct SidebarRailWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = WorkspaceLayout.sidebarRailWidth
}

private struct SidebarModeKey: EnvironmentKey {
    static let defaultValue: SidebarMode = .pinned
}

extension EnvironmentValues {
    /// The sidebar's mode, injected at the sidebar root (`SidebarHostRoot`)
    /// from `store.sidebarMode` — the target mode from the start of a
    /// transition, so a morph switches once. The tray reads it for its
    /// pills' corner (`TrayGlassStyle.pillCornerRadius(for:)`) and shadow
    /// (`SidebarDialTuning.trayGlass(for:state:)`). Pinned outside it.
    var sidebarMode: SidebarMode {
        get { self[SidebarModeKey.self] }
        set { self[SidebarModeKey.self] = newValue }
    }

    /// The collapsed rail's width (`SidebarWidthModel.railWidth`), injected
    /// once at the sidebar root (`SidebarHostRoot`); the rail tray sizes its
    /// square pills from it (`RailTrayGeometry`). The rail's floor width
    /// (`WorkspaceLayout.sidebarRailWidth`) outside it.
    var sidebarRailWidth: CGFloat {
        get { self[SidebarRailWidthKey.self] }
        set { self[SidebarRailWidthKey.self] = newValue }
    }

    /// `WorkspaceLayout.sidebarTrailingGutter(for:)`, injected once at the
    /// sidebar root (`SidebarHostRoot`). 0 outside it, so a view hosted on
    /// its own (tests, previews) pads its full visible inset.
    var sidebarTrailingGutter: CGFloat {
        get { self[SidebarTrailingGutterKey.self] }
        set { self[SidebarTrailingGutterKey.self] = newValue }
    }
}

/// The sidebar list column's padding, for both expanded tabs and the rail.
/// Tagged for the DEBUG Redlines overlay before and after each layer, so it
/// can measure both.
///
/// Expanded (`symmetric: false`): the window margin
/// (`SidebarDialTuning.windowMargin`) sets the column's outer edge — leading
/// from the window edge; trailing so the visible gap to the next surface,
/// gutter included, is the same margin — and the content-padding dials add
/// inner spacing inside it.
///
/// Rail (`symmetric: true`): one inset, the window margin, on BOTH sides of
/// the rail column, and no inner horizontal dials. The rail's row cards and
/// its tray pill (`SidebarTray`, centred on the full rail) then share one
/// centre by construction, whatever the leading/trailing dials hold.
///
/// `horizontalOnly`: the pinned History footer below the list
/// (`SidebarSessionSections.Layout.footer`) takes the column's horizontal
/// insets but none of the list's vertical padding or redline frames.
struct SidebarColumnPadding: ViewModifier {
    /// Re-renders on every dial write; see `SidebarDialTuning.epochKey`.
    @AppStorage(SidebarDialTuning.epochKey, store: SidebarDialTuning.store) private var dialEpochTick = 0
    /// See `EnvironmentValues.sidebarTrailingGutter`.
    @Environment(\.sidebarTrailingGutter) private var trailingGutter
    var symmetric = false
    var horizontalOnly = false

    func body(content: Content) -> some View {
        let margin = SidebarDialTuning.windowMargin()
        content
            .redlineFrame(horizontalOnly ? nil : RedlineID.listContent)
            .padding(.leading, symmetric ? 0 : SidebarDialTuning.contentPaddingLeading())
            .padding(.trailing, symmetric ? 0 : SidebarDialTuning.contentPaddingTrailing())
            .padding(.top, horizontalOnly ? 0 : SidebarDialTuning.contentPaddingTop())
            .redlineFrame(horizontalOnly ? nil : RedlineID.listInner)
            .padding(.leading, margin)
            .padding(.trailing, symmetric ? margin : SidebarDialTuning.contentColumnTrailingPadding(gutter: trailingGutter))
            .padding(.bottom, horizontalOnly ? 0 : 4)
    }
}
