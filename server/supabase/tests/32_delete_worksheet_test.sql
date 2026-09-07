-- 학습지 한 장을 지우면 딸린 것이 전부 따라 지워지는가.
--
-- 삭제는 되돌릴 수 없어서, 덜 지우는 것도 더 지우는 것도 나쁘다.
--   · 덜 지우면: 사용자는 지웠다고 믿는데 문항·응답·복습 회차가 남는다.
--   · 더 지우면: 남의 학습지가 사라진다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid; other uuid; w uuid; w2 uuid; q uuid; n int;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'del@onpar.test') returning id into u;
  insert into auth.users (id, email) values (gen_random_uuid(), 'del2@onpar.test') returning id into other;

  insert into public.worksheets (user_id, topic, status, html_path)
  values (u, '지울 학습지', 'ready', u || '/w1.html') returning id into w;
  insert into public.worksheets (user_id, topic, status)
  values (u, '남을 학습지', 'ready') returning id into w2;

  insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation, difficulty)
  values (w, u, 0, 'short_answer', '문제', '답', '해설', 2) returning id into q;
  insert into public.responses (worksheet_id, user_id, response_id, quiz_item_id, kind, first_correct, correct)
  values (w, u, 'r0', q, 'choice', true, true);
  insert into public.review_schedules (user_id, worksheet_id, quiz_item_id, repetition, interval_days, ease, due_at, state)
  values (u, w, q, 0, 1, 2.5, now(), 'pending');
  insert into public.annotations (worksheet_id, user_id, strokes_path, stroke_count, bytes, rev)
  values (w, u, u || '/w1.json', 3, 100, 1);

  -- ── 남의 학습지는 못 지운다 ──
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', other::text, true);
  delete from public.worksheets where id = w;
  reset role;
  -- 세는 것은 **역할을 되돌린 뒤에** 한다. 남의 토큰으로 세면 RLS 때문에 어차피 0 이 나와서,
  -- 안 지워졌는데도 지워진 것처럼 보인다.
  select count(*) into n from public.worksheets where id = w;
  assert n = 1, '남의 학습지가 지워졌다';

  -- ── 주인은 지울 수 있고, 딸린 것이 따라 지워진다 ──
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', u::text, true);
  delete from public.worksheets where id = w;
  reset role;

  select count(*) into n from public.worksheets where id = w;
  assert n = 0, '학습지가 안 지워졌다';
  select count(*) into n from public.quiz_items where worksheet_id = w;
  assert n = 0, format('문항이 %s개 남았다', n);
  select count(*) into n from public.responses where worksheet_id = w;
  assert n = 0, format('응답이 %s개 남았다', n);
  select count(*) into n from public.review_schedules where worksheet_id = w;
  assert n = 0, format('복습 회차가 %s개 남았다 — 지운 학습지의 문제로 알림이 온다', n);
  select count(*) into n from public.annotations where worksheet_id = w;
  assert n = 0, format('필기 메타가 %s개 남았다', n);

  -- 다른 학습지는 그대로.
  select count(*) into n from public.worksheets where id = w2;
  assert n = 1, '다른 학습지까지 지워졌다';

  raise notice '── 학습지 삭제 테스트 전부 통과 ──';
end $$;

-- ── 제목만 고칠 수 있다 ────────────────────────────────────────────────
do $$
declare u uuid; w uuid; t text; s text;
begin
  select id into u from auth.users where email = 'del@onpar.test';
  select id into w from public.worksheets where user_id = u limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', u::text, true);

  update public.worksheets set title = '내가 고친 제목' where id = w;
  select title into t from public.worksheets where id = w;
  assert t = '내가 고친 제목', '제목을 못 고쳤다 — 앱에 제목 바꾸기가 있다';

  -- 상태는 서버 소유다. 앱이 고칠 수 있으면 실패한 학습지를 완성으로 바꿀 수 있다.
  begin
    update public.worksheets set status = 'ready' where id = w;
    raise exception '사용자가 상태를 고쳤다';
  exception when insufficient_privilege then null;
  end;

  reset role;
  select status into s from public.worksheets where id = w;
  assert s is not null, '상태가 사라졌다';
  raise notice '── 제목 수정 권한 테스트 전부 통과 ──';
end $$;
