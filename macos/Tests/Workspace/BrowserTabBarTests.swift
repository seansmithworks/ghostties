import AppKit
import Testing
@testable import Ghostty

/// The tab strip's geometry: one line per title, equal widths that shrink
/// as tabs are added, a close button that never shares space with the
/// title, and a height that never changes.
@MainActor
struct BrowserTabBarTests {
    private func bar(titles: [String], width: CGFloat, selected: Int = 0) -> (BrowserTabBar, BrowserTabManager) {
        let manager = BrowserTabManager()
        for title in titles {
            let tab = manager.createTab()
            manager.updateTab(id: tab.id, title: title)
        }
        if manager.tabs.indices.contains(selected) { manager.switchTab(id: manager.tabs[selected].id) }
        let bar = BrowserTabBar(frame: NSRect(x: 0, y: 0, width: width, height: BrowserTabBar.barHeight))
        bar.tabManager = manager
        bar.layoutSubtreeIfNeeded()
        bar.layout()
        for tab in bar.tabViewsForTesting { tab.layout() }
        return (bar, manager)
    }

    private let long = "Sean Smith · Product designer who builds things for people who make software"

    @Test func tabsShareTheStripEvenlyUpToTheMaximum() {
        #expect(BrowserTabBar.tabWidth(count: 1, availableWidth: 900) == BrowserTabBar.maxTabWidth)
        let four = BrowserTabBar.tabWidth(count: 4, availableWidth: 600)
        #expect(four == BrowserTabBar.maxTabWidth || four * 4 + BrowserTabBar.tabSpacing * 3 <= 600)
        let eight = BrowserTabBar.tabWidth(count: 8, availableWidth: 600)
        #expect(eight < four)
        #expect(eight * 8 + BrowserTabBar.tabSpacing * 7 <= 600)
    }

    @Test func everyTabIsTheSameWidthAndTheStripHeightNeverChanges() {
        for count in [1, 4, 8] {
            let (bar, _) = bar(titles: Array(repeating: long, count: count), width: 640)
            let frames = bar.tabViewsForTesting.map(\.frame)
            #expect(frames.count == count)
            #expect(Set(frames.map(\.width)).count == 1, "\(count) tabs: equal widths")
            #expect(Set(frames.map(\.height)).count == 1)
            #expect(bar.intrinsicContentSize.height == BrowserTabBar.barHeight)
            // The + sits after the last tab, inside the strip.
            let plus = bar.addTabButtonForTesting.frame
            #expect(plus.minX >= frames.last!.maxX)
            #expect(plus.maxX <= bar.bounds.maxX)
        }
    }

    @Test func titlesAreOneLineAndNeverMeetTheCloseButton() {
        let (bar, _) = bar(titles: [long, "Google", long, long], width: 640)
        for tab in bar.tabViewsForTesting {
            let label = tab.titleLabelForTesting
            #expect(label.maximumNumberOfLines == 1)
            #expect(label.lineBreakMode == .byTruncatingTail)
            #expect(label.frame.height <= tab.bounds.height, "one line fits the tab")
            #expect(!label.frame.intersects(tab.closeButtonForTesting.frame), "the title stays clear of the close slot")
        }
    }

    @Test func closeShowsForTheSelectedTabAndOnHoverOnly() {
        let (bar, _) = bar(titles: ["One", "Two", "Three"], width: 640, selected: 1)
        let tabs = bar.tabViewsForTesting
        #expect(tabs.map { $0.closeButtonForTesting.isHidden } == [true, false, true])
        tabs[2].setHoveredForTesting(true)
        #expect(!tabs[2].closeButtonForTesting.isHidden)
        tabs[2].setHoveredForTesting(false)
        #expect(tabs[2].closeButtonForTesting.isHidden)
    }

    @Test func aTitleChangeKeepsTheSameTabView() {
        let (bar, manager) = bar(titles: ["One", "Two"], width: 640)
        let before = bar.tabViewsForTesting.map(ObjectIdentifier.init)
        manager.updateTab(id: manager.tabs[0].id, title: long)
        #expect(bar.tabViewsForTesting.map(ObjectIdentifier.init) == before)
        #expect(bar.tabViewsForTesting[0].titleLabelForTesting.stringValue == long)
    }
}
