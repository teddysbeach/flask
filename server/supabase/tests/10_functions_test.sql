-- 쿼터 · 결제 함수 동작 테스트. 실패 시 예외로 중단된다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid;
  p record;
  r record;
  ok boolean;
  n int;
begin
  -- ── 가입 트리거 ───────────────────────────────────────────────────────
  insert into auth.users (email, raw_user_meta_data)
  values ('a@onpar.test', '{"full_name":"테스터"}') returning id into u;

  select * into p from public.profiles where id = u;
  assert p.id is not null,            '가입 트리거가 profiles 를 만들지 않았다';
  assert p.quota_total = 2,           format('무료 장수가 2가 아니라 %s', p.quota_total);
  assert p.quota_used = 0,            '초기 사용량이 0이 아니다';
  assert p.display_name = '테스터',    'display_name 이 메타데이터에서 안 왔다';
  raise notice 'PASS 가입 트리거 → profiles(quota_total=2)';

  -- ── consume_quota : 2장까지만 ─────────────────────────────────────────
  assert public.consume_quota(u) = true,  '1번째 생성이 막혔다';
  assert public.consume_quota(u) = true,  '2번째 생성이 막혔다';
  assert public.consume_quota(u) = false, '무료 2장을 넘겼는데 3번째가 통과했다';
  select quota_used into n from public.profiles where id = u;
  assert n = 2, format('quota_used 가 2가 아니라 %s', n);
  raise notice 'PASS consume_quota 무료 2장 상한';

  -- ── refund_quota ──────────────────────────────────────────────────────
  perform public.refund_quota(u);
  select quota_used into n from public.profiles where id = u;
  assert n = 1, format('환불 후 quota_used 가 1이 아니라 %s', n);
  assert public.consume_quota(u) = true, '환불했는데 다시 생성이 안 된다';
  raise notice 'PASS refund_quota';

  -- ── 결제 지급 : 장수는 products 에서 온다 ──────────────────────────────
  select * into r from public.grant_quota_from_purchase(
    u, 'ios', 'onpar.sheets.10', 'txn_A', 'orig_A', 12900, '{"env":"sandbox"}'::jsonb);
  assert r.granted = 10,              format('10장 상품인데 %s장 지급됨', r.granted);
  assert r.already_processed = false, '첫 지급인데 already_processed 가 true';
  select quota_total into n from public.profiles where id = u;
  assert n = 12, format('quota_total 이 12가 아니라 %s', n);
  raise notice 'PASS 결제 지급 (장수는 products 카탈로그 기준)';

  -- ── 멱등성 : 같은 영수증 재전송 ────────────────────────────────────────
  select * into r from public.grant_quota_from_purchase(
    u, 'ios', 'onpar.sheets.10', 'txn_A', 'orig_A', 12900, '{"env":"sandbox"}'::jsonb);
  assert r.already_processed = true, '중복 영수증인데 already_processed 가 false';
  assert r.granted = 0,              format('중복인데 %s장이 또 지급됨', r.granted);
  select quota_total into n from public.profiles where id = u;
  assert n = 12, format('중복 지급으로 quota_total 이 %s 가 됨', n);
  select count(*) into n from public.purchases where transaction_id = 'txn_A';
  assert n = 1, format('purchases 행이 %s개 (1개여야 함)', n);
  raise notice 'PASS 결제 멱등성 (같은 영수증 2회 → 1회만 지급)';

  -- ── 없는 상품은 거부 ──────────────────────────────────────────────────
  begin
    perform public.grant_quota_from_purchase(
      u, 'ios', 'onpar.sheets.9999', 'txn_B', null, 999, '{}'::jsonb);
    assert false, '존재하지 않는 상품인데 지급됨';
  exception when check_violation then
    raise notice 'PASS 미등록 상품 거부';
  end;

  -- ── 환불 회수 : 이미 쓴 장수는 회수하지 않는다 ─────────────────────────
  -- 현재 quota_total=12, quota_used=2. 10장짜리를 환불하면 total 은 2로 내려간다.
  assert public.revoke_quota_from_purchase('ios', 'txn_A') = true, '환불 회수 실패';
  select * into p from public.profiles where id = u;
  assert p.quota_total = 2, format('회수 후 quota_total 이 2가 아니라 %s', p.quota_total);
  assert p.quota_used  = 2, format('회수가 quota_used 를 건드렸다: %s', p.quota_used);
  assert public.consume_quota(u) = false, '환불 후에도 생성이 된다';
  raise notice 'PASS 환불 회수 (사용분은 회수 안 함, 이후 생성 차단)';

  -- ── 환불 멱등 ─────────────────────────────────────────────────────────
  assert public.revoke_quota_from_purchase('ios', 'txn_A') = false, '이미 회수된 건이 또 회수됨';
  select quota_total into n from public.profiles where id = u;
  assert n = 2, format('중복 회수로 quota_total 이 %s 가 됨', n);
  raise notice 'PASS 환불 멱등성';

  raise notice '── 함수 테스트 전부 통과 ──';
end $$;
