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
  estimated_minutes: number

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
      common_mistake: string | null
    }[]
  }

  pro_tips: { tip: string; why: string }[]   // 3~5개

  quiz: {                                     // 정확히 5개
    kind: QuizKind
    question: string
    choices: string[] | null
    answer: string
    explanation: string
    difficulty: number
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
