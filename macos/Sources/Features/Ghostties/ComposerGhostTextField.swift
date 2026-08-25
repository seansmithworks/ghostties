import AppKit
import SwiftUI

// MARK: - UNVERIFIED — read before touching this file

/// Composer UI 11 plan §5/§7, Step 7 (two commits, 7a construction + 7b
/// ghost subview/Tab-accept — this file is 7a; 7b's additions are marked
/// inline where they land). This is the repo's FIRST standalone
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
/// after every programmatic write); this commit (7a) leaves it EMPTY
/// (documented, not implemented) because the thing it would apply, the
/// ghost label, doesn't exist until 7b.
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

        init(parent: ComposerGhostTextField) {
            self.parent = parent
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
        /// write. **Empty in 7a** — documented, not implemented; 7b fills
        /// it in with ghost-label positioning/painting. No temporary
        /// attributes are applied here or planned tonight (Q2 open, see
        /// this file's header).
        func applyStyles() {
            // Intentionally empty — see doc comment above.
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            // A-F14: IME composition in flight — skip the binding write
            // until the composition commits (the next `textDidChange`
            // after that, with `hasMarkedText()` false).
            guard !textView.hasMarkedText() else { return }
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
                // 7a: consumed no-op — nothing to accept yet, no ghost
                // exists in this commit. 7b replaces this with the actual
                // accept-the-ghost behavior. Returning true either way:
                // letting Tab fall through moves focus off the field, which
                // is worse than a no-op.
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

        func teardown() {
            guard let textView, let window = textView.window else { return }
            if window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
    }
}

/// The repo's first standalone (non-field-editor) `NSTextView` subclass.
/// 7a: no overrides yet beyond identity — 7b adds `currentGhostText` and an
/// `accessibilityValue()` override (A-F17) so the field doesn't announce
/// empty while the screen shows a predicted path.
final class ComposerGhostNSTextView: NSTextView {}
