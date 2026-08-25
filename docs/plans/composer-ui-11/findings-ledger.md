# Findings ledger — composer-ui-11

Two independent refuters, neither the drafter. Generalist: `refutation-generalist.md` (VERDICT rethink).
AppKit/TextKit domain lens: `refutation-appkit.md` (VERDICT rethink). Evidence unedited on disk.

## Structural decisions taken from the gate

**D-A. The overnight run builds everything VERIFIABLE in full, and builds model B as an
isolated non-default spike.** Sean chose model B explicitly, so it gets built. But AppKit F13
established something he could not have known when he chose: every acceptance gate for the
field swap is a manual key matrix, and this repo forbids agent-driven synthetic keystrokes
(`feedback_subagent-gui-automation-hit-live-session`). So model B ships tonight as commits he
can drive in ten minutes, NOT as the default field. The composer he wakes to still works.

**D-B. The ghost path is rendered from `resolutionLineSegments(...)` + `selectedOption`.**
`SessionComposerPrediction` is deleted from the plan entirely. Generalist F2/F3 + weakest
assumption. This closes F2, F3, F6, F7 at once and collapses the whole data layer.

**D-C. Spec is re-derived from `V02Quieted22` / `V02Quieted222` ONLY.** G1-G5 are Claude's
build-out Sean has never seen (`a1daa6608` says so explicitly). They become flagged proposals,
and the canvas gets re-seeded so he can actually rule on them.

**D-D. 11.1 ships tonight in model A as a computed placeholder string.** One grey, no
sub-ranges, no AppKit. Delivers 11.1 whole with zero rewrite risk, and stops the safe half of
the work from being blocked behind the risky half.

## Ledger

| # | Finding | Disposition |
|---|---|---|
| G-F1 | Plan built G1-G5, not Sean's boards | ACCEPTED. D-C. Kills pin column, timestamps, lane hairline, footer strip. |
| G-F2 | Ghost path and Return diverge on arrow press | ACCEPTED. D-B. |
| G-F3 | Assumption 5 falsified by `ProjectBinding.locked/.prefilled` | ACCEPTED. D-B removes the rival source. |
| G-F4 | `NSTextView` has no placeholder API | ACCEPTED (= AppKit F6). Hand-drawn, budgeted. |
| G-F5 | Ghost clipped at rest; no invalidation strategy | ACCEPTED (= AppKit F2/F16). |
| G-F6 | In-field segment clicks ignore `.locked` | ACCEPTED. Moot tonight: D-E keeps the resolution line as the mouse route. |
| G-F7 | Deleting resolution line drops `Select project` / `Project unavailable` / `No match` | ACCEPTED. D-E. Zero-project first run would have been a dead composer. |
| G-F8 | Step 2 silently changes what Return does on first open | ACCEPTED. Pinned-ahead-of-recents moves index 0, which `onAppear` seeds (`:772`). Needs an explicit test. |
| G-F9 | `ComposerRow` already draws a 16pt leading icon | ACCEPTED. Reconcile against the boards; no second leading slot. |
| G-F10 | Newline-bearing paste not sanitised | ACCEPTED (= AppKit F15). `isFieldEditor = true`. |
| G-F11 | IME marked-text corruption | ACCEPTED (= AppKit F14). |
| G-F12 | Tab acceptance casing undefined | ACCEPTED. Flagged for Sean, strawman: preserve typed casing, resolve case-insensitively. |
| G-F13 | R1 fallback is a multi-view refactor, not a one-liner | ACCEPTED. Removed from the overnight path with D-A. |
| G-F14 | Pins list never pruned or reconciled | ACCEPTED. |
| G-F15 | macOS 13 risk is the TextKit stack, not `#available` | ACCEPTED (= AppKit F26). Build the TextKit 1 stack explicitly. |
| G-F16 | Undo scope unverified | ACCEPTED (= AppKit F7). |
| G-F17 | 11.1 does not need model B | ACCEPTED. D-D. |
| G-F18 | Cut `lastUsedAt` migration | ACCEPTED. Boards show the literal string `recent`. Persisted-state change overnight for a mock Sean never saw. Also AppKit F19: `maxRecents = 3` makes the column mostly blank anyway. |
| G-F19 | Cut the footer strip | ACCEPTED. Errors go to the existing `writeError` strip (`:1010-1016`). |
| G-F20 | Keeping `resolutionLineSegments` alive for its tests is tests-driving-design | REJECTED as stated. Under D-B the function becomes the ghost's genuine source, so it is load-bearing, not preserved for its tests. The finding dissolves rather than being overruled. |
| G-F21 | Two overnight review rounds are the same actor, not independent | ACCEPTED. Reviewers spawn as separate agents with fresh context, and the builder never reviews itself. |
| G-F22 | Spec sources read but not ranked | ACCEPTED. Root cause of G-F1. This was an error in my brief to the drafter, not the drafter's. |
| G-F23 | Strawmen laundered into locked decisions | ACCEPTED IN PART. Sean said apply-or-redline, do not re-ask, so building them is right. Correction is presentational: both stay at the top of the morning list as open questions. |
| G-F24 | `resolutionLineSegments` returns six labels, not three | ACCEPTED. My brief's undercount propagated into the plan. |
| G-F25 | Cited AppKit precedents are a different protocol on a different class | ACCEPTED (= AppKit F9). State plainly: there is no precedent. |
| G-F26 | Assumption 1 better evidenced than the plan knew | ACCEPTED. `:2306-2317` records it as observed shipped behaviour. R1 downgraded. |
| G-F27 | "All five G artboards agree" falsified by G5 | ACCEPTED. Moot under D-C. |
| G-F28 | Nothing would have looked at `.anchored` | ACCEPTED. 11pt/30pt sidebar popover cannot fit the path. Gate ghost rendering on `.centered`. |
| A-F1 | Construction clips instead of scrolling | ACCEPTED. Full sizing property set required. |
| A-F2 | Ghost outside text storage is clipped to zero width | ACCEPTED. Document-view frame must include ghost width. |
| A-F3 | Temporary attributes cleared on every edit | ACCEPTED. Re-apply on `textDidChange` AND after every programmatic write. |
| A-F4 | Continuous spell checking on by default | ACCEPTED. Disable all four checkers. |
| A-F5 | Ghost origin math wrong twice (container coords, trailing whitespace) | ACCEPTED. Use `firstRect(forCharacterRange:)`. |
| A-F6 | No placeholder; five AppKit defaults break parity | ACCEPTED. `drawsBackground`, `lineFragmentPadding`, `textContainerInset` all explicit. |
| A-F7 | `.string` assignment defeats undo and jumps the caret | ACCEPTED. `shouldChangeText` / `replaceCharacters` / `didChangeText`. |
| A-F8 | `focusTrigger` reset mutates state during view update | ACCEPTED. Must be async. |
| A-F10 | Unhandled `cancelOperation:` falls through to `complete:` | ACCEPTED. Return `true`. |
| A-F11 | Deleting hidden Buttons narrows key handling to first-responder scope | ACCEPTED. Real regression after an `NSOpenPanel` round trip. Buttons stay until proven unnecessary. |
| A-F12 | R1's guard makes the picker un-drivable if Assumption 1 is false | ACCEPTED. Fails silent, no test can see it. |
| A-F13 | Every gate on the risky steps is a forbidden manual key matrix | ACCEPTED. D-A. The decisive finding. |
| A-F17 | Field's accessibility value will lie; ghost is 2.4:1 contrast | ACCEPTED. Project design layers include a11y. `accessibilityValue` override required. |
| A-F18 | Mouse hit test has the same coordinate bug; kills drag-select | ACCEPTED. Moot tonight under D-E. |
| A-F20 | No first-responder teardown on dismiss | ACCEPTED. |
| A-F21 | Cut in-field click routing from this run | ACCEPTED. D-E. |
| A-F22 | A subview beats a `draw(_:)` override | ACCEPTED. Gets invalidation and an a11y element for free. |
| A-F23 | Step 4 bundles six independent risks in one commit | ACCEPTED. Split. |
| A-F24 | Assumption 1 argued by analogy; cited comment disclaims verification | ACCEPTED, tempered by G-F26. |
| A-F25 | Assumption 2 verified TRUE against `StandardKeyBinding.dict` | NOTED. Caveat recorded: a user `DefaultKeyBinding.dict` overrides it. |
| A-F27 | Focus test passes in the configuration where the behaviour is untestable | ACCEPTED. Same shape as the repo's vacuous-test rule. |
| A-F28 | "Renders identically" asserted, not measured | ACCEPTED. Repo precedent: the chip-width line shipped wrong three times on source-reading alone; a screenshot ended it. |

**D-E. The resolution line SURVIVES tonight.** Both refuters independently reached this
(G-F7, A-F21). It is the only mouse route into the pickers and the only home for four of its
six labels. It gets deleted after Sean has hands-on with the in-field rendering, not before.
This means 11.1's "delete the sub title" is built but staged behind his approval.
