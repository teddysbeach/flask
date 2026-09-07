-- 텔레메트리 테이블이 **사용자 토큰으로는 닫혀 있는가**.
--
-- 여기가 열려 있으면 남의 계정 이름으로 이벤트를 넣거나, 남이 무엇을 했는지 읽을 수 있다.
-- 분석 데이터는 "덜 민감하다" 고 여겨져서 자주 열린 채로 배포된다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid; other uuid; n int;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'tel@onpar.test') returning id into u;
  insert into auth.users (id, email) values (gen_random_uuid(), 'tel2@onpar.test') returning id into other;

  -- 서비스 롤(Edge Function)은 넣을 수 있다.
  insert into public.telemetry_events (user_id, install_id, name, props, occurred_at)
  values (u, gen_random_uuid(), 'appOpen', '{"kind":"cold"}'::jsonb, now());
  insert into public.crash_reports (user_id, install_id, fingerprint, message, occurred_at)
  values (u, gen_random_uuid(), 'abcd1234', '터졌다', now());

  -- ── 사용자 토큰으로는 아무것도 못 한다 ──
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', u::text, true);

  begin
    select count(*) into n from public.telemetry_events;
    raise exception '사용자가 텔레메트리를 읽었다 (%건)', n;
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.telemetry_events (user_id, install_id, name, occurred_at)
    values (other, gen_random_uuid(), 'purchaseComplete', now());
    raise exception '사용자가 남의 이름으로 이벤트를 넣었다';
  exception when insufficient_privilege then null;
  end;

  begin
    select count(*) into n from public.crash_reports;
    raise exception '사용자가 크래시 로그를 읽었다 (%건)', n;
  exception when insufficient_privilege then null;
  end;

  reset role;
  raise notice '── 텔레메트리 RLS 테스트 전부 통과 ──';
end $$;

-- ── 상한 제약 ────────────────────────────────────────────────────────────
do $$
declare u uuid;
begin
  select id into u from auth.users where email = 'tel@onpar.test';

  begin
    insert into public.telemetry_events (user_id, install_id, name, occurred_at)
    values (u, gen_random_uuid(), repeat('x', 100), now());
    raise exception '이벤트 이름 길이 제약이 없다';
  exception when check_violation then null;
  end;

  -- props 가 커지면 본문이 통째로 들어오고 있다는 뜻이다.
  begin
    insert into public.telemetry_events (user_id, install_id, name, props, occurred_at)
    values (u, gen_random_uuid(), 'appOpen',
            jsonb_build_object('name', repeat('가', 3000)), now());
    raise exception 'props 크기 제약이 없다';
  exception when check_violation then null;
  end;

  raise notice '── 텔레메트리 상한 테스트 전부 통과 ──';
end $$;

-- ── 보관 기간 ────────────────────────────────────────────────────────────
do $$
declare u uuid; r record;
begin
  select id into u from auth.users where email = 'tel@onpar.test';
  insert into public.telemetry_events (user_id, install_id, name, occurred_at)
  values (u, gen_random_uuid(), 'appOpen', now() - interval '200 days');
  insert into public.crash_reports (user_id, install_id, fingerprint, message, occurred_at)
  values (u, gen_random_uuid(), 'old', '오래된 크래시', now() - interval '400 days');

  select * into r from public.prune_telemetry('90 days'::interval);
  assert r.events_deleted >= 1, '오래된 이벤트가 안 지워졌다';
  assert r.crashes_deleted >= 1, '오래된 크래시가 안 지워졌다';

  -- 최근 것은 남아 있어야 한다.
  assert (select count(*) from public.telemetry_events where occurred_at > now() - interval '1 day') >= 1,
    '최근 이벤트까지 지웠다';

  raise notice '── 텔레메트리 보관기간 테스트 전부 통과 ──';
end $$;
