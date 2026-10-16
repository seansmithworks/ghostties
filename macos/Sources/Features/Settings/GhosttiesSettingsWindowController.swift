import AppKit
import SwiftUI

/// The Settings window (Cmd+, / app menu "Settings…"): a toolbar of tabs,
/// macOS's own Settings layout. One shared window; reopening brings it
/// forward on the tab it was left on.
final class GhosttiesSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = GhosttiesSettingsWindowController()

    enum Tab: Int { case general, appearance }

    private let tabs = NSTabViewController()

    private init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.item(
            label: "General", symbol: "gearshape",
            view: SettingsView()
        ))
        tabs.addTabViewItem(Self.item(
            label: "Appearance", symbol: "paintpalette",
            view: AppearanceSettingsView()
        ))
        // General is a placeholder today; open on the pane with content.
        tabs.selectedTabViewItemIndex = Tab.appearance.rawValue
        window.contentViewController = tabs
        window.toolbarStyle = .preference
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func item<V: View>(label: String, symbol: String, view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func show(tab: Tab? = nil) {
        if let tab { tabs.selectedTabViewItemIndex = tab.rawValue }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
