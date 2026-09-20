# Variant C — Off the canvas entirely

**Thesis:** the toggle's instability was a parenting bug — move it into the chrome gutter and it never touches terminal-theme geometry again.

**Sidebar OPEN:** 56pt gutter (`#242424`) flush left, toggle at the gutter's bottom; 180pt session list beside it. Terminal card floats right, 8pt insets, 12pt radius.

**Sidebar CLOSED (hard case):** the 56pt gutter does **not** collapse — independent of the session-list panel, it persists as its own column. Toggle holds the same position either way. Terminal card expands into the reclaimed width. Annotated on canvas: "gutter stays."

**Window chrome:** the gutter is exactly traffic-light width, so a top-pinned toggle collided with the lights. Fixed by splitting the gutter into a 56×56 top band (lights) and anchoring the toggle at the opposite end, the bottom. `+ New Session` sits beside the lights with its label in OPEN; CLOSED drops the label, collapsing to icon-only. Cost: two button treatments.

**Session title:** omitted both states — open, the highlighted row names it; closed, only the shell prompt cues it.

**Biggest risk:** closed sidebar has zero session-identity affordance — fine with one tab, a regression with several.

Only the browser icon floats over canvas.
