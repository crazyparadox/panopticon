-- Panopticon cloud schema (Neon Postgres).
--
-- The Mac app owns the data and pushes day-level snapshots: the analysis
-- pipeline REPLACES a day's timeline cards in place (sliding-window regen),
-- so sync sends whole days and the server swaps them atomically rather than
-- upserting individual cards. Run this once against your Neon database:
--
--   psql "$DATABASE_URL" -f sql/schema.sql

create table if not exists timeline_cards (
  id bigserial primary key,
  device_id text not null,
  day text not null,                       -- "yyyy-MM-dd", 4 AM logical-day boundary
  start_ts bigint not null,                -- unix seconds
  end_ts bigint not null,
  start_time text not null,                -- display string, e.g. "3:45 PM"
  end_time text not null,
  category text not null,
  subcategory text not null default '',
  title text not null,
  summary text not null,
  detailed_summary text not null default '',
  distractions jsonb,
  app_sites jsonb,
  synced_at timestamptz not null default now()
);

create index if not exists timeline_cards_day_idx on timeline_cards (device_id, day);
create index if not exists timeline_cards_ts_idx on timeline_cards (device_id, start_ts);

create table if not exists daily_recaps (
  device_id text not null,
  day text not null,
  payload jsonb not null,                  -- PersistedDailyStandupDraft JSON from the app
  updated_at timestamptz not null default now(),
  primary key (device_id, day)
);

-- Sync bookkeeping: which days each device last pushed and when. Lets the
-- MCP surface data freshness, and the app resume incremental sync.
create table if not exists sync_state (
  device_id text not null,
  day text not null,
  cards_count integer not null default 0,
  pushed_at timestamptz not null default now(),
  primary key (device_id, day)
);
