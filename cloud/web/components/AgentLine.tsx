import Link from "next/link";
import type { Agent } from "@ghostties/contract";
import { Ghost } from "./Ghost";
import { StatusGlyph } from "./StatusGlyph";
import styles from "./AgentLine.module.css";

/** A roster row: status slot, ghost, name, one-line summary, age. */
export function AgentLine({
  agent,
  meta,
  age,
  depth = 0,
}: {
  agent: Agent;
  meta?: string;
  age: string;
  depth?: number;
}) {
  const talkable = agent.role !== "worker";
  const content = (
    <>
      <StatusGlyph status={agent.status} />
      <span className={styles.ghost}>
        <Ghost name={agent.ghost_character ?? "blinky"} size={14} />
      </span>
      <span className={styles.text}>
        <span className={styles.name}>
          {agent.name}
          {meta && <span className={styles.meta}>{meta}</span>}
        </span>
        {agent.summary && (
          <span className={styles.summary}>{agent.summary}</span>
        )}
      </span>
      <span className={styles.age}>{age}</span>
    </>
  );
  const style = { paddingLeft: `calc(var(--s2) + ${depth} * var(--s6))` };
  return talkable ? (
    <Link
      href={`/agents/${agent.id}`}
      className={`${styles.line} ${styles.link}`}
      style={style}
    >
      {content}
    </Link>
  ) : (
    <div className={styles.line} style={style}>
      {content}
    </div>
  );
}
