-- 운영 도구 테스트.
--
-- 런북이 시키는 두 가지가 실제로 되는지만 본다.
--   1. "실패율을 보라" — 볼 수 있는가
--   2. "대사 후 수동 지급하라" — 지급하면 장부에 남고, 대사에서 설명되는가
\set ON_ERROR_STOP on

do $$
declare
  u uuid; w uuid; g record; n int; total int; unexplained int;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'ops@onpar.test') returning id into u;

  -- 잡 기록 몇 건 (성공 2 · 실패 1)
  insert into public.worksheets (id, user_id, topic, status) values
    (gen_random_uuid(), u, '성공1', 'ready') returning id into w;
  insert into public.generation_jobs (worksheet_id, user_id, attempt, stage, status, cost_usd, finished_at)
  values (w, u, 1, 'done', 'succeeded', 0.11, now());
  insert into public.worksheets (id, user_id, topic, status) values (gen_random_uuid(), u, '성공2', 'ready') returning id into w;
  insert into public.generation_jobs (worksheet_id, user_id, attempt, stage, status, cost_usd, finished_at)
  values (w, u, 1, 'done', 'succeeded', 0.13, now());
  insert into public.worksheets (id, user_id, topic, status, error_code) values (gen_random_uuid(), u, '실패1', 'failed', 'llm_refused') returning id into w;
  insert into public.generation_jobs (worksheet_id, user_id, attempt, stage, status, cost_usd, error_code, finished_at)
  values (w, u, 1, 'plan', 'failed', 0.02, 'llm_refused', now());

  select h.failed, h.attempts into n, total
    from public.daily_generation_health h where h.day = date_trunc('day', now());
  assert n = 1,     format('실패 건수가 1이 아니라 %s', n);
  assert total = 3, format('시도 건수가 3이 아니라 %s', total);
  raise notice 'PASS 일일 건강 상태: 실패 %/% 건이 보인다', n, total;

  select count(*) into n from public.failure_breakdown where error_code = 'llm_refused';
  assert n = 1, '실패 사유별 집계가 비어 있다';
  raise notice 'PASS 실패 사유별 집계';

  -- ── 프롬프트별 품질 ────────────────────────────────────────────────────
  update public.worksheets set prompt_version = 'abc12345', quality_score = 88, revisions = 1
   where user_id = u and status = 'ready';
  select q.worksheets into n from public.quality_by_prompt q where q.prompt_version = 'abc12345';
  assert n = 2, format('프롬프트 지문별 집계가 %s건 (2건이어야 함)', n);
  raise notice 'PASS 프롬프트별 품질';

  -- ── 수동 지급 ──────────────────────────────────────────────────────────
  select * into g from public.grant_quota_manual(u, 3, '결제는 됐는데 지급이 안 된 건 (문의 #12)', 'ops:kim');
  assert g.new_quota_total = 5, format('무료 2 + 수동 3 = 5 여야 하는데 %s', g.new_quota_total);

  select count(*) into n from public.manual_grants where user_id = u and sheets = 3;
  assert n = 1, '지급은 됐는데 장부에 안 남았다';
  raise notice 'PASS 수동 지급: 장수가 늘고 장부에 남는다';

  -- 대사: 수동 지급분이 '설명되지 않는 숫자' 로 남으면 안 된다.
  select count(*) into n from public.quota_reconciliation r where r.user_id = u;
  assert n = 0, '장부에 남긴 수동 지급이 대사에서 미설명으로 잡힌다';
  raise notice 'PASS 대사: 장부에 남긴 지급은 설명된다';

  -- 반대로 장부 없이 직접 올리면 대사에 걸려야 한다. 그게 이 뷰의 목적이다.
  update public.profiles set quota_total = quota_total + 7 where id = u;
  select r.unexplained into unexplained from public.quota_reconciliation r where r.user_id = u;
  assert unexplained = 7, format('설명되지 않는 장수가 7이 아니라 %s', unexplained);
  raise notice 'PASS 대사: 장부 없는 지급은 잡아낸다';

  -- 메모 없는 지급은 막는다. 3개월 뒤의 나를 위한 방어다.
  begin
    perform public.grant_quota_manual(u, 1, 'x');
    assert false, '메모 3자 미만인데 지급됐다';
  exception when check_violation then
    raise notice 'PASS 메모 없는 지급은 거부한다';
  end;

  -- 없는 사용자
  begin
    perform public.grant_quota_manual(gen_random_uuid(), 1, '없는 사용자 테스트');
    assert false, '없는 사용자에게 지급됐다';
  exception when others then
    raise notice 'PASS 없는 사용자에게는 지급하지 않는다';
  end;
end $$;

-- 권한: 사용자는 장부도 뷰도 못 본다. 남의 사용량이 보이면 그 자체가 사고다.
set role authenticated;
do $$
begin
  begin
    perform count(*) from public.manual_grants;
    assert false, 'authenticated 가 수동 지급 장부를 읽었다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 사용자는 장부를 못 읽는다';
  end;

  begin
    perform count(*) from public.daily_generation_health;
    assert false, 'authenticated 가 운영 지표를 읽었다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 사용자는 운영 지표를 못 읽는다';
  end;

  begin
    perform public.grant_quota_manual(gen_random_uuid(), 100, '내 장수 늘리기');
    assert false, 'authenticated 가 스스로 장수를 지급했다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 사용자는 스스로 지급할 수 없다';
  end;
end $$;
reset role;

do $$ begin raise notice '── 운영 도구 테스트 전부 통과 ──'; end $$;
