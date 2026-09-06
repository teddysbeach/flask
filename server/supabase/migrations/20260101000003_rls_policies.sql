-- RLS. 모든 테이블 예외 없이 활성화한다.
-- 근거: docs/plan/03-data-model.md §3

alter table public.profiles                 enable row level security;
alter table public.products                 enable row level security;
alter table public.worksheets               enable row level security;
alter table public.quiz_items               enable row level security;
alter table public.prerequisite_suggestions enable row level security;
alter table public.annotations              enable row level security;
alter table public.review_schedules         enable row level security;
alter table public.generation_jobs          enable row level security;
alter table public.purchases                enable row level security;

-- ── profiles ────────────────────────────────────────────────────────────
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id);
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
-- INSERT 정책 없음: 가입 트리거(SECURITY DEFINER)만 만든다.

-- 쿼터 컬럼은 본인도 못 바꾼다. 변경은 SECURITY DEFINER 함수로만.
--
-- 주의: 컬럼 단위 revoke 만으로는 막히지 않는다. Postgres 는 테이블 단위 권한이 있으면
-- 컬럼 단위 revoke 를 무시한다("the table-level grant is unaffected by a column-level revoke").
-- Supabase 는 기본적으로 authenticated 에 테이블 단위 권한을 준다.
-- 그래서 테이블 권한을 걷어내고 허용할 컬럼만 다시 준다.
revoke update on public.profiles from authenticated, anon;
grant  update (display_name, locale, review_hour, timezone) on public.profiles to authenticated;

-- ── products : 활성 상품은 누구나 읽는다 (구매 화면) ─────────────────────
create policy products_select_active on public.products
  for select using (is_active);

-- ── worksheets ──────────────────────────────────────────────────────────
create policy worksheets_select_own on public.worksheets
  for select using (auth.uid() = user_id);
create policy worksheets_update_own on public.worksheets
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy worksheets_delete_own on public.worksheets
  for delete using (auth.uid() = user_id);
-- INSERT 정책 없음: 생성은 반드시 Edge Function(service_role)을 거친다.

-- 사용자가 바꿔도 되는 건 제목뿐. 나머지 컬럼은 서버 소유.
revoke update on public.worksheets from authenticated, anon;
grant  update (title) on public.worksheets to authenticated;

-- ── 읽기 전용 파생 테이블 ────────────────────────────────────────────────
create policy quiz_select_own on public.quiz_items
  for select using (auth.uid() = user_id);
create policy prereq_select_own on public.prerequisite_suggestions
  for select using (auth.uid() = user_id);
create policy review_select_own on public.review_schedules
  for select using (auth.uid() = user_id);
create policy jobs_select_own on public.generation_jobs
  for select using (auth.uid() = user_id);

-- 결제 원장은 읽기만. raw_receipt(영수증 원본)는 노출하지 않는다.
-- profiles 와 같은 이유로 테이블 권한을 걷고 컬럼만 허용한다.
create policy purchases_select_own on public.purchases
  for select using (auth.uid() = user_id);
revoke select on public.purchases from authenticated, anon;
grant  select (id, user_id, platform, product_id, transaction_id,
               quantity_granted, price_krw, state, purchased_at, refunded_at, created_at)
  on public.purchases to authenticated;

-- ── annotations : 필기는 사용자가 직접 쓴다 (Fn 경유는 낭비) ──────────────
create policy annotations_select_own on public.annotations
  for select using (auth.uid() = user_id);
create policy annotations_insert_own on public.annotations
  for insert with check (auth.uid() = user_id);
create policy annotations_update_own on public.annotations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy annotations_delete_own on public.annotations
  for delete using (auth.uid() = user_id);
