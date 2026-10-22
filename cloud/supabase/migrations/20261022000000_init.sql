-- Ghostties cloud: the schema web, mobile and the Mac desk share.
-- Types mirror cloud/contract/index.ts; change both together.
--
-- Shape: workspace -> desks (machines) + projects -> agents
--        (chief_of_staff -> general_manager -> worker) -> conversations
--        -> messages, with asks (agent waiting on a human) and tasks.
-- Every child row carries workspace_id so RLS and realtime filters are one
-- indexed equality, never a join.

-- MARK: - Enums

create type public.member_role   as enum ('owner', 'member');
create type public.desk_kind     as enum ('mac', 'cloud');
create type public.agent_role    as enum ('chief_of_staff', 'general_manager', 'worker');
create type public.agent_status  as enum ('busy', 'idle', 'needs_input', 'needs_permission', 'ended', 'offline');
create type public.author_kind   as enum ('user', 'agent', 'system');
create type public.message_kind  as enum ('text', 'status', 'ask', 'answer', 'handoff');
create type public.ask_kind      as enum ('question', 'permission', 'decision');
create type public.ask_status    as enum ('open', 'answered', 'expired', 'cancelled');
create type public.task_lane     as enum ('inbox', 'backlog', 'running', 'needs-you', 'review', 'done');
create type public.task_priority as enum ('high', 'medium', 'low', 'none');
create type public.push_platform as enum ('ios', 'macos', 'web');

-- MARK: - Tables

create table public.workspaces (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  owner_id   uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces on delete cascade,
  user_id      uuid not null references auth.users on delete cascade,
  role         public.member_role not null default 'member',
  created_at   timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index on public.workspace_members (user_id);

create table public.desks (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces on delete cascade,
  name         text not null,
  kind         public.desk_kind not null default 'mac',
  app_version  text,
  last_seen_at timestamptz,
  created_at   timestamptz not null default now()
);
create index on public.desks (workspace_id);

create table public.projects (
  id                 uuid primary key default gen_random_uuid(),
  workspace_id       uuid not null references public.workspaces on delete cascade,
  name               text not null,
  ghost_character    text,
  repo_url           text,
  desktop_project_id uuid,
  last_active_at     timestamptz,
  created_at         timestamptz not null default now(),
  unique (workspace_id, desktop_project_id)
);

create table public.agents (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null references public.workspaces on delete cascade,
  role             public.agent_role not null,
  name             text not null,
  project_id       uuid references public.projects on delete cascade,
  parent_agent_id  uuid references public.agents on delete set null,
  desk_id          uuid references public.desks on delete set null,
  status           public.agent_status not null default 'offline',
  summary          text,
  branch           text,
  ghost_character  text,
  last_activity_at timestamptz,
  created_at       timestamptz not null default now(),
  -- The chief of staff spans projects; everyone else belongs to one.
  check ((role = 'chief_of_staff') = (project_id is null))
);
create index on public.agents (workspace_id);
create unique index one_chief_of_staff_per_workspace
  on public.agents (workspace_id) where role = 'chief_of_staff';

create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid not null references public.workspaces on delete cascade,
  agent_id        uuid not null references public.agents on delete cascade,
  title           text,
  created_by      uuid references auth.users on delete set null,
  last_message_at timestamptz,
  created_at      timestamptz not null default now()
);
create index on public.conversations (workspace_id, last_message_at desc);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid not null references public.workspaces on delete cascade,
  conversation_id uuid not null references public.conversations on delete cascade,
  author_kind     public.author_kind not null,
  author_user_id  uuid references auth.users on delete set null,
  author_agent_id uuid references public.agents on delete set null,
  kind            public.message_kind not null default 'text',
  body            text not null,
  payload         jsonb not null default '{}',
  client_id       uuid,
  created_at      timestamptz not null default now(),
  unique (conversation_id, client_id),
  check (author_kind <> 'agent' or author_agent_id is not null)
);
create index on public.messages (conversation_id, created_at);
create index on public.messages (workspace_id);

create table public.asks (
  id                    uuid primary key default gen_random_uuid(),
  workspace_id          uuid not null references public.workspaces on delete cascade,
  agent_id              uuid not null references public.agents on delete cascade,
  conversation_id       uuid not null references public.conversations on delete cascade,
  kind                  public.ask_kind not null,
  prompt                text not null,
  options               jsonb not null default '[]',
  recommended_option_id text,
  status                public.ask_status not null default 'open',
  answer                jsonb,
  answered_by           uuid references auth.users on delete set null,
  answered_at           timestamptz,
  created_at            timestamptz not null default now()
);
create index open_asks on public.asks (workspace_id) where status = 'open';

create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces on delete cascade,
  project_id   uuid references public.projects on delete set null,
  agent_id     uuid references public.agents on delete set null,
  title        text not null,
  lane         public.task_lane not null default 'inbox',
  priority     public.task_priority not null default 'none',
  branch       text,
  body         text not null default '',
  source       text,
  source_id    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on public.tasks (workspace_id, lane);

create table public.conversation_reads (
  conversation_id uuid not null references public.conversations on delete cascade,
  user_id         uuid not null references auth.users on delete cascade,
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.push_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users on delete cascade,
  platform     public.push_platform not null,
  token        text not null unique,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index on public.push_tokens (user_id);

-- MARK: - Membership check (used by every policy)

create function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = ws and m.user_id = (select auth.uid())
  );
$$;

-- Realtime topics are "workspace:<uuid>"; anything else is denied, never an error.
create function public.workspace_from_topic(topic text) returns uuid
language sql immutable set search_path = '' as $$
  select case
    when topic ~ '^workspace:[0-9a-fA-F-]{36}$' then substr(topic, 11)::uuid
  end;
$$;

-- MARK: - Row level security

alter table public.workspaces         enable row level security;
alter table public.workspace_members  enable row level security;
alter table public.desks              enable row level security;
alter table public.projects           enable row level security;
alter table public.agents             enable row level security;
alter table public.conversations      enable row level security;
alter table public.messages           enable row level security;
alter table public.asks               enable row level security;
alter table public.tasks              enable row level security;
alter table public.conversation_reads enable row level security;
alter table public.push_tokens        enable row level security;

create policy "members read" on public.workspaces for select to authenticated
  using (public.is_member(id));
create policy "owner updates" on public.workspaces for update to authenticated
  using (owner_id = (select auth.uid()));

create policy "members read" on public.workspace_members for select to authenticated
  using (public.is_member(workspace_id));

-- Members have full access to the workspace's working tables. Today the Mac
-- desk signs in as the user, so agent-authored rows arrive with the user's
-- JWT. When cloud runners land, give them their own role and narrow these.
do $$
declare t text;
begin
  foreach t in array array['desks', 'projects', 'agents', 'conversations', 'asks', 'tasks'] loop
    execute format(
      'create policy "members all" on public.%I for all to authenticated
         using (public.is_member(workspace_id)) with check (public.is_member(workspace_id))', t);
  end loop;
end $$;

-- Messages are append-only, and a user can only speak as themselves.
create policy "members read" on public.messages for select to authenticated
  using (public.is_member(workspace_id));
create policy "members append" on public.messages for insert to authenticated
  with check (
    public.is_member(workspace_id)
    and (author_kind <> 'user' or author_user_id = (select auth.uid()))
  );

create policy "own reads" on public.conversation_reads for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own tokens" on public.push_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Private Broadcast/Presence channel per workspace.
create policy "members join workspace channel" on realtime.messages for select to authenticated
  using (public.is_member(public.workspace_from_topic((select realtime.topic()))));
create policy "members send on workspace channel" on realtime.messages for insert to authenticated
  with check (public.is_member(public.workspace_from_topic((select realtime.topic()))));

-- MARK: - Triggers

-- A message bumps its conversation so lists sort by recency.
create function public.touch_conversation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end $$;
create trigger messages_touch_conversation after insert on public.messages
  for each row execute function public.touch_conversation();

-- workspace_id is copied from the parent, never trusted from the client.
create function public.inherit_workspace_from_conversation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select c.workspace_id into strict new.workspace_id
  from public.conversations c where c.id = new.conversation_id;
  return new;
end $$;
create trigger messages_inherit_workspace before insert on public.messages
  for each row execute function public.inherit_workspace_from_conversation();
create trigger asks_inherit_workspace before insert on public.asks
  for each row execute function public.inherit_workspace_from_conversation();

create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;
create trigger tasks_touch_updated_at before update on public.tasks
  for each row execute function public.touch_updated_at();

-- Every new account gets a personal workspace with a chief of staff, so the
-- clients never render an empty org chart.
create function public.bootstrap_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare ws uuid;
begin
  insert into public.workspaces (name, owner_id) values ('Personal', new.id) returning id into ws;
  insert into public.workspace_members (workspace_id, user_id, role) values (ws, new.id, 'owner');
  insert into public.agents (workspace_id, role, name) values (ws, 'chief_of_staff', 'Chief of Staff');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.bootstrap_new_user();

-- MARK: - RPCs (security invoker: RLS still applies)

create function public.send_message(p_conversation_id uuid, p_body text, p_client_id uuid)
returns public.messages
language plpgsql set search_path = '' as $$
declare m public.messages;
begin
  insert into public.messages (conversation_id, author_kind, author_user_id, body, client_id)
  values (p_conversation_id, 'user', (select auth.uid()), p_body, p_client_id)
  on conflict (conversation_id, client_id) do nothing
  returning * into m;
  if m.id is null then
    select * into strict m from public.messages
    where conversation_id = p_conversation_id and client_id = p_client_id;
  end if;
  return m;
end $$;

create function public.start_conversation(
  p_agent_id uuid, p_body text, p_client_id uuid, p_title text default null
) returns public.conversations
language plpgsql set search_path = '' as $$
declare c public.conversations;
begin
  insert into public.conversations (workspace_id, agent_id, title, created_by)
  select a.workspace_id, a.id, p_title, (select auth.uid())
  from public.agents a where a.id = p_agent_id
  returning * into strict c;
  perform public.send_message(c.id, p_body, p_client_id);
  select * into strict c from public.conversations where id = c.id;
  return c;
end $$;

create function public.answer_ask(p_ask_id uuid, p_answer jsonb)
returns public.asks
language plpgsql set search_path = '' as $$
declare a public.asks;
begin
  update public.asks
  set status = 'answered', answer = p_answer,
      answered_by = (select auth.uid()), answered_at = now()
  where id = p_ask_id and status = 'open'
  returning * into a;
  if a.id is null then
    raise exception 'ask % is not open', p_ask_id using errcode = 'P0002';
  end if;
  insert into public.messages (conversation_id, author_kind, author_user_id, kind, body, payload)
  values (
    a.conversation_id, 'user', (select auth.uid()), 'answer',
    coalesce(
      (select o->>'label' from jsonb_array_elements(a.options) o where o->>'id' = p_answer->>'option_id'),
      p_answer->>'text', ''
    ),
    jsonb_build_object('ask_id', a.id) || p_answer
  );
  return a;
end $$;

create function public.mark_conversation_read(p_conversation_id uuid)
returns void
language sql set search_path = '' as $$
  insert into public.conversation_reads (conversation_id, user_id)
  values (p_conversation_id, (select auth.uid()))
  on conflict (conversation_id, user_id) do update set last_read_at = now();
$$;

create function public.register_push_token(p_platform public.push_platform, p_token text)
returns public.push_tokens
language plpgsql security definer set search_path = '' as $$
declare t public.push_tokens;
begin
  -- A token moves with the device, so a new sign-in on it takes it over.
  insert into public.push_tokens (user_id, platform, token)
  values ((select auth.uid()), p_platform, p_token)
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, last_seen_at = now()
  returning * into t;
  return t;
end $$;

create function public.desk_heartbeat(p_desk_id uuid, p_app_version text default null)
returns public.desks
language plpgsql set search_path = '' as $$
declare d public.desks;
begin
  update public.desks
  set last_seen_at = now(), app_version = coalesce(p_app_version, app_version)
  where id = p_desk_id
  returning * into strict d;
  return d;
end $$;

-- MARK: - Realtime publication

alter publication supabase_realtime add table
  public.messages, public.asks, public.agents, public.conversations, public.tasks, public.desks;
