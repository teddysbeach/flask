-- 문의 접수.
--
-- **로그아웃 상태에서도 넣을 수 있어야 한다.** 로그인이 안 돼서 문의하는 사람이
-- 문의하려면 로그인부터 하라는 말을 듣는 화면은 만들지 않는다. 그래서 user_id 는 null 을 허용한다.
--
-- 대신 읽기는 본인 것만이다. user_id 가 null 인 행(로그아웃 문의)은 아무에게도 안 보인다 —
-- 익명으로 들어온 글을 다른 익명 사용자가 읽을 수 있으면 그건 게시판이지 문의함이 아니다.
-- 답변·상태 변경은 운영이 서비스 롤로 한다(사용자에게 update/delete 를 주지 않는다).

create table public.support_tickets (
  id          uuid primary key default gen_random_uuid(),

  -- null = 로그아웃 상태에서 들어온 문의. 계정과 이어 붙이지 않는다.
  user_id     uuid references auth.users(id) on delete set null,

  -- 문의 유형. 앱의 ContactTopic 과 같은 닫힌 목록이다 — 자유 문자열이면 분류가 무너진다.
  topic       text not null,
  body        text not null,

  -- 어느 빌드에서 났는지. 이게 없으면 "저는 안 그런데요" 로 끝난다.
  app_version text,
  platform    text,

  status      text not null default 'open',
  created_at  timestamptz not null default now(),

  constraint support_tickets_topic_known check (
    topic in ('payment', 'generation', 'annotation', 'review', 'account', 'other')),
  -- 화면의 maxLength 와 같은 값. 화면만 막으면 API 로는 얼마든지 들어온다.
  constraint support_tickets_body_len check (char_length(body) between 1 and 2000),
  constraint support_tickets_status_known check (status in ('open', 'answered', 'closed')),
  constraint support_tickets_platform_known check (
    platform is null or platform in ('ios', 'android', 'other')),
  constraint support_tickets_version_len check (
    app_version is null or char_length(app_version) <= 40)
);

comment on table public.support_tickets is
  '문의함. user_id 가 null 이면 로그아웃 상태에서 들어온 문의다. 읽기는 본인 것만, 답변은 서비스 롤.';

-- 운영이 오래된 것부터 처리하고, 접수 함수가 최근 1분 건수를 세는 경로.
create index support_tickets_user_created_idx
  on public.support_tickets (user_id, created_at desc);
create index support_tickets_open_idx
  on public.support_tickets (created_at desc) where status = 'open';

alter table public.support_tickets enable row level security;

-- 본인 것만 보인다. 익명 문의(user_id is null)는 아무에게도 안 보인다.
create policy support_tickets_select_own on public.support_tickets
  for select to authenticated using (auth.uid() = user_id);

-- 접수는 로그인 여부와 무관하다. 다만 **남의 이름으로는 못 넣는다** —
-- anon 은 auth.uid() 가 null 이라 `auth.uid() = user_id` 가 참이 될 수 없고,
-- 남는 길은 user_id 를 비우고 넣는 것뿐이다.
create policy support_tickets_insert_self_or_anon on public.support_tickets
  for insert to anon, authenticated
  with check (auth.uid() = user_id or user_id is null);

-- 상태(status)를 사용자가 바꾸면 "처리 완료" 를 스스로 눌러 문의를 덮을 수 있다.
-- update/delete 정책은 없고, 권한도 걷어낸다.
revoke update, delete on public.support_tickets from anon, authenticated;

-- 넣을 수 있는 칸도 정해 둔다. status 와 created_at 은 우리 것이다.
-- (컬럼 단위 revoke 는 테이블 단위 권한이 있으면 무시되므로 먼저 걷어내고 다시 준다.)
revoke insert on public.support_tickets from anon, authenticated;
grant  insert (user_id, topic, body, app_version, platform)
  on public.support_tickets to anon, authenticated;
grant  select on public.support_tickets to authenticated;
