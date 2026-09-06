// 학습지 데이터 계약. docs/plan/04-worksheet-spec.md §3
//
// LLM 은 이 모양의 JSON 만 만든다. HTML 은 render.ts 가 조립한다.
// 인라인 마크업도 LLM 이 태그를 쓰는 게 아니라 InlineNode 배열로 받아 렌더러가 태그를 만든다.
// 이 규칙 하나가 프롬프트 인젝션이 HTML 인젝션으로 번지는 경로를 끊는다.

export const SCHEMA_VERSION = 1

/** 11개 섹션 키. SECTIONS 상수는 파일 하단에 있고 값이 같아야 한다(테스트가 검사). */
export type SectionKey =
  | 'what_we_learn' | 'before_and_need' | 'prerequisites' | 'origin_story'
  | 'roleplay' | 'main_lesson' | 'pro_tips' | 'quiz' | 'homework'
  | 'wrap_up' | 'next_steps'

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
  | { kind: 'plot'; fn: 'x^2' | 'x^3' | 'sin' | 'exp' | 'linear'; xRange: [number, number]
      points?: number[]; secant?: [number, number]; tangentAt?: number; label?: string }
  | { kind: 'distribution'; panels: { title: string; profile: 'two-humps' | 'fringes' | 'fringes-weak' | 'single' }[] }
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
export const EXAMPLE_KINDS: readonly ExampleKind[] = ['code', 'calc', 'steps', 'compare', 'scene']

export type InlineNode = {
  type: 'text' | 'bold' | 'em' | 'code'
  value: string
}

/** ① 설계 단계(claude-opus-5)의 출력. 판단만 담는다. */
export interface WorksheetOutline {
  schema_version: number
  title: string
  topic_normalized: string
  level: Level
  estimated_minutes: number
  section_briefs: { section: string; bullets: string[]; target_tokens: number }[]
  facts: { when: string; what: string; confidence: Confidence }[]
  roleplay_mode: 'real_case' | 'hypothetical'
  quiz_plan: { asks: string; answer_gist: string; source_block: number; difficulty: number }[]
  prerequisites: { title: string; why: string; one_liner: string }[]
  next_steps: { title: string; why: string; difficulty_delta: 'same' | 'harder' }[]
}

/** ② 집필 단계(claude-sonnet-5)의 출력. 실제 학습지. */
export interface WorksheetContent {
  schema_version: number
  title: string
  topic_normalized: string
  level: Level
  category: Category
  /**
   * 시간은 장식이 아니다. 학습자가 계획을 세우는 데 쓴다.
   * core 는 본문+문제, practice 는 활동, optional 은 숙제(homework 합계와 같아야 한다).
   */
  time: { core: number; practice: number; optional: number }
  /** 이 학습지가 전제하는 것. '입문' 이 무엇에 대한 입문인지 밝힌다. */
  assumes: string[]

  what_we_learn: {
    /** 일상 비유. 설명 사다리 ①단이고 학습지 맨 앞에 온다. 이게 없으면 독자는 걸어둘 못이 없다. */
    analogy: string
    summary: InlineNode[]
    objectives: string[]          // 정확히 3개
    one_liner: string
  }

  /** 어려운 말을 그 자리에서 푼다. 3~6개. docs/plan/11-voice-and-persona.md §3 */
  glossary: { term: string; plain: string }[]

  /** 파르(먼저 헤맨 사람)의 한마디. 막히기 쉬운 지점에 2~4개. */
  guide_notes: { section: SectionKey; note: string }[]

  before_and_need: {
    world_before: InlineNode[]
    pain_points: string[]         // 2~4개
    why_it_emerged: InlineNode[]
  }

  prerequisites: { title: string; why: string; one_liner: string }[]  // 정확히 3개

  origin_story: {
    timeline: { when: string; what: string; confidence: Confidence }[]  // 2~5개
    narrative: InlineNode[]
    uncertainty_note: string | null
  }

  roleplay: {
    mode: 'real_case' | 'hypothetical'
    scene: string
    dialogue: { speaker: string; line: string }[]
    takeaway: InlineNode[]
    disclaimer: string | null     // hypothetical 이면 필수
  }

  main_lesson: {
    blocks: {                     // 3~6개
      heading: string
      body: InlineNode[]
      example: {
        kind: ExampleKind
        caption: string
        /** 여러 줄 텍스트. steps 는 줄바꿈으로, compare 는 `전 | 후` 로 나눈다. */
        body: string
        /** kind 가 'code' 일 때만 쓴다. */
        language: string | null
      } | null
      /** 이 블록에서 보여줄 도형 id (figures[] 참조) */
      figure: string | null
      /** 설명 뒤에 학생이 할 일. 블록의 절반 이상에 있어야 한다. */
      activity: Activity | null
      common_mistake: string | null
    }[]
  }

  /** 과목 특유의 표상. 수학·과학·미술은 최소 1개. */
  figures: Figure[]

  pro_tips: { tip: string; why: string }[]   // 3~5개

  quiz: {                                     // 정확히 5개
    kind: QuizKind
    question: string
    choices: string[] | null
    answer: string
    /** 왜 그 답인지. "본론 N번에서 말했어요" 는 해설이 아니다. */
    explanation: string
    difficulty: number
    /**
     * near: 본문의 예를 숫자만 바꾼 것. far: 새 상황·반례·오류 분석.
     * 5개 중 far 가 2개 이상이어야 한다. 전부 near 면 점수와 실력이 분리된다.
     */
    transfer: 'near' | 'far'
    /** 자주 나오는 오답과 그 이유. 학생 답을 진단하는 데 쓴다. */
    misconceptions: { wrong: string; why: string }[]
  }[]

  homework: {
    tasks: { title: string; detail: string; estimated_minutes: number }[]
    submission_hint: string
  }

  wrap_up: {
    usage_examples: string[]      // 2~4개
    daily_life_guide: InlineNode[]
    checklist: string[]
  }

  next_steps: { title: string; why: string; difficulty_delta: 'same' | 'harder' }[]
}

/** 렌더러가 필요로 하는, DB 에서 온 식별자들 */
export interface RenderContext {
  worksheetId: string
  /** quiz[i] 에 대응하는 quiz_items.id. 복습 알림이 이 id 로 해당 문제에 스크롤한다. */
  quizItemIds: string[]
  theme?: 'light' | 'dark'
}

/** 11개 섹션. 순서 불변이고 내용이 빈약해도 생략하지 않는다. */
export const SECTIONS = [
  { key: 'what_we_learn',   title: '무엇을 배우는가',        ink: 'sm' },
  { key: 'before_and_need', title: '이것이 생기기 전에는',    ink: 'md' },
  { key: 'prerequisites',   title: '먼저 보면 좋은 학습지',   ink: 'sm' },
  { key: 'origin_story',    title: '탄생 배경',              ink: 'md' },
  { key: 'roleplay',        title: '상황극 & 예시',          ink: 'md' },
  { key: 'main_lesson',     title: '본론',                   ink: 'lg' },
  { key: 'pro_tips',        title: '꿀팁',                   ink: 'md' },
  { key: 'quiz',            title: '질의 5개',               ink: 'sm' },
  { key: 'homework',        title: '숙제 & 과제',            ink: 'lg' },
  { key: 'wrap_up',         title: '마무리 팁',              ink: 'md' },
  { key: 'next_steps',      title: '다음 단계 제안',          ink: 'sm' },
] as const

export const SECTION_KEYS = SECTIONS.map((s) => s.key) as readonly SectionKey[]
