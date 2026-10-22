"use client";

import Link from "next/link";
import { useState } from "react";
import type { Ask } from "@ghostties/contract";
import { answerAsk } from "@/lib/client-api";
import styles from "./AskCard.module.css";

const KIND = {
  permission: "Permission",
  decision: "Decision",
  question: "Question",
} as const;

/**
 * An agent waiting on you: a question, permission or decision. Styled after
 * the agent CLI's own permission box (the bordered block in the Mac app's
 * terminal) with numbered options, so a request reads the same everywhere.
 */
export function AskCard({
  ask,
  agentName,
  linkToConversation = false,
}: {
  ask: Ask;
  agentName: string;
  linkToConversation?: boolean;
}) {
  const [answered, setAnswered] = useState<string | null>(null);
  const [pending, setPending] = useState<string | null>(null);

  async function choose(optionId: string, label: string) {
    setPending(optionId);
    await answerAsk(ask, { option_id: optionId });
    setPending(null);
    setAnswered(label);
  }

  const isCommand = ask.kind === "permission";

  return (
    <section
      className={styles.card}
      aria-label={`${KIND[ask.kind]} from ${agentName}`}
    >
      <header className={styles.meta}>
        <span>{KIND[ask.kind]}</span>
        <span aria-hidden="true">·</span>
        {linkToConversation ? (
          <Link href={`/agents/${ask.agent_id}`} className={styles.agent}>
            {agentName}
          </Link>
        ) : (
          <span>{agentName}</span>
        )}
      </header>
      <p className={`${styles.prompt} ${isCommand ? "mono" : ""}`}>
        {ask.prompt}
      </p>
      {answered ? (
        <p className={styles.answered} role="status">
          ✓ {answered}
        </p>
      ) : (
        <ol className={styles.options}>
          {ask.options.map((o, i) => {
            const recommended = o.id === ask.recommended_option_id;
            return (
              <li key={o.id}>
                <button
                  type="button"
                  className={`${styles.option} ${recommended ? styles.recommended : ""}`}
                  disabled={pending !== null}
                  aria-busy={pending === o.id}
                  aria-describedby={o.detail ? `${ask.id}-${o.id}` : undefined}
                  onClick={() => choose(o.id, o.label)}
                >
                  <span className={styles.index}>{i + 1}.</span>
                  <span className={styles.label}>{o.label}</span>
                  {recommended && (
                    <span className={styles.tag}>Recommended</span>
                  )}
                </button>
                {o.detail && (
                  <p id={`${ask.id}-${o.id}`} className={styles.detail}>
                    {o.detail}
                  </p>
                )}
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}
