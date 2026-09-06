// WorksheetContent 검증기. 의존성 없음 (Deno/Node 양쪽에서 동일하게 돈다).
//
// 범용 검증기를 쓰지 않는 이유: 실패 메시지가 곧 LLM 재요청 프롬프트가 되기 때문이다.
// "must have required property 'quiz'" 보다 "quiz 는 정확히 5개여야 하는데 4개입니다" 가
// 재요청 성공률을 올린다. 경로와 기대값을 사람이 읽을 수 있게 낸다.

import { SCHEMA_VERSION, SECTION_KEYS, CATEGORIES, EXAMPLE_KINDS } from './worksheet-types.ts'
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
  const category = oneOf(c, r.category, 'category', CATEGORIES)

  // 시간은 세 덩어리로. "약 26분" 하나만 있으면 숙제 40분과 충돌해 아무도 못 믿는다.
  const tm = obj(c, r.time, 'time')
  const time = {
    core: num(c, tm.core, 'time.core', 10, 120),
    practice: num(c, tm.practice, 'time.practice', 0, 90),
    optional: num(c, tm.optional, 'time.optional', 0, 180),
  }

  // '입문' 이 무엇에 대한 입문인지. 선수지식을 숨기지 않는다.
  const assumes = arr(c, r.assumes, 'assumes', 1, 4)
    .map((a, i) => str(c, a, `assumes[${i}]`, { max: 120 }))

  // 활동 하나의 공통 형태. hook 과 블록 활동이 같은 검증을 받는다.
  const activity = (v: unknown, path: string) => {
    const a = obj(c, v, path)
    const kind = oneOf(c, a.kind, `${path}.kind`, ['predict', 'decide', 'compute', 'draw', 'explain'] as const)
    const options = a.options == null ? null
      : arr(c, a.options, `${path}.options`, 2, 5).map((x, j) => str(c, x, `${path}.options[${j}]`, { max: 120 }))
    if ((kind === 'predict' || kind === 'decide') && !options) {
      c.issues.push(at(`${path}.options`, `${kind} 활동은 고를 것(options)이 있어야 합니다`))
    }
    return {
      kind,
      prompt: str(c, a.prompt, `${path}.prompt`, { min: 10, max: 400 }),
      options,
      reveal: str(c, a.reveal, `${path}.reveal`, { min: 10, max: 500 }),
    }
  }

  // ① 무엇을 배우는가 — 일상 비유가 반드시 먼저 온다 (설명 사다리 ①단)
  const w = obj(c, r.what_we_learn, 'what_we_learn')
  const hook = activity(w.hook, 'what_we_learn.hook')
  // 첫 예측은 반드시 고르는 것이어야 한다. 계산이나 그림은 아직 아무것도 모르는 상태에서 시킬 수 없다.
  if (hook.kind !== 'predict' && hook.kind !== 'decide') {
    c.issues.push(at('what_we_learn.hook.kind', `첫 활동은 predict 또는 decide 여야 합니다 (받은 값: ${hook.kind}). 설명 전이라 고를 수만 있습니다`))
  }
  const whatWeLearn = {
    hook,
    analogy: str(c, w.analogy, 'what_we_learn.analogy', { min: 10, max: 400 }),
    summary: inline(c, w.summary, 'what_we_learn.summary'),
    objectives: arr(c, w.objectives, 'what_we_learn.objectives', 3, 3)
      .map((o, i) => str(c, o, `what_we_learn.objectives[${i}]`, { max: 200 })),
    one_liner: str(c, w.one_liner, 'what_we_learn.one_liner', { max: 200 }),
  }

  // 용어 풀이 — 어려운 말을 그 자리에서 푼다
  const glossary = arr(c, r.glossary, 'glossary', 3, 6).map((g, i) => {
    const o = obj(c, g, `glossary[${i}]`)
    return {
      term: str(c, o.term, `glossary[${i}].term`, { max: 60 }),
      plain: str(c, o.plain, `glossary[${i}].plain`, { min: 5, max: 300 }),
    }
  })

  // 파르의 한마디
  // 파르는 오개념 교정·힌트에만. 세 번 넘게 "저도 처음엔…" 하면 목소리가 아니라 문체 템플릿이 된다.
  const guideNotes = arr(c, r.guide_notes, 'guide_notes', 1, 2).map((g, i) => {
    const o = obj(c, g, `guide_notes[${i}]`)
    return {
      section: oneOf(c, o.section, `guide_notes[${i}].section`, SECTION_KEYS),
      note: str(c, o.note, `guide_notes[${i}].note`, { min: 10, max: 400 }),
    }
  })

  // 도형 — 구조화된 스펙만. SVG 문자열은 받지 않는다.
  const figureIds = new Set<string>()
  const figures = arr(c, r.figures, 'figures', 0, 6).map((f, i) => {
    const o = obj(c, f, `figures[${i}]`)
    const id = str(c, o.id, `figures[${i}].id`, { max: 40 })
    if (figureIds.has(id)) c.issues.push(at(`figures[${i}].id`, `중복된 id: ${id}`))
    figureIds.add(id)
    const sp = obj(c, o.spec, `figures[${i}].spec`)
    const kind = oneOf(c, sp.kind, `figures[${i}].spec.kind`, ['plot', 'distribution', 'tonecurve', 'swatches'] as const)
    let spec: any = { kind }
    if (kind === 'plot') {
      const xr = arr(c, sp.xRange, `figures[${i}].spec.xRange`, 2, 2).map((v, j) => num(c, v, `figures[${i}].spec.xRange[${j}]`, -100, 100))
      spec = {
        kind,
        fn: oneOf(c, sp.fn, `figures[${i}].spec.fn`, ['x^2', 'x^3', 'sin', 'exp', 'linear', 'abs'] as const),
        interactive: sp.interactive === true,
        xRange: xr,
        points: sp.points == null ? undefined : arr(c, sp.points, `figures[${i}].spec.points`, 0, 8).map((v, j) => num(c, v, `figures[${i}].spec.points[${j}]`, -100, 100)),
        secant: sp.secant == null ? undefined : arr(c, sp.secant, `figures[${i}].spec.secant`, 2, 2).map((v, j) => num(c, v, `figures[${i}].spec.secant[${j}]`, -100, 100)),
        tangentAt: sp.tangentAt == null ? undefined : num(c, sp.tangentAt, `figures[${i}].spec.tangentAt`, -100, 100),
        label: sp.label == null ? undefined : str(c, sp.label, `figures[${i}].spec.label`, { max: 60 }),
      }
    } else if (kind === 'distribution') {
      // 슬릿 폭을 무시한 점-경로 모델이다. 실제 단일슬릿은 넓은 회절 무늬를 만든다.
      // 이 사실을 그림에 밝히지 않으면 학생이 나중에 실제 사진을 보고 혼란스러워한다.
      if (sp.idealized !== true) {
        c.issues.push(at(`figures[${i}].spec.idealized`, 'distribution 도형은 idealized: true 로 이상화 모델임을 밝혀야 합니다'))
      }
      spec = { kind, interactive: sp.interactive === true, idealized: true, panels: arr(c, sp.panels, `figures[${i}].spec.panels`, 1, 4).map((pn, j) => {
        const po = obj(c, pn, `figures[${i}].spec.panels[${j}]`)
        return {
          title: str(c, po.title, `figures[${i}].spec.panels[${j}].title`, { max: 60 }),
          profile: oneOf(c, po.profile, `figures[${i}].spec.panels[${j}].profile`, ['two-humps', 'fringes', 'fringes-weak', 'single'] as const),
        }
      }) }
    } else if (kind === 'tonecurve') {
      spec = { kind, curve: oneOf(c, sp.curve, `figures[${i}].spec.curve`, ['linear', 's-mild', 's-strong', 'inverse-s'] as const),
               clipHighlights: sp.clipHighlights === true }
    } else {
      spec = { kind, rows: arr(c, sp.rows, `figures[${i}].spec.rows`, 1, 6).map((rw, j) => {
        const ro = obj(c, rw, `figures[${i}].spec.rows[${j}]`)
        return {
          label: str(c, ro.label, `figures[${i}].spec.rows[${j}].label`, { max: 40 }),
          colors: arr(c, ro.colors, `figures[${i}].spec.rows[${j}].colors`, 2, 6).map((col, k) => {
            const v = str(c, col, `figures[${i}].spec.rows[${j}].colors[${k}]`, { max: 9 })
            if (!/^#[0-9a-fA-F]{6}$/.test(v)) c.issues.push(at(`figures[${i}].spec.rows[${j}].colors[${k}]`, '#RRGGBB 형식이어야 합니다'))
            return v
          }),
        }
      }) }
    }
    return {
      id,
      title: str(c, o.title, `figures[${i}].title`, { max: 100 }),
      alt: str(c, o.alt, `figures[${i}].alt`, { min: 10, max: 300 }),
      spec,
      drawTask: nullableStr(c, o.drawTask, `figures[${i}].drawTask`, 300),
    }
  })

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
          const kind = oneOf(c, e.kind, `main_lesson.blocks[${i}].example.kind`, EXAMPLE_KINDS)
          const language = nullableStr(c, e.language, `main_lesson.blocks[${i}].example.language`, 30)
          // language 는 코드에만 붙는다. 계산이나 동작 순서에 'javascript' 가 붙으면 잘못된 것이다.
          if (kind !== 'code' && language) {
            c.issues.push(at(`main_lesson.blocks[${i}].example.language`,
              `kind 가 ${kind} 이면 language 는 null 이어야 합니다`))
          }
          return {
            kind,
            caption: str(c, e.caption, `main_lesson.blocks[${i}].example.caption`, { max: 200 }),
            body: str(c, e.body, `main_lesson.blocks[${i}].example.body`, { min: 1, max: 2000 }),
            language,
          }
        })(),
        figure: (() => {
          const fid = nullableStr(c, o.figure, `main_lesson.blocks[${i}].figure`, 40)
          if (fid && !figureIds.has(fid)) c.issues.push(at(`main_lesson.blocks[${i}].figure`, `figures 에 없는 id: ${fid}`))
          return fid
        })(),
        activity: o.activity == null ? null : activity(o.activity, `main_lesson.blocks[${i}].activity`),
        common_mistake: nullableStr(c, o.common_mistake, `main_lesson.blocks[${i}].common_mistake`, 400),
      }
    }),
  }
  // 설명 한 단위마다 학생이 무언가를 해야 한다. 절반 이상.
  const withActivity = mainLesson.blocks.filter((b) => b.activity).length
  if (withActivity * 2 < mainLesson.blocks.length) {
    c.issues.push(at('main_lesson.blocks', `활동이 있는 블록이 ${withActivity}/${mainLesson.blocks.length} 입니다. 절반 이상이어야 합니다 — 읽기만 하면 이해했다고 착각합니다`))
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
    const explanation = str(c, o.explanation, `quiz[${i}].explanation`, { max: 800 })
    // "본론 N번째 블록에서 말했어요" 는 해설이 아니라 위치 안내다.
    if (/본론\s*[0-9첫두세네다섯]+\s*번째|블록에서\s*(다뤘|말했|설명했)/.test(explanation)) {
      c.issues.push(at(`quiz[${i}].explanation`, '본문 위치를 알려주는 것은 해설이 아닙니다. 왜 그 답인지, 왜 다른 답은 틀리는지를 쓰세요'))
    }
    return {
      kind,
      question: str(c, o.question, `quiz[${i}].question`, { max: 500 }),
      choices,
      answer: str(c, o.answer, `quiz[${i}].answer`, { max: 500 }),
      explanation,
      difficulty: num(c, o.difficulty, `quiz[${i}].difficulty`, 1, 3),
      transfer: oneOf(c, o.transfer, `quiz[${i}].transfer`, ['near', 'far'] as const),
      misconceptions: arr(c, o.misconceptions, `quiz[${i}].misconceptions`, 0, 3).map((m, j) => {
        const mo = obj(c, m, `quiz[${i}].misconceptions[${j}]`)
        return {
          wrong: str(c, mo.wrong, `quiz[${i}].misconceptions[${j}].wrong`, { max: 200 }),
          why: str(c, mo.why, `quiz[${i}].misconceptions[${j}].why`, { max: 300 }),
        }
      }),
    }
  })
  const farCount = quiz.filter((q) => q.transfer === 'far').length
  if (farCount < 2) {
    c.issues.push(at('quiz', `far transfer 문제가 ${farCount}개입니다. 2개 이상이어야 합니다 — 본문 예시를 숫자만 바꾼 문제로는 실력을 알 수 없습니다`))
  }

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
  const hwSum = homework.tasks.reduce((n, t) => n + t.estimated_minutes, 0)
  if (hwSum !== time.optional) {
    c.issues.push(at('time.optional', `숙제 합계(${hwSum}분)와 다릅니다(${time.optional}분). 시간은 학습자가 계획에 쓰는 값이라 어긋나면 안 됩니다`))
  }

  // ⑩ 마무리
  const wu = obj(c, r.wrap_up, 'wrap_up')
  const wrapUp = {
    usage_examples: arr(c, wu.usage_examples, 'wrap_up.usage_examples', 2, 4)
      .map((u, i) => str(c, u, `wrap_up.usage_examples[${i}]`, { max: 300 })),
    daily_life_guide: inline(c, wu.daily_life_guide, 'wrap_up.daily_life_guide'),
    checklist: arr(c, wu.checklist, 'wrap_up.checklist', 2, 6)
      .map((x, i) => str(c, x, `wrap_up.checklist[${i}]`, { max: 200 })),
    reflection: str(c, wu.reflection, 'wrap_up.reflection', { min: 15, max: 300 }),
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
    title, topic_normalized: topic, level, category, time, assumes,
    figures,
    what_we_learn: whatWeLearn,
    glossary,
    guide_notes: guideNotes,
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
