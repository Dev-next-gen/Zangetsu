-- Disposable database fixture: only the columns the change journal uses.
create table public.history (
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
create table public.profile_history (
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
