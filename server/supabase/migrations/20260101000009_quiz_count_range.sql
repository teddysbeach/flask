-- 문항 수 고정(5개)을 푼 뒤 남은 제약을 맞춘다.
--
-- V6 에서 "모든 학습지는 5문제" 를 없앴다. 문항 수는 분야가 정하고(4~7),
-- 무엇을 증거로 삼는지(evidence)가 개수를 대신한다 — docs/plan/15-robustness.md.
-- 그런데 quiz_items.idx 가 0~4 로 묶여 있어서 여섯 번째 문항부터 저장이 실패했다.
-- 검증기는 통과하고 DB 에서 터지는, 가장 늦게 발견되는 종류의 어긋남이다.
--
-- prerequisite_suggestions.idx 도 같은 이유로 푼다. 사전학습 섹션이 사라지고
-- exit_ticket.next_steps 의 easier 항목이 그 자리를 이어받았는데, 개수는 0~3 이다.

alter table public.quiz_items
  drop constraint if exists quiz_items_idx_range;
alter table public.quiz_items
  add constraint quiz_items_idx_range check (idx between 0 and 6);

alter table public.prerequisite_suggestions
  drop constraint if exists prereq_idx_range;
alter table public.prerequisite_suggestions
  add constraint prereq_idx_range check (idx between 0 and 2);
