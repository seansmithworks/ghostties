# Ghostties for iPhone

The phone side of Ghostties: talk to your chief of staff and general
managers, and answer what they need from you. No terminal here. Sessions run
on your desks (the Mac app, later cloud runners); this app is the
conversation layer on top.

**Status:** scaffold. Every screen runs on an in-memory stub
(`Ghostties/StubClient.swift`). Nothing talks to a server yet.

Native SwiftUI, iOS 18+, no third-party dependencies yet.

## Run

Open `ios/Ghostties.xcodeproj`, pick the **Ghostties iOS** scheme and an
iPhone simulator, and run. From the command line:

```sh
xcodebuild build -project ios/Ghostties.xcodeproj -scheme "Ghostties iOS" \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

The project uses folder-synced groups: add a `.swift` file under
`ios/Ghostties/` and it is in the target, no project edit needed.

## Layout

| File | What |
| --- | --- |
| `NeedsYouView.swift` | **Needs you**: every open ask across agents, answered in place |
| `AgentsView.swift` | **Agents**: chief of staff, general managers, desks |
| `ConversationView.swift` | One conversation with an agent, asks inline, optimistic send |
| `Contract.swift` | Codable mirror of the cloud contract rows |
| `GhosttiesClient.swift` | The one protocol views reach the backend through |
| `StubClient.swift`, `StubSeed.swift` | In-memory implementation and its sample rows |
| `AppStore.swift` | `@Observable` state, kept current by the client's change stream |
| `Theme.swift` | Design tokens carried over from the Mac app |
| `GhostGrids.swift` | The 24 ghost silhouettes, generated from `GhosttiesCore` |

## Wiring the backend

1. Add the shared Swift contract package (`cloud/contract`, product
   `GhosttiesCloud`) as a local package and delete `Contract.swift`.
2. Add `supabase-swift` and a `SupabaseClient: GhosttiesClient`: table reads,
   the `send_message` / `start_conversation` / `answer_ask` RPCs, and
   Realtime `postgres_changes` for `changes()`.
3. Pass it to `AppStore(client:)` in `GhosttiesApp.swift`.
4. Then Sign in with Apple, and APNs push through `register_push_token`.

## Design carry-over

Same rules as [`DESIGN.md`](../DESIGN.md), adapted for touch:

- Two layers: **chrome** (`#F0E9E6` / `#242424`) behind everything,
  **canvas** (`#FAF7F3` / `#141413`) for cards, with the terminal card's 12pt
  continuous corner and 6% shadow.
- Status is one monospaced glyph, as in the sidebar: braille spinner while
  busy, `?` in full ink when it needs you, `✓` idle, empty when offline.
  Reduce Motion freezes the spinner to `…`.
- No accent colour. Terracotta stays reserved for the waiting state; primary
  buttons are solid ink.
- Pixel ghosts are the same 12×12 grids the Mac app draws.
- Type uses the centred-modal scale (15 / 13 / 11) as Dynamic Type text
  styles. Touch targets are at least 44pt.
