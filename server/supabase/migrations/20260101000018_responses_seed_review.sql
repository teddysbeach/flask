-- 학습지에서 틀린 문제는 더 빨리 돌아온다.
--
-- 지금까지 responses 는 쌓기만 하고 아무도 읽지 않았다. 학생이 학습지 안에서 무엇을 틀렸는지
-- 다 알고 있으면서 복습 일정은 그걸 모른 채 짜였다.
--
-- 특히 나쁜 경우가 있었다. 복습 회차는 문항에 **돌아가며** 배정된다(0,1,2,3,4,0,…).
-- 그래서 학생이 학습지에서 틀린 문제가 하필 회차 4번을 맡았으면 그 문제의 첫 복습이 35일 뒤다.
-- 방금 틀린 것을 한 달 넘게 안 물어보는 것은 망각곡선을 거꾸로 쓰는 것이다.
--
-- 그래서 첫 답이 틀린 문항은 첫 회차(1일 뒤)로 끌어당기고 ease 를 낮춘다.
-- 반대 방향(맞혔으니 더 미루기)은 하지 않는다 — 미루는 실수는 되돌릴 기회가 없고,
-- 학습지 안에서 한 번 맞힌 것이 안다는 뜻도 아니다(찍었을 수도 있다).

create or replace function public.seed_review_from_response()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 정답 키가 없는 활동(first_correct is null)과 맞힌 문항은 건드리지 않는다.
  if new.first_correct is not false or new.quiz_item_id is null then
    return new;
  end if;

  update public.review_schedules s
     set repetition    = 0,
         interval_days = 1,
         -- SM-2 의 ease 를 그대로 쓴다. 틀린 답 하나가 간격 전체를 천천히 늘어나게 만든다.
         ease          = greatest(s.ease - 0.3, 1.3),
         -- 이미 더 이른 일정이 잡혀 있으면 그대로 둔다. 늦추는 방향으로는 절대 움직이지 않는다.
         due_at        = least(s.due_at, now() + interval '1 day')
   where s.quiz_item_id = new.quiz_item_id
     and s.user_id      = new.user_id
     and s.state        = 'pending'
     -- 이미 당겨 놓은 것을 다시 당기지 않는다(같은 답을 여러 번 저장해도 결과가 같아야 한다).
     and (s.repetition > 0 or s.due_at > now() + interval '1 day');

  return new;
end;
$$;

drop trigger if exists responses_seed_review on public.responses;

-- insert 와 update 둘 다 본다. 앱은 같은 자리를 여러 번 덮어쓰며 저장한다(upsert).
create trigger responses_seed_review
  after insert or update of first_correct, quiz_item_id on public.responses
  for each row
  execute function public.seed_review_from_response();

revoke execute on function public.seed_review_from_response() from public, anon, authenticated;
