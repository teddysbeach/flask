-- responses RLS · 권한 테스트.
-- 학습 응답은 사용자가 직접 쓴다. 그래서 "본인 것만" 이 정책으로 강제되는지, 그리고
-- 행의 정체(worksheet_id / response_id / kind)가 나중에 바뀌지 않는지 확인한다.
\set ON_ERROR_STOP on

-- 이 파일만 돌려도 되도록 자기 사용자를 만든다 (20_ 의 alice/bob 에 기대지 않는다)
insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'carol@onpar.test'),
  ('44444444-4444-4444-4444-444444444444', 'dave@onpar.test');

insert into public.worksheets (id, user_id, topic, status) values
  ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '미분계수', 'ready'),
  ('dddddddd-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', '데이브의 주제', 'ready');

insert into public.quiz_items (id, worksheet_id, user_id, idx, kind, question, choices, answer, explanation) values
  ('cccccccc-1111-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
   '33333333-3333-3333-3333-333333333333', 0, 'multiple_choice', '할선의 극한은?',
   '["접선", "법선", "0"]'::jsonb, '접선', '점이 가까워진다');

-- 데이브의 응답 한 줄 (service_role 문맥에서 미리 넣어 둔다)
insert into public.responses (worksheet_id, user_id, response_id, kind, first_choice, final_choice, correct)
values ('dddddddd-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444',
        'quiz-1', 'choice', 0, 0, false);

-- ── Carol 로 전환 ────────────────────────────────────────────────────────
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

do $$
declare n int;
begin
  -- 본인 응답은 직접 쓸 수 있어야 한다 (필기와 같다 — Edge Function 을 거칠 이유가 없다)
  insert into public.responses
    (worksheet_id, user_id, response_id, quiz_item_id, kind,
     first_choice, final_choice, correct, attempts, ms_since_prompt)
  values
    ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
     'quiz-1', 'cccccccc-1111-0000-0000-000000000001', 'choice',
     2, 0, true,
     '[{"choice":2,"correct":false,"at":1,"msSincePrompt":4200},
       {"choice":0,"correct":true,"at":2,"msSincePrompt":9100}]'::jsonb,
     4200);
  insert into public.responses
    (worksheet_id, user_id, response_id, kind, text, chars, ink_strokes, ms_since_prompt)
  values
    ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
     'reason-1', 'written', '점이 가까워지면 할선이 접선이 된다', 20, 3, 15000);
  raise notice 'PASS RLS: 본인 응답 저장 허용';

  -- 첫 응답과 최종 응답이 따로 남아야 한다 (덮어쓰기였다면 이 검사가 의미가 없다)
  select count(*) into n from public.responses
   where response_id = 'quiz-1' and first_choice = 2 and final_choice = 0
     and jsonb_array_length(attempts) = 2;
  assert n = 1, '첫 오답(first_choice)이 최종 정답에 덮어써졌다';
  raise notice 'PASS 스키마: first/final/attempts 가 따로 남는다';

  -- 남의 응답은 보이지 않는다
  select count(*) into n from public.responses;
  assert n = 2, format('Carol 에게 응답이 %s개 보인다 (2개여야 함)', n);
  select count(*) into n from public.responses
   where worksheet_id = 'dddddddd-0000-0000-0000-000000000001';
  assert n = 0, 'Dave 의 응답이 Carol 에게 보인다';
  raise notice 'PASS RLS: 남의 응답 안 보임';

  -- 남의 이름으로는 못 쓴다
  begin
    insert into public.responses (worksheet_id, user_id, response_id, kind)
    values ('dddddddd-0000-0000-0000-000000000001',
            '44444444-4444-4444-4444-444444444444', 'quiz-2', 'choice');
    assert false, '남의 user_id 로 응답을 저장했다';
  exception when insufficient_privilege then
    raise notice 'PASS RLS: 남의 이름으로 응답 저장 차단';
  end;

  -- 답을 고치는 것(정상 갱신)은 허용
  update public.responses
     set final_choice = 1, attempts = attempts || '[{"choice":1}]'::jsonb, updated_at = now()
   where response_id = 'quiz-1';
  get diagnostics n = row_count;
  assert n = 1, '본인 응답을 갱신하지 못했다';
  raise notice 'PASS RLS: 본인 응답 갱신 허용';

  -- 행의 정체는 못 바꾼다 (컬럼 단위 권한)
  begin
    update public.responses set worksheet_id = 'dddddddd-0000-0000-0000-000000000001'
     where response_id = 'quiz-1';
    assert false, 'worksheet_id 를 바꿔 남의 학습지에 응답을 옮겼다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: worksheet_id 변경 차단';
  end;
  begin
    update public.responses set response_id = 'quiz-9' where response_id = 'quiz-1';
    assert false, 'response_id 를 바꿔 이력을 세탁했다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: response_id 변경 차단';
  end;
  begin
    update public.responses set user_id = '44444444-4444-4444-4444-444444444444'
     where response_id = 'quiz-1';
    assert false, 'user_id 를 바꿔 응답을 넘겼다';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: user_id 변경 차단';
  end;

  -- 남의 응답은 갱신 대상 자체가 되지 않는다 (에러가 아니라 0행)
  update public.responses set correct = true
   where worksheet_id = 'dddddddd-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, format('남의 응답 %s행을 고쳤다', n);
  raise notice 'PASS RLS: 남의 응답 갱신 차단';

  -- 학습 이력은 지우지 않는다 (DELETE 정책도 권한도 없다)
  begin
    delete from public.responses where response_id = 'quiz-1';
    get diagnostics n = row_count;
    assert n = 0, format('응답 %s행이 지워졌다', n);
    raise notice 'PASS RLS: 응답 삭제 차단';
  exception when insufficient_privilege then
    raise notice 'PASS 권한: 응답 삭제 차단';
  end;

  -- 같은 자리에 두 줄이 생기면 "마지막 응답"이 무엇인지 알 수 없게 된다
  begin
    insert into public.responses (worksheet_id, user_id, response_id, kind)
    values ('cccccccc-0000-0000-0000-000000000001',
            '33333333-3333-3333-3333-333333333333', 'quiz-1', 'choice');
    assert false, '같은 (worksheet_id, response_id) 가 두 번 들어갔다';
  exception when unique_violation then
    raise notice 'PASS 제약: (worksheet_id, response_id) 유일';
  end;

  -- 알 수 없는 kind 는 거부
  begin
    insert into public.responses (worksheet_id, user_id, response_id, kind)
    values ('cccccccc-0000-0000-0000-000000000001',
            '33333333-3333-3333-3333-333333333333', 'x-1', 'doodle');
    assert false, 'kind 제약이 없다';
  exception when check_violation then
    raise notice 'PASS 제약: kind 는 choice/written 만';
  end;
end $$;

reset role;
do $$ begin raise notice '── responses RLS 테스트 전부 통과 ──'; end $$;
