// 학습지 데이터 계약. docs/plan/04-worksheet-spec.md §3
//
// LLM 은 이 모양의 JSON 만 만든다. HTML 은 render.ts 가 조립한다.
// 인라인 마크업도 LLM 이 태그를 쓰는 게 아니라 InlineNode 배열로 받아 렌더러가 태그를 만든다.
// 이 규칙 하나가 프롬프트 인젝션이 HTML 인젝션으로 번지는 경로를 끊는다.
//
// V5: 11개 섹션 템플릿을 버리고 학습 순서 6단계로 바꿨다.
//   문제 제시 → 예측 → 관찰 → 개념 → 연습 → 나가기 전에(exit ticket)
//
// V6: 6단계는 그대로 두고 **로버스트니스**를 계약에 넣었다.
// 세 번째 외부 평가의 요지: "UI 와 교수설계가 좋아졌기 때문에 남아 있는 단순화가
// 훨씬 더 권위 있게 보인다." 즉 이제 위험은 못 만든 것이 아니라 **너무 그럴듯한 것**이다.
//
// 그래서 아래 네 가지가 선택이 아니라 필드가 됐다.
//   1. Boundary      — 규칙마다 "언제 성립하고 언제 깨지는가". 단순화를 절대법칙으로 두지 않는다.
//   2. model_note    — 모든 이상화 표상이 "무엇을 생략했는지" 스스로 말한다.
//   3. evidence      — 문제는 개수가 아니라 증거 종류로 센다. 5문제 정량은 없앴다.
//   4. robustness    — 이 학습지가 막아야 할 대표 오개념을 미리 적고, 어디서 어떻게 막는지 밝힌다.
//
// 그리고 정직성 규칙 하나: 근거 없는 숫자 정밀도를 만들지 않는다(readout: 'qualitative').

export const SCHEMA_VERSION = 3

/** 6단계 키. SECTIONS 상수는 파일 하단에 있고 값이 같아야 한다(테스트가 검사). */
export type SectionKey = 'problem' | 'predict' | 'observe' | 'concept' | 'practice' | 'exit_ticket'

export type Level = 'beginner' | 'intermediate' | 'advanced'
export type Confidence = 'high' | 'medium' | 'low'
export type QuizKind = 'short_answer' | 'multiple_choice' | 'explain'

/** 12개 분야. docs/plan/12-categories.md */
export type Category =
  | 'math' | 'science' | 'cs' | 'art' | 'music' | 'language'
  | 'finance' | 'history' | 'business' | 'health' | 'cooking' | 'psychology'

export const CATEGORIES: readonly Category[] = [
  'math', 'science', 'cs', 'art', 'music', 'language',
  'finance', 'history', 'business', 'health', 'cooking', 'psychology',
]

/**
 * 예시의 모양. 분야마다 자연스러운 형태가 다르다.
 * 이걸 code 하나로만 두면 수학 학습지에 미분 계산이 코드 블록으로 들어간다.
 */
export type ExampleKind = 'code' | 'calc' | 'steps' | 'compare' | 'scene'
export const EXAMPLE_KINDS: readonly ExampleKind[] = ['code', 'calc', 'steps', 'compare', 'scene']

/**
 * 규칙의 경계. 입문용 단순화가 절대법칙으로 굳는 것을 막는 장치다.
 *
 * 세 번째 평가의 지적: "핵심 규칙 → 적용 조건 → 깨지는 경우" 3단이 없으면
 * 학생은 규칙만 떼어 기억한다. 그래서 규칙을 진술하는 블록은 이걸 달아야 한다.
 *
 *   holds_when  "그 점에서 도함수가 존재할 때"
 *   breaks_when "|x| 의 x=0 처럼 양쪽 기울기가 다르면 성립하지 않아요"
 */
export interface Boundary {
  holds_when: string
  breaks_when: string
}

/**
 * 문제가 무엇을 증거로 삼는가. 개수가 아니라 종류가 숙달을 증명한다.
 * 같은 개념을 서로 다른 표상에서 반복해 성공해야 "배웠다" 고 말할 수 있다.
 *
 *   recall     정의·용어를 되살린다 (가장 약한 증거)
 *   apply      배운 절차를 새 숫자에 적용한다
 *   compute    직접 계산한다
 *   graph      식 없이 그림·그래프에서 판단한다
 *   table      수치 표에서 추정한다
 *   diagnose   결과를 보고 원인 후보를 좁힌다
 *   edge_case  규칙이 깨지는 경우를 식별한다
 *   explain    말로 설명한다
 */
export type EvidenceKind =
  | 'recall' | 'apply' | 'compute' | 'graph' | 'table' | 'diagnose' | 'edge_case' | 'explain'

export const EVIDENCE_KINDS: readonly EvidenceKind[] = [
  'recall', 'apply', 'compute', 'graph', 'table', 'diagnose', 'edge_case', 'explain',
]

export interface Example {
  kind: ExampleKind
  caption: string
  /** 여러 줄 텍스트. steps 는 줄바꿈으로, compare 는 `전 | 후` 로 나눈다. */
  body: string
  /** kind 가 'code' 일 때만 쓴다. */
  language: string | null
}

/**
 * 도형. LLM 이 SVG 를 직접 쓰게 두면 렌더가 깨지고 XSS 가 열린다.
 * 구조화된 스펙만 받고 figures.ts 가 결정론적으로 SVG 를 만든다.
 *
 *   plot          함수 그래프 + 점·할선·접선 (수학·경제)
 *   distribution  나란한 분포/세기 패턴 (물리 — 간섭무늬, 통계)
 *   tonecurve     톤 커브 + 히스토그램 (미술 — 색보정)
 *   swatches      색 견본 비교 (미술)
 */
export type FigureSpec =
  | { kind: 'plot'; fn: 'x^2' | 'x^3' | 'sin' | 'exp' | 'linear' | 'abs'; xRange: [number, number]
      points?: number[]; secant?: [number, number]; tangentAt?: number; label?: string
      /** true 면 두 번째 점을 슬라이더로 움직여 할선이 접선으로 가는 것을 직접 본다 (h 는 양쪽 다) */
      interactive?: boolean }
  | { kind: 'distribution'; panels: { title: string; profile: 'two-humps' | 'fringes' | 'fringes-weak' | 'single' }[]
      /** true 면 결맞음 슬라이더로 간섭이 연속적으로 약해지는 것을 본다 */
      interactive?: boolean
      /** 슬릿 폭을 무시한 이상화 모델임을 그림에 밝힌다. distribution 은 항상 true 여야 한다(검증기). */
      idealized?: boolean }
  | { kind: 'tonecurve'; curve: 'linear' | 's-mild' | 's-strong' | 'inverse-s'; clipHighlights?: boolean }
  | { kind: 'swatches'; rows: { label: string; colors: string[] }[] }
  /**
   * 실물 자극. 색보정처럼 "눈으로 판단하는 능력" 을 가르치는 분야는 도식으로 대신할 수 없다.
   * 이미지는 assets/manifest.json 에 등록된 것만 쓴다(라이선스·출처가 확인된 것).
   * 렌더러가 data URI 로 박아 넣으므로 외부 요청은 여전히 0회다.
   */
  | { kind: 'photo'; assetId: string; /** 비교용 두 번째 이미지 */ compareAssetId?: string }

export interface Figure {
  id: string
  title: string
  /** 스크린리더용. 그림이 무엇을 보여주는지 문장으로. */
  alt: string
  spec: FigureSpec
  /** 학생이 그림에 직접 표시해야 하는 것. 있으면 그림 위에 필기 여백을 겹친다. */
  drawTask: string | null
  /**
   * 이 그림이 생략한 것. 이상화 표상(distribution·tonecurve·swatches)은 필수(검증기).
   * "이 색 견본은 실제 사진의 혼합광을 단순화한 모형이에요" 처럼.
   */
  model_note: string | null
  /**
   * 슬라이더가 붙은 그림의 눈금 표시 방식.
   *   quantitative — 화면의 수가 그림에서 실제로 계산되는 값일 때만 (예: 할선의 기울기)
   *   qualitative  — 정성 모형. 낮음/중간/높음 으로만 보여준다.
   * 근거 없는 퍼센트는 사람이 법칙으로 기억한다. 그래서 기본값은 qualitative 다.
   */
  readout: 'quantitative' | 'qualitative'
}

/**
 * 활동. 설명 한 단위마다 학생이 무언가를 결정·예측·계산·표시하게 만든다.
 * 읽기만 하면 이해했다고 착각한다. 이 슬롯이 그 착각을 막는다.
 */
export interface Activity {
  kind: 'predict' | 'decide' | 'compute' | 'draw' | 'explain'
  prompt: string
  /** decide/predict 일 때 고를 것들 */
  options: string[] | null
  /** 학생이 답한 뒤에 보여주는 것. 정답이 아니라 '왜'. */
  reveal: string
}

export type InlineNode = {
  type: 'text' | 'bold' | 'em' | 'code'
  value: string
}

export interface ConceptBlock {
  heading: string
  body: InlineNode[]
  /**
   * 이 블록이 세운 규칙의 경계. 규칙을 진술하는 블록에는 반드시 있어야 한다(린트).
   * 없으면 학생은 "두 점을 붙이면 접선이 된다" 만 떼어 기억한다.
   */
  boundary: Boundary | null
  example: Example | null
  /** 이 블록에서 보여줄 도형 id (figures[] 참조) */
  figure: string | null
  /** 설명 뒤에 학생이 할 일. 블록의 절반 이상에 있어야 한다. */
  activity: Activity | null
  common_mistake: string | null
}

export interface QuizItem {
  kind: QuizKind
  question: string
  choices: string[] | null
  answer: string
  /** 왜 그 답인지. "개념 N번에서 말했어요" 는 해설이 아니다. */
  explanation: string
  difficulty: number
  /**
   * near: 본문의 예를 숫자만 바꾼 것. far: 새 상황·반례·오류 분석.
   * far 가 2개 이상이어야 한다. 전부 near 면 점수와 실력이 분리된다.
   */
  transfer: 'near' | 'far'
  /** 이 문제가 무엇을 증거로 삼는가. 서로 다른 종류가 3가지 이상이어야 한다(검증기). */
  evidence: EvidenceKind
  /** 자주 나오는 오답과 그 이유. 학생 답을 진단하는 데 쓴다. 선택형은 선택지별 피드백이 된다. */
  misconceptions: { wrong: string; why: string }[]
}

export interface NextStep {
  title: string
  why: string
  /** easier 는 "이게 막히면 먼저" — 예전 사전학습 제안이 여기로 왔다. */
  difficulty_delta: 'easier' | 'same' | 'harder'
}

/** ① 설계 단계(claude-opus-5)의 출력. 판단만 담는다. */
export interface WorksheetOutline {
  schema_version: number
  title: string
  topic_normalized: string
  level: Level
  category: Category
  /** 학생이 아직 풀 수 없는 구체적 문제. 학습지 전체가 이 문제로 수렴한다. */
  problem_gist: string
  /** 첫 예측. 흔한 오답이 반드시 선택지에 들어 있어야 한다. */
  prediction: { question: string; options: string[]; common_wrong: string }
  /** 예측을 시험할 증거. 어떤 도형·데이터·예시를 보여줄지 */
  observation_gist: string
  concept_blocks: { heading: string; gist: string; activity_kind: Activity['kind'] | null }[]
  /** 맥락 노트에 쓸 사실. 확실성 판단은 여기서 끝난다. */
  facts: { when: string; what: string; confidence: Confidence }[]
  quiz_plan: { asks: string; answer_gist: string; source_block: number; difficulty: number
               transfer: 'near' | 'far'; evidence: EvidenceKind }[]
  next_steps: NextStep[]
  /** 이 주제에서 학생이 흔히 굳히는 오해 3~5개. 집필은 이걸 막도록 써야 한다. */
  guards: { misconception: string; where: SectionKey; how: string }[]
}

/** ② 집필 단계(claude-sonnet-5)의 출력. 실제 학습지. */
export interface WorksheetContent {
  schema_version: number
  title: string
  topic_normalized: string
  level: Level
  category: Category
  /** 한 줄 정의. 제목 아래에 놓인다. */
  one_liner: string
  /**
   * 시간은 장식이 아니다. 학습자가 계획을 세우는 데 쓴다.
   * core 는 ①~④, practice 는 ⑤ 문제, optional 은 확장 과제(practice.extended 합계와 같아야 한다).
   */
  time: { core: number; practice: number; optional: number }
  /** 이 학습지가 전제하는 것. '입문' 이 무엇에 대한 입문인지 밝힌다. */
  assumes: string[]

  /** 어려운 말을 그 자리에서 푼다. 3~6개. 개념 단계에 놓인다. */
  glossary: { term: string; plain: string }[]
  /** 파르(먼저 헤맨 사람)의 한마디. 오개념 교정·힌트에만, 1~2개. */
  guide_notes: { section: SectionKey; note: string }[]
  /** 과목 특유의 표상. 수학·과학·미술·경제는 최소 1개. */
  figures: Figure[]

  /**
   * 로버스트니스 예산. "이 학습지는 어떤 오해에 버티는가" 를 만들기 전에 적는다.
   * 좋은 학습지는 많은 내용을 담은 것이 아니라 예상 가능한 실패를 막은 것이다.
   * 3~5개. 각각 어디서(where) 어떻게(how) 막는지 밝혀야 하고, 검사관이 실제로 막혔는지 본다.
   */
  robustness: {
    guards: { misconception: string; where: SectionKey; how: string }[]
  }

  /**
   * ① 문제 제시 — 학생이 아직 풀 수 없는 구체적 상황.
   * 개념 이름으로 시작하지 않는다. "미분이란…" 이 아니라 "이 차가 3초 시점에 얼마나 빨랐나".
   */
  problem: {
    situation: InlineNode[]
    /** 학습지가 끝나면 답할 수 있어야 하는 질문 하나 */
    question: string
    why_it_matters: string
    /** 정확히 3개. "이해한다" 가 아니라 증거가 남는 행동으로. */
    objectives: string[]
  }

  /**
   * ② 예측 — 설명을 하나도 읽기 전에 틀릴 기회.
   * hook 은 predict/decide 만. 흔한 오답이 선택지에 있어야 예측이 진단이 된다.
   */
  predict: {
    hook: Activity
    /** 왜 그렇게 골랐는지 한 줄 쓰기 (필기). 이유를 적어야 나중에 자기 생각과 비교할 수 있다. */
    reasoning_prompt: string
  }

  /**
   * ③ 관찰 — 예측을 시험할 증거. 도형(그래프·패턴·커브) 또는 예시(코드·장면·비교) 중 하나는 반드시.
   * 개념 설명은 여기 없다. 무엇이 보이는지만.
   */
  observe: {
    intro: InlineNode[]
    figure: string | null
    example: Example | null
    /** "…를 보세요" 관찰 지시 2~4개. 무엇을 봐야 할지 모르면 관찰이 아니라 감상이다. */
    notice: string[]
    /** 예측과 비교. decide(맞았나/틀렸나/반만) 또는 explain(무엇이 달랐나). */
    compare: Activity
  }

  /** ④ 개념 — 관찰한 것을 설명하는 개념. 비유는 관찰 뒤에 온다. */
  concept: {
    /** 일상 비유. 설명 사다리 ①단. 관찰한 것에 이름을 붙인다. */
    analogy: string
    blocks: ConceptBlock[]              // 2~5개, 절반 이상에 activity
    /**
     * 짧은 역사·맥락. 없어도 된다. 있으면 접힌 채로 나간다.
     * 사실은 confidence=high 만. 미검증 사실은 배지를 달아 내보내지 않고 뺀다.
     */
    context_note: {
      text: InlineNode[]
      facts: { when: string; what: string; confidence: Confidence }[]   // 0~3
    } | null
  }

  /** ⑤ 연습 — 문제 4~7개(far 2개 이상, 증거 종류 3가지 이상) + 확장 과제. */
  practice: {
    quiz: QuizItem[]                    // 4~7개. 개수가 아니라 evidence 종류로 숙달을 센다
    extended: { title: string; detail: string; estimated_minutes: number }[]   // 0~3
  }

  /**
   * ⑥ 나가기 전에 (exit ticket) — 처음 예측으로 돌아가고, 한 문장으로 말하고, 틀린 문장을 골라낸다.
   * 완료감이 아니라 증거를 남기는 단계.
   */
  exit_ticket: {
    /** 처음 예측과 지금 생각이 어디서 달라졌는지 (필기) */
    revisit: string
    /** 개념을 한 문장으로 (필기) */
    one_sentence: string
    /** decide: 틀린 문장 하나 고르기. 오개념이 굳었는지 마지막으로 본다. */
    misconception_check: Activity
    /** 증거 기반 자기 점검 2~4개 */
    self_check: string[]
    /** 내일 해볼 한 가지 */
    apply_tomorrow: string
    next_steps: NextStep[]              // 2~4개
  }
}

/** 렌더러가 필요로 하는, DB 에서 온 식별자들 */
export interface RenderContext {
  worksheetId: string
  /** practice.quiz[i] 에 대응하는 quiz_items.id. 복습 알림이 이 id 로 해당 문제에 스크롤한다. */
  quizItemIds: string[]
  theme?: 'light' | 'dark'
}

/**
 * 6단계. 순서 불변, 전부 핵심 경로. 접히는 것은 개념 안의 맥락 노트뿐이다.
 * 섹션 id(sec-1..sec-6)는 필기 좌표의 앵커라 생략하지 않는다.
 */
export const SECTIONS = [
  { key: 'problem',     title: '문제 제시',   lead: '아직은 못 푸는 문제 하나' },
  { key: 'predict',     title: '예측',        lead: '설명을 읽기 전에 먼저 골라요' },
  { key: 'observe',     title: '관찰',        lead: '예측이 맞았는지 증거를 봐요' },
  { key: 'concept',     title: '개념',        lead: '본 것에 이름을 붙여요' },
  { key: 'practice',    title: '연습',        lead: '새 상황에서 써 봐요' },
  { key: 'exit_ticket', title: '나가기 전에', lead: '처음 예측으로 돌아가요' },
] as const

export const SECTION_KEYS = SECTIONS.map((s) => s.key) as readonly SectionKey[]
