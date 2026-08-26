# Composer QA automation — draft plan (UNREVIEWED)

Goal: shrink Sean's manual composer pass to the two things that genuinely need a human, by automating the classes of defect that escaped this morning.

## What is already built (do not rebuild)

Verified by reading the files, not by report:

- `macos/Tests/Ghostties/ComposerGhostTextFieldTests.swift:75` has `makeCoordinator(...)`, a working offscreen harness that builds a real `ComposerGhostNSTextView` plus `ComposerGhostTextField.Coordinator` with no window and no focus.
- 23 `@Test` funcs there call `coordinator.textView(_:doCommandBy:)` with real `NSResponder` selectors (`insertNewline`, `insertTab`, `insertBacktab`, `moveUp`, `moveDown`, `cancelOperation`). This is genuine key-path coverage without synthetic events.
- Tab was ALREADY covered pre-fix with a string assertion (`tabAcceptsTheActiveSegmentGhost`, `84c3b5f14` version, line 188) and the dead-end shipped anyway.

So "add a coordinator harness" is not the gap. The harness exists and is good.

## Why the two defects escaped it

**Defect 2 (Tab dead-end).** Every existing selector test fires ONE selector against a FRESH fixture. The dead-end only appears on the SECOND Tab, when the remainder already starts with `" > "`. A single-shot test passes; the bug lives in the sequence.

**Defect 1 (ghost welded to current project).** The coordinator receives `fullPath` as a fixture string, so no coordinator test can ever observe where that string came from. The binding lives in `SessionComposerPalette.ghostFullPathForModelB` (`:618`), which is `private` and therefore unreachable from the test target. The new `SessionComposerModelBGhostSourceTests` covers `destination(for:)` but its own doc comment (lines 14 and 21) states it does NOT cover `ghostFullPathForModelB`'s `selectedOption`-kind dispatch. That dispatch is precisely what was wrong.

## Steps

**Step 1. Make the dispatch testable.**
Extract the body of `ghostFullPathForModelB` (`SessionComposerPalette.swift:618`) into a pure static function taking `(selectedOption, currentProject, ghostPlaceholder, store, recentSelections)` and returning the path string. Leave the computed property as a thin caller. Cover the three branches: no selection, selection is a template in the current project, selection is a different project.

**Step 2. Sequence tests, not single-shot.**
Add a driver over the existing `makeCoordinator` harness that runs an ordered script of steps (type text, fire selector) and asserts field string plus ghost after EACH step. Cover at minimum: type `bruk` then Tab then Tab; type to an exact segment boundary then Tab; Tab with an empty ghost.

**Step 3. A/B differential.**
Same typed sequence through both models, asserting each resolves the same launch target. Field-and-list disagreement is the invariant that broke; a diff is the cheapest guard.

**Step 4. Filmstrip evidence.**
Extend the existing snapshot harness to emit one PNG per sequence step.

## Out of scope

macOS 13 key-event routing (needs real hardware), feel, XCUITest of any kind.

## Assumptions

1. `ghostFullPathForModelB` can be made testable without changing runtime behavior.
2. The test target can reach `SessionComposerPalette` statics (`destination(for:)` is already reached this way).
3. Sequence driving needs no window or run loop, since existing selector tests already run windowless.
4. Model A's resolution is reachable for a differential without touching model A's production path.
