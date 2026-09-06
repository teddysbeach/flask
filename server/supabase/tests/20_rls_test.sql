-- RLS · 권한 테스트. authenticated 역할로 전환해서 실제 정책을 통과시킨다.
\set ON_ERROR_STOP on

-- 두 사용자와 각자의 학습지 하나씩 (service_role 문맥에서 준비)
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@onpar.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@onpar.test');

insert into public.worksheets (id, user_id, topic, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '이벤트 소싱', 'ready'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '밥의 비밀 주제', 'ready');

-- ── Alice 로 전환 ────────────────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
declare n int; ok boolean;
begin
  select count(*) into n from public.worksheets;
  assert n = 1, format('Alice 에게 학습지가 %s개 보인다 (1개여야 함)', n);

  select count(*) into n from public.worksheets
   where id = 'bbbbbbbb-0000-0000-0000-000000000001';
  assert n = 0, 'Bob 의 학습지가 Alice 에게 보인다';
  raise notice 'PASS RLS: 남의 학습지 안 보임';

  -- 학습지 직접 INSERT 는 막혀야 한다 (생성은 Edge Function 전용)
  begin
    insert into public.worksheets (user_id, topic)
    values ('11111111-1111-1111-1111-111111111111', '몰래 만든 학습지');
    assert false, 'authenticated 가 worksheets 를 직접 INSERT 했다';
  exception when insufficient_privilege then
    raise notice 'PASS RLS: 학습지 직접 INSERT 차단';
  end;

  -- 제목은 고칠 수 있어야 한다
  update public.worksheets set title = '내가 붙인 제목'
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  raise notice 'PASS 제목 수정 허용';

  -- 쿼터 컬럼은 본인도 못 바꾼다
  begin
    update public.profiles set quota_total = 9999
     where id = '11111111-1111-1111-1111-111111111111';
    assert false, 'authenticated 가 quota_total 을 직접 올렸다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: quota_total 직접 수정 차단';
  end;

  -- 쿼터 함수도 직접 못 부른다
  begin
    ok := public.consume_quota('11111111-1111-1111-1111-111111111111');
    assert false, 'authenticated 가 consume_quota 를 직접 실행했다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: consume_quota 직접 실행 차단';
  end;

  begin
    perform public.grant_quota_from_purchase(
      '11111111-1111-1111-1111-111111111111', 'ios', 'onpar.sheets.30',
      'fake_txn', null, 0, '{}'::jsonb);
    assert false, 'authenticated 가 결제 지급 함수를 직접 실행했다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 결제 지급 함수 직접 실행 차단';
  end;

  -- 필기는 본인 것을 직접 쓸 수 있어야 한다
  insert into public.annotations (worksheet_id, user_id, stroke_count)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          '11111111-1111-1111-1111-111111111111', 3);
  raise notice 'PASS RLS: 본인 필기 저장 허용';

  -- 남의 학습지에는 필기를 못 붙인다
  begin
    insert into public.annotations (worksheet_id, user_id)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
            '22222222-2222-2222-2222-222222222222');
    assert false, '남의 학습지에 필기를 붙였다';
  exception when insufficient_privilege then
    raise notice 'PASS RLS: 남의 학습지 필기 차단';
  end;

  -- 상품 카탈로그는 누구나 읽어야 한다 (구매 화면)
  select count(*) into n from public.products where is_active;
  assert n = 3, format('활성 상품이 %s개 (3개여야 함)', n);
  raise notice 'PASS RLS: 상품 카탈로그 조회 허용';
end $$;

reset role;
do $$ begin raise notice '── RLS 테스트 전부 통과 ──'; end $$;
