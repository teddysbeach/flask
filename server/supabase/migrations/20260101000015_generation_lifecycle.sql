-- 생성이 끊긴 자리를 치운다.
--
-- 사고 시나리오: 생성은 응답을 보낸 뒤 EdgeRuntime.waitUntil 안에서 돈다.
-- 배포·인스턴스 회수·wall clock 초과로 그 백그라운드가 죽으면 학습지 행은
-- 'generating' 인 채로 남는다. 그러면 두 가지가 동시에 벌어진다.
--
--   1. 차감한 장수가 환불되지 않는다 (환불하는 코드가 죽었으니까)
--   2. "진행 중인 생성은 하나만" 가드가 그 행을 보고 **영원히** 429 를 돌려준다
--
-- 돈을 낸 사람이 다시는 학습지를 못 만드는 상태가 되고, 앱을 지웠다 깔아도 안 풀린다.
--
-- ── 환불은 정확히 한 번 ────────────────────────────────────────────────────
-- 파이프라인의 실패 처리와 아래 청소기가 같은 행을 각자 환불하면 공짜 장수가 생긴다.
-- 그래서 두 함수 모두 **상태 전이에 성공한 경우에만** 환불한다.
-- `update ... where status in ('queued','generating')` 가 그 자물쇠다 —
-- 경쟁이 나면 한쪽만 행을 바꾸고, 진 쪽은 환불하지 않는다.

-- 생성 하나를 실패로 닫고 장수를 되돌린다. 이미 끝난 건이면 아무것도 하지 않는다.
create or replace function public.fail_generation(p_worksheet uuid, p_code text)
returns boolean            -- 이번 호출이 실제로 닫고 환불했는가
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid;
begin
  update public.worksheets
     set status = 'failed', error_code = p_code
   where id = p_worksheet
     and status in ('queued', 'generating')
  returning user_id into v_user;

  if v_user is null then
    return false;          -- 남이 이미 닫았다. 두 번 환불하지 않는다.
  end if;

  update public.profiles
     set quota_used = greatest(quota_used - 1, 0)
   where id = v_user;

  return true;
end;
$$;

-- 오래 매달려 있는 생성을 정리한다. 새 생성을 받기 직전에 부른다.
-- 기본 10분: 정상 생성은 40~120초고, 재작성 2회 + 재시도까지 가도 그 안이다.
create or replace function public.reap_stale_generations(
  p_user    uuid,
  p_timeout interval default interval '10 minutes'
)
returns int                -- 정리하고 환불한 건수
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  with stale as (
    update public.worksheets
       set status = 'failed', error_code = 'generation_stalled'
     where user_id = p_user
       and status in ('queued', 'generating')
       and created_at < now() - p_timeout
    returning id
  )
  select count(*) into v_n from stale;

  if v_n > 0 then
    update public.profiles
       set quota_used = greatest(quota_used - v_n, 0)
     where id = p_user;
  end if;

  return v_n;
end;
$$;

-- 운영용: 사용자를 가리지 않고 한 번에 치운다. 사람이 손으로 부르는 자리다.
create or replace function public.reap_all_stale_generations(
  p_timeout interval default interval '10 minutes'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid; v_total int := 0;
begin
  for v_user in
    select distinct user_id from public.worksheets
     where status in ('queued', 'generating')
       and created_at < now() - p_timeout
  loop
    v_total := v_total + public.reap_stale_generations(v_user, p_timeout);
  end loop;
  return v_total;
end;
$$;

revoke execute on function
  public.fail_generation(uuid, text),
  public.reap_stale_generations(uuid, interval),
  public.reap_all_stale_generations(interval)
from public, anon, authenticated;

grant execute on function
  public.fail_generation(uuid, text),
  public.reap_stale_generations(uuid, interval),
  public.reap_all_stale_generations(interval)
to service_role;

-- 막힌 생성을 보는 눈. 런북이 "막힌 생성" 을 확인하라고 하는데 볼 곳이 없었다.
create or replace view public.stalled_generations as
select id, user_id, topic, status, created_at,
       now() - created_at as stuck_for
  from public.worksheets
 where status in ('queued', 'generating')
   and created_at < now() - interval '10 minutes'
 order by created_at;

revoke all on public.stalled_generations from public, anon, authenticated;
