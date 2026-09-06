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
   → Claude API (claude-opus-5, structured output)
   → WorksheetContent JSON  ── 스키마 검증(Zod) 실패 시 1회 재요청
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

## 4. Claude API 호출 설계

```ts
// server/supabase/functions/generate-worksheet/claude.ts
import Anthropic from "npm:@anthropic-ai/sdk";

const client = new Anthropic();  // ANTHROPIC_API_KEY 는 Edge Function secret

const stream = client.messages.stream({
  model: Deno.env.get("WORKSHEET_MODEL") ?? "claude-opus-5",
  max_tokens: 32000,
  thinking: { type: "adaptive" },
  output_config: {
    effort: "high",
    format: { type: "json_schema", schema: WORKSHEET_JSON_SCHEMA },  // 구조화 출력
  },
  system: [
    { type: "text", text: WORKSHEET_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
  ],
  messages: [{ role: "user", content: buildUserPrompt(topic, level, locale) }],
});
const message = await stream.finalMessage();
```

**설계 근거**

- `messages.stream()` — `max_tokens` 가 크면 논스트리밍은 HTTP 타임아웃 위험. 스트림 + `finalMessage()`.
- `output_config.format` (structured outputs) — 구식 `output_format` 파라미터가 아니라 이쪽.
  스키마 위반 응답 자체를 줄여서 재시도 비용을 낮춘다.
- `thinking: {type:"adaptive"}` + `effort: "high"` — 4번(탄생 배경), 5번(상황극) 섹션의 품질 차이가
  여기서 갈린다. `budget_tokens` 는 이 모델에서 400 오류이므로 쓰지 않는다.
- **프롬프트 캐싱** — 시스템 프롬프트(스키마 설명 + 스타일 가이드, 약 3~5K 토큰)는 모든 요청에서 동일하므로
  `cache_control` 을 건다. 캐시 히트는 `usage.cache_read_input_tokens` 로 검증한다.
- 사용자 입력은 **캐시 브레이크포인트 뒤**(messages)에 둔다. 앞에 두면 캐시가 매번 깨진다.

### 비용 추정 (`claude-opus-5`: 입력 $5 / 출력 $25 per 1M)

| 항목 | 토큰 | 비용 |
|---|---|---|
| 입력 (시스템 캐시 히트 + 사용자 입력) | ~4,500 | ~$0.008 |
| 출력 (학습지 JSON, thinking 포함) | ~9,000 | ~$0.225 |
| **학습지 1장 합계** | | **≈ $0.23 (약 320원)** |
| 무료 사용자 1명 (2장) | | ≈ $0.46 |

- 신규 가입 1,000명 = 약 $460. 무료 티어의 실비이므로 예산 상한과 알람을 반드시 건다.
- 참고로 `claude-sonnet-5`($2/$10)로 내리면 1장 ≈ $0.10 이지만,
  **무료 2장은 전환율을 결정하므로 v1에서는 품질을 우선한다.** 
  섹션별 분리 생성 시 3·11번(단순 제안 목록)만 `claude-haiku-4-5`($1/$5)로 내리는 것은 검토 가치 있음 → Q4.
- Batch API(50% 할인)는 최대 24시간 지연이라 대화형 UX에 부적합. 사용하지 않음.

## 5. 프롬프트 원칙 (`server/prompts/worksheet.v1.md`)

시스템 프롬프트에 반드시 포함할 규칙:

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

프롬프트는 `prompt_version` 으로 버전을 찍고 `worksheets` 행에 기록 → 품질 회귀 추적.

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
