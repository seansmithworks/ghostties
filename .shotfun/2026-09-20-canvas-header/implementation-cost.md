# What each variant costs to build

**E is the cheapest of the three, not the most expensive — the buttons already sit where E puts them.** Today's toggles are anchored to the *window* top, not the card: `sidebarToggleButton.centerYAnchor.constraint(equalTo: topAnchor, constant: 22)`, with the constant rewritten each `layout()` pass from the live traffic-light close-button frame. They are already on the traffic-light row. What makes the current design read as a welded strip is not the buttons — it's the 28pt of card reserved above the terminal plus the centered title label sitting in it.

So the thing Sean is removing and the thing he is replacing it with are two separable changes, and E only needs the first half.

## Cost per variant

- **E — off the content.** Delete `titleLabel`, set `terminalTopConstraint` to 0. The buttons don't move, don't get reparented, and don't need a new material. Smallest diff of the three.
- **D — top corners, always on.** Everything E does, plus re-anchor both buttons from the window top to the card's own top corners at 16pt, plus a real glass material (`NSVisualEffectView`) that doesn't exist in this view today. Moderate.
- **F — reveal on approach.** Everything D does, plus an `NSTrackingArea` over the card's top region driving the existing alpha fade. Genuinely a small increment on top of D — the fade machinery is already built (`sidebarToggleButton.animator().alphaValue`, already `reduceMotion`-aware at `context.duration = reduceMotion ? 0 : 0.2`).

Ordering is E < D < F, and the gap between D and F is much smaller than the gap between E and D. None of the three is expensive. **The pick is a design call, not an engineering-cost call** — the cost column shouldn't decide it.

## Two things that bite whichever you pick

- **`terminalTitleBarHeight` is not header-only.** It's `28` in `WorkspaceLayout.swift:94` and `BrowserPanelView.swift:90` uses it for the browser nav-bar height. Zeroing the constant breaks the browser panel; the header change has to zero the *constraint* at the three call sites in `WorkspaceViewContainer.swift` (1296, 1315, 1947) and leave the constant alone.
- **Overlay mode already has no controls at all.** In `.overlay`, the code already sets `terminalTopConstraint = 0` and fades *both* buttons to `alphaValue = 0`. There is an existing state where the sidebar toggle is unreachable. That's not caused by this work, but D and F both claim the card's top corners, so whichever variant wins should say what overlay mode does — otherwise the pre-existing gap gets inherited and looks new.

## Decision for Sean

- **Does the cheapness of E change your pick?** Recommended answer: no — pick on how it looks and feels, since none of the three is costly. Noted only so the choice is informed.
- **What happens in overlay mode?** Recommended answer: show the chosen variant's controls there too, since the current no-controls state is a bug wearing a design decision's clothes.

<details>
<summary>Where this came from</summary>

Read directly in `macos/Sources/Features/Ghostties/WorkspaceViewContainer.swift` (2393 lines): button construction at 260–300, parenting at 1890–1891, constraint setup at 1945–2010, per-mode animation at 1280–1360. Constants in `WorkspaceLayout.swift`. No code was changed.

</details>
