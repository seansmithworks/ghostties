# Beta 27 ship map, 2026-10-21

> **Reader:** Sean, and any agent working toward the beta 27 tag. **Decay:** a dated snapshot. It is right as of 2026-10-21, a newer map in `docs/ship/` supersedes it, and it can be deleted once beta 27 is tagged. **Linked from:** `docs/release-checklist.md`. **Upstream boundary:** everything here is fork work; nothing goes to ghostty-org.

Every open item between `main` today (after #258) and tagging `v0.5.0-beta.27`, sorted by who can do it.

- **Cloud**: safe and checkable from a Linux sandbox (docs, `web/`, release copy). Done on `claude/beta-ship-push` unless marked otherwise.
- **Mac**: needs a build, a UI test, a capture or a signing step on Sean's Mac.
- **Sean**: a decision or a one-way door.

## Where the evidence comes from

`BACKLOG.md` left this repository on 2026-10-13 (#238) and now lives in a private notes repo. This file is public, so it doesn't quote the backlog, and **no backlog line was checked against this map**. Each evidence line below is a quote from a public PR description, `CHANGELOG.md`, `AGENTS.md`, the release workflow or the site itself. Before the tag, someone with the notes should reconcile this map against the backlog's 2026-10-05 to 2026-10-21 entries. Whether to reconcile against it is Sean's call, since he made the file private on purpose.

## State of `main`

Beta 26 shipped 2026-10-12. Since the tag, 24 PRs merged (#234 to #258). #234 to #236 were the beta 26 release itself (cask bump, backlog, betas on the stable feed); of the rest, fourteen change what users see. `CHANGELOG.md` `## [Unreleased]` was empty. Four PRs are open: drafts #209 and #230 (docs only), draft #259 (Swift, opened 2026-10-21 23:58 UTC, fixes the onboarding gaps #209 found), and #260 (Swift, ready for review, opened 2026-10-22 00:17 UTC, fixes three hover reveal defects found after #258 merged).

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
| 12 | Confirm the hover reveal reaches Release builds | Cloud | `SidebarDialKit.swift`: `hoverBarPushesCanvas` reads `bool(hoverBarPushesCanvasKey, default: true, …)`; its call site in `WorkspaceViewContainer.swift` `revealFromClosedStrip()` is not behind `#if DEBUG` | **Done**: Release ships it on, as the changelog draft says |
| 13 | Hover reveal known limits | Mac, then Sean | #258: "No narrow-window clamp, so the reveal can squeeze the terminal below its minimum in very narrow windows"; "The terminal reflows on each reveal, and Ghostty's resize readout ('128 x 41') shows"; "A width drag during a reveal persists the pinned width"; "The window reports pinned while the stored mode stays closed" | Open. #260 (item 32) fixes the last two. Sean decides which of the rest block the tag |
| 14 | Browser-only window closes without asking from the red button and File > Close | Mac (Swift) | #257: "The window's red close button and File > Close by mouse still close a browser-only window without asking." | Open |
| 15 | Settings and theme picker live checks | Mac | #247: "Manual check before merge (needs a real keypress): Cmd+, from a focused terminal opens Settings"; #248: "window close mid-preview restores the theme" | Open. PRs say "Sean reviewed in Dev" for #252 to #254; #247 and #248 checks aren't recorded |
| 16 | Captures for the theme work | Mac | #250, #252: "not yet captured from the running app"; #244: "Before/after visuals: pending"; #246: "after-state captures … sent to Sean; not embedded yet" | Open. Needed for the beta 27 site and launch posts |
| 17 | Hover bar and rail reveal shadows after a light/dark switch | Mac (Swift) | #240: "The hover-bar (`backgroundEffectView`) and `railRevealBacking` shadows likely hit the same reset; logged as a follow-up." | Open. Since #258 the closed sidebar reveals the real pinned layout by default, so the hover bar shadow only matters with that dial off; the rail reveal shadow still applies |
| 18 | Log a missing bundled theme file | Mac (Swift) | #245: "If the bundled theme file were missing, the canvas silently falls back to the system window colour (follow-up: log it)." | Open |
| 19 | Re-check `zig build` now that upstream is on Zig 0.16 | Mac | `AGENTS.md`: "Build through Xcode until Zig 0.16 ships, then re-check." `CHANGELOG.md` beta 26: "Ghostties now builds on the latest upstream Ghostty (Zig 0.16)" | Open. If it works, `AGENTS.md` Commands changes |
| 20 | Homepage hero film | Mac | `web/index.html`: `src: '/assets/hero-dark.mp4', // not recorded yet` | Open. Not a tag blocker |
| 21 | Onboarding gaps found in #209, fixed in draft #259 | Mac | #259: "I could not run them" (`ClaudeHookRegistrarTests`); "A local test run … plus a first-launch check of the sheet in task-first mode" | Open. Run the tests and the first-launch check, then merge. Until it ships, Claude Code status needs a manual hook setup, which `/download` now says |
| 22 | Light theme cyan contrast | Sean | #244: "light −~6%, only cyan (p6) crosses below 3:1 (2.83)" | Decide: accept, or tune Ghostties Light's p6 |
| 23 | Which onboarding concept | Sean | #209: "three clickable concepts (mild / wild / wilder)"; PR is a draft since 2026-10-10 | Decide, then merge or close #209 |
| 24 | Harness positioning | Sean | #230: "the business-vs-maker call, prioritized action items, and open questions" | Decide, then merge or close #230. Shapes the launch copy's angle, not the tag |
| 25 | Changelog wording for beta 27 | Sean | Item 1's draft was written from PR descriptions, not from using the build | Edit, then date the section |
| 26 | Tag `v0.5.0-beta.27` | Sean (one-way door) | `ghostties-release.yml`: "TEMPORARY RULE (until v1.0): betas go to the stable feed too"; a tag offers the update to every install | After items 10, 15 and 25, item 30 if #259 rides beta 27, item 32 (#260) merged or explicitly deferred, and whichever of 13, 14 and 21 Sean marks as blocking |
| 27 | Merge the Homebrew cask PR | Sean | `ghostties-release.yml`: "homebrew-cask job only ever opens a PR against the tap — it never merges" | After the tag |
| 28 | Post the launch kit | Sean (one-way door) | Drafts only in `docs/ship/launch/`; nothing was posted | After the tag and item 16's captures |
| 29 | Bundle identifier is still upstream's | Sean (one-way door, pre-1.0) | README: "The dialogs say 'Ghostty' rather than 'Ghostties' because they use the bundle identifier inherited from upstream." | Not for beta 27. Changing it later resets permissions and needs a Sparkle migration plan |
| 30 | Silent write to `~/.claude/settings.json` | Sean | #259: "if someone removes the hook, it comes back on the next launch. The options are: ship as is, add an opt-out flag, or gate it behind the onboarding 'Connect' step." | Decide before #259 merges. Also decides whether #259 rides beta 27 |
| 31 | Keep promoting `gt` and the MCP server? | Sean | `OnboardingSheet.swift:176`: the in-app install runs `scripts/install-gt.sh` from a repo checkout; #259 removes that button; #209's gt audit recommends a keep or stop-promoting call | Decide. This branch left them off the new homepage feature list and the launch kit, since an app install doesn't get them. README's "What it adds" and "Its relationship to Ghostty" still name them: a known overclaim to fix before launch, whichever way this goes |
| 32 | Merge #260, the hover reveal fixes | Mac | #260: "Leaving the reveal within 250ms was debounced away, leaving it stuck open"; "Dragging the edge past snap during a reveal saved `.collapsed` (and widths) as the user's mode"; full suite "1 fail … ('CEF did not initialize', env; branch touches no browser code)" | Open, not a draft. The changelog draft and launch copy ("it closes when the pointer leaves", "never changes whether the sidebar stays closed") are only true with #260 in. If it slips, cut those clauses |

## Not in this map

- The "beta.15 and earlier" note on `/download` still reads correctly, so it was left alone.
- The ghost palette drift and the 17 homepage animations that ignore `prefers-reduced-motion` (`web/DESIGN.md` §3 and §7) are real, but neither blocks a beta.
- `#249`, `#245` and `#242` change nothing users see.

## Checks run on this branch

- Lighthouse 12.6.1, local `python3 -m http.server` (no production CSP), mobile defaults:
  - `index.html`: accessibility 96 → **100**, best practices 100, SEO 100, performance 73 to 96 across six runs, swinging on total blocking time from `ghost-field.js`, which this branch doesn't touch (87 and 96 on `main`)
  - `download.html`: 100 in all four categories, before and after
- No horizontal overflow at 1280, 600 or 375 px on either page.
- `scripts/update-web-version.py v0.5.0-beta.27` against a copy of the edited pages: all 7 patterns match.
- `scripts/generate-changelog-page.py` against the edited `CHANGELOG.md`: `web/changelog.html` is unchanged, because the undated Unreleased section is skipped.
