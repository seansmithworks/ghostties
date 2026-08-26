# Findings ledger — composer QA automation

Refuter: `planner` (Opus), repo read access. Unedited output in `refutation.md`. Verdict `rethink`.
Draft held at `draft-plan.md`. Four kills independently re-verified by the planner before acceptance.

| # | Finding | Disposition |
|---|---|---|
| F1 | Sequential-Tab driver already exists (`ComposerGhostTextFieldTests.swift:191`, three Tabs, string + ghost asserted after each) | **ACCEPTED, verified.** Step 2 deleted. The test name was in the planner's own grep output and was not read. |
| F2 | A/B differential is vacuous: both branches terminate in the same `handle(event)` closure (`SessionComposerPalette.swift:1398-1428`) | **ACCEPTED, verified.** Step 3 deleted. Productive axis is ghost-vs-list, not A-vs-B. |
| F3 | Assumption 3 false where it matters: `selectedOption` derives from `@State selectedIndex` (`:87`, `:937`), nil unmounted, so the binding always takes the `guard let` early return | **ACCEPTED, verified.** This is the kill. Any windowless binding test passes green while defect 1's class stays live. |
| F4 | Step 1 extracts link 4 of a 5-link private chain; links 2-3 stay private and self-dependent | **ACCEPTED.** Extraction abandoned in favour of testing the real chain through a mounted render. |
| F5 | `makeCoordinator` hardcodes `ghostFullPath: ""` and never installs a ghost label (`:75-104`) | **ACCEPTED.** Confirms the harness cannot carry Step 2 as written. Moot once Step 2 is cut. |
| F6 | The two halves of the defect-1 fix are joined by a hand-written literal that production contradicts (`SessionComposerModelBGhostSourceTests.swift:19-23`) | **ACCEPTED.** The new plan's mounted test closes this join by construction. |
| F7 | The plan states scenarios, not the invariant | **ACCEPTED.** Invariant adopted verbatim as the table's assertion. |
| F8 | Tab termination needs a fixpoint property, not a fixed 2-Tab script | **ACCEPTED.** Becomes test 2. |
| F9 | No falsification requirement on any step | **ACCEPTED.** Mutant proof is now an acceptance criterion on both tests. |
| F10 | `.anchored` presentation never scoped out | **ACCEPTED.** Explicitly out of scope. |
| F11 | Whole surface sits behind a flag defaulting OFF; plan never says whether it flips | **ACCEPTED.** Flag stays off; tests drive model B directly. |
| F12 | Cut filmstrip PNGs — `7b566b9c1` removed the tautological freshness guard six hours ago; value is in the pixel predicates | **ACCEPTED.** Step 4 deleted. Reuses `darkestGhostPixel`. |
| F13 | Cut Step 3 | **ACCEPTED**, per F2. |
| F14 | Cut Step 1's no-selection branch — already covered by `SessionComposerGhostPlaceholderTests` | **ACCEPTED.** |
| F15 | "23 tests call `doCommandBy:`" was `grep -c "@Test"` reported as selector coverage; real figure is 15 call sites | **ACCEPTED, verified.** Planner error. A count presented as a measurement. |
| F16 | Diagnosis read the pre-fix tree (`84c3b5f14`) and generalised to current, under a "verified by reading the files" banner | **ACCEPTED, verified.** Planner error, and the same class as L15. |
| F17 | Plan ignored the fix commit's own +259 lines of tests, incl. a defect-1 regression test | **ACCEPTED.** Root cause of F1 and F16. |
| F18 | `renderPNG` vs `renderPNGWithExtraLayoutPass` are not interchangeable; the second exists because a single layout pass misplaces the ghost through an `NSViewRepresentable`, which model B is | **ACCEPTED.** New plan names the correct helper. Would have produced a false failure. |
| F19 | The file's hand-maintained "what is NOT verified" header is an inventory, not a measurement, and must not scope coverage | **ACCEPTED.** Bears out L4: a comment is prose. |

Nothing rejected. Rejecting nothing is itself a signal that the draft was weak, not that the critic was lenient.
