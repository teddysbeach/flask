-- 로컬 Postgres 에서 마이그레이션을 검증하기 위한 Supabase 흉내 shim.
-- 실제 Supabase 에는 이미 존재하는 것들이라 마이그레이션에 포함하지 않는다.

create schema if not exists auth;
create schema if not exists storage;

do $$ begin
  create role anon;          exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role;  exception when duplicate_object then null; end $$;

grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant all on tables to service_role;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);

-- 요청 컨텍스트의 사용자 id. Supabase 는 JWT 에서 뽑지만 여기선 GUC 로 흉내낸다.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table if not exists storage.buckets (
  id text primary key, name text not null, public boolean not null default false
);
create table if not exists storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name      text not null,
  owner     uuid
);
alter table storage.objects enable row level security;

create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select string_to_array(name, '/')
$$;
