-- 생성이 어디까지 갔는지 **서버가 말한다.** 그리고 매달린 생성은 스스로 닫힌다.
--
-- ── 무엇이 잘못돼 있었나 ────────────────────────────────────────────────────
--
-- 진행 화면은 서버에 아무것도 묻지 않고 **경과 시간만 보고** 단계를 지어냈다.
-- 18초가 지나면 "학습지를 쓰고 있어요", 70초가 지나면 "품질을 검사하고 있어요".
-- 그래서 13분이 지나도 화면은 여전히 "품질을 검사하고 있어요" 라고 말한다 —
-- 서버는 이미 죽었는데. 사용자가 잃는 것은 시간이 아니라 **다음에 이 앱이 하는 말을
-- 믿을 이유**다.
--
-- 더 나쁜 것은 그게 거짓말인 채로 영원히 남는다는 점이었다. 생성은 응답을 보낸 뒤
-- EdgeRuntime.waitUntil 안에서 도는데, 그 백그라운드가 죽으면(배포·인스턴스 회수·
-- wall clock 초과) 아무도 그 행을 닫아 주지 않는다. 청소기(reap_stale_generations)는
-- **같은 사용자가 새 생성을 요청할 때만** 돈다. 요청하지 않으면 영원히 'generating' 이다.
-- 홈의 "만드는 중" 카드도 영원히 돈다.
--
-- ── 두 가지를 넣는다 ────────────────────────────────────────────────────────
--
--   1. stage — 파이프라인이 실제로 밟고 있는 단계. 이미 코드 안에 있던 값인데
--      끝날 때 기록(generation_jobs)에만 남기고 진행 중에는 아무 데도 안 썼다.
--      진실이 있는데 발행을 안 하고 있었던 것이다.
--
--   2. worksheet_status() — 상태를 **읽는 행위가 곧 고치는 행위**가 된다.
--      앱은 이미 3초마다 이 행을 보고 있다. 그때 시간이 지난 건이면 그 자리에서
--      닫고 환불한다. 별도의 스케줄러(pg_cron)를 켜지 않고도 매달린 생성이
--      한 번의 폴링 안에 풀린다.

-- ── 1. 단계 ────────────────────────────────────────────────────────────────

alter table public.worksheets
  add column if not exists stage    text,
  add column if not exists stage_at timestamptz;

-- 파이프라인(_shared/pipeline.ts)의 단계 이름과 같아야 한다.
-- 앱의 STAGE 표기와 어긋나면 화면이 빈칸이 되므로 제약으로 못 박는다.
alter table public.worksheets
  drop constraint if exists worksheets_stage_valid;
alter table public.worksheets
  add constraint worksheets_stage_valid
  check (stage is null or stage in ('plan','draft','critic','revise','render','save'));

comment on column public.worksheets.stage is
  '생성 파이프라인이 지금 밟고 있는 단계. 진행 화면이 지어내지 않고 이걸 읽는다.';
comment on column public.worksheets.stage_at is
  '그 단계에 들어간 시각. "이 단계에서 멈춰 있다" 를 말할 수 있는 유일한 근거다.';

-- 단계를 적는다. 끝난 건(ready/failed)에는 쓰지 않는다 —
-- 늦게 도착한 단계 보고가 이미 닫힌 학습지를 되살린 것처럼 보이면 안 된다.
create or replace function public.set_generation_stage(p_worksheet uuid, p_stage text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.worksheets
     set stage = p_stage, stage_at = now()
   where id = p_worksheet
     and status in ('queued', 'generating');
$$;

revoke execute on function public.set_generation_stage(uuid, text) from public, anon, authenticated;
grant execute on function public.set_generation_stage(uuid, text) to service_role;

-- ── 2. 읽으면서 고친다 ──────────────────────────────────────────────────────

-- 매달린 생성으로 판정하는 시간. 정상 생성은 40~120초고, 파이프라인 자신이
-- 그보다 먼저(8분) 스스로 끊는다. 여기 걸리는 것은 **파이프라인이 아예 죽은 경우**뿐이다.
create or replace function public.generation_stall_timeout()
returns interval
language sql
immutable
as $$ select interval '10 minutes' $$;

grant execute on function public.generation_stall_timeout() to authenticated, service_role;

-- 학습지 한 장의 상태. 앱의 진행 화면이 3초마다 부른다.
--
-- 보통의 select 와 다른 점은 하나다 — **시간이 지난 건이면 먼저 닫고 환불한다.**
-- 환불은 fail_generation 이 쥔 자물쇠를 그대로 쓰므로 청소기·파이프라인과 겹쳐도
-- 정확히 한 번이다.
--
-- 남의 행에는 아무 일도 하지 않는다. security definer 라 RLS 를 지나가므로
-- user_id 대조를 함수 안에서 직접 한다.
create or replace function public.worksheet_status(p_id uuid)
returns table (
  id uuid, topic text, title text, status text, error_code text,
  stage text, stage_at timestamptz, html_path text,
  created_at timestamptz, ready_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_owner uuid; v_status text; v_created timestamptz;
begin
  select w.user_id, w.status, w.created_at
    into v_owner, v_status, v_created
    from public.worksheets w where w.id = p_id;

  -- 없는 행이거나 남의 행이면 아무것도 돌려주지 않는다. 있음/없음도 알려주지 않는다.
  if v_owner is null or v_owner is distinct from auth.uid() then
    return;
  end if;

  -- 매달린 건이면 여기서 닫는다. 앱이 이 행을 보러 온 것 자체가 청소 신호다.
  if v_status in ('queued', 'generating')
     and v_created < now() - public.generation_stall_timeout() then
    perform public.fail_generation(p_id, 'generation_stalled');
  end if;

  return query
    select w.id, w.topic, w.title, w.status, w.error_code,
           w.stage, w.stage_at, w.html_path, w.created_at, w.ready_at
      from public.worksheets w
     where w.id = p_id;
end;
$$;

revoke execute on function public.worksheet_status(uuid) from public, anon;
grant execute on function public.worksheet_status(uuid) to authenticated, service_role;

-- 매달린 것을 보는 눈도 같은 기준을 쓰게 맞춘다.
--
-- 컬럼이 하나 늘어난다(stage). `create or replace view` 는 컬럼 목록이 바뀌면
-- "cannot change name of view column" 으로 거절한다 — 먼저 지우고 다시 만든다.
drop view if exists public.stalled_generations;
create view public.stalled_generations as
select id, user_id, topic, status, stage, created_at,
       now() - created_at as stuck_for,
       now() - coalesce(stage_at, created_at) as stuck_in_stage
  from public.worksheets
 where status in ('queued', 'generating')
   and created_at < now() - public.generation_stall_timeout()
 order by created_at;

revoke all on public.stalled_generations from public, anon, authenticated;
