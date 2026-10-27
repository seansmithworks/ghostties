import AppKit

/// URL bar + navigation controls for the browser panel.
/// Layout: [<] [>] [↻] [____URL field____] [DevTools]
@MainActor
final class BrowserNavigationBar: NSView {
    let backButton: NSButton
    let forwardButton: NSButton
    let reloadButton: NSButton
    let urlField: NSTextField
    let devToolsButton: NSButton
    #if DEBUG
    /// "Driven by <session>" while an agent is attached; hidden otherwise.
    let drivenByPill = BrowserDrivenByPill()
    private var urlFieldTrailingToDevTools: NSLayoutConstraint!
    private var urlFieldTrailingToPill: NSLayoutConstraint!
    #endif

    override init(frame: NSRect) {
        backButton = Self.makeSymbolButton(
            symbolName: "chevron.left",
            accessibilityDescription: "Back"
        )
        forwardButton = Self.makeSymbolButton(
            symbolName: "chevron.right",
            accessibilityDescription: "Forward"
        )
        reloadButton = Self.makeSymbolButton(
            symbolName: "arrow.clockwise",
            accessibilityDescription: "Reload"
        )
        devToolsButton = Self.makeSymbolButton(
            symbolName: "wrench.and.screwdriver",
            accessibilityDescription: "Developer Tools"
        )

        urlField = NSTextField()
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.font = .systemFont(ofSize: 11)
        urlField.placeholderString = "Enter URL…"
        urlField.bezelStyle = .roundedBezel
        urlField.lineBreakMode = .byTruncatingTail
        urlField.cell?.truncatesLastVisibleLine = true
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        let buttons = [backButton, forwardButton, reloadButton]
        for button in buttons {
            addSubview(button)
        }
        addSubview(urlField)
        addSubview(devToolsButton)
        let urlFieldTrailing = urlField.trailingAnchor.constraint(equalTo: devToolsButton.leadingAnchor, constant: -8)
        #if DEBUG
        addSubview(drivenByPill)
        urlFieldTrailingToDevTools = urlFieldTrailing
        urlFieldTrailingToPill = urlField.trailingAnchor.constraint(equalTo: drivenByPill.leadingAnchor, constant: -8)
        NSLayoutConstraint.activate([
            drivenByPill.trailingAnchor.constraint(equalTo: devToolsButton.leadingAnchor, constant: -8),
            drivenByPill.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        #endif

        // Disable forward/back by default (no history yet).
        backButton.isEnabled = false
        forwardButton.isEnabled = false

        NSLayoutConstraint.activate([
            // Back button
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Forward button
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Reload button
            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 4),
            reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // URL field — flexible width
            urlField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            urlFieldTrailing,
            urlField.centerYAnchor.constraint(equalTo: centerYAnchor),

            // DevTools button at trailing edge
            devToolsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            devToolsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    #if DEBUG
    /// Shows the pill naming the driving session, or hides it (nil).
    func setDrivenBy(name: String?, color: NSColor?) {
        let shown = name != nil
        if let name { drivenByPill.name = name }
        drivenByPill.color = color
        drivenByPill.isHidden = !shown
        // Off before on, so the two never hold the field at once.
        let (on, off) = shown ? (urlFieldTrailingToPill!, urlFieldTrailingToDevTools!) : (urlFieldTrailingToDevTools!, urlFieldTrailingToPill!)
        off.isActive = false
        on.isActive = true
    }
    #endif

    // MARK: - Factory

    private static func makeSymbolButton(
        symbolName: String,
        accessibilityDescription: String
    ) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 13, weight: .medium
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }
}
