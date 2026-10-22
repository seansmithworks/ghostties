import { StyleSheet, Text, View } from 'react-native';

import { useAgents, useDesks, useProjects } from '@/api/hooks';
import { isDeskOnline, type Agent } from '@/api/types';
import { AgentRow } from '@/components/agent-row';
import { Card } from '@/components/card';
import { Screen } from '@/components/screen';
import { SectionLabel } from '@/components/section-label';
import { Spacing, Type } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/**
 * Who you can talk to: the chief of staff, then one general manager per
 * project, then the desks they run on. Workers stay behind their GM.
 */
export default function AgentsScreen() {
  const theme = useTheme();
  const { data: agents } = useAgents();
  const { data: projects } = useProjects();
  const { data: desks } = useDesks();

  const chief = agents.filter((a) => a.role === 'chief_of_staff');
  const managers = agents.filter((a) => a.role === 'general_manager');
  const workersOf = (gm: Agent) => agents.filter((a) => a.parent_agent_id === gm.id && a.role === 'worker');

  const managerSubtitle = (gm: Agent) => {
    const project = projects.find((p) => p.id === gm.project_id)?.name;
    const workers = workersOf(gm);
    const waiting = workers.filter((w) => w.status === 'needs_input' || w.status === 'needs_permission').length;
    const parts = [
      gm.summary ?? project,
      workers.length ? `${workers.length} worker${workers.length === 1 ? '' : 's'}` : null,
      waiting ? `${waiting} waiting` : null,
    ];
    return parts.filter(Boolean).join(' · ');
  };

  return (
    <Screen title="Agents">
      {chief.length > 0 && (
        <>
          <SectionLabel>Chief of staff</SectionLabel>
          <Card>
            {chief.map((a, i) => (
              <AgentRow key={a.id} agent={a} last={i === chief.length - 1} />
            ))}
          </Card>
        </>
      )}
      {managers.length > 0 && (
        <>
          <SectionLabel>General managers</SectionLabel>
          <Card>
            {managers.map((a, i) => (
              <AgentRow key={a.id} agent={a} subtitle={managerSubtitle(a)} last={i === managers.length - 1} />
            ))}
          </Card>
        </>
      )}
      {desks.length > 0 && (
        <>
          <SectionLabel>Desks</SectionLabel>
          <Card>
            {desks.map((desk, i) => {
              const online = isDeskOnline(desk);
              return (
                <View
                  key={desk.id}
                  accessible
                  accessibilityLabel={`${desk.name}, ${online ? 'online' : 'offline'}`}
                  style={[
                    styles.desk,
                    i < desks.length - 1 && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.border },
                  ]}>
                  <Text style={[Type.rowTitle, { color: theme.ink, flex: 1 }]} numberOfLines={1}>
                    {desk.name}
                  </Text>
                  <Text style={[Type.rowSubtitle, { color: online ? theme.ink : theme.inkSecondary }]}>
                    {online ? 'Online' : 'Offline'}
                  </Text>
                </View>
              );
            })}
          </Card>
        </>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  desk: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    paddingHorizontal: Spacing.lg,
    minHeight: 48,
  },
});
