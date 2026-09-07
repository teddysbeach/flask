// WorksheetContent 검증기. 의존성 없음 (Deno/Node 양쪽에서 동일하게 돈다).
//
// 범용 검증기를 쓰지 않는 이유: 실패 메시지가 곧 LLM 재요청 프롬프트가 되기 때문이다.
// "must have required property 'quiz'" 보다 "quiz 는 정확히 5개여야 하는데 4개입니다" 가
// 재요청 성공률을 올린다. 경로와 기대값을 사람이 읽을 수 있게 낸다.

import { SCHEMA_VERSION, SECTION_KEYS, CATEGORIES, EXAMPLE_KINDS, EVIDENCE_KINDS } from './worksheet-types.ts'
import { ASSET_IDS } from './assets.g.ts'
import type { WorksheetContent, InlineNode, Activity, Example, Boundary } from './worksheet-types.ts'

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
  const oneLiner = str(c, r.one_liner, 'one_liner', { max: 200 })

  // 시간은 세 덩어리로. "약 26분" 하나만 있으면 확장 과제 40분과 충돌해 아무도 못 믿는다.
  const tm = obj(c, r.time, 'time')
  const time = {
    core: num(c, tm.core, 'time.core', 10, 120),
    practice: num(c, tm.practice, 'time.practice', 0, 90),
    optional: num(c, tm.optional, 'time.optional', 0, 180),
  }

  // '입문' 이 무엇에 대한 입문인지. 선수지식을 숨기지 않는다.
  const assumes = arr(c, r.assumes, 'assumes', 1, 4)
    .map((a, i) => str(c, a, `assumes[${i}]`, { max: 120 }))

  // ── 공통 조각 ────────────────────────────────────────────────────────────
  const activity = (v: unknown, path: string, allowed: readonly Activity['kind'][] = ['predict', 'decide', 'compute', 'draw', 'explain']): Activity => {
    const a = obj(c, v, path)
    const kind = oneOf(c, a.kind, `${path}.kind`, allowed)
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

  const example = (v: unknown, path: string): Example => {
    const e = obj(c, v, path)
    const kind = oneOf(c, e.kind, `${path}.kind`, EXAMPLE_KINDS)
    const language = nullableStr(c, e.language, `${path}.language`, 30)
    // language 는 코드에만 붙는다. 계산이나 동작 순서에 'javascript' 가 붙으면 잘못된 것이다.
    if (kind !== 'code' && language) {
      c.issues.push(at(`${path}.language`, `kind 가 ${kind} 이면 language 는 null 이어야 합니다`))
    }
    return {
      kind,
      caption: str(c, e.caption, `${path}.caption`, { max: 200 }),
      body: str(c, e.body, `${path}.body`, { min: 1, max: 2000 }),
      language,
    }
  }

  // 규칙의 경계. 둘 다 있어야 의미가 있다 — 조건만 있고 반례가 없으면 여전히 절대법칙이다.
  const boundary = (v: unknown, path: string): Boundary => {
    const o = obj(c, v, path)
    return {
      holds_when: str(c, o.holds_when, `${path}.holds_when`, { min: 5, max: 300 }),
      breaks_when: str(c, o.breaks_when, `${path}.breaks_when`, { min: 5, max: 300 }),
    }
  }

  const fact = (v: unknown, path: string) => {
    const o = obj(c, v, path)
    return {
      when: str(c, o.when, `${path}.when`, { max: 60 }),
      what: str(c, o.what, `${path}.what`, { max: 400 }),
      confidence: oneOf(c, o.confidence, `${path}.confidence`, ['high', 'medium', 'low'] as const),
    }
  }

  // 용어 풀이 — 어려운 말을 그 자리에서 푼다
  const glossary = arr(c, r.glossary, 'glossary', 3, 6).map((g, i) => {
    const o = obj(c, g, `glossary[${i}]`)
    return {
      term: str(c, o.term, `glossary[${i}].term`, { max: 60 }),
      plain: str(c, o.plain, `glossary[${i}].plain`, { min: 5, max: 300 }),
    }
  })

  // 파르의 한마디 — 오개념 교정·힌트에만. 세 번 넘게 "저도 처음엔…" 하면 문체 템플릿이 된다.
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
    const kind = oneOf(c, sp.kind, `figures[${i}].spec.kind`, ['plot', 'distribution', 'tonecurve', 'swatches', 'photo'] as const)
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
    } else if (kind === 'photo') {
      // 실물 자극은 등록된 것만. 라이선스와 출처를 확인하지 않은 이미지는 제품에 못 들어간다.
      const assetId = str(c, sp.assetId, `figures[${i}].spec.assetId`, { max: 60 })
      if (!ASSET_IDS.includes(assetId)) {
        c.issues.push(at(`figures[${i}].spec.assetId`,
          `assets/manifest.json 에 없는 자산입니다: ${assetId}. 라이선스·출처가 확인된 사진만 쓸 수 있습니다`))
      }
      const cmp = sp.compareAssetId == null ? undefined : str(c, sp.compareAssetId, `figures[${i}].spec.compareAssetId`, { max: 60 })
      if (cmp && !ASSET_IDS.includes(cmp)) {
        c.issues.push(at(`figures[${i}].spec.compareAssetId`, `assets/manifest.json 에 없는 자산입니다: ${cmp}`))
      }
      spec = { kind, assetId, compareAssetId: cmp }
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
    // 이상화 표상은 자기가 무엇을 생략했는지 말해야 한다.
    // 단순화는 죄가 아니다. 단순화를 현실의 법칙처럼 숨기는 것이 문제다.
    const IDEALIZED = ['distribution', 'tonecurve', 'swatches']
    const modelNote = nullableStr(c, o.model_note, `figures[${i}].model_note`, 300)
    if (IDEALIZED.includes(kind) && !modelNote) {
      c.issues.push(at(`figures[${i}].model_note`,
        `${kind} 은 이상화 모형이라 model_note 로 무엇을 생략했는지 밝혀야 합니다`))
    }
    // 근거 없는 숫자 정밀도 금지. 화면의 수는 그림에서 실제로 계산되는 값일 때만 쓴다.
    const readout = oneOf(c, o.readout ?? 'qualitative', `figures[${i}].readout`, ['quantitative', 'qualitative'] as const)
    if (readout === 'quantitative' && kind !== 'plot') {
      c.issues.push(at(`figures[${i}].readout`,
        `${kind} 에는 정량 눈금을 붙일 수 없습니다. 이 모형에서 나오는 퍼센트는 실제 법칙이 아니라 학생이 법칙으로 기억하게 됩니다 — 'qualitative' 로 두세요`))
    }
    return {
      id,
      title: str(c, o.title, `figures[${i}].title`, { max: 100 }),
      alt: str(c, o.alt, `figures[${i}].alt`, { min: 10, max: 300 }),
      spec,
      drawTask: nullableStr(c, o.drawTask, `figures[${i}].drawTask`, 300),
      model_note: modelNote,
      readout,
    }
  })
  const figureRef = (v: unknown, path: string): string | null => {
    const fid = nullableStr(c, v, path, 40)
    if (fid && !figureIds.has(fid)) c.issues.push(at(path, `figures 에 없는 id: ${fid}`))
    return fid
  }

  // 로버스트니스 예산 — 이 학습지가 막아야 할 오해를 먼저 적는다.
  // 좋은 학습지는 많은 내용을 담은 것이 아니라 예상 가능한 실패를 막은 것이다.
  const rb = obj(c, r.robustness, 'robustness')
  const guards = arr(c, rb.guards, 'robustness.guards', 3, 5).map((g, i) => {
    const o = obj(c, g, `robustness.guards[${i}]`)
    return {
      misconception: str(c, o.misconception, `robustness.guards[${i}].misconception`, { min: 5, max: 200 }),
      where: oneOf(c, o.where, `robustness.guards[${i}].where`, SECTION_KEYS),
      how: str(c, o.how, `robustness.guards[${i}].how`, { min: 10, max: 300 }),
    }
  })

  // ① 문제 제시 — 개념 이름이 아니라 아직 못 푸는 구체적 상황으로 연다
  const pb = obj(c, r.problem, 'problem')
  const question = str(c, pb.question, 'problem.question', { min: 10, max: 300 })
  if (!/[?？]\s*$/.test(question.trim())) {
    c.issues.push(at('problem.question', '학습지가 끝나면 답할 수 있어야 하는 "질문" 이어야 합니다 (물음표로 끝나게)'))
  }
  const problem = {
    situation: inline(c, pb.situation, 'problem.situation'),
    question,
    why_it_matters: str(c, pb.why_it_matters, 'problem.why_it_matters', { min: 10, max: 300 }),
    objectives: arr(c, pb.objectives, 'problem.objectives', 3, 3)
      .map((o, i) => str(c, o, `problem.objectives[${i}]`, { max: 200 })),
  }

  // ② 예측 — 설명 전이라 고를 수만 있다. 계산이나 그림은 아직 시킬 수 없다.
  const pd = obj(c, r.predict, 'predict')
  const hook = activity(pd.hook, 'predict.hook', ['predict', 'decide'])
  const predict = {
    hook,
    reasoning_prompt: str(c, pd.reasoning_prompt, 'predict.reasoning_prompt', { min: 10, max: 300 }),
  }

  // ③ 관찰 — 증거(도형 또는 예시)가 없으면 관찰이 아니다
  const ob = obj(c, r.observe, 'observe')
  const observe = {
    intro: inline(c, ob.intro, 'observe.intro'),
    figure: figureRef(ob.figure, 'observe.figure'),
    example: ob.example == null ? null : example(ob.example, 'observe.example'),
    notice: arr(c, ob.notice, 'observe.notice', 2, 4).map((x, i) => str(c, x, `observe.notice[${i}]`, { max: 200 })),
    compare: activity(ob.compare, 'observe.compare', ['decide', 'explain']),
  }
  if (!observe.figure && !observe.example) {
    c.issues.push(at('observe', '관찰할 증거가 없습니다. figure(도형) 나 example(코드·장면·비교) 중 하나는 반드시 있어야 합니다'))
  }

  // ④ 개념 — 관찰한 것에 이름을 붙인다
  const cp = obj(c, r.concept, 'concept')
  const blocks = arr(c, cp.blocks, 'concept.blocks', 2, 5).map((blk, i) => {
    const o = obj(c, blk, `concept.blocks[${i}]`)
    return {
      heading: str(c, o.heading, `concept.blocks[${i}].heading`, { max: 100 }),
      body: inline(c, o.body, `concept.blocks[${i}].body`),
      boundary: o.boundary == null ? null : boundary(o.boundary, `concept.blocks[${i}].boundary`),
      example: o.example == null ? null : example(o.example, `concept.blocks[${i}].example`),
      figure: figureRef(o.figure, `concept.blocks[${i}].figure`),
      activity: o.activity == null ? null : activity(o.activity, `concept.blocks[${i}].activity`),
      common_mistake: nullableStr(c, o.common_mistake, `concept.blocks[${i}].common_mistake`, 400),
    }
  })
  // 설명 한 단위마다 학생이 무언가를 해야 한다. 절반 이상.
  const withActivity = blocks.filter((b) => b.activity).length
  if (withActivity * 2 < blocks.length) {
    c.issues.push(at('concept.blocks', `활동이 있는 블록이 ${withActivity}/${blocks.length} 입니다. 절반 이상이어야 합니다 — 읽기만 하면 이해했다고 착각합니다`))
  }
  // 규칙을 세웠으면 그 규칙이 깨지는 경우도 최소 하나는 보여야 한다.
  // 예외는 부록이 아니라 개념의 일부다.
  if (!blocks.some((b) => b.boundary)) {
    c.issues.push(at('concept.blocks', '규칙의 경계(boundary)를 밝힌 블록이 하나도 없습니다. 최소 한 블록에 "언제 성립하고(holds_when) 언제 깨지는지(breaks_when)" 를 적으세요 — 조건 없는 규칙은 절대법칙으로 기억됩니다'))
  }

  const cn = cp.context_note
  const contextNote = cn == null ? null : (() => {
    const o = obj(c, cn, 'concept.context_note')
    return {
      text: inline(c, o.text, 'concept.context_note.text'),
      facts: arr(c, o.facts, 'concept.context_note.facts', 0, 3).map((f, i) => fact(f, `concept.context_note.facts[${i}]`)),
    }
  })()
  const concept = {
    analogy: str(c, cp.analogy, 'concept.analogy', { min: 10, max: 400 }),
    blocks,
    context_note: contextNote,
  }

  // ⑤ 연습 — 문제 5개 + 확장 과제
  const pr = obj(c, r.practice, 'practice')
  // 문제 수는 고정하지 않는다. "모든 학습지는 5문제" 는 제작 규격이지 학습 증거가 아니다.
  // 대신 증거 종류를 요구한다 (아래).
  const quiz = arr(c, pr.quiz, 'practice.quiz', 4, 7).map((q, i) => {
    const o = obj(c, q, `practice.quiz[${i}]`)
    const kind = oneOf(c, o.kind, `practice.quiz[${i}].kind`, ['short_answer', 'multiple_choice', 'explain'] as const)
    let choices: string[] | null = null
    if (kind === 'multiple_choice') {
      choices = arr(c, o.choices, `practice.quiz[${i}].choices`, 3, 5)
        .map((ch, j) => str(c, ch, `practice.quiz[${i}].choices[${j}]`, { max: 200 }))
    } else if (o.choices != null) {
      c.issues.push(at(`practice.quiz[${i}].choices`, `kind 이 ${kind} 이면 choices 는 null 이어야 합니다`))
    }
    const explanation = str(c, o.explanation, `practice.quiz[${i}].explanation`, { max: 800 })
    // "개념 N번째 블록에서 말했어요" 는 해설이 아니라 위치 안내다.
    if (/(본론|개념)\s*[0-9첫두세네다섯]+\s*번째|블록에서\s*(다뤘|말했|설명했)/.test(explanation)) {
      c.issues.push(at(`practice.quiz[${i}].explanation`, '본문 위치를 알려주는 것은 해설이 아닙니다. 왜 그 답인지, 왜 다른 답은 틀리는지를 쓰세요'))
    }
    return {
      kind,
      question: str(c, o.question, `practice.quiz[${i}].question`, { max: 500 }),
      choices,
      answer: str(c, o.answer, `practice.quiz[${i}].answer`, { max: 500 }),
      explanation,
      difficulty: num(c, o.difficulty, `practice.quiz[${i}].difficulty`, 1, 3),
      transfer: oneOf(c, o.transfer, `practice.quiz[${i}].transfer`, ['near', 'far'] as const),
      evidence: oneOf(c, o.evidence, `practice.quiz[${i}].evidence`, EVIDENCE_KINDS),
      misconceptions: arr(c, o.misconceptions, `practice.quiz[${i}].misconceptions`, 0, 3).map((m, j) => {
        const mo = obj(c, m, `practice.quiz[${i}].misconceptions[${j}]`)
        return {
          wrong: str(c, mo.wrong, `practice.quiz[${i}].misconceptions[${j}].wrong`, { max: 200 }),
          why: str(c, mo.why, `practice.quiz[${i}].misconceptions[${j}].why`, { max: 300 }),
        }
      }),
    }
  })
  const farCount = quiz.filter((q) => q.transfer === 'far').length
  if (farCount < 2) {
    c.issues.push(at('practice.quiz', `far transfer 문제가 ${farCount}개입니다. 2개 이상이어야 합니다 — 본문 예시를 숫자만 바꾼 문제로는 실력을 알 수 없습니다`))
  }
  // 같은 개념을 서로 다른 표상에서 반복해 성공해야 숙달의 증거가 된다.
  // 전부 recall/apply 면 절차 숙련만 재고 개념 이해는 못 잰다.
  const evidenceKinds = new Set(quiz.map((q) => q.evidence))
  if (evidenceKinds.size < 3) {
    c.issues.push(at('practice.quiz', `증거 종류가 ${evidenceKinds.size}가지(${[...evidenceKinds].join(', ')})뿐입니다. 3가지 이상이어야 합니다 — 한 가지 표상에서만 맞히는 것은 숙달의 증거가 아닙니다`))
  }
  const weak = quiz.filter((q) => q.evidence === 'recall' || q.evidence === 'apply').length
  if (weak === quiz.length) {
    c.issues.push(at('practice.quiz', '전부 recall/apply 입니다. graph·table·diagnose·edge_case 중 최소 하나가 있어야 절차 숙련과 개념 이해를 구분할 수 있습니다'))
  }
  const extended = arr(c, pr.extended, 'practice.extended', 0, 3).map((t, i) => {
    const o = obj(c, t, `practice.extended[${i}]`)
    return {
      title: str(c, o.title, `practice.extended[${i}].title`, { max: 100 }),
      detail: str(c, o.detail, `practice.extended[${i}].detail`, { max: 800 }),
      estimated_minutes: num(c, o.estimated_minutes, `practice.extended[${i}].estimated_minutes`, 5, 180),
    }
  })
  const extSum = extended.reduce((n, t) => n + t.estimated_minutes, 0)
  if (extSum !== time.optional) {
    c.issues.push(at('time.optional', `확장 과제 합계(${extSum}분)와 다릅니다(${time.optional}분). 시간은 학습자가 계획에 쓰는 값이라 어긋나면 안 됩니다`))
  }
  const practice = { quiz, extended }

  // ⑥ 나가기 전에 — 완료감이 아니라 증거
  const et = obj(c, r.exit_ticket, 'exit_ticket')
  const exitTicket = {
    revisit: str(c, et.revisit, 'exit_ticket.revisit', { min: 15, max: 300 }),
    one_sentence: str(c, et.one_sentence, 'exit_ticket.one_sentence', { min: 10, max: 300 }),
    misconception_check: activity(et.misconception_check, 'exit_ticket.misconception_check', ['decide']),
    self_check: arr(c, et.self_check, 'exit_ticket.self_check', 2, 4)
      .map((x, i) => str(c, x, `exit_ticket.self_check[${i}]`, { max: 200 })),
    apply_tomorrow: str(c, et.apply_tomorrow, 'exit_ticket.apply_tomorrow', { min: 10, max: 300 }),
    next_steps: arr(c, et.next_steps, 'exit_ticket.next_steps', 2, 4).map((n, i) => {
      const o = obj(c, n, `exit_ticket.next_steps[${i}]`)
      return {
        title: str(c, o.title, `exit_ticket.next_steps[${i}].title`, { max: 80 }),
        why: str(c, o.why, `exit_ticket.next_steps[${i}].why`, { max: 300 }),
        difficulty_delta: oneOf(c, o.difficulty_delta, `exit_ticket.next_steps[${i}].difficulty_delta`, ['easier', 'same', 'harder'] as const),
      }
    }),
  }

  if (c.issues.length) throw new ValidationError(c.issues)

  return {
    schema_version: SCHEMA_VERSION,
    title, topic_normalized: topic, level, category, one_liner: oneLiner, time, assumes,
    glossary, guide_notes: guideNotes, figures,
    robustness: { guards },
    problem, predict, observe, concept, practice, exit_ticket: exitTicket,
  }
}
