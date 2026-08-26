# Refutation — composer QA automation draft plan

Adversarial review of `docs/plans/composer-qa/draft-plan.md`. Every claim below was checked against files at `ee33aef3d`.

## 1. WRONG

**F1. "Every existing selector test fires ONE selector against a FRESH fixture" is false at HEAD. Step 2 is already built.**
`macos/Tests/Ghostties/ComposerGhostTextFieldTests.swift:191` — `tabAcceptsExactlyOneSegmentLeavingTheRestGhosted` fires three sequential `insertTab:` selectors against a single fixture and asserts `textView.string` **and** `textView.currentGhostText` after each one, ending with a fourth assertion that the ghost is empty at the full path. That is exactly the "ordered script, assert after EACH step" driver Step 2 proposes. It was added by the fix commit `ee33aef3d` (+99 lines in that file). Consequence: an implementer handed this plan rebuilds coverage that shipped this morning, and the rebuild will pass immediately, which reads as validation.

**F2. Step 3's A/B differential compares one implementation against itself.**
`SessionComposerPalette.swift:1398-1428`: the model B branch (`ComposerGhostTextField`) and the model A branch (`ComposerQueryField`) both terminate in the identical closure `{ event in handle(event) }`. There is one commit path, not two. "Both models resolve the same launch target" is true by construction and cannot fail.
If the differential is instead aimed at the *ghost*: `SessionComposerPalette.swift:2246` guards the placeholder with `if query.isEmpty`. With `bruk` typed, model A renders **nothing**. So the ghost differential is either vacuous or — if you force model A to produce a string anyway — it asserts that model B must equal `ghostPlaceholder`, which is defect 1 re-encoded as the expected value. Shipping this step produces a test that would have gone green on the broken build.

**F3. Assumption 3 is false for the only thing that matters.**
`SessionComposerPalette.swift:937` — `selectedOption` reads `@State private var selectedIndex` (`:87`). That state is written from exactly two places: `.onAppear` (`:1009` → `:1017`) and `.onChange(of: composerStore.searchText) { reselectBestMatch() }` (`:1058`). Both are SwiftUI lifecycle callbacks that require a mounted view. On an unmounted `SessionComposerPalette` struct, `selectedIndex` is `nil`, so `ghostFullPathForModelB` (`:618`) takes `guard let selectedOption else { return ghostPlaceholder }` on **every** call. Windowless coordinator driving is genuinely free for the switch statement, and buys literally zero coverage of the selection→ghost binding. Any test written on Assumption 3 exercises the nil branch and passes green while defect 1's class stays live.

**F4. Step 1 extracts one link of a five-link chain and leaves the other four private.**
The chain that broke is `searchText → flattenedOptions (:933, private) → bestSelectionIndex (:958, private) → selectedOption (:937, private) → ghostFullPathForModelB (:618, private) → remainderGhost`. Step 1 makes link 4 testable. Links 2 and 3 stay private *and* self-dependent — `bestSelectionIndex` is not a thin wrapper over `SessionComposerRanking.bestMatchIndex`, it short-circuits first on `effectiveCommandParse.resolvedTemplateId` (`:966-971`), itself another private self-scoped property. When Step 1 is complete, "the ghost agrees with the highlighted row" is still not assertable end to end.
Worse, Step 1's three named branches ("no selection / template in the current project / different project") are literally the three branches of the ten lines as written. That is an implementation-shaped test of implementation-shaped code — the pattern this repo already logged as `feedback_vacuous-tests-pass-green`.

**F5. `makeCoordinator` cannot carry a ghost, so Step 2's stated harness doesn't work.**
`ComposerGhostTextFieldTests.swift:75-104` hardcodes `ghostFullPath: ""` and never calls `installGhostLabel` — `insertTabIsConsumedNoOpWithNoGhostLabel` (`:178`) exists specifically to document that. The one ghost-asserting test bypasses `makeCoordinator` and constructs the field inline (`:194-206`). "Add a driver over the existing `makeCoordinator` harness" requires a signature change the plan does not budget and does not mention.

## 2. MISSING

**F6. The stitched-literal hole between the two halves of the defect-1 fix is not closed.**
`SessionComposerModelBGhostSourceTests.swift:19-23` states in its own doc comment that the rendering proof uses the literal `"Brukas > Default > Shell"` — "NOT the live output of `destination(for:)`, which (correctly) ... lands on `Browser` for a vanilla fixture project." So the unit half and the render half are joined by a hand-written string that production **contradicts**. `destination(for:)` could return anything and the render test would still pass. Nothing in the four steps closes that join. The missing step is a composition test: feed `destination(for:)`'s actual return value into the ghost assertion, never a literal.

**F7. The plan never states the invariant, only example scenarios.**
Both defects are one property: *for any typed text that matches the highlighted row, the ghost is non-empty and is a prefix-consistent preview of that row's destination.* Defect 1 = the ghost was empty. Defect 2 = the ghost went empty mid-drill. A table-driven check over (fixture projects × typed prefixes) asserting `remainderGhost(typed:fullPath:) != ""` is one screenful and catches both classes. Three hand-picked scenarios catch three hand-picked scenarios.

**F8. Tab termination is not tested as a property, and the plan's script would miss a 3-segment dead-end.**
Step 2 specifies "type `bruk` then Tab then Tab". Defect 2 was a non-terminating drill. The general guard is: loop Tab until the ghost is empty, assert it terminates in ≤ segment count and that the final `textView.string == fullPath`. A fixed 2-Tab script is bounded at exactly the depth the author happened to think of.

**F9. No falsification requirement on any of the four steps.**
The fix commit's own evidence block records a mutant check ("fails against the old `activeSegmentGhost`, confirmed before restoring the fix"). The plan sets no such bar for the tests it proposes. Step 1's three-branch test is unfalsifiable by construction — it is derived from the code it tests. Every new test in this plan needs "proven to fail against the pre-fix implementation" as an acceptance criterion, or it is decoration.

**F10. `.anchored` presentation has zero coverage and is never scoped out.**
`SessionComposerPalette.swift:573-575` — `ghostPlaceholder` returns the generic string unless `request.presentation == .centered`. Model B's ghost is a `.centered`-only surface. The plan's "Out of scope" section lists macOS 13 routing, feel, and XCUITest, but never says which presentation the QA covers. State it, or the next reader assumes both.

**F11. The whole surface is behind a flag that defaults OFF.**
`flagDefaultsToOffAndDefaultPathBuildsComposerQueryField` (`ComposerGhostTextFieldTests.swift:27`) asserts `usesModelBFieldForTesting == false` by default. Every step in this plan is QA for a field Sean's own build does not render unless he flips `ghostties.composerModelBField`. The plan never says whether the flag flips as part of this work. If it doesn't, this QA covers nothing that ships.

## 3. OVERVALUED / GOLD-PLATED

**F12. Cut Step 4 (filmstrip PNGs) entirely.**
`7b566b9c1`, six hours old, **removed** `assertEvidenceMatchesDisk` as tautological and replaced it with an explicit process note stating that PNG freshness "genuinely cannot be verified at test RUN time." Step 4 proposes multiplying unassertable artifacts by the number of sequence steps, and each one needs a human eyeball — in a plan whose stated goal is removing Sean's hands. The value in that file is the pixel *predicates*, not the files: `darkestGhostPixel` (`SessionComposerSnapshotTests.swift:~204-260`), `ghostGrayBandPixelCount` (`:237`). Reuse the predicate as an assertion; do not emit more PNGs.

**F13. Cut Step 3 (see F2) and spend the budget on F7's invariant.** A differential is the right instinct, but the axis is wrong. The productive differential is ghost-vs-list (what the field previews vs what the highlighted row would launch), not model-A-vs-model-B.

**F14. Cut Step 1's "no selection" branch.** It returns `ghostPlaceholder` verbatim, and `SessionComposerGhostPlaceholderTests.swift` (9.4K) already covers that computation. A third assertion of the same fact.

## 4. EVIDENCE

**F15. A count was presented as a measurement.** "23 `@Test` funcs there call `coordinator.textView(_:doCommandBy:)`." The file has 23 `@Test` funcs *total*; 13 of them contain a `doCommandBy:` call (15 call sites). The other 10 are pure-function tests of `remainderGhost`/`nextSegment` plus the flag test. That figure is a `grep -c "@Test"` reported as selector coverage.

**F16. The plan's diagnosis reads the pre-fix tree and reports it as current.** It cites `84c3b5f14`'s line 188 accurately, then generalizes to "every existing selector test fires ONE selector against a FRESH fixture" — true at `84c3b5f14`, false at `ee33aef3d`, the commit the plan itself names as where the fixes landed. The "Verified by reading the files, not by report" banner is therefore untrue of the plan's single load-bearing diagnostic claim.

**F17. The plan omits the fix commit's own test additions.** `ee33aef3d` added +99 lines to `ComposerGhostTextFieldTests`, +83 to `SessionComposerModelBGhostSourceTests`, and +77 to `SessionComposerSnapshotTests`, including `workedExampleGhostsADifferentProjectsFullPath` — a defect-1 regression test with a real assertion and a failure message that names defect 1 by number. Any plan proposing Steps 2-4 must first reconcile against that commit; this one does not, so it is planning against a tree that no longer exists.

**F18. Two claims were never checked against a file.**
(a) "the existing snapshot harness" — the plan never establishes which helper. There are two, and they are not interchangeable: `renderPNG` (`:49`) and `renderPNGWithExtraLayoutPass` (`:94`). The second exists because a single `layoutSubtreeIfNeeded()` renders the ghost misplaced through an `NSViewRepresentable`, per its own doc comment ("confirmed against the same debug test"). Model B *is* an `NSViewRepresentable`. A driver written against `renderPNG` reproduces the exact bug that helper was created to fix.
(b) Assumption 4, "Model A's resolution is reachable for a differential" — model A has no resolution to reach once text is present (`:2246`). This was asserted, not read.

**F19. The plan cites a wrong doc comment and then trusts the document it came from.** `ComposerGhostTextField.swift:25` names `ComposerGhostTextFieldSelectorTests`; the only occurrence of that identifier anywhere in the repo is the comment itself. The plan correctly flags it — and then draws no conclusion. The conclusion is that this file's hand-maintained "what is NOT verified" header is an inventory, not a measurement, and must not be used to scope what is or isn't covered. The same header is the source of the plan's out-of-scope list.

## 5. WEAKEST ASSUMPTION

**Assumption 3 — "Sequence driving needs no window or run loop, since existing selector tests already run windowless."**

True for the coordinator's `doCommandBySelector` switch. False for anything carrying `selectedOption`, which is `@State`-derived and seeded only from `.onAppear` and `.onChange` (`SessionComposerPalette.swift:1009`, `:1058`). Defect 1 lives entirely on the false side of that line.

If it holds only in the weak form — and it does — Steps 1, 2 and 3 all collapse into fixture-fed tests where the test author hand-supplies the very string the bug corrupted (`ghostFullPath:` as a literal, exactly as `workedExampleGhostsADifferentProjectsFullPath` already does). The plan then produces four steps of green coverage for a defect class none of it can observe. That is the identical failure mode as the 949-test suite Sean's hands beat this morning, at higher cost.

## VERDICT

**rethink.**

Single most important change: **replace all four steps with one mounted-palette composition test plus one pure fixpoint test.**

1. *Defect 1's class, the only test that can see it.* In `SessionComposerSnapshotTests.swift`, seed an isolated store with two projects (`ghostties` scoped, `Brukas` not), set `composerStore.searchText = "bruk"` **before** mounting so `.onAppear`'s `selectedIndex = bestSelectionIndex(in: flattenedOptions)` runs with the query already in place, mount via `renderPNGWithExtraLayoutPass` (the only helper that survives an `NSViewRepresentable`), and assert `darkestGhostPixel(in:) != nil`. This is the whole defect: the ghost rendered zero pixels. It runs the real `flattenedOptions` → `bestSelectionIndex` → `selectedOption` → `ghostFullPathForModelB` chain with no extraction, no `private` changes, and no synthetic events. Table it over three or four (scoped project, typed prefix) pairs and it becomes the invariant from F7.
2. *Defect 2's class, free.* A pure fixpoint loop over `remainderGhost`/`nextSegment` — both already `static` and already tested — that drills until the ghost is empty and asserts it terminates within the segment count and lands exactly on `fullPath`. No mounting, no fixtures beyond a path string.

Both must carry the falsification bar from F9: fail against the pre-fix implementation before being trusted. Everything else in the draft is cut.
