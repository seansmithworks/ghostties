# Ghostties mobile

The phone side of Ghostties: talk to your chief of staff and general managers,
and answer what they need from you. No terminal here. Sessions run on your
desks (the Mac app, later cloud runners); this app is the conversation layer
on top.

**Status:** scaffold. Every screen runs on an in-memory stub
(`src/api/stub.ts`). Nothing talks to a server yet.

## Stack

Expo SDK 58 (React Native 0.88, TypeScript strict, Expo Router, native tabs).

Why Expo over SwiftUI: the web app and backend are TypeScript (Next.js on
Vercel, Supabase), so the cloud contract types, the Supabase client and the
realtime code are shared as-is. One codebase covers iOS and Android, EAS builds
and ships without Xcode, and OTA updates skip App Review for JS changes. The
cost: the Mac app's SwiftUI views and `GhosttiesCore` don't carry over, so the
design language is re-expressed as tokens (below) rather than shared code.

## Run

```sh
cd mobile
npm install
npx expo start          # then i (iOS sim), a (Android), w (web), or scan with Expo Go
npm run typecheck
npm run lint
```

## Layout

| Path | What |
| --- | --- |
| `src/app/(tabs)/index.tsx` | **Needs you**: every open ask across agents, answered in place |
| `src/app/(tabs)/agents.tsx` | **Agents**: chief of staff, general managers, desks |
| `src/app/agent/[id].tsx` | One conversation with an agent, asks inline, optimistic send |
| `src/api/contract.ts` | Vendored copy of `cloud/contract` (the shared row and RPC types) |
| `src/api/client.ts` | `GhosttiesClient`: the one interface screens talk to |
| `src/api/stub.ts` | In-memory implementation with canned replies |
| `src/constants/theme.ts` | Design tokens carried over from the Mac app |
| `src/constants/ghosts.ts` | The 24 ghost silhouettes, generated from `GhosttiesCore` |

## Wiring the backend

1. When `cloud/contract` lands on `main`, delete `src/api/contract.ts` and
   re-export from `@ghostties/contract` in `src/api/types.ts`.
2. Add `SupabaseClient implements GhosttiesClient`: table reads via
   `from(...)`, writes via the `send_message`, `start_conversation` and
   `answer_ask` RPCs, and `subscribe` on `postgres_changes` for
   `REALTIME_TABLES`.
3. Pass it to `<ClientProvider client={...}>` in `src/app/_layout.tsx`.
4. Auth (magic link + Sign in with Apple) and push (`register_push_token`
   with an Expo push token) come after that.

## Design carry-over

Same rules as [`DESIGN.md`](../DESIGN.md), adapted for touch:

- Two layers: **chrome** (`#F0E9E6` / `#242424`) behind everything, **canvas**
  (`#FAF7F3` / `#141413`) for cards, with the terminal card's 12pt continuous
  corner and 6% shadow.
- Status is one monospaced glyph, as in the sidebar: braille spinner while
  busy, `?` in full ink when it needs you, `✓` idle, empty when offline.
  Reduce Motion freezes the spinner to `…`.
- No accent colour. Terracotta stays reserved for the waiting state; primary
  buttons are solid ink.
- Pixel ghosts are the same 12×12 grids the Mac app draws.
- Type uses the centred-modal scale (15 / 13 / 11) instead of 11pt sidebar
  density. Touch targets are at least 44pt.
