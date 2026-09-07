-- 관문(app_config) 테스트.
--
-- 여기서 지켜야 하는 것은 하나다. **로그인 전에 읽혀야 한다.**
-- 부팅 첫 화면에서 읽는 값이라, 로그인해야 읽을 수 있으면 정작 점검 중일 때
-- "점검 중" 을 못 띄운다. 그래서 anon 으로 읽는 경로를 못 박아 둔다.
\set ON_ERROR_STOP on

-- ── 로그인하지 않은 사용자(anon) ─────────────────────────────────────────
set role anon;
set request.jwt.claim.sub = '';   -- 세션이 없다

do $$
declare n int; m boolean; b int;
begin
  select count(*) into n from public.app_config;
  assert n = 2, format('anon 에게 app_config 가 %s행 보인다 (ios/android 2행이어야 함)', n);
  raise notice 'PASS 관문: 로그인 없이 읽힌다';

  -- 기본 행은 통과여야 한다. 여기가 틀리면 앱을 켠 모든 사람이 처음부터 막힌다.
  for m, b in select maintenance, min_build from public.app_config loop
    assert m = false, '기본 행이 점검 중으로 들어가 있다';
    assert b = 0, format('기본 행의 min_build 가 %s 다 (0이어야 함)', b);
  end loop;
  raise notice 'PASS 관문: 기본값은 통과(maintenance=false, min_build=0)';

  -- 읽기만이다. 쓰기가 열려 있으면 아무나 전 사용자를 점검 중으로 만들 수 있다.
  begin
    update public.app_config set maintenance = true where platform = 'ios';
    assert false, 'anon 이 점검 스위치를 켰다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: anon 은 관문을 못 바꾼다';
  end;

  begin
    insert into public.app_config (platform, min_build) values ('android', 999);
    assert false, 'anon 이 app_config 에 행을 넣었다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: anon 은 관문에 행을 못 넣는다';
  end;
end $$;

reset role;

-- ── 로그인한 사용자도 읽기만 ─────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
declare n int;
begin
  select count(*) into n from public.app_config;
  assert n = 2, format('로그인한 사용자에게 app_config 가 %s행 보인다', n);

  begin
    update public.app_config set min_build = 9999;
    assert false, 'authenticated 가 min_build 를 올렸다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: authenticated 도 관문을 못 바꾼다';
  end;

  begin
    delete from public.app_config;
    assert false, 'authenticated 가 관문 행을 지웠다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 관문 행 삭제 차단';
  end;
end $$;

reset role;
set request.jwt.claim.sub = '';

-- ── 운영(서비스 롤)은 바꿀 수 있어야 한다 ────────────────────────────────
-- 못 바꾸면 사고가 났을 때 스토어 심사를 기다려야 사용자를 막을 수 있다.
do $$
declare n int;
begin
  update public.app_config
     set maintenance = true, message = '잠시 점검 중이에요', until = now() + interval '1 hour'
   where platform = 'ios';
  get diagnostics n = row_count;
  assert n = 1, '서비스 롤이 점검을 켜지 못했다';
  raise notice 'PASS 운영: 서비스 롤은 점검을 켤 수 있다';

  -- 켠 것은 되돌려 둔다. 뒤에 오는 테스트가 이 값을 보지 않게.
  update public.app_config set maintenance = false, message = null, until = null
   where platform = 'ios';

  -- 알 수 없는 플랫폼은 애초에 들어오지 않는다.
  begin
    insert into public.app_config (platform) values ('web');
    assert false, 'platform 제약이 없다';
  exception when check_violation then
    raise notice 'PASS 제약: platform 은 ios/android 만';
  end;

  raise notice '── app_config 테스트 전부 통과 ──';
end $$;
