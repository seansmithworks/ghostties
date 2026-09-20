# Legibility pass — glass buttons over hard terminal content

D's brief flagged the risk itself: glass-on-terminal-text legibility is content-dependent, and every mockup so far only shows tame dark placeholder text. This frame tests the content that actually breaks it.

**Setup:** D's exact glass buttons (`#FFFFFF2E` fill, 15pt radius, 1px `#FFFFFF26` stroke, 12px background blur, lucide icon at `#FFFFFFE6`), unchanged, over four content cases: dark shell (control), `htop` meters, a light theme, and diff colour blocks.

## Results

| Case | Verdict |
| --- | --- |
| Dark shell (control) | **Passes.** Both buttons read cleanly. This is the only case every existing D/F mockup has actually tested. |
| `htop` dense meters | **Fails.** The toggle sits on a bright green/red meter bar — icon contrast collapses, not just dims. |
| Light theme (Solarized) | **Fails hardest.** White glass on near-white background nearly disappears. Both buttons read as faint smudges. |
| Diff / colour blocks | **Fails.** The hard green/red seam cuts through both buttons — each one sits half on one colour, half on the other. |

3 of 4 realistic content cases break the glass. None of these are edge cases — htop, light themes, and diffs are ordinary terminal use, not adversarial content chosen to fail the test.

## Recommendation

D and F both float these buttons over live terminal content, so both inherit this failure mode; neither can be trusted as an always-on control without hoping the user's terminal cooperates. **E is the only variant that doesn't need that hope** — it's not exposed to this risk at all because its controls sit off the content entirely. Ship E, or don't ship D/F without a solved contrast strategy (not just "it looked fine over dark shell text").
