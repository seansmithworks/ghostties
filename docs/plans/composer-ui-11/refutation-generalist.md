# Refutation — composer UI 11 draft plan (generalist adversarial pass)

Read against the worktree at `a1daa6608`. Every citation below was opened, not inferred.

## 1. WRONG

**F1 — The plan builds the wrong artboards. 11.1 and 11.2 are `V02Quieted22` / `V02Quieted222`; G1–G5 are Claude's own unapproved build-out.**
Sean's own commit `a1daa6608` (`BACKLOG.md`) states it flatly: *"They are `V02Quieted22.dc.html` (titled **11.1**) and `V02Quieted222.dc.html` (titled **11.2**)"*, and of the G files: *"Claude's build-out of this direction is on disk as `G1Rest` / `G2Typing` / `G3Diverge` / `G4Inferred` / `G5Pinned` … **They are NOT in the live canvas**."* The plan's §1 opens "Field (all five G artboards agree)" and derives its spec from them. What that costs, verified against the two authoritative files:

- **The ghost is `stties`, not the whole path.** `V02Quieted222.dc.html` renders typed `Gho` + ghost `stties` — full stop, no `> Default > Orchestrator`. The original request says the same ("`Gho` solid + `stties` ghosted"). The plan's §1c/§4 build "the predicted remainder" as the whole remaining path, sourced from G2/G5.
- **There is no lane hairline in 11.2.** `V02Quieted222` has exactly one `1px #E5E5E3` rule — under the field. Between pinned/recent and templates there is nothing but the 1px flex gap. Step 2's "inset hairline `Divider` between non-empty lanes (5pt vertical margin, 10pt horizontal, per G5)" ships a rule Sean's board deleted. The board is literally titled "Quieted — headers become rules" and then drops the rules.
- **The pin marker is a trailing meta label, not a leading slot.** `V02Quieted222` row 1: `<div …flex-grow:1>cco</div><div style="font-size:11px;color:#636363">Pinned Icon</div>` — same trailing slot the word `recent` occupies. G5's 10×10 leading-slot glyph is Claude's invention.
- **There are no timestamps.** Both authoritative boards show the literal string `recent` in the trailing slot. `4m` appears only in G5, on one row.
- **There is no footer hint strip.** `⇥ accept ↵ launch` exists only in G2/G3. The plan makes that strip the new home for `Creating…` and the red branch error (§6.2, §6.3) — an entire relocation strategy resting on a surface that appears in no board Sean directed.
- Row padding in both authoritative boards is `6px 10px`, not the `8px 10px` §1 cites from G5.

Consequence: by morning the composer carries a pin column, a timestamp column, a lane divider and a footer strip that Sean never asked for, and a ghost that spans three segments where his board shows one. All four are visible in the first screenshot, all four are wrong, and each is entangled with production code (§6 error routing depends on the footer).

**F2 — The ghost path and Return will disagree the moment ↑/↓ moves the selection.**
Step 4 claims: *"The prediction display and the commit path share the same source (recents), so what the field shows is what Return does."* False. Return commits `selectedOption` (`SessionComposerPalette.swift:698-706`), driven by `selectedIndex`, which `handle(.move(...))` rewrites on every arrow press (`:1553-1560`). Today's resolution line takes `templateTitle: selectedOption?.title` (`:1147`) so it tracks the highlight live. The plan's ghost comes from a *separate* `SessionComposerPrediction` keyed off `recentSelections`. Arrow down one row and the field says `ghostties > Default > Orchestrator` while Return launches Codex. The unit test the plan proposes ("prediction head == seeded selection for the rest state") pins the only case where they agree and certifies the bug as correct.

Worse, this collides with the hazard Sean parked in the same commit: *"typing `main` then backspacing to `mai` leaves `Run "mai"` as the sole row, auto-selected; Return shell-execs it."* Under this plan the field would be showing a ghosted template name while Return shell-execs `mai`. The plan never mentions the parked item.

**F3 — Assumption 5 is falsified by `SessionComposerRequest.ProjectBinding`.**
The composer opens `.locked(Project)`, `.prefilled(Project)`, or `.open` (`SessionComposerStore.swift:404-412`). `currentProject` resolves from `commandProject` then `selectedProjectId` (`:215-223`), and `recentOptions` is filtered `$0.projectId == project.id` (`:632-635`). Every sidebar-anchored open is bound to *that row's* project. The plan's rest-state prediction takes the head of `recentProjectIds` (§1c) — a different project. In the `.anchored` presentation, which assumption 10 says adopts the new field automatically, the field would ghost-prefill a project the composer cannot launch into.

**F4 — `NSTextView` has no placeholder.**
Step 3 promises the new view "renders IDENTICALLY to today (plain single-color text, placeholder…)" and §4 Step 4 says "the standard placeholder draws instead". There is no public placeholder API on `NSTextView` — that property lives on `NSTextFieldCell`. The placeholder (`"Type a project, branch, and command…"`, `:1069`) must be hand-drawn in the same `draw(_:)` override as the ghost, with its own empty/focused/prediction-absent state machine. The plan budgets zero work for it and asserts a free API that does not exist.

**F5 — The ghost will be clipped, and will leave residue.**
§4 draws the ghost after the last glyph inside the text view's own coordinate space. Two unhandled consequences:
- A single-line horizontally-scrolling `NSTextView` sizes its frame to its *content*. At rest (11.1's entire case) the string is empty, the frame is ~0pt wide, and the ghost draws outside `bounds` — clipped by the clip view. 11.1 renders nothing.
- `draw(_:)` receives a dirty rect. AppKit invalidates minimally on edit; the region past the last glyph is not part of it. Backspacing from `ghos` to `gho` will not repaint the vacated ghost tail unless the view explicitly invalidates it. The plan has no `setNeedsDisplay` strategy anywhere. R3's mitigation addresses scroll desync only.

**F6 — In-field segment clicks ignore `.locked`.**
§6.1 routes a click inside the settled project range to "toggle the corresponding picker". `resolutionSegment` is deliberately non-clickable when `isProjectLocked` (`:1209-1215`, and `DESIGN.md:187`: *"a locked composer must never expose a live picker affordance"*). The plan carries no lock gate. Shipped as-is, a locked composer opens a project picker whose selection `commit()` then ignores (`:666-670`) — the exact N3 divergence the code comments say was closed.

**F7 — Deleting the resolution line deletes the only project affordance in the empty state.**
`resolutionLineSegments` (`SessionComposerCommandParser.swift:1172-1194`) emits five labels, not the three §6 enumerates: `"Project unavailable"` (locked, unresolvable), `"Select project"` (no project — `DESIGN.md:187` calls it *"the only project affordance in the composer, reachable with zero projects"*), `"Default"`, `"Creating…"`, and the red not-found string; plus `templateLabel: "No match"`. In-field click routing requires a *settled project segment range* to hit. With zero projects there is no such range and no picker entry point — the trailing dropdown was removed in the model A rebuild. First-run with no projects becomes a dead composer. Nothing in §6 relocates `"Select project"`, `"Project unavailable"`, or `"No match"`.

**F8 — "The list restyle touches zero field code… lowest-risk visible win" is wrong.**
Step 2 rewrites lane composition, i.e. `flattenedOptions` (`:687-690`). That array feeds `bestSelectionIndex` (`:712-728`), `selectedOption`, the resolution line's `templateLabel`, and what Return commits. Reordering pinned ahead of recents changes index 0 on a blank query — which is exactly what `onAppear` seeds (`:772`). Step 2 silently changes what Return does on first open. R6 frames this as "breaks index math"; the real risk is that the math stays correct and the *target* changes.

**F9 — `ComposerRow` already renders a 16pt leading icon.**
`:2038-2043` draws `Image(systemName: option.leadingIcon).frame(width: 16)` on every template row, and `makeOption` always supplies one (`iconName(for:)`, `:620-627`). Neither authoritative board nor G5 shows an icon. Step 2 adds an 11pt pin slot *in front of it* and claims the result is "exactly as G5 draws it". It is not: G5 has a pin slot and no icon, on every row in both lanes including `New template` — the plan puts the slot on lane 1 only, which is a third option matching neither board. Also unreconciled: the shipped row is two-line (title + `subtitle` in a `VStack`, `:2046-2055`); every board is single-line with trailing meta.

## 2. MISSING

**F10 — Newline-bearing paste and drag-drop.** A `TextField` strips newlines; an `NSTextView` does not. Intercepting `insertNewline(_:)` stops the Return key, not `⌘V` of `foo\nbar`, and not a text/file drag onto the view. `searchText` is the parser's input (`SessionComposerCommandParser.tokenize`) and is written verbatim to the store. No sanitiser is specified anywhere in Step 3.

**F11 — Marked text / IME.** `updateNSView` writing `binding → textView.string` mid-composition tears down the marked range. `TextField` handles this; the plan's "standard representable dance" guard is `!=` on the whole string, which is true during composition. Not Sean's daily path, but it is a silent corruption class.

**F12 — Case handling on Tab acceptance.** `V02Quieted222` shows typed `Gho` completing to ghost `stties` against a project literally named `ghostties`. What does `insertTab` write — `Ghostties` (typed casing + remainder, which is not a real project name) or `ghostties` (a retroactive rewrite of characters the user typed)? The parser's project match is the arbiter and the plan never says. Ship the first and Tab produces a string that does not resolve.

**F13 — R1's fallback is not small.** "Route picker navigation through the coordinator's own `.move`/`.submit` events when `isPickerOpen`, driving `highlightedIndex` via a binding" requires converting `@State private var highlightedIndex` to a binding in **two** private views (`ProjectDropdownView` `:2122+`, `WorktreeDropdownView` `:2377+`), rewiring both `.onAppear` seeds, `WorktreeDropdownView`'s shrink clamp (`:2384-2395`), and both private `commitHighlighted()`s — plus `WorktreeDropdownView`'s own third capture layer against its `New branch name…` field (`:2306-2322`). That is a multi-view refactor at 4am, presented as a pre-decided one-liner.

**F14 — Nothing prunes the pins list.** `ghostties.sessionComposerPinnedTemplateIds` is uncapped and never reconciled against `store.templates`. Delete a pinned user template and the UUID persists forever; rename a preset *file* and its SHA-256 id changes (`PresetLoader.swift:162`), silently orphaning the pin. Recents are capped at 3, which is why they never showed this.

**F15 — No macOS 13 verification exists, and §4's structural argument is weaker than stated.** "Zero `#available`" is true and irrelevant to the actual 13-specific risk, which is the TextKit stack: `NSTextView(frame:)` gets TextKit 2 by default, and `addTemporaryAttributes` requires an `NSLayoutManager`. Assumption 3 handles this by forcing compatibility mode — correct — but that forcing is the one construction detail whose behaviour differs across 13/14/26, and it is the one thing that cannot be tested here. The mitigation named ("`grep -c '#available' == 0`") does not test it.

**F16 — Undo scope.** `allowsUndo = true` on a fresh `NSTextView` per composer open registers against the window's undo manager, not a field editor that AppKit tears down on focus change. R7 asserts parity with "exactly as the field editor's was" without checking `undoManagerForTextView(_:)`. The D4 matrix item tests the chip-undo overlay, not undo *after* the composer closes.

## 3. OVERVALUED / GOLD-PLATED

**F17 — 11.1 does not need model B at all. This is the biggest cut available.**
11.1's rest state is: field empty, whole path in one grey, one font, no sub-ranges. That is a placeholder string. `TextField(_:text:prompt:)` renders it today, correctly, at both presentations, with zero risk — and the plan itself concedes the empty case falls back to the placeholder. Only 11.2's typed-black + ghost-grey *pair* needs sub-range control. Sean was shown the model-B risk and chose it, so keep it on the branch — but sequencing 11.1 behind Steps 3 and 4 means the safe half of tonight's work cannot land if the risky half stalls, and §2's justification ("building ghost-prefill twice") is false: the placeholder route is one computed `String`, not a build.

**F18 — Cut Step 1a (`lastUsedAt`) entirely.** The whole schema migration (§7), its legacy-decode test, and the `Equatable` dedupe hazard (R5) exist to render `4m` — which appears in exactly one non-authoritative artboard. Sean's boards show the static word `recent`, and `filteredRecentOptions` already knows which rows are recent. This is a persisted-state change, taken overnight, to satisfy a mock he never saw.

**F19 — Cut the footer strip.** No authoritative board has it, and §6 makes it structural by hanging `Creating…` and the branch error on it. Both belong in the existing `writeError` strip (`:1010-1016`), which is already built, already `.systemRed`, already positioned, and already untouched by Step 2 per the plan's own line.

**F20 — `resolutionLineSegments` "repurposed rather than deleted… keeping its existing tests alive"** (§6). Seven assertions in `SessionComposerCommandParserTests.swift` reference it. Keeping a function alive so its tests stay green is tests driving design. Either the segment logic is the ghost path's source (see the fix below, in which case it is genuinely load-bearing) or it is dead and its tests should die with it.

**F21 — "Two mandatory independent review rounds" is not a mitigation for R9.** The six-for-six pattern is *a second reader finding what the first missed*. Overnight, both rounds are the same actor re-reading its own output in the same context window. R9's mitigation is R9.

## 4. EVIDENCE

**F22 — The spec sources were read but not ranked.** §1 says "Spec sources, all read" and lists seven files as peers. `git show a1daa6608` — the commit the branch is cut from — separates them explicitly: two are Sean's directions, five are Claude's dropped build-out. The plan quotes neither of Sean's in-canvas notes (`"ghosted prefill based on last selection. We don't need the sub title"`, `"trying to show the ghosted prefilled text, predicting what may be typed"`), both of which are embedded as text in the artboards it says it read. Every gold-plated surface in F1 traces to this one un-made distinction.

**F23 — "Decision 4 (locked)" and "decision 3" have no source.** Both are the *open* strawmen in `a1daa6608`, under a checkbox headed **"DECIDE OR KILL — two open design questions** blocking a clean 11.1/11.2 build", each ending "Kill by confirming." The plan converts unconfirmed strawmen into settled decisions and then omits them from §13's four flagged items. Building the strawman is right; calling it locked and dropping it from the morning list is how the question never gets answered.

**F24 — §6's three states came from the brief's wording, not from the function.** The brief says "renders three states nothing else does: Default, Creating…, and a `.systemRed` branch-not-found error." `resolutionLineSegments` (`SessionComposerCommandParser.swift:1172-1194`) returns six labels. The plan reproduced the brief's count exactly, including its omissions — F7 is the cost. A `sed` of those 30 lines would have caught it.

**F25 — The AppKit precedents cited do not exist in this repo.** `grep -rn "NSTextView(" macos/Sources/` returns zero. `TabTitleEditor.swift:339-354` — cited at §4.2 as `TabTitleEditor.swift:343-347` — is `NSTextFieldDelegate.control(_:textView:doCommandBy:)` on an `NSTextField`'s field editor, a different protocol on the exact architecture model B replaces. `TabTitleEditor.swift:206-219`, cited at §4.1 as "the exact pattern", makes an `NSTextField` first responder. The plan is not wrong that these are the closest things available; it is wrong to present them as precedent rather than as *there is none*.

**F26 — Assumption 1 is better evidenced than the plan knows, and the plan missed where that evidence lives.** `WorktreeDropdownView`'s Blocker-5 comment (`SessionComposerPalette.swift:2306-2317`) states it as observed shipped behaviour: *"AppKit dispatches key equivalents via `performKeyEquivalent` BEFORE `keyDown` reaches the first responder, so Return in the field fired `commitHighlighted()`."* R1 is over-weighted. The plan cites `:1815-1826` and `:2215-2226` — the two comments that *assume* it — and not the one that measured it.

**F27 — §1's "all five G artboards agree" is falsified by G5.** §1's footer rule is "shown only while a ghost completion is currently attached to typed text (G1 and G4 show no footer)". `G5Pinned.dc.html` has typed `Gho` + ghost `stties …` and no footer. The plan's own cited evidence contradicts the rule it derives from it.

**F28 — No measurement could have seen `.anchored`.** Assumption 10 says the sidebar popover "should adopt the new field automatically". At `.anchored`, `fieldHeight` is 30, `fieldFontSize` is 11 (`:140-151`), and `paletteWidth` is the sidebar width minus 16. `Ghostties > Default > Orchestrator` at 11pt does not fit; with the resolution line deleted there is no fallback readout and no picker entry point. The plan's acceptance criteria are all `.centered` 360pt screenshots. Nothing in the plan would have looked at the popover.

## 5. WEAKEST ASSUMPTION

**Assumption 5** — *"The prediction's rest-state source (head of `recentProjectIds` + last pair for that project) matches 'predicted from the last selection'."*

It is false in three independent ways, each verified: the composer is frequently bound to a project that is not the recents head (F3, `ProjectBinding`); the thing Sean's note calls "last selection" is already modelled in code as `selectedOption`, seeded at open by `bestSelectionIndex` (`:772`) and moved by every arrow press (F2); and the prediction engine is a *second* source of truth for a string the composer already computes.

If it is false, the plan does not fail loudly — it ships. The screenshots pass, because with fresh single-project recents all three sources agree. What ships is a field that states, in Sean's own type, a destination that Return does not go to. That is strictly worse than the resolution line it deletes, because the resolution line was honest by construction: it read `selectedOption`. And it is one keystroke from the hazard Sean parked yesterday, where the divergent target is a shell exec.

**The single most important change:** delete `SessionComposerPrediction` as an independent source. Render the ghost path from what the composer has already resolved — `resolutionLineSegments(...)`'s project/branch labels plus `selectedOption?.title` — so the field is a restyling of the resolution line's data, not a rival prediction. That closes F2, F3, F6 and F7 at once (the lock gate, `"Select project"`, `"No match"` and `"Creating…"` all come along for free), collapses Step 1 to nothing, and makes 11.1 shippable tonight as a computed placeholder string while model B lands underneath it on its own schedule. Then rebuild §1's spec table from `V02Quieted22`/`V02Quieted222` only, and put the two DECIDE-OR-KILL questions at the top of §13 where Sean will see them.

VERDICT: rethink — bind the ghost path to `selectedOption` and the existing `resolutionLineSegments` output instead of a new prediction engine, and re-derive the spec from `V02Quieted22`/`V02Quieted222` rather than the G1–G5 build-out Sean never saw.
