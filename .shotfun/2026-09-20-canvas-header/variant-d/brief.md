# Variant D — Top corners, always on

**Thesis:** replace the welded header strip with two liquid-glass icon buttons floating inset from the terminal card's own top-left and top-right corners — the card becomes pure terminal, the way an Arc tab is pure page.

**Why stable across sidebar states:** the buttons are positioned relative to the card's own bounding box (16pt inset from its corners), not the window. When the sidebar opens or closes, the card resizes but its corners are still its corners — the inset never has to be recalculated, and nothing is anchored to the sidebar's presence or width.

**Biggest risk:** glass-on-terminal-text legibility is content-dependent. Over the dark test output here it reads fine, but a bright `vim`/`htop` frame or a light-mode theme with busy top-of-scroll content could wash the glass out or make the buttons hard to spot at a glance — this needs a real-content pass, not just placeholder shell lines, before it's trusted.
