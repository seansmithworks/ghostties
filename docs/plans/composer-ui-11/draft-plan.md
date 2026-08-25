# Composer UI 11: ghost prefill (11.1) + inline completion (11.2)

Branch: `feat/composer-ui-11`, cut from `feat/composer-branch-segment` at `a1daa6608`. The parent branch is frozen (gated on Sean's hands-on pass, sole blocker on beta.24); nothing here commits to it. All PRs go to `origin` (`SeanSmithWorks/ghostties`) only. Nothing that reads local session state gets committed (public repo).

Spec sources, all read: `docs/design/composer/V02Quieted22.dc.html`, `V02Quieted222.dc.html`, `G1Rest.dc.html`, `G2Typing.dc.html`, `G3Diverge.dc.html`, `G4Inferred.dc.html`, `G5Pinned.dc.html`.

One citation correction to the research brief: `TabTitleEditor.swift` lives at `macos/Sources/Helpers/TabTitleEditor.swift`, not under `Features/Ghostties/`. Everything cited from it below uses the real path.

---

## 1. Design spec extracted from the mocks

The mocks are light-theme, fixed-hex artboards; the app is theme-aware and token-driven. The plan maps every mock value to a semantic color or existing token, and flags the deltas.

### Field (all five G artboards agree)

| Mock value | Meaning | Implementation |
|---|---|---|
| font-size 15px, line-height 20px | field text | existing `fieldFontSize` `.centered` = 15 (`SessionComposerPalette.swift:146-151`); `.anchored` stays 11 |
| `#1A1A1A` (`.typed`) | TYPED text | `NSColor.labelColor` |
| `#1A1A1A7E` (`.ghost`, alpha 0x7E = 126/255 = 0.49) | PREDICTED text | `labelColor.withAlphaComponent(0.49)` |
| `#636363` (`.settled`, G3/G4 only) | SETTLED text | `NSColor.secondaryLabelColor` |
| caret 1.5px wide, `#1A1A1A` | insertion point between typed and ghost | native NSTextView caret; ghost draws after end-of-text |
| field padding `13px 12px 10px 12px` | field container | keep existing `fieldHeight` 38 + `.padding(.horizontal, 10)` (`:1073-1074`); deltas of 2px or less vs mock are absorbed by the 4pt scale rule (DESIGN.md §5 forbids 13/10 as spacing values; 12 is legal, existing 10 is a pre-existing deviation left alone) |
| hairline `#E5E5E3` under field | field/list divider | existing `Divider()` (`:974`) |

Decision 4 (locked): SETTLED (`#636363`, already resolved) and PREDICTED (`#1A1A1A7E`, a guess) are two distinct greys and must never collapse into one.

### Results list (V02Quieted222 + G5)

| Mock value | Meaning | Implementation |
|---|---|---|
| no section headers; lanes separated by hairline `#E9E4E0`, margin `5px 10px` (G5) | RECENT/TEMPLATES headers deleted | headerless sections + inset `Divider` rows |
| row: `8px 10px` padding, radius 6, gap 1-2 | row chrome | keep existing vertical `rowVerticalPadding` 8 (`:171-176`), horizontal 8, radius 5 (`ComposerRow`, `:2062-2068`); the 10px/6px mock values violate the DESIGN.md 4pt scale and one-radius rule, so rows keep 8/5. Flagged as a deliberate reconcile, listed for Sean |
| row title 13px weight 500 `#1a1a1a` | row text | existing `rowFontSize` `.centered` = 13, `.medium` |
| selected row `rgba(91,141,239,0.20)` | selection | existing `Color.accentColor.opacity(0.2)` (`:2059`), identical value (accent is `#5B8DEF`) |
| pin glyph 10x10 in an 11px leading `slot`, `#8A8078` unselected / `#3E6FD0` selected (G5) | pinned marker | 10pt SF Symbol `pin.fill` in an 11pt-wide leading slot, `.secondary` tint, `.accentColor` when row selected; slot rendered (empty) on every row in the pinned/recent lane so titles align, exactly as G5 draws it |
| `4m` right-aligned, 11px, `#B0A8A2` (G5) | recency timestamp | `subtitleFontSize` 11, `.tertiary`; shown on any row with a recorded `lastUsedAt`, pinned or not (decision 3) |
| `New template` row, `#1A1A1A60` (alpha 0.38), last row inside list | create affordance moves into the list | new final `ComposerOption` row, `.tertiaryLabelColor`-styled title, no trailing ellipsis (mock copy is `New template`) |
| card width 360px | palette width | existing `WorkspaceLayout.composerOverlayWidth` = 360 (`WorkspaceLayout.swift:37`), no change |

### Footer hint row (G2/G3 only)

`⇥ accept  ↵ launch`, 10px, `#A9A29C`, padding `9px 12px`, above-hairline `#ECE7E2`. Implementation: 10pt (`sectionHeaderFontSize`, `:204`), `.tertiary`, shown only while a ghost completion is currently attached to typed text (G1 and G4 show no footer). This same strip doubles as the status/error strip (section 6).

---

## 2. Approach and why this decomposition

Four production steps, ordered data -> list -> field substrate -> field styling, rather than the obvious alternative (build 11.1 as one vertical, then 11.2 as another). Reasons:

1. Both directions share one substrate: the NSTextView field (model B). Building 11.1 on the SwiftUI `TextField` first would mean building ghost-prefill twice, once against a field that cannot render it in-line (macOS 13 sub-range tinting is impossible on `TextField`, settled) and once against NSTextView.
2. The list restyle (11.2's lanes, pins, timestamps, in-list New template) touches zero field code. It is the lowest-risk visible win and ships first.
3. The riskiest change in the whole plan is swapping the field's input machinery. Step 3 does that swap at strict behavior parity (same plain rendering, resolution line still present, every keyboard path re-verified) so that when Step 4 adds tri-tone rendering, any regression bisects cleanly to either "the swap" or "the styling", never both.
4. Each step is a separate commit and individually shippable; Sean can stop after any step and still have a coherent composer.

Steps 1 and 2 are pure SwiftUI/model work and carry no model-B risk at all. If model B dies in review, Steps 1-2 still stand.

## 3. Ordered steps

### Step 0: cut branch, re-measure baseline

- `git checkout -b feat/composer-ui-11 a1daa6608` (inside this worktree; the session cannot run git in sibling worktrees).
- Run the full suite once: `xcodebuild test` (Debug, `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`, derivedDataPath `macos/build`), read totals from `xcrun xcresulttool get test-results summary`. The claimed 885/0/1 baseline is re-measured here, not trusted. Do NOT touch `TEST_TARGET_NAME` (arming it fires nine GUI-driving UI tests).
- Proves: clean starting point; any later failure count is attributable.

### Step 1: data layer (recents timestamp, pins, prediction engine)

Files: `macos/Sources/Features/Ghostties/SessionComposerStore.swift`, new `macos/Sources/Features/Ghostties/SessionComposerPrediction.swift`, new tests in `macos/Tests/Ghostties/`.

1a. **`RecentComposerSelection` gains `lastUsedAt`** (schema migration, section 7).
1b. **Pinned template ids** (data model, section 8).
1c. **Prediction engine**: a new pure type, `SessionComposerPrediction`, that answers "given the current field text, parse state, recents, and pins, what is the predicted remainder and how does the full path split into settled/typed/ghost ranges". Inputs are plain values (no store access) so it is unit-testable like `SessionComposerCommandParser`:
   - Rest state (empty text): predicted path = last-used project (`recentProjectIds` head, `SessionComposerStore.swift:456-460`) `>` its branch label (same source the resolution line uses: `currentBranchLabel ?? "Default"`, `SessionComposerCommandParser.swift:1183-1186`) `>` last-used template for that project (`recentSelections` head filtered by project, `:427-429`). This renders G1's `ghostties > Default > Orchestrator`, whole line PREDICTED grey.
   - Typing: completion is offered only when the top-ranked candidate for the ACTIVE segment (text after the last `>`) has the typed text as a case-insensitive prefix. Fuzzy matches keep filtering the list but never render as ghost text (you cannot splice `stties` onto `gho` unless it is a literal prefix). Candidate domain per segment position follows the existing parser's resolution order for that position (projects for segment 1; branches and templates for later segments, template precedence matching what `Return` would commit). G2/G3/G5 all show prefix completion.
   - After a settled segment: G3 (`ghostties > ` settled, `rev` typed, `iew` ghost) and G4 (`ghostties > main > ` settled, `Orchestrator` all-ghost) fall out of the same range math.
- Tests (new file `SessionComposerPredictionTests.swift`): rest prediction from seeded recents; prefix-only completion (fuzzy match yields no ghost); tri-tone range split for G3/G4 shapes; empty-recents rest state (no prediction, plain placeholder). Migration and dedupe tests per section 7. Every test asserts on returned ranges/strings, not just non-nil (vacuous-test rule: each new test is checked by mutating the production line it guards and watching it fail).
- Proves: `xcodebuild test` green plus the new suites; no UI change yet.

### Step 2: list restyle (11.2 lanes, pins, timestamps, in-list New template)

Files: `SessionComposerPalette.swift` only (sections array `:976-981`, `ComposerResultsTable` `:1911`, `ComposerRow` `:2002`, `templateContextMenu` `:2084-2100`, `newTemplateRow` `:1287-1325`, `composerCard` tail `:1018`).

- Sections become headerless: `ComposerResultsTable` replaces its `Text(title)` header rendering (`:1943-1949`) with an inset hairline `Divider` between non-empty lanes (5pt vertical margin, 10pt horizontal, per G5). The `(title:options:)` tuple keeps its shape; titles become a11y-only lane labels (each lane gets `.accessibilityLabel` so VoiceOver users do not lose the grouping the visual headers carried).
- Lane composition changes from RECENT/TEMPLATES/PROJECTS/COMMAND to: lane 1 = pinned + recent (pinned first, decision 3; recents after, most-recent-first), lane 2 = remaining templates (resolver order, then query-ranked exactly as `filteredTemplateOptions` does today `:653-659`), lanes 3/4 = PROJECTS and COMMAND unchanged in content, headerless like the rest. `flattenedOptions` (`:687-690`) keeps mirroring on-screen order; selection/keyboard index math is unchanged because it already flattens the section array.
- `ComposerRow` gains: leading 11pt pin slot (rendered for all rows in lane 1 so titles align; empty elsewhere), right-aligned relative timestamp (`4m`, `2h`, `3d`; minutes floor at `now`, recomputed when the composer opens, not live-ticking) shown when the option's `(projectId, templateId)` pair has a `lastUsedAt`. `ComposerOption` (`:1707-1735`) gains `isPinned: Bool` and `lastUsedAt: Date?` fields (both default nil/false so existing call sites compile unchanged).
- Context menu gains Pin/Unpin (section 8).
- `New template` moves from the always-visible footer `Button` (`newTemplateRow`, `:1287-1325`) into the list as the final `ComposerOption` row, ghost-styled title. Its action triggers the existing `isAddingTemplate` inline-name flow; the inline `TextField` editor branch of `newTemplateRow` (`:1288-1302`) is KEPT and still renders in the footer position while naming is in progress; only the idle button branch is deleted. Tradeoff stated plainly: the row scrolls with the list (max height 220, `:1976`), so with many templates it is not always visible. The mock draws it as a row; that is Sean's design decision, and typical lists here are short (about 10 rows). Accepted, with the old footer restorable in one revert if he hates it.
- The `writeError` strip (`:1010-1016`) and no-match shake are untouched.
- Proves: suite green; screenshots of the four lane states (pins, recents, hairlines, New template row) at 360pt width. Layout claims are settled with pixels, not source reading (the `.frame(maxWidth:)` lesson: acceptance is visual).

### Step 3: model B field swap at behavior parity

Files: new `macos/Sources/Features/Ghostties/ComposerTextField.swift` (NSViewRepresentable + Coordinator + NSTextView subclass), `SessionComposerPalette.swift` (`queryRow` `:1055` swaps `ComposerQueryField` for the new view; `ComposerQueryField` struct `:1762-1901` is deleted in this commit), new `macos/Tests/Ghostties/ComposerTextFieldCoordinatorTests.swift`.

The new view renders IDENTICALLY to today (plain single-color text, placeholder, resolution line still present below). Only the input machinery changes.

Construction: single-line NSTextView inside an NSScrollView (no visible scrollers, horizontal elasticity off): `textContainer.widthTracksTextView = false`, container width `.greatestFiniteMagnitude`, `isRichText = false`, `isFieldEditor`-style behavior hand-built via the coordinator (see key matrix, section 4). `allowsUndo = true` so AppKit text undo keeps working; the `pendingChipUndo` overlay (`:964-971`) and its disarm via `noteSearchTextEditedByTyping()` (`searchTextBinding` setter, `:510-516`) are preserved because the coordinator routes all text changes through the same binding. Two free wins set at construction: `isAutomaticQuoteSubstitutionEnabled = false` and `isAutomaticDashSubstitutionEnabled = false`. The second one actually fixes the known `--resume` em-dash breakage that the SwiftUI `TextField` could not suppress (documented impossible for `TextField` at `SessionComposerPalette.swift:1849-1860`); the parser's smart-quote tolerance stays as a backstop.

Text sync: `textDidChange` writes `textView.string` to the `query` binding; `updateNSView` writes binding to `textView.string` only when they differ (guard against feedback loops, the standard representable dance). One representation only: the storage always equals `composerStore.searchText` verbatim. No attachments, no substituted objects, ever (locked: the two-representations bug class from the chip era).

- Proves: suite green plus the new coordinator tests (section 4 lists them); a manual keyboard matrix pass identical to the one that gated Slice A/B rounds: type/backspace/⌘A/⌘Z, ↑/↓/⌃P/⌃N/Return/Escape with picker closed, same set with project picker open, with branch picker open, Return against empty results (shake), Escape closing picker vs composer, click-outside dismiss, `+ Add project…` NSOpenPanel round trip without composer death, reopen-focuses-field, Cmd+T while open refocuses (`focusSearchFieldTrigger`).

### Step 4: in-field path rendering + resolution line deletion

Files: `ComposerTextField.swift`, `SessionComposerPalette.swift` (`queryRow` `:1055-1137`, `resolutionLine` `:1139` deleted along with `resolutionSegment`/`resolutionDot` helpers), `SessionComposerCommandParser.swift` (`resolutionLineSegments` `:1163-1196` retired or repurposed per below), `DESIGN.md`.

- **Tri-tone rendering.** Settled segments (resolved text the user typed or Tab-accepted, i.e. real characters in `searchText`) tint via `NSLayoutManager.addTemporaryAttributes` with `.foregroundColor` over the settled ranges computed by `SessionComposerPrediction`. Temporary attributes ONLY (locked): the characters stay ordinary, deletable text runs; backspace/⌘A/caret behavior is untouched because nothing but draw-time color changes. Typed active-segment text stays `labelColor` (no temporary attribute).
- **Ghost suffix.** The predicted remainder is NOT in the text storage. The NSTextView subclass overrides `draw(_:)` and paints the ghost string at the point following the last glyph (rect from `layoutManager.boundingRect(forGlyphRange:in:)` of the final glyph, or the caret origin for empty text), in the field font at 49 percent label color. Because it is drawn in the text view's own coordinate space, horizontal scrolling moves it in lockstep with the text for free. This is exactly the desync problem that killed the transparent-overlay route for `TextField` (no readable scroll offset), and it is the core reason model B exists. When empty and unfocused-prediction-absent, the standard placeholder draws instead.
- **Tab accepts.** `insertTab(_:)` in `doCommandBySelector` accepts the current segment's ghost completion into `searchText` (plus a ` > ` separator when further predicted segments remain); repeated Tab walks the path. `insertBacktab` is consumed as a no-op (a palette must not tab-cycle focus). Strawman default (flagged for Sean, one line to change): segment-at-a-time rather than whole-path accept; Return never requires acceptance, it launches the resolved selection directly, which is current behavior (`selectedOption` is seeded on open, DESIGN.md:185).
- **Return with a pure prediction** (G1, nothing typed): unchanged from today; `selectedOption` is already seeded to the predicted template, so `.submit` commits it. The prediction display and the commit path share the same source (recents), so what the field shows is what Return does. A unit test pins prediction head == seeded selection for the rest state.
- **Resolution line deleted** and its three states plus mouse route relocated per section 6.
- **Footer hint row** `⇥ accept  ↵ launch` added per section 1, sharing the strip with statuses.
- **`.anchored` presentation** (sidebar popover) gets the same field and prefill at its existing 11pt scale; it shares every code path.
- Proves: suite green plus prediction/acceptance tests; pixel screenshots of all five G states reproduced in the running app, including a deliberately long path at 360pt width to show ghost text scrolling in sync (the exact overflow case that killed the overlay approach); two-tone screenshot in BOTH light and dark themes.

### Step 5: DESIGN.md update, review rounds

- DESIGN.md §4 rewritten where it currently documents the resolution line as a shipping surface (`DESIGN.md:185-187`): the "RESOLUTION LINE" paragraph and the model-B-is-later framing (`:187`) are replaced by the in-field path spec (tri-tone semantics, the two-greys rule, ghost drawing, Tab acceptance, footer strip statuses, in-field segment click routes). §4's model A paragraph (`:183`) gets a one-line pointer that model B landed. The §6 shadow table and everything else stays.
- Review: minimum TWO independent review rounds before the PR is ready (six-for-six: every second round here has found a real defect), and any fix commit that touches layout gets a THIRD pass re-reviewing the fix as new code seeded with what the prior round cleared.
- PR to `origin` with before/after screenshots and a short interaction recording (required for UI changes). Merge is Sean's.

## 4. The six SwiftUI behaviours: AppKit replacements, macOS 13 semantics

The entire replacement uses AppKit APIs that predate macOS 13 by a decade and contain not a single `#available` branch, which is the structural argument for macOS 13 safety: there is no version-gated path to silently no-op, unlike `Backport.onKeyPress` (`macos/Sources/Helpers/Backport.swift:53-68`, returns bare `content` below 14). Verification is (i) coordinator unit tests that drive the selectors directly (app-hosted tests run from the CLI, about 33s) and (ii) `grep -c '#available' ComposerTextField.swift` == 0 as an explicit review checklist item. Honest limitation, stated as such: no macOS 13 hardware/VM is available in this environment, so 13-specific runtime verification cannot be performed here; the mitigation is the no-version-branch construction plus single-path Return, and the risk register carries it (R2).

1. **`.focused($isTextFieldFocused)` + `.onAppear` auto-focus + `focusTrigger`** (`SessionComposerPalette.swift:1841,1885-1890,1891-1900`): Coordinator calls `window.makeFirstResponder(textView)` inside `DispatchQueue.main.async` after view installation, the exact pattern `TabTitleEditor` uses (`macos/Sources/Helpers/TabTitleEditor.swift:207-219`, deferred so AppKit has created the field editor). `updateNSView` observes the `focusTrigger` binding (`SessionComposerStore.focusSearchFieldTrigger`, `SessionComposerStore.swift:106`, set at `:532`) and re-asserts first responder, then resets the trigger, preserving the S7 reopen-refocus semantics. Test: unit test hosts the view in a real `NSWindow`, flips the trigger, asserts `window.firstResponder === textView`; plus the Step 3 manual matrix.
2. **`.onExitCommand`** (`:1862`): `control(_:textView:doCommandBy:)`-style handling in `NSTextViewDelegate.textView(_:doCommandBySelector:)` for `cancelOperation(_:)`, dispatching `.exit`. Precedent: `TabTitleEditor.swift:343-347`. Always dispatched, picker open or not (the parent's `closeChipPickerOrDismiss` already arbitrates picker-vs-composer close, `:1128`). Test: invoke the delegate method with `#selector(NSResponder.cancelOperation(_:))`, assert one `.exit` event.
3. **`.onMoveCommand`** (`:1863`): `moveUp(_:)`/`moveDown(_:)` selectors in the same delegate hook, dispatching `.move(.up)/.move(.down)`, returning true so the caret does not move. Gated on `isPickerOpen` exactly as today. Test: selector-driven, both gate states.
4. **`.onSubmit`** (`:1868-1875`): `insertNewline(_:)` in the same hook, replicating today's exact guard ladder: picker open -> consume silently (never insert a newline into a single-line field); no selection -> `.submitNoMatch`; else `.submit`. This is THE macOS 13 Return path and it is the only one (see 5). Test: three-way selector test (picker open / no selection / selection) asserting the dispatched event vector, mutant-checked by relaxing each guard.
5. **`.backport.onKeyPress(.return)`** (`:1876-1884`): deleted with no replacement. It existed only as the 14+ twin of `.onSubmit`; `insertNewline(_:)` is version-independent, so Return now has exactly one code path on every macOS version. This also retires the double-fire question permanently (section 5b).
6. **Four hidden `.keyboardShortcut` Buttons** ↑/↓/⌃P/⌃N (`:1817-1836`): deleted. ↑/↓ arrive as `moveUp(_:)`/`moveDown(_:)` per item 3. ⌃P/⌃N arrive as the SAME selectors because macOS standard key bindings map Control-P/Control-N to `moveUp:`/`moveDown:` before the delegate hook, so they need no separate registration at all. Test: the selector tests cover them by construction; the manual matrix presses the literal keys.

## 5. The two invariants

**(a) Conditional mounting of the hidden Buttons.** The invariant exists because two live `.keyboardShortcut` registrations for the same key in one window have no SwiftUI resolution guarantee (`:1815-1826` documents the round-2 fix; `ProjectDropdownView.keyboardCaptureLayer`'s own doc comment at `:2215-2226` relies on it). Model B satisfies it structurally: the field registers ZERO `.keyboardShortcut`s, ever, so while a picker is open the picker's three hidden Buttons (`:2227-2248`) are the only registrations in the window, by construction rather than by conditional mounting. The residual question is different and is named in the risk register (R1): do the picker's key-equivalent Buttons still intercept ↑/↓/Return while an NSTextView (rather than a SwiftUI `TextField`'s field editor) is first responder? The mechanism is the same (the field editor SwiftUI focuses is itself an NSTextView, and `performKeyEquivalent` traversal happens at the window level before keyDown reaches the responder), so parity is expected, but Step 3's manual matrix verifies it with real keys, and the coordinator's picker-open guards (consume Return, pass arrows to no-op) are belt and braces underneath: even if an event leaks past the Buttons, it cannot insert a newline or double-drive the list.

**(b) Double-fire.** Today `.onSubmit` and `.onKeyPress` may both fire on 14+, harmless only because every `ComposerOption.action` nils `selectedIndex` synchronously first so the second fire resolves nothing. Model B removes the second Return path entirely (one `insertNewline(_:)` handler), so the double-fire cannot occur. The synchronous nil-first discipline in the commit path is nevertheless KEPT untouched, because it also protects the N4 failure-reseed flow (`:1528-1532`) and rapid double-activation by mouse. A comment at the old `:1876` site's replacement records why the discipline outlives the bug it was built for, so a future cleanup does not delete it.

Also preserved: the deliberately-removed focus-loss auto-dismiss stays removed (`:1519-1523` area documents why: the project dropdown and `+ Add project…`'s `NSOpenPanel` take first responder mid-interaction). The new Coordinator implements NO `textDidEndEditing`/resign-based dismiss whatsoever, and the review checklist carries an explicit "no focus-loss dismiss added" item.

## 6. Where the resolution line's jobs go

`resolutionLine` (`:1139`, styling documented at DESIGN.md:185-187) currently carries three states and the only mouse route into the pickers. Destinations:

1. **Mouse route into project/branch pickers**: in-field segment clicks. The NSTextView subclass overrides `mouseDown(with:)`: map the click point to a character index (`layoutManager.characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints:)`), and if it lands inside the settled project segment range or settled branch segment range (ranges already computed by `SessionComposerPrediction` for tinting), toggle the corresponding picker via the existing callbacks (same mutual-exclusion writes the resolution line's segments perform today, `:1153-1156, :1176-1178`), consuming the event; otherwise call super for normal caret placement. Ghost (not-yet-real) segments are not clickable; clicks past the end of text place the caret at the end (default behavior). The range mapper is a pure function with unit tests; the hit test itself is verified by hand in the matrix. The pickers themselves (`inlineProjectPicker`/`inlineBranchPicker`, expansion logic at `:1089-1106`) are untouched, as are the B3 refresh-on-open triggers (`:1131-1136`).
2. **"Creating…" (worktree add in flight)**: cannot live in the field (field text is `searchText` verbatim, and "Creating…" is not user text). It renders in the footer strip: `Creating worktree…` at 10pt `.secondary`, replacing the `⇥ accept  ↵ launch` hints while `composerStore.isCreatingWorktree` is true. Same strip, one occupant at a time, priority error > creating > hints.
3. **Red `branch "x" not found`**: two homes. The unresolved branch token inside the field tints `.systemRed` via the same temporary-attributes mechanism (the parser already produces `TypedBranchResolution.unresolved(token)`, `SessionComposerCommandParser.swift:1180-1182`), and the footer strip shows the full message in `.systemRed` (10pt), so the failure is legible even when the token is scrolled out of view. This preserves the pre-Return visibility the resolution line provided.
4. **"Default" (no branch override)**: becomes the predicted branch segment in the field's ghost path (G1 renders literally `ghostties > Default > Orchestrator`), and the settled label when accepted.

`resolutionLineSegments` (`SessionComposerCommandParser.swift:1163-1196`) is repurposed rather than deleted: its project/branch label and error logic feed the prediction engine and footer strip, keeping its existing tests alive; the `→ project · branch · template` row rendering is what dies.

## 7. `RecentComposerSelection` migration

Current shape (`SessionComposerStore.swift:35-38`): `{projectId, templateId}` pairs, JSON in `UserDefaults` under `ghostties.sessionComposerRecentSelections` (`:419`), cap 3 (`:420`), written only by `recordRecent` (`:431-440`) from `precommit` (`:671`).

- Add `let lastUsedAt: Date?`. Swift's synthesized `Decodable` uses `decodeIfPresent` for optionals, so already-persisted JSON lacking the key decodes to `nil` with no custom decoder and no versioning: rows from before the change simply show no timestamp until their next use. A unit test decodes a hard-coded legacy JSON string (no `lastUsedAt`) through the real decoder to pin this.
- **Dedupe fix that the naive diff would break**: `recordRecent` dedupes with `current.removeAll { $0 == entry }` (`:434`). With `lastUsedAt` participating in synthesized `Equatable`, timestamps never match and every relaunch of the same pair would stack duplicates until the cap silently ate genuine history. The predicate changes to match on `(projectId, templateId)` only. A test re-records the same pair twice and asserts count 1 with the newer timestamp.
- `recordRecent` writes `Date()`. Downgrade safety: `JSONDecoder` ignores unknown keys, so parent-branch code reading the new JSON still decodes cleanly (rollback story, section 12).
- `recentProjectIds` (`:442-471`) is untouched.

## 8. Pinning: data model and affordance

`AgentTemplate` (`Models/AgentTemplate.swift:9-110`) has no pin field, and adding one is the wrong move for three verifiable reasons: (1) built-ins and file-based presets are not persisted user templates; they are regenerated (deterministic ids: built-ins hard-coded, `AgentTemplate.swift:118+`; presets SHA-256 of filename, `PresetLoader.swift:162,254-255,435-450`), so a struct field on them would not persist; (2) a non-optional field on the `Codable` struct would throw `keyNotFound` on every existing `workspace.json` (synthesized `Decodable` only tolerates missing keys for optionals), a live data-migration hazard on Sean's real workspace; (3) `updateTemplate` refuses default templates entirely (`WorkspaceStore.swift:894`), so built-ins could never be pinned through the only write path. `Project.isPinned` (`Models/Project.swift:8`) is precedent for pinning-as-persisted-bool, but projects are always persisted objects; templates are not.

Instead, pins live beside the recents: `ghostties.sessionComposerPinnedTemplateIds`, a JSON `[String]` of template UUIDs on `SessionComposerStore`, mirroring the `recentProjectIdsData` pattern (`SessionComposerStore.swift:453-471`) including the `isolatedForTesting` domain (`:66`). Deterministic preset/built-in ids make this stable across launches for all three template groups. Pins are global, not per-project (a pinned global template shows pinned in every project); flagged to Sean as observable behavior. `togglePin(templateId:)` published so the palette re-renders; order within the pinned block is pin order (most recently pinned first), matching the "pinned sorts first" decision without inventing a second sort key.

Affordance: the existing template context menu on composer rows, `ComposerRow.templateContextMenu` (`SessionComposerPalette.swift:2084-2100`), gains a first item `Pin` / `Unpin` for every template-backed row including presets and built-ins (pinning is composer-list state, not a template edit, so the `isDefault` write-guard is irrelevant). The sibling menu it was ported from (`TemplatePickerView.swift:187-217`) is deliberately NOT mirrored; pins only affect the composer list, and touching the picker is off-objective (noted, not done).

## 9. Risks, ranked

| # | Risk | Mitigation |
|---|---|---|
| R1 | Picker keyboardCaptureLayer Buttons stop intercepting ↑/↓/Return once first responder is our NSTextView instead of SwiftUI's field editor | Same window-level key-equivalent mechanism, expected parity; Step 3 gates on the manual key matrix with both pickers; coordinator consume-guards underneath; fallback (pre-decided, small): route picker navigation through the coordinator's own `.move`/`.submit` events when `isPickerOpen`, driving `highlightedIndex` via a binding, which removes the Buttons from the equation entirely |
| R2 | Return broken on real macOS 13 (the single most dangerous fact: `.onSubmit` has no AppKit twin, `Backport.onKeyPress` is a no-op below 14) | one version-independent `insertNewline(_:)` path, zero `#available` in the new file (checklist-enforced), selector-level unit tests; residual risk stated honestly since no 13.x runtime is available here |
| R3 | Ghost drawing desyncs from text under horizontal overflow, or misaligns baseline | drawn in the text view's own coordinates so scroll moves both together by construction; acceptance criterion is a screenshot of a deliberately overflowing path; baseline taken from the layout manager's last-glyph rect, not font metrics arithmetic |
| R4 | Focus regressions (auto-focus on open, reopen refocus, NSOpenPanel round trip, no accidental focus-loss dismiss) | TabTitleEditor's deferred `makeFirstResponder` pattern; `focusTrigger` consumption preserved; explicit "no resign-based dismiss" review item; matrix covers the NSOpenPanel path |
| R5 | Recents dedupe regression from the `Equatable` change (silent history loss) | predicate matches on the pair only; dedicated test |
| R6 | Lane reorder breaks `selectedIndex`/`flattenedOptions` math or scroll-to-selection | flattening already derives from the section array (`:1927-1929, :687-690`); tests assert flattened order equals on-screen order for seeded pin/recent fixtures |
| R7 | NSTextView undo interacts badly with the chip-undo overlay (`:946-971`) | `allowsUndo = true` keeps AppKit text undo local to the view exactly as the field editor's was; the overlay's disarm path is unchanged because all typing still flows through `searchTextBinding`; matrix includes the documented D4 sequence (chip change, type, ⌘Z) |
| R8 | Two-tone illegible or wrong in dark mode (mock hexes are light-only) | all colors are semantic (`labelColor` family); light+dark screenshots are an acceptance criterion |
| R9 | This codebase's review pattern: round 2 finds what round 1 missed, six-for-six, and fix commits regress cleared paths | two mandatory independent review rounds, third pass on any layout-touching fix commit, re-review fixes as new code |

## 10. Out of scope (deliberate)

- Mirroring Pin/Unpin into `TemplatePickerView`'s menu, or any template picker restyle.
- Restyling the `.anchored` popover's type scale (it inherits behavior, keeps its 11pt scale).
- `TEST_TARGET_NAME` fix (arms nine GUI-driving UI tests; standing hazard, untouched).
- The typed `>` grammar itself, ranking algorithm changes, skills `/` prefix (reserved), per-project pin scoping, live-ticking timestamps, hover-reveal chips.
- Any commit to `feat/composer-branch-segment`, any upstream remote operation.

## 11. Assumptions (load-bearing, each one attackable)

1. SwiftUI `.keyboardShortcut` hidden Buttons intercept keys via window-level `performKeyEquivalent` before an AppKit first responder's `keyDown`, for a plain NSTextView as they demonstrably do for a focused `TextField`'s field editor (shipping behavior of the picker today). Falsified -> R1 fallback.
2. macOS standard key bindings translate ⌃P/⌃N to `moveUp:`/`moveDown:` before `textView(_:doCommandBySelector:)`, so no separate registration is needed. Falsified -> add an explicit `keyDown` check in the subclass, 5 lines.
3. `NSLayoutManager.addTemporaryAttributes` with `.foregroundColor` renders without invalidating layout on the TextKit stack a plain `NSTextView(frame:)` gets on macOS 13 through 26 (temporary attributes are the documented mechanism for exactly this, used by spell checking since 10.5). Includes the assumption that the view lands on a layout-manager-backed stack (TextKit 1 or compatibility mode) where `layoutManager` is non-nil; construction will force `textView.layoutManager` access before first draw to guarantee compatibility mode.
4. Prefix-only inline completion is the correct reading of 11.2 (`Gho` + `stties`); fuzzy matches filter the list but never ghost-complete.
5. The prediction's rest-state source (head of `recentProjectIds` + last pair for that project) matches "predicted from the last selection" in Sean's board note.
6. `Date` encodes/decodes through the store's default `JSONEncoder`/`JSONDecoder` strategy consistently (same coder pair both directions, `:428, :439`), so no explicit date strategy is needed.
7. Preset template ids remain deterministic across launches (`PresetLoader.swift:162`), making UUID-keyed pins stable.
8. The suite baseline at `a1daa6608` is green; Step 0 verifies before any change lands.
9. `xcodebuild` invocations need `ONLY_ACTIVE_ARCH=YES ARCHS=arm64` and derivedDataPath `macos/build` (repo-documented constraints).
10. The `.anchored` presentation should adopt the new field automatically; if Sean wants the sidebar popover left alone entirely, Step 4 gates the ghost rendering on `presentation == .centered` with a one-line switch.

## 12. Rollback story

- Nothing merges anywhere without Sean; the parent branch and beta.24 are untouched by construction. If he hates all of it in the morning: the branch is simply abandoned (delete via `git update-ref -d` if desired; `git branch -D` is denied in this environment). Cost: zero to `main`, zero to the parent branch.
- Partial dislike: each step is one commit; `git revert` of Step 4 alone restores the resolution line and plain field while keeping the list restyle and the NSTextView substrate; reverting Steps 3+4 restores the shipped `TextField` composer exactly (the `ComposerQueryField` deletion travels with Step 3's commit, so a revert resurrects it intact).
- Persisted state is downgrade-safe both ways: old code reading new recents JSON ignores the unknown `lastUsedAt` key (`JSONDecoder` behavior, test-pinned); the pins key is simply unread by old code; nothing rewrites `workspace.json` schema at all (the pin design specifically avoids it).
- The only unrecoverable cost of a full abandon is wall-clock time spent.

## 13. Flagged for Sean (strawman defaults chosen, not blockers)

1. Tab acceptance: segment-at-a-time (default, built) vs whole-path in one press. One-line change either way.
2. Row horizontal padding/radius: DESIGN.md-legal 8pt/5pt kept over the mock's 10px/6px. Pixel-visible only side by side.
3. Pins are global across projects (section 8).
4. `New template` row scrolls with the list; the always-visible footer property is spent (Step 2). Old footer is one revert away.
