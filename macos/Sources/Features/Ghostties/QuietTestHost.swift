import AppKit
import ObjectiveC

/// Makes the app-hosted XCTest run invisible to whoever is using the Mac:
/// no Dock icon, no activation, and every window a test orders front is
/// parked far outside all screens first (still key-capable and still
/// renderable, so first-responder and `cacheDisplay` tests are unaffected).
///
/// Installed once from `main.swift`, before any window or state load. Outside
/// XCTest hosting `install()` is a no-op, so shipping behaviour is unchanged.
enum QuietTestHost {
    /// True when this process is the host for an XCTest bundle.
    static var isActive: Bool {
        isActive(env: ProcessInfo.processInfo.environment)
    }

    static func isActive(env: [String: String]) -> Bool {
        env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }

    /// Far outside any plausible multi-display arrangement.
    static let parkedOrigin = NSPoint(x: -32000, y: -32000)

    private static var installed = false

    static func install() {
        guard isActive, !installed else { return }
        installed = true
        // Backstop for AppKit/SwiftUI paths that place a window themselves
        // (sheets, popovers, content-size changes): anything that lands on a
        // screen is parked again.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didUpdateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                (note.object as? NSWindow)?.quietParkIfOnScreen()
            }
        }
        NSApplication.shared.setActivationPolicy(.accessory)

        swap(NSWindow.self, #selector(NSWindow.orderFront(_:)), #selector(NSWindow.quiet_orderFront(_:)))
        swap(NSWindow.self, #selector(NSWindow.orderFrontRegardless), #selector(NSWindow.quiet_orderFrontRegardless))
        swap(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.quiet_makeKeyAndOrderFront(_:)))
        swap(NSWindow.self, Selector(("orderWindow:relativeTo:")), #selector(NSWindow.quiet_orderWindow(_:relativeTo:)))
        swap(NSWindow.self, #selector(NSWindow.setFrame(_:display:)), #selector(NSWindow.quiet_setFrame(_:display:)))
        swap(NSWindow.self, #selector(NSWindow.setFrame(_:display:animate:)), #selector(NSWindow.quiet_setFrame(_:display:animate:)))
        swap(NSWindow.self, Selector(("setIsVisible:")), #selector(NSWindow.quiet_setIsVisible(_:)))
        swap(NSWindow.self, #selector(NSWindow.constrainFrameRect(_:to:)), #selector(NSWindow.quiet_constrainFrameRect(_:to:)))
        swap(NSApplication.self, #selector(NSApplication.activate(ignoringOtherApps:)), #selector(NSApplication.quiet_activate(ignoringOtherApps:)))
    }

    private static func swap(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, original),
              let b = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

extension NSWindow {
    fileprivate func quietParkIfOnScreen() {
        guard isVisible, NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return }
        setFrameOrigin(QuietTestHost.parkedOrigin)
    }

    fileprivate func quietPark() {
        if frame.origin != QuietTestHost.parkedOrigin {
            setFrameOrigin(QuietTestHost.parkedOrigin)
        }
    }

    /// AppKit pulls titled windows back onto a screen; leave parked ones alone.
    @objc fileprivate func quiet_constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if frameRect.origin == QuietTestHost.parkedOrigin { return frameRect }
        return quiet_constrainFrameRect(frameRect, to: screen)
    }

    /// Popover and menu windows are placed by AppKit relative to a screen and
    /// clamped onto it; keep their size, park their origin.
    private var quietIsTransient: Bool {
        let name = String(describing: type(of: self))
        return name.contains("Popover") || name.contains("Menu")
    }

    private func quietParked(_ frame: NSRect) -> NSRect {
        quietIsTransient ? NSRect(origin: QuietTestHost.parkedOrigin, size: frame.size) : frame
    }

    @objc fileprivate func quiet_setFrame(_ frame: NSRect, display: Bool) {
        quiet_setFrame(quietParked(frame), display: display)
    }

    @objc fileprivate func quiet_setFrame(_ frame: NSRect, display: Bool, animate: Bool) {
        quiet_setFrame(quietParked(frame), display: display, animate: animate)
    }

    @objc fileprivate func quiet_orderWindow(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if place != .out { quietPark() }
        quiet_orderWindow(place, relativeTo: other)
        if place != .out { quietPark() }
    }

    @objc fileprivate func quiet_setIsVisible(_ visible: Bool) {
        if visible { quietPark() }
        quiet_setIsVisible(visible)
        if visible { quietPark() }
    }

    @objc fileprivate func quiet_orderFront(_ sender: Any?) {
        quietPark()
        quiet_orderFront(sender)
        quietPark() // titled windows get re-constrained onto a screen when ordered in
    }

    @objc fileprivate func quiet_orderFrontRegardless() {
        quietPark()
        quiet_orderFrontRegardless()
        quietPark() // titled windows get re-constrained onto a screen when ordered in
    }

    @objc fileprivate func quiet_makeKeyAndOrderFront(_ sender: Any?) {
        quietPark()
        quiet_makeKeyAndOrderFront(sender)
        quietPark() // titled windows get re-constrained onto a screen when ordered in
    }
}

extension NSApplication {
    /// Test mode never activates the app.
    @objc fileprivate func quiet_activate(ignoringOtherApps flag: Bool) {}
}
