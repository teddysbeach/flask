-- 매달린 생성이 **읽히는 순간** 스스로 닫히는가.
--
-- 신고: 13분째 "만드는 중" 이었다.
--
-- 원인은 청소기(reap_stale_generations)가 **같은 사용자가 새 생성을 요청할 때만** 돌았다는
-- 것이다. 요청하지 않으면 행은 영원히 'generating' 이고, 차감한 장수도 안 돌아온다.
-- 그런데 앱은 그 행을 3초마다 보고 있었다 — 보는 쪽이 고치게 하면 스케줄러 없이도 풀린다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid; other uuid; w uuid; stale uuid; fresh uuid;
  r record; n int; used int;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'prog@onpar.test') returning id into u;
  insert into auth.users (id, email) values (gen_random_uuid(), 'prog2@onpar.test') returning id into other;
  update public.profiles set quota_total = 10, quota_used = 3 where id = u;

  -- ── 단계는 진행 중인 것에만 적힌다 ──
  insert into public.worksheets (user_id, topic, status) values (u, '진행 중', 'generating')
  returning id into w;
  perform public.set_generation_stage(w, 'draft');
  select stage, stage_at into r from public.worksheets where id = w;
  assert r.stage = 'draft', '단계가 안 적혔다';
  assert r.stage_at is not null, '단계에 들어간 시각이 없다';

  update public.worksheets set status = 'ready' where id = w;
  perform public.set_generation_stage(w, 'render');
  select stage into r from public.worksheets where id = w;
  assert r.stage = 'draft', '이미 끝난 학습지에 늦게 온 단계 보고가 적혔다';
  raise notice '── 단계 기록 테스트 전부 통과 ──';
end $$;

do $$
declare
  u uuid; other uuid; stale uuid; fresh uuid; r record; used int;
begin
  select au.id into u   from auth.users au where au.email = 'prog@onpar.test';
  select au.id into other from auth.users au where au.email = 'prog2@onpar.test';

  update public.profiles set quota_total = 10, quota_used = 3 where id = u;

  -- 10분을 넘긴 매달린 건 하나, 방금 시작한 건 하나.
  insert into public.worksheets (user_id, topic, status, created_at)
  values (u, '매달린 것', 'generating', now() - interval '13 minutes') returning id into stale;
  insert into public.worksheets (user_id, topic, status, created_at)
  values (u, '방금 시작', 'generating', now() - interval '30 seconds') returning id into fresh;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', u::text, true);

  -- ── 읽는 것만으로 매달린 건이 닫힌다 ──
  select * into r from public.worksheet_status(stale);
  assert r.status = 'failed', '13분째 매달린 건이 아직 generating 이다: ' || r.status;
  assert r.error_code = 'generation_stalled', '실패 사유가 없다';

  -- ── 방금 시작한 건은 건드리지 않는다 ──
  select * into r from public.worksheet_status(fresh);
  assert r.status = 'generating', '살아 있는 생성을 죽였다';

  -- ── 남의 학습지는 보이지도, 닫히지도 않는다 ──
  perform set_config('request.jwt.claim.sub', other::text, true);
  select count(*) into used from public.worksheet_status(fresh);
  assert used = 0, '남의 학습지가 보인다';

  reset role;
  select status into r from public.worksheets where id = fresh;
  assert r.status = 'generating', '남이 읽었는데 내 생성이 닫혔다';

  -- ── 장수는 정확히 한 번 돌아온다 ──
  select quota_used into used from public.profiles where id = u;
  assert used = 2, '매달린 한 건의 환불이 한 번이 아니다 (quota_used=' || used || ')';

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform public.worksheet_status(stale);
  perform public.worksheet_status(stale);
  reset role;
  select quota_used into used from public.profiles where id = u;
  assert used = 2, '다시 읽을 때마다 장수가 늘어난다 (quota_used=' || used || ')';

  raise notice '── 매달린 생성 자가 회수 테스트 전부 통과 ──';
end $$;

-- ── 권한 ──
do $$
declare n int;
begin
  -- 단계 기록은 서버만. 사용자가 부를 수 있으면 진행 표시를 마음대로 꾸밀 수 있다.
  select count(*) into n from information_schema.role_routine_grants
   where routine_schema = 'public' and routine_name = 'set_generation_stage'
     and grantee in ('anon', 'authenticated');
  assert n = 0, 'set_generation_stage 가 사용자에게 열려 있다';

  -- 상태 조회는 로그인 사용자에게 열려 있어야 한다(앱이 이걸 폴링한다).
  select count(*) into n from information_schema.role_routine_grants
   where routine_schema = 'public' and routine_name = 'worksheet_status'
     and grantee = 'authenticated';
  assert n > 0, 'worksheet_status 를 앱이 못 부른다';

  raise notice '── 진행 조회 권한 테스트 전부 통과 ──';
end $$;
