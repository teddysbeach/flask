-- 운영 도구.
--
-- 런북(17-release-ops.md)은 "생성 실패율 10% 를 보라", "장수 오차는 대사 후 수동 지급하라" 고
-- 적어 두었는데, 정작 그걸 볼 쿼리도 지급할 함수도 없었다.
-- 사고가 났을 때 만들기 시작하면 늦다.

-- ── 0. 수동 지급 장부 ────────────────────────────────────────────────────
-- 사람이 손으로 장수를 넣는 순간이 있다(결제는 됐는데 지급이 안 된 건, 사과 지급 등).
-- 장부 없이 profiles.quota_total 만 올리면 나중에 대사할 때 그 차이를 설명할 수 없고,
-- "누가 왜 줬는지" 도 남지 않는다. 지급과 기록을 한 함수로 묶는 이유다.
create table if not exists public.manual_grants (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  sheets     int  not null,
  memo       text not null,
  granted_by text not null,
  created_at timestamptz not null default now(),
  constraint manual_grants_sheets_range check (sheets between -100 and 100 and sheets <> 0),
  constraint manual_grants_memo_len    check (char_length(memo) between 3 and 500)
);

create index if not exists manual_grants_user_idx on public.manual_grants (user_id, created_at desc);

alter table public.manual_grants enable row level security;
-- 정책을 하나도 두지 않는다 = 서비스 롤 말고는 아무도 못 읽고 못 쓴다.
revoke all on public.manual_grants from public, anon, authenticated;

-- 장수를 손으로 넣고 장부에 남긴다. 둘은 한 트랜잭션이어야 한다 —
-- 지급만 되고 기록이 빠지면 그 장수는 영원히 설명되지 않는 숫자가 된다.
create or replace function public.grant_quota_manual(
  p_user   uuid,
  p_sheets int,
  p_memo   text,
  p_by     text default 'ops'
)
returns table (grant_id uuid, new_quota_total int)   -- 이름을 컬럼과 다르게 둔다(모호성 방지)
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_total int;
begin
  insert into public.manual_grants (user_id, sheets, memo, granted_by)
  values (p_user, p_sheets, p_memo, p_by)
  returning id into v_id;

  update public.profiles p
     set quota_total = greatest(p.quota_total + p_sheets, p.quota_used)
   where p.id = p_user
  returning p.quota_total into v_total;

  if v_total is null then
    raise exception '없는 사용자에게 지급하려 했습니다: %', p_user;
  end if;

  return query select v_id, v_total;
end;
$$;

revoke execute on function public.grant_quota_manual(uuid, int, text, text)
from public, anon, authenticated;
grant execute on function public.grant_quota_manual(uuid, int, text, text) to service_role;

-- ── 1. 일일 건강 상태 ────────────────────────────────────────────────────
-- 런북의 임계값(실패율 10%, p95 150초, 장당 원가 350원)을 한 줄에서 본다.
create or replace view public.daily_generation_health as
with jobs as (
  select date_trunc('day', finished_at) as day, status, cost_usd, worksheet_id
    from public.generation_jobs
   where finished_at is not null
)
select
  j.day,
  count(*)                                                      as attempts,
  count(*) filter (where status = 'succeeded')                  as succeeded,
  count(*) filter (where status = 'failed')                     as failed,
  round(100.0 * count(*) filter (where status = 'failed') / nullif(count(*), 0), 1)
                                                                as fail_pct,
  round(sum(cost_usd)::numeric, 2)                              as spent_usd,
  round(avg(cost_usd)::numeric, 4)                              as avg_cost_usd,
  round(max(cost_usd)::numeric, 4)                              as max_cost_usd
from jobs j
group by j.day
order by j.day desc;

-- 실패 사유별. "실패율이 올랐다" 다음에 반드시 따라오는 질문이다.
create or replace view public.failure_breakdown as
select date_trunc('day', finished_at) as day,
       error_code,
       count(*) as n
  from public.generation_jobs
 where status = 'failed' and finished_at is not null
 group by 1, 2
 order by 1 desc, 3 desc;

-- ── 2. 프롬프트별 품질 ───────────────────────────────────────────────────
-- prompt_version 을 채우기 시작했으니, 품질이 떨어졌을 때 어느 프롬프트인지 물을 수 있다.
create or replace view public.quality_by_prompt as
select w.prompt_version,
       count(*)                          as worksheets,
       round(avg(w.quality_score))       as avg_score,
       round(avg(w.revisions), 2)        as avg_revisions,
       min(w.ready_at)                   as first_seen,
       max(w.ready_at)                   as last_seen
  from public.worksheets w
 where w.status = 'ready' and w.prompt_version is not null
 group by w.prompt_version
 order by max(w.ready_at) desc;

-- ── 3. 장수 대사 ─────────────────────────────────────────────────────────
-- "결제한 만큼 받았는가" 를 한눈에. 어긋난 행만 나온다.
create or replace view public.quota_reconciliation as
select p.id                                          as user_id,
       p.quota_total,
       p.quota_used,
       2                                             as free_grant,
       coalesce(sum(pr.sheets), 0)                   as purchased,
       coalesce(sum(gm.sheets), 0)                   as granted_manually,
       p.quota_total - 2 - coalesce(sum(pr.sheets), 0) - coalesce(sum(gm.sheets), 0)
                                                     as unexplained
  from public.profiles p
  left join (
    select pu.user_id, pd.sheets
      from public.purchases pu
      join public.products pd on pd.id = pu.product_id
     where pu.user_id is not null
  ) pr on pr.user_id = p.id
  left join public.manual_grants gm on gm.user_id = p.id
 group by p.id, p.quota_total, p.quota_used
having p.quota_total - 2 - coalesce(sum(pr.sheets), 0) - coalesce(sum(gm.sheets), 0) <> 0;

revoke all on
  public.daily_generation_health,
  public.failure_breakdown,
  public.quality_by_prompt,
  public.quota_reconciliation
from public, anon, authenticated;
