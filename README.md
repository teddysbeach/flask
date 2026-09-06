# Baewoom (배움) — 학습지 생성 앱

> 배우고 싶은 개념을 입력하면 **11개 섹션으로 구조화된 학습지**를 만들어주고,
> 아이패드에서 애플펜슬로 바로 필기하며 풀고,
> **망각곡선 주기에 맞춰 복습 문제를 로컬 알림으로** 보내주는 Flutter 앱.

**현재 상태: 기획 단계.** 아직 코드는 없고 계획 문서만 있다.

## 개요

| 항목 | 내용 |
|---|---|
| 앱 | Flutter (iPadOS 우선 → iOS → Android) |
| 디자인 | **popol.me/designsystem 준수** (토큰 SSOT → 앱 UI와 학습지 HTML 동시 적용) |
| 백엔드 | Supabase (Auth · Postgres + RLS · Storage · Realtime) |
| 학습지 생성 | Supabase Edge Functions에서 Claude API 호출 — **API 키는 서버에만** |
| 필기 | WebView 내부 Canvas + Pointer Events (Apple Pencil 필압) |
| 복습 | 에빙하우스 간격(1/3/7/16/35일) + SM-2 lite + 로컬 알림 |
| 무료 정책 | 계정당 학습지 2개 |

## 학습지 11개 섹션

1. 무엇을 배우는가 · 2. 이것이 생기기 전에는 / 왜 필요했는지 · 3. 사전학습 제안 3개 ·
4. 탄생 배경 · 5. 상황극 & 예시(사실 기반 또는 명시적 가상) · 6. 본론 · 7. 꿀팁 ·
8. 질의 5개 · 9. 숙제 & 과제 · 10. 마무리 팁 · 사용 예시 · 일상 적용 · 11. 다음 단계 제안

## 계획 문서

| 문서 | 내용 |
|---|---|
| [00. 제품 개요](docs/plan/00-overview.md) | 문제 정의, 가설, 스코프, 성공 지표 |
| [01. 아키텍처](docs/plan/01-architecture.md) | 시스템 구성, 기술 선택 근거, 폴더 구조 |
| [02. 디자인 시스템](docs/plan/02-design-system.md) | popol.me 토큰 계약 ⚠️ **값 미확보** |
| [03. 데이터 모델](docs/plan/03-data-model.md) | Supabase 스키마, RLS, 쿼터 원자성 |
| [04. 학습지 규격](docs/plan/04-worksheet-spec.md) | 11섹션 JSON 스키마, HTML 규격, LLM 호출 |
| [05. API 규격](docs/plan/05-api-spec.md) | Edge Function / PostgREST 경계, 오류 코드 |
| [06. 필기 레이어](docs/plan/06-annotation.md) | 아이패드 필기 설계, 좌표계, 동기화 |
| [07. 복습 & 알림](docs/plan/07-review-notifications.md) | 망각곡선, SM-2 lite, iOS 64개 한도 대응 |
| [08. 로드맵](docs/plan/08-roadmap.md) | M0~M5 마일스톤과 작업 분해 |
| [09. 미결정 사항](docs/plan/09-open-questions.md) | 질문 7개 + 리스크 10개 |

## 착수 전 블로커

1. **popol.me 디자인 토큰** — 현재 작업 환경에서 `popol.me` 도메인이 차단되어 값을 읽지 못했다.
   `design/design_tokens.json` 을 채워야 UI 구현을 시작할 수 있다. ([Q2](docs/plan/09-open-questions.md))
2. **Apple Pencil 필압 spike** — WKWebView 안에서 Pointer Events 필압이 나오는지 실기기 검증.
   결과가 필기 아키텍처를 확정한다. ([M0](docs/plan/08-roadmap.md))
3. **Supabase 프로젝트 / Anthropic API 키** ([Q5](docs/plan/09-open-questions.md))

## 레거시

`langhelper/` 는 이 레포의 이전 Flask 프로젝트이며 신규 프로젝트와 무관하다.
처리 방침 미정 — [Q7](docs/plan/09-open-questions.md) 참조.
