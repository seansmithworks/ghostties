# Variant B — Quiet until summoned

**Thesis:** a terminal should be nothing but terminal until you reach for a control — at rest the CARD is bare, zero chrome.

**Window chrome:** both mockups now show the sidebar's top band (traffic lights + `+ New Session`), `ACTIVE 10` header, and session rows — chrome that never disappears, outside the card. This narrows the claim: the window was never bare, only the card is. Weaker than "bare canvas," but honest — the sidebar sits beside the card unchanged in both states.

**Glass button position:** anchored 16pt from the card's own top-left corner, floating over the card, not the window — auto-follows the card's edge regardless of sidebar width, no runtime-recalculated constraint.

**Discoverability:** ghost icons persist at rest, 8% opacity, at the buttons' anchors — a permanent trace, not a hidden control. Pointer proximity to the top ~80px resolves them into liquid-glass buttons (backdrop blur + 15% white fill) with a subtle top scrim.

**Session title:** omitted — already lives as the sidebar row's live terminal title.

**Biggest risk:** an 8%-opacity glyph may be invisible on light/bright terminal themes (e.g. `#f7f7f7`) — only proven against the given dark tokens.
