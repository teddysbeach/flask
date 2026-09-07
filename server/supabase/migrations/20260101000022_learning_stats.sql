-- 학습 기록.
--
-- 지금 다시 오게 하는 장치가 로컬 알림 하나뿐이다. 그런데 데이터는 이미 쌓이고 있다 —
-- responses(무엇을 맞고 틀렸는지)와 review_schedules(언제 무엇을 복습했는지).
-- 쌓아만 두고 안 보여주면 사용자에게는 없는 것과 같다.
--
-- 뷰가 아니라 함수인 이유: 사용자 자신의 것만 돌려줘야 하는데, security definer 함수가
-- auth.uid() 로 잠그는 편이 뷰에 RLS 를 얹는 것보다 실수할 여지가 적다.

create or replace function public.learning_stats()
returns table (
  worksheets_total   int,   -- 만든 학습지(완성된 것만)
  quiz_answered      int,   -- 답한 문제 수
  quiz_correct       int,   -- 처음에 맞힌 문제 수
  reviews_done       int,   -- 끝낸 복습 회차
  reviews_due_today  int,   -- 오늘 남은 복습
  streak_days        int,   -- 연속 학습일(오늘 또는 어제까지 이어진 것)
  active_days        int    -- 학습한 날의 수(전체)
)
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception '로그인이 필요해요' using errcode = '28000';
  end if;

  select count(*)::int into worksheets_total
  from public.worksheets where user_id = me and status = 'ready';

  select count(*)::int, coalesce(count(*) filter (where first_correct), 0)::int
    into quiz_answered, quiz_correct
  from public.responses where user_id = me and quiz_item_id is not null;

  select count(*)::int into reviews_done
  from public.review_schedules where user_id = me and state in ('done', 'retired');

  select count(*)::int into reviews_due_today
  from public.review_schedules
  where user_id = me and state = 'pending' and due_at <= now();

  -- 학습한 날 = 무언가에 답한 날. 학습지를 만들기만 한 날은 안 센다 —
  -- 만들기만 하고 안 푼 날을 연속에 세면 그 숫자는 성실함이 아니라 결제를 세는 것이 된다.
  with days as (
    select distinct (updated_at at time zone coalesce(
      (select timezone from public.profiles where id = me), 'Asia/Seoul'))::date as d
    from public.responses where user_id = me
    union
    select distinct (answered_at at time zone coalesce(
      (select timezone from public.profiles where id = me), 'Asia/Seoul'))::date
    from public.review_schedules where user_id = me and answered_at is not null
  ),
  numbered as (
    select d, row_number() over (order by d desc) as rn from days
  )
  select
    coalesce((
      -- 오늘(또는 어제)부터 하루도 안 빠지고 이어진 날의 수.
      -- 어제까지만 이어져도 연속으로 본다 — 오늘 아직 안 했다고 어제까지의 노력을 0 으로
      -- 만들면, 하루 늦게 연 사람이 다시 시작할 마음을 잃는다.
      select count(*)::int from numbered
      where d = (select max(d) from days) - ((rn - 1) * interval '1 day')
        and (select max(d) from days) >= (now() at time zone coalesce(
              (select timezone from public.profiles where id = me), 'Asia/Seoul'))::date - 1
    ), 0),
    coalesce((select count(*)::int from days), 0)
  into streak_days, active_days;

  return next;
end $$;

revoke all on function public.learning_stats() from public, anon;
grant execute on function public.learning_stats() to authenticated;
