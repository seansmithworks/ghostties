-- Plays one user and one stranger through the RPCs and RLS.
\set ON_ERROR_STOP on
create function pg_temp.check(ok boolean, label text) returns text language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  return 'ok   ' || label;
end $$;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'sean@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'stranger@example.com');

-- Sean
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

select pg_temp.check(count(*) = 1, 'bootstrap made one workspace') from public.workspaces;
select pg_temp.check(name = 'Chief of Staff', 'bootstrap made a chief of staff') from public.agents;

insert into public.projects (workspace_id, name) select id, 'ghostties' from public.workspaces;
insert into public.agents (workspace_id, role, name, project_id, parent_agent_id)
  select p.workspace_id, 'general_manager', 'GM ghostties', p.id, a.id
  from public.projects p, public.agents a where a.role = 'chief_of_staff';

select pg_temp.check((public.start_conversation(
  (select id from public.agents where role = 'chief_of_staff'),
  'Morning. What needs me?', '11111111-1111-1111-1111-111111111111', 'Daily')).id is not null, 'start_conversation');
-- Retrying the same client_id returns the first message, not a duplicate.
select pg_temp.check((public.send_message((select id from public.conversations), 'Morning. What needs me?',
  '11111111-1111-1111-1111-111111111111')).id is not null, 'send_message retry');
select pg_temp.check(count(*) = 1, 'retry did not duplicate') from public.messages;
select pg_temp.check(last_message_at is not null, 'conversation touched') from public.conversations;

-- The desk (same JWT today) posts an agent ask.
insert into public.messages (conversation_id, author_kind, author_agent_id, kind, body)
  select c.id, 'agent', c.agent_id, 'text', 'Two things.' from public.conversations c;
insert into public.asks (agent_id, conversation_id, kind, prompt, options, recommended_option_id)
  select c.agent_id, c.id, 'decision', 'Merge #260?',
    '[{"id":"y","label":"Merge it"},{"id":"n","label":"Hold"}]', 'y'
  from public.conversations c;
select pg_temp.check((public.answer_ask((select id from public.asks), '{"option_id":"y"}')).status = 'answered', 'answer_ask');
select pg_temp.check(body = 'Merge it' and kind = 'answer', 'answer posted as message')
  from public.messages where kind = 'answer';

select public.mark_conversation_read((select id from public.conversations));
select pg_temp.check(count(*) = 1, 'mark_conversation_read') from public.conversation_reads;
select pg_temp.check((public.register_push_token('ios', 'a1b2c3d4e5f60718293a4b5c6d7e8f90')).platform = 'ios', 'register_push_token');
insert into public.desks (workspace_id, name) select id, 'Sean''s MacBook' from public.workspaces;
select pg_temp.check((public.desk_heartbeat((select id from public.desks), '1.4.0')).last_seen_at is not null, 'desk_heartbeat');

-- A user cannot speak as someone else.
do $$ begin
  insert into public.messages (conversation_id, author_kind, author_user_id, body)
    select id, 'user', '00000000-0000-0000-0000-00000000000b', 'spoof' from public.conversations;
  raise exception 'spoof was allowed';
exception when insufficient_privilege then null;
end $$;
select 'ok   spoofed author rejected';

-- Realtime channel auth.
select pg_temp.check(public.is_member(public.workspace_from_topic('workspace:' || id)), 'member may join own workspace channel') from public.workspaces;
set realtime.topic = 'not-a-workspace';
select pg_temp.check(count(*) = 0, 'bad topic denied, no error') from realtime.messages;

-- Stranger sees nothing of Sean's.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select pg_temp.check(count(*) = 1, 'stranger sees only own workspace') from public.workspaces;
select pg_temp.check(count(*) = 0, 'stranger sees no messages') from public.messages;
select pg_temp.check(count(*) = 0, 'stranger sees no asks') from public.asks;
do $$ begin
  perform public.send_message(
    (select id from public.conversations limit 1), 'x', gen_random_uuid());
  -- No visible conversation: the insert's trigger finds no row.
exception when no_data_found or insufficient_privilege or not_null_violation then null;
end $$;
select pg_temp.check(count(*) = 0, 'stranger cannot post') from public.messages;
