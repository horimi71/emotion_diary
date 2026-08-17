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

-- ===== 사진 첨부 확장: 계정 표시, 좋아요/싫어요, 조회/다운로드 제한 =====

alter table diary_entries add column if not exists user_email text;

create table if not exists diary_photos (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references diary_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null,
  created_at timestamptz not null default now()
);

alter table diary_photos enable row level security;

create policy "select_all_photos_for_members"
  on diary_photos for select
  using (auth.role() = 'authenticated');

create policy "insert_own_photos"
  on diary_photos for insert
  with check (auth.uid() = user_id);

create index if not exists diary_photos_entry_idx on diary_photos (entry_id);
create index if not exists diary_photos_user_created_idx on diary_photos (user_id, created_at desc);

alter publication supabase_realtime add table diary_photos;

create table if not exists photo_reactions (
  photo_id uuid not null references diary_photos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (reaction in ('like', 'dislike')),
  created_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);

alter table photo_reactions enable row level security;

create policy "select_all_reactions_for_members"
  on photo_reactions for select
  using (auth.role() = 'authenticated');

create policy "manage_own_reaction"
  on photo_reactions for insert
  with check (auth.uid() = user_id);

create policy "update_own_reaction"
  on photo_reactions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "delete_own_reaction"
  on photo_reactions for delete
  using (auth.uid() = user_id);

alter publication supabase_realtime add table photo_reactions;

create table if not exists photo_views (
  photo_id uuid not null references diary_photos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  view_count int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);

alter table photo_views enable row level security;

create policy "select_own_views"
  on photo_views for select
  using (auth.uid() = user_id);

create policy "insert_own_views"
  on photo_views for insert
  with check (auth.uid() = user_id);

create policy "update_own_views"
  on photo_views for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists photo_downloads (
  photo_id uuid not null references diary_photos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);

alter table photo_downloads enable row level security;

create policy "select_own_downloads"
  on photo_downloads for select
  using (auth.uid() = user_id);

create policy "insert_own_downloads"
  on photo_downloads for insert
  with check (auth.uid() = user_id);
