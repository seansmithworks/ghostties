# Vendored: DialKit

- Source: `mikelikesdesign/dialkit-ios`
- Version: v0.3
- License: MIT

## Local modifications

1. **`Package.swift`: `platforms` lowered from `.macOS(.v14)` to `.macOS(.v13)`.**
   iOS platform (`.v17`) is unchanged. The app target that consumes this
   package has a macOS 13 floor (`decision_align-to-upstream-degrade-
   gracefully` — never raise the app floor for a fork feature), and
   `@available`/`#available` on the app side cannot gate an `import` of a
   module whose own package manifest declares a higher deployment target
   than the importing target — SwiftPM/Xcode reject the whole module at
   that lower target regardless of call-site guards. Lowering the
   manifest's floor here, then annotating the handful of macOS-14-only
   call sites individually (below), lets the app keep importing `DialKit`
   at its own macOS 13 floor while callers still gate actual macOS 14 API
   use behind `@available`/`#available` as before.

2. **`Sources/DialKit/DialPanelView.swift` and `Sources/DialKit/DialRoot.swift`:
   `@available(macOS 14, iOS 17, *)` added to the declarations that use the
   two-parameter `onChange(of:) { _, new in }` closure form** (a macOS
   14/iOS 17 SDK API, not just a deployment-target nicety), plus every
   type that constructs or is transitively reached through one of those
   declarations, so the manifest's lowered floor doesn't just move the
   compile error to those call sites instead:
   - `DialDrawerHost`
   - `DialDrawerPanel`
   - `DialPanelControlsView`
   - `DialTextRow`
   - `DialColorRow`
   - `DialTransitionControl`
   - `DialBezierRow`
   - `DialPanelContainer`
   - `DialRoot` (public entry point)

   No DialKit logic was rewritten — this is purely marking existing
   declarations as macOS-14/iOS-17-only, matching how the app already
   gates every DialKit call site behind `if #available(macOS 14, *)` /
   `@available(macOS 14, *)` (see `ComposerZeroChromeStyle.swift`).

3. **`Package.swift`: removed the `DialKitCoreTests` and `DialKitTests`
   test targets.** No `Tests/` directory was vendored alongside `Sources/`
   for either target, so the manifest failed to resolve
   ("Source files ... should be located under 'Tests/...'") independent of
   the platform floor. Since no test sources exist to vendor, the
   unpopulated target declarations were dropped rather than fabricated.
