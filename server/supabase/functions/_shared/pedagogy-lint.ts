// 학습 설계 검사. 말투가 아니라 "학습이 일어나는가" 를 본다.
//
// 외부 평가에서 받은 지적을 기계적으로 잡을 수 있는 것부터 코드로 옮겼다.
// 의미적인 것(오개념, 근접 전이의 정도)은 critic 단계의 LLM 이 본다 — critic.ts
//
// 지적의 요지: "학생이 무엇을 읽었는가" 만 있고 "무엇을 했는가" 가 없다.

import type { WorksheetContent } from './worksheet-types.ts'

export interface PedagogyIssue { path: string; rule: string; detail: string }
export interface PedagogyReport {
  ok: boolean
  errors: PedagogyIssue[]
  warnings: PedagogyIssue[]
  metrics: {
    activityRatio: number
    farTransfer: number
    figures: number
    enrichmentRatio: number
    verbatimQuiz: number
    /** 첫 예측 활동이 hook 에 있는가 (설명 전에 틀릴 기회) */
    hookFirst: boolean
    /** 핵심 경로(core 섹션) 텍스트 / 전체 텍스트 */
    corePathRatio: number
  }
}

/** 과목 특유의 표상이 없으면 그 과목을 가르친 게 아니다. */
const NEEDS_FIGURE = new Set(['math', 'science', 'art', 'finance'])

/**
 * 분야별로 반복해서 심어지는 오개념 헤드라인.
 * 본문에서 나중에 정정해도 제목이 먼저 오개념을 심는다 — 초보는 헤드라인을 가장 강하게 기억한다.
 */
const MISCONCEPTION_TRAPS: Record<string, { pattern: RegExp; why: string }[]> = {
  science: [
    { pattern: /보는 순간|지켜보면|쳐다보면|의식이 .*바꾼|마음이 .*바꾼/, why: '"관측 = 사람이 본다" 오개념. 경로 정보가 새어 나가는 것이 기준이다' },
    { pattern: /알갱이가 아니(다|라는|에요)/, why: '"전자 = 입자 아님" 으로 저장된다. "고전적인 입자 모델로는 설명할 수 없다" 로 써야 한다' },
    { pattern: /탐지기를 (붙이면|켜면) 두 무더기/, why: '이분법. 실제로는 두 단일슬릿 분포의 합이고, 경로정보가 늘수록 간섭이 연속적으로 약해진다' },
    { pattern: /슬릿 하나.{0,10}봉우리 하나|봉우리 하나(예요|이에요|가 생)/, why: '실제 단일슬릿은 회절로 넓은 중앙 최대와 측면 최대를 만든다. 이상화 모델임을 밝히지 않으면 실제 사진에서 혼란스러워한다' },
    { pattern: /둘 (중 하나가 아니라 )?둘 다 아니/, why: '"그럼 대체 뭐예요?" 에 답할 수 없는 슬로건. "고전적 입자 모델 하나로도 파동 모델 하나로도 모든 결과를 설명할 수 없는 양자계" 로 현상 중심으로' },
    { pattern: /질문이 답의 모양을 정|묻느냐에 따라 .*(바뀐|달라진)/, why: '"우리가 묻는 대로 자연이 현실을 바꾼다" 로 저장된다. "장치가 두 경로를 구별 가능하게 만드느냐에 따라 검출 확률분포가 달라진다" 가 정확하다' },
  ],
  math: [
    { pattern: /도착(은|하지는) 못|절대 도착하지/, why: '극한은 "도착 못 하는 것" 이 아니다. 그 점의 값과 무관하게 주변에서 어디로 가는지를 본다' },
    { pattern: /정확히 .{0,6}(되려면|나오려면).{0,12}(0으로|0 으로) (놓|두)/, why: '극한값을 "금지된 h=0 에 숨은 값" 처럼 만든다. h≠0 인 차분몫의 값들이 h→0 일 때 그 값을 극한으로 갖는 것이다' },
    { pattern: /초등학교 (산수|수학)|초등 수준/, why: '어떤 학생에게는 "이것도 못 하면 기본도 안 된다" 는 신호가 된다. "익숙한 평균 변화율 계산" 이면 같은 정보에 모욕 가능성이 없다' },
    { pattern: /dx.*(아주 작은|매우 작은).*(변화량|숫자|값)/, why: 'dx 를 "아주 작은 Δx" 로 기억하게 된다. 이 단계에서는 dy/dx 표기의 기호로만 읽게 한다' },
    { pattern: /시험 문제의 (절반|반)|시험에 (잘|자주) 나/, why: '"왜 그런지 넘어가지 말라" 고 해놓고 시험 기술을 강조하면 메시지가 충돌한다' },
  ],
  art: [
    { pattern: /한 번 (날아간|잃은).*(되살릴 수 없|복구할 수 없)/, why: 'RAW 에서는 일부 채널 클리핑을 복구할 수 있다. "중요한 디테일이 있는 영역에서 모든 채널이 손실됐는가" 로 가르쳐야 한다' },
    { pattern: /스포이드로 .*(찍으면|누르면) (한 번에|바로) 맞/, why: '화면에서 회색처럼 보이는 것이 중성이라는 보장이 없다. 신뢰할 수 있는 중성 기준물을 쓴다' },
    { pattern: /교정은 정답이 있/, why: '너무 단정적. 의도적 색온도, 혼합 조명에서는 "정답" 이 없다. 입문용 근사임을 밝혀야 한다' },
    { pattern: /(조명|빛)(을|의 색을) 덜 받(아서|는)/, why: 'WB 기준물은 조명을 "덜 받는" 것이 아니라 피사체와 "같은" 조명을 받아야 그 조명을 측정할 수 있다' },
    { pattern: /(언제나|항상|무조건) .{0,10}(이 순서|순서대로)|순서(는|가) (언제나|항상) /, why: '순서는 규칙이 아니라 초보자가 원인을 분리해 연습하기 위한 권장 진단 순서(scaffold)다' },
    { pattern: /따뜻[^.!?]{0,30}노랑[^.!?]{0,25}파랑/, why: '"따뜻한 사진 = 하이라이트 노랑 + 그림자 파랑" 공식으로 외운다. "따뜻한 룩의 예시 A" 로 쓰고 다른 방법 B 를 나란히' },
  ],
}

/**
 * 오개념 문구 바로 뒤에 부정·반박이 따라오면 그건 오개념을 심는 게 아니라 바로잡는 문장이다.
 * "…라고 생각하지 않는 편이", "…라는 주장을 반박", "…가 아니에요" 처럼.
 * 검사관이 권한 "누군가 X 라고 말한다면 어떻게 답하겠어요?" 형식의 문제가 여기 걸리면 안 된다.
 */
function isRefuted(text: string, from: number): boolean {
  const tail = text.slice(from, from + 40)
  // '안 돼요', '안 됩니다' 도 부정이다. '안' 홀로는 '안에·안내' 와 겹치므로 뒤에 돼/되 가 올 때만.
  return /않|아니|반박|틀린|오해|잘못|아닙|말고|이 아니|안 ?[돼되]/.test(tail)
}

const textOf = (nodes: any[] | undefined) =>
  (nodes ?? []).map((n) => n?.value ?? '').join('')

export function pedagogyLint(c: WorksheetContent): PedagogyReport {
  const errors: PedagogyIssue[] = []
  const warnings: PedagogyIssue[] = []
  const E = (path: string, rule: string, detail: string) => errors.push({ path, rule, detail })
  const Wn = (path: string, rule: string, detail: string) => warnings.push({ path, rule, detail })

  // ── 0. 첫 활동은 설명 전에. hook 이 predict/decide 가 아니면 검증기가 이미 거부한다 ──
  const hookFirst = c.what_we_learn.hook.kind === 'predict' || c.what_we_learn.hook.kind === 'decide'
  // hook 의 reveal 에 정답을 다 써버리면 "예측" 이 아니라 "정답 먼저 보여주기" 가 된다
  if (c.what_we_learn.hook.reveal.length > 320) {
    Wn('what_we_learn.hook.reveal', '예측 활동의 답이 김', '첫 예측의 reveal 은 방향만 주고 본론에서 풀어야 합니다')
  }

  // ── 1. 활동 비율: 설명 한 단위마다 학생이 무언가를 해야 한다 ─────────────
  const blocks = c.main_lesson.blocks
  const withAct = blocks.filter((b) => b.activity).length
  const activityRatio = blocks.length ? withAct / blocks.length : 0
  if (activityRatio < 0.5) {
    E('main_lesson.blocks', '읽기만 하는 본론', `활동이 ${withAct}/${blocks.length} 블록에만 있습니다. 읽으면 이해했다고 착각합니다`)
  }

  // ── 2. 과목 표상: 수학·과학·미술·경제는 그림 없이 못 가르친다 ─────────────
  if (NEEDS_FIGURE.has(c.category) && c.figures.length === 0) {
    E('figures', '시각자료 없음', `${c.category} 는 과목 특유의 표상(그래프·패턴·커브)이 최소 1개 있어야 합니다. "머릿속으로 그려 보세요" 는 도형이 아닙니다`)
  }
  const referenced = new Set(blocks.map((b) => b.figure).filter(Boolean))
  for (const f of c.figures) {
    if (!referenced.has(f.id)) Wn(`figures[${f.id}]`, '고아 도형', '어느 블록에서도 참조하지 않습니다')
  }

  // ── 3. 전이: 본문을 그대로 베낀 문제는 실력을 재지 못한다 ─────────────────
  const lessonText = blocks.map((b) => textOf(b.body) + ' ' + (b.example?.body ?? '') + ' ' + (b.common_mistake ?? '')).join(' ')
    + ' ' + c.pro_tips.map((t) => t.tip + ' ' + t.why).join(' ')
  let verbatim = 0
  c.quiz.forEach((q, i) => {
    // 정답 문장의 핵심 조각(12자 이상)이 본문에 그대로 있으면 베낀 것이다
    const core = q.answer.replace(/[.,!?()\s]/g, '')
    const probe = core.slice(0, Math.min(14, core.length))
    const lesson = lessonText.replace(/[.,!?()\s]/g, '')
    const copied = probe.length >= 12 && lesson.includes(probe)
    if (copied) verbatim++
    if (copied && q.transfer === 'far') {
      E(`quiz[${i}]`, '전이 거리 허위', `far 라고 표시했지만 정답 문구가 본문에 그대로 있습니다: "${q.answer.slice(0, 30)}…"`)
    }
    if (q.misconceptions.length === 0 && q.difficulty >= 2) {
      Wn(`quiz[${i}]`, '오답 진단 없음', '난이도 2 이상인데 자주 나오는 오답과 이유가 없습니다. 정답만 보여주면 피드백이 아닙니다')
    }
  })
  const farTransfer = c.quiz.filter((q) => q.transfer === 'far').length
  if (verbatim >= 4) {
    E('quiz', '본문 복사 확인', `${verbatim}/5 문제의 정답이 본문에 그대로 있습니다. 새 상황·반례·오류 분석 문제로 바꾸세요`)
  }

  // ── 4. 파르 과사용 ──────────────────────────────────────────────────────
  const selfOpen = c.guide_notes.filter((g) => /^\s*저(도|는|의)\s/.test(g.note)).length
  if (c.guide_notes.length >= 2 && selfOpen === c.guide_notes.length) {
    E('guide_notes', '문체 템플릿', '파르의 말이 전부 "저도/저는…" 으로 시작합니다. 자기 개방은 한 번이면 충분하고, 나머지는 오개념 교정이나 힌트여야 합니다')
  }

  // ── 5. 분야별 오개념 헤드라인 ───────────────────────────────────────────
  // 필드를 하나로 이어붙이지 않는다. 이어붙이면 앞 필드의 오개념 뒤에 뒷 필드의 교정 문장이
  // 따라와 반박 창(isRefuted)이 그걸 보고 넘어간다 — 오개념이 교정 문장 덕에 숨는 셈이다.
  const heads: [string, string][] = [
    ['title', c.title], ['what_we_learn.one_liner', c.what_we_learn.one_liner],
    ['what_we_learn.analogy', c.what_we_learn.analogy],
    ...c.glossary.map((g, i) => [`glossary[${i}].plain`, g.plain] as [string, string]),
    ...blocks.flatMap((b, i) => [
      [`main_lesson.blocks[${i}].heading`, b.heading],
      [`main_lesson.blocks[${i}].body`, textOf(b.body)],
      [`main_lesson.blocks[${i}].common_mistake`, b.common_mistake ?? ''],
      [`main_lesson.blocks[${i}].activity.reveal`, b.activity?.reveal ?? ''],
    ] as [string, string][]),
    // question 은 뺀다: "누군가 X 라고 말한다면?" 처럼 반박 대상을 인용하는 문제가 정당하다
    ...c.quiz.flatMap((q, i) => [
      [`quiz[${i}].answer`, q.answer],
      [`quiz[${i}].explanation`, q.explanation],
    ] as [string, string][]),
    ...c.pro_tips.flatMap((t, i) => [
      [`pro_tips[${i}].tip`, t.tip], [`pro_tips[${i}].why`, t.why],
    ] as [string, string][]),
  ]
  for (const trap of MISCONCEPTION_TRAPS[c.category] ?? []) {
    for (const [path, text] of heads) {
      const m = trap.pattern.exec(text)
      if (m && !isRefuted(text, m.index + m[0].length)) E(path, '오개념', `"${m[0]}" — ${trap.why}`)
    }
  }

  // ── 6. 불확실한 사실은 검증하거나 빼야지, 배지를 달아 내보내면 안 된다 ────
  c.origin_story.timeline.forEach((t, i) => {
    if (t.confidence !== 'high') {
      E(`origin_story.timeline[${i}]`, '미검증 사실', `confidence=${t.confidence}. 학습 목표와 무관한 역사 정보를 불확실한 채로 넣지 않습니다. 검증해서 넣거나 뺍니다`)
    }
  })

  // ── 7. 부가 콘텐츠 비중: 역사·상황극·꿀팁이 본론보다 길면 연습 시간이 줄어든다 ──
  const enrichment = textOf(c.origin_story.narrative).length
    + c.origin_story.timeline.reduce((n, t) => n + t.what.length, 0)
    + c.roleplay.scene.length + c.roleplay.dialogue.reduce((n, d) => n + d.line.length, 0) + textOf(c.roleplay.takeaway).length
    + c.pro_tips.reduce((n, t) => n + t.tip.length + t.why.length, 0)
  const core = lessonText.length + blocks.reduce((n, b) => n + (b.activity ? b.activity.prompt.length + b.activity.reveal.length : 0), 0)
  const enrichmentRatio = core ? enrichment / core : 0
  if (enrichmentRatio > 0.9) {
    Wn('root', '부가 콘텐츠 과다', `역사·상황극·꿀팁이 본론의 ${Math.round(enrichmentRatio * 100)}% 입니다. 재미가 연습을 밀어냅니다`)
  }

  // ── 8. 체크리스트: 증거 없는 자기평가 ──────────────────────────────────
  const vague = c.wrap_up.checklist.filter((x) => /할 수 있(어요|다)\s*$/.test(x.trim()) && !/[0-9]|그림|써|적어|골라|계산/.test(x)).length
  if (vague === c.wrap_up.checklist.length) {
    Wn('wrap_up.checklist', '완료감 UX', '"~할 수 있어요" 만 있으면 점검이 아니라 완료감입니다. 증거를 요구하는 항목("새 함수 하나를 직접 미분해 보았다")을 섞으세요')
  }

  // ── 9. 난이도 ───────────────────────────────────────────────────────────
  if (c.quiz.every((q) => q.difficulty <= 2)) Wn('quiz', '난이도 상한', '난이도 3 문제가 없습니다')

  // ── 10. 핵심 경로 비중 ─────────────────────────────────────────────────
  const asideText = enrichment + c.next_steps.reduce((n, x) => n + x.title.length + x.why.length, 0)
  const coreText = core + c.what_we_learn.analogy.length + textOf(c.what_we_learn.summary).length
    + c.quiz.reduce((n, q) => n + q.question.length + q.answer.length + q.explanation.length, 0)
    + c.homework.tasks.reduce((n, t) => n + t.detail.length, 0)
  const corePathRatio = coreText + asideText ? coreText / (coreText + asideText) : 1

  return {
    ok: errors.length === 0, errors, warnings,
    metrics: { activityRatio, farTransfer, figures: c.figures.length, enrichmentRatio, verbatimQuiz: verbatim, hookFirst, corePathRatio },
  }
}

export function pedagogyIssuesToPrompt(r: PedagogyReport): string {
  return r.errors.map((e) => `- ${e.path}: [${e.rule}] ${e.detail}`).join('\n')
}
