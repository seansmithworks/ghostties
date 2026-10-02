# Variant A — Inset Persistent

**Thesis:** the two icons never disappear; liquid-glass, not opacity/hiding, separates them from terminal text underneath.

**Sidebar icon position:** anchored 16px inset from the terminal card's *own* top-left corner, not the sidebar column. Same offset open (card at x=216) or closed (card at x=16) — a static inset, no recompute.

**Session title ("Shell 38"):** omitted — already lives in the sidebar row. Floating it over arbitrary terminal content would recreate the contrast problem this change exists to kill.

**Window chrome:** traffic lights + "+ New Session" sit in a 16px-inset top band, atop whichever surface owns the window's edge. Open: the sidebar's own chrome strip, above `ACTIVE 3` and the rows. Closed: sidebar strip is gone, so the band relocates full-width above the terminal card, on the canvas background — never vanishing. Glass icons stay inset from the card's corners, a band-height lower when closed, so no collision.

**Biggest risk:** persistence is the bet. Two glass blobs sit over real shell output every frame, forever — including mid-selection or reading near a corner. Glass buys legibility, not zero cost; it still dims a fixed terminal patch permanently. Argues against "controls should earn their pixels."
