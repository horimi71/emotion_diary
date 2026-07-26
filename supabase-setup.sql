create table if not exists diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  emotion text not null,
  intensity text not null,
  emoji text not null,
  message text not null,
  created_at timestamptz not null default now()
);

alter table diary_entries enable row level security;

create policy "select_all_for_members"
  on diary_entries for select
  using (auth.role() = 'authenticated');

create policy "insert_own_entries"
  on diary_entries for insert
  with check (auth.uid() = user_id);

create index if not exists diary_entries_user_created_idx
  on diary_entries (user_id, created_at desc);

alter publication supabase_realtime add table diary_entries;
