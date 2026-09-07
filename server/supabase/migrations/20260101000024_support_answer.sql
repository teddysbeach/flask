-- 문의에 답을 담을 자리.
--
-- 지금까지는 status 만 있었다(open/answered/closed). 그래서 "답변됨" 이라고 표시해도
-- **답이 어디에도 없었다.** 사용자는 접수 번호를 받고 그것으로 아무것도 할 수 없었다.
-- 문의는 보내는 것이 아니라 답을 받는 것이라, 답이 없으면 절반만 만든 기능이다.

alter table public.support_tickets
  add column if not exists answer text,
  add column if not exists answered_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'support_tickets_answer_len') then
    alter table public.support_tickets
      add constraint support_tickets_answer_len
      check (answer is null or char_length(answer) between 1 and 4000);
  end if;
  -- 답을 적었으면 시각도 있어야 한다. 사용자에게 "언제 답이 왔는지" 는 답만큼 중요하다.
  if not exists (select 1 from pg_constraint where conname = 'support_tickets_answer_pair') then
    alter table public.support_tickets
      add constraint support_tickets_answer_pair
      check ((answer is null) = (answered_at is null));
  end if;
end $$;

comment on column public.support_tickets.answer is
  '운영이 적는 답변. 사용자는 자기 문의에 달린 답만 읽는다(support_tickets_select_own).';

-- 답을 다는 것은 운영(서비스 롤)만. 사용자에게 update 권한이 없다는 사실은 그대로다.
create or replace function public.answer_support_ticket(
  p_ticket uuid,
  p_answer text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.support_tickets
     set answer = p_answer,
         answered_at = now(),
         status = 'answered'
   where id = p_ticket;
  if not found then
    raise exception '문의를 찾지 못했어요: %', p_ticket;
  end if;
end $$;

revoke all on function public.answer_support_ticket(uuid, text) from public, anon, authenticated;
grant execute on function public.answer_support_ticket(uuid, text) to service_role;
