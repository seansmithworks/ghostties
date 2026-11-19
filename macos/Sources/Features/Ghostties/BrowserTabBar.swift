import AppKit
import Combine

/// The browser panel's tab strip, below the navigation bar: one tab per page
/// and a + at the end. Tabs share the strip evenly up to a maximum width;
/// titles stay on one line and truncate. A tab's close button sits in a
/// fixed leading slot, shown for the selected tab and the tab under the
/// pointer, and the title is centred clear of that slot so they never touch.
@MainActor
final class BrowserTabBar: NSView {
    // MARK: - Properties

    weak var tabManager: BrowserTabManager? {
        didSet { subscribeToManager() }
    }

    /// Called when the + button is clicked. The owner creates the tab, since a
    /// tab needs a page view and this bar only draws the manager's tabs.
    var onAddTab: (() -> Void)?

    /// Tab views in strip order. Reused by tab id across updates, so a title
    /// change or a selection never rebuilds the strip under the pointer.
    private var tabViews: [BrowserTabItemView] = []
    private let addTabButton = NSButton()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Metrics

    /// Strip height: the navigation bar's row height, whatever the tab count.
    static let barHeight: CGFloat = WorkspaceLayout.terminalTitleBarHeight
    /// Inset from the panel's leading and trailing edges; lines the first tab
    /// up with the navigation bar's back button.
    static let horizontalInset: CGFloat = 8
    /// Inset of a tab from the strip's top and bottom.
    static let verticalInset: CGFloat = 4
    /// Gap between tabs, and between the last tab and the +.
    static let tabSpacing: CGFloat = 4
    /// The widest a tab gets; tabs shrink evenly below it as they are added.
    static let maxTabWidth: CGFloat = 192
    /// The + button's square.
    static let addButtonSize: CGFloat = 20

    /// Each tab's width when `count` tabs share `availableWidth` (the strip
    /// less its insets and the +): equal shares, capped at `maxTabWidth`.
    static func tabWidth(count: Int, availableWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let gaps = tabSpacing * CGFloat(count - 1)
        let share = floor((availableWidth - gaps) / CGFloat(count))
        return max(0, min(maxTabWidth, share))
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight)
    }

    override var isFlipped: Bool { true }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")

        addTabButton.bezelStyle = .inline
        addTabButton.isBordered = false
        addTabButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New tab"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        addTabButton.imagePosition = .imageOnly
        addTabButton.contentTintColor = BrowserTabItemView.secondaryInk
        addTabButton.toolTip = "New Tab"
        addTabButton.target = self
        addTabButton.action = #selector(addTabClicked)
        addSubview(addTabButton)

        let height = heightAnchor.constraint(equalToConstant: Self.barHeight)
        height.isActive = true
    }

    // MARK: - Manager Subscription

    private func subscribeToManager() {
        cancellables.removeAll()

        guard let manager = tabManager else {
            update(tabs: [], activeId: nil)
            return
        }

        // Both BrowserTabBar and BrowserTabManager are @MainActor, so the
        // publishers already fire on the main actor — no .receive(on:) needed.
        // (Using RunLoop.main here caused a crash in debug builds due to a
        // Combine/@MainActor isolation conflict.)
        manager.$tabs
            .combineLatest(manager.$activeTabId)
            .sink { [weak self] tabs, activeId in
                self?.update(tabs: tabs, activeId: activeId)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update

    private func update(tabs: [BrowserTabManager.Tab], activeId: UUID?) {
        var existing = Dictionary(uniqueKeysWithValues: tabViews.map { ($0.tabId, $0) })
        tabViews = tabs.map { tab in
            let view = existing.removeValue(forKey: tab.id) ?? makeTabView(id: tab.id)
            view.title = tab.title
            view.isSelected = tab.id == activeId
            return view
        }
        for stale in existing.values { stale.removeFromSuperview() }
        needsLayout = true
    }

    private func makeTabView(id: UUID) -> BrowserTabItemView {
        let view = BrowserTabItemView(tabId: id)
        view.onSelect = { [weak self] in self?.tabManager?.switchTab(id: id) }
        view.onClose = { [weak self] in self?.tabManager?.closeTab(id: id) }
        addSubview(view)
        return view
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let tabHeight = bounds.height - Self.verticalInset * 2
        let available = bounds.width - Self.horizontalInset * 2 - Self.addButtonSize - Self.tabSpacing
        let width = Self.tabWidth(count: tabViews.count, availableWidth: available)

        var x = Self.horizontalInset
        for view in tabViews {
            view.frame = NSRect(x: x, y: Self.verticalInset, width: width, height: tabHeight)
            x += width + Self.tabSpacing
        }
        if tabViews.isEmpty { x = Self.horizontalInset }
        addTabButton.frame = NSRect(
            x: x,
            y: (bounds.height - Self.addButtonSize) / 2,
            width: Self.addButtonSize,
            height: Self.addButtonSize
        )
    }

    // MARK: - Actions

    @objc private func addTabClicked() {
        onAddTab?()
    }

    #if DEBUG
    /// Test seam: the tab views in strip order.
    var tabViewsForTesting: [BrowserTabItemView] { tabViews }
    /// Test seam: the + button.
    var addTabButtonForTesting: NSButton { addTabButton }
    #endif
}

// MARK: - Tab

/// One tab in `BrowserTabBar`: a centred single-line title, and a close
/// button in a fixed leading slot that shows for the selected tab and on
/// hover. The selected tab carries the strip's one fill and the primary ink.
@MainActor
final class BrowserTabItemView: NSView {
    let tabId: UUID
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var title: String = "" {
        didSet {
            guard title != oldValue else { return }
            titleLabel.stringValue = title
            toolTip = title
            setAccessibilityLabel(title)
        }
    }

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refreshState()
        }
    }

    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            refreshState()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var hoverArea: NSTrackingArea?

    /// The close button's square, and the slot it sits in.
    static let closeSlotSize: CGFloat = 16
    /// Padding between the tab's edge and the close slot.
    static let edgePadding: CGFloat = 4
    /// How far the title stays from each edge: the close slot plus padding on
    /// both sides, so the centred title never reaches the button.
    static let titleInset: CGFloat = edgePadding + closeSlotSize + edgePadding

    init(tabId: UUID) {
        self.tabId = tabId
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerCurve = .continuous

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.usesSingleLineMode = true
        titleLabel.cell?.wraps = false
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close Tab"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = Self.secondaryInk
        closeButton.toolTip = "Close Tab"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        refreshState()
    }

    // MARK: State

    private func refreshState() {
        closeButton.isHidden = !(isSelected || isHovered)
        titleLabel.font = .systemFont(ofSize: 11, weight: isSelected ? .medium : .regular)
        titleLabel.textColor = isSelected ? .labelColor : Self.secondaryInk
        setAccessibilityValue(isSelected)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let fill: NSColor? = isSelected ? Self.selectedFill : (isHovered ? Self.hoverFill : nil)
        var resolved: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = fill?.cgColor }
        layer?.backgroundColor = resolved
        layer?.cornerRadius = Self.cornerRadius
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let slot = Self.closeSlotSize
        closeButton.frame = NSRect(x: Self.edgePadding, y: (bounds.height - slot) / 2, width: slot, height: slot)
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(
            x: Self.titleInset,
            y: (bounds.height - labelHeight) / 2,
            width: max(0, bounds.width - Self.titleInset * 2),
            height: labelHeight
        )
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { isHovered = false }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    /// Selects on press, as Safari's and Finder's tabs do. The tab never
    /// takes first responder, so the keys stay where they were.
    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }

    @objc private func closeClicked() {
        onClose?()
    }

    #if DEBUG
    /// Test seam: the title label and close button.
    var titleLabelForTesting: NSTextField { titleLabel }
    var closeButtonForTesting: NSButton { closeButton }
    /// Test seam: draws the hover state without a pointer (captures).
    func setHoveredForTesting(_ hovered: Bool) { isHovered = hovered }
    #endif

    // MARK: Tokens

    /// The selected tab's fill: ink at the composer's highlighted-row step,
    /// the heavier of the two row steps, so the selection reads at a glance.
    static let selectedFill = NSColor(name: nil) { appearance in
        let theme = ChromeTheme.active(appearance.isDarkForBrowserTabs ? .dark : .light)
        return theme.ink.withAlphaComponent(ChromeTheme.Step.composerRow.opacity(theme.polarity))
    }

    /// The tab under the pointer: ink at the active-row step, a step below
    /// the selection.
    static let hoverFill = NSColor(name: nil) { appearance in
        let theme = ChromeTheme.active(appearance.isDarkForBrowserTabs ? .dark : .light)
        return theme.ink.withAlphaComponent(ChromeTheme.Step.row.opacity(theme.polarity))
    }

    /// Unselected titles, the close button and the +: the chrome's muted ink.
    static let secondaryInk = NSColor(name: nil) { appearance in
        ChromeTheme.active(appearance.isDarkForBrowserTabs ? .dark : .light).inkSecondary
    }

    /// Concentric with the browser card: the card's corner less the tab's
    /// inset from the card's edge.
    static var cornerRadius: CGFloat {
        WorkspaceLayout.concentricRadius(
            parent: WorkspaceLayout.terminalCornerRadius,
            inset: BrowserTabBar.horizontalInset
        )
    }
}

private extension NSAppearance {
    var isDarkForBrowserTabs: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
