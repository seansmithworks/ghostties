"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { Agent, Project, Workspace } from "@ghostties/contract";
import { Ghost } from "./Ghost";
import { StatusGlyph } from "./StatusGlyph";
import styles from "./Rail.module.css";

/**
 * The chrome column: the web counterpart of the Mac sidebar. It lists the
 * agents you talk to (the chief of staff, then one GM per project), not the
 * workers under them; those live on Today and Desks.
 */
export function Rail({
  workspace,
  agents,
  projects,
  unread,
}: {
  workspace: Workspace;
  agents: Agent[];
  projects: Project[];
  unread: Record<string, boolean>;
}) {
  const pathname = usePathname();
  const chief = agents.find((a) => a.role === "chief_of_staff");
  const managers = agents.filter((a) => a.role === "general_manager");
  const projectName = (id: string | null) =>
    projects.find((p) => p.id === id)?.name ?? "";

  return (
    <nav className={`rail ${styles.rail}`} aria-label="Workspace">
      <div className={styles.header}>
        <Ghost name="blinky" size={16} />
        <span className={styles.workspace}>{workspace.name}</span>
      </div>

      <ul className={styles.list}>
        <NavRow href="/" active={pathname === "/"} label="Today" />
        <NavRow href="/desks" active={pathname === "/desks"} label="Desks" />
      </ul>

      {chief && (
        <>
          <h2 className={styles.label}>Workspace</h2>
          <ul className={styles.list}>
            <AgentRow
              agent={chief}
              subtitle={`${managers.length} general managers`}
              active={pathname === `/agents/${chief.id}`}
              unread={unread[chief.id] ?? false}
            />
          </ul>
        </>
      )}

      <h2 className={styles.label}>General managers</h2>
      <ul className={styles.list}>
        {managers.map((a) => (
          <AgentRow
            key={a.id}
            agent={a}
            subtitle={projectName(a.project_id)}
            active={pathname === `/agents/${a.id}`}
            unread={unread[a.id] ?? false}
          />
        ))}
      </ul>

      <div className={styles.footer}>
        <Link href="/login" className={styles.footerLink}>
          Sign in
        </Link>
      </div>
    </nav>
  );
}

function NavRow({
  href,
  active,
  label,
}: {
  href: string;
  active: boolean;
  label: string;
}) {
  return (
    <li>
      <Link
        href={href}
        className={`${styles.row} ${active ? styles.active : ""}`}
        aria-current={active ? "page" : undefined}
      >
        <span className={styles.title}>{label}</span>
      </Link>
    </li>
  );
}

function AgentRow({
  agent,
  subtitle,
  active,
  unread,
}: {
  agent: Agent;
  subtitle: string;
  active: boolean;
  unread: boolean;
}) {
  return (
    <li>
      <Link
        href={`/agents/${agent.id}`}
        className={`${styles.row} ${styles.agentRow} ${active ? styles.active : ""}`}
        aria-current={active ? "page" : undefined}
      >
        <StatusGlyph status={agent.status} />
        <span className={styles.text}>
          <span className={`${styles.title} ${unread ? styles.unread : ""}`}>
            {agent.name}
          </span>
          <span className={styles.subtitle}>{subtitle}</span>
        </span>
        {unread && (
          <span className={styles.dot} role="img" aria-label="Unread" />
        )}
      </Link>
    </li>
  );
}
