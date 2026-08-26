# Refutation — AppKit/TextKit lens (composer-ui-11 draft plan)

Scope: the model-B NSTextView rewrite (Steps 3-4) and the AppKit claims in §4, §5, §6, §11.
Everything below is grounded in AppKit semantics or a verified repo line. A generalist pass covers process/scope.

---

## WRONG

### F1. The stated construction produces a field that CLIPS, not one that scrolls — which voids the entire reason model B exists

§3 Step 3 lists exactly three sizing properties: `textContainer.widthTracksTextView = false`, container width `.greatestFiniteMagnitude`, `isRichText = false`. That is not enough to get horizontal scrolling out of an NSTextView in an NSScrollView. You also need, at minimum:

```
textView.isHorizontallyResizable = true
textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
textView.autoresizingMask = [.height]        // NOT .width
scrollView.hasHorizontalScroller = false
scrollView.horizontalScrollElasticity = .none
```

Without `isHorizontallyResizable = true`, the text view's frame never exceeds the clip view's width. The container is infinitely wide so nothing wraps, but the document view never grows, so `NSScrollView` has nothing to scroll and `scrollRangeToVisible(_:)` is a no-op. Result: type past 360pt and the caret walks off the right edge and **disappears** — the text does not scroll, it clips.

Consequence if it ships: Step 3's claimed "behavior parity" is a regression in the single most basic property of a text field, and R3's mitigation ("drawn in the text view's own coordinates so scroll moves both together by construction") is arguing about lockstep motion of something that never moves.

### F2. Worse than F1: the ghost is not in the layout, so the scroll view can never reveal it

Even with F1 fixed, the ghost string is deliberately outside the text storage (§4 / line 109). The text view sizes itself to the *used rect of the real glyphs*. So:

- The document view's width stops at the end of the typed text.
- `scrollRangeToVisible` scrolls to keep the **caret** visible, which parks the caret at the right edge of the clip view.
- The ghost starts at the caret and is drawn into `bounds` that do not extend past it. NSView drawing is clipped to bounds; the ghost is clipped to zero width.

So the exact case the plan names as its acceptance criterion — "a deliberately long path at 360pt width to show ghost text scrolling in sync" (line 115) — is the case where the ghost is guaranteed invisible. And the acceptance criterion cannot detect it: a screenshot of a scrolled-right long path with the ghost missing looks like "no prediction available", which is a legitimate state of this feature.

Fix required: the ghost width must participate in the document view's frame (`frame.size.width = usedRect.maxX + ghostWidth + inset`) and be excluded from `scrollRangeToVisible` targeting, or the ghost must be a real subview of the document view. Neither is in the plan.

### F3. Temporary attributes do not survive typing — the plan treats them as set-once

Assumption 3 says `addTemporaryAttributes` "renders without invalidating layout". True but irrelevant. The load-bearing property the plan never states is lifetime: **`NSLayoutManager` clears/fixes up temporary attributes over the edited range on every text change**, via `processEditing(for:edited:range:changeInLength:invalidatedRange:)`. That is precisely why `NSSpellChecker` re-applies its `.spellingState` temporary attributes after every keystroke rather than setting them once.

Two consequences the plan does not handle:

1. Settled-segment tinting must be recomputed and re-applied after **every** `textDidChange`. Not mentioned anywhere in Step 4.
2. Programmatic writes do not fire `textDidChange` at all. `NSText.string`'s setter does not post `NSTextDidChangeNotification` and does not call the delegate. So every store-driven text change — the chip-undo restore (`SessionComposerPalette.swift:946-971`), the N4 failure reseed (`:1528-1532`), the `+ Add project…` completion — leaves the tri-tone colors pinned to stale ranges. Silent, and only visible as "the greys are wrong sometimes".

### F4. Continuous spell checking is on by default for NSTextView and it writes to the same temporary-attribute channel

`NSTextField`/SwiftUI `TextField` do not continuously spell-check; `NSTextView` does — `isContinuousSpellCheckingEnabled` seeds from the global `NSContinuousSpellCheckingEnabled` default, which is on for most users. Two failures, one cosmetic and one not:

- Red squiggles under `ghostties`, `cco`, `--resume`, every project name. Step 3 claims the new view "renders IDENTICALLY to today" (line 96). It does not.
- The spell checker applies temporary attributes **asynchronously** over ranges it chooses. Those applications overlap the plan's settled-segment `.foregroundColor` ranges and the `.systemRed` unresolved-branch tint (§6.3). The interleaving is not deterministic. This is exactly the class of bug that passes a screenshot gate and fails in use.

Must set `isContinuousSpellCheckingEnabled = false`, `isAutomaticSpellingCorrectionEnabled = false`, `isGrammarCheckingEnabled = false`, `isAutomaticTextReplacementEnabled = false` alongside the two substitution toggles the plan does name.

### F5. The ghost-origin math as specified is wrong twice over

Line 109: "rect from `layoutManager.boundingRect(forGlyphRange:in:)` of the final glyph, or the caret origin for empty text."

- `boundingRect(forGlyphRange:in:)` returns rects **in text-container coordinates**. They must be offset by `textView.textContainerOrigin` before drawing in view coordinates. Not mentioned. With the default `textContainerInset` and `lineFragmentPadding` of 5, the ghost lands 5pt+ off horizontally and misaligned vertically.
- Bounding/used rects **exclude trailing whitespace**. The composer grammar puts a space immediately before every ghost: G3 is `ghostties > ` settled + `rev` typed + `iew` ghost; G4 is `ghostties > main > ` settled + all-ghost. In the G4 shape the last real character is a space, so the last-glyph rect ends at the `>`, and the ghost is painted **on top of** the separator. This is not an edge case — it is two of the five specified states.

The correct call for "where does the insertion point after the last character sit" is `textView.firstRect(forCharacterRange:actualRange:)` (converted from screen) or `layoutManager.location(forGlyphAt:)` + `lineFragmentRect(forGlyphAt:effectiveRange:)`, not a bounding rect of the last glyph.

### F6. `NSTextView` has no placeholder, and its defaults will paint over the composer card

Line 109: "When empty and unfocused-prediction-absent, the standard placeholder draws instead." There is no standard placeholder. `placeholderString` is `NSTextField` API; `NSTextView` has no public placeholder. It has to be hand-drawn in the same `draw(_:)` override — which the plan neither budgets nor tests, and the current placeholder string is non-trivial ("Type a project, branch, and command…", `SessionComposerPalette.swift:1071`).

Same category, all Step-3 "parity" breakers not in the construction list:

- `drawsBackground` defaults **true** with `backgroundColor = .textBackgroundColor` on both the NSTextView and the NSScrollView. Step 3 as written paints an opaque white (light) / near-black (dark) rectangle across the composer card's material.
- `textContainer.lineFragmentPadding` defaults to **5**. On top of the existing `.padding(.horizontal, 10)` (`:1074`) the text shifts right by 5pt relative to today and relative to the mock's 12px.
- `textContainerInset` defaults to `(0, 0)`. A single line inside a 38pt (`.centered`) or 30pt (`.anchored`) frame — both verified at `SessionComposerPalette.swift:140-151` — renders **top-aligned**, not vertically centered as the SwiftUI `TextField` + `.padding(.vertical, 6)` does today.

Any one of these makes Step 3's stated proof ("renders IDENTICALLY to today") false, which matters because Step 3 is the bisect anchor for Step 4.

### F7. The text-sync design breaks undo — which is R7's own mitigation

Line 100: "`updateNSView` writes binding to `textView.string` only when they differ." Assigning `.string` on an NSTextView with `allowsUndo = true`:

- registers no undo action and does not close the current coalescing group, so the undo stack keeps records whose ranges refer to pre-assignment text;
- resets `selectedRange` — the caret jumps to the end of the string on any store-driven write, mid-edit;
- does not call `didChangeText()`, so no delegate callback (see F3).

R7's mitigation is "`allowsUndo = true` keeps AppKit text undo local to the view exactly as the field editor's was". It does not, because the write path chosen defeats it. The correct write-back is `shouldChangeText(in:replacementString:)` → `textStorage.replaceCharacters(in:with:)` → `didChangeText()`, preserving `selectedRange` explicitly across the replacement.

### F8. `updateNSView` resetting `focusTrigger` mutates SwiftUI state during a view update

Line 127: `updateNSView` "observes the `focusTrigger` binding … and re-asserts first responder, then resets the trigger". `focusTrigger` is `$composerStore.focusSearchFieldTrigger` — an `@Published` on an `ObservableObject`. Writing it from inside `updateNSView` is a state mutation during view update: purple runtime warning, undefined update ordering, and a plausible re-entrant update loop with `searchText` publishing on the same object. Must be `DispatchQueue.main.async`.

### F9. The `TabTitleEditor` precedent is a different protocol on a different class

§4 item 2 cites "Precedent: `TabTitleEditor.swift:343-347`" for `doCommandBySelector` handling. That code (verified, `macos/Sources/Helpers/TabTitleEditor.swift:339-355`) is `NSTextFieldDelegate.control(_:textView:doCommandBy:)` — the **NSControl/field-editor** callback, reached because an `NSTextField` is first responder and AppKit lends it the window's shared field editor. The plan needs `NSTextViewDelegate.textView(_:doCommandBySelector:)` on a standalone, non-field-editor NSTextView. Same for §4 item 1: `TabTitleEditor.swift:207-219` calls `makeFirstResponder` on an **NSTextField** and then reaches through `currentEditor()`; a standalone NSTextView has no `currentEditor()` and no deferred field-editor creation, so the `DispatchQueue.main.async` deferral is cargo-culted from a mechanism that does not apply.

The conclusion happens to hold — `NSTextView.doCommandBySelector:` does consult its delegate, and `insertNewline:`/`cancelOperation:`/`moveUp:`/`moveDown:`/`insertTab:` all arrive there via `interpretKeyEvents:` — but the plan's evidence for it is a false precedent, so nothing in the plan has actually established it.

### F10. Escape: `cancelOperation:` unhandled falls through to `complete:`

I verified the binding directly against `/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`: `0x1b` → `cancelOperation:` (and `~0x1b` → `complete:`). Good. But `NSTextView`'s own default `cancelOperation:` implementation runs `complete:` — the word-completion popup you get pressing Esc in TextEdit. §4 item 2 specifies dispatching `.exit` but **never states the return value** of the delegate method (item 3 does state `true` for the arrows; item 2 does not). Return `false` there and Escape both closes the composer *and* leaves an orphaned completion panel on screen. One-word fix, but it is the kind of omission an autonomous run will implement literally.

### F11. Deleting the four hidden Buttons narrows key handling from window-scope to first-responder-scope

§4 item 6 deletes ↑/↓/⌃P/⌃N Buttons. Today those are `.keyboardShortcut` registrations resolved at window level: they work **whether or not the field holds first responder**. In model B all four only work when the NSTextView is first responder, because they arrive through `interpretKeyEvents:`.

This is not hypothetical. The focus-loss auto-dismiss was deliberately removed precisely because focus leaves the field mid-interaction (`SessionComposerPalette.swift:1519-1523` area, quoted by the plan itself at line 140): the project dropdown and `+ Add project…`'s `NSOpenPanel` take first responder while the composer stays open. After an `NSOpenPanel` round trip, or after any click that lands on a non-text subview of the palette, ↑/↓/⌃P/⌃N go dead with no visible cause. Note also that ⌃P/⌃N are **not key equivalents at all** — they only ever reach a text responder — so there is no window-level fallback for them by construction.

### F12. R1's "belt and braces" guard is the failure mode, not the mitigation

§5(a)/R1: if the picker's Buttons stop winning against an NSTextView first responder, the coordinator's guards "are belt and braces underneath: even if an event leaks past the Buttons, it cannot insert a newline or double-drive the list."

Invert it. The guards consume Return and no-op the arrows **whenever `isPickerOpen`**. So if Assumption 1 is false, the outcome is not "a leaked event does something wrong" — it is that the project/branch picker becomes **completely un-drivable by keyboard**: arrows do nothing, Return does nothing, and Escape is the only key that responds. A dead key produces no error, no log, and no test failure.

And the specified tests cannot see it. §4's tests "invoke the delegate method with `#selector(...)`" — they call the handler directly, bypassing `NSWindow.sendEvent:` and `performKeyEquivalent:` entirely. Event *routing* is the thing at risk and selector-level tests are structurally blind to it.

### F13. Every gate on R1/R2/R4 is a manual key matrix that the overnight run is forbidden to perform

Step 3's proof (line 102) and R1/R2/R4's mitigations all reduce to "the manual keyboard matrix". This repo carries a hard rule for agent briefs: screen capture is fine, synthetic keystrokes / AX driving never (`feedback_subagent-gui-automation-hit-live-session`, after a subagent typed into a live session). An autonomous overnight run therefore cannot execute the matrix at all.

Net: by morning, the riskiest change in the plan will be marked "proved" by a green unit suite that cannot observe the failure mode, with the actual gate silently skipped. This is the single highest-probability path to unreviewable work, and it applies to Steps 3 and 4 in full.

---

## MISSING

### F14. IME and dead-key composition are not handled anywhere

`hasMarkedText()` appears nowhere in the plan. During CJK composition or an option-dead-key sequence (option-e then e for é):

- `textDidChange` fires for the **marked** (uncommitted) text, so `composerStore.searchText` receives romaji/partial input, the parser and prediction engine run on it, and the ghost renders a prediction derived from uncommitted characters.
- Any store-side normalization that round-trips through `updateNSView`'s `textView.string = ...` **destroys the marked-text session** mid-composition (unmarks, commits garbage, drops the candidate window).
- The settled-range temporary attributes are computed against character indices that include marked text, so the greys land on the composition underline.
- `insertTab:` never reaches `doCommandBySelector` during composition (the input context consumes Tab for candidate selection), so Tab-accept silently stops working — with a ghost still drawn, which reads as a broken feature.

Minimum: suppress ghost drawing and tinting while `hasMarkedText()`, and do not write the binding until composition commits.

### F15. Newlines can still enter a "single-line" field

`insertNewline:` is handled, but paste is not. `⌘V` of multi-line text, drag-and-drop of text, and the Services menu all route through `insertText(_:replacementRange:)` / `readSelection(from:)`, not through `doCommandBySelector`. `isFieldEditor = true` is the AppKit property that makes a text view reject newlines wholesale; the plan says field-editor behavior is "hand-built via the coordinator" and then builds only the key path. Need `textView(_:shouldChangeTextIn:replacementString:)` filtering, or set `isFieldEditor = true`.

### F16. No invalidation strategy for the ghost

The prediction changes on every keystroke, but NSTextView only invalidates the edited region (plus the caret rect on blink). `draw(_:)` receives a **partial dirty rect**. A shrinking ghost leaves residue; a ghost overlapping the blinking caret rect gets re-composited over an un-cleared background every 0.5s (visible weight/antialiasing drift). The plan needs an explicit `setNeedsDisplay(oldGhostRect.union(newGhostRect))` on every prediction change and on caret movement. Not mentioned.

### F17. Accessibility: the field's accessibility value will lie about its own contents

`NSTextView`'s accessibility value is its string. The ghost is not in the string and custom `draw(_:)` output is invisible to the accessibility tree. Combined with deleting the resolution line — which was real, readable `Text` — the result is:

- At rest (G1) the field is announced as **empty** while the screen shows `ghostties > Default > Orchestrator`. That whole state is the feature.
- The settled/predicted grey distinction (§1 Decision 4, "must never collapse") has no non-visual equivalent at all.
- This lands on a surface that deliberately hides everything else from VoiceOver while open (`WorkspaceViewContainer.swift:1709-1712` un-hides sidebar/terminal on close, i.e. they are hidden while the composer is up). The composer field is essentially the only a11y content, and the plan makes it lie.

Also unaddressed: `labelColor.withAlphaComponent(0.49)` is roughly 2.4:1 against the light card — well under WCAG AA 4.5:1 — and it is content, not decoration, because it states what Return will do. The project's design layers include `a11y` (CLAUDE.md).

Minimum: `accessibilityValue` override returning typed + predicted with the prediction marked, or an `NSAccessibility` custom element / `accessibilityHelp` carrying the ghost string.

### F18. The mouse hit test in §6.1 has the same coordinate bug as the ghost origin, and loses selection gestures

`layoutManager.characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints:)` takes a point in **text-container** coordinates. The plan says "map the click point to a character index" with no `convert(_:from: nil)` + `textContainerOrigin` subtraction. Off by the inset and the 5pt line-fragment padding — enough to mis-hit at segment boundaries, which is where users click.

Separately, overriding `mouseDown(with:)` and consuming it inside settled ranges kills drag-select and double-click-to-select-word over exactly the text users most want to edit (the project name). And there is still no keyboard route into the pickers — the arrow keys can place the caret inside the settled project range and nothing happens, which is the same spec gap Slice A shipped open on the chip.

### F19. `maxRecents` is 3, so the timestamp column can never appear on more than three rows

Verified: `SessionComposerStore.swift:420` `maxRecents = 3`, deduped on the pair, written only from `precommit`. §1 line 38 shows `4m` on rows "with a recorded `lastUsedAt`". Pinned templates outside the top-3 recents will never have one, so G5's pinned lane renders with a permanently empty timestamp column. Either raise the cap (a separate persisted-state change with its own migration) or accept that the mock's timestamp column is mostly blank — the plan does neither and does not notice.

### F20. No first-responder teardown on dismiss

The overlay dismiss animates `alphaValue` to 0 (`WorkspaceViewContainer.swift:1736-1741`) before removal. An NSTextView that is still first responder keeps receiving keystrokes while invisible. The terminal restore at `:1727-1732` is guarded on `window?.isKeyWindow == true` for good reasons documented there, so there is a window where nothing has focus. Today SwiftUI's focus system resigns on disappear; model B has no equivalent and the plan explicitly adds no resign handling (§5, line 140 — correctly refusing a resign-based *dismiss*, but that is a different thing from resigning on teardown).

---

## OVERVALUED / GOLD-PLATED

### F21. §6.1 (in-field segment click routing) should be cut from this run

It reimplements a working, shipping mouse route (`resolutionLine`, the only mouse entry into the pickers) inside the hardest possible medium — glyph-level hit testing in a view whose coordinate math the plan already gets wrong twice (F5, F18) — for zero new user capability. Keep the resolution line as the mouse route through Step 4 and delete it only after Sean has hands-on with the in-field rendering. That also removes the §6.2/§6.3 relocation work and the footer-strip priority machine from the overnight critical path.

### F22. The `draw(_:)` override is the expensive way to buy the one property that motivated it

The stated motive is scroll lockstep. A subview of the document view gets that for free, gets AppKit's invalidation for free (F16), and can carry an accessibility element (F17). The `draw(_:)` route buys nothing extra and owns three problems the plan has not costed. If the override stays, it must at least handle partial dirty rects and hand-draw the placeholder (F6).

### F23. Step 4 bundles six independent risks into one commit

Tri-tone tinting + ghost drawing + Tab acceptance + resolution-line deletion + footer strip + in-field mouse routing + DESIGN.md, all in the step that cannot be verified without hands. §2's whole bisect argument ("any regression bisects cleanly to either the swap or the styling") collapses inside Step 4, where six mechanisms land together. If Step 4 runs at all tonight, split at minimum: tinting-only commit, ghost-drawing commit, acceptance commit.

---

## EVIDENCE

### F24. Assumption 1 was never verified against anything, and the code cited in its support explicitly disclaims verification

§5(a) and R1 argue by analogy: "the mechanism is the same (the field editor SwiftUI focuses is itself an NSTextView…), so parity is expected". No file, no experiment. Meanwhile the doc comment the plan leans on for invariant (b) says, verbatim (`SessionComposerPalette.swift:2200-2206`): *"this repo cannot verify from source alone whether `.onSubmit`/`.onKeyPress` actually both fire, only that a double-fire is harmless if they do."* The plan cites that comment block as establishing the invariant it disclaims. Invariant (a)'s citation (`:2215-2226`) is likewise a doc comment written by this same fork describing an intended arrangement, not evidence about AppKit dispatch order.

On the merits, `NSWindow.sendEvent:` does run the view tree's `performKeyEquivalent:` before `keyDown:` reaches the first responder, so Assumption 1 is *probably* true — but "probably" is carrying Step 3's entire acceptance and nothing in the plan can distinguish it from false (F12).

### F25. Assumption 2 is TRUE — verified — but the plan's reasoning about it is wrong

I checked `StandardKeyBinding.dict` directly: `^p` → `moveUp:`, `^n` → `moveDown:`, `0xf700`/`0xf701` → `moveUp:`/`moveDown:`, `0x1b` → `cancelOperation:`, `\t` → `insertTab:`, `0x19` → `insertBacktab:`. So §4 item 6 lands. Two caveats the plan does not state: a user-installed `~/Library/KeyBindings/DefaultKeyBinding.dict` overrides these (Sean is a terminal user; not exotic), and these bindings are delivered via `interpretKeyEvents:`, i.e. **only to a first-responder text view** — which is the narrowing in F11. The plan's phrasing "before the delegate hook" describes a layer that does not exist.

### F26. Assumption 3's TextKit-1 claim is right but the construction is order-dependent, and the wrong half of the assumption is the load-bearing half

Accessing `NSTextView.layoutManager` does trigger Apple's documented TextKit 1 compatibility fallback on Ventura+, so `layoutManager` will be non-nil and `addTemporaryAttributes` will work on 13 through 26. Conceded. But:

- The fallback is *lazy and ordering-sensitive*. "Construction will force `textView.layoutManager` access before first draw" is a comment-enforced invariant that any later refactor (or a `textLayoutManager` touch from an intervening line) silently breaks. The deterministic construction is to build the TextKit 1 stack explicitly — `NSTextStorage` → `NSLayoutManager` → `NSTextContainer` → `NSTextView(frame:textContainer:)` — which never enters TextKit 2 in the first place. Same line count, no invariant to police.
- The half of Assumption 3 that actually carries the feature is the unstated one — that temporary attributes persist across typing — and it is false (F3).

### F27. The specified focus test proves less than it appears to

§4 item 1: "unit test hosts the view in a real `NSWindow`, flips the trigger, asserts `window.firstResponder === textView`". An app-hosted test window is not key and not on screen; `makeFirstResponder` succeeds in a non-key window and grants no keyboard delivery. The assertion passes in exactly the configuration where the behavior it stands for (keystrokes reach the field) is untestable. It is not a vacuous test by the repo's own definition — it names a production symbol — but it is a green light for something it never measured, which is the same failure shape.

### F28. Step 3's proof is stated as a fact it cannot have checked

Line 96: "The new view renders IDENTICALLY to today (plain single-color text, placeholder, resolution line still present below)." This is asserted, not measured, and F4/F6 show it is false on at least five NSTextView defaults before a single line of styling is written. The repo's own hard-won rule applies (`reference_swiftui-frame-maxwidth-is-greedy`: the chip-width line shipped wrong three times on source-reading alone; a screenshot ended it). Step 2 correctly adopts "acceptance is visual" (line 90). Step 3, the higher-risk step, does not.

---

## WEAKEST ASSUMPTION

**Assumption 3 — specifically its unstated half: that `addTemporaryAttributes` is a set-once mechanism that survives typing.**

It is not. `NSLayoutManager` fixes up and clears temporary attributes over the edited range on every text change (which is why the spell checker re-applies its own on every keystroke), and programmatic `.string` assignment does not even notify the delegate that a recompute is needed. Temporary attributes are the *only* mechanism the plan has for the settled/predicted grey distinction — Decision 4, locked, "must never collapse into one" — and for the `.systemRed` unresolved-branch tint that §6.3 makes the pre-Return error surface.

If it is false, and it is: the tri-tone rendering degrades intermittently and non-deterministically — correct right after a full re-apply, wrong after a mid-string edit, wrong after any store-driven text change, and racing the spell checker's async passes. None of that is caught by a unit test on the range-math function (which is pure and will be green), and none of it is caught by a screenshot taken immediately after a fresh render, which is the only acceptance criterion Step 4 has. It ships looking correct and fails in use, on the one feature the whole plan exists to build.

Runner-up: Assumption 1, not because it is likely false (it probably is not) but because F12 + F13 mean the plan has no mechanism whatsoever to find out.

---

**VERDICT: rethink** — the AppKit half, not the whole plan. Steps 0-2 (data layer, prediction engine, list restyle) are sound, verifiable without hands, and should run tonight as planned. Steps 3-4 must not run unattended: their entire acceptance rests on a manual key matrix the overnight agent is barred from performing (F13), and four independent silent-breakage defects (F1/F2 scroll+clip, F3/F4 temporary-attribute lifetime, F5 ghost origin, F7 undo/caret) would all pass the specified gates. **The single most important change: stop the overnight run after Step 2, and convert Step 3 from "swap the field and prove parity by hand" into a standalone, screenshot-gated spike that Sean drives for ten minutes before Step 4 is written at all.**
