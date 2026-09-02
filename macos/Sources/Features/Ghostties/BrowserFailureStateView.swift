import AppKit

/// Inline empty state rendered inside the browser panel's content area when
/// the embedded browser could not start — either the creation watchdog
/// timed out, or CEF itself isn't available (`scripts/download-cef.sh`
/// hasn't been run). Persistent-panel surface, so this must explain itself
/// rather than disappear like a toast would.
@MainActor
final class BrowserFailureStateView: NSView {
    var onRetry: (() -> Void)?
    /// Called when the user chooses to reset browser data. Only reachable
    /// when `show(message:showResetAction:)` is called with `true` — i.e.
    /// when the failure was detected via the browser-open-attempt sentinel
    /// (a previous launch's attempt crashed the process).
    var onResetProfileData: (() -> Void)?

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        return label
    }()

    private lazy var buttonRow: NSStackView = {
        let stack = NSStackView(views: [retryButton, resetButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }()

    private lazy var retryButton: NSButton = {
        let button = NSButton(title: "Retry", target: self, action: #selector(retryTapped))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var resetButton: NSButton = {
        let button = NSButton(title: "Reset browser data", target: self, action: #selector(resetTapped))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        isHidden = true

        let stack = NSStackView(views: [messageLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }

    /// Show the failure state with the given message. `showResetAction`
    /// reveals the "Reset browser data" action alongside Retry — set this
    /// when the failure came from a detected previous-launch crash
    /// (`CEFBrowserView.creationFailedDueToPreviousCrash`), since a plain
    /// retry cannot recover from that state.
    func show(message: String, showResetAction: Bool = false) {
        messageLabel.stringValue = message
        resetButton.isHidden = !showResetAction
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    @objc private func retryTapped() {
        onRetry?()
    }

    @objc private func resetTapped() {
        onResetProfileData?()
    }
}
