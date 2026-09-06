-- 인덱스. 근거: docs/plan/03-data-model.md

create index worksheets_user_created_idx
  on public.worksheets (user_id, created_at desc);

-- 진행 중인 잡만 훑는 부분 인덱스 (대부분의 행은 ready 라 인덱스가 작게 유지된다)
create index worksheets_active_status_idx
  on public.worksheets (status)
  where status in ('queued', 'generating');

create index quiz_items_worksheet_idx
  on public.quiz_items (worksheet_id, idx);

create index prereq_worksheet_idx
  on public.prerequisite_suggestions (worksheet_id, idx);

-- "다가오는 복습 N개" 조회의 핵심. 로컬 알림 재스케줄러가 매번 때린다.
create index review_due_idx
  on public.review_schedules (user_id, state, due_at);

create index review_worksheet_idx
  on public.review_schedules (worksheet_id);

create index jobs_worksheet_idx
  on public.generation_jobs (worksheet_id, attempt);

create index jobs_cost_window_idx
  on public.generation_jobs (finished_at desc)
  where status = 'succeeded';

create index purchases_user_idx
  on public.purchases (user_id, purchased_at desc);

create index purchases_original_txn_idx
  on public.purchases (original_transaction_id)
  where original_transaction_id is not null;
