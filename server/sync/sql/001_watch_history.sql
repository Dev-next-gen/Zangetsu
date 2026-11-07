-- First VPS sync slice. Run on a dedicated PostgreSQL database as its owner.
-- PostgREST must expose only sync_api and verify Supabase-signed JWTs before
-- assuming the authenticated role. Do not expose PostgreSQL itself publicly.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$$;

create schema if not exists sync_api;
create schema if not exists sync_private;
revoke all on schema sync_api, sync_private from public;
grant usage on schema sync_api, sync_private to authenticated;

create or replace function sync_private.jwt_user_key()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub';
$$;
revoke all on function sync_private.jwt_user_key() from public;
grant execute on function sync_private.jwt_user_key() to authenticated;

create or replace function sync_private.keep_newer_history()
returns trigger
language plpgsql
as $$
begin
  if old.updated_at > new.updated_at then
    return old;
  end if;
  return new;
end;
$$;
revoke all on function sync_private.keep_newer_history() from public;

create table if not exists sync_api.history (
  user_key text not null,
  source_id text not null,
  show_id text not null,
  show_title text not null default '',
  cover text,
  cover_headers jsonb,
  show_url text,
  category text,
  episode_id text,
  episode_number double precision,
  episode_url text,
  position_ms bigint not null default 0,
  duration_ms bigint not null default 0,
  updated_at bigint not null default 0,
  mal_id text,
  primary key (user_key, source_id, show_id)
);

-- Profile rows are copied before the profile-management cutover. The profile
-- foreign key is added only after that copy, to avoid rejecting older users'
-- history while profile management still lives on Supabase.
create table if not exists sync_api.profile_history (
  user_key text not null,
  profile_id text not null,
  source_id text not null,
  show_id text not null,
  show_title text not null default '',
  cover text,
  cover_headers jsonb,
  show_url text,
  category text,
  episode_id text,
  episode_number double precision,
  episode_url text,
  position_ms bigint not null default 0,
  duration_ms bigint not null default 0,
  updated_at bigint not null default 0,
  mal_id text,
  primary key (user_key, profile_id, source_id, show_id)
);

create index if not exists history_recent_by_user
  on sync_api.history (user_key, updated_at desc, source_id, show_id);
create index if not exists profile_history_recent_by_user
  on sync_api.profile_history
  (user_key, profile_id, updated_at desc, source_id, show_id);

drop trigger if exists keep_newer_history on sync_api.history;
create trigger keep_newer_history before update on sync_api.history
  for each row execute function sync_private.keep_newer_history();
drop trigger if exists keep_newer_profile_history on sync_api.profile_history;
create trigger keep_newer_profile_history
  before update on sync_api.profile_history
  for each row execute function sync_private.keep_newer_history();

alter table sync_api.history enable row level security;
alter table sync_api.history force row level security;
alter table sync_api.profile_history enable row level security;
alter table sync_api.profile_history force row level security;

drop policy if exists own_history on sync_api.history;
create policy own_history on sync_api.history for all to authenticated
  using (user_key = sync_private.jwt_user_key())
  with check (user_key = sync_private.jwt_user_key());
drop policy if exists own_profile_history on sync_api.profile_history;
create policy own_profile_history on sync_api.profile_history
  for all to authenticated
  using (user_key = sync_private.jwt_user_key())
  with check (user_key = sync_private.jwt_user_key());

revoke all on sync_api.history, sync_api.profile_history from public;
grant select, insert, update, delete on sync_api.history, sync_api.profile_history
  to authenticated;
