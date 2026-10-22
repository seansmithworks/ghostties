"use client";

import { useRef, useState, type FormEvent } from "react";
import type { Ask, Message } from "@ghostties/contract";
import { sendMessage } from "@/lib/client-api";
import { AskCard } from "./AskCard";
import styles from "./Conversation.module.css";

type Pending = Message & { pending?: boolean };

/**
 * A conversation with the chief of staff or a GM. User lines echo the agent
 * CLI's `> prompt` so the transcript reads like the Mac app's terminal
 * without being one. Sends are optimistic, keyed by `client_id`.
 */
export function Conversation({
  workspaceId,
  conversationId,
  agentName,
  initialMessages,
  asks,
}: {
  workspaceId: string;
  conversationId: string;
  agentName: string;
  initialMessages: Message[];
  asks: Ask[];
}) {
  const [messages, setMessages] = useState<Pending[]>(initialMessages);
  const [draft, setDraft] = useState("");
  const endRef = useRef<HTMLDivElement>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const body = draft.trim();
    if (!body) return;
    const clientId = crypto.randomUUID();
    setDraft("");
    setMessages((m) => [
      ...m,
      {
        id: clientId,
        workspace_id: workspaceId,
        conversation_id: conversationId,
        author_kind: "user",
        author_user_id: null,
        author_agent_id: null,
        kind: "text",
        body,
        payload: {},
        client_id: clientId,
        created_at: new Date().toISOString(),
        pending: true,
      },
    ]);
    requestAnimationFrame(() =>
      endRef.current?.scrollIntoView({ block: "end" }),
    );
    const saved = await sendMessage(
      {
        p_conversation_id: conversationId,
        p_body: body,
        p_client_id: clientId,
      },
      workspaceId,
    );
    setMessages((m) => m.map((x) => (x.client_id === clientId ? saved : x)));
  }

  return (
    <>
      <div className="canvas-scroll">
        <ol
          className={styles.log}
          aria-label={`Conversation with ${agentName}`}
        >
          {messages.map((m) => (
            <li
              key={m.id}
              className={`${styles.message} ${styles[m.author_kind]} ${m.pending ? styles.pending : ""}`}
            >
              {m.author_kind === "user" && (
                <span className={styles.prompt} aria-hidden="true">
                  &gt;
                </span>
              )}
              {m.author_kind === "agent" && (
                <span className={styles.dot} aria-hidden="true" />
              )}
              <span className="visually-hidden">
                {m.author_kind === "user"
                  ? "You: "
                  : m.author_kind === "agent"
                    ? `${agentName}: `
                    : ""}
              </span>
              <p className={styles.body}>{m.body}</p>
            </li>
          ))}
          {asks.map((a) => (
            <li key={a.id} className={styles.ask}>
              <AskCard ask={a} agentName={agentName} />
            </li>
          ))}
        </ol>
        <div ref={endRef} />
      </div>
      <form className={styles.composer} onSubmit={onSubmit}>
        <label htmlFor="composer" className="visually-hidden">
          Message {agentName}
        </label>
        <input
          id="composer"
          className={styles.field}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={`Message ${agentName}…`}
          autoComplete="off"
        />
        <button type="submit" className={styles.send} disabled={!draft.trim()}>
          Send
        </button>
      </form>
    </>
  );
}
