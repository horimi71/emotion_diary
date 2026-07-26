create table if not exists diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  emotion text not null,
  intensity text not null,
  emoji text not null,
  message text not null,
  photo_urls text[],
  created_at timestamptz not null default now()
);

alter table diary_entries add column if not exists photo_urls text[];

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

-- Storage: run this after creating a bucket named "diary-photos" (Storage → New bucket → Public bucket: ON)
create policy "authenticated_can_upload_diary_photos"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'diary-photos');

create policy "anyone_can_view_diary_photos"
  on storage.objects for select
  using (bucket_id = 'diary-photos');
