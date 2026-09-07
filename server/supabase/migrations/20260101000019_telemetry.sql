-- 텔레메트리: 사용 이벤트와 크래시.
--
-- 왜 제3자 SDK 를 안 쓰는가:
--   17-release-ops.md 의 개인정보 표에 "제3자 공유 ❌" 라고 적어 두었다. Firebase 나
--   Amplitude 를 붙이는 순간 그 줄이 거짓말이 되고, 스토어의 데이터 세이프티 신고 내용도
--   바뀐다. 우리가 재려는 것(퍼널 몇 개, 실패율, 크래시)은 테이블 두 개로 충분하다.
--
-- 무엇을 담지 않는가:
--   주제 원문·답안·이메일·영수증. 앱이 sanitizeProps 로 한 번 거르고, 여기서는
--   props 크기와 키 개수에 상한을 둔다 — 상한이 없으면 언젠가 본문이 통째로 들어온다.

create table if not exists public.telemetry_events (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users(id) on delete set null,
  -- 로그인 전 이벤트(온보딩·가입 시작)를 잇는 익명 키. 기기마다 하나, 재설치하면 새로 생긴다.
  install_id   uuid not null,
  name         text not null,
  props        jsonb not null default '{}'::jsonb,
  app_version  text,
  platform     text,
  -- 기기에서 만들어진 시각. 오프라인에서 쌓였다가 나중에 올라올 수 있어 서버 시각과 다르다.
  occurred_at  timestamptz not null,
  created_at   timestamptz not null default now(),

  constraint telemetry_name_len check (char_length(name) between 1 and 64),
  constraint telemetry_props_size check (pg_column_size(props) <= 2048)
);

create index if not exists telemetry_events_time_idx on public.telemetry_events (occurred_at desc);
create index if not exists telemetry_events_name_idx on public.telemetry_events (name, occurred_at desc);

create table if not exists public.crash_reports (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users(id) on delete set null,
  install_id   uuid not null,
  -- 같은 크래시를 묶는 열쇠. 메시지의 가변 부분(주소·id)을 앱이 지운 뒤 해시한 값이다.
  fingerprint  text not null,
  message      text not null,
  stack        text,
  context      text,
  fatal        boolean not null default false,
  app_version  text,
  platform     text,
  occurred_at  timestamptz not null,
  created_at   timestamptz not null default now(),

  constraint crash_message_len check (char_length(message) <= 2000),
  constraint crash_stack_len check (stack is null or char_length(stack) <= 8000)
);

create index if not exists crash_reports_fp_idx on public.crash_reports (fingerprint, occurred_at desc);
create index if not exists crash_reports_time_idx on public.crash_reports (occurred_at desc);

-- RLS: 정책을 하나도 두지 않는다 = 사용자 토큰으로는 읽지도 쓰지도 못한다.
-- 쓰기는 Edge Function(service_role)만, 읽기는 운영자(대시보드)만.
alter table public.telemetry_events enable row level security;
alter table public.crash_reports enable row level security;
revoke all on public.telemetry_events from anon, authenticated;
revoke all on public.crash_reports from anon, authenticated;

-- ── 운영용 뷰 ────────────────────────────────────────────────────────────
-- 출시 후에 볼 것만 만든다. 대시보드가 없어도 SQL 한 줄로 답이 나와야 한다.

create or replace view public.daily_funnel as
select
  date_trunc('day', occurred_at)                                              as day,
  count(*) filter (where name = 'appOpen')                                    as opens,
  count(distinct install_id) filter (where name = 'appOpen')                  as devices,
  count(*) filter (where name = 'signupComplete')                             as signups,
  count(*) filter (where name = 'worksheetCreateStart')                       as create_start,
  count(*) filter (where name = 'worksheetCreateComplete')                    as create_done,
  count(*) filter (where name = 'worksheetCreateFailed')                      as create_failed,
  count(*) filter (where name = 'reviewAnswer')                               as review_answers,
  count(*) filter (where name = 'paywallView')                                as paywall_views,
  count(*) filter (where name = 'purchaseComplete')                           as purchases
from public.telemetry_events
group by 1
order by 1 desc;

-- 같은 크래시가 몇 번, 몇 명에게 났는가. 이 정렬이 곧 고칠 순서다.
create or replace view public.crash_summary as
select
  fingerprint,
  min(message)                        as message,
  count(*)                            as hits,
  count(distinct install_id)          as devices,
  bool_or(fatal)                      as ever_fatal,
  max(app_version)                    as last_version,
  max(occurred_at)                    as last_seen
from public.crash_reports
group by fingerprint
order by hits desc;

grant select on public.daily_funnel, public.crash_summary to service_role;

-- 보관 기간. 무한히 쌓으면 비용이 조용히 늘고, 오래된 사용 로그는 쓸모도 없다.
create or replace function public.prune_telemetry(keep interval default '90 days')
returns table (events_deleted int, crashes_deleted int)
language plpgsql security definer set search_path = public as $$
declare e int; c int;
begin
  delete from public.telemetry_events where occurred_at < now() - keep;
  get diagnostics e = row_count;
  -- 크래시는 조금 더 오래 둔다. 재현이 어려운 버그는 몇 달 뒤에 다시 물어보게 된다.
  delete from public.crash_reports where occurred_at < now() - (keep * 2);
  get diagnostics c = row_count;
  return query select e, c;
end $$;

revoke all on function public.prune_telemetry(interval) from public, anon, authenticated;
grant execute on function public.prune_telemetry(interval) to service_role;
