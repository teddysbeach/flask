-- 프로필 사진 · 권한 테스트 (20260101000012_avatar_storage.sql)
--
-- 확인하는 것 두 가지:
--   1. avatar_path 는 본인만 바꾼다 (컬럼 grant 가 빠지면 아예 저장이 안 되고,
--      RLS 가 새면 남의 프로필 사진을 바꿀 수 있다).
--   2. 남의 폴더에는 파일을 못 쓴다 — 경로 첫 조각이 사용자 id 라는 규약이 정책으로 강제되는지.
\set ON_ERROR_STOP on

-- 이 파일만 돌려도 되도록 자기 사용자를 만든다.
insert into auth.users (id, email) values
  ('55555555-5555-5555-5555-555555555555', 'erin@onpar.test'),
  ('66666666-6666-6666-6666-666666666666', 'frank@onpar.test');

-- 버킷 설정 (service_role 문맥에서 확인)
do $$
declare b record;
begin
  select * into b from storage.buckets where id = 'avatars';
  assert b.id is not null, 'avatars 버킷이 없다';
  assert b.public = false,
    'avatars 버킷이 public 이다 — id 만 알면 남의 프로필 사진이 열린다';
  assert b.file_size_limit = 2097152,
    format('avatars 용량 제한이 %s (2MB 여야 함)', b.file_size_limit);
  assert b.allowed_mime_types @> array['image/jpeg','image/png'],
    'avatars 가 jpeg/png 를 허용하지 않는다';
  raise notice 'PASS 버킷: avatars 비공개 · 2MB · jpeg/png';

  select * into b from storage.buckets where id = 'annotations';
  assert b.file_size_limit = 8388608,
    format('annotations 용량 제한이 %s (8MB 여야 함)', b.file_size_limit);
  raise notice 'PASS 버킷: annotations 8MB';
end $$;

-- ── Erin 으로 전환 ──────────────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

do $$
declare n int; v text;
begin
  -- 본인 프로필 사진 경로는 바꿀 수 있어야 한다 (컬럼 grant + RLS)
  update public.profiles set avatar_path = '55555555-5555-5555-5555-555555555555/avatar_1.jpg'
   where id = '55555555-5555-5555-5555-555555555555';
  select avatar_path into v from public.profiles
   where id = '55555555-5555-5555-5555-555555555555';
  assert v = '55555555-5555-5555-5555-555555555555/avatar_1.jpg',
    'avatar_path 가 저장되지 않았다 (컬럼 update grant 누락?)';
  raise notice 'PASS 권한: 본인 avatar_path 수정 허용';

  -- 되돌리기(기본 이미지로) = null
  update public.profiles set avatar_path = null
   where id = '55555555-5555-5555-5555-555555555555';
  raise notice 'PASS 권한: 본인 avatar_path 비우기 허용';

  -- 남의 프로필은 보이지도, 바뀌지도 않는다
  update public.profiles set avatar_path = 'hacked/avatar.jpg'
   where id = '66666666-6666-6666-6666-666666666666';
  get diagnostics n = row_count;
  assert n = 0, format('남의 avatar_path 를 %s행 바꿨다', n);
  raise notice 'PASS RLS: 남의 avatar_path 수정 차단';

  -- 쿼터 컬럼은 여전히 막혀 있어야 한다 (grant 를 다시 적으면서 넓히지 않았는지)
  begin
    update public.profiles set quota_total = 9999
     where id = '55555555-5555-5555-5555-555555555555';
    assert false, 'avatar_path grant 를 추가하면서 quota_total 까지 열렸다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: quota_total 은 여전히 차단';
  end;

  -- 본인 폴더에는 올릴 수 있다
  insert into storage.objects (bucket_id, name, owner)
  values ('avatars', '55555555-5555-5555-5555-555555555555/avatar_1.jpg',
          '55555555-5555-5555-5555-555555555555');
  raise notice 'PASS Storage RLS: 본인 폴더 업로드 허용';

  -- 남의 폴더에는 못 올린다
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('avatars', '66666666-6666-6666-6666-666666666666/avatar_1.jpg',
            '55555555-5555-5555-5555-555555555555');
    assert false, '남의 폴더에 프로필 사진을 올렸다';
  exception when insufficient_privilege then
    raise notice 'PASS Storage RLS: 남의 폴더 업로드 차단';
  end;

  -- 폴더 없이 버킷 루트에 올리는 것도 막힌다 (첫 조각이 사용자 id 가 아니다)
  begin
    insert into storage.objects (bucket_id, name) values ('avatars', 'avatar_1.jpg');
    assert false, '버킷 루트에 프로필 사진을 올렸다';
  exception when insufficient_privilege then
    raise notice 'PASS Storage RLS: 버킷 루트 업로드 차단';
  end;

  -- 필기도 같은 규약이다 — 남의 폴더에 필기를 올리지 못한다
  begin
    insert into storage.objects (bucket_id, name)
    values ('annotations', '66666666-6666-6666-6666-666666666666/w1.json.gz');
    assert false, '남의 폴더에 필기를 올렸다';
  exception when insufficient_privilege then
    raise notice 'PASS Storage RLS: 남의 필기 폴더 업로드 차단';
  end;
end $$;

-- ── Frank 로 전환: 에린의 사진은 보이지 않는다 ──────────────────────────
set request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';

do $$
declare n int;
begin
  select count(*) into n from storage.objects
   where bucket_id = 'avatars'
     and name = '55555555-5555-5555-5555-555555555555/avatar_1.jpg';
  assert n = 0, '남의 프로필 사진 객체가 보인다';
  raise notice 'PASS Storage RLS: 남의 프로필 사진 안 보임';

  -- 남의 사진을 지울 수도 없다
  delete from storage.objects
   where bucket_id = 'avatars'
     and name = '55555555-5555-5555-5555-555555555555/avatar_1.jpg';
  get diagnostics n = row_count;
  assert n = 0, format('남의 프로필 사진을 %s개 지웠다', n);
  raise notice 'PASS Storage RLS: 남의 프로필 사진 삭제 차단';
end $$;

reset role;
