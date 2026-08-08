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
| `404.html` | Centred layout, ghost topple animation, `.home-link` |
| `privacy.html` | **None** — the shared sheet covers the whole page |

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

Grouped by role (prose ramp, then footer/timestamp ramp), not strictly by
value — see the ordering note on the token block in `style.css`. **The
contrast column is from the 2026-08-03 fix pass, measured against `--bg`.**
Everything below passes WCAG AA for body-size text.

| Token | Alpha | Contrast | Use |
| --- | --- | --- | --- |
| `--text-heading` | `#fff` | — | `h1`, changelog release titles |
| `--text-heading-soft` | 0.90 | — | Licenses section titles |
| `--text-primary` | 0.85 | — | `body` default |
| `--text-body` | 0.65 | pass | Prose, links, list items |
| `--text-note` | 0.52 | 5.468 | Callout copy |
| `--text-meta` | 0.50 | 5.156 | File size, "all releases" |
| `--text-label` | 0.48 | 4.857 | Eyebrow `h2`, back link, dates |
| `--text-label-quiet` | 0.46 | 4.570 | Changelog subsection labels |
| `--text-faint` | 0.55 | 5.959 | Footer text and links, timestamps, bullets |

`--text-faint` used to be the worst value on the site at 2.27:1 (0.25 alpha)
— it was the footer, which appears on all seven pages. Raising the floor to
0.55 fixed it in a single token edit, shipped 2026-08-03. `--diff-del-fg`
(the hero terminal's red diff line) is 4.720:1 against its own
`--diff-del-bg` composite. `--accent` is 4.916:1.

Hover pairs: `--text-body-hover` (0.9), `--text-meta-hover` (0.65),
`--text-label-hover` (0.6), `--text-faint-hover` (0.65).

Hairlines: `--line` (0.08), `--line-strong` (0.12), `--line-faint` (0.07).

### Focus

`:focus-visible` in `style.css` is the main focus styling on the site: a
`2px solid var(--accent)` ring with a 2px offset and `--radius-sm` corners,
applied globally rather than per-component. `:focus-visible` (not `:focus`)
means it shows for keyboard navigation and never for a mouse or touch tap.
`--accent` measures 4.916:1 against `--bg` here too. The one exception is
`.skip-link:focus`, which reveals the skip link itself on focus (a `:focus`,
not `:focus-visible`, since the link is otherwise off-screen and needs to
appear for any focus method that lands on it).

**Decision (2026-08-05): the focus ring keeps `--accent`.** Terracotta being
dropped as an *app brand* colour raised the question of whether it should
still carry an *interaction* meaning on the web. It stays, for three
reasons: it already passes AA (4.916:1), it is the site's only chromatic
colour so there is nothing else to reach for, and inventing a second accent
solely for focus would add a colour with no other purpose on the page. Don't
reopen this without a concrete reason `--accent` itself is being replaced.

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

Un-tokenised sizes, all single-use inside one page block: 0.6875rem/11px
(changelog `h3`, homepage footer), 18px (licenses `h2`, hero terminal),
1.25rem/20px (changelog `h2`), 30px (product heading).

**The tokenised sizes above are now all `rem`**, converted in the
2026-08-03 fix pass so they scale with the user's font-size setting instead
of ignoring it. The un-tokenised sizes right above this were converted too —
all four are `rem` (0.6875rem, 1.25rem, 1.125rem, 1.875rem) — they just
stayed out of the shared token sweep because each is single-use inside one
page block.

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

Motion: `--transition: 0.2s` for every colour transition, plus a mirrored
quartic easing pair — `--ease-out` (`cubic-bezier(0.25, 1, 0.5, 1)`) for
arrivals and `--ease-in` (`cubic-bezier(0.5, 0, 0.75, 0)`) for acceleration
under gravity. There is deliberately **no spring or overshoot curve**: it dates
a page quickly and draws attention to the motion instead of the thing moving.

Two things to know before authoring motion here:

- **Set easing per keyframe, not once on the shorthand.** A single curve across
  a multi-phase sequence reads as a flip. `animation-timing-function` inside a
  keyframe block applies to the segment *starting* at that keyframe — that is
  how `/404`'s topple decelerates into its teeter, accelerates through the
  fall, and decelerates on each rebound.
- **Those per-keyframe curves must be literal `cubic-bezier()`.** `var()` is
  not substituted for `animation-timing-function` inside `@keyframes`, and it
  fails *silently* by falling back to the shorthand's curve. Verified in
  Chromium. Keep the literals in sync with the two tokens by hand.

The homepage's entrance, float, typewriter, scatter, and drift animations
predate these tokens and are hand-authored in its own block.

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

## 7. Known gaps

These are real and tracked in `BACKLOG.md`; they are listed here so nobody
concludes from this document that the system is finished.

- `prefers-reduced-motion` is honoured on `/404` (the ghost fades in already
  fallen — gentler, not zero) and by exactly one rule on the homepage
  (`.bg-ghost`). Seventeen homepage animations still run under `reduce`.
- Two footer variants across seven pages. `style.css` now holds one identical
  `.footer-links` block shared by the six document pages; the homepage keeps
  its own variant (an icons span plus a three-link row, no Licenses link).
  Collapsing them to one is a taste call, and deleting the homepage override
  is all it takes.
