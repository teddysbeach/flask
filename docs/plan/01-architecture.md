# 01. 아키텍처

## 1. 전체 구성

```
┌───────────────────────────────────────────────────────────┐
│  Flutter App (iPadOS / iOS / Android)                     │
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ 인증/홈/생성  │  │ 학습지 뷰어   │  │ 복습 큐         │  │
│  │              │  │ WebView+필기 │  │ 로컬 알림 스케줄 │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
│  packages/design_system  ← popol.me 토큰                   │
│  로컬 DB(Drift) : 학습지 캐시 · 필기 스트로크 · 복습 일정    │
└──────────┬─────────────────────────────┬──────────────────┘
           │ PostgREST (RLS)             │ HTTPS + JWT
           │ 읽기/단순 쓰기               │ 생성·쿼터·채점
           ▼                             ▼
┌────────────────────────┐   ┌──────────────────────────────┐
│ Supabase Postgres      │   │ Supabase Edge Functions      │
│  profiles              │◄──┤  generate-worksheet          │
│  worksheets            │   │  render-worksheet-html       │
│  quiz_items            │   │  review-answer               │
│  prerequisite_...      │   │  (service_role 로 DB 접근)    │
│  annotations           │   └───────────┬──────────────────┘
│  review_schedules      │               │ ANTHROPIC_API_KEY
│  generation_jobs       │               ▼
│  + RLS (auth.uid())    │   ┌──────────────────────────────┐
└────────────────────────┘   │ Claude API (claude-opus-5)   │
┌────────────────────────┐   │  구조화 출력 → 학습지 JSON    │
│ Supabase Storage       │   └──────────────────────────────┘
│  worksheets/{id}.html  │
│  annotations/{id}.json │
└────────────────────────┘
```

## 2. 기술 선택과 근거

| 영역 | 선택 | 근거 | 대안과 기각 이유 |
|---|---|---|---|
| 앱 | **Flutter 3.x (stable)** | 요구사항. iPad 우선, 단일 코드베이스 | — |
| 상태관리 | **Riverpod 2 (codegen)** | 비동기 상태(생성 잡, Realtime 구독)와 궁합. 테스트 용이 | Bloc: 보일러플레이트 과다 |
| 라우팅 | **go_router** | 알림 탭 → 딥링크(`/review/{id}`) 처리가 선언적 | Navigator 1.0: 딥링크 수작업 |
| 로컬 DB | **Drift (SQLite)** | 필기 스트로크·복습 일정의 오프라인 소스. 쿼리 필요 | Isar: 유지보수 리스크. Hive: 쿼리 약함 |
| 백엔드 | **Supabase** | 요구사항. Auth + Postgres + RLS + Storage + Realtime 한 벌 | — |
| 서버 로직 | **Supabase Edge Functions (Deno/TS)** | LLM 키를 클라이언트에 두지 않는다는 요구를 최소 인프라로 충족. Auth JWT 검증 내장 | 별도 Node 서버: 인프라·배포·비용 추가. v1엔 과함 |
| LLM | **Claude API, `claude-opus-5`** | 학습지 품질이 곧 제품. 무료 2장의 품질이 전환율 | 저가 모델은 "탄생 배경/상황극" 섹션에서 뻔해짐. `05-api-spec.md` 비용 분석 참조 |
| 필기 | **WebView 내부 Canvas + Pointer Events** | HTML 본문과 필기가 **같은 좌표계**를 공유 → 스크롤 동기화 문제가 원천 소멸 | Flutter CustomPaint 오버레이: WebView 스크롤 offset 브리지 필요, 지연·틀어짐 |
| 알림 | **flutter_local_notifications + timezone** | 요구사항이 로컬 알림. 서버 푸시 인프라 불필요 | FCM/APNs: v1 과잉 |

### Edge Function을 쓰되, 모든 걸 거기 두지는 않는다

**원칙: LLM 호출·쿼터·채점만 Edge Function. 나머지 읽기/쓰기는 PostgREST + RLS 직접 호출.**

RLS가 이미 행 단위 권한을 보장하므로, 학습지 목록 조회나 필기 저장까지 Edge Function으로 감싸면
콜드스타트 지연과 코드만 늘고 얻는 게 없다. 경계는 `05-api-spec.md`에 표로 고정한다.

## 3. 생성 파이프라인 (비동기 잡 패턴)

Edge Function은 벽시계 시간 제한이 있고, Opus 5로 8K 토큰짜리 학습지를 뽑으면 40~120초가 걸린다.
동기 HTTP 응답으로 처리하면 타임아웃·재시도 지옥에 빠진다. 따라서 **즉시 202 + 백그라운드 처리 + Realtime 구독**.

```
1. 앱   → POST /generate-worksheet {topic, level}
2. Fn   → consume_quota() 원자적 차감 (실패 시 402 반환, 여기서 종료)
3. Fn   → worksheets(status='queued') INSERT, generation_jobs INSERT
4. Fn   → 202 {worksheet_id} 즉시 반환          ← 앱은 여기서 로딩 화면
5. Fn   → EdgeRuntime.waitUntil(generate())     ← 응답 후에도 계속 실행
6.        Claude API 스트리밍 호출 (structured output)
7.        JSON 검증 → quiz_items / prerequisite_suggestions 분해 INSERT
8.        결정론적 렌더러로 HTML 조립 → Storage 업로드
9.        review_schedules 5회차 생성
10.       worksheets(status='ready', html_path=...) UPDATE
11. 앱   ← Supabase Realtime 이 worksheets 행 변경을 푸시 → 뷰어로 전환
```

**실패 시**: `status='failed'` + `error_code` 기록 → `refund_quota()` 호출로 쿼터 원복 →
앱은 "다시 시도" 버튼 노출 (재시도는 쿼터를 다시 차감).
잡 최대 재시도 2회, 지수 백오프. `generation_jobs.attempt` 로 추적.

### 왜 LLM에게 HTML을 만들게 하지 않는가

LLM이 HTML을 직접 뱉으면 (a) 태그가 깨지고 (b) 디자인 시스템 클래스를 매번 다르게 쓰고
(c) prompt injection이 곧 HTML injection이 된다.

> **LLM은 스키마가 고정된 JSON만 생성한다. HTML은 서버의 결정론적 템플릿 렌더러가 조립한다.**

이 규칙 하나로 렌더 안정성·디자인 일관성·XSS 방어가 동시에 해결된다. (`04-worksheet-spec.md`)

## 4. 폴더 구조

```
/
├─ app/                              # Flutter 앱
│  ├─ lib/
│  │  ├─ main.dart
│  │  ├─ core/                       # env, di, router, result, 에러 타입
│  │  ├─ data/
│  │  │  ├─ remote/                  # supabase client, edge fn client, dto
│  │  │  ├─ local/                   # drift db, dao
│  │  │  └─ repository/              # worksheet, annotation, review
│  │  ├─ domain/                     # entity, usecase
│  │  └─ features/
│  │     ├─ auth/                    # 로그인, 가입, 온보딩
│  │     ├─ home/                    # 내 학습지 목록, 남은 쿼터
│  │     ├─ create/                  # 주제 입력, 생성 대기 화면
│  │     ├─ worksheet/               # WebView 뷰어 + 필기 툴바
│  │     ├─ review/                  # 복습 카드, 알림 스케줄러
│  │     └─ settings/
│  ├─ assets/webview/                # 필기 런타임 JS/CSS (worksheet_runtime.js)
│  └─ test/
├─ packages/
│  └─ design_system/                 # popol.me 토큰 + 공용 위젯 (02번 문서)
│     ├─ lib/src/tokens/             # 생성물 (design_tokens.json → dart)
│     └─ lib/src/components/
├─ server/
│  └─ supabase/
│     ├─ migrations/                 # 001_init.sql, 002_rls.sql, ...
│     ├─ functions/
│     │  ├─ _shared/                 # auth 검증, supabase admin client, 에러
│     │  ├─ generate-worksheet/
│     │  ├─ render-worksheet-html/   # 렌더러 (재렌더용, 생성 시엔 내부 호출)
│     │  └─ review-answer/
│     └─ seed.sql
├─ design/
│  ├─ design_tokens.json             # 단일 진실 공급원 (SSOT)
│  └─ build_tokens.dart              # → dart 토큰 + worksheet.css 동시 생성
├─ docs/plan/                        # 이 문서들
└─ legacy/langhelper/                # 기존 Flask 코드 (Q7 참조)
```

## 5. 환경 / 시크릿

| 이름 | 위치 | 비고 |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | 앱 (`--dart-define`) | 공개 가능. RLS가 방어선 |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret | **앱에 절대 넣지 않음** |
| `ANTHROPIC_API_KEY` | Edge Function secret | **앱에 절대 넣지 않음** |
| `WORKSHEET_MODEL` | Edge Function secret | 기본 `claude-opus-5` |

`.env`, `*.secrets.json`, `supabase/.env` 는 `.gitignore`에 추가한다.
앱 빌드는 `--dart-define-from-file=env/dev.json` 방식으로 dev/prod 분리.
