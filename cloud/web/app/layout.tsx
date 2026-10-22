import type { Metadata, Viewport } from "next";
import { Rail } from "@/components/Rail";
import {
  getWorkspace,
  listAgents,
  unreadByAgent,
  listProjects,
} from "@/lib/data";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Ghostties", template: "%s · Ghostties" },
  description: "Talk to your chief of staff, general managers and desks.",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f0e9e6" },
    { media: "(prefers-color-scheme: dark)", color: "#242424" },
  ],
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [workspace, agents, projects, unread] = await Promise.all([
    getWorkspace(),
    listAgents(),
    listProjects(),
    unreadByAgent(),
  ]);

  return (
    <html lang="en">
      <body>
        <div className="shell">
          <Rail
            workspace={workspace}
            agents={agents}
            projects={projects}
            unread={unread}
          />
          <main className="canvas">{children}</main>
        </div>
      </body>
    </html>
  );
}
