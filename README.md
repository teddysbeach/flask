# ONPAR (온파) — 학습지 생성 앱

**ONPAR** = 온(전부의·온전한) + par(라틴어·스페인어·영어: 동등한) — *"모두가 같은 자리에서 배운다."*

> 배우고 싶은 개념을 입력하면 **6단계(문제 제시 → 예측 → 관찰 → 개념 → 연습 → 나가기 전에)로 구조화된 학습지**를 만들어주고,
> 아이패드에서 애플펜슬로 바로 필기하며 풀고,
> **망각곡선 주기에 맞춰 복습 문제를 로컬 알림으로** 보내주는 Flutter 앱.

**현재 상태: 서버·학습지 엔진 구현 완료, Flutter 앱 미착수.**
학습지 계약·검증기·렌더러·검사 루프·필기 런타임·DB(RLS·동시성)는 돌아가고 테스트로 고정돼 있다.
남은 것은 Flutter 앱과 인프라 계정(`09-open-questions.md` Q5)이다.

**제품 원칙은 로버스트니스다** — [15. 로버스트니스](docs/plan/15-robustness.md).
정상 케이스에서 잘 설명되는 학습지가 아니라, 오해·예외·입력 실패·기기 차이에서도 개념이 무너지지 않는 학습지를 만든다.
그래서 아래 넷은 취향이 아니라 스키마 필드이고, 어기면 빌드가 깨진다.

| 장치 | 막는 것 |
|---|---|
| `boundary` (성립 조건 · 깨지는 경우) | 입문용 단순화가 절대법칙으로 굳는 것 |
| `model_note` (이 그림이 생략한 것) | 모형을 현실로 착각하는 것 |
| `evidence` (문항이 무엇을 증거로 삼는가) | 절차 숙련을 개념 이해로 오인하는 것 |
| `robustness.guards` (막아야 할 오해 3~5개) | 예상 가능한 실패를 안 막고 넘어가는 것 |

그리고 **근거 없는 숫자 정밀도를 만들지 않는다**: 정성 모형의 눈금은 낮음/중간/높음까지다.

## 개요

| 항목 | 내용 |
|---|---|
| 앱 | Flutter (iPadOS 우선 → iOS → Android) |
| 디자인 | **[SEED Design System](https://github.com/daangn/seed-design)** (Apache 2.0) + **Untitled UI Icons** (MIT) — 토큰 SSOT 하나로 앱 UI와 학습지 HTML 동시 적용 |
| 백엔드 | Supabase (Auth · Postgres + RLS · Storage · Realtime) |
| 학습지 생성 | Edge Functions에서 2단계 호출 — 설계 `claude-opus-5` → 집필 `claude-sonnet-5`. **API 키는 서버에만** |
| 필기 | WebView 내부 Canvas + Pointer Events (Apple Pencil 필압) |
| 복습 | 에빙하우스 간격(1/3/7/16/35일) + SM-2 lite + 로컬 알림 |
| 무료 정책 | 계정당 학습지 2개 (장당 생성 실비 약 300원 — 검사 루프 포함) |
| 유료 | 인앱결제 소모성 팩 — 3장 4,900원 / **10장 12,900원** / 30장 29,900원 |

## 학습지 6단계

| # | 단계 | 학생이 하는 것 |
|---|---|---|
| 1 | 문제 제시 | 아직 못 푸는 구체적 상황 하나를 본다 (개념 이름으로 시작하지 않는다) |
| 2 | 예측 | 설명을 읽기 전에 고른다 — 흔한 오답이 선택지에 있다 — 그리고 이유를 한 줄 쓴다 |
| 3 | 관찰 | 도형·데이터·예시를 보고 예측과 비교한다. 설명은 아직 없다 |
| 4 | 개념 | 본 것에 이름을 붙인다: 비유 → 표상 → 예시 → 활동 → 흔한 실수 → 용어 |
| 5 | 연습 | 문제 5개(새 상황 2개 이상, 오답별 진단) + 확장 과제 |
| 6 | 나가기 전에 | 처음 예측으로 돌아가 무엇이 달라졌는지 쓰고, 한 문장으로 말하고, 틀린 문장을 골라낸다 |

처음엔 11개 섹션(탄생 배경·상황극·꿀팁…)이었다. 두 번째 외부 평가가 "구조 자체를 해체하라" 고 했고,
그대로 했다. 경위는 [13. 품질 루프 §9](docs/plan/13-quality-loop.md).

## 제품 원칙 — 로버스트니스

> 학생, 기기, 선행지식, 오답 패턴, 표현 방식, 과목 특성이 달라져도 **학습목표와 데이터 해석이 무너지지 않는 것.**

세 번째 외부 평가의 경고는 칭찬이 아니었다. "UI 와 교수설계가 좋아졌기 때문에
남아 있는 단순화·오류·측정 결함이 훨씬 더 권위 있게 보인다." 그래서 V6 부터는
디자인을 동결하고 아래 넷을 계약에 넣었다.

- **모든 규칙은 경계를 말한다** — `boundary { holds_when, breaks_when }`. 조건 없는 규칙은 절대법칙으로 기억된다.
- **모든 모형은 생략한 것을 말한다** — `figure.model_note`. 단순화는 죄가 아니고, 숨기는 것이 문제다.
- **문제는 개수가 아니라 증거로 센다** — `evidence` 3종 이상. "모든 학습지 5문제" 는 제작 규격이지 학습 증거가 아니다.
- **처음 생각을 지운 데이터는 데이터가 아니다** — `firstChoice` 는 덮어쓰지 않는다. 정답보다 변화가 중요하다.

전문은 [15. 로버스트니스](docs/plan/15-robustness.md).

## 계획 문서

| 문서 | 내용 |
|---|---|
| [00. 제품 개요](docs/plan/00-overview.md) | 문제 정의, 가설, 스코프, 성공 지표, **유닛 이코노믹스** |
| [01. 아키텍처](docs/plan/01-architecture.md) | 시스템 구성, 기술 선택 근거, 폴더 구조 |
| [02. 디자인 시스템](docs/plan/02-design-system.md) | Seed 토큰, Untitled UI 아이콘, 교체 절차, 상표 주의 |
| [03. 데이터 모델](docs/plan/03-data-model.md) | Supabase 스키마, RLS, 쿼터 원자성, 결제 원장 |
| [04. 학습지 규격](docs/plan/04-worksheet-spec.md) | 6단계 JSON 스키마, HTML 규격, 2단계 LLM 호출·비용 예산 |
| [05. API 규격](docs/plan/05-api-spec.md) | Edge Function / PostgREST 경계, 영수증 검증, 오류 코드 |
| [06. 필기 레이어](docs/plan/06-annotation.md) | 아이패드 필기 설계, 좌표계, 동기화 |
| [07. 복습 & 알림](docs/plan/07-review-notifications.md) | 망각곡선, SM-2 lite, iOS 64개 한도 대응 |
| [08. 로드맵](docs/plan/08-roadmap.md) | M0~M5 마일스톤과 작업 분해 |
| [09. 미결정 사항](docs/plan/09-open-questions.md) | 질문 7개 + 리스크 10개 |
| [10. 가격 설계](docs/plan/10-pricing.md) | 가격 3종, 유닛 이코노믹스, 실측 후 조정 규칙 |
| [11. 목소리와 페르소나](docs/plan/11-voice-and-persona.md) | 파르 페르소나, 설명 사다리, 단어 정책, 말투 강제 |
| [12. 분야 카테고리](docs/plan/12-categories.md) | 12개 분야, 예시 종류, 분야별 적응 규칙 |
| [13. 품질 검사 루프](docs/plan/13-quality-loop.md) | 학습설계 린트, 검사관, 재작성 루프, 비용 영향 |
| [14. 실물 자극 자산](docs/plan/14-stimulus-assets.md) | 사진 파이프라인, 라이선스, art 출고 게이트 |
| [15. 로버스트니스](docs/plan/15-robustness.md) | **제품 원칙.** 콘텐츠·평가·런타임 세 레이어, 출고 체크리스트 |

## 디자인 교체

디자인은 **`design/design_tokens.json` 하나가 유일한 교체 지점**이다.
값만 바꾸고 `node design/build_tokens.mjs` 를 돌리면 Flutter 테마와 학습지 CSS가 함께 다시 생성된다.
앱 코드도 학습지 렌더러도 한 줄 고치지 않는다. 코드에 색·간격·서체 리터럴이 없도록 CI가 강제한다.

## 유닛 이코노믹스

장당 생성 원가 약 300원(설계 opus + 집필 sonnet + 검사관 opus, 재작성률 30% 가정),
무료 2장은 원가만 600원/가입자(사실상 CAC). 가격은 **손익분기 결제 전환율**을 기준으로 설계했다.

| 상품 | 마진 (수수료 15%) | 손익분기 전환율 |
|---|---|---|
| ~~5장 1,900원 (초기안)~~ | — | ❌ |
| 3장 4,900원 | 2,886원 | 20.8% |
| **10장 12,900원** | **6,968원** | **8.6%** |
| 30장 29,900원 | 14,105원 | 4.3% |

스토어 수수료 30% 면 10장 기준 11.5%. 성립하지만 검사 루프 도입 전(3.1%)보다 여유가 절반이다.
상세는 [10. 가격 설계](docs/plan/10-pricing.md).

**최우선 조치**: Apple Small Business Program / Google Play 소규모 사업자 등록
(신청만으로 수수료 30% → 15%).

## 착수 전 블로커

1. **Apple Pencil 필압 spike** — WKWebView 안에서 Pointer Events 필압이 나오는지 실기기 검증.
   결과가 필기 아키텍처를 확정한다. ([M0](docs/plan/08-roadmap.md))
2. **Supabase 프로젝트 / Anthropic API 키** ([Q5](docs/plan/09-open-questions.md))

## 라이선스 고지

- **SEED Design System** — Apache License 2.0, Copyright 2025 주식회사 당근마켓
- **untitledui-js** (Untitled UI Icons) — MIT, Copyright (c) 2025 Emmanuel C. Alozie
- **Pretendard** — SIL Open Font License 1.1

⚠️ Seed 의 브랜드 색(`#FF6600`)은 당근마켓의 상표적 자산이다.
Apache 2.0 은 코드 라이선스이고 상표는 별개다 — **상용 출시 전 `brand.*` 를 ONPAR 고유 색으로 교체할 것.**
([02. 디자인 시스템 §8](docs/plan/02-design-system.md))
