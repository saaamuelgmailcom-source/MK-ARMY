-- ============================================================
-- PLU ARMY — Consolidated Database Schema
-- Run in Supabase: SQL Editor -> New Query -> paste all -> Run
--
-- This combines the project's migration history into a single
-- file: tables, indexes, RLS policies, storage policies, and
-- realtime publication.
--
-- SECURITY NOTE: the RLS policies below are intentionally open
-- (using (true)) because the app currently authenticates users
-- by name+phone lookup rather than Supabase Auth. This means
-- any client holding the anon key can write to any row in
-- these tables (e.g. set is_admin = true on any user, edit or
-- delete any post). Do not treat this as a secure baseline —
-- see the PLU ARMY security review for the fix (migrating to
-- Supabase phone-OTP auth with auth.uid()-scoped policies).
-- ============================================================

-- ============================
-- 1. TABLES
-- ============================

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null unique,
  location text,
  is_active boolean not null default true,
  is_admin boolean not null default false,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null check (type in ('text', 'audio', 'image')),
  content text,          -- text content, or file URL for audio/image
  is_pinned boolean not null default false,   -- admin announcements
  is_deleted boolean not null default false,  -- soft delete by admin
  reply_to uuid references posts(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)  -- one like per user per post
);

create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  reported_by uuid not null references users(id) on delete cascade,
  reason text,
  status text not null default 'pending' check (status in ('pending', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);

-- ============================
-- 2. INDEXES
-- ============================

create index if not exists idx_posts_created_at on posts(created_at desc);
create index if not exists idx_replies_post_id on replies(post_id);
create index if not exists idx_likes_post_id on likes(post_id);
create index if not exists idx_reports_status on reports(status);

-- ============================
-- 3. ROW LEVEL SECURITY
-- ============================

alter table users enable row level security;
alter table posts enable row level security;
alter table replies enable row level security;
alter table likes enable row level security;
alter table reports enable row level security;

-- USERS
create policy "public can read users" on users for select using (true);
create policy "public can insert users" on users for insert with check (true);
create policy "public can update users" on users for update using (true);

-- POSTS
create policy "public can read posts" on posts for select using (true);
create policy "public can insert posts" on posts for insert with check (true);
create policy "public can update posts" on posts for update using (true);

-- REPLIES
create policy "public can read replies" on replies for select using (true);
create policy "public can insert replies" on replies for insert with check (true);

-- LIKES
create policy "public can read likes" on likes for select using (true);
create policy "public can insert likes" on likes for insert with check (true);
create policy "public can delete likes" on likes for delete using (true);

-- REPORTS
create policy "public can read reports" on reports for select using (true);
create policy "public can insert reports" on reports for insert with check (true);
create policy "public can update reports" on reports for update using (true);

-- ============================
-- 4. STORAGE POLICIES (post-media bucket)
-- ============================

create policy "public can upload media"
on storage.objects for insert
with check (bucket_id = 'post-media');

create policy "public can read media"
on storage.objects for select
using (bucket_id = 'post-media');

-- ============================
-- 5. REALTIME
-- ============================

alter publication supabase_realtime add table posts;
alter publication supabase_realtime add table likes;

-- ============================
-- 6. SEED ADMIN ACCOUNT
-- ============================
-- Run this once manually in the SQL editor with your own details —
-- not committed here since name/phone are personal identifiers.
--
-- insert into users (name, phone, location, is_active, is_admin)
-- values ('Your Name', '0700000000', 'Kampala', true, true);
