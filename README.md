# ONPAR (온파) — 학습지 생성 앱

**ONPAR** = 온(전부의·온전한) + par(라틴어·스페인어·영어: 동등한) — *"모두가 같은 자리에서 배운다."*

> 배우고 싶은 개념을 입력하면 **11개 섹션으로 구조화된 학습지**를 만들어주고,
> 아이패드에서 애플펜슬로 바로 필기하며 풀고,
> **망각곡선 주기에 맞춰 복습 문제를 로컬 알림으로** 보내주는 Flutter 앱.

**현재 상태: 기획 단계.** 아직 코드는 없고 계획 문서만 있다.

## 개요

| 항목 | 내용 |
|---|---|
| 앱 | Flutter (iPadOS 우선 → iOS → Android) |
| 디자인 | **[Orca Design System](https://github.com/stablyai/orca)** (MIT) 기반 — 토큰 SSOT 하나로 앱 UI와 학습지 HTML 동시 적용, 언제든 교체 가능 |
| 백엔드 | Supabase (Auth · Postgres + RLS · Storage · Realtime) |
| 학습지 생성 | Edge Functions에서 2단계 호출 — 설계 `claude-opus-5` → 집필 `claude-sonnet-5`. **API 키는 서버에만** |
| 필기 | WebView 내부 Canvas + Pointer Events (Apple Pencil 필압) |
| 복습 | 에빙하우스 간격(1/3/7/16/35일) + SM-2 lite + 로컬 알림 |
| 무료 정책 | 계정당 학습지 2개 (장당 생성 실비 150원 이내) |
| 유료 | 인앱결제 소모성 팩 — 3장 4,900원 / **10장 12,900원** / 30장 29,900원 |

## 학습지 11개 섹션

1. 무엇을 배우는가 · 2. 이것이 생기기 전에는 / 왜 필요했는지 · 3. 사전학습 제안 3개 ·
4. 탄생 배경 · 5. 상황극 & 예시(사실 기반 또는 명시적 가상) · 6. 본론 · 7. 꿀팁 ·
8. 질의 5개 · 9. 숙제 & 과제 · 10. 마무리 팁 · 사용 예시 · 일상 적용 · 11. 다음 단계 제안

## 계획 문서

| 문서 | 내용 |
|---|---|
| [00. 제품 개요](docs/plan/00-overview.md) | 문제 정의, 가설, 스코프, 성공 지표, **유닛 이코노믹스** |
| [01. 아키텍처](docs/plan/01-architecture.md) | 시스템 구성, 기술 선택 근거, 폴더 구조 |
| [02. 디자인 시스템](docs/plan/02-design-system.md) | Orca 토큰, 브랜드 액센트, 교체 절차 |
| [03. 데이터 모델](docs/plan/03-data-model.md) | Supabase 스키마, RLS, 쿼터 원자성, 결제 원장 |
| [04. 학습지 규격](docs/plan/04-worksheet-spec.md) | 11섹션 JSON 스키마, HTML 규격, 2단계 LLM 호출·비용 예산 |
| [05. API 규격](docs/plan/05-api-spec.md) | Edge Function / PostgREST 경계, 영수증 검증, 오류 코드 |
| [06. 필기 레이어](docs/plan/06-annotation.md) | 아이패드 필기 설계, 좌표계, 동기화 |
| [07. 복습 & 알림](docs/plan/07-review-notifications.md) | 망각곡선, SM-2 lite, iOS 64개 한도 대응 |
| [08. 로드맵](docs/plan/08-roadmap.md) | M0~M5 마일스톤과 작업 분해 |
| [09. 미결정 사항](docs/plan/09-open-questions.md) | 질문 7개 + 리스크 10개 |
| [10. 가격 설계](docs/plan/10-pricing.md) | 가격 3종, 유닛 이코노믹스, 실측 후 조정 규칙 |

## 디자인 교체

디자인은 **`design/design_tokens.json` 하나가 유일한 교체 지점**이다.
값만 바꾸고 `dart run design/build_tokens.dart` 를 돌리면 Flutter 테마와 학습지 CSS가 함께 다시 생성된다.
앱 코드도 학습지 렌더러도 한 줄 고치지 않는다. 코드에 색·간격·서체 리터럴이 없도록 CI가 강제한다.

## 유닛 이코노믹스

장당 생성 원가 133원, 무료 2장은 원가만 266원/가입자(사실상 CAC).
가격은 **손익분기 결제 전환율**을 기준으로 설계했다.

| 상품 | 마진 (수수료 15%) | 손익분기 전환율 |
|---|---|---|
| ~~5장 1,900원 (초기안)~~ | ~~803원~~ | ~~33.1%~~ ❌ |
| 3장 4,900원 | 3,387원 | 7.9% |
| **10장 12,900원** | **8,638원** | **3.1%** |
| 30장 29,900원 | 19,115원 | 1.4% |

전체 손익분기 전환율 약 **2.1%**. 스토어 수수료 30%를 내더라도 흑자다.
상세는 [10. 가격 설계](docs/plan/10-pricing.md).

**최우선 조치**: Apple Small Business Program / Google Play 소규모 사업자 등록
(신청만으로 수수료 30% → 15%).

## 착수 전 블로커

1. **Apple Pencil 필압 spike** — WKWebView 안에서 Pointer Events 필압이 나오는지 실기기 검증.
   결과가 필기 아키텍처를 확정한다. ([M0](docs/plan/08-roadmap.md))
2. **Supabase 프로젝트 / Anthropic API 키** ([Q5](docs/plan/09-open-questions.md))

## 라이선스 고지

Orca Design System — MIT, Copyright (c) 2026 Lovecast Inc.
Geist / Pretendard — SIL Open Font License 1.1.
