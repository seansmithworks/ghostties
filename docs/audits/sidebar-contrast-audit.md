# Sidebar Contrast Audit

Measurement only. WCAG 2.1 relative luminance, computed with `python3` per the formula in the brief. All alpha colors composited over their actual render backdrop before computing.

## Verdict

**Sean's suspicion is confirmed.** Every low-emphasis text element in the sidebar — section headers, session subtitles/timestamps, template subtitles, the build badge — resolves to **`tertiaryLabelColor` (25% opacity) and fails 4.5:1 in both modes**, worst case **1.31:1** (inactive-session dot, light). Session/template *titles* (opaque `.primary`/label color) pass with huge margin (12.98–17.78:1) — the failures are concentrated exactly where the brief predicted: low-emphasis text and the status-dot palette.

## Backgrounds used

| Token | Light | Dark |
|---|---|---|
| Chrome (`chromeBackgroundLight/Dark`) | `#F0E9E6` (240,233,230) | `white:0.14` → (36,36,36) |
| Canvas (`canvasBackgroundLight/Dark`) | `#FAF7F3` (250,247,243) | `white:0.18` → (46,46,46) |
| Popover/material (template picker; not a Ghostties token — system `NSColor.windowBackgroundColor`) | approx (236,236,236) | approx (40,40,40) |

Sidebar rows render on **chrome** (sidebar itself is `.background(.clear)`); the template picker is a native `.popover`, not chrome/canvas — its true background is system material, approximated here. Flagged per-row below.

## System dynamic colors — cannot read resolved value statically

`NSColor.tertiaryLabelColor` / `.secondaryLabelColor` have no static RGBA — Apple resolves them at draw time and doesn't publish exact values. The numbers below use the widely-documented/commonly-measured Apple values, **substituted, not verified against this specific OS build**:

- `labelColor`: light `rgba(0,0,0,1.0)` · dark `rgba(255,255,255,1.0)`
- `secondaryLabelColor`: light `rgba(0,0,0,0.5)` · dark `rgba(255,255,255,0.55)`
- `tertiaryLabelColor`: light `rgba(0,0,0,0.25)` · dark `rgba(255,255,255,0.25)`
- `systemGreen`: light `(52,199,89)` · dark `(48,209,88)`

SwiftUI's `.foregroundStyle(.tertiary)` / `.secondary)` (used in `TemplatePickerView.swift`) is treated as equivalent to the NSColor label hierarchy for this measurement — the exact `HierarchicalShapeStyle` opacity Apple applies is likewise unpublished.

## Results table

| Element | Mode | fg (nominal → composited) | bg | Ratio | Size/weight | Threshold | Verdict |
|---|---|---|---|---|---|---|---|
| Section header `ACTIVE 3` / `INACTIVE 2` / `ARCHIVE 124` (`RecentsListView.swift:559`) | Light | tertiaryLabel 25% on black → `rgb(180,175,173)` | chrome `(240,233,230)` | **1.81** | 10pt semibold | 4.5:1 | **FAIL** |
| Section header `ACTIVE 3` / etc. | Dark | tertiaryLabel 25% on white → `rgb(91,91,91)` | chrome `(36,36,36)` | **2.28** | 10pt semibold | 4.5:1 | **FAIL** |
| Section header `PINNED` / `RECENT` / `ALL PROJECTS` (`WorkspaceSidebarView.swift:445`) | Light | same token, same composite | chrome `(240,233,230)` | **1.81** | 10pt semibold | 4.5:1 | **FAIL** |
| Section header `PINNED` / etc. | Dark | same token, same composite | chrome `(36,36,36)` | **2.28** | 10pt semibold | 4.5:1 | **FAIL** |
| Session row title (`RecentsRowView.swift:78-80`), idle row | Light | `.primary` (opaque black) | chrome `(240,233,230)` | **17.50** | 12pt regular | 4.5:1 | PASS |
| Session row title, idle row | Dark | `.primary` (opaque white) | chrome `(36,36,36)` | **15.52** | 12pt regular | 4.5:1 | PASS |
| Session row title, ACTIVE row (tinted bg) | Light | `.primary` opaque | `activeRowLight` (4% black) over chrome → `(230,224,221)` | **16.05** | 12pt regular | 4.5:1 | PASS |
| Session row title, ACTIVE row | Dark | `.primary` opaque | `activeRowDark` (6% white) over chrome → `(49,49,49)` | **12.98** | 12pt regular | 4.5:1 | PASS |
| Session row subtitle (project name, `RecentsRowView.swift:84-86`) | Light | tertiaryLabel 25% → `(180,175,173)` | chrome `(240,233,230)` | **1.81** | 10pt regular | 4.5:1 | **FAIL** |
| Session row subtitle | Dark | tertiaryLabel 25% → `(91,91,91)` | chrome `(36,36,36)` | **2.28** | 10pt regular | 4.5:1 | **FAIL** |
| Session row timestamp (`RecentsRowView.swift:94-96`, same token) | Light/Dark | identical to subtitle above | chrome | **1.81 / 2.28** | 10pt regular | 4.5:1 | **FAIL** |
| Template name (`TemplatePickerView.swift:153-154`) | Light | `.primary` opaque | popover approx `(236,236,236)` | **17.78** | 12pt medium | 4.5:1 | PASS |
| Template name | Dark | `.primary` opaque | popover approx `(40,40,40)` | **14.74** | 12pt medium | 4.5:1 | PASS |
| Template subtitle / `"Default shell"` (`TemplatePickerView.swift:155-167`) | Light | `.tertiary` 25% → `(177,177,177)` | popover approx `(236,236,236)` | **1.82** | 10pt regular | 4.5:1 | **FAIL** |
| Template subtitle / `"Default shell"` | Dark | `.tertiary` 25% → `(94,94,94)` | popover approx `(40,40,40)` | **2.27** | 10pt regular | 4.5:1 | **FAIL** |
| Build badge (`BuildInfoBadgeView.swift:124-126`), 9pt (below 11pt UI floor by design) | Light | tertiaryLabel 25% → `(188,185,182)` | `.ultraThinMaterial`, approx canvas `(250,247,243)` | **1.83** | **9pt** regular | 4.5:1 | **FAIL** |
| Build badge | Dark | tertiaryLabel 25% → `(98,98,98)` | approx canvas `(46,46,46)` | **2.23** | 9pt regular | 4.5:1 | **FAIL** |
| Idle session dot (`RecentsRowView.swift:124`, `Color.primary.opacity(0.30)`) | Light | 30% black → `(168,163,161)` | chrome `(240,233,230)` | **2.08** | graphical object | 3:1 | **FAIL** |
| Idle session dot | Dark | 30% white → `(102,102,102)` | chrome `(36,36,36)` | **2.69** | graphical object | 3:1 | **FAIL** |
| Inactive session dot (`RecentsRowView.swift:125`, `Color.primary.opacity(0.12)`) | Light | 12% black → `(211,205,202)` | chrome `(240,233,230)` | **1.31** | graphical object | 3:1 | **FAIL** |
| Inactive session dot | Dark | 12% white → `(62,62,62)` | chrome `(36,36,36)` | **1.46** | graphical object | 3:1 | **FAIL** |
| Status dot — blue, your-turn `statusYourTurnBlue` `#5B8DEF` | Light | opaque `(91,141,239)` | chrome `(240,233,230)` | **2.69** | graphical object | 3:1 | **FAIL** |
| Status dot — blue | Dark | opaque `(91,141,239)` | chrome `(36,36,36)` | **4.81** | graphical object | 3:1 | PASS |
| Status dot — gold, needs-decision `statusNeedsDecisionGold` `#FFC400` | Light | opaque `(255,196,0)` | chrome `(240,233,230)` | **1.33** | graphical object | 3:1 | **FAIL (worst overall)** |
| Status dot — gold | Dark | opaque `(255,196,0)` | chrome `(36,36,36)` | **9.72** | graphical object | 3:1 | PASS |
| Status dot — orange, long-running `statusLongRunningOrange` `#F97316` | Light | opaque `(249,115,22)` | chrome `(240,233,230)` | **2.34** | graphical object | 3:1 | **FAIL** |
| Status dot — orange | Dark | opaque `(249,115,22)` | chrome `(36,36,36)` | **5.54** | graphical object | 3:1 | PASS |
| Status dot — green, working (`Color(.systemGreen)`, system dynamic) | Light | opaque `(52,199,89)` | chrome `(240,233,230)` | **1.85** | graphical object | 3:1 | **FAIL** |
| Status dot — green | Dark | opaque `(48,209,88)` | chrome `(36,36,36)` | **7.68** | graphical object | 3:1 | PASS |

## Every FAIL — proposed passing value

Ranked by real-world visibility (session/status content the user scans constantly, down to rarely-opened surfaces). All values are proposals for Sean's approval, not decisions — `WorkspaceLayout.swift`/`DESIGN.md` stay canonical until he signs off.

1. **All four status dots, light mode** (worst: gold **1.33:1**, then green 1.85, blue 2.69, orange 2.34) — the palette Sean picked for "green=working, blue=your-turn, gold=needs-decision, orange=long-running" is calibrated for dark chrome and collapses against the light `#F0E9E6` chrome. Smallest fix: darken each hue until it clears 3:1 against `(240,233,230)`, holding hue/saturation:
   - gold `#FFC400` → **`#A88100`**, ratio 3.00
   - green (systemGreen) `#34C759` → **`#289A45`**, ratio 3.00
   - orange `#F97316` → **`#D96413`**, ratio 3.00
   - blue `#5B8DEF` → **`#5584E1`**, ratio 3.00
   These four numbers only need to apply in light mode (dark mode already passes at 4.81–9.72:1) — if Sean wants one hex per state across both modes, use the darker light-mode value everywhere; it still passes dark mode with margin.

2. **Idle/Inactive session dots** (worst: inactive light **1.31:1**) — `Color.primary.opacity(0.30/0.12)` was tuned for "recede," not for meeting a graphical-object floor. Smallest fix: raise idle to opacity **0.55** (light) / **0.45** (dark) and inactive to opacity **0.62** (light) / **0.50** (dark) to clear 3:1 — but note these two states are deliberately near-invisible by design intent ("in the long tail"); Sean may instead choose to exempt them as decorative rather than informational (WCAG 1.4.11 doesn't require passing contrast for purely decorative UI). Flagging the design call rather than picking for him.

3. **`ACTIVE 3` / `INACTIVE 2` / `ARCHIVE 124` section headers** (light **1.81:1**, dark **2.28:1**) — high-traffic since they sit atop every list. Smallest fix: swap `sectionHeaderForeground` from `tertiaryLabelColor` (25%) to **`secondaryLabelColor`** (50%/55%) is *not* enough by itself (light mode secondary only reaches 3.83:1, still short). Needs a fixed opaque token instead of a system dynamic color: **`rgb(109,106,104)` / `#6D6A68`** in light, **`rgb(138,138,138)` / `#8A8A8A`** in dark — both land exactly at 4.50:1 against chrome.

4. **`PINNED` / `RECENT` / `ALL PROJECTS` section headers** — identical token, identical fix as #3.

5. **Session row subtitle (project name) + timestamp** (light **1.81:1**, dark **2.28:1**) — same `tertiaryLabelColor` token, same fix as #3: **`#6D6A68`** light / **`#8A8A8A`** dark, 4.50:1.

6. **Template subtitle / `"Default shell"`** (light **1.82:1**, dark **2.27:1**) — same fix pattern against the popover's material background: **`rgb(107,107,107)` / `#6B6B6B`** light, **`rgb(142,142,142)` / `#8E8E8E`** dark, both 4.50:1. (Notable: `#6B6B6B` is *exactly* `DESIGN.md`'s already-documented `textSecondary` light token — see Token Drift below. It was never wired into code.)

7. **Build badge** (light **1.83:1**, dark **2.23:1**) — lowest-traffic surface (dev-only, default off in Release) but still the worst nominal size (9pt, already below the 11pt floor by design). Fix: **`rgb(115,114,112)` / `#736F70`** light, **`rgb(148,148,148)` / `#949494`** dark, 4.50:1 against canvas. If the true `.ultraThinMaterial` backdrop is lighter/darker than canvas in practice, re-measure against the actual composited pixel before shipping — this number is an approximation, flagged above.

## `DESIGN.md` vs `WorkspaceLayout.swift` — token drift

**Verdict: `WorkspaceLayout.swift` is NOT a complete implementation of `DESIGN.md`, and `DESIGN.md` is stale in the other direction too.** Concretely:

- `DESIGN.md` documents `textPrimary` (`#1a1a1a`/`#f0efed`) and `textSecondary` (`#6b6b6b`/`#9a9a9a`) as canonical text-color tokens. **Neither exists in `WorkspaceLayout.swift`, and neither string appears anywhere in `macos/Sources/Features/Ghostties/`.** Code uses `Color.primary` / `Color(.tertiaryLabelColor)` (system dynamic colors) instead — a completely different mechanism than the fixed hex `DESIGN.md` specifies. This is the root cause of the contrast failures above: the fixed `textSecondary` hex would have passed (or nearly passed — see below); the system `tertiaryLabelColor` substitute does not.
- `DESIGN.md` documents `border` and `destructive` and `success` tokens (`#e5e5e3`/`#2a2a2a`, `#dc3545`, `#2d7d46`). **None of the three exist in `WorkspaceLayout.swift`.**
- `WorkspaceLayout.swift` has a full status-dot palette (`statusYourTurnBlue`, `statusNeedsDecisionGold`, `statusLongRunningOrange`, plus `sourceDot*` tokens) that **`DESIGN.md`'s "Activity indicator states" table doesn't reflect** — it still lists only `Waiting: waitingTerracotta`, `Running: — (system)`, `Idle/done: — (muted)`, which predates the blue/gold/orange convention-led palette.
- Checked `#6b6b6b` (DESIGN.md's `textSecondary` light) against the real chrome background: **4.44:1** — just short of 4.5:1, needs a hair darker (see fix #3 above, `#6D6A68`). Against dark chrome, `#9a9a9a` gets **5.52:1** — passes.

## Hardcoded-color violations found (outside `WorkspaceLayout.swift`)

```
$ grep -rEn "Color\(red:|NSColor\(red:|Color\(white:|NSColor\(white:" . | grep -v WorkspaceLayout.swift
./TaskRowView.swift:467:        case .running:  return Color(red: 0.541, green: 0.663, blue: 0.416) // sage
./NewTaskComposerView.swift:348:        .background(Color(white: 0.14))
```

- `TaskRowView.swift:467` — a **duplicate, not a divergence**: `0.541, 0.663, 0.416` is the exact same RGB as `WorkspaceLayout.sourceDotShell`. Should reference the token instead of restating the literal, but doesn't currently drift in value.
- `NewTaskComposerView.swift:348` — inside a `#Preview` block only (SwiftUI canvas preview background), not production render code. Still a literal that should be `WorkspaceLayout.expandedContainerDark` or similar per the "never hardcode" rule, but has zero runtime/user impact.

No other `Color(red:...)`, `NSColor(red:...)`, `Color(white:...)`, or 6-digit hex literals exist outside `WorkspaceLayout.swift` in `macos/Sources/Features/Ghostties/`. Font sizes and spacing values *are* hardcoded as inline literals throughout view files (e.g. `.font(.system(size: 10, weight: .semibold))` appears 6+ times across `RecentsListView.swift`, `WorkspaceSidebarView.swift`, `TemplatePickerView.swift`) rather than pulled from named constants — the repo convention as stated only appears to bind *colors* to `WorkspaceLayout`, not font sizes; flagging since the brief's framing ("colors and spacing are never hardcoded anywhere else") reads as covering both.

## `git status --short`

```
?? docs/audits/
?? docs/audits/sidebar-contrast-audit.md
```

(Plus the pre-existing untracked files from other in-flight work in this repo — `docs/plans/switchboard-status-engine-integration.html`, `drafts/`, `examples/`, `macos/Tests/Ghostties/ThrottleTrailingEdgeHypothesisTests.swift`, `scripts/demo/` — none touched by this pass.) Zero modifications to any tracked file.
