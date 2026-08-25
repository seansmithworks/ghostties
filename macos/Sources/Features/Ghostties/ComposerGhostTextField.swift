import AppKit
import SwiftUI

// MARK: - UNVERIFIED — read before touching this file

/// Composer UI 11 plan §5/§7, Step 7 (two commits, 7a construction + 7b
/// ghost subview/Tab-accept — both commits are in this file; 7b's
/// additions are marked inline where they land). This is the repo's FIRST
/// standalone
/// `NSTextView` (G-F25/A-F9 — `TabTitleEditor` is `NSTextFieldDelegate` on a
/// field editor, a different protocol on a different class; nothing here
/// copies it). It is built to the AppKit semantics documented in
/// `docs/plans/composer-ui-11/refutation-appkit.md` (findings A-F1 through
/// A-F28) and gated OFF by default
/// (`ComposerGhostTextField.modelBFieldStorageKey`, `@AppStorage`, default
/// `false`) — `SessionComposerPalette.queryRow` still builds
/// `ComposerQueryField` unless Sean flips the flag himself.
///
/// **What is NOT verified, and cannot be verified by an agent** (A-F13 —
/// every gate below is a manual keyboard matrix, and this repo forbids
/// agent-driven synthetic keystrokes,
/// `feedback_subagent-gui-automation-hit-live-session`):
/// - That any of the keyboard handling actually WORKS when driven by real
///   `NSWindow.sendEvent:`/`performKeyEquivalent:` routing. The
///   `doCommandBySelector` tests in `ComposerGhostTextFieldSelectorTests`
///   call the delegate method directly — they prove the SWITCH statement's
///   logic, nothing about whether a keystroke ever reaches it (A-F12).
/// - Focus delivery in a real (key) window — the focus test hosts this in
///   an app-hosted `NSWindow` that is never key, which proves
///   `makeFirstResponder` succeeds, not that keystrokes are delivered
///   (A-F27).
/// - IME/dead-key composition (`hasMarkedText()` is guarded against, never
///   exercised — there is no way to synthesize a marked-text session in a
///   test).
/// - Undo scope across a composer close/reopen cycle (A-F7/G-F16).
/// - `⌘V` of multi-line text, drag-and-drop, or Services insertions
///   (`isFieldEditor = true` is set, per A-F15, but not driven).
/// - On-screen material/vibrancy fidelity, or the `.anchored` popover path
///   (this field only renders when `.centered`, matching the ghost-gate
///   rule G-F28; `.anchored` keeps `ComposerQueryField` even with the flag
///   on).
/// - Whether the four hidden `.keyboardShortcut` Buttons (retained
///   unchanged from `ComposerQueryField`, A-F11) still win first against a
///   live `NSTextView` first responder the way they did against SwiftUI's
///   own field editor — Assumption 1 in the refutation, "probably true,
///   unverifiable here" (A-F24/A-F26).
/// - (7b) The active-segment-ghost APPROXIMATION: there is no production
///   "current segment" data structure in `SessionComposerCommandParser`.
///   The spike derives it by truncating the full predicted path's
///   remainder at the next `" > "` separator — matches the
///   V02Quieted222 board's `Gho` + `stties` shape in the ordinary case,
///   but has not been checked against every parser edge case (quoted
///   tokens, `--resume`, etc.).
///
/// Settled-segment temporary-attribute TINTING is explicitly OUT OF SCOPE
/// tonight (Q2 in `plan.md` §11 is open — one grey vs two is Sean's call).
/// `applyStyles()` below is the single re-apply socket A-F3 requires
/// (fired from `textDidChange` AND — transitively, via `didChangeText()` —
/// after every programmatic write). 7b (this commit) fills it in: it
/// positions/paints the ACTIVE-SEGMENT-REMAINDER ghost label (a subview,
/// A-F22) and extends the document view's frame to include it (A-F2). It
/// applies NO temporary attributes — there is nothing to tint yet, Q2 is
/// still open.
struct ComposerGhostTextField: NSViewRepresentable {
    /// `@AppStorage` key gating model B. Default OFF — read at the call
    /// site (`SessionComposerPalette.queryRow`), not here; this type has no
    /// opinion about the flag beyond owning its name.
    static let modelBFieldStorageKey = "ghostties.composerModelBField"

    @Binding var query: String
    var fontSize: CGFloat
    /// The row height the field renders inside (`.centered` only tonight,
    /// 38pt — `SessionComposerPalette.fieldHeight`). Used only to compute a
    /// vertical `textContainerInset` that centers a single line, since
    /// `NSTextView`'s own inset defaults to `(0, 0)` and renders top-aligned
    /// (A-F6).
    var rowHeight: CGFloat
    @Binding var focusTrigger: Bool
    /// D6 parity with `ComposerQueryField.hasSelection` — whether Return
    /// commits (`.submit`) or shakes (`.submitNoMatch`).
    var hasSelection: Bool
    /// D6 parity with `ComposerQueryField.isPickerOpen` — while true, this
    /// field's own arrow/Return handling goes quiet (the inline
    /// project/branch picker is the only live handler); mirrors the guard
    /// ladder in `ComposerQueryField.body`'s `.onSubmit`/`.onMoveCommand`
    /// exactly, selector-for-selector.
    var isPickerOpen: Bool
    /// D-B: the SAME full predicted path `ComposerQueryField`'s rest-state
    /// ghost placeholder renders (`SessionComposerPalette.ghostPlaceholder`,
    /// sourced from `resolutionLineSegments(...)` + `selectedOption`) — NOT
    /// a second prediction engine. (7b) once typing starts, `applyStyles()`
    /// derives the active-segment remainder from it.
    var ghostFullPath: String
    var onEvent: ((ComposerQueryField.KeyboardEvent) -> Void)?

    /// `DESIGN.md` §4's ghost grey, `#1A1A1A7E` (0x7E/0xFF ≈ 0.49) — same
    /// production symbol `ComposerQueryField.ghostPlaceholderOpacity` pins,
    /// re-declared here (not shared) because this type has its own AppKit
    /// color path (`NSColor`, not SwiftUI `Color`) and no common base to
    /// hang a shared constant on without touching `ComposerQueryField`,
    /// which is out of scope.
    static let ghostOpacity: CGFloat = 0.49

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Active-segment ghost (7b)

    /// Derives the ACTIVE-SEGMENT-REMAINDER ghost from the same full-path
    /// source model A's rest-state placeholder uses (D-B) — see this type's
    /// UNVERIFIED note for what this approximates and does not. Empty
    /// `typed` returns the whole path (matches the 11.1 rest state, one
    /// grey); non-empty `typed` truncates the remainder at the next
    /// `" > "` so only the CURRENT segment's tail ghosts, per
    /// `V02Quieted222.dc.html` (`Gho` typed + `stties` ghosted, not the
    /// rest of the path). Returns `""` when `typed` isn't a
    /// case-insensitive prefix of `fullPath` — no ghost renders against
    /// text the predicted path doesn't agree with.
    static func activeSegmentGhost(typed: String, fullPath: String) -> String {
        guard !fullPath.isEmpty else { return "" }
        guard typed.count < fullPath.count else { return "" }
        if typed.isEmpty { return fullPath }
        guard fullPath.lowercased().hasPrefix(typed.lowercased()) else { return "" }
        let remainderStart = fullPath.index(fullPath.startIndex, offsetBy: typed.count)
        let remainder = fullPath[remainderStart...]
        if let separatorRange = remainder.range(of: " > ") {
            return String(remainder[remainder.startIndex..<separatorRange.lowerBound])
        }
        return String(remainder)
    }

    // MARK: - Construction (7a)

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack (A-F26/G-F15): NEVER rely on touching
        // `.layoutManager` to trigger AppKit's lazy TextKit-1-compatibility
        // fallback — build the stack directly so there is no ordering
        // invariant for a later refactor to silently break.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = ComposerGhostNSTextView(frame: .zero, textContainer: textContainer)

        // Full horizontal-scroll sizing set (A-F1) — without every one of
        // these the document view never grows past the clip view's width,
        // `NSScrollView` has nothing to scroll, and typed text past the
        // field's edge simply clips instead of scrolling into view.
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.height]
        textView.minSize = NSSize(width: 0, height: rowHeight)

        // Parity defaults (A-F6) — NSTextView's own defaults paint an
        // opaque `.textBackgroundColor` rectangle and top-align a single
        // line; both would visibly break parity with the composer card.
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = false
        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: fontSize))
        let verticalInset = max(0, (rowHeight - lineHeight) / 2)
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)

        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor

        // `isFieldEditor = true` (A-F15/G-F10): rejects newline-bearing
        // paste, drag, and Services insertions wholesale — the only
        // construction-level defense against a "single line" field that
        // silently accepts a pasted multi-line string. `doCommandBySelector`
        // below still separately consumes `insertNewline:` for the ordinary
        // typed-Return path.
        textView.isFieldEditor = true

        // All four checkers off (A-F4), plus the two substitution toggles —
        // this is a command field (project name, branch, shell flag), not
        // prose. Continuous spell check in particular writes to the SAME
        // temporary-attribute channel a future tinting pass would use
        // (A-F3/A-F4); off is required, not cosmetic.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.string = query

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.installGhostLabel(in: textView)
        context.coordinator.applyStyles()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        // A-F14: never write the binding — or run the styling pass — into a
        // live IME composition session.
        if !textView.hasMarkedText(), textView.string != query {
            context.coordinator.setText(query, in: textView)
        }
        context.coordinator.applyStyles()

        if focusTrigger {
            // A-F8: never assign SwiftUI `@Published` state synchronously
            // inside `updateNSView` — that's a state mutation during view
            // update. Both the first-responder assertion AND the trigger
            // reset are deferred to the next runloop turn.
            DispatchQueue.main.async {
                if let window = textView.window {
                    window.makeFirstResponder(textView)
                }
                self.focusTrigger = false
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        // A-F20: an invisible overlay whose text view still holds first
        // responder keeps eating keystrokes after dismiss animates it out.
        coordinator.teardown()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerGhostTextField
        weak var textView: ComposerGhostNSTextView?
        weak var ghostLabel: NSTextField?

        init(parent: ComposerGhostTextField) {
            self.parent = parent
        }

        /// 7b: A-F22 — a SUBVIEW of the document view (the text view
        /// itself), not a `draw(_:)` override. Scroll lockstep, AppKit
        /// invalidation, and an accessibility element all come free; a
        /// `draw(_:)` override would have to hand-roll all three.
        func installGhostLabel(in textView: ComposerGhostNSTextView) {
            let label = NSTextField(labelWithString: "")
            label.font = textView.font
            label.textColor = NSColor.labelColor.withAlphaComponent(ComposerGhostTextField.ghostOpacity)
            label.isSelectable = false
            label.isEditable = false
            label.drawsBackground = false
            label.isHidden = true
            textView.addSubview(label)
            ghostLabel = label
            textView.onWindowChange = { [weak self] in self?.applyStyles() }
        }

        /// Write-back path (A-F7): NEVER `textView.string = …` — that
        /// registers no undo action, resets `selectedRange` to the end on
        /// every store-driven write (jumping the caret mid-edit), and does
        /// not notify the delegate. `shouldChangeText` →
        /// `replaceCharacters(in:with:)` → `didChangeText()` is the correct
        /// triad; `didChangeText()` (unlike direct `.string` assignment)
        /// DOES post `NSText.didChangeNotification` and call this
        /// delegate's `textDidChange`, so a single write path satisfies
        /// A-F3's "re-apply on programmatic write" requirement without a
        /// second manual trigger site.
        func setText(_ text: String, in textView: NSTextView) {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard textView.shouldChangeText(in: fullRange, replacementString: text) else { return }
            textView.textStorage?.replaceCharacters(in: fullRange, with: text)
            textView.didChangeText()
            let newLength = (text as NSString).length
            textView.setSelectedRange(NSRange(location: newLength, length: 0))
        }

        /// A-F3's single re-apply socket. Fired from `textDidChange` and
        /// (transitively, via `didChangeText()`) after every programmatic
        /// write. 7b: positions/paints the active-segment ghost label. NO
        /// temporary attributes are applied — there is nothing to tint yet
        /// (Q2 open, see this file's header).
        func applyStyles() {
            guard let textView, let ghostLabel else { return }

            guard !textView.hasMarkedText() else {
                ghostLabel.isHidden = true
                textView.currentGhostText = ""
                return
            }

            let typed = textView.string
            let ghostText = ComposerGhostTextField.activeSegmentGhost(
                typed: typed,
                fullPath: parent.ghostFullPath
            )
            textView.currentGhostText = ghostText

            guard !ghostText.isEmpty else {
                ghostLabel.isHidden = true
                return
            }

            ghostLabel.stringValue = ghostText
            ghostLabel.font = textView.font
            ghostLabel.textColor = NSColor.labelColor.withAlphaComponent(ComposerGhostTextField.ghostOpacity)
            ghostLabel.sizeToFit()

            // A-F5: insertion-point origin via `firstRect(forCharacterRange:
            // actualRange:)`, NOT `boundingRect(forGlyphRange:in:)` — that's
            // in text-container coordinates (needs `textContainerOrigin`
            // added back) AND excludes trailing whitespace, which would
            // land the ghost on top of the " > " separator in exactly the
            // shapes this field exists to render.
            let length = (typed as NSString).length
            let caretRange = NSRange(location: length, length: 0)
            var actualRange = NSRange(location: 0, length: 0)
            let screenRect = textView.firstRect(forCharacterRange: caretRange, actualRange: &actualRange)
            var origin = NSPoint(x: textView.textContainerInset.width, y: textView.textContainerInset.height)
            if screenRect != .zero, let window = textView.window {
                let windowRect = window.convertFromScreen(screenRect)
                let viewRect = textView.convert(windowRect, from: nil)
                origin = NSPoint(x: viewRect.minX, y: viewRect.minY)
            }
            ghostLabel.frame = NSRect(
                x: origin.x,
                y: origin.y,
                width: ghostLabel.frame.width,
                height: ghostLabel.frame.height
            )
            ghostLabel.isHidden = false

            // A-F2: the document view's frame must include the ghost width
            // or a long-path ghost is clipped to zero — the text view
            // otherwise sizes itself to the used rect of the real glyphs
            // only, and the scroll view has nothing beyond that to reveal.
            let requiredWidth = ghostLabel.frame.maxX + textView.textContainerInset.width
            if textView.frame.width < requiredWidth {
                textView.setFrameSize(NSSize(width: requiredWidth, height: textView.frame.height))
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            // A-F14: IME composition in flight — skip the binding write AND
            // the ghost recompute until the composition commits (the next
            // `textDidChange` after that, with `hasMarkedText()` false).
            guard !textView.hasMarkedText() else {
                ghostLabel?.isHidden = true
                return
            }
            parent.query = textView.string
            applyStyles()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Mirrors `ComposerQueryField.body`'s `.onSubmit` guard
                // ladder selector-for-selector (D6/B1): quiet while a picker
                // is open, `.submitNoMatch` shakes instead of silently
                // swallowing Return against an empty result list.
                guard !parent.isPickerOpen else { return true }
                if parent.hasSelection {
                    parent.onEvent?(.submit)
                } else {
                    parent.onEvent?(.submitNoMatch)
                }
                return true

            case #selector(NSResponder.cancelOperation(_:)):
                // A-F10: MUST return true. `NSTextView`'s default
                // `cancelOperation:` runs `complete:` (the word-completion
                // panel) — returning `false` here both dispatches `.exit`
                // AND leaves an orphaned completion popup on screen.
                parent.onEvent?(.exit)
                return true

            case #selector(NSResponder.moveUp(_:)):
                if !parent.isPickerOpen { parent.onEvent?(.move(.up)) }
                return true

            case #selector(NSResponder.moveDown(_:)):
                if !parent.isPickerOpen { parent.onEvent?(.move(.down)) }
                return true

            case #selector(NSResponder.insertTab(_:)):
                // 7b: Tab accepts the active-segment ghost. No-ops (still
                // returns true — letting Tab fall through would move focus
                // off the field) when there's nothing to accept.
                acceptGhost(in: textView)
                return true

            case #selector(NSResponder.insertBacktab(_:)):
                // Consumed no-op — a single-line field has nothing for
                // Shift-Tab to do, and letting it fall through would move
                // focus off the field.
                return true

            default:
                return false
            }
        }

        /// 7b: Tab accepts the active-segment ghost. G-F12 strawman
        /// (flagged, plan §11.5): typed casing is PRESERVED, resolution is
        /// case-insensitive — `Gho` + accepted `stties` yields exactly
        /// `Ghostties`, never a canonical rewrite of what was already
        /// typed.
        func acceptGhost(in textView: NSTextView) {
            guard let ghostText = self.textView?.currentGhostText, !ghostText.isEmpty else { return }
            let newText = textView.string + ghostText
            setText(newText, in: textView)
            parent.query = newText
            applyStyles()
        }

        func teardown() {
            guard let textView, let window = textView.window else { return }
            if window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
    }
}

/// The repo's first standalone (non-field-editor) `NSTextView` subclass.
/// Carries the ghost's current suggestion text so `accessibilityValue()`
/// (A-F17) can state it — without this override the field's accessibility
/// value is just `string`, which announces EMPTY at rest while the screen
/// shows a full predicted path (the same lie the deleted resolution line's
/// removal would otherwise leave VoiceOver with, since the composer hides
/// the rest of the sidebar/terminal while open).
final class ComposerGhostNSTextView: NSTextView {
    var currentGhostText: String = ""

    /// 7b fix (found via the snapshot evidence, not source-reading — see
    /// this file's UNVERIFIED note): `applyStyles()`'s ghost-origin math
    /// (A-F5) reads `firstRect(forCharacterRange:actualRange:)`, which
    /// needs `window` to convert screen coordinates. `makeNSView` calls
    /// `applyStyles()` before SwiftUI has attached the returned
    /// `NSScrollView` to a window, so that FIRST call always falls back to
    /// the text-container-inset origin — landing the ghost label at the
    /// START of the field, overlapping already-typed text, instead of
    /// after it. `updateNSView`'s later `applyStyles()` call can arrive too
    /// late for an immediate offscreen capture (no further SwiftUI update
    /// cycle fires without a state change). This hook re-runs styling the
    /// moment a window actually arrives, closing that gap.
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    override func accessibilityValue() -> String? {
        guard !currentGhostText.isEmpty else { return string }
        return "\(string), suggestion: \(currentGhostText)"
    }
}
