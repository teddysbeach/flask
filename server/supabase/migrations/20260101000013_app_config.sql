-- 앱 관문(점검 · 강제 업데이트).
--
-- 이 표가 있는 이유는 하나다. 사고가 났을 때 **스토어 심사를 기다리지 않고** 사용자를
-- 막거나 새 빌드로 밀어 올릴 수 있어야 한다. 앱에 박아 두면 그 판단이 며칠 늦는다.
--
-- 읽기는 **로그인 전에도** 되어야 한다. 부팅 첫 화면에서 읽는 값이라
-- 로그인해야 읽을 수 있으면 "점검 중" 을 정작 점검 때 못 띄운다.
-- 그래서 anon 에게도 select 를 연다. 여기엔 개인정보가 없다 — 공지 문구와 빌드 번호뿐이다.
-- 쓰기는 service_role 만. 정책을 하나도 안 만들면 그게 곧 "아무도 못 쓴다" 가 된다.

create table public.app_config (
  platform     text primary key check (platform in ('ios', 'android')),

  -- 이 번호보다 낮은 빌드는 들어올 수 없다(강제 업데이트). 0 이면 아무도 안 막는다.
  min_build    int  not null default 0,
  -- 최신 빌드. min_build 보다 크면 "권장 업데이트" 로만 안내한다.
  latest_build int  not null default 0,
  store_url    text,

  maintenance  boolean not null default false,
  -- 점검/업데이트 안내 문구. 그대로 사용자에게 보인다.
  message      text,
  -- 점검이 끝날 예정 시각. 모르면 null — 모르면서 아는 척 하지 않는다.
  until        timestamptz,
  updated_at   timestamptz not null default now(),

  constraint app_config_builds_nonneg check (min_build >= 0 and latest_build >= 0),
  constraint app_config_message_len check (message is null or char_length(message) <= 500)
);

comment on table public.app_config is
  '앱 부팅 관문. 로그인 전에 읽히므로 anon 도 select 할 수 있다(개인정보 없음). 쓰기는 서비스 롤만.';
comment on column public.app_config.min_build is
  '이 값보다 낮은 빌드는 강제 업데이트. 기본 0 — 아무도 막지 않는다.';

-- 기본 행. 없으면 첫 조회가 0행이 되고, 그때 관문이 어떻게 동작할지가 앱 코드에 달린다.
-- 통과가 기본이라는 사실을 데이터에도 적어 둔다.
insert into public.app_config (platform, min_build, latest_build, maintenance) values
  ('ios',     0, 0, false),
  ('android', 0, 0, false);

alter table public.app_config enable row level security;

-- 읽기는 누구나(로그인 전 포함). 쓰기 정책은 없다 = service_role 만 쓴다.
create policy app_config_select_all on public.app_config
  for select to anon, authenticated using (true);

-- Supabase 는 authenticated 에 테이블 단위 쓰기 권한을 기본으로 준다.
-- 정책만 없으면 막히긴 하지만, 권한 자체를 걷어내는 편이 실수에 강하다.
revoke insert, update, delete on public.app_config from anon, authenticated;
grant  select on public.app_config to anon, authenticated;
