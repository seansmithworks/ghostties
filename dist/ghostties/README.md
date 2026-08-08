# Ghostties Distribution Packaging

This directory holds Ghostties-fork-specific distribution packaging
(Homebrew Cask, npm installer shim). It's namespaced under `dist/ghostties/`
rather than living directly in `dist/` so it doesn't collide with upstream
Ghostty's `dist/cmake`, `dist/linux`, `dist/macos`, `dist/windows`, and
`dist/doxygen`, which are still actively maintained upstream.
