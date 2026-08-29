import AppKit
import SwiftUI
import GhosttiesCore

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
/// - Whether the four hidden `.keyboardShortcut` Buttons (retained from
///   `ComposerQueryField`, A-F11 — mounted at the call site,
///   `SessionComposerPalette.queryRow`'s model-B branch, NOT in this file;
///   this type owns no SwiftUI `body` to hang them on) still win first
///   against a live `NSTextView` first responder the way they did against
///   SwiftUI's own field editor — Assumption 1 in the refutation, "probably
///   true, unverifiable here" (A-F24/A-F26). CORRECTION (review, fix 1):
///   these four Buttons were DROPPED from the initial construction despite
///   the plan requiring them retained, and the omission went undocumented
///   here — this file's own header claimed them present while they were
///   not. Restored at the call site with the same `!isPickerOpen`
///   conditional mounting `ComposerQueryField.body` uses. Their WIN-FIRST
///   behavior against this file's `NSTextView` remains exactly as
///   unverified as stated above — restoring them closes the "dropped
///   entirely" gap, not the "unverified interaction" one.
/// - (Spotlight/Raycast rewrite) The `nextSegment(remainder:)`
///   APPROXIMATION: there is no production "current segment" data
///   structure in `SessionComposerCommandParser`. `Tab`'s one-segment
///   accept is derived by string-splitting the full predicted path's
///   remainder at the next `" > "` separator — matches the worked
///   example's `Bruk` + `as > main > Shell` shape in the ordinary case,
///   but has not been checked against every parser edge case (quoted
///   tokens, `--resume`, etc.). The GHOST ITSELF (`remainderGhost`) is no
///   longer an approximation of "current segment" — it is the literal
///   remainder of `ghostFullPath`, the same full destination Return
///   commits.
/// - A small residual gap between typed text and the ghost's first glyph
///   (review fix 5): round 1's diagnosis ("`o`→`s` glyph-pair side
///   bearing") was WRONG, found in round 2 — the header and
///   `applyStyles()`'s own fix-5 comment both stated it. The actual cause
///   was BLOCKER 1 (this file's header, above): `typedWidth` measured
///   "Gho" against `textView.font` (15pt) while the glyphs it was
///   measuring against actually DREW at 12pt (unattributed programmatic
///   text, TextKit's own default), so the two numbers were never
///   comparing like with like. With Blocker 1 fixed — typed text now
///   carries `textView.typingAttributes` (15pt) on write, matching the
///   font `typedWidth` was always measuring against — the residual
///   RE-measured at ~3.5pt logical (7px @2x) in `step7-modelb-light.png`
///   (was ~2pt/4px under the old, mismatched-font measurement; the two
///   numbers are not comparable, since the earlier one was measuring the
///   wrong thing). Not fully closed to zero; most likely ordinary
///   sub-pixel slop between `firstRect(forCharacterRange:)`'s caret
///   position and `NSString.size(withAttributes:)`'s independently
///   computed advance width — both are legitimate, independently correct
///   measurements of slightly different things (an insertion-point rect
///   vs. a string's typographic advance), not proven fully closed, but no
///   longer attributed to a specific glyph pair's bearing.
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
    /// The full destination Return would commit right now — NOT
    /// `SessionComposerPalette.ghostPlaceholder` (model A's rest-state-only
    /// placeholder, welded to `currentProject`). Sourced instead from
    /// `SessionComposerPalette.ghostFullPathForModelB`, which reads the
    /// CURRENTLY HIGHLIGHTED option's own resolved destination — a
    /// highlighted project row ghosts THAT project's path even though
    /// `currentProject` never changed, which is what lets typing `bruk`
    /// against a highlighted `Brukas` project row ghost `Brukas > ...`
    /// instead of `<currentProject> > ...` not matching the typed prefix
    /// at all. Still not a second prediction engine — no value here is
    /// computed independently of what a Return commit would read. Once
    /// typing starts, `applyStyles()` derives the full remainder
    /// (`remainderGhost`) from it; `Tab` advances one segment at a time
    /// (`nextSegment(remainder:)`).
    var ghostFullPath: String
    var onEvent: ((ComposerQueryField.KeyboardEvent) -> Void)?

    /// DESIGN.md §4's ghost grey went through `#1A1A1A7E` (0x7E/0xFF ≈ 0.49,
    /// measured 2.99:1 light / 3.99:1 dark against WCAG AA text contrast's
    /// 4.5:1 floor) and 0.65 (measured 4.74:1 light / 5.93:1 dark, clearing
    /// AA) before Sean, looking at the real build, called 0.50 as a
    /// deliberate contrast/legibility tradeoff for ghost-completion text —
    /// his call as design authority, not an accessibility miss. **0.50 does
    /// NOT meet WCAG AA** (measured ≈3.0:1 light mode; see
    /// `ComposerDesignCallRenderTests`' evidence for the exact rendered
    /// ratio). Same production symbol `ComposerQueryField.ghostPlaceholderOpacity`
    /// pins, re-declared here (not shared) because this type has its own
    /// AppKit color path (`NSColor`, not SwiftUI `Color`) and no common base
    /// to hang a shared constant on without touching `ComposerQueryField`,
    /// which is out of scope. Deliberately kept in lockstep with that
    /// constant — this is model B (behind View → Experimental Composer
    /// Field, default OFF); `ComposerQueryField` is model A, the shipping
    /// default. If you change one, change the other.
    static let ghostOpacity: CGFloat = 0.50

    /// DEFECT 3 fix (review round 2): a small fixed trailing pad added to
    /// `ghostInkSize`'s measured (advance-width) size — see
    /// `applyStyles()`'s doc comment for why the plain advance-width
    /// measurement alone did not close the last glyph's clip (CoreText
    /// anti-aliasing bleed beyond even the reported advance width).
    /// Deliberately far short of `sizeToFit()`'s ~4pt chrome-padded frame
    /// (A-F2 rejected that for over-reserving scroll space); this only
    /// needs to cover a rasterizer's sub-pixel bleed. This margin is the
    /// thing that actually closes the clip (final review round) — see
    /// `ghostInkSize`'s doc comment for why an earlier TextKit-based
    /// "ink bounds" measurement was reverted.
    static let glyphAntialiasMargin: CGFloat = 3

    /// Fix 3 (review, round 1) computed this as `labelColor.alphaComponent
    /// * ghostOpacity` (0.4165) on the theory that it mirrors the shipping
    /// SwiftUI field's `Color(nsColor: .labelColor).opacity(0.49)` math
    /// (SwiftUI's `.opacity` multiplies the color's own existing alpha).
    /// Round 2 found that value was landing right for the WRONG reason: it
    /// was measured to match only because `installGhostLabel` ALSO set
    /// `label.textColor = .labelColor` (carrying labelColor's own 0.85
    /// alpha) — if that alpha were genuinely composited a second time on
    /// top of this value the result would be visibly darker than measured
    /// (0.85 x 0.4165 ≈ 0.354, not 0.4165). The accidental-but-correct
    /// result only held because labelColor's own alpha does NOT reliably
    /// apply in this view's rendering path (a layer-backed `NSTextField`
    /// subview inside an `NSTextView`'s document view, under an
    /// `NSHostingView`) — an ambient rendering detail, not a designed
    /// property. Fixed deliberately: `installGhostLabel` now forces the
    /// label's `textColor` alpha to `1.0` explicitly
    /// (`.withAlphaComponent(1)`), so `alphaValue` below is GUARANTEED to be
    /// the field's only alpha multiplier regardless of whether the
    /// rendering path would otherwise have honored `textColor`'s own alpha.
    /// This value still equals `labelColor.alphaComponent * ghostOpacity`
    /// (0.4165 when `ghostOpacity` was 0.49; 0.425 at the current 0.50) —
    /// it needs to, since the label's ink color is now clamped opaque and
    /// this is the ONLY place `labelColor`'s 0.85 factor is applied — but
    /// it is now the single, sole, deliberate source of the composite
    /// alpha, not a coincidental match against a second hidden one.
    static var ghostAlpha: CGFloat {
        NSColor.labelColor.alphaComponent * ghostOpacity
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Ghost semantics (Spotlight-inline-completion + Raycast-Tab-drill)

    /// The `" > "` segment separator every full destination path
    /// (`ghostFullPath`) is built from (`SessionComposerCommandParser`'s
    /// `resolutionLineSegments`/`ghostPlaceholder`, and the model-B-only
    /// `ghostFullPathForModelB` at the `SessionComposerPalette` call site).
    static let segmentSeparator = " > "

    /// Derives the ghost from the same full-path source model A's
    /// rest-state placeholder uses (D-B) — see this type's UNVERIFIED note
    /// for what this approximates and does not. Renders the FULL remainder
    /// of `fullPath` beyond whatever has been typed/accepted so far — NOT
    /// truncated at the next `" > "` — per the corrected spec: Return
    /// always launches the whole visible path, so the ghost must always
    /// preview the whole thing, not just the current segment. (`Tab`
    /// advances exactly one segment into typed text; see `nextSegment(
    /// remainder:)` below for that half.) Empty `typed` returns the whole
    /// path (also matches the 11.1 rest state, one grey). Returns `""`
    /// when `typed` isn't a case-insensitive prefix of `fullPath` — no
    /// ghost renders against text the predicted path doesn't agree with.
    static func remainderGhost(typed: String, fullPath: String) -> String {
        guard !fullPath.isEmpty else { return "" }
        if typed.isEmpty { return fullPath }
        // Fix 6b (review): the old implementation checked the prefix on
        // `.lowercased()` strings but then offset into `fullPath` by
        // `typed.count` — the ORIGINAL (not lowercased) Character count.
        // Lowercasing can change Character count (`"İ".lowercased()` is
        // two Characters, `"i̇"`), so a match confirmed on the lowercased
        // strings did not guarantee `typed.count` original characters of
        // `fullPath` corresponded to it — degenerate Unicode input only,
        // but silently misaligned the remainder. `range(of:options:)`
        // with `.caseInsensitive` + `.anchored` finds the match directly
        // in `fullPath`'s OWN indices, with no cross-string count
        // arithmetic to go stale.
        guard let prefixRange = fullPath.range(of: typed, options: [.caseInsensitive, .anchored]) else {
            return ""
        }
        guard prefixRange.upperBound < fullPath.endIndex else { return "" }
        return String(fullPath[prefixRange.upperBound...])
    }

    /// The ONE segment `Tab` accepts out of the full ghost `remainder`
    /// (Raycast-style drill-down): the rest of the segment currently being
    /// typed, PLUS its trailing `" > "` when another segment follows — so
    /// one Tab from `typed == "Bruk"` against a `"Brukas > main > Shell"`
    /// remainder of `"as > main > Shell"` lands on `"Brukas > "` (not just
    /// `"Brukas"`), immediately re-scoping the list to the next segment's
    /// candidates, matching the worked example in the composer spec. The
    /// FINAL segment (no `" > "` ahead in the remainder) has nothing to
    /// stop at, so the whole remainder is the "one segment" left to
    /// accept. This is the ONLY place a whole-remainder ghost and a
    /// one-segment-at-a-time Tab coexist without dead-ending: the old
    /// implementation cut the GHOST itself at the first separator, so once
    /// a whole segment was accepted the remainder started with `" > "`
    /// and truncating there returned `""` — Tab then had nothing left to
    /// accept even though more of the path remained. Cutting only the
    /// ACCEPT unit, never the ghost itself, removes that dead end.
    static func nextSegment(remainder: String) -> String {
        guard !remainder.isEmpty else { return "" }
        // A remainder that STARTS with the separator (typed already ended
        // exactly on a prior segment boundary) must search for the NEXT
        // one past that leading separator — searching from the start
        // would just find the leading separator itself and stop there,
        // returning only `" > "` with the following segment's name left
        // behind.
        var searchStart = remainder.startIndex
        if remainder.hasPrefix(segmentSeparator) {
            searchStart = remainder.index(remainder.startIndex, offsetBy: segmentSeparator.count)
        }
        guard let separatorRange = remainder.range(of: segmentSeparator, range: searchStart..<remainder.endIndex) else {
            return remainder
        }
        return String(remainder[remainder.startIndex..<separatorRange.upperBound])
    }

    /// FINAL REVIEW correction: this was previously a throwaway TextKit 1
    /// stack (`NSTextStorage`/`NSLayoutManager`/`NSTextContainer`), on the
    /// claim that `boundingRect(forGlyphRange:in:)` is "bearing-aware / the
    /// glyphs' true painted extent" unlike `NSString.size(withAttributes:)`.
    /// That claim was WRONG: `boundingRect(forGlyphRange:in:)` returns the
    /// union of line-fragment USED rects, which is advance-based, not ink-
    /// based — two proofs. First, the DEFECT 3 fix commit's own body says
    /// swapping to `ghostInkSize` alone reproduced an IDENTICAL hard cutoff
    /// at the same column (if it were genuinely ink-based this fix would
    /// have moved the clip). Second, its returned HEIGHT is used verbatim
    /// as the label height below, and in `step7-modelb-light.png` the
    /// ghost's ink spans the same rows (27-50) as the typed run — that is
    /// LINE HEIGHT, not a tight ink bounding box. The thing that actually
    /// fixed the clipping is `glyphAntialiasMargin` (a fixed 3pt trailing
    /// pad, below applyStyles), which this TextKit stack cost a full
    /// allocation per call to sit alongside, on EVERY `applyStyles()` call
    /// — which fires on every keystroke. Reverted to the plain
    /// advance-width string measurement `sizeToFit()` also uses, with
    /// `glyphAntialiasMargin` doing the actual clip-avoidance work (see
    /// `applyStyles()`'s doc comment for the re-measured taper proof).
    static func ghostInkSize(for text: String, font: NSFont) -> NSSize {
        guard !text.isEmpty else { return .zero }
        return (text as NSString).size(withAttributes: [.font: font])
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

        // Fix 4 (review, A-F6): font MUST be set before computing
        // `verticalInset` — `NSTextView.font` is already non-nil at
        // construction (its own AppKit default, not this field's 15pt), so
        // the `?? NSFont.systemFont(ofSize: fontSize)` fallback below never
        // fires if this line runs after. That silently centered the inset
        // against the WRONG line height. Setting the real font first makes
        // `textView.font` always non-nil AND correct, so the inset is
        // always computed against it.
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor

        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: fontSize))
        let verticalInset = max(0, (rowHeight - lineHeight) / 2)
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)

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
        // Fix 6a (review, A-F7): never `textView.string = …` directly, even
        // at construction — the file's own `setText` doc comment forbids
        // it (no undo action registered, no delegate notification), and
        // leaving the one place that violated it made it a live tripwire
        // for the next edit to copy. Routes through the same sanctioned
        // `shouldChangeText` -> `replaceCharacters(in:with:)` ->
        // `didChangeText()` triad as every other write.
        context.coordinator.setText(query, in: textView)

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

        /// Fix 2 (review) idempotency cache — see `applyStyles()`'s doc
        /// comment for what this fixes.
        private var lastAppliedGhostText: String?
        private var lastAppliedOrigin: NSPoint?

        init(parent: ComposerGhostTextField) {
            self.parent = parent
        }

        /// 7b: A-F22 — a SUBVIEW of the document view (the text view
        /// itself), not a `draw(_:)` override. Scroll lockstep, AppKit
        /// invalidation, and an accessibility element all come free; a
        /// `draw(_:)` override would have to hand-roll all three.
        ///
        /// Fix 2/3 (review): the ghost previously baked its opacity into
        /// `NSTextField.textColor` (a translucent-alpha `NSColor`). Text
        /// drawn with a translucent color onto this view's (layer-backed,
        /// fully transparent — `drawsBackground = false` top to bottom)
        /// hierarchy rendered visibly DARKER than the same alpha applied
        /// any other way — measured `rgb(66,66,66)` light /
        /// `rgb(196,196,196)` dark in `step7-modelb-light.png` /
        /// `-dark.png`, both matching `1 − (1 − 0.49)²` (a doubled 0.49
        /// composite) to three decimal places even though only ONE draw
        /// was happening. `wantsLayer = true` (an EXPLICIT own layer,
        /// rather than inheriting the "draw into the ancestor's flattened
        /// layer" behavior every AppKit view under an `NSHostingView` gets
        /// by default) plus applying the opacity as the LABEL's
        /// `alphaValue` (a single, correct, post-composite alpha blend)
        /// instead of baking it into `textColor` (full-opacity
        /// `.labelColor`, correctly antialiased) fixes it — measured
        /// `rgb(151,151,151)` light against the shipping SwiftUI path's
        /// own `rgb(149,149,149)`, within AA-rounding noise. This doubling
        /// was the historical bug this fix closed, not a description of
        /// current behavior: `ghostAlpha` applies a single multiplication,
        /// `labelColor.alphaComponent (0.85) × ghostOpacity`, with no
        /// second composite anywhere in this path. At the current
        /// `ghostOpacity` (0.50) the effective rendered alpha is
        /// 0.85 × 0.50 ≈ 0.425.
        ///
        /// BLOCKER (review round 2): that match was against the WRONG
        /// mechanism — see `ghostAlpha`'s doc comment. `textColor` is now
        /// forced to alpha `1.0` explicitly (`.withAlphaComponent(1)`) so
        /// `alphaValue` is deterministically the only alpha reduction this
        /// label applies, matching the shipping path's math on purpose
        /// rather than by an unproven rendering-path coincidence.
        func installGhostLabel(in textView: ComposerGhostNSTextView) {
            let label = NSTextField(labelWithString: "")
            label.font = textView.font
            label.textColor = NSColor.labelColor.withAlphaComponent(1.0)
            label.alphaValue = ComposerGhostTextField.ghostAlpha
            label.isSelectable = false
            label.isEditable = false
            label.drawsBackground = false
            label.wantsLayer = true
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
        ///
        /// BLOCKER 1 fix (review round 2): `replaceCharacters(in:with:)`
        /// takes a plain `String`, which carries no attributes. Writing
        /// into EMPTY storage (the common case — every `setText` call from
        /// `makeNSView`/`updateNSView` starts from an empty or
        /// about-to-be-fully-replaced text view) left the inserted run with
        /// NO preceding character to inherit attributes from, so it rendered
        /// at TextKit's own layout-manager defaults — NOT `textView.font`
        /// (this field's 15pt) or `textView.textColor` (`.labelColor`).
        /// Measured (pre-fix `0db87aef3` vs the regression, `step7-modelb-
        /// light.png`): typed "Gho" glyph height 24px -> 19px (19/24 ≈
        /// 12/15), darkest typed pixel rgb(39,39,39) (labelColor at 0.85)
        /// -> rgb(0,0,0) (unattributed). Fix: after the replace, explicitly
        /// stamp the inserted range with `textView.typingAttributes` — the
        /// same attribute dictionary AppKit itself derives from
        /// `font`/`textColor` and applies to USER-typed input via
        /// `insertText:` — so a programmatic write and a keystroke produce
        /// IDENTICAL attributes on the same range, rather than depending on
        /// storage-adjacency inheritance that silently fails on empty
        /// storage.
        func setText(_ text: String, in textView: NSTextView) {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard textView.shouldChangeText(in: fullRange, replacementString: text) else { return }
            textView.textStorage?.replaceCharacters(in: fullRange, with: text)
            let newLength = (text as NSString).length
            if newLength > 0 {
                textView.textStorage?.setAttributes(
                    textView.typingAttributes,
                    range: NSRange(location: 0, length: newLength)
                )
            }
            textView.didChangeText()
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
            let ghostText = ComposerGhostTextField.remainderGhost(
                typed: typed,
                fullPath: parent.ghostFullPath
            )
            textView.currentGhostText = ghostText

            guard !ghostText.isEmpty else {
                ghostLabel.isHidden = true
                return
            }

            // Only make the label VISIBLE once there is a real window to
            // compute its position from — before window attachment
            // (`makeNSView`'s own direct call), `firstRect(forCharacterRange:)`
            // has nothing to convert screen coordinates against and this
            // method used to fall back to the text-container-inset origin,
            // landing the label at the wrong spot. `onWindowChange` fires a
            // corrected call once the window attaches.
            guard let window = textView.window else {
                ghostLabel.isHidden = true
                return
            }

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
            guard screenRect != .zero else {
                ghostLabel.isHidden = true
                return
            }
            let windowRect = window.convertFromScreen(screenRect)
            let viewRect = textView.convert(windowRect, from: nil)
            // Fix 5 (review round 1): `firstRect`'s x left a visible gap
            // between the typed text and the ghost (`Gho stties`, not
            // `Ghostties`). Measuring the typed text's OWN width with
            // `NSString.size(withAttributes:)` (the same family
            // `sizeToFit()` uses for the ghost label, below) gives both
            // pieces a consistent measurement basis.
            //
            // BLOCKER 1 correction (review round 2): round 1's diagnosis of
            // the residual gap ("`o`→`s` glyph-pair side bearing") was
            // WRONG — see this file's header for the full write-up. This
            // line measures `typed` against `textView.font` (15pt); with
            // Blocker 1 unfixed, the ACTUAL typed glyphs drew at an
            // unattributed default (~12pt), so `typedWidth` was always
            // wider than what was really on screen, inflating the gap and
            // producing a plausible-looking-but-wrong "glyph bearing"
            // explanation. With Blocker 1 fixed (typed text now carries
            // `textView.typingAttributes`, 15pt, matching the font measured
            // here), re-measured against the freshly rendered
            // `step7-modelb-light.png`: gap is ~3.5pt logical (7px @2x) —
            // not directly comparable to round 1's ~2pt/4px figure, since
            // that number was measuring a mismatched-font comparison, not
            // a smaller version of this same gap. Not fully closed to
            // zero.
            //
            // FINAL REVIEW correction: round 2's "ordinary rounding
            // between `firstRect`'s insertion-point rect and this
            // independently computed advance width" diagnosis is WRONG —
            // `firstRect`'s x is never used past this point; six lines
            // below, `originX` is built purely from
            // `textView.textContainerInset.width + typedWidth`, and
            // `viewRect` (the only thing `firstRect` feeds) contributes
            // `minY` only. There is no horizontal `firstRect` comparison
            // for rounding to occur between. (This is the SECOND wrong
            // diagnosis of this same gap — round 1's "`o`→`s` side
            // bearing" was also wrong, above.)
            //
            // Measured facts instead: a column scan of the typed-vs-ghost
            // boundary in `step7-modelb-light.png` shows 2 blank columns
            // between glyphs INSIDE the typed run, 1-2 blank columns
            // INSIDE the ghost run, but 5 blank columns AT the
            // typed-to-ghost boundary — a systematic ~1.5-2pt excess, not
            // sub-pixel rounding slop. Prime suspect: `NSTextFieldCell`'s
            // own leading title inset (the ghost label sits at
            // `originX`, immediately after the typed run, so any
            // consistent leading inset baked into the label's own
            // drawing would land exactly here). Tested directly:
            // `label.cell?.titleRect(forBounds: label.bounds)` on this
            // font/string reports `origin.x == 0.0`, both at a
            // `sizeToFit()`-natural frame AND at a frame padded well
            // beyond the natural title size — `titleRect` itself shows no
            // leading inset, so it does not confirm this hypothesis.
            // Whether `NSTextFieldCell`'s draw-time rendering applies a
            // leading offset that `titleRect(forBounds:)` doesn't expose
            // remains UNTESTED; that piece is still a hypothesis, not a
            // measured cause.
            let typedWidth = (typed as NSString).size(withAttributes: [.font: textView.font as Any]).width
            let originX = textView.textContainerInset.width + typedWidth
            let origin = NSPoint(x: originX, y: viewRect.minY)

            // This method is a legitimate MULTI-CALL socket by design
            // (A-F3 — fired from both `onWindowChange` AND `updateNSView`,
            // which SwiftUI invokes at least once immediately after
            // `makeNSView`). Skipping the repaint when content AND
            // position are BOTH unchanged from the last applied state
            // avoids redundant redisplay work on the ordinary path where
            // nothing changed between the two calls (see
            // `installGhostLabel`'s doc comment for the actual
            // double-alpha rendering defect this file had, which was a
            // separate bug from this idempotency check). The position
            // comparison uses a SUB-POINT TOLERANCE (0.5pt), not exact
            // `NSPoint` equality — the two calls' `firstRect`
            // recomputations land at the SAME logical caret position but
            // not always the exact same `CGFloat` (TextKit layout settling
            // between the two passes), and an exact-equality guard never
            // actually matched.
            let originUnchanged: Bool = {
                guard let last = lastAppliedOrigin else { return false }
                return abs(last.x - origin.x) < 0.5 && abs(last.y - origin.y) < 0.5
            }()
            guard ghostText != lastAppliedGhostText || !originUnchanged || ghostLabel.isHidden else {
                return
            }
            lastAppliedGhostText = ghostText
            lastAppliedOrigin = origin

            ghostLabel.stringValue = ghostText
            ghostLabel.font = textView.font
            // BLOCKER (review round 2): forced opaque, same as
            // `installGhostLabel` — see `ghostAlpha`'s doc comment.
            ghostLabel.textColor = NSColor.labelColor.withAlphaComponent(1.0)
            ghostLabel.alphaValue = ComposerGhostTextField.ghostAlpha
            // `sizeToFit()` sizes the label from `NSTextFieldCell`'s own
            // `titleRect(forBounds:)`, which pads several points WIDER
            // than the string's actual measured ink width (measured:
            // `sizeToFit()` on "stties" at this font returns a 41.5pt-wide
            // frame; `(ghostText as NSString).size(withAttributes:)`
            // measures 37.4pt for the SAME string, standalone). That extra
            // width is trailing, not leading — round 1 asserted
            // `NSTextFieldCell`'s `titleRect` origin.x is 0 for the padded
            // frame with no evidence; FINAL REVIEW round tested it
            // directly (`label.cell?.titleRect(forBounds: label.bounds)`,
            // both at a `sizeToFit()`-natural frame and a frame padded
            // beyond the natural title size) and confirmed `origin.x ==
            // 0.0` in both cases — it doesn't
            // explain the fix-5 leading gap above (confirmed: this change
            // alone did not move it), but IS a real correctness gap
            // against A-F2's "document frame must include the ghost
            // width" contract, since `sizeToFit()`'s inflated width would
            // over-reserve scroll space beyond the ghost's actual ink.
            //
            // DEFECT 3 fix (review round 2): the raw-string-measurement
            // swap above went too far the other direction.
            // `NSString.size(withAttributes:)` returns the sum of glyph
            // ADVANCE widths, not the glyphs' actual painted ink extent —
            // a glyph whose outline overshoots its own advance (this
            // font's terminal `s` does, measured directly: column-ink-count
            // scan of `step7-modelb-light.png` showed the last `s` cut with
            // a HARD zero at the frame edge, not tapering the way every
            // other glyph in the string does) gets its trailing pixels
            // clipped by `ghostLabel.frame`'s width, since `NSTextField`
            // clips its cell's drawing to its own frame. Round 2 first
            // tried sizing via `NSLayoutManager.boundingRect(forGlyphRange:in:)`
            // on the theory that it's the glyph ink bounding box,
            // bearing-aware — that did NOT close the clip (re-measured:
            // identical hard cutoff at the same column), which is itself
            // proof the theory was wrong (`boundingRect(forGlyphRange:in:)`
            // is advance-based, same as `NSString.size(withAttributes:)` —
            // see `ghostInkSize`'s doc comment, corrected in the final
            // review round). The residual is anti-aliasing bleed:
            // CoreText's rasterizer paints partially-covered pixels up to
            // ~1-2px past even the reported advance width, which no
            // pre-render metric captures exactly. `ghostInkSize`'s
            // (plain advance-width) measurement plus a small fixed
            // trailing margin (`glyphAntialiasMargin`) covers that bleed
            // without reintroducing `sizeToFit()`'s ~4pt chrome padding —
            // re-measured after this fix: the final glyph tapers over
            // multiple columns (14 -> 11 -> 8 -> 0) instead of a hard
            // cutoff (see this fix set's commit body for the full scan).
            let measuredSize = ComposerGhostTextField.ghostInkSize(for: ghostText, font: ghostLabel.font ?? textView.font ?? NSFont.systemFont(ofSize: parent.fontSize))
            ghostLabel.frame = NSRect(
                x: origin.x,
                y: origin.y,
                width: measuredSize.width + ComposerGhostTextField.glyphAntialiasMargin,
                height: measuredSize.height
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

        /// 7b: Tab accepts exactly ONE segment of the full ghost
        /// (`nextSegment(remainder:)`), leaving the rest ghosted — NOT the
        /// whole remaining ghost text, which `currentGhostText` now holds
        /// in full per `remainderGhost`. G-F12 strawman (flagged, plan
        /// §11.5): typed casing is PRESERVED, resolution is
        /// case-insensitive — `Gho` + accepted `stties > ` yields exactly
        /// `Ghostties > `, never a canonical rewrite of what was already
        /// typed.
        func acceptGhost(in textView: NSTextView) {
            guard let ghostText = self.textView?.currentGhostText, !ghostText.isEmpty else { return }
            let segment = ComposerGhostTextField.nextSegment(remainder: ghostText)
            guard !segment.isEmpty else { return }
            let newText = textView.string + segment
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
