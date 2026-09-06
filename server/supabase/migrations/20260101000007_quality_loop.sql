-- 검사 루프 도입. 학습지마다 검사관 점수와 재작성 횟수를 남긴다.
-- 이 값이 없으면 "학습지 품질이 떨어지고 있는가" 를 알 방법이 없다.

alter table public.worksheets
  add column quality_score int,
  add column revisions     int not null default 0,
  add constraint worksheets_quality_range check (quality_score is null or quality_score between 0 and 100);

alter table public.generation_jobs
  add column critic_tokens_in  int not null default 0,
  add column critic_tokens_out int not null default 0,
  add column quality_score     int,
  add column revisions         int not null default 0;

alter table public.generation_jobs
  drop constraint jobs_stage_valid,
  add constraint jobs_stage_valid check (stage in ('plan', 'draft', 'critic', 'revise', 'render', 'done'));

-- 품질 추이를 보는 뷰. 최근 100건의 점수 분포와 재작성 비율.
create or replace view public.quality_trend as
select
  date_trunc('day', finished_at) as day,
  count(*)                        as worksheets,
  round(avg(quality_score))       as avg_score,
  round(100.0 * avg(case when revisions > 0 then 1 else 0 end)) as pct_revised,
  round(avg(cost_usd)::numeric, 4) as avg_cost_usd
from public.generation_jobs
where status = 'succeeded'
group by 1 order by 1 desc;
