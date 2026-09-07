-- 탈퇴와 복습 시각. 앱이 쓰기 시작하면서 필요해진 것들.

-- ── 탈퇴 사유 ────────────────────────────────────────────────────────────
-- 사람과 잇지 않는다. user_id 를 두면 "지웠다" 고 말한 것을 안 지운 셈이 된다.
-- 통계로만 쓰므로 익명 집계 테이블이다.
create table if not exists public.withdrawal_reasons (
  id         uuid primary key default gen_random_uuid(),
  reason     text not null,
  detail     text,
  created_at timestamptz not null default now(),
  constraint withdrawal_detail_len check (detail is null or char_length(detail) <= 500)
);

alter table public.withdrawal_reasons enable row level security;
-- 정책 없음 = 서비스 롤만 읽고 쓴다. 사용자는 남의 탈퇴 사유를 볼 이유가 없다.

-- ── 구매 내역 익명화 ─────────────────────────────────────────────────────
-- 법정 보존 의무가 있어 행은 남기되, 탈퇴하면 사람과 끊는다.
alter table public.purchases
  add column if not exists anonymized_at timestamptz;

-- user_id 가 null 이 될 수 있어야 익명화가 가능하다.
alter table public.purchases
  alter column user_id drop not null;

-- 참조는 유지하되 계정이 사라져도 행이 남게 한다.
do $$
begin
  alter table public.purchases drop constraint if exists purchases_user_id_fkey;
  alter table public.purchases
    add constraint purchases_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete set null;
exception when others then null;
end $$;

-- ── 복습 알림 시각 ───────────────────────────────────────────────────────
-- 앱은 야간(22~08시)에 알림을 보내지 않으므로 그 시각으로 설정되면
-- 서버가 계산한 due_at 과 실제 알림이 어긋난다. 애초에 못 넣게 막는다.
-- (앱 설정 화면도 8~21시만 고르게 되어 있다 — 두 곳에서 같은 규칙을 지킨다.)
alter table public.profiles
  drop constraint if exists profiles_review_hour_range;
update public.profiles set review_hour = 21 where review_hour < 8 or review_hour > 21;
alter table public.profiles
  add constraint profiles_review_hour_range check (review_hour between 8 and 21);
