import AppKit

/// Inline empty state rendered inside the browser panel's content area when
/// the embedded browser could not start — either the creation watchdog
/// timed out, or CEF itself isn't available (`scripts/download-cef.sh`
/// hasn't been run). Persistent-panel surface, so this must explain itself
/// rather than disappear like a toast would.
@MainActor
final class BrowserFailureStateView: NSView {
    var onRetry: (() -> Void)?

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var retryButton: NSButton = {
        let button = NSButton(title: "Retry", target: self, action: #selector(retryTapped))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
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

        let stack = NSStackView(views: [messageLabel, retryButton])
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

    /// Show the failure state with the given message.
    func show(message: String) {
        messageLabel.stringValue = message
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
