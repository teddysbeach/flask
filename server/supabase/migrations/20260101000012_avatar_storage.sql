-- 프로필 사진: 비공개 `avatars` 버킷 + profiles.avatar_path
--
-- 공개(public) 버킷으로 두지 않는다. 공개면 URL 이 `/storage/v1/object/public/avatars/{user_id}/...`
-- 로 뻔해서 **사용자 id 만 알면 누구나 남의 프로필 사진을 본다**. 앱은 서명 URL 로 연다.
-- 경로 규약은 다른 버킷과 같다: {bucket}/{user_id}/{파일명}

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public            = excluded.public,
      file_size_limit   = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 필기는 8MB. A4 5장 빽빽한 필기가 압축 후 300~800KB 이므로(06-annotation §4) 한참 여유가 있고,
-- 그 열 배를 넘는 업로드는 정상 필기가 아니다 — 앱 버그나 악의적 업로드로 보고 서버에서 끊는다.
update storage.buckets set file_size_limit = 8388608 where id = 'annotations';

-- 프로필 사진: 본인 폴더만 읽고 쓴다. 다른 버킷과 같은 패턴
-- ((storage.foldername(name))[1] = auth.uid()::text).
create policy avatars_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── profiles.avatar_path ────────────────────────────────────────────────
alter table public.profiles add column if not exists avatar_path text;

comment on column public.profiles.avatar_path is
  '프로필 사진의 Storage 경로({user_id}/avatar_{stamp}.jpg). URL 이 아니다 — '
  '버킷이 비공개라 볼 때마다 서명 URL 을 새로 만들고, 서명 URL 은 만료되므로 DB 에 넣으면 안 된다.';

-- 20260101000003 이 profiles 의 테이블 단위 UPDATE 권한을 걷어내고 컬럼만 다시 줬다.
-- 새 컬럼은 그 목록에 없으므로 여기서 같이 준다. 빠뜨리면 사진 저장이 42501 로 막힌다.
-- (컬럼 단위 grant 는 누적이지만, 무엇이 허용인지 한눈에 보이도록 전체 목록을 다시 적는다.)
grant update (display_name, locale, review_hour, timezone, avatar_path)
  on public.profiles to authenticated;
