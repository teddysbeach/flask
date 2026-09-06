# server/supabase

ONPAR 백엔드. Supabase Postgres 스키마와 Edge Functions.

## 구조

```
migrations/   순서대로 적용되는 스키마 마이그레이션
functions/    Edge Functions (Deno)
  _shared/    공용 — 토큰 CSS(생성물), auth 검증, admin client
tests/        로컬 Postgres 검증
```

## 로컬 테스트

Supabase CLI 없이 **순수 Postgres 만으로** 마이그레이션과 정책을 검증한다.
`tests/00_shim.sql` 이 Supabase 가 제공하는 것들(`auth.users`, `auth.uid()`,
`storage.objects`, `anon`/`authenticated`/`service_role` 역할)을 흉내낸다.

```bash
./server/supabase/tests/run.sh
```

검증하는 것:

| 파일 | 내용 |
|---|---|
| `10_functions_test.sql` | 가입 트리거, 무료 2장 상한, 환불, 결제 지급·멱등성, 미등록 상품 거부, 환불 회수 |
| `20_rls_test.sql` | 남의 데이터 격리, 학습지 직접 INSERT 차단, 쿼터 컬럼·함수 직접 접근 차단 |
| `30_concurrency_test.sh` | **동시 요청에서 쿼터 초과 지급이 없는지** (워커 8 × 시도 40 = 320회) |

## 주의: 컬럼 단위 revoke 의 함정

Postgres 는 **테이블 단위 권한이 있으면 컬럼 단위 `revoke` 를 무시한다.**
Supabase 는 기본적으로 `authenticated` 에 테이블 권한을 주므로,
특정 컬럼만 막으려면 반드시 이 순서로 해야 한다.

```sql
revoke update on public.profiles from authenticated, anon;      -- 테이블 권한을 걷고
grant  update (display_name, locale) on public.profiles to authenticated;  -- 허용할 것만 다시
```

`revoke update (quota_total) ...` 만 쓰면 **아무것도 막히지 않는다.**
`20_rls_test.sql` 이 이걸 잡는다.

## 마이그레이션 규칙

- 파일명 `YYYYMMDDHHMMSS_설명.sql`, 사전순 = 적용순
- **적용된 마이그레이션은 수정하지 않는다.** 변경은 새 파일로.
- 모든 테이블은 예외 없이 RLS 활성화
- 쿼터·결제 조작은 전부 `SECURITY DEFINER` 함수로만, 실행 권한은 `service_role` 에만
