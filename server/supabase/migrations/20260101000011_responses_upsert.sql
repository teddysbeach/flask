-- 응답 저장이 실제로 되게 맞춘다. 앱을 붙이면서 드러난 세 가지.
--
-- 1) PostgREST 의 upsert 는 보낸 **모든** 컬럼을 DO UPDATE SET 에 넣는다.
--    앱은 행을 만들 때 user_id 와 quiz_item_id 를 보내야 하는데(NOT NULL, 그리고 어느 문항인지),
--    둘 다 update grant 목록에 없어서 두 번째 저장부터 권한 오류가 났다.
--    두 값은 한 번 정해지면 바뀌지 않는 것이라 "자기 값으로 다시 쓰는 것" 만 허용하면 된다.
--    그건 트리거로 막는다 — grant 를 넓히되 값이 바뀌면 거부한다.
--
-- 2) 서술형의 고쳐 쓴 이력과 선택형의 피드백 열람 여부가 갈 곳이 없었다.
--    학습분석에서 정답 자체보다 중요한 것이 **변화**인데, 그 변화를 담을 칸이 없었다.
--
-- 3) updated_at 은 앱이 보내는 값이 아니라 서버가 찍는 값이어야 한다.

-- ── 학습 과정을 담을 칸 ──────────────────────────────────────────────────
alter table public.responses
  add column if not exists feedback_seen     boolean not null default false,
  add column if not exists changed_mind      boolean not null default false,
  add column if not exists first_correct     boolean,
  -- [{chars, at}] — 몇 자에서 몇 자로 늘었는지. 답 자체가 아니라 쓰는 과정이다.
  add column if not exists revision_history  jsonb   not null default '[]'::jsonb,
  add column if not exists submitted_at      timestamptz;

-- ── upsert 가 통과하도록 권한을 넓힌다 ───────────────────────────────────
grant update (user_id, quiz_item_id, kind,
              first_choice, final_choice, correct, attempts,
              text, chars, ink_strokes, ms_since_prompt,
              feedback_seen, changed_mind, first_correct, revision_history, submitted_at,
              updated_at)
  on public.responses to authenticated;

-- ── 넓힌 권한이 새 구멍이 되지 않게 ──────────────────────────────────────
-- user_id 를 바꿀 수 있으면 남의 이름으로 응답을 옮길 수 있고,
-- quiz_item_id 를 바꿀 수 있으면 A 문항의 오답을 B 문항의 정답으로 둔갑시킬 수 있다.
create or replace function public.responses_guard_immutable()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception '응답의 소유자는 바꿀 수 없습니다' using errcode = '42501';
  end if;
  if old.quiz_item_id is not null and new.quiz_item_id is distinct from old.quiz_item_id then
    raise exception '응답이 가리키는 문항은 바꿀 수 없습니다' using errcode = '42501';
  end if;
  if new.worksheet_id is distinct from old.worksheet_id then
    raise exception '응답이 속한 학습지는 바꿀 수 없습니다' using errcode = '42501';
  end if;
  -- 시각은 서버가 찍는다. 앱이 보낸 값은 버린다.
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists responses_guard_immutable on public.responses;
create trigger responses_guard_immutable
  before update on public.responses
  for each row execute function public.responses_guard_immutable();
