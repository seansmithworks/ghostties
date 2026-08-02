# ghostties.org — web design system

Source of truth for every design value on the marketing site.

> The `DESIGN.md` in the repo root documents the **macOS app**. It does not
> apply here, and the two systems do not share tokens today.

---

## 1. How the CSS is organised

```
web/style.css      tokens + reset + base elements + shared components + footer
web/<page>.html    <link rel="stylesheet" href="/style.css">  then a <style>
                   block holding only what is unique to that page
```

**The link tag must come before the page's `<style>` block.** Both files use
plain element and single-class selectors, so the cascade is decided by source
order — page rules win because they come later. Move the link below the style
block and every page override silently stops working.

`style.css` has no `Cache-Control` entry in `vercel.json`, deliberately: the
filename is not content-hashed, so it must be allowed to revalidate. **Do not
fold it into the `/assets/*` rule** — that rule is a one-hour cache with a
day-long stale window, which would serve a stale stylesheet after a deploy.

### What lives where

| Page | Page-specific CSS |
| --- | --- |
| `index.html` | Hero scene, ghost pyramid, typewriter terminal, product windows, ambient backdrop, mono footer variant |
| `download.html` | `.download-block`, `.download-btn`, `.download-meta`, `.all-releases` |
| `changelog.html` | `.release*` group |
| `support.html` | `.known-issue` |
| `licenses.html` | `h2` title override |
| `404.html` | Centred layout, ghost, `.home-link` |
| `privacy.html` | **None** — the shared sheet covers the whole page |
| `task-flows.html` | Out of system entirely; see §7 |

---

## 2. Adding or changing a value

- **A colour, size, or radius used on more than one page** → add or edit a
  token in `style.css` `:root`. Never paste a new literal into a page block.
- **A rule two or more pages need** → move it into the relevant section of
  `style.css` and delete it from the pages.
- **A genuine one-off** → keep it in that page's `<style>` block with a short
  comment saying why. There are six of these today, all listed in §6.

Verify by screenshot diff, not by eye: serve `web/` locally
(`python3 -m http.server`) and capture every page at 1280 and 375 before and
after. The homepage needs an ~11s settle — its typewriter runs to 10.1s — and
its floating ghosts and looping product videos mean two captures of the *same*
build differ by ~0.14%. Treat anything under that as noise.

---

## 3. Colour

Everything sits on one background. All foreground colour is white at varying
alpha, plus a single accent.

### Surfaces

| Token | Value | Use |
| --- | --- | --- |
| `--bg` | `#1a1a2e` | Page background, every page |
| `--surface-raised` | `rgba(255,255,255,0.04)` | `.note` callout, `pre` |
| `--surface-inline` | `rgba(255,255,255,0.07)` | Inline `<code>` |
| `--surface-card` | `#0f0f1a` | Product window behind the video |

### Text ramp

Densest to faintest. **The contrast column is from the 2026-08-02 audit,
measured against `--bg`.** Everything from `--text-note` down fails WCAG AA
for body-size text.

| Token | Alpha | Contrast | Use |
| --- | --- | --- | --- |
| `--text-heading` | `#fff` | — | `h1`, changelog release titles |
| `--text-heading-soft` | 0.90 | — | Licenses section titles |
| `--text-primary` | 0.85 | — | `body` default |
| `--text-body` | 0.65 | pass | Prose, links, list items |
| `--text-note` | 0.45 | 4.27–4.43 | Callout copy |
| `--text-meta` | 0.40 | 3.78 | File size, "all releases" |
| `--text-label` | 0.35 | 3.21 | Eyebrow `h2`, back link, dates |
| `--text-label-quiet` | 0.30 | 2.70 | Changelog subsection labels |
| `--text-faint` | 0.25 | **2.27** | Footer text and links, timestamps, bullets |

`--text-faint` at 2.27:1 is the worst value on the site and it is the footer,
which appears on all seven pages. The audit's note: raising the floor to 0.55
yields 5.96:1. **That fix is now a single token edit** — it was the point of
building this file. It is queued in `BACKLOG.md` under Accessibility and has
not been applied here, because this pass was a refactor.

Hover pairs: `--text-body-hover` (0.9), `--text-meta-hover` (0.65),
`--text-label-hover` (0.6), `--text-faint-hover` (0.5).

Hairlines: `--line` (0.08), `--line-strong` (0.12), `--line-faint` (0.07).

### Accent

`--accent: #c97350` — terracotta. Two uses: product captions on the homepage,
and the 404 home link. It **passes** AA at 4.92:1.

It is also the only chromatic colour below the hero, and it was explicitly
dropped as a brand colour for the app (see the root `DESIGN.md` and the
`terracotta-not-brand-color` note). The 8-ghost palette that *is* the brand
sits unused below the fold. Replacing it is a design decision, queued in
`BACKLOG.md` — not made here.

### Hero terminal (index only)

| Token | Value |
| --- | --- |
| `--terminal-fg` | `#e0e0e0` |
| `--diff-add-fg` / `--diff-add-bg` | `rgba(100,220,120,0.9)` / `rgba(80,210,100,0.13)` |
| `--diff-del-fg` / `--diff-del-bg` | `rgba(255,100,100,0.7)` / `rgba(255,80,80,0.13)` |

### Ghost palette

The eight pixel ghosts are coloured by inline `fill` attributes on each SVG,
not by CSS, so they are not tokenised. The homepage uses one set and the six
subpages' favicon script uses a second, different set:

| | Homepage | Subpages |
| --- | --- | --- |
| red | `#FF4136` | `#e84855` |
| purple | `#7C4DFF` | `#8b5cf6` |
| cyan | `#00BCD4` | `#22d3ee` |
| pink | `#FF80AB` | `#f472b6` |
| orange | `#FF9800` | `#f59e0b` |
| yellow | `#FFEB3B` | `#eab308` |
| light blue | `#81D4FA` | `#38bdf8` |
| indigo | `#7986CB` | `#7c6f9c` |

Two palettes for one mascot set is unresolved drift. Pick one before either
gets used anywhere new.

---

## 4. Type

| Token | Stack |
| --- | --- |
| `--font-ui` | `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif` |
| `--font-mono` | `"SFMono-Regular", "SF Mono", "Fira Code", "Cascadia Code", "JetBrains Mono", monospace` |

Both stacks are supersets of the three UI and three mono variants that were
scattered across the pages before. On macOS — the only platform this product
runs on — they resolve identically to what shipped before.

| Token | Size | Use |
| --- | --- | --- |
| `--size-caption` | 12px | `.updated`, `pre` |
| `--size-small` | 13px | `code`, `.back`, eyebrow `h2`, footer, `.note p` |
| `--size-meta` | 14px | `.all-releases`, changelog list items |
| `--size-body` | 15px | `p`, `li` |
| `--size-lead` | 16px | `.lead` |
| `--size-title-sm` | 22px | `h1` below 480px |
| `--size-title` | 28px | `h1` |

Line height: `--leading-snug` 1.6, `--leading-body` 1.65.

Un-tokenised sizes, all single-use inside one page block: 11px (changelog
`h4`, homepage footer), 18px (licenses `h2`, hero terminal), 20px (changelog
`h3`), 30px (product heading).

**Every size is a `px` literal.** Text scaling therefore breaks layouts —
queued in `BACKLOG.md` under Responsive. Because the sizes are tokens now,
converting the scale to `rem` is one block in `style.css`.

### Headings

`h2` in the shared sheet is a **small uppercase eyebrow** — that is what three
of the four document pages using it want. Two pages need a display heading
instead and must opt out explicitly with `text-transform: none` *and* a `margin-top`
reset: `.product h2` on the homepage and `h2` on `/licenses`. Forgetting
either is the most likely way to break a page from this file.

---

## 5. Spacing, radius, motion

Spacing is not tokenised — it was never the source of duplication, and raw px
reads better here. The values in use form a loose 4px scale: 4, 8, 10, 12, 16,
20, 24, 28, 32, 36, 40, 48, 56, 64, 88, 96.

Radius: `--radius-sm` 4px (`.note`, `code`), `--radius-md` 6px (`pre`),
`--radius-lg` 8px (`.download-btn`). The product card uses 10px directly.

Motion: `--transition: 0.2s` for every colour transition. The homepage's
entrance, float, typewriter, scatter, and drift animations are hand-authored
in its own block and are not tokenised.

Only one breakpoint is shared: `max-width: 480px`. The homepage adds
`max-width: 720px` for the product windows. **Nothing addresses 481–719px**,
which is exactly where the audit found horizontal overflow — queued in
`BACKLOG.md` under Responsive.

---

## 6. Deliberate exceptions

Six values stayed as literals rather than becoming tokens. Each is used
exactly once, and each sits in a page block rather than `style.css`. Across
the seven pages that is down from 131 occurrences of 29 distinct literals.

1. `#ffffff` — `.download-btn` background. The only inverted surface on the site.
2. `rgba(255,255,255,0.55)` — changelog release summary. An off-ramp step.
3. `rgba(255,255,255,0.6)` — changelog list items. An off-ramp step.
4. `rgba(201,115,80,0.3)` — the product window glow. This is `--accent` with
   alpha; it stays literal because the glow is scheduled for removal or
   replacement along with the terracotta decision above.
5. `rgba(0,0,0,0.7)` and 6. `rgba(0,0,0,0.35)` — the two layers of the product
   card's drop shadow. The only shadow on the site; tokenise if a second one
   ever appears.

Two more things this file does not fix:

- **The homepage JS restates the diff colours inline.** The script at the
  bottom of `index.html` locks the final download line by writing
  `rgba(100,220,120,0.9)` and `rgba(80,210,100,0.13)` as inline styles. Those
  duplicate `--diff-add-fg` and `--diff-add-bg`. Change one, change both.
- **`pre` is styled in `style.css` but no page uses a `<pre>` today.** It was
  authored on `/licenses` and left in place rather than deleted as part of a
  refactor.

---

## 7. `/flows` is outside this system

`task-flows.html` has its own `:root` block with a different background
(`#0f0f0f`), a different body grey (`#e5e5e5`), and a different accent
spelling (`#c97350` lowercase, same colour). It was not migrated, because
whether the page stays on the site at all is an open decision in
`BACKLOG.md`. If it stays, it should adopt these tokens. If it goes, this
section goes with it.

---

## 8. Known gaps

These are real and tracked in `BACKLOG.md`; they are listed here so nobody
concludes from this document that the system is finished.

- No focus styling is authored anywhere. The browser default is intact, so
  this is a gap rather than a removal — but a design system should own it.
- `prefers-reduced-motion` is honoured by exactly one rule (`.bg-ghost`).
  Seventeen animations still run under `reduce`.
- Four footer variants across seven pages. `style.css` now holds the document
  footer; the homepage keeps a mono override. Collapsing them to one is a
  taste call, and deleting the override is all it takes.
- No `<main>` landmark or skip link on any page; no `<h1>` on the homepage.
