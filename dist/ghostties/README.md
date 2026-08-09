# Ghostties Distribution Packaging

This directory holds Ghostties-fork-specific distribution packaging
(Homebrew Cask, npm installer shim). It's namespaced under `dist/ghostties/`
rather than living directly in `dist/` so it doesn't collide with upstream
Ghostty's `dist/cmake`, `dist/linux`, `dist/macos`, `dist/windows`, and
`dist/doxygen`, which are still actively maintained upstream.

## Install

Recommended:

```
brew install --cask seansmithworks/tap/ghostties
```

Alternative, if you don't have Homebrew:

```
npx ghostties-install
```

See `homebrew/README.md` and `npm/ghostties-install/README.md` for details.
