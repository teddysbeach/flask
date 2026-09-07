-- 문항 수가 4~7 인 학습지가 실제로 저장되는지. 검증기만 통과하고 DB 에서 터지면 소용없다.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000aa';
  w uuid;
begin
  insert into auth.users (id, email) values (u, 'quizcount@test.local')
    on conflict (id) do nothing;
  insert into public.profiles (id, display_name) values (u, '문항수')
    on conflict (id) do nothing;

  insert into public.worksheets (user_id, topic, status)
  values (u, '문항 수 테스트', 'ready') returning id into w;

  -- 7문항(idx 0~6)이 들어가야 한다
  for i in 0..6 loop
    insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation)
    values (w, u, i, 'short_answer', '질문 ' || i, '답', '해설');
  end loop;
  raise notice 'PASS 문항 7개(idx 0~6) 저장';

  -- 8번째(idx 7)는 여전히 막혀야 한다. 상한이 없으면 오타가 그대로 들어간다.
  begin
    insert into public.quiz_items (worksheet_id, user_id, idx, kind, question, answer, explanation)
    values (w, u, 7, 'short_answer', '여덟 번째', '답', '해설');
    raise exception 'FAIL idx 7 이 들어갔다 — 상한이 없다';
  exception when check_violation then
    raise notice 'PASS 상한 밖(idx 7)은 거부';
  end;

  delete from public.worksheets where id = w;
  raise notice '── 문항 수 테스트 전부 통과 ──';
end $$;
