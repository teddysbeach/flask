# 04. 학습지 규격

## 1. 11개 섹션 (고정, 순서 불변)

| # | 키 | 섹션명 | 목적 |
|---|---|---|---|
| 1 | `what_we_learn` | 무엇을 배우는가 | 한 문단 요약 + 학습 목표 3개 + 소요 시간 |
| 2 | `before_and_need` | 이것이 생기기 전에는 | 이전 세계의 불편, 왜 필요해졌는가 |
| 3 | `prerequisites` | 먼저 보면 좋은 학습지 3개 | 각각 새 학습지 생성 진입점 |
| 4 | `origin_story` | 탄생 배경 | 언제·누가·어떤 맥락에서. **연도/인물은 확실할 때만** |
| 5 | `roleplay` | 상황극 & 예시 | 이해를 돕는 스토리. 사실 기반이거나 "가상임"을 명시 |
| 6 | `main_lesson` | 본론 | 핵심 학습 내용. 3~6개 하위 블록 |
| 7 | `pro_tips` | 꿀팁 | 실무자만 아는 요령 3~5개 |
| 8 | `quiz` | 질의 5개 | 복습 알림의 재료가 되는 문제 |
| 9 | `homework` | 숙제 & 과제 | 직접 해보는 과제 |
| 10 | `wrap_up` | 마무리 팁 | 사용 예시 + 일상 적용 가이드 |
| 11 | `next_steps` | 다음 단계 제안 | 이어서 배울 것 3개 |

## 2. 생성 계약: LLM은 JSON만, HTML은 서버가

```
사용자 입력(topic, level)
   → ① 설계: claude-opus-5  → WorksheetOutline JSON (판단)
   → ② 집필: claude-sonnet-5 → WorksheetContent JSON (문장화)
   → 스키마 검증(Zod) 실패 시 해당 단계만 1회 재요청
   → 결정론적 렌더러 renderWorksheet(json, tokens) 
   → 완결형 HTML 1파일 (CSS·폰트 인라인)
   → Storage 업로드
```

LLM 출력 문자열은 **전부 HTML 이스케이프** 후 삽입한다. 예외는 없다.
인라인 마크업이 필요한 곳(굵게, 코드)은 LLM이 HTML을 쓰는 게 아니라
`[{type:"text"|"bold"|"code", value:"..."}]` 형태의 **인라인 노드 배열**로 받아 렌더러가 태그를 만든다.
→ prompt injection이 HTML injection으로 번지는 경로를 원천 차단.

## 3. `WorksheetContent` JSON 스키마 (요약)

```jsonc
{
  "schema_version": 1,
  "title": "string",                       // 학습지 제목
  "topic_normalized": "string",            // 사용자 입력 정규화
  "level": "beginner|intermediate|advanced",
  "estimated_minutes": 25,

  "what_we_learn": {
    "summary": [InlineNode],
    "objectives": ["string", "string", "string"],   // 정확히 3개
    "one_liner": "string"                            // 한 줄 정의
  },

  "before_and_need": {
    "world_before": [InlineNode],          // 이전에는 어땠는지
    "pain_points": ["string"],             // 2~4개
    "why_it_emerged": [InlineNode]         // 어떤 필요가 이걸 낳았는지
  },

  "prerequisites": [                       // 정확히 3개
    { "title": "string", "why": "string", "one_liner": "string" }
  ],

  "origin_story": {
    "timeline": [                          // 2~5개
      { "when": "string", "what": "string", "confidence": "high|medium|low" }
    ],
    "narrative": [InlineNode],
    "uncertainty_note": "string|null"      // 불확실하면 여기에 솔직히 적는다
  },

  "roleplay": {
    "mode": "real_case|hypothetical",      // 사실 기반 / 가상 시나리오
    "scene": "string",                     // 상황 설정
    "dialogue": [ { "speaker": "string", "line": "string" } ],
    "takeaway": [InlineNode],
    "disclaimer": "string|null"            // hypothetical 이면 필수
  },

  "main_lesson": {
    "blocks": [                            // 3~6개
      {
        "heading": "string",
        "body": [InlineNode],
        "example": { "caption": "string", "code": "string|null", "language": "string|null" },
        "common_mistake": "string|null"
      }
    ]
  },

  "pro_tips": [ { "tip": "string", "why": "string" } ],   // 3~5개

  "quiz": [                                // 정확히 5개
    {
      "kind": "short_answer|multiple_choice|explain",
      "question": "string",
      "choices": ["string"] | null,
      "answer": "string",
      "explanation": "string",
      "difficulty": 1
    }
  ],

  "homework": {
    "tasks": [ { "title": "string", "detail": "string", "estimated_minutes": 15 } ],
    "submission_hint": "string"
  },

  "wrap_up": {
    "usage_examples": ["string"],          // 2~4개
    "daily_life_guide": [InlineNode],      // 일상 적용
    "checklist": ["string"]                // 스스로 점검
  },

  "next_steps": [ { "title": "string", "why": "string", "difficulty_delta": "same|harder" } ]
}
```

`InlineNode` = `{ "type": "text"|"bold"|"code"|"em", "value": "string" }`

**검증 규칙 (Zod)**: 배열 길이 제약(prerequisites=3, quiz=5, objectives=3)은 스키마에서 강제한다.
LLM이 4개를 주면 스키마 실패 → 오류 메시지를 붙여 1회 재요청 → 그래도 실패면 잡 실패 처리.

## 4. LLM 호출 설계 — 2단계 하이브리드

**결정 (Q4): 설계는 `claude-opus-5`, 집필은 `claude-sonnet-5`. 학습지 1장 예산 150원 이내.**

```
주제 입력
   │
   ├─ ① 설계 (claude-opus-5)  ─────────────────────────
   │     무엇을 · 어떤 순서로 · 무엇이 사실인지 판단
   │     출력: 설계도(outline) JSON — 작다 (~900 tokens)
   │
   ├─ ② 집필 (claude-sonnet-5) ────────────────────────
   │     설계도를 받아 문장으로 채운다
   │     출력: WorksheetContent JSON — 크다 (~6,000 tokens)
   │
   └─ 스키마 검증 → 렌더러 → HTML
```

### 왜 이렇게 나누는가

학습지 품질을 결정하는 것은 **분량이 아니라 판단**이다.
"무엇을 가르칠지, 어떤 순서로 쌓을지, 이 연도가 사실인지, 이 문제가 본문을 제대로 물어보는지" —
이건 Opus 5 가 해야 한다. 하지만 이 판단의 **출력량은 작다**.

반대로 토큰의 90%를 먹는 것은 본문 문장화이고, **설계도가 이미 정확하면 문장화는 Sonnet 5 로 충분하다.**

비싼 모델을 비싼 구간(판단)에만 쓰고, 싼 모델을 양이 많은 구간(집필)에 쓴다.

### ① 설계 단계 — `claude-opus-5`

`WorksheetOutline` 출력:
- 11개 섹션 각각의 **요지 bullet** (문장이 아니라 뼈대)
- 4번 탄생 배경의 **연도·인물 + `confidence` 확정** ← 이 판단은 여기서 끝난다
- 5번 상황극의 `mode`(사실/가상) 결정
- 8번 문제 5개의 **골격**(무엇을 묻는지 + 정답 요지 + 어느 본문 블록에 근거하는지)
- 3번 사전학습 3개, 11번 다음 단계 3개
- 섹션별 **목표 분량(토큰)** 배분

### ② 집필 단계 — `claude-sonnet-5`

설계도를 입력으로 받아 `WorksheetContent` 전체를 채운다.

**Sonnet 이 뒤집을 수 없는 것** (프롬프트로 고정):
- `confidence`, `mode`, `disclaimer` — 사실성 판단은 ①에서 확정된 것을 **그대로 옮긴다**
- 문제 5개가 묻는 대상 — 새 문제를 지어내지 않는다
- 섹션 개수와 순서

집필 단계가 사실 판단을 다시 하지 않게 막는 것이 이 구조의 핵심 안전장치다.

### 호출 코드

```ts
// ① 설계 — claude-opus-5
const plan = await opus.messages.stream({
  model: "claude-opus-5",
  max_tokens: 1000,                       // 하드캡 (비용 상한)
  thinking: { type: "adaptive" },
  output_config: { effort: "medium", format: { type: "json_schema", schema: OUTLINE_SCHEMA } },
  system: [{ type: "text", text: PLAN_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
  messages: [{ role: "user", content: buildPlanPrompt(topic, level) }],
}).finalMessage();

// ② 집필 — claude-sonnet-5
const draft = await sonnet.messages.stream({
  model: "claude-sonnet-5",
  max_tokens: 6000,                       // 하드캡
  thinking: { type: "adaptive" },
  output_config: { effort: "medium", format: { type: "json_schema", schema: WORKSHEET_SCHEMA } },
  system: [{ type: "text", text: DRAFT_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
  messages: [{ role: "user", content: buildDraftPrompt(outline) }],
}).finalMessage();
```

- `messages.stream()` + `finalMessage()` — `max_tokens` 가 크면 논스트리밍은 HTTP 타임아웃 위험.
- `output_config.format` (structured outputs) — 구식 `output_format` 파라미터가 아니라 이쪽.
- `budget_tokens` 는 두 모델 모두 400 오류이므로 쓰지 않는다. 깊이는 `effort` 로 조절.
- **프롬프트 캐싱** — 두 단계의 시스템 프롬프트는 매 요청 동일하므로 `cache_control` 을 건다.
  사용자 입력은 반드시 캐시 브레이크포인트 **뒤**(messages)에 둔다. 앞에 두면 캐시가 매번 깨진다.

### 비용 예산 — 학습지 1장

**환율 1 USD = 1,400 KRW 가정. 150원 = $0.107.**
아래는 **프롬프트 캐시 히트를 계산에 넣지 않은 보수적 상한**이다(캐시가 먹으면 더 내려간다).

| 단계 | 모델 | 단가 (in/out per 1M) | 입력 | 출력 상한 | 비용 |
|---|---|---|---|---|---|
| ① 설계 | `claude-opus-5` | $5 / $25 | 2,600 | 1,000 | $0.0380 |
| ② 집필 | `claude-sonnet-5` | $2 / $10 | 4,400 | 6,000 | $0.0688 |
| **합계 (최악)** | | | | | **$0.1068 ≈ 149원** |
| 합계 (평균 실측 예상) | | | | | ≈ $0.095 ≈ 133원 |

무료 사용자 1명(2장) ≈ 300원. 신규 1,000명 ≈ 30만원.

### 솔직하게 짚을 두 가지 리스크

1. **Opus 5 의 thinking 토큰은 출력으로 과금된다.** adaptive thinking 이라 양이 요청마다 다르고,
   설계 단계 비용이 계산대로 나오지 않을 수 있다. → `max_tokens: 1000` 하드캡이 최후 방어선이고,
   **M2 에서 30건 실측한 뒤 `effort` 와 캡을 확정한다.** 예산이 초과하면 `effort: "low"` 로 내린다.
2. **150원은 환율에 종속된다.** 1,450원/USD 가 되면 같은 $0.1068 이 155원이 된다.
   → 예산은 **달러로 관리**한다: 목표 `$0.105/장`, 경보 `$0.12/장`.

### 런타임 가드

- `generation_jobs` 에 단계별 `tokens_in/out` 과 실비를 기록한다.
- 최근 100건 이동평균이 `$0.12/장` 을 넘으면 자동 다운시프트:
  집필 단계 섹션별 목표 분량을 15% 축소 → 그래도 안 되면 `effort: "low"`.
- 일일 총 지출 상한 초과 시 `generate-worksheet` 소프트 차단 (503 + 안내). `05-api-spec.md` §5.

### 채택하지 않은 대안

- **전부 Opus 5** (1장 ≈ $0.23 ≈ 320원): 예산 2배 초과.
- **전부 Sonnet 5** (1장 ≈ $0.09 ≈ 126원): 더 싸지만 4번(탄생 배경)·8번(문제 설계)의 판단 품질이 떨어진다.
  무료 2장이 곧 전환율이므로 판단 구간에는 Opus 를 쓴다.
- **Batch API** (50% 할인): 최대 24시간 지연이라 대화형 UX 에 부적합.
- **섹션별 병렬 분할 호출**: 지연은 줄지만 시스템 프롬프트가 호출 수만큼 중복 과금된다.
  캐시로 상쇄되더라도 섹션 간 문맥 일관성이 깨져서 채택하지 않는다.

## 5. 프롬프트 원칙

프롬프트는 단계별로 나뉜다: `server/prompts/plan.v1.md`(설계) / `server/prompts/draft.v1.md`(집필).
아래 규칙 중 1·3은 **설계 단계**가 책임지고, 2·4·5·6·7은 **집필 단계**가 지킨다.

1. **정직성** — 확실하지 않은 연도·인물·수치는 단정하지 말고 `confidence: "low"` 또는
   `uncertainty_note` 에 적는다. 그럴듯한 거짓 일화를 만들지 않는다.
   (5번 상황극이 가상이면 `mode: "hypothetical"` + `disclaimer` 필수 — 사용자가 요구한 "사실기반이거나 솔직한".)
2. **초심자 기준** — 2번(이전에는 어땠는지)은 "그게 없던 시절의 불편"을 구체적 장면으로 쓴다. 추상어 금지.
3. **문제는 본문에서만** — 8번 질의 5개는 6번 본론에서 다룬 내용만 낸다. 본문에 없는 걸 물으면 안 된다.
   복습 알림으로 몇 주 뒤에 나오는 문제이므로 **문제만 읽어도 맥락이 서게** 쓴다.
4. **과제는 실행 가능해야** — 9번은 "생각해보세요"가 아니라 손을 움직이는 과제.
5. **일상 적용** — 10번은 학습자의 실제 생활/업무에 붙이는 구체적 방법.
6. **길이 예산** — 섹션별 최대 길이를 명시해 특정 섹션이 문서를 잡아먹지 않게 한다.
7. **언어** — 한국어. 기술 용어는 `한국어(English)` 병기 1회.

두 프롬프트는 각각 버전을 찍어 `worksheets.prompt_version` 에 `plan.v1+draft.v1` 형태로 기록한다 → 품질 회귀 추적.

## 6. HTML 출력 규격

**완결형 단일 파일**. 외부 요청 0회 (CSS·폰트 인라인, 이미지 없음) → 오프라인에서 동일하게 렌더.

```html
<!doctype html>
<html lang="ko" data-theme="light">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>/* GENERATED from design_tokens.json — 02-design-system.md §1 */</style>
</head>
<body>
<article class="sheet" data-worksheet-id="..." data-schema-version="1" data-sheet-width="820">

  <header class="sheet__header">
    <h1 class="sheet__title">...</h1>
    <p class="sheet__meta">난이도 · 예상 25분</p>
  </header>

  <section class="sec" id="sec-1" data-section="what_we_learn">
    <h2 class="sec__title"><span class="sec__num">01</span>무엇을 배우는가</h2>
    <div class="sec__body">...</div>
    <div class="ink-space" data-ink-space="md"></div>   <!-- 필기 여백 -->
  </section>

  <!-- sec-2 ... sec-11 동일 패턴 -->

  <section class="sec" id="sec-8" data-section="quiz">
    <h2 class="sec__title"><span class="sec__num">08</span>질의 5개</h2>
    <ol class="quiz">
      <li class="quiz__item" data-quiz-id="{uuid}">
        <p class="quiz__q">...</p>
        <div class="ink-space" data-ink-space="lg"></div>  <!-- 답 쓰는 칸 -->
        <details class="quiz__a"><summary>정답 보기</summary><div>...</div></details>
      </li>
    </ol>
  </section>

</article>
<canvas id="ink-layer" class="ink-layer"></canvas>   <!-- 필기 레이어, 06번 문서 -->
<script>/* GENERATED: worksheet_runtime.js — 필기 엔진 */</script>
</body>
</html>
```

**불변 규칙 (필기 좌표 안정성의 전제)**

- 섹션 id는 `sec-1` ~ `sec-11` 로 **항상 11개 모두 존재**한다 (내용이 빈약해도 섹션을 생략하지 않는다).
- `data-quiz-id` 는 `quiz_items.id` 와 동일 → 복습 알림에서 해당 문제로 스크롤 가능.
- 문서 폭 `--sheet-width` 는 **고정**. 화면 맞춤은 `transform: scale()` 로만.
- `.ink-space` 는 필기 전용 빈 블록. 렌더러가 섹션 성격에 따라 `sm|md|lg` 를 배정한다.
- HTML을 다시 생성해도(재렌더) 동일 JSON이면 **바이트 단위로 동일**해야 한다 (렌더러 순수 함수).
  이 성질이 깨지면 기존 필기가 어긋난다. 렌더러에 골든 파일 테스트를 건다.

## 7. 테스트

| 테스트 | 내용 |
|---|---|
| 스키마 검증 | 픽스처 JSON 20종(정상/누락/개수초과)에 대한 Zod 통과·실패 |
| 렌더러 골든 테스트 | 픽스처 JSON → HTML 스냅샷 비교 (결정론성 보장) |
| XSS | `<script>`, `" onload=` 등을 모든 문자열 필드에 넣어 이스케이프 확인 |
| 프롬프트 회귀 | 고정 주제 10개에 대해 생성 → 섹션 누락·길이 초과·정직성 위반 자동 체크 |
| 단계 간 정합성 | 집필 결과가 설계도의 `confidence` / `mode` / 문제 대상을 **뒤집지 않았는지** 자동 대조 |
| 비용 회귀 | 30건 실측으로 장당 실비가 `$0.105` 목표·`$0.12` 경보 안에 드는지 확인 |
