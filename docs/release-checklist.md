# Ghostties Release Checklist

Follow these steps before tagging any release. The tag triggers CI (`.github/workflows/ghostties-release.yml`), and CI does most of the publishing. Everything before the tag is manual.

Until v1.0, a `-beta` tag publishes to **both** the beta and the stable appcast, because every install defaults to the stable channel. Tagging a beta therefore offers it as an update to every installed copy. Treat the tag as a one-way door.

## Before tagging

- [ ] All PRs for this release merged to `main`
- [ ] Full test suite green: the `xcodebuild test` command in [TESTING.md](../TESTING.md)
- [ ] **Turn `## [Unreleased]` in `CHANGELOG.md` into a dated section on `main`**: `## [0.5.0-beta.XX] — YYYY-MM-DD`, plain-language notes, no PR numbers, no hashes. CI refuses to build a tag whose version has no dated section on `main`, and copies that section into the GitHub release body. This is the source of truth for all release copy.
- [ ] Smoke test the key changes on a local Release build

## Tagging

```bash
git tag v0.5.0-beta.XX && git push origin v0.5.0-beta.XX
```

CI will: check the changelog section → build, sign and notarize the DMG → create the GitHub release with the changelog section as its body → write both appcasts, bump the version strings on `web/index.html` and `web/download.html`, and regenerate `web/changelog.html` on `main` → open a cask bump PR on the Homebrew tap.

## After CI completes (~40 min)

- [ ] Verify `ghostties.org/appcast-stable.xml` and `ghostties.org/appcast-beta.xml` are live and show the new version
- [ ] Verify `ghostties.org/download` shows the new version and DMG size
- [ ] Merge the cask bump PR on the Homebrew tap
- [ ] Smoke test: install the DMG, confirm Sparkle finds the next update (if applicable)

## Distribution surfaces checklist

| Surface                 | Updated by                    | Content                                |
| ----------------------- | ----------------------------- | -------------------------------------- |
| `CHANGELOG.md`          | Manual (before tag, on main)  | Source of truth                        |
| GitHub release body     | CI                            | Copied from the CHANGELOG section      |
| Sparkle dialog          | CI (appcast item)             | Version, commit, link to release notes |
| Appcasts (both feeds)   | CI                            | Version, DMG URL, signature            |
| `web/` version strings  | CI (`update-web-version.py`)  | DMG URL, version, date, size           |
| `web/changelog.html`    | CI (`generate-changelog-page.py`) | Rendered from CHANGELOG.md         |
| Homebrew tap cask       | CI opens a PR; merge by hand  | Version + SHA256                       |
