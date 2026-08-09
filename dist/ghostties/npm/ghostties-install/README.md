# ghostties-install

A zero-dependency installer shim for [Ghostties](https://ghostties.org). Downloads a
pinned, checksum-verified build of `Ghostties.app` and places it on your Mac.

**Published to npm.** `npx ghostties-install` downloads the pinned,
checksum-verified `Ghostties.app` build and installs it — no separate `npm
install` step needed.

**Recommended install path: [Homebrew Cask](https://ghostties.org).** This npm shim
exists for people who already live in `npx` and want a one-liner; it defers to the
cask for everything else (auto-bumped versions, `brew upgrade`, uninstall hooks). If
you have Homebrew, use the cask instead.

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
2. Refuses to overwrite an existing install at the target unless you pass `--force`.
   Ghostties self-updates via Sparkle, so an existing install may already be newer
   than the version this installer is pinned to.
3. Downloads the pinned release zip from GitHub Releases, with progress output
   (it's ~154 MB).
4. Verifies the download's SHA-256 against a pinned checksum before touching the
   archive contents. On mismatch it deletes the download and exits non-zero —
   it will never extract or install an unverified binary.
5. Extracts with `ditto -x -k` (not `unzip`), which preserves extended attributes,
   symlinks, and code-signature integrity on `.app` bundles.
6. Stages the app under a temp name inside the target directory and renames it
   into place, so a failure mid-install never leaves a half-written app behind.
7. Cleans up its temp download/extraction directory on both success and failure.

It does **not** strip the `com.apple.quarantine` extended attribute. Ghostties is
signed with a Developer ID certificate and notarized, so Gatekeeper clears it on
first launch; stripping quarantine in an installer is a security anti-pattern this
project won't do.

After install, Ghostties updates itself in place via Sparkle. You do not need to
re-run this installer for future versions.

## Pinned version

This package pins an exact release tag and asset checksum rather than resolving
"latest" at install time — a pinned checksum is the supply-chain-safe design, and
because the app self-updates via Sparkle on first launch, a slightly-stale pin
self-heals immediately after install.

**Bumping the pin is currently a manual step**, not automated in CI. The
Homebrew cask's version bump is automated by a separate CI workflow in this repo;
the npm package's is not — publishing a new pin means `npm publish` by hand.
Because the app self-updates via Sparkle on first launch, a stale pin self-heals,
so this is a deliberate trade rather than a gap to close urgently. If you're
bumping this by hand: update `RELEASE.tag`, `RELEASE.assetName` (should stay the
same name), and `RELEASE.sha256` in `bin/ghostties-install.js`, using the sha256
GitHub reports for the release asset, then run `npm publish`.

## Zero dependencies

This package has no runtime dependencies. It only uses Node.js built-in modules
(`fs`, `https`, `crypto`, `child_process`, `path`, `os`) and the macOS system tool
`ditto`. An installer that places a binary on your machine is exactly the kind of
tool that shouldn't carry supply-chain surface it doesn't need.
