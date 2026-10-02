# Variant E · Off the content entirely

**Thesis:** the header strip isn't a terminal feature, it's window chrome — so it moves into the window's own background above the card, and the card becomes 100% terminal, edge to edge.

**Traffic-light conflict (closed state):** the toggle can't sit flush at the band's left edge like it does in the open state, because that's where macOS puts the lights. Resolved by shifting the toggle right of the lights with a 16px gap — it gives up perfect edge alignment rather than colliding. The globe is unaffected and stays flush right in both states.

**Session title:** removed, not relocated. The band above the card is 44px tall and both controls already justify to its edges; there's no natural slot for centered text without re-introducing a strip.

**Biggest risk — vertical space:** yes, this costs terminal height. The 44px band plus an 8px gap above the card is ~52px of vertical space that used to be usable in the old design's card-minus-header math, in both sidebar states, on every screen.
