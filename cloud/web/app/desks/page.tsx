import { PhoneNav } from "@/components/PhoneNav";
import { TASK_LANES, taskLaneLabel } from "@ghostties/contract";
import { AgentLine } from "@/components/AgentLine";
import {
  deskOnline,
  listAgents,
  listDesks,
  listProjects,
  listTasks,
  now,
} from "@/lib/data";
import { relative } from "@/lib/time";
import styles from "./desks.module.css";

export const metadata = { title: "Desks" };

/**
 * Where work runs. A desk is a machine hosting agents (the Mac app, or a
 * cloud runner); this page shows what each one is doing and, per project,
 * how the sidebar's task lanes stand. No terminal: that stays on the Mac.
 */
export default async function DesksPage() {
  const [desks, agents, projects, tasks] = await Promise.all([
    listDesks(),
    listAgents(),
    listProjects(),
    listTasks(),
  ]);
  const t = now();
  const projectName = (id: string | null) =>
    projects.find((p) => p.id === id)?.name;

  return (
    <div className="canvas-scroll">
      <div className="page">
        <PhoneNav current="desks" />
        <h1 className="page-title">Desks</h1>
        <p className="secondary">Machines hosting your agents.</p>

        <div className="section">
          {desks.map((desk) => {
            const online = deskOnline(desk);
            const hosted = agents.filter(
              (a) => a.desk_id === desk.id && a.role === "worker",
            );
            return (
              <section
                key={desk.id}
                className={styles.desk}
                aria-labelledby={desk.id}
              >
                <header className={styles.deskHeader}>
                  <span
                    className={`${styles.presence} ${online ? styles.online : ""}`}
                    aria-hidden="true"
                  />
                  <h2 id={desk.id} className={styles.deskName}>
                    {desk.name}
                  </h2>
                  <span className={styles.deskMeta}>
                    {desk.kind === "mac" ? "Mac" : "Cloud"}
                    {desk.app_version && ` · ${desk.app_version}`}
                    {" · "}
                    {online
                      ? "Online"
                      : `Last seen ${relative(desk.last_seen_at, t)} ago`}
                  </span>
                </header>
                {hosted.length === 0 ? (
                  <p className={styles.empty}>No sessions.</p>
                ) : (
                  <div className={styles.agents}>
                    {hosted.map((a) => (
                      <AgentLine
                        key={a.id}
                        agent={a}
                        meta={[projectName(a.project_id), a.branch]
                          .filter(Boolean)
                          .join(" · ")}
                        age={relative(a.last_activity_at, t)}
                      />
                    ))}
                  </div>
                )}
              </section>
            );
          })}
        </div>

        <section className="section" aria-labelledby="lanes">
          <h2 id="lanes" className="section-label">
            Lanes
          </h2>
          <div className={styles.tableWrap}>
            <table className={styles.lanes}>
              <thead>
                <tr>
                  <th scope="col">
                    <span className="visually-hidden">Project</span>
                  </th>
                  {TASK_LANES.map((lane) => (
                    <th key={lane} scope="col">
                      {taskLaneLabel(lane)}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {projects.map((p) => (
                  <tr key={p.id}>
                    <th scope="row">{p.name}</th>
                    {TASK_LANES.map((lane) => {
                      const n = tasks.filter(
                        (x) => x.project_id === p.id && x.lane === lane,
                      ).length;
                      return (
                        <td key={lane} className={n ? "" : styles.zero}>
                          {n || "–"}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  );
}
