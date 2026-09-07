-- 공지.
--
-- 왜 지금 만드는가: 앱에는 이미 /notices 로 가는 길이 둘 있었다 —
-- Routes.notices 상수와 딥링크 파서(deep_links.dart). 그런데 **라우터에 그 경로가 없어서**
-- 공지 링크를 누르면 "없는 페이지" 에 떨어졌다. 화면을 만들려면 읽을 곳이 있어야 한다.
--
-- 로그인 없이 읽힌다. 점검 공지는 로그인이 안 될 때 가장 필요하다.

create table if not exists public.notices (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null,
  -- 상단 고정. 점검처럼 지금 당장 알아야 하는 것에만 쓴다.
  pinned       boolean not null default false,
  -- 게시 시각. 미래로 잡아 두면 그때부터 보인다(예약 공지).
  published_at timestamptz not null default now(),
  -- 지난 공지를 감출 때. null 이면 계속 보인다.
  expires_at   timestamptz,
  created_at   timestamptz not null default now(),

  constraint notices_title_len check (char_length(title) between 1 and 200),
  constraint notices_body_len check (char_length(body) between 1 and 8000)
);

-- 부분 인덱스에 now() 를 못 쓴다(IMMUTABLE 이 아니다). 목록이 짧아 전체 인덱스로 충분하다.
create index if not exists notices_visible_idx
  on public.notices (pinned desc, published_at desc);

alter table public.notices enable row level security;

-- 읽기는 누구나. 쓰기 정책은 두지 않는다 = service_role(운영)만 쓴다.
create policy notices_read_all on public.notices
  for select to anon, authenticated
  using (published_at <= now() and (expires_at is null or expires_at > now()));

grant select on public.notices to anon, authenticated;
