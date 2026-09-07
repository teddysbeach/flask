-- 문의함(support_tickets) RLS · 권한 테스트.
--
-- 두 가지를 못 박는다.
--   1. **로그아웃 상태에서도 넣을 수 있다.** 로그인이 안 돼서 문의하는 사람을
--      로그인 화면으로 돌려보내면 그 사람은 우리에게 닿을 길이 없다.
--   2. **남의 문의는 안 보인다.** 익명 문의도 아무에게도 안 보인다 —
--      익명으로 들어온 글을 다른 익명 사용자가 읽으면 그건 문의함이 아니라 게시판이다.
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('77777777-7777-7777-7777-777777777777', 'grace@onpar.test'),
  ('88888888-8888-8888-8888-888888888888', 'heidi@onpar.test');

-- ── 로그아웃 상태(anon) ──────────────────────────────────────────────────
set role anon;
set request.jwt.claim.sub = '';

do $$
declare n int;
begin
  insert into public.support_tickets (user_id, topic, body, app_version, platform)
  values (null, 'account', '로그인이 안 돼서 앱에서 문의합니다. 인증 메일이 오지 않아요.', '1.0.0 (12)', 'ios');
  raise notice 'PASS 접수: 로그아웃 상태에서도 문의가 들어간다';

  -- 남의 이름으로는 못 넣는다. anon 은 auth.uid() 가 null 이라 참이 될 수 없다.
  begin
    insert into public.support_tickets (user_id, topic, body)
    values ('77777777-7777-7777-7777-777777777777', 'other', '그레이스인 척하고 넣는 문의입니다.');
    assert false, 'anon 이 남의 user_id 로 문의를 넣었다';
  exception when insufficient_privilege then
    raise notice 'PASS RLS: anon 은 남의 이름으로 못 넣는다';
  end;

  -- 넣을 수는 있어도 읽을 수는 없다. anon 에게는 select 권한 자체를 주지 않았다 —
  -- 익명으로 들어온 문의를 다른 익명 사용자가 읽으면 그건 문의함이 아니라 게시판이다.
  begin
    select count(*) into n from public.support_tickets;
    assert false, format('anon 에게 문의가 %s건 보인다 (읽히면 안 된다)', n);
  exception when insufficient_privilege then
    raise notice 'PASS 권한: anon 은 문의함을 못 읽는다';
  end;
end $$;

reset role;

-- ── Grace 로 전환 ──────────────────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';

do $$
declare n int; t uuid;
begin
  insert into public.support_tickets (user_id, topic, body, app_version, platform)
  values ('77777777-7777-7777-7777-777777777777', 'payment',
          '충전은 됐는데 남은 장수가 그대로예요. 어제 저녁에 10장을 샀어요.', '1.0.0 (12)', 'ios')
  returning id into t;
  raise notice 'PASS 접수: 로그인 상태에서 본인 이름으로 들어간다';

  -- 남의 이름으로는 못 넣는다.
  begin
    insert into public.support_tickets (user_id, topic, body)
    values ('88888888-8888-8888-8888-888888888888', 'other', '하이디인 척하고 넣는 문의입니다.');
    assert false, '남의 user_id 로 문의를 넣었다';
  exception when insufficient_privilege then
    raise notice 'PASS RLS: 남의 이름으로 접수 차단';
  end;

  -- 상태는 우리 것이다. 사용자가 'closed' 로 넣으면 접수되자마자 닫힌 문의가 된다.
  begin
    insert into public.support_tickets (user_id, topic, body, status)
    values ('77777777-7777-7777-7777-777777777777', 'other', '처리 완료로 넣어보는 문의입니다.', 'closed');
    assert false, '사용자가 status 를 정해서 넣었다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: status 는 사용자가 못 넣는다';
  end;

  -- 본문 길이 상한. 화면만 막으면 API 로는 얼마든지 들어온다.
  begin
    insert into public.support_tickets (user_id, topic, body)
    values ('77777777-7777-7777-7777-777777777777', 'other', repeat('가', 2001));
    assert false, '본문 2000자 제한이 없다';
  exception when check_violation then
    raise notice 'PASS 제약: 본문은 2000자까지';
  end;

  -- 유형은 닫힌 목록이다.
  begin
    insert into public.support_tickets (user_id, topic, body)
    values ('77777777-7777-7777-7777-777777777777', 'refund_now', '알 수 없는 유형으로 넣는 문의입니다.');
    assert false, 'topic 제약이 없다';
  exception when check_violation then
    raise notice 'PASS 제약: topic 은 닫힌 목록';
  end;

  -- 본인 것만 보인다(익명 문의는 본인 것이 아니다).
  select count(*) into n from public.support_tickets;
  assert n = 1, format('Grace 에게 문의가 %s건 보인다 (1건이어야 함)', n);
  raise notice 'PASS RLS: 익명 문의는 로그인한 사용자에게도 안 보인다';

  -- 문의는 사용자가 고치거나 지우지 않는다. 답변·종료는 운영이 서비스 롤로 한다.
  begin
    update public.support_tickets set body = '내용을 바꿔치기합니다' where id = t;
    assert false, '사용자가 접수된 문의를 고쳤다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 접수된 문의 수정 차단';
  end;
  begin
    delete from public.support_tickets where id = t;
    assert false, '사용자가 접수된 문의를 지웠다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 접수된 문의 삭제 차단';
  end;
end $$;

reset role;

-- ── Heidi 로 전환: 남의 문의는 보이지 않는다 ─────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';

do $$
declare n int;
begin
  select count(*) into n from public.support_tickets;
  assert n = 0, format('Heidi 에게 남의 문의가 %s건 보인다', n);

  select count(*) into n from public.support_tickets
   where user_id = '77777777-7777-7777-7777-777777777777';
  assert n = 0, 'Grace 의 문의가 Heidi 에게 보인다';
  raise notice 'PASS RLS: 남의 문의 안 보임';
end $$;

reset role;
set request.jwt.claim.sub = '';

-- ── 운영(서비스 롤) ──────────────────────────────────────────────────────
do $$
declare n int;
begin
  -- 익명 문의 1건 + Grace 1건. 운영은 전부 보고 상태를 바꿀 수 있어야 한다.
  select count(*) into n from public.support_tickets;
  assert n = 2, format('운영에게 문의가 %s건 보인다 (2건이어야 함)', n);

  update public.support_tickets set status = 'answered' where user_id is null;
  get diagnostics n = row_count;
  assert n = 1, '운영이 익명 문의의 상태를 못 바꿨다';
  raise notice 'PASS 운영: 서비스 롤은 전부 보고 상태를 바꾼다';

  raise notice '── support_tickets RLS 테스트 전부 통과 ──';
end $$;
