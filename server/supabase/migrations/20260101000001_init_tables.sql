-- ONPAR 초기 스키마
-- 설계 근거: docs/plan/03-data-model.md

create extension if not exists pgcrypto;

-- ── 사용자 프로필 ────────────────────────────────────────────────────────
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text,
  quota_total   int  not null default 2,   -- 가입 시 무료 2장
  quota_used    int  not null default 0,
  locale        text not null default 'ko',
  review_hour   int  not null default 21,  -- 복습 알림 시각 (로컬 0~23)
  timezone      text not null default 'Asia/Seoul',
  created_at    timestamptz not null default now(),
  constraint profiles_quota_nonneg check (quota_used >= 0 and quota_total >= 0)
);
comment on column public.profiles.quota_total is
  '구매/지급으로 늘어나는 총 생성 가능 장수. 환불 시 줄어들 수 있으므로 quota_used 를 밑돌 수 있다.';

-- ── 상품 카탈로그 ────────────────────────────────────────────────────────
-- 지급 장수의 유일한 근거. 클라이언트가 보낸 장수는 절대 쓰지 않는다.
create table public.products (
  id          text primary key,          -- onpar.sheets.10
  sheets      int  not null,
  price_krw   int  not null,
  is_active   boolean not null default true,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  constraint products_sheets_positive check (sheets > 0)
);

insert into public.products (id, sheets, price_krw, sort_order) values
  ('onpar.sheets.3',   3,  4900, 1),
  ('onpar.sheets.10', 10, 12900, 2),
  ('onpar.sheets.30', 30, 29900, 3);

-- ── 학습지 ──────────────────────────────────────────────────────────────
create table public.worksheets (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  topic           text not null,
  level           text not null default 'beginner',
  status          text not null default 'queued',
  title           text,
  content         jsonb,
  html_path       text,
  error_code      text,
  plan_model      text,
  draft_model     text,
  prompt_version  text,
  created_at      timestamptz not null default now(),
  ready_at        timestamptz,
  constraint worksheets_level_valid  check (level  in ('beginner','intermediate','advanced')),
  constraint worksheets_status_valid check (status in ('queued','generating','ready','failed')),
  constraint worksheets_topic_len    check (char_length(topic) between 1 and 120)
);

-- ── 질의 5개 ────────────────────────────────────────────────────────────
-- 복습 스케줄이 이 행을 참조하므로 content jsonb 에 묻지 않고 테이블로 승격.
create table public.quiz_items (
  id            uuid primary key default gen_random_uuid(),
  worksheet_id  uuid not null references public.worksheets(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  idx           int  not null,
  kind          text not null,
  question      text not null,
  choices       jsonb,
  answer        text not null,
  explanation   text not null,
  difficulty    int,
  unique (worksheet_id, idx),
  constraint quiz_items_idx_range   check (idx between 0 and 4),
  constraint quiz_items_kind_valid  check (kind in ('short_answer','multiple_choice','explain')),
  constraint quiz_items_choices_req check (kind <> 'multiple_choice' or choices is not null)
);

-- ── 사전학습 제안 3개 ────────────────────────────────────────────────────
create table public.prerequisite_suggestions (
  id                   uuid primary key default gen_random_uuid(),
  worksheet_id         uuid not null references public.worksheets(id) on delete cascade,
  user_id              uuid not null references public.profiles(id) on delete cascade,
  idx                  int  not null,
  title                text not null,
  why                  text not null,
  one_liner            text,
  spawned_worksheet_id uuid references public.worksheets(id) on delete set null,
  unique (worksheet_id, idx),
  constraint prereq_idx_range check (idx between 0 and 2)
);

-- ── 필기 ────────────────────────────────────────────────────────────────
-- 스트로크 본문은 Storage 에 gzip JSON 으로 둔다. 여기엔 메타만.
create table public.annotations (
  worksheet_id      uuid primary key references public.worksheets(id) on delete cascade,
  user_id           uuid not null references public.profiles(id) on delete cascade,
  format_version    int  not null default 1,
  strokes_path      text,
  stroke_count      int  not null default 0,
  bytes             int  not null default 0,
  rev               bigint not null default 0,   -- 낙관적 잠금
  updated_by_device text,
  updated_at        timestamptz not null default now()
);

-- ── 복습 스케줄 ─────────────────────────────────────────────────────────
create table public.review_schedules (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  worksheet_id  uuid not null references public.worksheets(id) on delete cascade,
  quiz_item_id  uuid not null references public.quiz_items(id) on delete cascade,
  repetition    int  not null default 0,
  interval_days int  not null,
  ease          numeric(4,2) not null default 2.50,
  due_at        timestamptz not null,
  state         text not null default 'pending',
  grade         int,
  answered_at   timestamptz,
  notified_at   timestamptz,
  created_at    timestamptz not null default now(),
  constraint review_state_valid check (state in ('pending','done','skipped','retired')),
  constraint review_grade_range check (grade is null or grade between 0 and 3),
  constraint review_ease_range  check (ease between 1.30 and 2.80)
);

-- ── 생성 잡 ─────────────────────────────────────────────────────────────
create table public.generation_jobs (
  id             uuid primary key default gen_random_uuid(),
  worksheet_id   uuid not null references public.worksheets(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  attempt        int  not null default 1,
  stage          text not null default 'plan',
  status         text not null default 'running',
  error_code     text,
  error_detail   text,
  plan_tokens_in    int not null default 0,
  plan_tokens_out   int not null default 0,
  draft_tokens_in   int not null default 0,
  draft_tokens_out  int not null default 0,
  cache_read_tokens int not null default 0,
  cost_usd       numeric(10,6),
  started_at     timestamptz not null default now(),
  finished_at    timestamptz,
  duration_ms    int,
  constraint jobs_stage_valid  check (stage  in ('plan','draft','render','done')),
  constraint jobs_status_valid check (status in ('running','succeeded','failed'))
);

-- ── 결제 원장 ───────────────────────────────────────────────────────────
create table public.purchases (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.profiles(id) on delete cascade,
  platform                text not null,
  product_id              text not null references public.products(id),
  transaction_id          text not null,
  original_transaction_id text,
  quantity_granted        int  not null,
  price_krw               int,
  state                   text not null default 'granted',
  raw_receipt             jsonb,
  purchased_at            timestamptz,
  refunded_at             timestamptz,
  created_at              timestamptz not null default now(),
  -- 중복 지급을 막는 핵심 제약. 재시도가 몇 번 들어와도 지급은 정확히 한 번.
  unique (platform, transaction_id),
  constraint purchases_platform_valid check (platform in ('ios','android')),
  constraint purchases_state_valid    check (state in ('granted','refunded','revoked'))
);
