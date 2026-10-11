# Vendored: DialkitmacOS

- Source: `mikelikesdesign/dialkit-macos`
- Pinned commit: `cc305b46beb731e50cbdde84aed5530d83842acc` (2026-10-06)
- License: MIT (`LICENSE`)

Only the tuning API (`DialkitmacOS`, `DialkitmacOSCore`, `DialkitmacOSProtocol`)
and the debug agent (`DialkitmacOSAgent`) are vendored. The inspector app,
CLI, in-app UI, tests and examples are not; the inspector is built from the
upstream checkout: `swift run dialkit-macos`.

## Local modifications

1. **`Package.swift`: `platforms` is `.macOS(.v13)`, upstream is `.macOS(.v14)`;
   the target list is trimmed to the four above.** Same reason as the
   `Packages/DialKit` vendoring: the app has a macOS 13 floor, and Xcode
   rejects `import` of a module whose manifest declares a higher deployment
   target regardless of call-site `#available`. Sources are byte-identical to
   the pinned commit. Call sites in the app are guarded `@available(macOS 14, *)`.

2. The agent connects to `127.0.0.1:44777` only (`DialKitConnectionDefaults`),
   with no other network use. The app starts it from `SidebarDialInspector`,
   `#if DEBUG` only.

3. **Every source file is wrapped in `#if DIALKIT_ENABLED` / `#endif`** (first and last
   line), and `Package.swift` defines it for the debug configuration only, so a Release
   build links empty modules and `scripts/assert-no-dialkit.sh` passes. Re-apply the
   wrapper when updating.

To update: re-copy `Sources/{DialKitProtocol,DialKitCore,DialKit,DialKitAgent}`
from a new commit, re-read the agent's networking code, bump the commit above.
