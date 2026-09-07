// 학습지 데이터 계약. docs/plan/04-worksheet-spec.md §3
//
// LLM 은 이 모양의 JSON 만 만든다. HTML 은 render.ts 가 조립한다.
// 인라인 마크업도 LLM 이 태그를 쓰는 게 아니라 InlineNode 배열로 받아 렌더러가 태그를 만든다.
// 이 규칙 하나가 프롬프트 인젝션이 HTML 인젝션으로 번지는 경로를 끊는다.
//
// V5: 11개 섹션 템플릿을 버리고 학습 순서 6단계로 바꿨다.
//   문제 제시 → 예측 → 관찰 → 개념 → 연습 → 나가기 전에(exit ticket)
// 두 번째 외부 평가의 결론이 "구조 자체를 해체하라" 였고, 사용자가 그 제안을 받아들였다.
// 역사·상황극·꿀팁·사전학습 섹션은 사라졌다. 남길 가치가 있는 것은 개념 단계의
// 짧은 맥락 노트(context_note)와 다음 단계(next_steps, easier 포함)로 흡수했다.

export const SCHEMA_VERSION = 2

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
      /** true 면 경로정보 슬라이더로 간섭 가시도가 연속적으로 줄어드는 것을 본다 */
      interactive?: boolean
      /** 슬릿 폭을 무시한 이상화 모델임을 그림에 밝힌다. distribution 은 항상 true 여야 한다(검증기). */
      idealized?: boolean }
  | { kind: 'tonecurve'; curve: 'linear' | 's-mild' | 's-strong' | 'inverse-s'; clipHighlights?: boolean }
  | { kind: 'swatches'; rows: { label: string; colors: string[] }[] }

export interface Figure {
  id: string
  title: string
  /** 스크린리더용. 그림이 무엇을 보여주는지 문장으로. */
  alt: string
  spec: FigureSpec
  /** 학생이 그림에 직접 표시해야 하는 것. 있으면 그림 위에 필기 여백을 겹친다. */
  drawTask: string | null
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
   * 5개 중 far 가 2개 이상이어야 한다. 전부 near 면 점수와 실력이 분리된다.
   */
  transfer: 'near' | 'far'
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
  quiz_plan: { asks: string; answer_gist: string; source_block: number; difficulty: number; transfer: 'near' | 'far' }[]
  next_steps: NextStep[]
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

  /** ⑤ 연습 — 문제 5개(far 2개 이상) + 확장 과제. */
  practice: {
    quiz: QuizItem[]                    // 정확히 5개
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
