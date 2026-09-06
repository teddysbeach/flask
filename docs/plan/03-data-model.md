# 03. 데이터 모델 (Supabase Postgres)

## 1. ERD 개요

```
auth.users ─1:1─ profiles
                    │1
                    ├──N worksheets ──1:N quiz_items
                    │        │        ├─1:N prerequisite_suggestions
                    │        │        ├─1:1 annotations
                    │        │        └─1:N generation_jobs
                    │
                    └──N review_schedules ──► quiz_items (복습할 문제)
```

## 2. 테이블

### `profiles`

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `id` | `uuid` PK | `references auth.users(id) on delete cascade` |
| `display_name` | `text` | |
| `quota_total` | `int not null default 2` | **기본 2개 학습지** |
| `quota_used` | `int not null default 0` | |
| `locale` | `text default 'ko'` | |
| `created_at` | `timestamptz default now()` | |

- `check (quota_used >= 0 and quota_used <= quota_total)` — DB 레벨에서 초과 차단.
- `auth.users` INSERT 트리거로 자동 생성 (`handle_new_user()`).

### `worksheets`

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `id` | `uuid PK default gen_random_uuid()` | |
| `user_id` | `uuid not null` → profiles | |
| `topic` | `text not null` | 사용자 원문 입력 |
| `level` | `text not null default 'beginner'` | `beginner`/`intermediate`/`advanced` |
| `status` | `text not null default 'queued'` | `queued`→`generating`→`ready` / `failed` |
| `content` | `jsonb` | 11섹션 전체 (`04-worksheet-spec.md` 스키마) |
| `html_path` | `text` | Storage 경로 `worksheets/{user_id}/{id}.html` |
| `title` | `text` | LLM이 정한 학습지 제목 |
| `error_code` | `text` | 실패 시 |
| `model` | `text` | 생성 모델 ID (재현성) |
| `prompt_version` | `text` | 프롬프트 버전 (품질 A/B용) |
| `tokens_in` / `tokens_out` | `int` | 비용 추적 |
| `created_at` / `ready_at` | `timestamptz` | |

인덱스: `(user_id, created_at desc)`, `(status)` (부분: `where status in ('queued','generating')`).

### `quiz_items`

학습지 질의 5개. **복습 스케줄이 이 행을 참조**하므로 `content` jsonb에 묻지 않고 별도 테이블로 승격.

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `id` | `uuid PK` | |
| `worksheet_id` | `uuid not null` (cascade) | |
| `user_id` | `uuid not null` | RLS 단순화를 위한 비정규화 |
| `idx` | `int not null` | 0..4 |
| `question` | `text not null` | |
| `kind` | `text not null` | `short_answer` / `multiple_choice` / `explain` |
| `choices` | `jsonb` | MC일 때만 |
| `answer` | `text not null` | |
| `explanation` | `text not null` | |
| `difficulty` | `int` | 1~3 |

`unique (worksheet_id, idx)`.

### `prerequisite_suggestions`

사전학습 제안 3개. 별도 테이블로 두면 "제안 → 실제 생성" 전환 추적이 된다.

| 컬럼 | 타입 |
|---|---|
| `id` `uuid PK` / `worksheet_id` / `user_id` / `idx` (0..2) |
| `title` `text` — 제안 주제명 |
| `why` `text` — 왜 먼저 배워야 하는지 |
| `spawned_worksheet_id` `uuid null` — 이 제안으로 실제 생성된 학습지 |

### `annotations`

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `worksheet_id` | `uuid PK` (1:1) | |
| `user_id` | `uuid not null` | |
| `format_version` | `int not null default 1` | 스트로크 포맷 버전 |
| `strokes_path` | `text` | Storage `annotations/{user_id}/{worksheet_id}.json.gz` |
| `stroke_count` | `int` | |
| `bytes` | `int` | |
| `rev` | `bigint not null default 0` | 낙관적 동시성 (기기 간 충돌 감지) |
| `updated_at` | `timestamptz` | |
| `updated_by_device` | `text` | |

스트로크 본문은 수 MB가 될 수 있어 Postgres가 아니라 **Storage에 gzip JSON**으로 둔다.
테이블에는 메타만. (`06-annotation.md` §4)

### `review_schedules`

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `id` | `uuid PK` | |
| `user_id` / `worksheet_id` / `quiz_item_id` | `uuid not null` | |
| `repetition` | `int not null default 0` | 회차 (0=1일차) |
| `interval_days` | `int not null` | 현재 간격 |
| `ease` | `numeric not null default 2.5` | SM-2 ease factor |
| `due_at` | `timestamptz not null` | |
| `state` | `text not null default 'pending'` | `pending`/`done`/`skipped`/`retired` |
| `grade` | `int` | 응답 체감 난이도 0~3 |
| `answered_at` | `timestamptz` | |
| `notified_at` | `timestamptz` | 로컬 알림 발화 기록 |

인덱스: `(user_id, state, due_at)` — "다가오는 복습 N개" 조회의 핵심.

### `purchases`

인앱결제 원장. **영수증 검증에 성공한 것만 기록되며, 이 표가 쿼터 지급의 유일한 근거다.**

| 컬럼 | 타입 | 비고 |
|---|---|---|
| `id` | `uuid PK` | |
| `user_id` | `uuid not null` | |
| `platform` | `text not null` | `ios` / `android` |
| `product_id` | `text not null` | `onpar.sheets.3` / `.10` / `.30` |
| `transaction_id` | `text not null` | 스토어 트랜잭션 ID |
| `original_transaction_id` | `text` | Apple 환불 알림 매칭용 |
| `quantity_granted` | `int not null` | 지급 장수. **서버 카탈로그 기준** (3/10/30) |
| `price_krw` | `int` | 표시가 (4900 / 12900 / 29900) |
| `state` | `text not null default 'granted'` | `granted` / `refunded` / `revoked` |
| `raw_receipt` | `jsonb` | 검증 응답 원본 (분쟁 대응) |
| `purchased_at` / `created_at` | `timestamptz` | |
| `refunded_at` | `timestamptz` | |

**`unique (platform, transaction_id)`** — 이 제약 하나가 **중복 지급을 막는 핵심**이다.
재시도·네트워크 오류로 같은 영수증이 두 번 들어와도 두 번째는 DB가 거부한다.

인덱스: `(user_id, purchased_at desc)`, `(original_transaction_id)`.

### `generation_jobs`

| 컬럼 | 타입 |
|---|---|
| `id` `uuid PK` / `worksheet_id` / `user_id` |
| `attempt` `int not null default 1` |
| `status` `text` — `running`/`succeeded`/`failed` |
| `error_code` `text` / `error_detail` `text` |
| `started_at` / `finished_at` `timestamptz` |
| `duration_ms` `int` / `tokens_in` / `tokens_out` `int` |

운영 대시보드(성공률·p95 지연·비용)의 소스.

## 3. RLS 정책

**모든 테이블 `enable row level security`. 예외 없음.**

```sql
-- 패턴 (worksheets 예시). 나머지 테이블도 동일 형태.
create policy "own_select" on worksheets
  for select using (auth.uid() = user_id);
create policy "own_update" on worksheets
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- INSERT 는 정책을 주지 않는다: 학습지 생성은 반드시 Edge Function(service_role)을 통해서만.
```

| 테이블 | select | insert | update | delete |
|---|---|---|---|---|
| `profiles` | 본인 | 트리거만 | 본인 (단 `quota_*` 는 컬럼 권한으로 차단) | ✕ |
| `worksheets` | 본인 | ✕ (Fn만) | 본인 (title 수정 정도) | 본인 |
| `quiz_items` | 본인 | ✕ | ✕ | cascade |
| `prerequisite_suggestions` | 본인 | ✕ | ✕ | cascade |
| `annotations` | 본인 | 본인 | 본인 | 본인 |
| `review_schedules` | 본인 | ✕ | ✕ (채점은 Fn) | ✕ |
| `generation_jobs` | 본인 | ✕ | ✕ | ✕ |
| `purchases` | 본인 (`raw_receipt` 제외) | ✕ (Fn만) | ✕ | ✕ |

**중요**: `profiles.quota_total` / `quota_used` 는 클라이언트가 절대 못 바꾸게 한다.
Postgres 컬럼 단위 GRANT (`revoke update (quota_total, quota_used) on profiles from authenticated`)
로 막고, 변경은 아래 SECURITY DEFINER 함수로만.

Storage 버킷 `worksheets`, `annotations` 는 **private**. 접근은 서명 URL(유효기간 1시간) 또는
`storage.objects` RLS에 `(storage.foldername(name))[1] = auth.uid()::text` 정책.

## 4. 쿼터 — 원자적 차감/환불

동시 요청으로 무료 2개를 3개 만드는 레이스를 DB 한 문장으로 막는다.

```sql
create or replace function consume_quota(p_user uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  update profiles
     set quota_used = quota_used + 1
   where id = p_user and quota_used < quota_total
  returning true into ok;
  return coalesce(ok, false);
end $$;

create or replace function refund_quota(p_user uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update profiles set quota_used = greatest(quota_used - 1, 0) where id = p_user;
end $$;
```

- `WHERE quota_used < quota_total` 가 행 잠금 + 조건을 한 번에 처리 → 레이스 불가.
- `execute` 권한은 `service_role` 에만 부여. `authenticated` 에서 회수.
- 생성 실패 시 반드시 `refund_quota`. 단 **부분 성공(HTML까지 만들어짐)은 환불하지 않는다.**

### 결제 지급 — 중복 방지가 내장된 한 트랜잭션

```sql
create or replace function grant_quota_from_purchase(
  p_user uuid, p_platform text, p_product_id text,
  p_transaction_id text, p_original_transaction_id text,
  p_quantity int, p_price_krw int, p_receipt jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  -- unique(platform, transaction_id) 위반 시 아무것도 하지 않고 기존 행을 돌려준다.
  -- 재시도가 몇 번 들어와도 지급은 정확히 한 번.
  insert into purchases (user_id, platform, product_id, transaction_id,
                         original_transaction_id, quantity_granted, price_krw, raw_receipt)
  values (p_user, p_platform, p_product_id, p_transaction_id,
          p_original_transaction_id, p_quantity, p_price_krw, p_receipt)
  on conflict (platform, transaction_id) do nothing
  returning id into v_id;

  if v_id is null then                        -- 이미 처리된 영수증
    select id into v_id from purchases
     where platform = p_platform and transaction_id = p_transaction_id;
    return v_id;
  end if;

  update profiles set quota_total = quota_total + p_quantity where id = p_user;
  return v_id;
end $$;
```

환불 회수(`revoke_quota_from_purchase`)도 같은 형태로 둔다. 스토어 환불 알림이 오면
`purchases.state = 'refunded'` 로 바꾸고 `quota_total` 에서 차감한다.
**단, 이미 써버린 장수는 회수하지 않는다** (`quota_used` 는 건드리지 않는다 —
`quota_used > quota_total` 이 되면 생성이 자연스럽게 막힌다).

## 5. 마이그레이션 파일

```
server/supabase/migrations/
  20260101000001_init_tables.sql
  20260101000002_rls_policies.sql
  20260101000003_quota_functions.sql
  20260101000004_new_user_trigger.sql
  20260101000005_storage_buckets.sql
  20260101000006_indexes.sql
```

로컬 개발은 `supabase start` → `supabase db reset` 로 재현. CI에서 마이그레이션 드라이런 검증.
