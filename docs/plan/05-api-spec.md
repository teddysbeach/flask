# 05. API 규격

## 1. 경계: Edge Function vs PostgREST

| 하는 일 | 경로 | 이유 |
|---|---|---|
| 학습지 생성 | **Edge Function** `POST /generate-worksheet` | LLM 키 보호 + 쿼터 원자성 |
| 생성 재시도 | **Edge Function** `POST /retry-worksheet` | 동일 |
| HTML 재렌더 | **Edge Function** `POST /render-worksheet-html` | 렌더러가 서버에만 존재 |
| 복습 채점 | **Edge Function** `POST /review-answer` | 간격 계산을 클라가 조작 못 하게 |
| 결제 영수증 검증 | **Edge Function** `POST /verify-purchase` | 클라이언트 신뢰 불가. 쿼터 지급의 유일한 경로 |
| 스토어 환불 알림 수신 | **Edge Function** `POST /store-webhook` | 스토어가 직접 호출 (JWT 없음, 서명 검증) |
| 학습지 목록/상세 조회 | PostgREST (RLS) | 단순 SELECT. Fn으로 감쌀 이유 없음 |
| 필기 저장/조회 | Storage + PostgREST (RLS) | 대용량. Fn 경유는 낭비 |
| 다가오는 복습 조회 | PostgREST (RLS) | 단순 SELECT |
| 프로필 조회 | PostgREST (RLS) | |
| 구매 내역 조회 | PostgREST (RLS) | 단순 SELECT (`raw_receipt` 제외) |

인증은 전부 Supabase JWT (`Authorization: Bearer <access_token>`).
Edge Function은 진입 시 `_shared/auth.ts` 로 JWT를 검증해 `user_id` 를 얻고,
DB 접근은 `service_role` 클라이언트로 한다 (RLS 우회는 Fn 안에서만).

## 2. Edge Function 엔드포인트

### `POST /functions/v1/generate-worksheet`

```jsonc
// 요청
{ "topic": "이벤트 소싱", "level": "beginner", "locale": "ko" }

// 202 Accepted
{ "worksheet_id": "uuid", "status": "queued", "quota_remaining": 1 }

// 402 Payment Required — 쿼터 소진 → 앱은 구매 화면으로
{ "error": "quota_exhausted", "quota_total": 2, "quota_used": 2, "product_id": "onpar.sheets.5" }

// 400 — topic 길이 위반(1~120자) / 금칙 입력
{ "error": "invalid_topic", "detail": "..." }

// 429 — 동시 생성 제한(사용자당 진행 중 잡 1개)
{ "error": "generation_in_progress", "worksheet_id": "uuid" }
```

처리 순서는 `01-architecture.md` §3 그대로. `consume_quota()` 성공 후에만 잡을 만든다.

### `POST /functions/v1/retry-worksheet`

```jsonc
{ "worksheet_id": "uuid" }   // → 202. status='failed' 인 학습지만 허용. 쿼터를 다시 차감한다.
```

### `POST /functions/v1/render-worksheet-html`

```jsonc
{ "worksheet_id": "uuid" }   // → 200 { "html_path": "...", "signed_url": "...", "expires_in": 3600 }
```
디자인 토큰이 바뀌었을 때 기존 학습지를 새 스타일로 다시 굽는 용도.
**주의**: 렌더러가 순수 함수이므로 DOM 구조는 동일 → 기존 필기 좌표 유지됨.

### `POST /functions/v1/verify-purchase`

```jsonc
// 요청 — 클라이언트가 스토어에서 받은 영수증/토큰을 그대로 올린다
{
  "platform": "ios",
  "product_id": "onpar.sheets.5",
  "receipt": "<Apple: signedTransactionInfo (JWS) / Google: purchaseToken>"
}

// 200 — 지급 완료 (이미 처리된 영수증도 200. 멱등)
{ "granted": 5, "quota_total": 7, "quota_used": 2, "purchase_id": "uuid", "already_processed": false }

// 400 — 영수증 검증 실패
{ "error": "invalid_receipt", "detail": "..." }

// 409 — 다른 계정에 이미 귀속된 트랜잭션
{ "error": "transaction_owned_by_other_user" }
```

**처리 순서**
1. JWT 로 `user_id` 확인
2. 플랫폼별 서버 검증 — Apple: App Store Server API 로 JWS 서명 검증 / Google: Play Developer API `purchases.products.get`
3. `product_id` 가 우리가 파는 상품인지, 상태가 `purchased` 인지 확인
4. `grant_quota_from_purchase()` 호출 — **`unique(platform, transaction_id)` 가 중복 지급을 막는다** (`03-data-model.md` §4)
5. 성공 응답 후에야 클라이언트가 트랜잭션을 `finish()` / `acknowledge()` 한다

**절대 하지 않는 것**: 클라이언트가 "결제 성공했다"고 말하는 것만 믿고 쿼터를 올리는 것.
영수증 검증은 전적으로 서버 몫이다.

**지급 실패 복구**: 결제는 됐는데 4번에서 실패(네트워크·서버 오류)하면 사용자는 돈만 내고 못 받는다.
→ 클라이언트는 **미완료 트랜잭션을 로컬에 큐잉**하고 앱 실행마다 재시도한다.
Apple `Transaction.updates` / Google `queryPurchasesAsync` 리스너를 항상 켜 둔다.
멱등이므로 몇 번을 재시도해도 안전하다.

### `POST /functions/v1/store-webhook`

App Store Server Notifications V2 / Google Play RTDN 수신.
`REFUND` / `REVOKE` 이벤트에 대해 `purchases.state = 'refunded'` + `quota_total` 차감.
JWT 대신 **스토어 서명 검증**으로 인증한다 (사용자 세션이 없는 호출이므로).

### `POST /functions/v1/review-answer`

```jsonc
// 요청
{ "review_id": "uuid", "grade": 2 }        // 0=모르겠음 1=어려움 2=보통 3=쉬움

// 200
{
  "correct_answer": "...",
  "explanation": "...",
  "next": { "review_id": "uuid", "due_at": "2026-09-20T09:00:00Z", "interval_days": 7 }
}
```
간격 계산(`07-review-notifications.md` §2)은 **서버에서만** 수행한다.

## 3. PostgREST 주요 쿼리 (앱에서 직접)

```dart
// 내 학습지 목록
supabase.from('worksheets')
  .select('id,title,topic,status,created_at,ready_at')
  .order('created_at', ascending: false).limit(50);

// 학습지 상세 + 문제 + 사전학습 제안 (임베디드 조인)
supabase.from('worksheets')
  .select('*, quiz_items(*), prerequisite_suggestions(*)')
  .eq('id', id).single();

// 로컬 알림 재스케줄용 — 다가오는 복습 (iOS 64개 한도 대응, 07번 §4)
supabase.from('review_schedules')
  .select('id,due_at,worksheet_id,quiz_item_id,quiz_items(question)')
  .eq('state', 'pending')
  .order('due_at')
  .limit(60);

// 생성 상태 실시간 구독
supabase.channel('ws:$worksheetId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update, schema: 'public', table: 'worksheets',
    filter: PostgresChangeFilter(type: eq, column: 'id', value: worksheetId),
    callback: ...)
  .subscribe();
```

## 4. 오류 코드 표

| 코드 | HTTP | 의미 | 앱 동작 |
|---|---|---|---|
| `quota_exhausted` | 402 | 잔여 쿼터 없음 | 구매 화면 (5장 1,900원) |
| `invalid_topic` | 400 | 주제 형식 위반 | 입력창 인라인 오류 |
| `generation_in_progress` | 429 | 이미 생성 중 | 진행 중 학습지로 이동 |
| `plan_schema_invalid` | — (잡 실패) | 설계 단계 스키마 위반 (재요청 후에도) | 재시도 버튼 + 쿼터 환불됨 |
| `draft_schema_invalid` | — (잡 실패) | 집필 단계 스키마 위반 (재요청 후에도) | 재시도 버튼 + 쿼터 환불됨 |
| `draft_contradicts_plan` | — (잡 실패) | 집필이 설계도의 사실 판단을 뒤집음 | 집필만 1회 재시도 |
| `llm_upstream_error` | — (잡 실패) | Claude API 5xx/429 | 해당 단계만 자동 재시도 2회 후 실패 |
| `llm_refused` | — (잡 실패) | 안전 정책상 거절 | "다른 주제로 시도" 안내 |
| `render_failed` | — (잡 실패) | 렌더러 예외 | 내부 알람 + 재시도 |
| `invalid_receipt` | 400 | 영수증 검증 실패 | 재시도 큐에 유지 + 고객문의 안내 |
| `transaction_owned_by_other_user` | 409 | 다른 계정에 귀속된 트랜잭션 | 고객문의 안내 |
| `unauthorized` | 401 | JWT 무효 | 재로그인 |

## 5. 관측 & 한도

- 모든 Edge Function 호출에 `request_id` (UUID) 부여, 로그·`generation_jobs` 에 기록.
- **비용 알람**: 장당 실비 목표 `$0.105`, 경보 `$0.12` (150원 = $0.107 @1,400원/USD).
  최근 100건 이동평균이 경보를 넘으면 자동 다운시프트(집필 분량 15% 축소 → `effort: "low"`).
  일일 총 LLM 지출이 임계치를 넘으면 `generate-worksheet` 를 소프트 차단(503 + 안내).
  단계별(`plan` / `draft`) `tokens_in/out` 을 각각 기록해 어느 쪽이 예산을 먹는지 분리 추적한다.
- 레이트리밋: 사용자당 진행 중 생성 잡 1개, 시간당 생성 시도 5회 (429).
- **월 신규 가입 상한**: 무료 2장 원가(266원/명)를 마케팅 예산에서 역산해 상한을 건다.
  초과 시 신규 가입을 대기자 명단으로 돌린다 (`00-overview.md` §7 권고 3).
- `usage.cache_read_input_tokens` 를 잡 로그에 남겨 프롬프트 캐시 히트율을 모니터링한다
  (0이 계속 나오면 시스템 프롬프트에 변동 값이 섞인 것 — `04-worksheet-spec.md` §4).
