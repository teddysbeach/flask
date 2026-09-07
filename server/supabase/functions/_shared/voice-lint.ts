// 말투 검사. docs/plan/11-voice-and-persona.md §6
//
// 프롬프트로 "친절하게 써주세요" 라고 부탁하는 것과, 안 지켰을 때 거부하는 것은 다르다.
// 검출된 목록은 그대로 LLM 재요청 프롬프트가 된다.

export interface VoiceIssue {
  path: string
  rule: string
  detail: string
}

/**
 * 못 따라온 사람을 소외시키는 말들.
 * "쉽죠?" 는 이해한 사람에게는 공감이지만 못 이해한 사람에게는 판결이다.
 */
const BANNED: { pattern: RegExp; rule: string; why: string }[] = [
  { pattern: /쉽죠|쉽[지죠]요|어렵지 ?않(습니다|아요)/, rule: '난이도 단정', why: '못 따라온 사람을 소외시킵니다' },
  { pattern: /간단(합니다|해요|히 말해)/, rule: '난이도 단정', why: '읽는 사람에게 간단하지 않을 수 있습니다' },
  { pattern: /당연히|당연[한하]/, rule: '전제 강요', why: '모르는 사람에게는 당연하지 않습니다' },
  { pattern: /아시다시피|알다시피|누구나 (아는|알듯)/, rule: '전제 강요', why: '모르는 독자를 배제합니다' },
  { pattern: /에 불과(합니다|해요)|별거 ?아[닙니]/, rule: '어려움 부정', why: '독자가 느낀 어려움을 부정합니다' },
  { pattern: /반드시 외우|무조건 외우|암기하세요/, rule: '명령', why: '파르는 시키지 않습니다' },
  // 맨 명령형. 권하는 형태("해 보세요", "해 주세요")는 '하세요' 를 포함하지 않으므로 안 걸린다.
  { pattern: /[가-힣]하세요|하십시오/, rule: '명령', why: '"…해 보세요" 처럼 권하는 형태를 씁니다' },
  { pattern: /요청이 올바르지|잘못된 입력|사용자[의 ]*(실수|잘못)/, rule: '사용자 탓', why: '실패 문구는 언제나 우리 탓입니다' },
]

/**
 * 해요체 이탈(반말). 파르는 존댓말을 쓴다.
 *
 * 어미를 나열하는 방식(한다|이다|된다…)은 '짓는다', '간다', '없다' 처럼 빠져나가는 게 많다.
 * 평서형 반말은 결국 "…다." 로 끝나므로 그걸 잡되, 합니다체("…니다.")는 존댓말이므로 제외한다.
 */
const CASUAL = /[가-힣]{1,12}(?<!니)다\.(?=\s|$)|[가-힣]{1,12}[보하]자\.(?=\s|$)/

/** 한자어 → 우리말. 경고만 하고 실패시키지는 않는다(문맥상 맞는 경우가 있다). */
const STIFF: [RegExp, string][] = [
  [/영속화/, '저장해 둔다'],
  [/도출(한다|합니다|해요)/, '계산해서 얻는다'],
  [/상충/, '서로 부딪힌다'],
  [/수행(한다|합니다)/, '한다'],
  [/활용(한다|합니다)/, '쓴다'],
  [/지속성을 보장/, '사라지지 않게 한다'],
]

export const MAX_SENTENCE_CHARS = 90
export const TARGET_AVG_SENTENCE = 60

const splitSentences = (t: string) =>
  t.split(/(?<=[.!?])\s+|\n+/).map((s) => s.trim()).filter((s) => s.length > 0)

/**
 * 학습지에서 사람이 읽는 문자열만 뽑는다. 코드·용어명은 검사 대상이 아니다.
 * V5 6단계(문제 제시 → 예측 → 관찰 → 개념 → 연습 → 나가기 전에)의 산문 필드를 전부 훑는다.
 * 부분 객체도 받는다(테스트가 한 필드만 넣어 규칙을 시험한다).
 */
export function collectProse(content: any): { path: string; text: string }[] {
  const out: { path: string; text: string }[] = []
  const push = (path: string, v: unknown) => {
    if (typeof v === 'string' && v.trim()) out.push({ path, text: v })
  }
  const inline = (path: string, nodes: any[]) => {
    if (!Array.isArray(nodes)) return
    // code 노드는 코드라서 말투 검사 대상이 아니다
    push(path, nodes.filter((n) => n?.type !== 'code').map((n) => n?.value ?? '').join(''))
  }

  // ① 문제 제시
  inline('problem.situation', content.problem?.situation)
  push('problem.question', content.problem?.question)
  push('problem.why_it_matters', content.problem?.why_it_matters)
  ;(content.problem?.objectives ?? []).forEach((o: string, i: number) => push(`problem.objectives[${i}]`, o))

  // ② 예측
  push('predict.hook.prompt', content.predict?.hook?.prompt)
  push('predict.hook.reveal', content.predict?.hook?.reveal)
  push('predict.reasoning_prompt', content.predict?.reasoning_prompt)

  // ③ 관찰 — example.body 는 코드·계산이라 뺀다
  inline('observe.intro', content.observe?.intro)
  ;(content.observe?.notice ?? []).forEach((n: string, i: number) => push(`observe.notice[${i}]`, n))
  push('observe.compare.prompt', content.observe?.compare?.prompt)
  push('observe.compare.reveal', content.observe?.compare?.reveal)

  // ④ 개념
  push('concept.analogy', content.concept?.analogy)
  ;(content.concept?.blocks ?? []).forEach((b: any, i: number) => {
    inline(`concept.blocks[${i}].body`, b?.body)
    push(`concept.blocks[${i}].common_mistake`, b?.common_mistake)
    push(`concept.blocks[${i}].activity.prompt`, b?.activity?.prompt)
    push(`concept.blocks[${i}].activity.reveal`, b?.activity?.reveal)
    // V6: 규칙의 경계도 학생이 읽는 문장이다. 여기만 딱딱한 논문 말투가 되기 쉬워서 함께 본다.
    push(`concept.blocks[${i}].boundary.holds_when`, b?.boundary?.holds_when)
    push(`concept.blocks[${i}].boundary.breaks_when`, b?.boundary?.breaks_when)
  })
  inline('concept.context_note.text', content.concept?.context_note?.text)
  ;(content.glossary ?? []).forEach((g: any, i: number) => push(`glossary[${i}].plain`, g?.plain))
  ;(content.guide_notes ?? []).forEach((g: any, i: number) => push(`guide_notes[${i}].note`, g?.note))

  // V6: 그림이 무엇을 생략했는지 밝히는 문장도 학습지에 그대로 나간다.
  // drawTask 와 alt 도 사람이 읽는 문장이다 — 오래 검사 밖에 있었고, 그래서
  // "…비교하세요" 같은 명령형이 그대로 나갔다. 화면에 보이는 글은 전부 같은 잣대로 잰다.
  ;(content.figures ?? []).forEach((f: any, i: number) => {
    push(`figures[${i}].model_note`, f?.model_note)
    push(`figures[${i}].drawTask`, f?.drawTask)
    push(`figures[${i}].alt`, f?.alt)
  })
  // V6: 로버스트니스 예산. 오해와 막는 방법은 파르가 쓰는 문장이다.
  ;(content.robustness?.guards ?? []).forEach((g: any, i: number) => {
    push(`robustness.guards[${i}].misconception`, g?.misconception)
    push(`robustness.guards[${i}].how`, g?.how)
  })

  // ⑤ 연습
  ;(content.practice?.quiz ?? []).forEach((q: any, i: number) => {
    push(`practice.quiz[${i}].question`, q?.question)
    push(`practice.quiz[${i}].answer`, q?.answer)
    push(`practice.quiz[${i}].explanation`, q?.explanation)
    ;(q?.misconceptions ?? []).forEach((m: any, j: number) => push(`practice.quiz[${i}].misconceptions[${j}].why`, m?.why))
  })
  ;(content.practice?.extended ?? []).forEach((t: any, i: number) => push(`practice.extended[${i}].detail`, t?.detail))

  // ⑥ 나가기 전에
  push('exit_ticket.revisit', content.exit_ticket?.revisit)
  push('exit_ticket.one_sentence', content.exit_ticket?.one_sentence)
  push('exit_ticket.misconception_check.prompt', content.exit_ticket?.misconception_check?.prompt)
  push('exit_ticket.misconception_check.reveal', content.exit_ticket?.misconception_check?.reveal)
  ;(content.exit_ticket?.self_check ?? []).forEach((s: string, i: number) => push(`exit_ticket.self_check[${i}]`, s))
  push('exit_ticket.apply_tomorrow', content.exit_ticket?.apply_tomorrow)
  ;(content.exit_ticket?.next_steps ?? []).forEach((n: any, i: number) => push(`exit_ticket.next_steps[${i}].why`, n?.why))

  return out
}

export interface VoiceReport {
  ok: boolean
  errors: VoiceIssue[]     // 재요청 사유
  warnings: VoiceIssue[]   // 기록만
  avgSentenceChars: number
}

export function voiceLint(content: any): VoiceReport {
  const errors: VoiceIssue[] = []
  const warnings: VoiceIssue[] = []
  const prose = collectProse(content)

  let totalChars = 0
  let sentenceCount = 0

  for (const { path, text } of prose) {
    for (const b of BANNED) {
      const m = b.pattern.exec(text)
      if (m) errors.push({ path, rule: b.rule, detail: `"${m[0]}" — ${b.why}` })
    }
    const casual = CASUAL.exec(text)
    if (casual) {
      errors.push({ path, rule: '반말', detail: `"${casual[0].trim()}" — 파르는 해요체 존댓말을 씁니다` })
    }
    for (const [re, better] of STIFF) {
      const m = re.exec(text)
      if (m) warnings.push({ path, rule: '딱딱한 한자어', detail: `"${m[0]}" → "${better}" 가 낫습니다` })
    }
    for (const s of splitSentences(text)) {
      totalChars += s.length
      sentenceCount++
      if (s.length > MAX_SENTENCE_CHARS) {
        warnings.push({ path, rule: '긴 문장', detail: `${s.length}자 — 한 문장에 한 개념이면 대개 ${MAX_SENTENCE_CHARS}자를 넘지 않습니다` })
      }
    }
  }

  const avg = sentenceCount ? Math.round(totalChars / sentenceCount) : 0
  if (avg > TARGET_AVG_SENTENCE + 20) {
    warnings.push({ path: 'root', rule: '평균 문장 길이', detail: `평균 ${avg}자 (목표 ${TARGET_AVG_SENTENCE}자)` })
  }

  return { ok: errors.length === 0, errors, warnings, avgSentenceChars: avg }
}

/** 재요청 프롬프트에 붙일 문구. */
export function voiceIssuesToPrompt(report: VoiceReport): string {
  return report.errors
    .map((e) => `- ${e.path}: [${e.rule}] ${e.detail}`)
    .join('\n')
}
