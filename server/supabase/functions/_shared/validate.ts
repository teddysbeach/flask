// WorksheetContent 검증기. 의존성 없음 (Deno/Node 양쪽에서 동일하게 돈다).
//
// 범용 검증기를 쓰지 않는 이유: 실패 메시지가 곧 LLM 재요청 프롬프트가 되기 때문이다.
// "must have required property 'quiz'" 보다 "quiz 는 정확히 5개여야 하는데 4개입니다" 가
// 재요청 성공률을 올린다. 경로와 기대값을 사람이 읽을 수 있게 낸다.

import { SCHEMA_VERSION } from './worksheet-types.ts'
import type { WorksheetContent, InlineNode } from './worksheet-types.ts'

export class ValidationError extends Error {
  // 파라미터 프로퍼티(constructor(readonly x))는 쓰지 않는다.
  // Node 의 strip-only 타입 제거가 지원하지 않아서 테스트가 안 돌아간다.
  issues: string[]
  constructor(issues: string[]) {
    super(issues.join('\n'))
    this.name = 'ValidationError'
    this.issues = issues
  }
}

type Ctx = { issues: string[] }

const at = (path: string, msg: string) => `${path}: ${msg}`

function str(c: Ctx, v: unknown, path: string, { min = 1, max = 4000 } = {}): string {
  if (typeof v !== 'string') { c.issues.push(at(path, `문자열이어야 합니다 (받은 값: ${typeof v})`)); return '' }
  const t = v.trim()
  if (t.length < min) c.issues.push(at(path, `${min}자 이상이어야 합니다 (현재 ${t.length}자)`))
  if (t.length > max) c.issues.push(at(path, `${max}자 이하여야 합니다 (현재 ${t.length}자)`))
  return v
}

function num(c: Ctx, v: unknown, path: string, min: number, max: number): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) { c.issues.push(at(path, '숫자여야 합니다')); return min }
  if (v < min || v > max) c.issues.push(at(path, `${min}~${max} 범위여야 합니다 (현재 ${v})`))
  return v
}

function oneOf<T extends string>(c: Ctx, v: unknown, path: string, allowed: readonly T[]): T {
  if (typeof v !== 'string' || !allowed.includes(v as T)) {
    c.issues.push(at(path, `${allowed.join(' / ')} 중 하나여야 합니다 (받은 값: ${JSON.stringify(v)})`))
    return allowed[0]
  }
  return v as T
}

function arr(c: Ctx, v: unknown, path: string, min: number, max: number): unknown[] {
  if (!Array.isArray(v)) { c.issues.push(at(path, '배열이어야 합니다')); return [] }
  if (v.length < min || v.length > max) {
    c.issues.push(at(path, min === max
      ? `정확히 ${min}개여야 하는데 ${v.length}개입니다`
      : `${min}~${max}개여야 하는데 ${v.length}개입니다`))
  }
  return v
}

const INLINE_TYPES = ['text', 'bold', 'em', 'code'] as const

function inline(c: Ctx, v: unknown, path: string, min = 1): InlineNode[] {
  const list = arr(c, v, path, min, 60)
  return list.map((n, i) => {
    const p = `${path}[${i}]`
    if (typeof n !== 'object' || n === null) { c.issues.push(at(p, '{type, value} 객체여야 합니다')); return { type: 'text', value: '' } as InlineNode }
    const o = n as Record<string, unknown>
    return { type: oneOf(c, o.type, `${p}.type`, INLINE_TYPES), value: str(c, o.value, `${p}.value`, { min: 0, max: 2000 }) }
  })
}

function obj(c: Ctx, v: unknown, path: string): Record<string, unknown> {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) {
    c.issues.push(at(path, '객체여야 합니다'))
    return {}
  }
  return v as Record<string, unknown>
}

const nullableStr = (c: Ctx, v: unknown, path: string, max = 600): string | null =>
  v === null || v === undefined ? null : str(c, v, path, { max })

/**
 * 검증하고 정규화한 값을 돌려준다. 실패하면 ValidationError 를 던진다.
 * error.issues 를 그대로 LLM 재요청 프롬프트에 붙인다.
 */
export function validateWorksheet(input: unknown): WorksheetContent {
  const c: Ctx = { issues: [] }
  const r = obj(c, input, 'root')

  if (r.schema_version !== SCHEMA_VERSION) {
    c.issues.push(at('schema_version', `${SCHEMA_VERSION} 이어야 합니다 (받은 값: ${JSON.stringify(r.schema_version)})`))
  }

  const title = str(c, r.title, 'title', { max: 80 })
  const topic = str(c, r.topic_normalized, 'topic_normalized', { max: 120 })
  const level = oneOf(c, r.level, 'level', ['beginner', 'intermediate', 'advanced'] as const)
  const minutes = num(c, r.estimated_minutes, 'estimated_minutes', 5, 180)

  // ① 무엇을 배우는가
  const w = obj(c, r.what_we_learn, 'what_we_learn')
  const whatWeLearn = {
    summary: inline(c, w.summary, 'what_we_learn.summary'),
    objectives: arr(c, w.objectives, 'what_we_learn.objectives', 3, 3)
      .map((o, i) => str(c, o, `what_we_learn.objectives[${i}]`, { max: 200 })),
    one_liner: str(c, w.one_liner, 'what_we_learn.one_liner', { max: 200 }),
  }

  // ② 이전에는 어땠는지
  const b = obj(c, r.before_and_need, 'before_and_need')
  const beforeAndNeed = {
    world_before: inline(c, b.world_before, 'before_and_need.world_before'),
    pain_points: arr(c, b.pain_points, 'before_and_need.pain_points', 2, 4)
      .map((p, i) => str(c, p, `before_and_need.pain_points[${i}]`, { max: 300 })),
    why_it_emerged: inline(c, b.why_it_emerged, 'before_and_need.why_it_emerged'),
  }

  // ③ 사전학습 제안 3개
  const prerequisites = arr(c, r.prerequisites, 'prerequisites', 3, 3).map((p, i) => {
    const o = obj(c, p, `prerequisites[${i}]`)
    return {
      title: str(c, o.title, `prerequisites[${i}].title`, { max: 80 }),
      why: str(c, o.why, `prerequisites[${i}].why`, { max: 300 }),
      one_liner: str(c, o.one_liner, `prerequisites[${i}].one_liner`, { max: 200 }),
    }
  })

  // ④ 탄생 배경
  const os = obj(c, r.origin_story, 'origin_story')
  const originStory = {
    timeline: arr(c, os.timeline, 'origin_story.timeline', 2, 5).map((t, i) => {
      const o = obj(c, t, `origin_story.timeline[${i}]`)
      return {
        when: str(c, o.when, `origin_story.timeline[${i}].when`, { max: 60 }),
        what: str(c, o.what, `origin_story.timeline[${i}].what`, { max: 400 }),
        confidence: oneOf(c, o.confidence, `origin_story.timeline[${i}].confidence`, ['high', 'medium', 'low'] as const),
      }
    }),
    narrative: inline(c, os.narrative, 'origin_story.narrative'),
    uncertainty_note: nullableStr(c, os.uncertainty_note, 'origin_story.uncertainty_note'),
  }

  // ⑤ 상황극
  const rp = obj(c, r.roleplay, 'roleplay')
  const mode = oneOf(c, rp.mode, 'roleplay.mode', ['real_case', 'hypothetical'] as const)
  const disclaimer = nullableStr(c, rp.disclaimer, 'roleplay.disclaimer')
  // 정직성 규칙: 가상 시나리오는 반드시 그렇다고 밝힌다.
  if (mode === 'hypothetical' && !disclaimer) {
    c.issues.push(at('roleplay.disclaimer', 'mode 가 hypothetical 이면 가상임을 밝히는 disclaimer 가 반드시 있어야 합니다'))
  }
  const roleplay = {
    mode,
    scene: str(c, rp.scene, 'roleplay.scene', { max: 600 }),
    dialogue: arr(c, rp.dialogue, 'roleplay.dialogue', 2, 12).map((d, i) => {
      const o = obj(c, d, `roleplay.dialogue[${i}]`)
      return {
        speaker: str(c, o.speaker, `roleplay.dialogue[${i}].speaker`, { max: 40 }),
        line: str(c, o.line, `roleplay.dialogue[${i}].line`, { max: 500 }),
      }
    }),
    takeaway: inline(c, rp.takeaway, 'roleplay.takeaway'),
    disclaimer,
  }

  // ⑥ 본론
  const ml = obj(c, r.main_lesson, 'main_lesson')
  const mainLesson = {
    blocks: arr(c, ml.blocks, 'main_lesson.blocks', 3, 6).map((blk, i) => {
      const o = obj(c, blk, `main_lesson.blocks[${i}]`)
      const ex = o.example
      return {
        heading: str(c, o.heading, `main_lesson.blocks[${i}].heading`, { max: 100 }),
        body: inline(c, o.body, `main_lesson.blocks[${i}].body`),
        example: ex === null || ex === undefined ? null : (() => {
          const e = obj(c, ex, `main_lesson.blocks[${i}].example`)
          return {
            caption: str(c, e.caption, `main_lesson.blocks[${i}].example.caption`, { max: 200 }),
            code: nullableStr(c, e.code, `main_lesson.blocks[${i}].example.code`, 2000),
            language: nullableStr(c, e.language, `main_lesson.blocks[${i}].example.language`, 30),
          }
        })(),
        common_mistake: nullableStr(c, o.common_mistake, `main_lesson.blocks[${i}].common_mistake`, 400),
      }
    }),
  }

  // ⑦ 꿀팁
  const proTips = arr(c, r.pro_tips, 'pro_tips', 3, 5).map((t, i) => {
    const o = obj(c, t, `pro_tips[${i}]`)
    return {
      tip: str(c, o.tip, `pro_tips[${i}].tip`, { max: 200 }),
      why: str(c, o.why, `pro_tips[${i}].why`, { max: 300 }),
    }
  })

  // ⑧ 질의 5개
  const quiz = arr(c, r.quiz, 'quiz', 5, 5).map((q, i) => {
    const o = obj(c, q, `quiz[${i}]`)
    const kind = oneOf(c, o.kind, `quiz[${i}].kind`, ['short_answer', 'multiple_choice', 'explain'] as const)
    let choices: string[] | null = null
    if (kind === 'multiple_choice') {
      choices = arr(c, o.choices, `quiz[${i}].choices`, 3, 5)
        .map((ch, j) => str(c, ch, `quiz[${i}].choices[${j}]`, { max: 200 }))
    } else if (o.choices != null) {
      c.issues.push(at(`quiz[${i}].choices`, `kind 이 ${kind} 이면 choices 는 null 이어야 합니다`))
    }
    return {
      kind,
      question: str(c, o.question, `quiz[${i}].question`, { max: 500 }),
      choices,
      answer: str(c, o.answer, `quiz[${i}].answer`, { max: 500 }),
      explanation: str(c, o.explanation, `quiz[${i}].explanation`, { max: 800 }),
      difficulty: num(c, o.difficulty, `quiz[${i}].difficulty`, 1, 3),
    }
  })

  // ⑨ 숙제
  const hw = obj(c, r.homework, 'homework')
  const homework = {
    tasks: arr(c, hw.tasks, 'homework.tasks', 1, 3).map((t, i) => {
      const o = obj(c, t, `homework.tasks[${i}]`)
      return {
        title: str(c, o.title, `homework.tasks[${i}].title`, { max: 100 }),
        detail: str(c, o.detail, `homework.tasks[${i}].detail`, { max: 800 }),
        estimated_minutes: num(c, o.estimated_minutes, `homework.tasks[${i}].estimated_minutes`, 5, 180),
      }
    }),
    submission_hint: str(c, hw.submission_hint, 'homework.submission_hint', { max: 400 }),
  }

  // ⑩ 마무리
  const wu = obj(c, r.wrap_up, 'wrap_up')
  const wrapUp = {
    usage_examples: arr(c, wu.usage_examples, 'wrap_up.usage_examples', 2, 4)
      .map((u, i) => str(c, u, `wrap_up.usage_examples[${i}]`, { max: 300 })),
    daily_life_guide: inline(c, wu.daily_life_guide, 'wrap_up.daily_life_guide'),
    checklist: arr(c, wu.checklist, 'wrap_up.checklist', 2, 6)
      .map((x, i) => str(c, x, `wrap_up.checklist[${i}]`, { max: 200 })),
  }

  // ⑪ 다음 단계
  const nextSteps = arr(c, r.next_steps, 'next_steps', 3, 3).map((n, i) => {
    const o = obj(c, n, `next_steps[${i}]`)
    return {
      title: str(c, o.title, `next_steps[${i}].title`, { max: 80 }),
      why: str(c, o.why, `next_steps[${i}].why`, { max: 300 }),
      difficulty_delta: oneOf(c, o.difficulty_delta, `next_steps[${i}].difficulty_delta`, ['same', 'harder'] as const),
    }
  })

  if (c.issues.length) throw new ValidationError(c.issues)

  return {
    schema_version: SCHEMA_VERSION,
    title, topic_normalized: topic, level, estimated_minutes: minutes,
    what_we_learn: whatWeLearn,
    before_and_need: beforeAndNeed,
    prerequisites,
    origin_story: originStory,
    roleplay,
    main_lesson: mainLesson,
    pro_tips: proTips,
    quiz,
    homework,
    wrap_up: wrapUp,
    next_steps: nextSteps,
  }
}
