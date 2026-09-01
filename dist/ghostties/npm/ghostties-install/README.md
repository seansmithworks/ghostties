# ghostties-install

A zero-dependency installer shim for [Ghostties](https://ghostties.org). Downloads the
newest published build of `Ghostties.app`, verifies it, and places it on your Mac.

**Published to npm.** `npx ghostties-install` resolves the newest release,
downloads it, verifies it, and installs it — no separate `npm install` step
needed.

**Recommended install path:** `brew install --cask seansmithworks/tap/ghostties`
(see [`../../homebrew/README.md`](../../homebrew/README.md)). This npm shim exists
for people who already live in `npx` and want a one-liner; the cask does more for
you (checksum-verified download, `/Applications` placement, `uninstall`/`zap`
cleanup) while Sparkle handles updates in-app either way. If you have Homebrew, use
the cask instead.

## Requirements

- macOS on **Apple silicon (arm64)**. There is no Intel build.
- Node.js >= 18 (for running `npx`).

## Usage

```
npx ghostties-install
```

Installs `Ghostties.app` into `/Applications`.

### Flags

| Flag              | Env var                 | Default         | Description                                      |
| ----------------- | ------------------------ | --------------- | ------------------------------------------------- |
| `--target <dir>`  | `GHOSTTIES_INSTALL_DIR`  | `/Applications` | Directory to install into.                        |
| `--force`         | —                        | off             | Overwrite an existing `Ghostties.app` at target.  |
| `-h`, `--help`    | —                        | —               | Show usage.                                       |

Example, installing somewhere other than `/Applications`:

```
npx ghostties-install --target ~/Applications
```

## What it does

1. Checks that you're on macOS/arm64. Hard-fails with a clear message otherwise —
   Ghostties has no Linux, Windows, or Intel build.
2. Resolves the newest published release from the GitHub API at run time. Every
   Ghostties release so far is a GitHub prerelease, so this reads the release list
   (not the "latest" endpoint, which excludes prereleases) and takes the newest entry.
3. Refuses to overwrite an existing install at the target unless you pass `--force`.
   Ghostties self-updates via Sparkle, so an existing install may already be newer
   than the release this installer just resolved.
4. Downloads that release's zip from GitHub Releases, with progress output
   (it's ~154 MB).
5. Verifies the download's SHA-256 against the digest GitHub published for that
   asset before touching the archive contents. On mismatch it deletes the download
   and exits non-zero — it will never extract or install an unverified binary.
6. Extracts with `ditto -x -k` (not `unzip`), which preserves extended attributes,
   symlinks, and code-signature integrity on `.app` bundles.
7. Verifies the extracted app bundle's code signature with `codesign` and confirms
   it's signed by Ghostties' Developer ID team identifier. This check doesn't depend
   on any version, so it keeps working the same way release after release.
8. Stages the app under a temp name inside the target directory and renames it
   into place, so a failure mid-install never leaves a half-written app behind.
9. Cleans up its temp download/extraction directory on both success and failure.

It does **not** strip the `com.apple.quarantine` extended attribute. Ghostties is
signed with a Developer ID certificate and notarized, so Gatekeeper clears it on
first launch; stripping quarantine in an installer is a security anti-pattern this
project won't do.

After install, Ghostties updates itself in place via Sparkle. You do not need to
re-run this installer for future versions.

## Always installs the newest release

This package resolves the newest published release from the GitHub API at
install time rather than pinning a version — a pinned version goes stale the
moment the next release ships, and this installer has no CI automation to bump
a pin on every release. Nothing in `bin/ghostties-install.js` needs to be
edited when a new version ships.

Integrity is verified two ways instead: the download's SHA-256 is checked
against the digest GitHub publishes for that exact asset, and the extracted
app bundle's code signature is checked against Ghostties' Developer ID team
identifier. The signature check is the stronger guarantee — it holds for every
future release, not just the one a checksum happened to be pinned to.

## Zero dependencies

This package has no runtime dependencies. It only uses Node.js built-in modules
(`fs`, `https`, `crypto`, `child_process`, `path`, `os`) and the macOS system tool
`ditto`. An installer that places a binary on your machine is exactly the kind of
tool that shouldn't carry supply-chain surface it doesn't need.
