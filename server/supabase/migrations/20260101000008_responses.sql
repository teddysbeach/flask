-- 학습 응답. "썼다"가 아니라 "무엇을 어떻게 썼다"를 남긴다.
--
-- 외부 평가: 서술형은 attempted=true 만 남아서 깊은 학습과 아무 말이나 쓰는 행위가 데이터상
-- 같았고, 선택형은 마지막 응답이 첫 응답을 덮어써서 첫 오답(= 그 학생의 오개념)이 사라졌다.
-- 학습분석에서 중요한 것은 first response → feedback → retry → final response 다.
-- 그래서 first_choice / final_choice / attempts 를 따로 둔다. attempts 는 append-only 이력이다.
--
-- 한 줄 = 문서 안의 응답 한 자리. 결정론적 렌더러가 내는 response_id(예: quiz-3)가 문서 내 좌표다.
-- quiz_item_id 는 연습 문제일 때만 채워진다(활동·예측·성찰 칸은 quiz_items 에 없다).

create table public.responses (
  id              uuid primary key default gen_random_uuid(),
  worksheet_id    uuid not null references public.worksheets(id) on delete cascade,
  user_id         uuid not null references public.profiles(id)   on delete cascade,
  response_id     text not null,                                   -- 문서 내 결정론적 id
  quiz_item_id    uuid references public.quiz_items(id) on delete set null,
  kind            text not null,
  first_choice    int,          -- 절대 덮어쓰지 않는다. 첫 선택이 오개념의 증거다.
  final_choice    int,
  correct         boolean,      -- 정답 키가 없는 활동은 null
  attempts        jsonb not null default '[]'::jsonb,               -- [{choice,text,correct,at,msSincePrompt}]
  text            text,         -- 서술형: 타이핑한 답 (필기만 했으면 null)
  chars           int  not null default 0,
  ink_strokes     int  not null default 0,
  ms_since_prompt int,          -- 그 자리가 처음 화면에 보인 시각 기준
  updated_at      timestamptz not null default now(),
  unique (worksheet_id, response_id),
  constraint responses_kind_valid      check (kind in ('choice', 'written')),
  constraint responses_counts_nonneg   check (chars >= 0 and ink_strokes >= 0),
  constraint responses_ms_nonneg       check (ms_since_prompt is null or ms_since_prompt >= 0),
  constraint responses_attempts_array  check (jsonb_typeof(attempts) = 'array')
);

comment on column public.responses.attempts is
  '시도 이력(append-only). 길이 2 이상이면 피드백을 보고 고쳤다는 뜻이다. 요소를 지우지 않는다.';
comment on column public.responses.ms_since_prompt is
  '첫 응답까지 걸린 시간. 기준은 그 요소가 처음 뷰포트에 보인 시각(IntersectionObserver).';

-- "이 학습지에서 뭘 틀렸나" (복습 화면) 와 "최근에 뭘 풀었나" (홈)
create index responses_worksheet_idx on public.responses (worksheet_id);
create index responses_user_recent_idx on public.responses (user_id, updated_at desc);
-- 오답 문항 모으기. 대부분의 행은 correct 가 참이거나 null 이라 인덱스가 작게 유지된다.
create index responses_wrong_idx on public.responses (user_id, quiz_item_id)
  where correct is false;

-- ── RLS : 응답은 사용자가 직접 쓴다 (필기와 같은 이유로 Fn 경유는 낭비) ──
alter table public.responses enable row level security;

create policy responses_select_own on public.responses
  for select using (auth.uid() = user_id);
create policy responses_insert_own on public.responses
  for insert with check (auth.uid() = user_id);
create policy responses_update_own on public.responses
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- DELETE 정책 없음: 응답은 지우지 않는다. 학습 이력을 지우는 건 데이터 손상이다.

-- 행의 정체(어느 학습지의 어느 자리인가)는 나중에 바뀔 수 없다. 바꿀 수 있으면
-- 남의 문항에 자기 응답을 붙이거나 이력을 세탁할 수 있다.
--
-- 주의: 컬럼 단위 revoke 만으로는 막히지 않는다. Postgres 는 테이블 단위 권한이 있으면
-- 컬럼 단위 revoke 를 무시한다("the table-level grant is unaffected by a column-level revoke").
-- Supabase 는 기본적으로 authenticated 에 테이블 단위 권한을 준다.
-- 그래서 테이블 권한을 걷어내고 허용할 컬럼만 다시 준다. (profiles · worksheets 와 같은 패턴)
revoke update, delete on public.responses from authenticated, anon;
grant  update (first_choice, final_choice, correct, attempts,
               text, chars, ink_strokes, ms_since_prompt, updated_at)
  on public.responses to authenticated;
