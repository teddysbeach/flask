-- 끊긴 생성 정리 테스트.
--
-- 지키는 것은 두 가지다.
--   1. 매달린 생성이 **영원히 새 생성을 막지 않는다** (돈 낸 사람이 앱을 못 쓰게 되는 사고)
--   2. 환불은 정확히 **한 번**이다 (청소기와 파이프라인이 각자 환불하면 공짜 장수가 생긴다)
\set ON_ERROR_STOP on

do $$
declare
  u uuid;
  w1 uuid; w2 uuid; w3 uuid;
  n int;
  used int;
  ok boolean;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'stale@onpar.test')
  returning id into u;
  update public.profiles set quota_total = 10 where id = u;

  -- ── fail_generation : 닫고 한 번만 환불한다 ────────────────────────────
  perform public.consume_quota(u);
  insert into public.worksheets (user_id, topic, status) values (u, '미분', 'generating')
  returning id into w1;

  select quota_used into used from public.profiles where id = u;
  assert used = 1, format('차감 후 quota_used 가 1이 아니라 %s', used);

  ok := public.fail_generation(w1, 'llm_upstream_error');
  assert ok = true, '첫 호출이 환불하지 않았다';
  select quota_used into used from public.profiles where id = u;
  assert used = 0, format('환불 후 quota_used 가 0이 아니라 %s', used);
  raise notice 'PASS fail_generation: 실패를 닫고 장수를 되돌린다';

  -- 같은 건을 또 닫으려 하면 아무 일도 없어야 한다.
  -- 이게 무너지면 실패 한 번에 장수가 두 장 생긴다 — 공짜 학습지다.
  ok := public.fail_generation(w1, 'llm_upstream_error');
  assert ok = false, '이미 닫힌 건이 두 번째로 환불됐다';
  select quota_used into used from public.profiles where id = u;
  assert used = 0, format('두 번째 호출 뒤 quota_used 가 %s 로 바뀌었다', used);
  raise notice 'PASS fail_generation: 두 번 불러도 환불은 한 번';

  -- 이미 완성된 학습지는 실패로 뒤집히지 않는다.
  insert into public.worksheets (user_id, topic, status) values (u, '완성본', 'ready')
  returning id into w2;
  ok := public.fail_generation(w2, 'llm_upstream_error');
  assert ok = false, '완성된 학습지를 실패로 바꿨다';
  select status into ok from (select status = 'ready' as status from public.worksheets where id = w2) s;
  assert ok, '완성된 학습지의 상태가 바뀌었다';
  raise notice 'PASS fail_generation: 완성본은 건드리지 않는다';

  -- ── reap_stale_generations : 오래 매달린 것만 ──────────────────────────
  perform public.consume_quota(u);
  insert into public.worksheets (user_id, topic, status, created_at)
  values (u, '오래 매달린 생성', 'generating', now() - interval '30 minutes')
  returning id into w3;

  select quota_used into used from public.profiles where id = u;
  assert used = 1, format('차감 후 quota_used 가 1이 아니라 %s', used);

  -- 방금 시작한 생성은 정리 대상이 아니다. 정상 생성을 죽이면 그게 더 큰 사고다.
  insert into public.worksheets (user_id, topic, status) values (u, '방금 시작', 'queued');

  n := public.reap_stale_generations(u);
  assert n = 1, format('정리된 건수가 1이 아니라 %s (방금 시작한 것까지 죽였을 수 있다)', n);
  select quota_used into used from public.profiles where id = u;
  assert used = 0, format('정리 후 quota_used 가 0이 아니라 %s', used);

  select count(*) into n from public.worksheets
   where id = w3 and status = 'failed' and error_code = 'generation_stalled';
  assert n = 1, '매달린 생성이 failed/generation_stalled 로 안 바뀌었다';

  select count(*) into n from public.worksheets where user_id = u and status = 'queued';
  assert n = 1, '방금 시작한 생성까지 정리됐다';
  raise notice 'PASS reap_stale_generations: 오래된 것만 정리하고 환불한다';

  -- 두 번 돌려도 더 환불하지 않는다.
  n := public.reap_stale_generations(u);
  assert n = 0, format('두 번째 정리에서 %s건이 또 잡혔다', n);
  select quota_used into used from public.profiles where id = u;
  assert used = 0, format('두 번째 정리 뒤 quota_used 가 %s', used);
  raise notice 'PASS reap_stale_generations: 두 번 돌려도 환불은 한 번';

  -- 청소기가 먼저 치운 건을 파이프라인이 뒤늦게 닫아도 환불이 겹치지 않는다.
  ok := public.fail_generation(w3, 'llm_upstream_error');
  assert ok = false, '청소기가 치운 건을 파이프라인이 또 환불했다';
  select quota_used into used from public.profiles where id = u;
  assert used = 0, format('겹친 환불로 quota_used 가 %s 가 됐다', used);
  raise notice 'PASS 청소기와 파이프라인이 겹쳐도 환불은 한 번';

  -- ── 막힌 생성을 보는 눈 ────────────────────────────────────────────────
  insert into public.worksheets (user_id, topic, status, created_at)
  values (u, '또 매달린 것', 'generating', now() - interval '2 hours');
  select count(*) into n from public.stalled_generations where user_id = u;
  assert n = 1, format('stalled_generations 에 %s건 보인다 (1건이어야 함)', n);
  raise notice 'PASS stalled_generations 뷰';

  -- ── 운영용 일괄 정리 ───────────────────────────────────────────────────
  n := public.reap_all_stale_generations();
  assert n >= 1, format('일괄 정리가 %s건만 잡았다', n);
  select count(*) into n from public.stalled_generations;
  assert n = 0, format('일괄 정리 뒤에도 %s건이 남았다', n);
  raise notice 'PASS reap_all_stale_generations';
end $$;

-- ── 권한: 사용자는 못 부른다 ───────────────────────────────────────────────
-- 부를 수 있으면 아무나 남의 생성을 죽이고 남의 장수를 움직인다.
set role authenticated;
do $$
begin
  begin
    perform public.fail_generation(gen_random_uuid(), 'x');
    assert false, 'authenticated 가 fail_generation 을 불렀다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: authenticated 는 fail_generation 을 못 부른다';
  end;

  begin
    perform public.reap_stale_generations(gen_random_uuid());
    assert false, 'authenticated 가 reap_stale_generations 를 불렀다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: authenticated 는 청소기를 못 부른다';
  end;
end $$;
reset role;

do $$ begin raise notice '── 생성 수명주기 테스트 전부 통과 ──'; end $$;
