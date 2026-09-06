-- Storage 버킷. 둘 다 private — 접근은 서명 URL 또는 아래 정책으로만.
-- 경로 규약: {bucket}/{user_id}/{worksheet_id}.{ext}

insert into storage.buckets (id, name, public)
values ('worksheets', 'worksheets', false), ('annotations', 'annotations', false)
on conflict (id) do nothing;

-- 학습지 HTML: 본인 폴더만 읽기. 쓰기는 service_role 만 (렌더러가 만든다).
create policy worksheets_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'worksheets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 필기: 본인 폴더에 직접 읽고 쓴다. 대용량이라 Edge Function 경유는 낭비.
create policy annotations_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'annotations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy annotations_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'annotations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy annotations_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'annotations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy annotations_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'annotations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
