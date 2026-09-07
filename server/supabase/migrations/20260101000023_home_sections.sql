-- 홈에 얹을 것들: 공지·이벤트·추천 주제.
--
-- 셋 다 **서버가 정한다.** 앱에 박아 두면 문구 하나 고치는 데 스토어 심사를 기다려야 하고,
-- 점검 공지는 그 기다림 동안 아무 소용이 없다.

-- ── ① 공지에 종류와 행동을 더한다 ────────────────────────────────────────
--
-- 공지와 이벤트는 사는 곳이 같다(둘 다 "우리가 사용자에게 하는 말"). 다른 것은
-- **다음 행동이 있는가** 뿐이다 — 이벤트에는 누를 곳이 있고 공지에는 없다.
alter table public.notices
  add column if not exists kind text not null default 'notice',
  add column if not exists cta_label text,
  add column if not exists cta_route text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'notices_kind_valid') then
    alter table public.notices
      add constraint notices_kind_valid check (kind in ('notice', 'event'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'notices_cta_pair') then
    -- 라벨만 있고 갈 곳이 없으면 눌러도 아무 일이 안 일어난다. 둘은 함께 있거나 함께 없다.
    alter table public.notices
      add constraint notices_cta_pair
      check ((cta_label is null) = (cta_route is null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'notices_cta_len') then
    alter table public.notices
      add constraint notices_cta_len
      check (cta_label is null or char_length(cta_label) between 1 and 20);
  end if;
end $$;

comment on column public.notices.cta_route is
  '앱 내부 경로(/paywall 등). **앱이 허용 목록으로 한 번 더 거른다** — '
  '여기에 아무 경로나 넣어 사용자를 엉뚱한 곳으로 보낼 수 없어야 한다.';

-- ── ② 추천 주제 ─────────────────────────────────────────────────────────
--
-- "다른 사람들이 많이 만든 주제" 를 보여주고 싶은 유혹이 있다. **하지 않는다.**
-- 주제는 사용자가 쓴 글이고, 거기에는 "내 우울증 약 부작용" 같은 것이 들어온다.
-- 집계라도 원문이 화면에 나오는 순간 그건 유출이다.
--
-- 대신 우리가 고른다. 커뮤니티의 느낌(뭘 배우면 좋을지 남이 알려주는 것)은 그대로 얻으면서
-- 누구의 데이터도 쓰지 않는다.
create table if not exists public.topic_picks (
  id          uuid primary key default gen_random_uuid(),
  -- 만들기 화면에 그대로 채워질 문장. 사용자가 고쳐 쓸 수 있어야 하므로 짧게.
  topic       text not null,
  -- 12개 카테고리 중 하나(docs/plan/12-categories.md). 표시용 라벨이라 자유 문자열이다.
  category    text,
  blurb       text,
  sort_order  int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),

  constraint topic_picks_topic_len check (char_length(topic) between 1 and 120),
  constraint topic_picks_blurb_len check (blurb is null or char_length(blurb) <= 200)
);

create index if not exists topic_picks_active_idx on public.topic_picks (sort_order, created_at desc);

alter table public.topic_picks enable row level security;

-- 읽기는 누구나(로그인 전 온보딩에서도 보여줄 수 있게). 쓰기 정책은 두지 않는다 = 운영만.
create policy topic_picks_read_all on public.topic_picks
  for select to anon, authenticated using (active);

grant select on public.topic_picks to anon, authenticated;

-- 처음부터 비어 있으면 그 섹션은 없는 기능과 같다. 12개 카테고리에서 골고루 심어 둔다.
insert into public.topic_picks (topic, category, blurb, sort_order)
select * from (values
  ('미분이 왜 필요한지',            '수학',        '변화를 재는 도구가 어디서 왔는지', 10),
  ('이중슬릿 실험이 말해 주는 것',   '물리·화학',   '입자와 파동 사이에서',            20),
  ('해시 테이블이 빠른 이유',        '컴퓨터·개발', '한 번에 찾아가는 원리',           30),
  ('화이트밸런스가 하는 일',         '미술·디자인', '같은 장면이 다르게 보이는 이유',   40),
  ('복리가 무서운 이유',            '경제·금융',   '시간이 곱해지는 계산',            50),
  ('조선의 붕당이 갈라진 이유',      '역사·인문',   '사람이 아니라 구조를 본다',        60),
  ('습관이 만들어지는 구조',        '심리·자기이해', '의지가 아니라 신호와 보상',        70),
  ('발효가 일어나는 조건',          '요리·생활',   '눈에 안 보이는 일꾼들',           80)
) as seed(topic, category, blurb, sort_order)
where not exists (select 1 from public.topic_picks);
