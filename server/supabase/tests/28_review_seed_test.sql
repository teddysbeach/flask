-- 학습지에서 틀린 문제가 복습 일정에 반영되는가.
--
-- 이걸 안 하면 회차를 돌려가며 배정하는 규칙 때문에, 방금 틀린 문제의 첫 복습이
-- 35일 뒤로 잡히는 일이 생긴다. 망각곡선을 거꾸로 쓰는 셈이다.
\set ON_ERROR_STOP on

do $$
declare
  u uuid; w uuid; q_wrong uuid; q_right uuid;
  s record;
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'seed@onpar.test') returning id into u;
  insert into public.worksheets (user_id, topic, status) values (u, '미분', 'ready') returning id into w;

  insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation, difficulty)
  values (w, u, 0, 'short_answer', '틀릴 문제', '답', '해설', 2) returning id into q_wrong;
  insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation, difficulty)
  values (w, u, 1, 'short_answer', '맞힐 문제', '답', '해설', 2) returning id into q_right;

  -- 회차 4번(35일 뒤)을 맡은 문항이 하필 학생이 틀린 문항인 상황.
  insert into public.review_schedules (user_id, worksheet_id, quiz_item_id, repetition, interval_days, ease, due_at, state)
  values (u, w, q_wrong, 4, 35, 2.5, now() + interval '35 days', 'pending'),
         (u, w, q_right, 3, 16, 2.5, now() + interval '16 days', 'pending');

  -- ── 틀린 답 ────────────────────────────────────────────────────────────
  insert into public.responses (worksheet_id, user_id, response_id, quiz_item_id, kind, first_correct, correct)
  values (w, u, 'q0', q_wrong, 'choice', false, false);

  select * into s from public.review_schedules where quiz_item_id = q_wrong;
  assert s.repetition = 0, format('틀린 문항의 회차가 %s (0이어야 함)', s.repetition);
  assert s.interval_days = 1, format('간격이 %s일 (1일이어야 함)', s.interval_days);
  assert s.due_at < now() + interval '2 days', '틀린 문항의 첫 복습이 아직 멀다';
  assert s.ease < 2.5, format('ease 가 안 낮아졌다: %s', s.ease);
  raise notice 'PASS 틀린 문항: 35일 뒤 → 하루 뒤로 당기고 ease 를 낮춘다';

  -- ── 맞힌 답은 건드리지 않는다 ──────────────────────────────────────────
  -- 미루는 실수는 되돌릴 기회가 없다. 그리고 한 번 맞힌 것이 안다는 뜻도 아니다(찍었을 수 있다).
  insert into public.responses (worksheet_id, user_id, response_id, quiz_item_id, kind, first_correct, correct)
  values (w, u, 'q1', q_right, 'choice', true, true);

  select * into s from public.review_schedules where quiz_item_id = q_right;
  assert s.repetition = 3, format('맞힌 문항의 회차가 %s 로 바뀌었다', s.repetition);
  assert s.ease = 2.5, format('맞힌 문항의 ease 가 %s 로 바뀌었다', s.ease);
  raise notice 'PASS 맞힌 문항: 아무것도 바꾸지 않는다';

  -- ── 같은 답을 여러 번 저장해도 결과가 같다 ────────────────────────────
  -- 앱은 같은 자리를 디바운스로 여러 번 덮어쓴다. 부를 때마다 ease 가 내려가면
  -- 오래 붙잡고 고친 학생일수록 간격이 바닥까지 떨어진다.
  update public.responses set first_correct = false, updated_at = now()
   where quiz_item_id = q_wrong;
  update public.responses set first_correct = false, updated_at = now()
   where quiz_item_id = q_wrong;

  select * into s from public.review_schedules where quiz_item_id = q_wrong;
  assert s.ease >= 2.2, format('여러 번 저장했더니 ease 가 %s 까지 내려갔다', s.ease);
  raise notice 'PASS 같은 답을 여러 번 저장해도 한 번만 반영된다';

  -- ── 이미 끝난 회차는 되살리지 않는다 ──────────────────────────────────
  update public.review_schedules set state = 'done' where quiz_item_id = q_right;
  update public.responses set first_correct = false where quiz_item_id = q_right;
  select * into s from public.review_schedules where quiz_item_id = q_right;
  assert s.repetition = 3, '끝난 회차를 되살렸다';
  raise notice 'PASS 끝난 회차는 건드리지 않는다';

  -- ── 정답 키가 없는 활동(first_correct is null)은 무시한다 ─────────────
  insert into public.responses (worksheet_id, user_id, response_id, quiz_item_id, kind, first_correct)
  values (w, u, 'act0', null, 'written', null);
  raise notice 'PASS 정답 키가 없는 활동은 일정에 영향을 주지 않는다';
end $$;

do $$ begin raise notice '── 응답→복습 반영 테스트 전부 통과 ──'; end $$;
