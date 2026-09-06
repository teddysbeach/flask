# 04. 학습지 규격

## 1. 11개 섹션 (고정, 순서 불변)

| # | 키 | 섹션명 | 경로 | 목적 |
|---|---|---|---|---|
| 1 | `what_we_learn` | 무엇을 배우는가 | **핵심** | **첫 예측(hook)** → 일상 비유 → 요약 + 목표 3개 + 용어 풀이 |
| 2 | `before_and_need` | 이것이 생기기 전에는 | 보조 | 이전 세계의 불편, 왜 필요해졌는가 |
| 3 | `prerequisites` | 먼저 알고 있어야 할 것 | 보조 | 각각 새 학습지 생성 진입점 |
| 4 | `origin_story` | 탄생 배경 | 보조 | 언제·누가·어떤 맥락에서. **연도/인물은 확실할 때만** |
| 5 | `roleplay` | 상황극 & 예시 | 보조 | 이해를 돕는 스토리. 사실 기반이거나 "가상임"을 명시 |
| 6 | `main_lesson` | 본론 | **핵심** | 설명 → 도형 → 예시 → 활동 → 흔한 실수. 3~6개 블록, 절반 이상에 활동 |
| 7 | `pro_tips` | 꿀팁 | 보조 | 실무자만 아는 요령 3~5개 |
| 8 | `quiz` | 적용 문제 | **핵심** | 복습 알림의 재료. far transfer 2개 이상 |
| 9 | `homework` | 직접 해보기 | **핵심** | 직접 해보는 과제 |
| 10 | `wrap_up` | 정리 | **핵심** | 사용 예시 + 일상 적용 + 점검 + **성찰(reflection)** |
| 11 | `next_steps` | 다음 단계 제안 | 보조 | 이어서 배울 것 3개 |

"보조" 섹션은 `SECTIONS[].core = false`. 렌더러가 `<details class="sec__fold">` 로 접어서 내보내고,
핵심 경로(1 → 6 → 8 → 9 → 10)가 먼저 읽히게 한다. 섹션 id 와 순서는 그대로다 — 필기 좌표는 흔들리지 않는다.

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

  "time": { "core": 25, "practice": 15, "optional": 40 },   // optional = 숙제 합계 (검증기)
  "assumes": ["string"],                   // 1~4개. "입문" 이 무엇에 대한 입문인지

  "what_we_learn": {
    "hook": Activity,                      // 첫 예측. predict|decide 만. 설명 전에 고르게 한다 (V4)
    "analogy": "string",                   // 일상 비유. 정의보다 먼저 온다 (설명 사다리 ①단)
    "summary": [InlineNode],
    "objectives": ["string", "string", "string"],   // 정확히 3개
    "one_liner": "string"                            // 한 줄 정의
  },

  "glossary": [                           // 3~6개 — 어려운 말을 그 자리에서 푼다
    { "term": "string", "plain": "string" }
  ],

  "guide_notes": [                        // 1~2개 — 파르(먼저 헤맨 사람)의 한마디. 오개념 교정·힌트에만
    { "section": SectionKey, "note": "string" }
  ],

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
        "figure": "string|null",           // figures[].id 참조
        "example": Example,                // kind: code|steps|compare|calc|scene
        "activity": Activity|null,         // 절반 이상의 블록에 필수
        "common_mistake": "string|null"
      }
    ]
  },

  "figures": [                             // 0~6개. 구조화 스펙만, SVG 문자열 금지
    {
      "id": "string", "title": "string", "alt": "string", "drawTask": "string|null",
      "spec": { "kind": "plot", "fn": "x^2|x^3|sin|exp|linear|abs", "xRange": [0, 6],
                "secant": [3, 5] | null, "tangentAt": 3 | null, "interactive": true }
            | { "kind": "distribution", "panels": [{ "title": "string", "profile": "single|two-humps|fringes|fringes-weak" }],
                "idealized": true,          // 필수. 슬릿 폭을 무시한 모델임을 캡션에 밝힌다
                "interactive": true }       // 경로정보 슬라이더
            | { "kind": "tonecurve", "curve": "linear|s-mild|s-strong|inverse-s", "clipHighlights": false }
            | { "kind": "swatches", "rows": [{ "label": "string", "colors": ["#rrggbb"] }] }
    }
  ],

  "pro_tips": [ { "tip": "string", "why": "string" } ],   // 3~5개

  "quiz": [                                // 정확히 5개
    {
      "kind": "short_answer|multiple_choice|explain",
      "question": "string",
      "choices": ["string"] | null,
      "answer": "string",
      "explanation": "string",
      "difficulty": 1,
      "transfer": "near|far",              // far 2개 이상
      "misconceptions": [ { "wrong": "string", "why": "string" } ]   // 선택형은 선택지별 피드백이 된다
    }
  ],

  "homework": {
    "tasks": [ { "title": "string", "detail": "string", "estimated_minutes": 15 } ],
    "submission_hint": "string"
  },

  "wrap_up": {
    "usage_examples": ["string"],          // 2~4개
    "daily_life_guide": [InlineNode],      // 일상 적용
    "checklist": ["string"],               // 스스로 점검
    "reflection": "string"                 // 처음 예측(hook)으로 돌아가 한 줄 쓰기 (V4)
  },

  "next_steps": [ { "title": "string", "why": "string", "difficulty_delta": "same|harder" } ]
}
```

`InlineNode` = `{ "type": "text"|"bold"|"code"|"em", "value": "string" }`
`Activity` = `{ "kind": "predict|decide|compute|draw|explain", "prompt": "string", "options": ["string"]|null, "reveal": "string" }`
— predict/decide 는 `options` 필수(라디오로 렌더), 나머지는 필기 칸 + "적었어요" 체크.

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

### 검사 루프

집필 뒤에 정적 검사 세 겹(정합성·말투·학습설계)과 검사관(opus)이 붙는다. 반려면 사유를 붙여 재작성, 최대 2회.
상세는 **`13-quality-loop.md`**. 아래 비용은 검사관 1회를 포함한 값이다.

### 비용 예산 — 학습지 1장

**환율 1 USD = 1,400 KRW 가정. 150원 = $0.107.**
아래는 **프롬프트 캐시 히트를 계산에 넣지 않은 보수적 상한**이다(캐시가 먹으면 더 내려간다).

| 단계 | 모델 | 단가 (in/out per 1M) | 입력 | 출력 상한 | 비용 |
|---|---|---|---|---|---|
| ① 설계 | `claude-opus-5` | $5 / $25 | 2,600 | 1,000 | $0.0380 |
| ② 집필 | `claude-sonnet-5` | $2 / $10 | 4,400 | 6,000 | $0.0688 |
| ③ 검사관 | `claude-opus-5` | $5 / $25 | 9,000 | 800 | $0.0650 |
| **합계 (초안 통과)** | | | | | **$0.1718 ≈ 240원** |
| 재작성 1회 포함 | | | | | $0.315 ≈ 441원 |
| 평균 (재작성률 30%) | | | | | ≈ $0.215 ≈ 300원 |

무료 사용자 1명(2장) ≈ 600원. 신규 1,000명 ≈ 60만원.

> 검사 루프 도입으로 목표였던 150원의 두 배가 됐다. 이유와 손익 영향은 `13-quality-loop.md` §5.

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
  <meta name="viewport" content="width=device-width, initial-scale=1">   <!-- 확대 금지는 WCAG 위반이라 뺐다 -->
  <style>/* GENERATED from design_tokens.json — 02-design-system.md §1 */</style>
</head>
<body>
<article class="sheet" data-worksheet-id="..." data-schema-version="1" data-sheet-width="820">

  <header class="sheet__header">
    <h1 class="sheet__title">...</h1>
    <p class="sheet__meta">난이도 · 예상 25분</p>
  </header>

  <section class="sec sec--core" id="sec-1" data-section="what_we_learn">
    <header class="sec__head">...</header>
    <div class="sec__body">
      <div class="act act--predict" data-response-id="hook-1" data-response-kind="choice">  <!-- 첫 예측 -->
        <p class="act__prompt">...</p>
        <div class="act__options" role="radiogroup">
          <label class="act__opt"><input type="radio" name="hook-1" value="..."> ...</label>
        </div>
        <p class="act__fb" data-feedback-slot hidden></p>
        <details class="act__reveal">...</details>   <!-- 고르기 전엔 런타임이 열지 않는다 -->
      </div>
      <p class="analogy">...</p> ...
    </div>
  </section>

  <section class="sec sec--aside" id="sec-2" data-section="before_and_need">   <!-- 보조: 접혀서 시작 -->
    <details class="sec__fold"><summary class="sec__fold-summary">...</summary> ... </details>
  </section>

  <section class="sec sec--core" id="sec-8" data-section="quiz">
    <ol class="quiz">
      <li class="quiz__item" data-quiz-id="{uuid}" data-response-id="quiz-3" data-response-kind="choice" data-answer="1">
        <p class="quiz__q">...</p>
        <div class="quiz__choices" role="radiogroup">
          <label class="act__opt" data-feedback="이렇게 골랐다면 …"><input type="radio" ...> ...</label>
        </div>
        <p class="act__fb" data-feedback-slot hidden></p>
        <button type="button" class="quiz__submit" data-submit>제출</button>
        <details class="quiz__a">...</details>
      </li>
      <li class="quiz__item" data-quiz-id="{uuid}" data-response-id="quiz-4" data-response-kind="written">
        <p class="quiz__q">...</p>
        <div class="ink-space" data-ink-space="sm"></div>   <!-- 답 쓰는 칸: 과제가 있는 곳에만 -->
        <label class="act__attempt"><input type="checkbox" data-attempted> 내 답을 적었어요</label>
        <details class="quiz__a">...</details>
      </li>
    </ol>
  </section>

</article>
<canvas id="ink-layer" class="ink-layer"></canvas>   <!-- 필기 레이어, 06번 문서 -->
<script>/* GENERATED: ink-runtime.g.ts — 필기 엔진 + 학습 상호작용(worksheet-interact.js) */</script>
</body>
</html>
```

**불변 규칙 (필기 좌표 안정성의 전제)**

- 섹션 id는 `sec-1` ~ `sec-11` 로 **항상 11개 모두 존재**한다 (내용이 빈약해도 섹션을 생략하지 않는다).
- `data-quiz-id` 는 `quiz_items.id` 와 동일 → 복습 알림에서 해당 문제로 스크롤 가능.
- 문서 폭 `--sheet-width` 는 **고정**. 화면 맞춤은 `transform: scale()` 로만.
- `.ink-space` 는 필기 전용 빈 블록. **과제가 붙은 자리에만** 둔다(서술형 문제, compute/draw/explain 활동, 그림 위 과제, 성찰).
  섹션 끝에 그냥 붙는 빈 칸은 없다 — 빈 종이는 과제가 아니다. 렌더 테스트가 강제한다.
- 응답 위젯: `data-response-id` 는 렌더 순서로 부여되는 결정론적 id. 런타임이 `ONPAR_RESPONSES[id]` 에 기록하고
  Flutter 브리지 `learn` 채널로 `{type: choice|attempt|slider, payload}` 를 보낸다.
- HTML을 다시 생성해도(재렌더) 동일 JSON이면 **바이트 단위로 동일**해야 한다 (렌더러 순수 함수).
  이 성질이 깨지면 기존 필기가 어긋난다. 렌더러에 골든 파일 테스트를 건다.

## 7. 테스트

| 테스트 | 내용 |
|---|---|
| 스키마 검증 | 픽스처 JSON 20종(정상/누락/개수초과)에 대한 Zod 통과·실패 |
| 렌더러 골든 테스트 | 픽스처 JSON → HTML 스냅샷 비교 (결정론성 보장) |
| XSS | `<script>`, `" onload=` 등을 모든 문자열 필드에 넣어 이스케이프 확인 |
| 프롬프트 회귀 | 고정 주제 10개에 대해 생성 → 섹션 누락·길이 초과·정직성 위반 자동 체크 |
| 말투 | 금지 표현·반말 검출, 합니다체 오인 없음, 코드 블록 제외 |
| 단계 간 정합성 | 집필 결과가 설계도의 `confidence` / `mode` / 문제 대상을 **뒤집지 않았는지** 자동 대조 |
| 비용 회귀 | 30건 실측으로 장당 실비가 `$0.105` 목표·`$0.12` 경보 안에 드는지 확인 |
