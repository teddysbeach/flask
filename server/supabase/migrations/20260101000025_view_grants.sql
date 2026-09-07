-- 운영용 뷰를 사용자에게서 닫는다.
--
-- **뷰는 기본적으로 RLS 를 우회한다.** `security_invoker` 를 켜지 않은 뷰는 만든 사람의
-- 권한으로 실행되므로, 뷰에 SELECT 권한만 있으면 그 아래 테이블의 RLS 는 아무 소용이 없다.
-- 그래서 운영용 뷰는 권한 자체를 회수해야 한다 — 20260101000016 이 자기 뷰에 그렇게 했다.
--
-- 그런데 그 뒤에 만든 뷰들이 그 규칙을 놓쳤다. Supabase 는 public 스키마의 새 테이블·뷰에
-- anon/authenticated 기본 권한을 주므로, **아무것도 안 적으면 열린 채로 배포된다.**
--
-- 무엇이 새어 나가고 있었나:
--   crash_summary   다른 사용자의 크래시 메시지(경로·상태가 섞인다)
--   storage_orphans 다른 사용자의 스토리지 경로(경로에 user_id 가 들어 있다)
--   daily_funnel    전체 사용자 수와 결제 건수
--   quality_trend   전체 생성 비용과 품질 점수 (2026-01-01-000007 부터 열려 있었다)

revoke all on
  public.crash_summary,
  public.daily_funnel,
  public.storage_orphans,
  public.quality_trend
from public, anon, authenticated;

grant select on
  public.crash_summary,
  public.daily_funnel,
  public.storage_orphans,
  public.quality_trend
to service_role;

-- 앞으로 만들 뷰가 같은 실수를 반복하지 않도록, **기본값 자체를 닫는다.**
-- 이 저장소의 마이그레이션은 전부 이 스키마에 만들어지므로 여기 한 줄이 다음 뷰를 지킨다.
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- 읽기 전용 공개 테이블은 쓰기 권한을 거둔다. RLS 가 이미 막고 있지만,
-- 정책 하나가 실수로 넓어졌을 때 권한이 두 번째 방벽이 된다.
revoke insert, update, delete on public.notices from anon, authenticated;
revoke insert, update, delete on public.topic_picks from anon, authenticated;
revoke insert, update, delete on public.products from anon, authenticated;
revoke insert, update, delete on public.app_config from anon, authenticated;
revoke insert, update, delete on public.withdrawal_reasons from anon, authenticated;
