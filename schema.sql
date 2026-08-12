-- ============================================================
-- PLU ARMY — Schema v2: real auth, locked-down RLS
-- Run in Supabase: SQL Editor -> New Query -> paste all -> Run
--
-- This REPLACES the old schema entirely. It drops the existing
-- tables and all their data (messages, photos, accounts) and
-- rebuilds everything on top of Supabase's own login system
-- instead of the old "anyone can write anything" setup.
--
-- BEFORE running this, also do the one-time dashboard steps in
-- SUPABASE_AUTH_SETUP.md — this SQL alone is not enough, phone
-- login won't work until that's done too.
-- ============================================================

-- ============================
-- 0. CLEAN SLATE
-- ============================
-- Wipes all existing app data and policies. Does NOT touch
-- auth.users (Supabase's own login table) — if you ever ran the
-- old schema and had test accounts, delete those separately from
-- Authentication -> Users in the dashboard.

drop table if exists reports cascade;
drop table if exists likes cascade;
drop table if exists replies cascade;
drop table if exists posts cascade;
drop table if exists users cascade;

-- ============================
-- 1. TABLES
-- ============================

-- Profile info for each logged-in account. The id is NOT
-- generated here — it's always the same id Supabase Auth
-- assigned when the person signed up, which is how the database
-- knows "this row belongs to whoever is currently logged in."
create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  phone text not null unique,
  location text,
  is_active boolean not null default true,
  is_admin boolean not null default false,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null check (type in ('text', 'audio', 'image')),
  content text,          -- text content, or file URL for audio/image
  is_pinned boolean not null default false,   -- admin announcements
  is_deleted boolean not null default false,  -- soft delete by admin/owner
  is_edited boolean not null default false,
  reply_to uuid references posts(id) on delete set null,
  created_at timestamptz not null default now()
);

create table replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create table likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)  -- one like per user per post
);

create table reports (
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

create index idx_posts_created_at on posts(created_at desc);
create index idx_replies_post_id on replies(post_id);
create index idx_likes_post_id on likes(post_id);
create index idx_reports_status on reports(status);

-- ============================
-- 3. HELPER: "is the currently logged-in person an admin?"
-- ============================
-- Used throughout the policies below instead of repeating the
-- same subquery everywhere. security definer + a fixed search_path
-- so it reliably reads the users table regardless of who calls it.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select is_admin from users where id = auth.uid()),
    false
  );
$$;

-- ============================
-- 4. GUARD TRIGGERS
-- ============================
-- Row-level security controls WHICH ROWS you can touch, but not
-- which COLUMNS within an allowed row. These two triggers close
-- that gap: they silently snap sensitive fields back to their old
-- value unless the person making the change is actually allowed
-- to change that field, no matter what the request body says.

-- Nobody can flip their own is_admin/is_active — only an admin
-- editing someone ELSE's row can do that.
create or replace function public.guard_user_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() = old.id then
    new.is_admin := old.is_admin;
    new.is_active := old.is_active;
  end if;
  return new;
end;
$$;

create trigger trg_guard_user_fields
before update on users
for each row execute function public.guard_user_fields();

-- Only an admin can pin/unpin a post — a regular user editing
-- their own message can't sneak a pin through.
create or replace function public.guard_post_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    new.is_pinned := old.is_pinned;
  end if;
  return new;
end;
$$;

create trigger trg_guard_post_fields
before update on posts
for each row execute function public.guard_post_fields();

-- ============================
-- 5. ROW LEVEL SECURITY
-- ============================

alter table users enable row level security;
alter table posts enable row level security;
alter table replies enable row level security;
alter table likes enable row level security;
alter table reports enable row level security;

-- USERS
-- Everyone can see basic profile info (names/avatars need to show
-- in the chat) — but only you can create your own row, and only
-- you (or an admin) can update it. The trigger above stops even
-- you from touching is_admin/is_active on yourself.
create policy "anyone can read profiles" on users
  for select using (true);

create policy "you can create only your own profile" on users
  for insert with check (auth.uid() = id);

create policy "you or an admin can update a profile" on users
  for update
  using (auth.uid() = id or public.is_admin())
  with check (auth.uid() = id or public.is_admin());

-- POSTS
-- Deleted posts are hidden from everyone except the author and
-- admins — enforced here, not just by the app hiding them visually.
create policy "visible posts are readable by everyone" on posts
  for select using (
    is_deleted = false or auth.uid() = user_id or public.is_admin()
  );

create policy "you can only post as yourself" on posts
  for insert with check (auth.uid() = user_id);

create policy "you or an admin can update a post" on posts
  for update
  using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- REPLIES (legacy table, kept for compatibility — the app
-- currently threads replies via posts.reply_to instead)
create policy "anyone can read replies" on replies
  for select using (true);

create policy "you can only reply as yourself" on replies
  for insert with check (auth.uid() = user_id);

-- LIKES
create policy "anyone can read likes" on likes
  for select using (true);

create policy "you can only like as yourself" on likes
  for insert with check (auth.uid() = user_id);

create policy "you can only remove your own like" on likes
  for delete using (auth.uid() = user_id);

-- REPORTS
-- Only admins can see the reports queue — who reported what is
-- moderation-sensitive, not something every member should read.
create policy "only admins can read reports" on reports
  for select using (public.is_admin());

create policy "you can only file a report as yourself" on reports
  for insert with check (auth.uid() = reported_by);

create policy "only admins can update reports" on reports
  for update using (public.is_admin());

-- ============================
-- 6. STORAGE POLICIES (post-media bucket)
-- ============================

drop policy if exists "public can upload media" on storage.objects;
drop policy if exists "public can read media" on storage.objects;
drop policy if exists "only logged-in users can upload media" on storage.objects;
drop policy if exists "anyone can view media" on storage.objects;

create policy "only logged-in users can upload media"
on storage.objects for insert
with check (bucket_id = 'post-media' and auth.role() = 'authenticated');

create policy "anyone can view media"
on storage.objects for select
using (bucket_id = 'post-media');

-- ============================
-- 7. REALTIME
-- ============================

alter publication supabase_realtime add table posts;
alter publication supabase_realtime add table likes;

-- ============================
-- 8. SEED YOUR OWN ADMIN ACCOUNT
-- ============================
-- Do this AFTER completing SUPABASE_AUTH_SETUP.md and after you've
-- registered your own account through the app once (as a normal
-- member). Then come back here, put in the same phone number you
-- registered with, and run this to promote that account to admin:
--
-- update users set is_admin = true where phone = '256700000000';
