-- 사용자 한 명의 여정을 처음부터 끝까지 한 번에 통과시킨다.
--
-- 조각마다 테스트가 있는데 이걸 또 두는 이유: **순서**에서만 나는 버그가 있다.
-- 각 함수는 맞는데 이어 붙이면 안 되는 경우 — 트리거가 서로를 밟거나, RLS 가
-- 서버가 만든 행을 사용자에게 안 보여 주거나, 환불이 두 번 되거나.
-- 배포 전에 "이 앱을 한 사람이 처음부터 끝까지 쓸 수 있는가" 를 묻는 자리다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid; w uuid; q1 uuid; q2 uuid; sched uuid;
  n int; total int; used int; g record; r record;
begin
  raise notice '';
  raise notice '── ① 가입 ──';
  insert into auth.users (id, email, raw_user_meta_data)
  values (gen_random_uuid(), 'journey@onpar.test', '{"full_name":"여정"}') returning id into u;

  select quota_total, quota_used into total, used from public.profiles where id = u;
  assert total = 2 and used = 0, format('가입 직후 장수가 %s/%s', used, total);
  raise notice '   무료 2장을 받았다';

  raise notice '── ② 학습지 만들기 (장수 차감 → 생성 → 완성) ──';
  assert public.consume_quota(u), '첫 생성이 막혔다';
  insert into public.worksheets (user_id, topic, status) values (u, '이벤트 소싱', 'generating')
  returning id into w;

  -- 완성: 문항과 복습 일정이 함께 생긴다(파이프라인 saveContent + saveSchedules 순서)
  update public.worksheets
     set status = 'ready', title = '이벤트 소싱', quality_score = 88, revisions = 1,
         prompt_version = 'abcd1234', ready_at = now()
   where id = w;
  insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation, difficulty)
  values (w, u, 0, 'short_answer', '문제1', '답1', '해설1', 2) returning id into q1;
  -- 선택형은 choices 가 있어야 한다(quiz_items_choices_req). 이 제약을 이 테스트가 처음 잡았다.
  insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, choices, answer, explanation, difficulty)
  values (w, u, 1, 'multiple_choice', '문제2', '["ㄱ","ㄴ","ㄷ"]'::jsonb, '답2', '해설2', 3) returning id into q2;
  insert into public.review_schedules (user_id, worksheet_id, quiz_item_id, repetition, interval_days, ease, due_at, state)
  values (u, w, q1, 0, 1, 2.5, now() + interval '1 day', 'pending'),
         (u, w, q2, 4, 35, 2.5, now() + interval '35 days', 'pending');
  raise notice '   학습지 1장 · 문항 2개 · 복습 2회차가 생겼다';

  raise notice '── ③ 학습지 풀기 (틀린 문제가 복습을 당긴다) ──';
  insert into public.responses (worksheet_id, user_id, response_id, quiz_item_id, kind, first_correct, correct, attempts)
  values (w, u, 'q-1', q2, 'choice', false, false, '[{"choice":1,"correct":false}]'::jsonb);

  select * into r from public.review_schedules where quiz_item_id = q2;
  assert r.repetition = 0 and r.due_at < now() + interval '2 days',
    '학습지에서 틀렸는데 첫 복습이 35일 뒤 그대로다';
  raise notice '   틀린 문항의 첫 복습이 35일 → 1일로 당겨졌다';

  raise notice '── ④ 복습하기 ──';
  select id into sched from public.review_schedules where quiz_item_id = q1;
  update public.review_schedules
     set state = 'done', repetition = repetition + 1, interval_days = 3,
         ease = 2.6, due_at = now() + interval '3 days', answered_at = now(), grade = 3
   where id = sched;
  select count(*) into n from public.review_schedules where user_id = u and state = 'done';
  assert n = 1, '복습 기록이 안 남았다';
  raise notice '   한 회차를 마쳤다';

  raise notice '── ⑤ 두 번째 생성이 실패하고 환불된다 ──';
  assert public.consume_quota(u), '두 번째 생성이 막혔다';
  select quota_used into used from public.profiles where id = u;
  assert used = 2, format('두 장을 썼는데 quota_used 가 %s', used);

  insert into public.worksheets (user_id, topic, status) values (u, '실패할 주제', 'generating')
  returning id into w;
  assert public.fail_generation(w, 'llm_refused'), '실패 처리가 환불하지 않았다';
  select quota_used into used from public.profiles where id = u;
  assert used = 1, format('환불 뒤 quota_used 가 %s (1이어야 함)', used);
  raise notice '   실패한 생성의 장수가 돌아왔다';

  raise notice '── ⑥ 결제 ──';
  select * into g from public.grant_quota_from_purchase(
    u, 'ios', 'onpar.sheets.10', 'txn_journey', 'orig_journey', 12900, '{"env":"sandbox"}'::jsonb);
  assert g.granted = 10, format('10장 상품인데 %s장', g.granted);

  -- 같은 영수증이 다시 와도 두 번 지급하지 않는다(스토어가 재전달하는 것은 정상이다).
  select * into g from public.grant_quota_from_purchase(
    u, 'ios', 'onpar.sheets.10', 'txn_journey', 'orig_journey', 12900, '{"env":"sandbox"}'::jsonb);
  assert g.already_processed, '같은 영수증이 두 번 지급됐다';
  select quota_total into total from public.profiles where id = u;
  assert total = 12, format('무료 2 + 결제 10 = 12 여야 하는데 %s', total);
  raise notice '   10장을 받았고, 같은 영수증은 두 번 지급되지 않는다';

  raise notice '── ⑦ 운영이 보는 그림 ──';
  select count(*) into n from public.quota_reconciliation q where q.user_id = u;
  assert n = 0, '정상 계정이 대사에서 미설명으로 잡힌다';
  raise notice '   대사에 걸리는 것이 없다';

  raise notice '── ⑧ 탈퇴 ──';
  -- 구매 내역은 법정 보존 의무가 있어 남기되, 사람과의 연결을 끊는다.
  update public.purchases set user_id = null, anonymized_at = now() where user_id = u;
  delete from auth.users where id = u;

  select count(*) into n from public.profiles where id = u;
  assert n = 0, '탈퇴했는데 프로필이 남았다';
  select count(*) into n from public.worksheets where user_id = u;
  assert n = 0, '탈퇴했는데 학습지가 남았다';
  select count(*) into n from public.review_schedules where user_id = u;
  assert n = 0, '탈퇴했는데 복습 일정이 남았다';
  select count(*) into n from public.responses where user_id = u;
  assert n = 0, '탈퇴했는데 학습 응답이 남았다';
  select count(*) into n from public.purchases where anonymized_at is not null;
  assert n = 1, '구매 내역이 통째로 사라졌다 (익명화해서 남겨야 한다)';
  raise notice '   사람에 딸린 것은 전부 지워졌고, 구매 내역만 익명으로 남았다';
end $$;

do $$ begin raise notice '── 여정 테스트 전부 통과 ──'; end $$;
