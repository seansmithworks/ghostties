import type { Ask, AskAnswer, Message, Rpcs } from "@ghostties/contract";

// Client-side writes, one per contract RPC. Stubbed: each resolves after a
// short delay so the optimistic path is exercised. With the backend live the
// body is `supabase.rpc(name, args)` through `lib/supabase/client.ts`, and
// other people's rows arrive over realtime (REALTIME_TABLES).

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function sendMessage(
  args: Rpcs["send_message"]["args"],
  workspaceId: string,
): Promise<Rpcs["send_message"]["returns"]> {
  await wait(250);
  const row: Message = {
    id: `msg-${args.p_client_id}`,
    workspace_id: workspaceId,
    conversation_id: args.p_conversation_id,
    author_kind: "user",
    author_user_id: null,
    author_agent_id: null,
    kind: "text",
    body: args.p_body,
    payload: {},
    client_id: args.p_client_id,
    created_at: new Date().toISOString(),
  };
  return row;
}

export async function answerAsk(
  ask: Ask,
  answer: AskAnswer,
): Promise<Rpcs["answer_ask"]["returns"]> {
  await wait(250);
  return {
    ...ask,
    status: "answered",
    answer,
    answered_at: new Date().toISOString(),
  };
}
