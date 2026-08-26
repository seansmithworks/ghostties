# Composer UI 11 plan (re-draft after adversarial gate)

Branch `feat/composer-ui-11` off `a1daa6608`. Parent branch FROZEN. Origin `SeanSmithWorks/ghostties` only, never upstream. No merges, no PRs, no releases. Baseline re-measured tonight: 885 passed / 0 failed / 1 skipped, exit 0.

## 1. Ships tonight vs gated on Sean

**Ships tonight (default composer, fully verifiable):**
- 11.1 rest-state ghost path as a computed placeholder on the existing SwiftUI `TextField` (model A, zero AppKit risk, `.centered` only).
- List restyle to the two authoritative boards: headerless lanes, trailing `recent` / pin meta, single-line rows, `New template` in the list, one hairline total.
- Pinning: UserDefaults UUID list on the store with pruning, Pin/Unpin in the row context menu.
- Resolution line DELETED, all six of its labels relocated (section 4), mouse route into pickers rebuilt as trailing field controls, explicit zero-project empty state.
- DESIGN.md section 4 rewritten to match.

**Built tonight but NOT default (Sean drives it, 10 minutes, section 5):** model B `NSTextView` field with in-line typed-black + ghost-grey completion (11.2), behind `defaults write ... ghostties.composerModelBField -bool YES`. Labeled UNVERIFIED: every interaction gate is a manual key matrix this repo forbids agents to perform (A-F13).

**Gated on Sean (not built, or built as strawman needing his call):** the two DECIDE-OR-KILL questions from `BACKLOG.md` @ 2026-08-25, everything G1 to G5 proposes beyond the two boards, Tab casing, settled-grey tinting (Q2), and every item in section 11.

Superseded structural decision: ledger D-E ("resolution line survives tonight") is replaced by this re-draft's directive. The two concerns that produced D-E (G-F7 dead first run, A-F21 mouse route) are solved structurally in section 4, not by keeping the line.

---

## 2. Design spec, extracted from the two authoritative boards only

Sources: `docs/design/composer/V02Quieted22.dc.html` (11.1) and `V02Quieted222.dc.html` (11.2). Nothing from G1 to G5 drives production code.

Sean's two in-canvas notes, quoted verbatim:
- 11.1: "The ghostties > default > orchestrator text is ghosted prefill based on last selection. We don't need the sub title"
- 11.2: "I'm trying to show the ghosted prefilled text, predicting what may be typed."

| Board value | Meaning | Implementation |
|---|---|---|
| card 360px, radius 12, `#FAF7F3` | palette card | existing `composerOverlayWidth` 360, existing material background, no change |
| field text 15px / lh 20px | field type | existing `fieldFontSize` `.centered` = 15 (`SessionComposerPalette.swift:146-151`) |
| typed `#1A1A1A` | typed text | `labelColor` (already default) |
| ghost `#1A1A1A7E` (alpha 0x7E = 0.49) | ghost prefill / completion | `Color(nsColor: .labelColor).opacity(0.49)` |
| 11.1 rest state | field empty; ghost = FULL path `Ghostties > Default > Orchestrator`, one grey, no sub-ranges | model A computed placeholder (step 3) |
| 11.2 typing state | typed `Gho` black + ghost `stties` grey; ghost is the ACTIVE SEGMENT REMAINDER only, not the rest of the path | model B spike only (section 5) |
| field padding 13/12/10/12 | field container | keep existing `fieldHeight` 38 + `.padding(.horizontal, 10)` (`:1073-1074`); deltas of 2px or less absorbed, flagged |
| ONE 1px `#E5E5E3` rule, under the field | the only hairline in the card | existing `Divider()` after `queryRow`; the second `Divider()` before the footer region (`:1008`) is DELETED |
| no lane divider, no headers | lanes separated by whitespace only | headerless sections, 1pt gap, no `Divider` between lanes |
| row: padding 6px 10px, radius 6, gap 8, baseline-aligned | row chrome | adopt board values 6/10/6 (`.centered`); DESIGN.md 4pt-scale and one-radius tension flagged for Sean (section 11.4) |
| row title 13px w500 `#1a1a1a`, SINGLE LINE, no leading icon | row content | subtitle line and 16pt leading icon (G-F9, `:2038-2055`) removed from composer rows; both flagged (section 11.3) |
| trailing meta 11px `#636363`: literal `recent`, literal `Pinned Icon` | recency / pin markers | trailing slot in `ComposerRow`: `Text("recent")` at `subtitleFontSize` `.secondary`, or `pin.fill` 10pt `.secondary`. NO timestamps, NO `lastUsedAt` (G-F18) |
| selected row `rgba(91,141,239,0.20)` | selection | existing `Color.accentColor.opacity(0.2)` (`:2059`), identical (accent `#5B8DEF`) |
| `New template` row, `#1A1A1A60`, last list row, no ellipsis | create affordance | in-list row, `.tertiary`-styled, copy `New template` |
| no footer strip, no `4m`, no leading pin slot | G-artboard inventions | not built; listed in section 11.7 |

Lane order (11.2 board): lane 1 = pinned then recent, lane 2 = remaining templates, `New template` last. PROJECTS / COMMAND lanes keep their content, headerless like the rest.

---

## 3. Ordered steps

Each step is one commit, individually revertible, with its own evidence (contract in section 6). Suite invocation for every step: `xcodebuild test`, Debug, `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`, `-derivedDataPath macos/build`, counts read via `xcrun xcresulttool get test-results summary`. `TEST_TARGET_NAME` is never touched (arms nine GUI-driving UI tests).

**Step 0 - branch cut.** `git checkout -b feat/composer-ui-11 a1daa6608` inside this worktree. Baseline 885/0/1 already measured tonight; recorded, not re-run.

**Step 1 - pinning data layer.** `SessionComposerStore` gains `ghostties.sessionComposerPinnedTemplateIds` (JSON `[String]` of UUIDs, mirroring `recentProjectIdsData` `:453-471`, including the `isolatedForTesting` domain), `togglePin(templateId:)` (published), and `prunePins(validIds:)` called from `open()` with the union of user template ids (`store.templates`), preset ids, and built-in ids (all deterministic: presets are SHA-256 of filename, `PresetLoader.swift:162`). No `AgentTemplate` field, no `workspace.json` change, no `lastUsedAt`, no migration of any kind (G-F18). Tests: toggle round-trip, persistence, prune drops an orphan UUID, pin order is most-recently-pinned-first.

**Step 2 - list restyle + screenshot harness.** `SessionComposerPalette.swift` only.
- Sections array (`:976-981`) becomes: lane 1 = pinned options (pin order, filtered to `availableTemplates`, ranked within lane by `SessionComposerRanking` when a query exists) + `filteredRecentOptions` minus pinned ids; lane 2 = `filteredTemplateOptions` minus pinned ids; PROJECTS and COMMAND unchanged. All titles nil (headerless); each lane keeps an `.accessibilityLabel` so VoiceOver retains grouping.
- `ComposerResultsTable` header rendering (`:1943-1949`) deleted; no lane `Divider` added (the 11.2 board has none).
- `ComposerRow`: single line (subtitle text and leading icon not rendered in the composer list; `subtitle` still feeds ranking and a11y), trailing meta via new `ComposerOption.trailingMeta: TrailingMeta?` (`.pinned` / `.recent`, default nil, `==`/`hash` untouched since they key on `id`). Row padding 6pt vertical, 10pt horizontal, radius 6 (`.centered`; `.anchored` keeps its existing values).
- `New template` moves in-list as a non-option row rendered after the last lane inside the scroll view (NOT part of `flattenedOptions`, so zero index-math change and no interaction with the G-F8 test). Its action triggers the existing `isAddingTemplate` flow; the inline-naming `TextField` branch of `newTemplateRow` (`:1287-1302`) keeps rendering in the footer position while naming; the idle button branch (`:1305-1324`) is deleted. The second `Divider()` dies with it.
- Context menu (`:2084-2100`) gains Pin / Unpin as first item for template-backed rows.
- **G-F8 is a real behavior change and gets its own test:** pinned-ahead-of-recents moves index 0, which `onAppear` seeds (`:772`), so first-open Return now commits the top PINNED template, not the most recent. Test: seed pins + recents in isolated defaults, open, assert the seeded selection's option id equals the pinned head, mutant-verified by relaxing the lane order and watching it fail.
- Introduces the snapshot harness: an app-hosted test helper that mounts `SessionComposerPalette` (`.centered` request, isolated fixture stores) in an offscreen `NSWindow` via `NSHostingView` and writes `bitmapImageRepForCachingDisplay` PNGs to `docs/plans/composer-ui-11/evidence/` (fixture data only; safe for the public repo), light and dark.

**Step 3 - 11.1 ghost placeholder (model A).** New pure function (parser or palette scope) `ghostPlaceholder(segments: ResolutionLineSegments, hasSelection: Bool, projectsExist: Bool) -> String` feeding `ComposerQueryField`'s existing `placeholder` parameter (it is a plain `var placeholder: String` rendered by `TextField`; switch to the `prompt:` initializer form so the 49 percent grey can be applied). Gated `request.presentation == .centered` (G-F28: `.anchored` is 11pt/30pt at sidebar width and cannot fit the path; it keeps the generic placeholder). Rules, in order:
- Real project resolved AND `selectedOption != nil`: `"<project> > <branch> > <template>"`, branch = `currentBranchLabel ?? "Default"`, branch segment omitted when `!isBranchSegmentEligible`. Source is `resolutionLineSegments(...)` + `selectedOption?.title`, the same values Return commits, so field and Return agree BY CONSTRUCTION (no prediction engine exists; D-B). Arrow keys move `selectedIndex`, the placeholder recomputes, agreement holds.
- Locked and unresolvable: `"Project unavailable"` (a status, not a destination).
- `store.projects.isEmpty`: `"Add a project to begin"`.
- Otherwise (no project, or no selection): the existing generic `"Type a project, branch, and command…"`. The full path renders ONLY when Return would launch exactly that path; the field never states a destination Return will not go to.
- Note: because the placeholder only exists while the field is EMPTY, model A can never show a ghost beside typed text, so the parked `Run "mai"` hazard (ghost shown while Return shell-execs) cannot occur in model A.
- Tests on the pure function: all four branches; arrow-move changes the template segment; empty-recents rest state.

**Step 4 - status strip + zero-project empty state (resolution line still present).** Additive, so its revert is independent of the deletion.
- The `writeError` strip (`:1010-1016`) generalizes to a status strip, one occupant, priority: `writeError` (red, post-Return, unchanged) > typed-branch-not-found (red, pre-Return: `branch "<token>" not found` from `TypedBranchResolution.unresolved`). Rendered only when non-nil, so the happy-path card matches the board exactly.
- Zero-project empty state: when `store.projects.isEmpty`, the results area renders `Add project…` (a row-styled button calling the existing `composerStore.addProjectViaPanel(workspaceStore:)`, `SessionComposerStore.swift:1277`, already used at `:1245`) instead of the bare `No matches` text. This is the first-run lifeline G-F7 demanded.
- Tests: strip priority (pure computed), empty state renders the button when projects are empty.

**Step 5 - resolution line deletion + trailing picker controls.** One commit; one revert restores the line whole.
- Delete `resolutionLine`, `resolutionSegment`, `resolutionDot` (`:1139-1230`) and the two `.padding` lines mounting it in `queryRow`.
- `queryRow`'s field row becomes `HStack { ComposerQueryField; branchControl?; projectControl? }` with two compact trailing controls (plain SwiftUI Buttons, no in-field hit testing, honoring A-F21/A-F18):
  - **projectControl:** `chevron.down` glyph, `.tertiary`, subtitle scale, 16pt hit target, toggles `inlineProjectPicker` with the same mutual-exclusion writes the segment performed (`isBranchPickerOpen = false; isProjectPickerOpen.toggle()`). Hidden when `isProjectLocked` (the locked rule from DESIGN.md 187 survives verbatim: a locked composer never exposes a live picker affordance). A11y label `"Select project"`, hint `"Opens project picker"`.
  - **branchControl:** `arrow.triangle.branch` glyph, shown only when `isBranchSegmentEligible`; toggles `inlineBranchPicker` (mirror mutual exclusion). Shows a text label beside the glyph ONLY when it has news: the branch name when an override is active (`currentBranchLabel != nil`), or `Creating…` while `isCreatingWorktree`. Absence of a label means default branch; the word `Default` is never restated outside the rest-state ghost path.
- The B3 refresh-on-open trigger and the eligibility latch fix stay where they are (they live on `queryRow`'s `.onChange` modifiers, not on the line).
- `resolutionLineSegments(...)` is NOT deleted: under D-B it is the ghost placeholder's genuine source, so it is load-bearing, and its seven parser tests stay honest (G-F20 dissolved).
- Tests: control visibility matrix (locked / non-git / creating) as pure computed checks.

**Section 4 below specifies where every one of the six labels went; the deletion completes tonight, nothing about it is gated on model B.**

**Step 6 - DESIGN.md.** Rewrite the resolution-line paragraphs of section 4 (`DESIGN.md:185-187`): in-field ghost placeholder spec (source, four rules, `.centered` gate), trailing controls, status strip, board row metrics with the 4pt-scale tension recorded as Sean's open call. Shadow table untouched.

**Step 7 - model B spike, isolated and non-default.** Two commits (A-F23: independent risks split):
- 7a: `ComposerGhostTextField.swift` construction + coordinator + selector tests, flag-gated, rendering parity target.
- 7b: ghost subview + Tab accept.
Full spec in section 5. A unit test asserts the flag defaults to OFF and the default path builds `ComposerQueryField`.

**Step 8 - reviews.** Two review rounds by SEPARATE agents spawned with fresh context; the builder never reviews its own output (G-F21). Any fix commit touching layout gets a third pass reviewing the fix as new code, seeded with what the prior round cleared (repo rule). Then stop; merging and hands-on are Sean's.

---

## 4. The resolution-line deletion, solved

The line carries SIX labels (`SessionComposerCommandParser.swift:1172-1194`, read directly, not the brief's three) plus the only mouse route into the pickers. Every job gets a named successor; none requires model B:

| # | Label / job | Where it goes | Step |
|---|---|---|---|
| 1 | `Project unavailable` (locked, unresolvable) | rest-state placeholder text; Return is already dead in this state (no templates resolve), so the field states status, not a false destination | 3 |
| 2 | `Select project` (no project, unlocked; the only zero-project affordance) | the STRING dies; the FUNCTION splits in three: the always-present projectControl chevron (whose a11y label keeps the words "Select project"), the `Add a project to begin` placeholder when zero projects, and the `Add project…` empty-state row reaching the same `NSOpenPanel` flow. First run is no longer a dead composer (G-F7) | 4, 5 |
| 3 | `Default` (no branch override) | the rest-state ghost path's branch segment (the 11.1 board literally renders `Default` there). While typing it appears nowhere, deliberately: the absence of a label on branchControl means default | 3, 5 |
| 4 | `Creating…` (worktree add in flight) | branchControl's label while `isCreatingWorktree` (the store's own comment says this state is read by the chip label alone, and branchControl is that label's successor) | 5 |
| 5 | red `branch "x" not found` | status strip in red, pre-Return, full message (more legible than a tinted token, and the decided home per G-F19); `writeError` after a failed Return unchanged | 4 |
| 6 | `templateLabel: "No match"` | DELETED with no relocation: the empty results table already renders `No matches` (`:1933-1937`) and Return-with-no-selection already shakes. Two existing surfaces cover it | 5 |
| - | mouse route into project picker | projectControl chevron (trailing, in the field row, plain Button) | 5 |
| - | mouse route into branch picker | branchControl (same) | 5 |

**The one job with no model A home, stated honestly:** the mid-typing resolved-path readout. With text in the field the placeholder is hidden and a `TextField` cannot tint sub-ranges (settled fact, macOS 13), so "where will this go?" while typing has no full answer until model B renders settled segments in-field. Interim mitigation: branchControl surfaces the invisible-branch-override case (the dangerous half, since a picker-chosen branch never appears in `searchText`); the project is almost always present in the typed text or was just picked. This is a REDUCED READOUT during typing, accepted for tonight, closed by model B, and flagged to Sean (11.6). It gates nothing: it is not one of the six labels, and the deletion ships whole.

---

## 5. Model B construction spec (isolated, non-default, UNVERIFIED)

Sean chose model B; it gets built tonight, but not as the default field, because every acceptance gate for the swap is a manual key matrix and this repo forbids agent-driven synthetic keystrokes (A-F13, `feedback_subagent-gui-automation-hit-live-session`).

**How Sean drives it (10 minutes):**
1. `defaults write com.seansmithdesign.ghostties.dev ghostties.composerModelBField -bool YES` (Debug/dev build; for a Release copy use `com.seansmithdesign.ghostties`). Relaunch not required for `@AppStorage`, but recommended. Revert: same command with `-bool NO`, or `defaults delete`.
2. Before trusting what is on screen: sibling worktrees share the dev bundle id (`reference_dev-builds-share-a-bundle-id`), so confirm the PATH in `lsappinfo list` points at this worktree's build.
3. Run the key matrix in section 7. Everything in it is UNVERIFIED until his hands do it.

The swap point is one `if` in `queryRow`: flag on builds `ComposerGhostTextField`, flag off (default) builds `ComposerQueryField` unchanged.

**Construction checklist, every AppKit finding incorporated:**
- **Explicit TextKit 1 stack** (G-F15, A-F26): `NSTextStorage` -> `NSLayoutManager` -> `NSTextContainer` -> `NSTextView(frame:textContainer:)`. Never touches `textLayoutManager`; no lazy-fallback invariant to police; identical behavior 13 through 27.
- **Full horizontal-scroll sizing set** (A-F1): `isHorizontallyResizable = true`, `maxSize = (greatestFiniteMagnitude, greatestFiniteMagnitude)`, `autoresizingMask = [.height]`, `textContainer.widthTracksTextView = false`, container width `greatestFiniteMagnitude`, scroll view with `hasHorizontalScroller = false`, `horizontalScrollElasticity = .none`.
- **Parity defaults** (A-F6): `drawsBackground = false` on both view and scroll view, `textContainer.lineFragmentPadding = 0`, explicit `textContainerInset` for vertical centering in the 38pt row, `isRichText = false`. Placeholder hand-drawn is NOT needed in the spike: the model A computed placeholder logic renders via a SwiftUI overlay `Text` shown when the storage is empty (same string source as step 3), which sidesteps the no-placeholder-API problem (G-F4) entirely.
- **`isFieldEditor = true`** (A-F15, G-F10): rejects newline-bearing paste, drag-drop, and Services insertions wholesale; the delegate still intercepts `insertTab:` before field-editor default handling.
- **Ghost as a SUBVIEW, not `draw(_:)`** (A-F22, G-F5): an `NSTextField(labelWithString:)` label added as a subview of the text view (the document view), field font, `labelColor` at 0.49. AppKit invalidation and an accessibility element come free; no dirty-rect bookkeeping.
- **Ghost origin via `firstRect(forCharacterRange:)`** (A-F5): end-of-text insertion point from `firstRect(forCharacterRange: NSRange(location: storage.length, length: 0))` converted from screen to view coordinates; never `boundingRect(forGlyphRange:)` (container-coordinate and trailing-whitespace bugs).
- **Document frame includes the ghost** (A-F2): after positioning the label, if `label.frame.maxX` exceeds the text view frame, `setFrameSize` extends it so the scroll view can reveal the ghost. Behavior under AppKit re-layout is exactly the kind of thing only the manual pass can confirm; labeled UNVERIFIED.
- **One styling pass, two trigger points** (A-F3): a single `applyStyles()` (ghost content + position, future tinting) invoked from `textDidChange` AND after every programmatic write. Tonight it applies NO temporary attributes, because the 11.2 board shows only typed-black + ghost-grey and settled-grey tinting is open question Q2; the A-F3 re-apply mechanism is the built-in socket that tinting plugs into when Q2 resolves.
- **Write-back path** (A-F7, G-F16): programmatic text changes go `shouldChangeText(in:replacementString:)` -> `textStorage.replaceCharacters(in:with:)` -> `didChangeText()`, preserving `selectedRange` explicitly. Never `.string =`. `allowsUndo = true`; undo scope after composer close is a manual-matrix item, UNVERIFIED.
- **All four checkers off** (A-F4): `isContinuousSpellCheckingEnabled`, `isAutomaticSpellingCorrectionEnabled`, `isGrammarCheckingEnabled`, `isAutomaticTextReplacementEnabled` all false; quote and dash substitution also off (as a side effect, model B is the first field here where typed `--resume` survives, worth one line in Sean's matrix).
- **Key handling**: `textView(_:doCommandBySelector:)` handles `insertNewline:` (guard ladder identical to today: picker open -> consume; no selection -> `.submitNoMatch`; else `.submit`), `moveUp:`/`moveDown:` (gated on `isPickerOpen`), `insertTab:` (accept ghost: append the active segment remainder to `searchText` preserving typed casing, resolving case-insensitively, per the G-F12 strawman; flagged 11.5), `insertBacktab:` (consumed no-op), and `cancelOperation:` dispatching `.exit` and **returning true** (A-F10: unhandled, it falls through to the `complete:` word-completion panel).
- **Hidden shortcut Buttons RETAINED** (A-F11): the wrapper keeps the four ↑/↓/⌃P/⌃N `.keyboardShortcut` Buttons and the `isPickerOpen` mounting logic from `ComposerQueryField`, because deleting them narrows key handling from window scope to first-responder scope and goes dead after an `NSOpenPanel` round trip. They come out only if Sean's matrix proves them unnecessary.
- **IME suppression** (A-F14, G-F11): while `textView.hasMarkedText()`, skip the binding write, hide the ghost label, and skip `applyStyles()`; resume on the `textDidChange` after composition commits.
- **Focus** (A-F8): first responder asserted via `DispatchQueue.main.async` after installation; `focusTrigger` consumed in `updateNSView` but RESET asynchronously (never a state write during view update).
- **Teardown** (A-F20): `dismantleNSView` resigns first responder (`window.makeFirstResponder(nil)` when the view holds it) so an invisible dismissing overlay stops eating keystrokes.
- **Accessibility** (A-F17): `accessibilityValue` override returns typed text plus `, suggestion: <ghost>` when a ghost is showing, so the field never announces empty while the screen shows a path.
- **No focus-loss dismiss of any kind** (preserved deliberately; documented at `SessionComposerPalette.swift:1519-1523`).
- **No precedent exists** (G-F25, A-F9): `TabTitleEditor` is `NSTextFieldDelegate` on a field editor, a different protocol on a different class. This file is the repo's first standalone `NSTextView`, stated plainly in its header comment.

Unit tests that ARE meaningful at this level (selector-driven, app-hosted): the `doCommandBySelector` event vectors for all five selectors with both `isPickerOpen` states, `cancelOperation:` returns true, `applyStyles()` fires on `didChangeText` and after a programmatic write, flag default OFF. What they cannot see, stated in the test file's header: event ROUTING (`performKeyEquivalent` vs `keyDown`), focus delivery in a non-key window (A-F27), and everything in the matrix.

---

## 6. Evidence contract

| Step | Artifact that proves it |
|---|---|
| 0 | branch exists at `a1daa6608`; baseline totals quoted from tonight's `xcresulttool` summary |
| 1 | suite totals (>=885 pass, 0 fail) + new pin tests enumerated in the summary; each new test mutant-verified once (repo vacuous-test rule: it must name a production symbol and fail under a mutation) |
| 2 | suite totals incl. the G-F8 first-open-Return test; PNGs from the snapshot harness at 360pt, light + dark: lane state with pins + recents, plain templates state. Layout claims are settled with pixels, never source reading (`reference_swiftui-frame-maxwidth-is-greedy`: the chip-width line shipped wrong three times until a screenshot ended it) |
| 3 | suite totals + placeholder function tests; PNG of the rest state side-by-side comparable with `V02Quieted22.dc.html` (full grey path, one grey) |
| 4 | suite totals + strip/empty-state tests; PNGs: branch-not-found strip, zero-project `Add project…` state |
| 5 | suite totals; PNGs: happy-path card with NO resolution line (field + hairline + rows, matching the board), locked state (no chevron), creating state (branchControl label); grep proof `resolutionLine` has zero remaining references |
| 6 | DESIGN.md diff quoted in the commit body |
| 7a/7b | suite totals; flag-default-OFF test; PNG of the model B field rendered offscreen (typed + ghost) labeled UNVERIFIED-INTERACTION; the drive instructions from section 5 pasted into the commit body |
| 8 | two reviewer reports from separately-spawned agents, findings and dispositions inline in the PR-prep notes |

Snapshot-harness caveat, stated up front: offscreen `NSWindow` rendering is layout evidence (spacing, type, presence/absence), not material/vibrancy fidelity. Final visual acceptance is Sean's hands-on pass.

---

## 7. What CANNOT be verified overnight

- **All model B interaction.** Every gate is a manual key matrix; synthetic keystrokes and AX driving are forbidden here. The matrix for Sean: type/backspace/⌘A/⌘Z, ⌘V of multi-line text, ↑/↓/⌃P/⌃N with picker closed and with each picker open, Return (selection / no selection / picker open), Escape (picker vs composer), Tab accept + casing, `--resume` survives, option-e e (IME), `+ Add project…` round trip then arrows still work, reopen refocus, dark mode.
- **macOS 13 Return.** The dev machine is macOS 27.0; no 13.x runtime exists here. Model B's mitigation is structural (one version-independent `insertNewline:` path, zero `#available`), but 13 behavior is unverifiable tonight, full stop.
- **Mouse flows.** Synthetic clicks are as forbidden as keystrokes: the trailing controls, empty-state button, pin context menu, and picker toggles are screenshot-proven to RENDER, not to CLICK.
- **On-screen material fidelity and `.anchored` in a real NSPopover** (offscreen harness limits).
- **Undo scope across composer close** (G-F16) and the chip-undo overlay interaction: matrix items.

---

## 8. Risks, ranked

| # | Risk | Traces to | Mitigation |
|---|---|---|---|
| 1 | A relocation misses a state and some path into the pickers is dead in a configuration nobody screenshot (e.g. locked + non-git) | G-F7, A-F21 | section 4 table is exhaustive over the six labels + two routes; control visibility matrix test; reviewer 1 is briefed to attack the table |
| 2 | Placeholder states a path Return does not launch | G-F2, G-F3 | source is `selectedOption` + `resolutionLineSegments` (D-B), agreement by construction; arrow-move test; the four placeholder rules render a path only when a selection exists |
| 3 | First-open Return target silently changes under pinned-first ordering | G-F8 | dedicated mutant-verified test; flagged to Sean as a behavior change, not smuggled |
| 4 | Lane reorder breaks `selectedIndex`/`flattenedOptions`/scroll math | draft R6 | flattening already derives from the sections array (`:687-690`, `:1927-1929`); order-equality tests; `New template` kept out of `flattenedOptions` |
| 5 | Model B leaks into the default path | A-F13 | single `if` swap point; flag-default-OFF unit test; reviewer checklist item |
| 6 | Offscreen snapshots pass while on-screen layout is wrong | A-F28 | harness is layout-only evidence, stated; Sean's pass is the acceptance; both reviewers get the PNGs plus the board files |
| 7 | Pin pruning drops a valid pin (wrong id universe) or keeps orphans | G-F14 | prune tests cover user/preset/built-in ids and an orphan; prune runs on `open()`, never on a background write |
| 8 | Dark mode wrong (boards are light-hex only) | draft R8 | all colors semantic; dark PNGs required at steps 2, 3, 5 |
| 9 | Six-for-six review pattern: round 2 finds what round 1 missed, and fix commits regress cleared paths | G-F21 | two independent fresh-context reviewer agents, builder never self-reviews, third pass on layout-touching fixes |
| 10 | Model B construction defects beyond the checklist (this is the repo's first standalone NSTextView; there is no precedent) | G-F25, A-F9 | contained: non-default, isolated commits, UNVERIFIED label, every named finding incorporated in section 5 |

---

## 9. Assumptions (each attackable)

1. `ComposerQueryField.placeholder` re-renders per parent evaluation (it is a plain `var` fed at `:1071`), so a computed string updates on arrow-move. Attack: SwiftUI caching; the arrow-move snapshot would catch it.
2. `resolutionLineSegments` with empty `searchText` yields the not-typed branch case (so the rest path uses `currentBranchLabel ?? "Default"`). Attack: read `typedBranchResolution`'s empty-text behavior before step 3; if wrong, the placeholder shows an error at rest and the step-3 test fails.
3. The snapshot harness can host `SessionComposerPalette` with isolated stores in an app-hosted test. Attack: an environment-object it needs is unavailable off-window; fallback is hosting `composerCard`'s parent view with injected stores, or capturing the running app's window with `screencapture` (screen capture is permitted; driving is not).
4. `TextField(text:prompt:)` accepts a styled prompt at deployment target 13.0. Attack: availability; fallback is keeping the default placeholder grey and flagging the delta (11.8).
5. Preset/built-in template ids are deterministic across launches (`PresetLoader.swift:162`), so UUID pins and pruning are stable. Attack: a preset file rename changes its SHA id; pruning then correctly drops the pin, by design.
6. `@AppStorage`/`UserDefaults.bool` is a sufficient model B gate without a scheme change. Attack: the palette is constructed before defaults change; relaunch recommendation covers it.
7. `.anchored` behavior is unchanged by steps 3 to 5 except losing the resolution line and gaining the two controls; nothing else in the popover moves. Attack: reviewer checks the `.anchored` branch of every touched computed property.
8. The status strip's pre-Return branch error duplicates no store write path (`writeError` stays store-owned and `private(set)`; the strip merely reads two published values). Attack: a third writer appears; grep in review.

---

## 10. Rollback

- **Whole branch:** abandon it; `main`, the frozen parent, and beta.24 are untouched by construction. Delete via `git update-ref -d` if wanted (`git branch -D` is denied here).
- **Per step:** one commit each; `git revert` of step 5 alone resurrects the resolution line intact (deletion travels in that single commit); reverting 7a+7b removes model B entirely; reverting 2 restores headers/icons/subtitles.
- **Persisted state:** no schema changes exist in this plan. The pins key is additive; old code never reads it. Recents are untouched (no `lastUsedAt`). Nothing rewrites `workspace.json`. Downgrade-safe in both directions with zero migration tests needed.
- **Model B:** flag-off is the shipped state; "rollback" is not running one `defaults write`.

---

## 11. FLAGGED FOR SEAN

The two DECIDE-OR-KILL strawmen from `BACKLOG.md` @ 2026-08-25, at the top because they are still OPEN questions; both were built as strawmen tonight per apply-or-redline, neither is settled:

1. **Can an item be pinned AND recent?** Backlog strawman: pinned sorts first and keeps the pin glyph; recency shows as a right-aligned timestamp on any row. Built tonight ADAPTED, because timestamps were cut with `lastUsedAt` (G-F18): a pinned-and-recent item renders once, in the pinned block, with the pin glyph; the `recent` label appears only on non-pinned recent rows. Kill by confirming, or redline the dedupe/meta rule.
2. **Does the ghost predict the whole path, or only the template? One grey or two?** Backlog strawman: two greys, settled vs predicted, because one grey makes an inferred project and a guessed template look identical. Built tonight per the boards, which are narrower: 11.1 rest state is the WHOLE path in ONE grey (model A placeholder cannot do sub-ranges anyway), and model B's ghost is the active-segment remainder only, no settled tinting. The two-greys question is therefore still fully open; the A-F3 styling socket in model B is where the answer plugs in. Kill by confirming one grey, or direct the two-grey treatment.

Then, in rough priority:

3. **Rows went single-line with no leading icon**, exactly as both boards draw them; the template-kind icon and the subtitle line are gone from the composer list (still in ranking and a11y). One revert restores them.
4. **Row metrics adopted from the board** (6pt vertical, 10pt horizontal, radius 6) over DESIGN.md's 4pt scale and one-radius rule. Your board vs your system; DESIGN.md carries the tension note either way.
5. **Tab casing (model B):** typed casing preserved, resolution case-insensitive (`Gho` + `stties` accepts as `Ghostties` even though the project is `ghostties`). One line to flip to canonical-rewrite.
6. **Mid-typing path readout is reduced in model A:** once you type, only branchControl shows resolution state (branch override / Creating…). The full in-field answer is model B's settled rendering. Live with it until model B, or direct an interim.
7. **G1 to G5 elements deliberately NOT built** (unapproved proposals you have not seen; canvas re-seed pending so you can rule on them): footer hint strip `⇥ accept ↵ launch` (G2/G3), `4m` recency timestamps + the `lastUsedAt` schema behind them (G5), 10pt leading pin-slot column (G5), lane hairline `#E9E4E0` between pinned/recent and templates (G5), G3's typed-vs-selection divergence treatment, G4's settled-grey inferred project (that is question 2).
8. **Ghost grey is 49 percent label, about 2.4:1 contrast** (A-F17), below WCAG AA for text; it is content (it states what Return does). Fine for a ghost by convention; your call whether the a11y layer wants a darker rest-state grey.
9. **Trailing picker controls partially reinstate a trailing affordance** the model A rebuild removed (the old divided project dropdown). They are the mouse route now that the sub title is gone; alternatives are hover-reveal (your earlier idea) or keyboard-only plus typed grammar.
10. **Pins are global across projects** (a pinned global template shows pinned everywhere).
11. **First-open Return now commits the top pinned template** when pins exist (was: most recent). Deliberate consequence of pinned-first; tested; say if recents should keep the seed.
12. **Model B awaits your ten-minute matrix** (section 5); nothing about its feel is verified until then.
