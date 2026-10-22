# cloud/web

The Ghostties web app: talk to your chief of staff and general managers,
answer what's waiting on you, and see what each desk is running. No
terminal; that stays on the Mac.

Next.js 16 (App Router, Cache Components) on Vercel, Supabase for auth, data
and realtime. Types come from [`@ghostties/contract`](../contract), shared
with the mobile app.

```sh
cd cloud/web
npm install
npm run dev        # http://localhost:3000, on stub data
npm run build && npm run lint
```

## Screens

| Route          | What                                                                       |
| -------------- | -------------------------------------------------------------------------- |
| `/` Today      | Open asks ("Needs you"), then the org tree: chief of staff → GMs → workers |
| `/agents/[id]` | Conversation with the chief of staff or a GM, open asks inline, composer   |
| `/desks`       | Each desk's sessions and presence, plus task lanes per project             |
| `/login`       | Magic link, GitHub, Apple (live once Supabase env is set)                  |

## Where the backend plugs in

- **Reads**: `lib/data.ts` is the only module pages read from. Today it
  returns `lib/stub.ts`; each function becomes a `from(table).select()`
  through `lib/supabase/server.ts`.
- **Writes**: `lib/client-api.ts` has one function per contract RPC
  (`send_message`, `answer_ask`). Each becomes `supabase.rpc(...)`.
- **Live**: subscribe to `REALTIME_TABLES` and `workspaceChannel()` from the
  contract in the client components (`Conversation`, `AskCard`, `Rail`).
- **Auth**: `proxy.ts` refreshes the Supabase session cookie; add the
  redirect to `/login` there when auth is real. With no env set it is a no-op.

Env: copy `.env.example` to `.env.local`.

## Design

Tokens in `app/globals.css` come from the Mac app's [`DESIGN.md`](../../DESIGN.md):
the chrome + canvas layers, the five `ChromeTheme` colours and their steps,
the 12px card with its shadow, the 4px spacing scale, the status glyphs
(spinner, `?`, `✓`) and the 24 pixel ghosts (`lib/ghosts.ts`, generated from
`GhosttiesCore`). Terracotta stays reserved, so it isn't used here.

Where the web deliberately differs from the Mac sidebar:

- Rail text is 13px, not 11pt, and the canvas uses the centered-modal scale
  (15px body, 38px field), because a browser page is read at arm's length.
- Rows use an 8px radius and the ask box a 4px one, echoing the agent CLI's
  permission box. The 12px radius stays on the canvas card.
- Below 720px the rail hides and the canvas goes full-bleed.

## Deploying

Vercel project with Root Directory `cloud/web` and "Include files outside the
root directory" on (the contract lives in `../contract`). Set the two
`NEXT_PUBLIC_SUPABASE_*` variables.
