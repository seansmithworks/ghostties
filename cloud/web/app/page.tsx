import { PhoneNav } from "@/components/PhoneNav";
import { AgentLine } from "@/components/AgentLine";
import { AskCard } from "@/components/AskCard";
import {
  deskOnline,
  listAgents,
  listDesks,
  listOpenAsks,
  listProjects,
  now,
} from "@/lib/data";
import type { Agent } from "@ghostties/contract";
import { relative } from "@/lib/time";
import styles from "./today.module.css";

export const metadata = { title: "Today" };

export default async function Today() {
  const [agents, asks, desks, projects] = await Promise.all([
    listAgents(),
    listOpenAsks(),
    listDesks(),
    listProjects(),
  ]);
  const t = now();
  const byId = new Map(agents.map((a) => [a.id, a]));
  const children = (parent: Agent) =>
    agents.filter((a) => a.parent_agent_id === parent.id);
  const chief = agents.find((a) => a.role === "chief_of_staff");
  const projectName = (id: string | null) =>
    projects.find((p) => p.id === id)?.name;
  const working = agents.filter(
    (a) => a.role === "worker" && a.status === "busy",
  ).length;
  const online = desks.filter(deskOnline).length;

  return (
    <div className="canvas-scroll">
      <div className="page">
        <PhoneNav current="today" />
        <h1 className="page-title">Today</h1>
        <p className="secondary">
          {asks.length} need{asks.length === 1 ? "s" : ""} you · {working}{" "}
          working · {online} of {desks.length} desks online
        </p>

        <section className="section" aria-labelledby="needs-you">
          <h2 id="needs-you" className="section-label">
            Needs you
          </h2>
          {asks.length === 0 ? (
            <p className="secondary">Nothing is waiting on you.</p>
          ) : (
            <div className={styles.asks}>
              {asks.map((a) => (
                <AskCard
                  key={a.id}
                  ask={a}
                  agentName={byId.get(a.agent_id)?.name ?? "Agent"}
                  linkToConversation
                />
              ))}
            </div>
          )}
        </section>

        {chief && (
          <section className="section" aria-labelledby="team">
            <h2 id="team" className="section-label">
              Team
            </h2>
            <div className={styles.tree}>
              <AgentLine
                agent={chief}
                age={relative(chief.last_activity_at, t)}
              />
              {children(chief).map((gm) => (
                <div key={gm.id}>
                  <AgentLine
                    agent={gm}
                    meta={projectName(gm.project_id)}
                    age={relative(gm.last_activity_at, t)}
                    depth={1}
                  />
                  {children(gm).map((w) => (
                    <AgentLine
                      key={w.id}
                      agent={w}
                      age={relative(w.last_activity_at, t)}
                      depth={2}
                    />
                  ))}
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
