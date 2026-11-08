#if DEBUG
import AppKit

/// "Driven by" on the browser panel while an agent is attached to it through
/// the gateway (`SessionCoordinator.agentDriver(ofBrowser:)`): a ring around
/// the panel and a pill in the navigation bar, both in the driving terminal's
/// ghost colour. Debug builds only, like the gateway; Release never shows it.
enum BrowserDrivenBy {
    static let ringWidth: CGFloat = 3
    static let pillStrokeWidth: CGFloat = 1.25
    static let pillFillOpacity: CGFloat = 0.12
    static let pillHorizontalPadding: CGFloat = 8
    static let pillHeight: CGFloat = 18
    static let pillMaxWidth: CGFloat = 200

    static func label(for name: String) -> String { "Driven by \(name)" }
}

/// The ring: a stroke inside the panel's edge, following its corner radius.
/// Never takes clicks and is not an accessibility element; the pill speaks.
@MainActor
final class BrowserDrivenByRing: NSView {
    var color: NSColor? { didSet { applyColors() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = BrowserDrivenBy.ringWidth
        layer?.cornerCurve = .continuous
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = superview?.layer?.cornerRadius ?? WorkspaceLayout.terminalCornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color?.cgColor
        }
    }
}

/// The pill: "Driven by <session name>", at the trailing end of the URL bar.
@MainActor
final class BrowserDrivenByPill: NSView {
    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        // The URL field's size.
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        return label
    }()

    var color: NSColor? { didSet { applyColors() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.borderWidth = BrowserDrivenBy.pillStrokeWidth
        layer?.cornerRadius = BrowserDrivenBy.pillHeight / 2
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: BrowserDrivenBy.pillHeight),
            widthAnchor.constraint(lessThanOrEqualToConstant: BrowserDrivenBy.pillMaxWidth),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BrowserDrivenBy.pillHorizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -BrowserDrivenBy.pillHorizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // The URL field gives way first; the pill truncates only past its cap.
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var name: String = "" {
        didSet {
            let text = BrowserDrivenBy.label(for: name)
            label.stringValue = text
            setAccessibilityLabel(text)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color?.cgColor
            layer?.backgroundColor = color?.withAlphaComponent(BrowserDrivenBy.pillFillOpacity).cgColor
        }
    }
}
#endif
