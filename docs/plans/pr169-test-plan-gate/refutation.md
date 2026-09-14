## 1. WRONG

**F1. 3 rows are UNRUNNABLE on main (A1 false for them).** 8579f6420: all three `effectiveStyle*` tests and `effectiveStyle()` itself were deleted in 275c37d69 (verified: exist at a46a6b972, absent at 275c37d69). 4e68b2c2c: mutation "restore fallback to `.classic`" doesn't compile — `.classic` is gone; plan's own rule then logs a false "vacuous." Working mutation on main is `.zeroChrome`. 6e0f97c37: both `...PlaysOnTheNewIdentityImmediately` names were renamed by f0c9c5cf7 — exist at neither a46a6b972 nor 275c37d69.

**F2. Misattributed tests (confirms builder's report).** `composerStyleReadsStaleClassicRawValueAsSingleLine` and `cardKindKeepsSingleLineDefaultWhenCentered` exist only from 275c37d69, not 4e68b2c2c. e4257a247 row lists 3 tests that 3b94a1226 added; e4257a247's one real test `launchBlendsFromRestingOffsetAtBeatStartToFortyAtTwoHundredMs` is absent. `...SizeDefaultsToThirty`/`FloatAmplitudeDefaultsToTwo`/`GapDefaultsToSix` are e9c922eb0 renames, not a0eec0232/57b0fcd42. a0eec0232's mutation "`floatOffsetX` returns 0" targets e9c922eb0 code and can't break the Y-offset (size+gap) or dial round-trip tests — stays green, false "vacuous."

**F3. Classic row mutates the wrong test.** `cardKindKeepsSingleLineDefaultWhenCentered` is the centered path; re-routing anchored never touches it. Drops everything BACKLOG.md:6 explicitly names: the 21 retargeted snapshot sites, `twentySevenProjectsScrollCleanlyInPopover`, `ComposerCardFitTests`, `cardKindIsPopoverWhenAnchoredRegardlessOfStored`.

**F4. Suite is already red on main; plan doesn't know.** `ComposerRound12TuningTests.swift:28-30` asserts 28/18/688; `ComposerZeroChromeStyle.swift:890-892` defaults are 24/18/640 since a0eec0232. `ComposerZeroChromeStyleTests.swift:2252` asserts corner radius 10; `:895` is 16. The 57b0fcd42 row's "corner radius back to fixed 10" turns that test GREEN. Baseline misread: BACKLOG.md:82 records 1147/**10 failed**/1 skipped at 911759a6e, not 5 flakes — the other 5 were real (launch lift −41, unrendered Witness pixel test, 2 glass tests). No known-good identifier set exists to diff.

**F5. "Already verified" is stale.** Dry run headSha is 79a151ffe — before 4e68b2c2c/f0c9c5cf7/8579f6420/fc549f34f/275c37d69 (275c37d69 edits DialKit controls). Live look on 057c19fed predates Classic removal changing the rendered card.

**F6. Manual items that can't be done or can't fail.** #13 needs `defaults write` (contradicts line 122 + A4). #12: no Release artifact exists (no beta until green), no build steps. #7 "reads as glass," #10 "works as before" have no reference.

## 2. MISSING

**M1.** No bucket for cross-commit breakage invisible to a per-commit table (Round12Tuning); no red-main protocol (who fixes, in what PR).
**M2.** Sidebar header add-project (`WorkspaceSidebarView.swift:236`, centered, `.locked(project)`) now renders single-line. 275c37d69 retargeted its locked-project snapshot tests to the popover — this path has zero render coverage and no manual item.
**M3.** Tests mutate Sean's tuned Dev defaults. Test host is Ghostties Dev.app (`project.pbxproj:1119`); SessionComposerSnapshotTests saves/restores real keys (`:641, :1262, :1680, :1784, :1839, :1921, :2385`). A killed run leaves his tuning mutated. No export-first step; manual pass comes after ~20 runs.
**M4.** Invocation doesn't work: "fresh build" produces no `.xctestrun` — needs `build-for-testing`, fresh DerivedData unspecified. Each mutation needs a rebuild, or proofs run stale and silently pass.
**M5.** No coordination with the PR #175 thread using Dev. No check that the zero-chrome Style select still works.

## 3. OVERVALUED

**O1.** Per-commit framing. df25c6023/6c25d8ef9/264222ea0 are non-rows. ef496f46d "empty frame set" kills all 27 frame tests at once — proves nothing per test. ~20 default/ReadsStoredValue pairs are constant-checks; one proof per dial suffices — and `CornerRadiusReadsStoredValue` stores 16 == default, vacuous against a read that ignores storage. Collapse to ~10 behaviours on main, one rebuild each.
**O2.** PR screenshots post-merge land on a closed PR.

## 4. EVIDENCE

**E1.** Table mixes committed and in-progress tree (275c37d69-only names attributed to 4e68b2c2c). **E2.** Test lists from commit messages/BACKLOG summaries, not `git show <sha> -- macos/Tests` (e4257a247 row). **E3.** "5 flakes" from BACKLOG.md:41, contradicted by :82 in the same file. **E4.** "PR CI green" is compile-only; cannot see F4. **E5.** Line 121 "Sean's Dev values match code defaults as of e9c922eb0" — never read. BACKLOG.md:13 records his gap as 5; e9c922eb0 set the default to 6.

## 5. WEAKEST ASSUMPTION

A1+A2: that commit-keyed proofs map onto main. Renames, deletions and default flips break ≥6 of 19 rows — they fail to compile, point at missing tests, or turn a red test green. The table would hand Sean confident, wrong verdicts.

**VERDICT: revise.** Single most important change: regenerate Part 2 from 275c37d69's actual test identifiers, keyed by behaviour, with a pre-pass-bar step that fixes the two stale default tests and classifies all 10 failures from 911759a6e.

Plan file: `/Users/seansmith/Code/ghostties/.claude/worktrees/session-7/docs/plans/pr169-composer-post-merge-test-plan.html`
