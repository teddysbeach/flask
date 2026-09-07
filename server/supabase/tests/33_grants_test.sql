-- 권한이 새는지 본다.
--
-- **뷰는 기본적으로 RLS 를 우회한다.** security_invoker 를 안 켠 뷰는 만든 사람의 권한으로
-- 돌기 때문에, 뷰에 SELECT 만 있으면 그 아래 테이블의 RLS 는 아무 소용이 없다.
-- Supabase 는 public 스키마의 새 뷰에 기본 권한을 주므로 **아무것도 안 적으면 열린 채로
-- 배포된다.** 실제로 네 개가 그렇게 열려 있었다(crash_summary·daily_funnel·
-- storage_orphans·quality_trend).
--
-- 이 테스트는 "새 뷰를 만들고 권한 회수를 잊는" 실수를 잡는다. 눈으로는 안 보인다.
\set ON_ERROR_STOP on

do $$
declare leaked text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into leaked
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('v', 'm')
    and (has_table_privilege('authenticated', c.oid, 'SELECT')
      or has_table_privilege('anon', c.oid, 'SELECT'));

  if leaked is not null then
    raise exception '사용자가 읽을 수 있는 운영 뷰: % — 뷰는 RLS 를 우회한다. revoke 를 잊었다', leaked;
  end if;
  raise notice '── 뷰 권한 테스트 전부 통과 ──';
end $$;

-- ── RLS 가 꺼진 테이블이 없는가 ──────────────────────────────────────────
do $$
declare open_tables text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into open_tables
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

  if open_tables is not null then
    raise exception 'RLS 가 꺼진 테이블: %', open_tables;
  end if;
  raise notice '── RLS 활성화 테스트 전부 통과 ──';
end $$;

-- ── 읽기 전용 공개 테이블에 쓰기 권한이 없는가 ───────────────────────────
-- RLS 가 이미 막지만, 정책 하나가 실수로 넓어졌을 때 권한이 두 번째 방벽이 된다.
do $$
declare t text; bad text := '';
begin
  foreach t in array array['notices', 'topic_picks', 'products', 'app_config', 'withdrawal_reasons']
  loop
    if has_table_privilege('authenticated', format('public.%I', t), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', t), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', t), 'DELETE') then
      bad := bad || t || ' ';
    end if;
  end loop;

  if bad <> '' then
    raise exception '읽기 전용이어야 하는 테이블에 쓰기 권한이 있다: %', bad;
  end if;
  raise notice '── 공개 테이블 쓰기 권한 테스트 전부 통과 ──';
end $$;

-- ── 텔레메트리·운영 테이블은 사용자에게서 완전히 닫혀 있는가 ─────────────
do $$
declare t text; bad text := '';
begin
  foreach t in array array['telemetry_events', 'crash_reports', 'manual_grants']
  loop
    if has_table_privilege('authenticated', format('public.%I', t), 'SELECT')
       or has_table_privilege('anon', format('public.%I', t), 'SELECT') then
      bad := bad || t || ' ';
    end if;
  end loop;

  if bad <> '' then
    raise exception '운영 전용 테이블이 사용자에게 열려 있다: %', bad;
  end if;
  raise notice '── 운영 테이블 차단 테스트 전부 통과 ──';
end $$;
