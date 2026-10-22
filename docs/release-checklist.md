# Ghostties Release Checklist

Follow these steps before tagging any release. The tag triggers CI (`.github/workflows/ghostties-release.yml`), and CI does most of the publishing. Everything before the tag is manual.

Until v1.0, a `-beta` tag publishes to **both** the beta and the stable appcast, because every install defaults to the stable channel. Tagging a beta therefore offers it as an update to every installed copy. Treat the tag as a one-way door.

What is still open for the next beta, and who can do it, is in the newest ship map under [`docs/ship/`](ship/).

## Before tagging

- [ ] All PRs for this release merged to `main`
- [ ] Full test suite green: the `xcodebuild test` command in [TESTING.md](../TESTING.md)
- [ ] **Turn `## [Unreleased]` in `CHANGELOG.md` into a dated section on `main`**: `## [0.5.0-beta.XX] — YYYY-MM-DD`, plain-language notes, no PR numbers, no hashes. Then add a fresh, empty `## [Unreleased]` above it. CI refuses to build a tag whose version has no dated section on `main`, and copies that section into the GitHub release body. This is the source of truth for all release copy.
- [ ] Smoke test the key changes on a local Release build

## Tagging

```bash
git tag v0.5.0-beta.XX && git push origin v0.5.0-beta.XX
```

CI runs these jobs in order:

1. `setup` checks the dated changelog section exists on `main`.
2. `build-macos` builds, signs and notarizes the DMG.
3. `appcast` writes both appcasts, bumps the version strings on `web/index.html` and `web/download.html`, and regenerates `web/changelog.html`, all on `main`.
4. `release` creates the GitHub release, with the changelog section as its body.
5. `homebrew-cask` opens a cask bump PR on the Homebrew tap. It runs only when the `HOMEBREW_TAP_REPO` variable is set.
6. `verify-release` checks every surface and writes a table to the run summary.

## After CI completes (~40 min)

- [ ] Read the `verify-release` summary. Anything not marked verified is yours to check by hand.
- [ ] Merge the cask bump PR on the Homebrew tap
- [ ] Smoke test: install the DMG, confirm Sparkle finds the next update (if applicable)

## Distribution surfaces checklist

| Surface                | Updated by                                   | Content                                |
| ---------------------- | -------------------------------------------- | -------------------------------------- |
| `CHANGELOG.md`         | Manual (before tag, on main)                 | Source of truth                        |
| Appcasts (both feeds)  | CI `appcast`                                 | Version, DMG URL, signature            |
| Sparkle dialog         | CI `appcast` (appcast item)                  | Version, commit, link to release notes |
| `web/` version strings | CI `appcast` (`update-web-version.py`)       | DMG URL, version, date, size           |
| `web/changelog.html`   | CI `appcast` (`generate-changelog-page.py`)  | Rendered from CHANGELOG.md             |
| GitHub release body    | CI `release`                                 | Copied from the CHANGELOG section      |
| Homebrew tap cask      | CI `homebrew-cask` opens a PR; merge by hand | Version + SHA256                       |
