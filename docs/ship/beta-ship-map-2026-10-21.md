# Beta 27 ship map, 2026-10-21

Every open item between `main` today (after #258) and tagging `v0.5.0-beta.27`, sorted by who can do it.

- **Cloud**: safe and checkable from a Linux sandbox (docs, `web/`, release copy). Done on `claude/beta-ship-push` unless marked otherwise.
- **Mac**: needs a build, a UI test, a capture or a signing step on Sean's Mac.
- **Sean**: a decision or a one-way door.

## Where the evidence comes from

`BACKLOG.md` left this repository on 2026-10-13 (#238) and now lives in a private notes repo. This file is public, so it doesn't quote the backlog. Each evidence line below is a quote from a public PR description, `CHANGELOG.md`, `AGENTS.md`, the release workflow or the site itself. A run with access to the notes should reconcile this map against the backlog's 2026-10-05 to 2026-10-21 entries before the tag.

## State of `main`

Beta 26 shipped 2026-10-12. Since then, 21 PRs merged (#237 to #258). Fourteen change what users see. `CHANGELOG.md` `## [Unreleased]` was empty. Two PRs are open, both docs-only drafts: #209 and #230.

## The ship map

| # | Item | Class | Evidence | Status |
|---|------|-------|----------|--------|
| 1 | Write the beta 27 changelog | Cloud | `CHANGELOG.md`: `## [Unreleased]` followed directly by `---`, after 14 user-facing merges | **Drafted** on this branch. Sean edits the wording |
| 2 | Release checklist describes an old pipeline | Cloud | `docs/release-checklist.md`: "Update `web/appcast-beta.xml` description — copy the changelog section"; the workflow now writes the appcast item and release body itself | **Done** on this branch |
| 3 | README install names only the DMG | Cloud | README: "Download the latest `.dmg` from Releases"; the site's recommended path is `brew install --cask` | **Done** on this branch |
| 4 | Homepage value prop and feature list | Cloud | `web/index.html` hero: "Ghostties runs every Claude Code session in one window"; no feature list on the page, though Codex is a built-in template since beta 26 | **Done** on this branch |
| 5 | Homepage accessibility below 100 | Cloud | Lighthouse `link-in-text-block` failed on the inline upstream link (accessibility 96) | **Done**: 100 locally |
| 6 | Download page has no first-launch guidance | Cloud | README "First launch" covers the macOS permission prompts; `/download` doesn't | **Done** on this branch |
| 7 | Meta and OG tags incomplete | Cloud | No `canonical`, `twitter:title`, `twitter:description` or image alt on either page | **Done** on this branch |
| 8 | `web/DESIGN.md` doesn't describe the live homepage | Cloud | `index.html` links `/v3.css`; `web/DESIGN.md` documents `style.css` and `v2.css` only | **Done**: §9 added |
| 9 | Launch kit drafts | Cloud | No launch copy exists for beta 26 or 27 | **Drafted** in `docs/ship/launch/` |
| 10 | Full suite green on `main` after #256, #257, #258 | Mac | #255: "Full GhosttyTests on 302356acc: 1993 total, 1991 passed, 1 failed" (`ComposerSingleLineStyleTests.singleLineFieldTextIsInsetFromTheCardsLeftEdge`, flaky); each later PR ran its suite on its own branch | Open |
| 11 | Root-cause the composer inset flake | Mac | #247: "fails identically on base 07a60c057; dark-mode pixel flake"; also seen on #248 and #255 | Open |
| 12 | Confirm the hover reveal reaches Release builds | Mac | #258: "behind the DialKit toggle 'Hover shows full sidebar', which defaults ON"; #243: DialKit is "DEBUG-only tooling … Release reads none of it" | Open. The changelog draft assumes it ships on |
| 13 | Hover reveal known limits | Mac, then Sean | #258: "No narrow-window clamp, so the reveal can squeeze the terminal below its minimum in very narrow windows"; "The terminal reflows on each reveal, and Ghostty's resize readout ('128 x 41') shows" | Open. Sean decides which block the tag |
| 14 | Browser-only window closes without asking from the red button and File > Close | Mac (Swift) | #257: "The window's red close button and File > Close by mouse still close a browser-only window without asking." | Open |
| 15 | Settings and theme picker live checks | Mac | #247: "Manual check before merge (needs a real keypress): Cmd+, from a focused terminal opens Settings"; #248: "window close mid-preview restores the theme" | Open. PRs say "Sean reviewed in Dev" for #252 to #254; #247 and #248 checks aren't recorded |
| 16 | Captures for the theme work | Mac | #250, #252: "not yet captured from the running app"; #244: "Before/after visuals: pending"; #246: "after-state captures … sent to Sean; not embedded yet" | Open. Needed for the beta 27 site and launch posts |
| 17 | Hover bar and rail reveal shadows after a light/dark switch | Mac (Swift) | #240: "The hover-bar (`backgroundEffectView`) and `railRevealBacking` shadows likely hit the same reset; logged as a follow-up." | Open |
| 18 | Log a missing bundled theme file | Mac (Swift) | #245: "If the bundled theme file were missing, the canvas silently falls back to the system window colour (follow-up: log it)." | Open |
| 19 | Re-check `zig build` now that upstream is on Zig 0.16 | Mac | `AGENTS.md`: "Build through Xcode until Zig 0.16 ships, then re-check." `CHANGELOG.md` beta 26: "Ghostties now builds on the latest upstream Ghostty (Zig 0.16)" | Open. If it works, `AGENTS.md` Commands changes |
| 20 | Homepage hero film | Mac | `web/index.html`: `src: '/assets/hero-dark.mp4', // not recorded yet` | Open. Not a tag blocker |
| 21 | Onboarding gaps found in #209 | Mac (Swift) | #209: "The onboarding 'Install gt' button only works from a repo checkout (`OnboardingSheet.swift:176`)"; "Claude Code status hooks are never registered automatically, so 'needs you' stays silent until the user pastes JSON by hand" | Open. The second one undercuts the headline feature for every new user |
| 22 | Light theme cyan contrast | Sean | #244: "light −~6%, only cyan (p6) crosses below 3:1 (2.83)" | Decide: accept, or tune Ghostties Light's p6 |
| 23 | Which onboarding concept | Sean | #209: "three clickable concepts (mild / wild / wilder)"; PR is a draft since 2026-10-10 | Decide, then merge or close #209 |
| 24 | Harness positioning | Sean | #230: "the business-vs-maker call, prioritized action items, and open questions" | Decide, then merge or close #230. Shapes the launch copy's angle, not the tag |
| 25 | Changelog wording for beta 27 | Sean | Item 1's draft was written from PR descriptions, not from using the build | Edit, then date the section |
| 26 | Tag `v0.5.0-beta.27` | Sean (one-way door) | `ghostties-release.yml`: "TEMPORARY RULE (until v1.0): betas go to the stable feed too"; a tag offers the update to every install | After items 10 to 16 and 25 |
| 27 | Merge the Homebrew cask PR | Sean | `ghostties-release.yml`: "homebrew-cask job only ever opens a PR against the tap — it never merges" | After the tag |
| 28 | Post the launch kit | Sean (one-way door) | Drafts only in `docs/ship/launch/`; nothing was posted | After the tag and the captures |
| 29 | Bundle identifier is still upstream's | Sean (one-way door, pre-1.0) | README: "The dialogs say 'Ghostty' rather than 'Ghostties' because they use the bundle identifier inherited from upstream." | Not for beta 27. Changing it later resets permissions and needs a Sparkle migration plan |

## Not in this map

- The "beta.15 and earlier" note on `/download` still reads correctly, so it was left alone.
- The ghost palette drift and the 17 homepage animations that ignore `prefers-reduced-motion` (`web/DESIGN.md` §3 and §7) are real, but neither blocks a beta.
- `#249`, `#245` and `#242` change nothing users see.

## Checks run on this branch

- Lighthouse 12.6.1, local `python3 -m http.server` (no production CSP), mobile defaults:
  - `index.html`: accessibility 96 → **100**, best practices 100, SEO 100, performance 94 to 96 across runs (same range as before the change)
  - `download.html`: 100 in all four categories, before and after
- No horizontal overflow at 1280, 600 or 375 px on either page.
- `scripts/update-web-version.py v0.5.0-beta.27` against a copy of the edited pages: all 7 patterns match.
- `scripts/generate-changelog-page.py` against the edited `CHANGELOG.md`: `web/changelog.html` is unchanged, because the undated Unreleased section is skipped.
