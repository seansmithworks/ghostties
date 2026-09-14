# Findings ledger: PR #169 post-merge test plan

Refuter: separate `planner` agent (Opus) with read access to the repo. Verdict: **revise**. 21 findings, 21 rows.

| # | Finding | Decision | Change |
|---|---|---|---|
| F1 | Three red-proof rows can't run on main: tests deleted or renamed, and one mutation doesn't compile | Accepted | Rebuild every proof against the final branch tip. Each mutation must compile on main. |
| F2 | Tests credited to the wrong commits, and one mutation breaks nothing | Accepted | Regenerate test lists from each commit's actual test diff and from the final tip's test names. |
| F3 | The Classic row mutates a centered-path test and drops the pop-up tests | Accepted | The pop-up proof covers `cardKindIsPopoverWhenAnchored…`, the scroll test, card-fit, and the moved snapshot tests. It also flags that pixel limits are unverified at 204pt. |
| F4 | The suite is already red: stale default assertions (verified: `ComposerRound12TuningTests.swift:28-30` expects 28/688, corner radius test expects 10). The baseline was 10 failures, not 5 flakes | Accepted | Stale assertions fixed PRE-merge (fixer dispatched). Plan baseline corrected to 1147/10 failed. This run's test IDs become the new baseline. |
| F5 | "Already verified" is out of date | Accepted | Every verified item names its commit: the dry run was on `79a151ffe`, the live look on `057c19fed` before Classic removal. Re-run the release dry run on main. |
| F6 | Manual items 12 and 13 can't be done without dev tools or writing settings; 7 and 10 have nothing to compare against | Accepted | 13 becomes "Classic is gone from the tuning panel's Style list". 12 becomes a release dry run on main. 7 and 10 compare against the installed Release app (inferred to still have the old pop-up). |
| M1 | No bucket for breakage across commits, and no plan for a red main | Accepted | Add a triage step: stale assertion, pixel-limit recalibration, or real regression. Fixes go in a follow-up PR from main, and no beta tag until green. |
| M2 | "Add project" from the sidebar header now renders single-line, with no coverage | Accepted | Added as a manual item. |
| M3 | Tests write to Sean's tuned Dev settings | Accepted | Back up with `defaults export` before the run and compare after. |
| M4 | The run steps don't work as written | Accepted | `build-for-testing` into a fresh DerivedData, then `test-without-building`. Rebuild before each red proof. |
| M5 | No coordination with the other thread using Dev; zero-chrome select unchecked | Partly accepted | A free Dev window was already a precondition, now stated. The zero-chrome select joins the tuning-panel item. |
| O1 | The per-commit framing is overbuilt | Accepted | Collapse to about 10 behaviour-keyed proofs, one rebuild each. Drop the non-rows. One proof per dial group. |
| O2 | Screenshots after merge land on a closed PR | Accepted | Screenshots move to the merge thread, before merge. |
| E1 | Mixed committed and in-progress code | Accepted | The rewriter reads only the committed tip, via `git show`. |
| E2 | Test lists came from summaries | Accepted | Same fix as F2. |
| E3 | Baseline contradiction inside BACKLOG | Accepted | Same fix as F4. |
| E4 | "PR CI green" is compile-only | Accepted | The plan says so. |
| E5 | Claim that Sean's Dev values match the code was never read | Accepted | Replaced with the stored values actually read. |
| Weakest assumption (A1+A2) | Proofs keyed by commit don't map onto main | Accepted | Proofs keyed by behaviour instead (O1). |
| Reviewer note on `275c37d69` | Pixel limits in the 21 moved tests were calibrated at 360pt, and the pop-up is 204pt | Accepted | Triage bucket "pixel-limit recalibration" (M1). |
| Verdict | revise | Accepted | Revised, not rethought: the three-part structure holds. |
