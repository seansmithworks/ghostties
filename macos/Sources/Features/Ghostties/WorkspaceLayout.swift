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

    /// The window's own corner radius: a titled Ghostties window on macOS
    /// 26+ (no toolbar), measured from an uncropped capture on macOS 27
    /// (2026-10-08), the same value `TerminalWindow` uses for this titlebar
    /// style.
    static let windowCornerRadius: CGFloat = 16

    /// A surface inset `margin` from the window's edges is concentric with
    /// the window corner: its radius is the window's less the margin (Sean,
    /// 2026-10-08). The one rule for the canvas card and the tray pills.
    static func concentricCornerRadius(margin: CGFloat) -> CGFloat {
        max(0, windowCornerRadius - margin)
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
    /// sits on. `#636363` clears 4.5:1 on chrome, the active-row tint, and
    /// canvas. See `docs/audits/sidebar-contrast-audit.md`.
    static let textSecondaryLight = Color(red: 0x63 / 255.0, green: 0x63 / 255.0, blue: 0x63 / 255.0)

    /// Secondary/muted text foreground (dark mode). See `textSecondaryLight`.
    static let textSecondaryDark = Color(red: 0x9A / 255.0, green: 0x9A / 255.0, blue: 0x9A / 255.0)

    /// Foreground for the small section-header labels in the sidebar
    /// ("Pinned", "Active Now", "Recent", "All Projects"). Muted by design so
    /// the project rows themselves stay the dominant visual. Uses the fixed
    /// `textSecondary` token (not `tertiaryLabelColor`) because this text must
    /// clear WCAG 4.5:1.
    static func sectionHeaderForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? textSecondaryDark : textSecondaryLight
    }

    /// An empty project's header and rail monogram in the one-view sidebar
    /// (Sean, 2026-10-08: shown dimmed, count 0). One tier below
    /// `sectionHeaderForeground` on purpose, so it sits under the 4.5:1 that
    /// token clears: the dimming is the signal that nothing is running there.
    static let emptyProjectForeground = Color(nsColor: .tertiaryLabelColor)

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
    static let sessionGhostSize: CGFloat = 20

    /// Padding between the session popover card's edge and its content. The
    /// card used to nest a grey block (14pt inner padding) inside a 10pt
    /// inset; with the block gone, content keeps the same 24pt it sat at.
    static let sessionPopoverContentPadding: CGFloat = 24

    /// Gap between the popover's rail-mode name line and the content under it
    /// (the content's top padding when a name line is present).
    static let sessionPopoverNameGap: CGFloat = 6

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
    /// Overlay/closed: the column's trailing edge IS the panel edge, so 0.
    static func sidebarTrailingGutter(for mode: SidebarMode, defaults: UserDefaults = SidebarDialTuning.store) -> CGFloat {
        sidebarTrailingGutter(for: mode, margin: SidebarDialTuning.windowMargin(defaults: defaults))
    }

    /// `sidebarTrailingGutter(for:)` at an explicit window margin.
    static func sidebarTrailingGutter(for mode: SidebarMode, margin: CGFloat) -> CGFloat {
        mode == .pinned ? margin : 0
    }

    /// Hit width of the sidebar drag handle on the rail: a strip over the
    /// rail's trailing edge, ending at the card's leading edge. Rail A2 has
    /// no sidebar-to-card gap for the handle to fill, and the tray capsules'
    /// window-margin inset (`RailTrayGeometry`) already leaves this strip clear.
    static let railDragHandleHitWidth: CGFloat = 8

    /// Width of the sidebar drag handle, whose trailing edge always sits on
    /// the card's leading edge. Pinned: the sidebar-to-card gap it sits in
    /// (`sidebarTrailingGutter`). Collapsed: `railDragHandleHitWidth`, over
    /// the rail, so the handle never depends on the gap. Overlay/closed: 0
    /// (the handle is hidden there).
    static func sidebarDragHandleWidth(for mode: SidebarMode, margin: CGFloat) -> CGFloat {
        switch mode {
        case .pinned: return sidebarTrailingGutter(for: .pinned, margin: margin)
        case .collapsed: return railDragHandleHitWidth
        case .closed, .overlay: return 0
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
    /// `from → to` lookup (Sean's canvas, "Flow 05 · Collapse and close"):
    /// collapse 244→rail 260ms, expand rail→244 240ms, full close 180ms,
    /// reopen 240ms — all on `drawer` except the full close, which runs the
    /// steeper `close` curve. Pairs the spec doesn't name (anything routing
    /// through `.overlay`) keep the pre-Flow-05 generic 200ms
    /// `legacyEaseInOut` — the brief says the reveal overlay "keeps its
    /// current animation unless it conflicts."
    static func sidebarTransitionTiming(from: SidebarMode, to: SidebarMode) -> SidebarTransitionTiming {
        switch (from, to) {
        case (.pinned, .collapsed):
            return SidebarTransitionTiming(duration: 0.26, curve: .drawer)
        case (.collapsed, .pinned):
            return SidebarTransitionTiming(duration: 0.24, curve: .drawer)
        case (_, .closed):
            return SidebarTransitionTiming(duration: 0.18, curve: .close)
        case (.closed, .pinned), (.closed, .collapsed):
            return SidebarTransitionTiming(duration: 0.24, curve: .drawer)
        default:
            return SidebarTransitionTiming(duration: 0.2, curve: .legacyEaseInOut)
        }
    }

    /// SwiftUI `Animation` matching a `SidebarTransitionTiming` row, for the
    /// content cross-fade described above `SidebarTransitionCurveKind.
    /// swiftUIAnimation`. Centralized here (not hand-built at each call
    /// site) so the content cross-fade can never silently drift from the
    /// AppKit width animation's own duration/curve.
    static func sidebarTransitionSwiftUIAnimation(_ timing: SidebarTransitionTiming) -> Animation {
        guard let points = timing.curve.swiftUIAnimation else {
            return .easeInOut(duration: timing.duration)
        }
        return .timingCurve(points.0, points.1, points.2, points.3, duration: timing.duration)
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

    // MARK: - Flow 05 Content Choreography (row-level, sidebar-presence)

    /// Duration of a session row's label (name/subtitle/timestamp) fade on
    /// COLLAPSE — the canvas's "label opacity 1 → 0, window 0-100ms" row.
    /// Runs from the very start of the collapse transition (no delay) —
    /// labels leave first, before the panel/glyph motion below even starts.
    static let sidebarRowLabelCollapseFadeDuration: TimeInterval = 0.1

    /// Delay before a session row's glyph starts its inward travel on
    /// COLLAPSE — the canvas's "glyph translateX +8 → +28px, window
    /// 60-260ms" row. The panel itself is already moving at t=0 (driven by
    /// `sidebarTransitionTiming`); the glyph's own small in-row shift waits
    /// until the label has mostly cleared before it starts.
    static let sidebarRowGlyphCollapseTravelDelay: TimeInterval = 0.06

    /// Duration of the glyph's inward travel once it starts (260ms total
    /// collapse window minus the 60ms delay above).
    static let sidebarRowGlyphCollapseTravelDuration: TimeInterval = 0.2

    /// Row corner radius on COLLAPSE — same 60-260ms window as the glyph
    /// travel above. The canvas's own table names "8 → 16px", but this
    /// row's EXISTING resting radius (`RecentsRowView.rowBackground`,
    /// unrelated to Flow 05) is 6, not 8 — resting stays 6 so this
    /// choreography never silently changes the settled row's appearance;
    /// the traveled value keeps the canvas's ~2x ratio (6 → 12) rather than
    /// importing its literal 16.
    static let sidebarRowCornerRadiusResting: CGFloat = 6
    static let sidebarRowCornerRadiusTraveled: CGFloat = 12

    /// Duration a session row's glyph takes to travel back out on EXPAND —
    /// the canvas's reopen note: "reverse at 240ms on the drawer curve...
    /// session glyphs fade in 40ms apart, labels land 60ms after their
    /// glyph." The glyph travels the FULL expand window; only the label is
    /// delayed/staggered (see `expandLabelDelay(rowIndex:glyphLandDuration:)`).
    static func sidebarRowGlyphExpandTravelDuration() -> TimeInterval {
        sidebarTransitionTiming(from: .collapsed, to: .pinned).duration
    }

    /// Duration of a session row's label fade-in on EXPAND, once its delay
    /// (`expandLabelDelay`) elapses. Deliberately shorter than a glyph's
    /// travel — the label is arriving, not moving spatially — but still a
    /// standard UI fade (Emil: tooltips/small popovers 125-200ms).
    static let sidebarRowLabelExpandFadeDuration: TimeInterval = 0.12

    /// Flow 05 expand stagger, exactly as spec'd on the canvas: "session
    /// glyphs fade in 40ms apart, labels land 60ms after their glyph." Every
    /// row's glyph travels the SAME full `glyphLandDuration` window (they
    /// all start together, at t=0) — only each row's LABEL is delayed:
    /// `glyphLandDuration` (wait for the glyph to land) + a flat 60ms, plus
    /// 40ms more per row index (0-based, in the row's own rendered section).
    /// Pure so the stagger schedule is directly unit-testable without
    /// driving any real animation. Stagger is decorative — never gates
    /// hit-testing, so rows stay clickable from frame 1 regardless of this
    /// delay (per the canvas's own "controls are clickable from frame 1").
    static func expandLabelDelay(rowIndex: Int, glyphLandDuration: TimeInterval) -> TimeInterval {
        glyphLandDuration + 0.06 + 0.04 * TimeInterval(max(rowIndex, 0))
    }

    /// Whether a session row should run the Flow 05 windowed label-fade/
    /// glyph-travel choreography above, or snap straight to its resting
    /// state and let only the container-level cross-fade animate (Flow 05
    /// "Reduced Motion: drop the translate entirely... layout snaps").
    /// Pure selector, mirroring `sidebarTransitionAlphaDuration`'s pattern,
    /// so the reduced-motion branch a row takes is covered directly.
    static func sidebarRowChoreographyEnabled(reduceMotion: Bool) -> Bool {
        !reduceMotion
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

extension EnvironmentValues {
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
