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

-- 이메일 대신 전화번호로 로그인하는 방식으로 전환하며 컬럼명도 맞춤 (내용은 그대로 유지됨)
alter table diary_entries rename column user_email to user_phone;

-- 관리자(01095306933@phone.emotiondiary.local)는 모든 회원의 기록/사진을 수정·삭제할 수 있다.
-- 그 외에는 update/delete 정책이 없으므로 일반 회원은 자신의 글도 수정/삭제할 수 없다.
create policy "admin_update_entries"
  on diary_entries for update
  using (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local')
  with check (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local');

create policy "admin_delete_entries"
  on diary_entries for delete
  using (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local');

create table if not exists diary_photos (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references diary_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null,
  created_at timestamptz not null default now()
);

-- 목록 화면용 저용량 썸네일(최대 320px, jpg quality 0.6). 원본(url)은 Full HD(1920x1080) 리사이즈본이며
-- 사진을 눌렀을 때만 로드된다. 기존 행은 thumb_url = url로 백필해 두었다(용량 절감은 안 됨).
alter table diary_photos add column if not exists thumb_url text;

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

create policy "admin_update_photos"
  on diary_photos for update
  using (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local')
  with check (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local');

create policy "admin_delete_photos"
  on diary_photos for delete
  using (auth.jwt() ->> 'email' = '01095306933@phone.emotiondiary.local');

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

-- photo_views, photo_downloads: no longer used by index.html (view-count limit and the
-- one-download-per-photo limit were both removed). Left in place, harmless if unused.
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
