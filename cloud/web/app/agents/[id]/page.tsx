import Link from "next/link";
import { notFound } from "next/navigation";
import { Conversation } from "@/components/Conversation";
import { Ghost } from "@/components/Ghost";
import { StatusGlyph } from "@/components/StatusGlyph";
import {
  getAgent,
  getConversationForAgent,
  isConversational,
  listAgents,
  listDesks,
  listProjects,
} from "@/lib/data";
import styles from "./agent.module.css";

const ROLE = {
  chief_of_staff: "Chief of staff",
  general_manager: "General manager",
  worker: "Worker",
} as const;

// Stub data is static, so every conversation prerenders. With a live backend
// this list comes from the same query and new agents render on demand.
export async function generateStaticParams() {
  return (await listAgents())
    .filter(isConversational)
    .map((a) => ({ id: a.id }));
}

export async function generateMetadata({ params }: PageProps<"/agents/[id]">) {
  const agent = await getAgent((await params).id);
  return { title: agent?.name ?? "Agent" };
}

export default async function AgentPage({ params }: PageProps<"/agents/[id]">) {
  const { id } = await params;
  const [agent, data, desks, projects] = await Promise.all([
    getAgent(id),
    getConversationForAgent(id),
    listDesks(),
    listProjects(),
  ]);
  if (!agent || !data) notFound();
  const desk = desks.find((d) => d.id === agent.desk_id);
  const project = projects.find((p) => p.id === agent.project_id);

  return (
    <>
      <header className={styles.header}>
        <Link
          href="/"
          className={`back-link ${styles.back}`}
          aria-label="Back to Today"
        >
          ‹
        </Link>
        <span className={styles.ghost}>
          <Ghost name={agent.ghost_character ?? "blinky"} size={20} />
        </span>
        <div className={styles.titles}>
          <h1 className={styles.name}>{agent.name}</h1>
          <p className={styles.meta}>
            {[
              agent.name === ROLE[agent.role] ? null : ROLE[agent.role],
              project?.name,
              desk?.name,
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
        </div>
        <StatusGlyph status={agent.status} />
      </header>
      <Conversation
        workspaceId={agent.workspace_id}
        conversationId={data.conversation.id}
        agentName={agent.name}
        initialMessages={data.messages}
        asks={data.asks}
      />
    </>
  );
}
