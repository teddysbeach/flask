-- 주인 없는 파일과 무료 장수 남용.
--
-- 둘 다 "조용히 새는" 종류다. 화면에는 아무 이상이 없고, 몇 달 뒤에 비용 청구서와
-- 쿼터 통계에서만 보인다.

-- ── ① 고아 파일 ─────────────────────────────────────────────────────────
--
-- 학습지 생성이 실패하거나 중간에 끊기면 Storage 에 파일만 남는다. 삭제 경로는
-- delete-worksheet 이 막았지만, 그 이전에 생긴 것과 앞으로 생길 사고는 여기서 본다.
-- **지우지 않고 보여만 준다** — 자동 삭제는 한 번 잘못 돌면 사용자 필기를 지운다.
create or replace view public.storage_orphans as
  select
    'worksheets'::text as bucket,
    o.name             as path,
    o.created_at,
    o.metadata->>'size' as size
  from storage.objects o
  where o.bucket_id = 'worksheets'
    and not exists (select 1 from public.worksheets w where w.html_path = o.name)
union all
  select
    'annotations'::text,
    o.name,
    o.created_at,
    o.metadata->>'size'
  from storage.objects o
  where o.bucket_id = 'annotations'
    and not exists (select 1 from public.annotations a where a.strokes_path = o.name);

grant select on public.storage_orphans to service_role;

-- ── ② 무료 장수 남용 ────────────────────────────────────────────────────
--
-- 가입하면 무료 2장을 준다. 계정을 새로 만들면 또 2장이라, 지금은 상한이 없다.
-- 기기 지문은 못 믿고 만들어서도 안 되므로, **하루에 만들 수 있는 장수**에 상한을 둔다.
-- 남용의 비용은 결국 생성 요청(우리가 모델에 내는 돈)이라, 거기에 상한을 두는 것이 맞다.
--
-- 유료 사용자에게도 걸리지만 상한이 넉넉해서 정상 사용은 닿지 않는다.
-- 실제로 닿는 사람은 하루에 30장을 만드는 사람뿐이고, 그건 학습이 아니다.
create or replace function public.daily_generation_count(p_user uuid)
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
  from public.worksheets
  where user_id = p_user
    and created_at > now() - interval '24 hours'
    -- 실패한 것은 안 센다. 우리 잘못으로 실패한 생성이 사용자의 상한을 깎으면 안 된다.
    and status <> 'failed'
$$;

revoke all on function public.daily_generation_count(uuid) from public, anon, authenticated;
grant execute on function public.daily_generation_count(uuid) to service_role;
