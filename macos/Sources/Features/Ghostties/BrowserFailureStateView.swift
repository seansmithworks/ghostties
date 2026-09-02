import AppKit

/// Inline empty-state notice rendered inside the browser panel's content
/// area when the embedded browser could not start — either the creation
/// watchdog timed out, or CEF itself isn't available
/// (`scripts/download-cef.sh` hasn't been run). Persistent-panel surface,
/// so this must explain itself rather than disappear like a toast would.
///
/// One factual line, no controls: any retry or profile reset happens
/// automatically upstream (the downgrade guard and the sentinel-triggered
/// reset both run without user interaction), so this view only reports
/// that it happened — it never asks the user to do anything.
@MainActor
final class BrowserFailureStateView: NSView {
    /// Retained for source compatibility with existing callers
    /// (WorkspaceViewContainer). Recovery is automatic, not user-triggered
    /// here, so nothing in this view invokes these.
    var onRetry: (() -> Void)?
    var onResetProfileData: (() -> Void)?

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
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

        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }

    /// Show the notice with the given message. `showResetAction` is
    /// accepted for source compatibility with existing callers but no
    /// longer affects rendering — this view never presents a button.
    func show(message: String, showResetAction: Bool = false) {
        messageLabel.stringValue = message
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
