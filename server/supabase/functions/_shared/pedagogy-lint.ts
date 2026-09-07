// 학습 설계 검사. 말투가 아니라 "학습이 일어나는가" 를 본다.
//
// 외부 평가에서 받은 지적을 기계적으로 잡을 수 있는 것부터 코드로 옮겼다.
// 의미적인 것(오개념, 근접 전이의 정도)은 critic 단계의 LLM 이 본다 — critic.ts
//
// 지적의 요지: "학생이 무엇을 읽었는가" 만 있고 "무엇을 했는가" 가 없다.
//
// V5: 학습지가 6단계(문제 제시 → 예측 → 관찰 → 개념 → 연습 → 나가기 전에)로 바뀌었다.
// 예전 본론은 개념(concept.blocks)으로, 역사·상황극·꿀팁은 개념 안의 맥락 노트(context_note)로,
// 마무리 체크리스트는 나가기 전에(exit_ticket.self_check)로 옮겨 왔다. 규칙의 뜻은 같고 자리만 바뀌었다.
// 새로 본 것은 "예측이 진단인가" — 흔한 오답이 선택지에 없으면 예측은 그냥 퀴즈다.

import type { WorksheetContent } from './worksheet-types.ts'

export interface PedagogyIssue { path: string; rule: string; detail: string }
export interface PedagogyReport {
  ok: boolean
  errors: PedagogyIssue[]
  warnings: PedagogyIssue[]
  /**
   * 출고 블로커. 모델이 다시 써도 고칠 수 없는 것(등록된 자산이 없다 등).
   * errors 에 넣지 않는다 — 넣으면 파이프라인이 두 번 재작성하고 환불하며 실패한다.
   * 재작성으로 풀리지 않으므로 생성은 정상 완료시키고, 출고 판단에만 쓴다.
   */
  releaseBlockers: PedagogyIssue[]
  metrics: {
    /** 개념 블록 중 활동이 있는 비율 */
    activityRatio: number
    farTransfer: number
    figures: number
    /** 맥락 노트 길이 / 개념 핵심(비유+블록 본문+활동) 길이 */
    enrichmentRatio: number
    verbatimQuiz: number
    /** 첫 예측이 고르는 활동이고(설명 전에 틀릴 기회), 관찰에 증거(도형 또는 예시)가 따라오는가 */
    hookFirst: boolean
    /** 핵심 경로 텍스트 / (핵심 경로 + 맥락 노트). 접히는 것은 맥락 노트뿐이라 나머지는 전부 핵심이다 */
    corePathRatio: number
    /** 연습 문제의 서로 다른 증거 종류 수 */
    evidenceKinds: number
    /** 경계(boundary)를 밝힌 개념 블록 수 */
    boundaries: number
    /** robustness.guards 개수 */
    guards: number
    /** 그중 지정한 섹션 본문에서 실제로 다뤄진 것으로 보이는 수 */
    guardsCovered: number
  }
}

/** 과목 특유의 표상이 없으면 그 과목을 가르친 게 아니다. */
const NEEDS_FIGURE = new Set(['math', 'science', 'art', 'finance'])

/**
 * 분야별로 반복해서 심어지는 오개념 헤드라인.
 * 본문에서 나중에 정정해도 제목이 먼저 오개념을 심는다 — 초보는 헤드라인을 가장 강하게 기억한다.
 */
const MISCONCEPTION_TRAPS: Record<string, { pattern: RegExp; why: string; unless?: RegExp }[]> = {
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
    // 조건 없이 "두 점을 붙이면 접선" 이라고 하면 미분가능성이 사라진다.
    // 뒤따르는 40자 안에 조건이 붙어 있으면(도함수·미분가능·…일 때만) 정당한 진술이다.
    { pattern: /(두 점을|점을)\s*(붙이면|합치면)\s*(할선이)?\s*접선/, unless: /도함수|미분\s?가능|존재할 때|일 때만|경우에만|조건/,
      why: '도함수가 존재할 때만이다. |x| 의 x=0 에서는 성립하지 않는다' },
  ],
  cs: [
    { pattern: /(상태|현재 상태)(는|를)\s*(저장하지 않|저장 안)/, why: '이벤트 스트림이 source of truth 라는 뜻이지 파생 상태를 저장하지 않는다는 뜻이 아니다. projection·read model·snapshot 은 실제로 저장한다' },
    { pattern: /(로그|서버 로그|감사 로그)(가|는|를)?\s*(곧|바로|즉|그냥)?\s*(이벤트 스트림|이벤트 목록)(이|가|입니다|이에요|예요)/, why: '운영 로그·감사 로그·도메인 이벤트 스트림은 목적도 권위도 다르다. 셋을 같게 가르치면 "event sourcing = 로그 많이 쌓기" 로 기억한다' },
    { pattern: /(이벤트 스트림|이벤트 목록)(은|는|이|가)?\s*(곧|바로|즉|그냥)\s*(서버 |감사 )?로그/, why: '운영 로그·감사 로그·도메인 이벤트 스트림은 목적도 권위도 다르다. 셋을 같게 가르치면 "event sourcing = 로그 많이 쌓기" 로 기억한다' },
    { pattern: /이벤트에는?\s*계산(값|한 값)을?\s*(넣지 않|절대)/, why: '그 시점에 결정된 도메인 사실(적용 가격·환율·세금)은 이벤트에 남겨야 할 수 있다. 편의용 파생 캐시만 금지다' },
  ],
  art: [
    { pattern: /한 번 (날아간|잃은).*(되살릴 수 없|복구할 수 없)/, why: 'RAW 에서는 일부 채널 클리핑을 복구할 수 있다. "중요한 디테일이 있는 영역에서 모든 채널이 손실됐는가" 로 가르쳐야 한다' },
    { pattern: /스포이드로 .*(찍으면|누르면) (한 번에|바로) 맞/, why: '화면에서 회색처럼 보이는 것이 중성이라는 보장이 없다. 신뢰할 수 있는 중성 기준물을 쓴다' },
    { pattern: /교정은 정답이 있/, why: '너무 단정적. 의도적 색온도, 혼합 조명에서는 "정답" 이 없다. 입문용 근사임을 밝혀야 한다' },
    { pattern: /(조명|빛)(을|의 색을) 덜 받(아서|는)/, why: 'WB 기준물은 조명을 "덜 받는" 것이 아니라 피사체와 "같은" 조명을 받아야 그 조명을 측정할 수 있다' },
    { pattern: /(언제나|항상|무조건) .{0,10}(이 순서|순서대로)|순서(는|가) (언제나|항상) /, why: '순서는 규칙이 아니라 초보자가 원인을 분리해 연습하기 위한 권장 진단 순서(scaffold)다' },
    { pattern: /따뜻[^.!?]{0,30}노랑[^.!?]{0,25}파랑/, why: '"따뜻한 사진 = 하이라이트 노랑 + 그림자 파랑" 공식으로 외운다. "따뜻한 룩의 예시 A" 로 쓰고 다른 방법 B 를 나란히' },
    // 결과 하나에서 원인 하나를 단정하는 역진단. "하늘이 파랗다면 색온도를 내린 거예요".
    { pattern: /(하늘이|얼굴이)[^.!?]{0,20}(면|이면)\s*[^.!?]{0,20}(올린|내린|띄운|만진)\s*(거|것)(예요|이에요|입니다)/,
      why: '색보정은 inverse problem 이다. 하나의 결과에서 원인을 유일하게 역추론할 수 없다. "~일 가능성이 있다" 로' },
  ],
}

/**
 * 모형에서 나온 퍼센트. "간섭이 30% 남아요" 같은 수는 그림이 만든 눈금이지 측정값이 아닌데,
 * 사람은 숫자를 법칙으로 기억한다. 좁게 잡는다 — 실제 데이터(가격·비율 통계)를 오탐하지 않도록
 * 이 모형들이 만들어 내는 양(간섭·가시도·확률·정확도) 바로 앞에 붙은 퍼센트만 본다.
 */
const FAKE_PRECISION = /\d+(\.\d+)?\s?%\s*(의\s*)?(간섭|가시도|확률|정확도)/

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

/** "~할 수 있다/있어요" 로 끝나면서 증거(숫자·그림·쓰기·고르기·계산)를 요구하지 않는 문장 */
const isVague = (x: string) =>
  /할 수 있(어요|다)\s*$/.test(x.trim()) && !/[0-9]|그림|써|적어|골라|계산/.test(x)

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)
const actLen = (a: { prompt: string; reveal: string } | null | undefined) =>
  a ? a.prompt.length + a.reveal.length : 0

const actText = (a: { prompt: string; reveal: string; options: string[] | null } | null | undefined) =>
  a ? [a.prompt, a.reveal, ...(a.options ?? [])].join(' ') : ''

/** 조사. 토큰 끝에서 한 번만 떼어낸다 — "관측을" 과 "관측이" 를 같은 낱말로 보기 위해서다. */
const JOSA = /(으로부터|이라는|이라고|에서는|라는|라고|에서|에게|한테|까지|부터|보다|처럼|만큼|으로|로서|로써|이나|은|는|이|가|을|를|와|과|도|만|의|에|로)$/

/** 어느 오해에나 나오는 말. 이게 섹션에 있다고 오해를 막은 것은 아니다. */
const GENERIC_TOKENS = new Set([
  '생각', '사람', '경우', '때문', '정도', '자체', '하나', '모두', '전부', '이것', '그것', '무엇',
  '자기', '우리', '대로', '학생', '내용', '부분', '설명', '이해', '이라고', '라고', '한다고', '거라고',
])

/** 용언의 어미. 이걸로 끝나면 활용형이라 보고 열쇳말에서 뺀다. */
const INFLECTION = /(해요|어요|아요|여요|예요|에요|세요|네요|이라|한다|된다|있다|없다|같다|하지|되지|않지|드는|드나|나요|까요|는다고|ㄴ다고|는다는|다고|다는|던데|지만|면서|으면|라면|해서|돼서|되어|하고|하며|하는|되는|보는|쓰는|넣는|여겨|기억|생각)$/

/**
 * 오해 문장에서 "그 오해를 다뤘는지" 를 가늠할 열쇳말을 뽑는다.
 * 보수적으로: 두 글자 이상 한글 덩어리에서 조사를 떼고, 아무 데나 나오는 말은 버리고,
 * 긴 것 몇 개만 본다. 짧은 토큰까지 요구하면 멀쩡한 학습지를 지적하게 된다.
 *
 * 활용형(용언)은 버린다. "저장하지 않는다고 기억해요" 에서 긴 것부터 세면
 * '않는다고·기억해요·저장하지' 가 뽑혀 정작 열쇳말인 '이벤트·상태' 가 밀린다.
 * 본문은 같은 뜻을 다른 어미로 쓰므로 용언으로는 절대 안 맞는다 — 체언만 남긴다.
 */
export function guardTokens(misconception: string): string[] {
  const raw = misconception.match(/[가-힣]{2,}/g) ?? []
  const seen = new Set<string>()
  for (const w of raw) {
    const t = w.replace(JOSA, '')
    const cand = t.length >= 2 ? t : w
    if (cand.length < 2 || GENERIC_TOKENS.has(cand)) continue
    if (INFLECTION.test(cand)) continue          // 활용형은 본문에서 다른 어미로 나온다
    seen.add(cand)
  }
  // 그래도 하나도 안 남으면(전부 용언인 오해 문장) 원래 방식으로 되돌린다 — 지적을 못 하느니 낫다.
  if (seen.size === 0) {
    for (const w of raw) {
      const t = w.replace(JOSA, '')
      const cand = t.length >= 2 ? t : w
      if (cand.length >= 2 && !GENERIC_TOKENS.has(cand)) seen.add(cand)
    }
  }
  return [...seen].sort((a, b) => b.length - a.length).slice(0, 4)
}

export function pedagogyLint(c: WorksheetContent): PedagogyReport {
  const errors: PedagogyIssue[] = []
  const warnings: PedagogyIssue[] = []
  const releaseBlockers: PedagogyIssue[] = []
  const E = (path: string, rule: string, detail: string) => errors.push({ path, rule, detail })
  const Wn = (path: string, rule: string, detail: string) => warnings.push({ path, rule, detail })
  // 재작성으로 풀리지 않는 것. errors 에 넣으면 파이프라인이 두 번 다시 쓰고 환불하며 실패한다.
  const B = (path: string, rule: string, detail: string) => releaseBlockers.push({ path, rule, detail })

  const hook = c.predict.hook
  const observe = c.observe
  const blocks = c.concept.blocks
  const quiz = c.practice.quiz
  const contextNote = c.concept.context_note
  // V6 필드. 부분 객체로 부르는 호출자가 있어 방어적으로 읽는다.
  const guards = c.robustness?.guards ?? []

  // ── 0. 첫 활동은 설명 전에, 그리고 예측은 진단이어야 한다 ─────────────────
  // hook 이 predict/decide 가 아니면 검증기가 이미 거부한다. 지표로만 남긴다.
  // 관찰에 증거(도형·예시)가 없으면 예측을 시험할 수 없으니 "먼저 틀릴 기회" 가 성립하지 않는다.
  const hasEvidence = Boolean(observe.figure || observe.example)
  const hookFirst = (hook.kind === 'predict' || hook.kind === 'decide') && hasEvidence
  // 선택지가 둘 미만이면 고를 것이 없다 — 흔한 오답이 들어갈 자리가 없으니 예측이 진단이 못 된다
  if (!hook.options || hook.options.length < 2) {
    E('predict.hook.options', '예측이 진단이 아님', `선택지가 ${hook.options?.length ?? 0}개입니다. 흔한 오답을 포함해 2개 이상이어야 예측이 학생의 생각을 드러냅니다`)
  }
  // hook 의 reveal 에 정답을 다 써버리면 "예측" 이 아니라 "정답 먼저 보여주기" 가 된다
  if (hook.reveal.length > 320) {
    Wn('predict.hook.reveal', '예측 활동의 답이 김', '첫 예측의 reveal 은 방향만 주고 개념 단계에서 풀어야 합니다')
  }

  // ── 1. 활동 비율: 설명 한 단위마다 학생이 무언가를 해야 한다 ─────────────
  const withAct = blocks.filter((b) => b.activity).length
  const activityRatio = blocks.length ? withAct / blocks.length : 0
  if (activityRatio < 0.5) {
    E('concept.blocks', '읽기만 하는 개념', `활동이 ${withAct}/${blocks.length} 블록에만 있습니다. 읽으면 이해했다고 착각합니다`)
  }

  // ── 2. 과목 표상: 수학·과학·미술·경제는 그림 없이 못 가르친다 ─────────────
  if (NEEDS_FIGURE.has(c.category)) {
    if (c.figures.length === 0) {
      E('figures', '시각자료 없음', `${c.category} 는 과목 특유의 표상(그래프·패턴·커브)이 최소 1개 있어야 합니다. "머릿속으로 그려 보세요" 는 도형이 아닙니다`)
    }
    // 표상이 있어도 관찰 단계에 없으면 학생은 예측을 그림으로 시험하지 못한다
    if (!observe.figure) {
      Wn('observe.figure', '관찰에 표상 없음', `관찰 단계에 표상이 없다. ${c.category} 는 예측을 시험하는 증거가 도형이어야 합니다`)
    }
  }
  const referenced = new Set<string>(blocks.map((b) => b.figure).filter((f): f is string => Boolean(f)))
  if (observe.figure) referenced.add(observe.figure)
  for (const f of c.figures) {
    if (!referenced.has(f.id)) Wn(`figures[${f.id}]`, '고아 도형', '관찰 단계도 어느 개념 블록도 참조하지 않습니다')
  }

  // ── 3. 전이: 개념 텍스트를 그대로 베낀 문제는 실력을 재지 못한다 ─────────────
  const blockText = blocks.map((b) => textOf(b.body) + ' ' + (b.example?.body ?? '') + ' ' + (b.common_mistake ?? '')).join(' ')
  const noteText = contextNote ? textOf(contextNote.text) : ''
  const lessonText = blockText + ' ' + c.concept.analogy + ' ' + noteText
  const lesson = lessonText.replace(/[.,!?()\s]/g, '')
  let verbatim = 0
  quiz.forEach((q, i) => {
    // 정답 문장의 핵심 조각(12자 이상)이 개념 텍스트에 그대로 있으면 베낀 것이다
    const core = q.answer.replace(/[.,!?()\s]/g, '')
    const probe = core.slice(0, Math.min(14, core.length))
    const copied = probe.length >= 12 && lesson.includes(probe)
    if (copied) verbatim++
    if (copied && q.transfer === 'far') {
      E(`practice.quiz[${i}]`, '전이 거리 허위', `far 라고 표시했지만 정답 문구가 개념 단계에 그대로 있습니다: "${q.answer.slice(0, 30)}…"`)
    }
    if (q.misconceptions.length === 0 && q.difficulty >= 2) {
      Wn(`practice.quiz[${i}]`, '오답 진단 없음', '난이도 2 이상인데 자주 나오는 오답과 이유가 없습니다. 정답만 보여주면 피드백이 아닙니다')
    }
  })
  const farTransfer = quiz.filter((q) => q.transfer === 'far').length
  if (verbatim >= 4) {
    E('practice.quiz', '본문 복사 확인', `${verbatim}/5 문제의 정답이 개념 단계에 그대로 있습니다. 새 상황·반례·오류 분석 문제로 바꾸세요`)
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
    ['title', c.title], ['one_liner', c.one_liner],
    ['problem.question', c.problem.question],
    ['problem.why_it_matters', c.problem.why_it_matters],
    ['concept.analogy', c.concept.analogy],
    ...c.glossary.map((g, i) => [`glossary[${i}].plain`, g.plain] as [string, string]),
    ...blocks.flatMap((b, i) => [
      [`concept.blocks[${i}].heading`, b.heading],
      [`concept.blocks[${i}].body`, textOf(b.body)],
      [`concept.blocks[${i}].common_mistake`, b.common_mistake ?? ''],
      [`concept.blocks[${i}].activity.reveal`, b.activity?.reveal ?? ''],
    ] as [string, string][]),
    // 활동의 prompt 는 뺀다: "…라고 생각하나요?" 처럼 오개념을 고르게 하는 것이 활동의 목적이다.
    // reveal 은 학생이 답한 뒤 남는 문장이라 헤드라인이다.
    ['observe.compare.reveal', observe.compare.reveal],
    ['predict.hook.reveal', hook.reveal],
    // question 은 뺀다: "누군가 X 라고 말한다면?" 처럼 반박 대상을 인용하는 문제가 정당하다
    ...quiz.flatMap((q, i) => [
      [`practice.quiz[${i}].answer`, q.answer],
      [`practice.quiz[${i}].explanation`, q.explanation],
    ] as [string, string][]),
    ['exit_ticket.one_sentence', c.exit_ticket.one_sentence],
    ['exit_ticket.misconception_check.reveal', c.exit_ticket.misconception_check.reveal],
  ]
  for (const trap of MISCONCEPTION_TRAPS[c.category] ?? []) {
    for (const [path, text] of heads) {
      const m = trap.pattern.exec(text)
      if (!m) continue
      const after = m.index + m[0].length
      // unless: 바로 뒤에 성립 조건이 붙어 있으면 절대법칙이 아니다 ("…접선이 돼요, 도함수가 있을 때만").
      if (trap.unless && trap.unless.test(text.slice(Math.max(0, m.index - 30), after + 40))) continue
      if (!isRefuted(text, after)) E(path, '오개념', `"${m[0]}" — ${trap.why}`)
    }
  }

  // ── 6. 불확실한 사실은 검증하거나 빼야지, 배지를 달아 내보내면 안 된다 ────
  contextNote?.facts.forEach((f, i) => {
    if (f.confidence !== 'high') {
      E(`concept.context_note.facts[${i}]`, '미검증 사실', `confidence=${f.confidence}. 학습 목표와 무관한 맥락 정보를 불확실한 채로 넣지 않습니다. 검증해서 넣거나 뺍니다`)
    }
  })

  // ── 7. 맥락 노트 비중: 역사·맥락이 개념보다 길면 연습 시간이 줄어든다 ──────
  const enrichment = noteText.length
  const core = c.concept.analogy.length
    + sum(blocks.map((b) => textOf(b.body).length + actLen(b.activity)))
  const enrichmentRatio = core ? enrichment / core : 0
  if (enrichmentRatio > 0.5) {
    Wn('concept.context_note', '맥락 노트 과다', `맥락 노트가 개념 핵심의 ${Math.round(enrichmentRatio * 100)}% 입니다. 접혀 나가더라도 재미가 연습을 밀어냅니다`)
  }

  // ── 8. 증거 없는 자기평가와 목표 ─────────────────────────────────────────
  const selfCheck = c.exit_ticket.self_check
  if (selfCheck.length && selfCheck.every(isVague)) {
    Wn('exit_ticket.self_check', '완료감 UX', '"~할 수 있어요" 만 있으면 점검이 아니라 완료감입니다. 증거를 요구하는 항목("새 함수 하나를 직접 미분해 보았다")을 섞으세요')
  }
  c.problem.objectives.forEach((o, i) => {
    if (isVague(o)) {
      Wn(`problem.objectives[${i}]`, '목표가 증거 없는 "~할 수 있다"', `"${o.slice(0, 40)}" — 목표는 증거가 남는 행동으로 씁니다("…를 계산한다", "…를 그림에 표시한다")`)
    }
  })
  // 오개념 점검은 틀린 문장 "하나" 를 고르는 것이라 셋은 있어야 고르는 의미가 있다
  const mcOptions = c.exit_ticket.misconception_check.options?.length ?? 0
  if (mcOptions < 3) {
    Wn('exit_ticket.misconception_check.options', '오개념 점검이 얕음', `선택지가 ${mcOptions}개입니다. 맞는 문장 둘 사이에 틀린 문장 하나가 숨어야 오개념이 굳었는지 보입니다`)
  }

  // ── 9. 난이도 ───────────────────────────────────────────────────────────
  if (quiz.every((q) => q.difficulty <= 2)) Wn('practice.quiz', '난이도 상한', '난이도 3 문제가 없습니다')

  // ── 10. 핵심 경로 비중: 접히는 것은 맥락 노트뿐이다 ───────────────────────
  const asideText = enrichment + sum((contextNote?.facts ?? []).map((f) => f.when.length + f.what.length))
  const coreText = core
    + textOf(c.problem.situation).length + c.problem.question.length + c.problem.why_it_matters.length
    + sum(c.problem.objectives.map((o) => o.length))
    + actLen(hook) + c.predict.reasoning_prompt.length
    + textOf(observe.intro).length + (observe.example?.body.length ?? 0)
    + sum(observe.notice.map((n) => n.length)) + actLen(observe.compare)
    + sum(blocks.map((b) => (b.example?.body.length ?? 0) + (b.common_mistake?.length ?? 0)))
    + sum(quiz.map((q) => q.question.length + q.answer.length + q.explanation.length))
    + sum(c.practice.extended.map((t) => t.detail.length))
    + c.exit_ticket.revisit.length + c.exit_ticket.one_sentence.length
    + actLen(c.exit_ticket.misconception_check) + sum(selfCheck.map((s) => s.length))
    + c.exit_ticket.apply_tomorrow.length
    + sum(c.exit_ticket.next_steps.map((n) => n.title.length + n.why.length))
    + sum(c.glossary.map((g) => g.plain.length)) + sum(c.guide_notes.map((g) => g.note.length))
  const corePathRatio = coreText + asideText ? coreText / (coreText + asideText) : 1

  // ── 11. 실물 자극: 지각 판단은 도식으로 훈련되지 않는다 ────────────────────
  // 다시 쓰라고 해도 모델이 사진을 만들어 낼 수 없다. 그래서 오류가 아니라 출고 블로커다.
  if (c.category === 'art' && !c.figures.some((f) => f.spec?.kind === 'photo')) {
    B('figures', '실물 자극 없음',
      '색을 판단하는 법을 가르치는데 실물 사진(spec.kind: "photo")이 하나도 없습니다. ' +
      '도식(swatches·tonecurve)은 개념을 증명하지만 지각 판단 능력을 훈련하지 못합니다 — ' +
      '견본에서 중성을 고르는 것과 실제 사진에서 색이 도는 것을 알아보는 것은 다른 능력입니다. ' +
      'server/assets/manifest.json 에 라이선스·출처가 확인된 사진을 등록하면 풀립니다.')
  }

  // ── 12. 표상 단일: 한 가지 표현 방식에만 학습을 걸지 않는다 ────────────────
  const exampleKinds = new Set<string>()
  for (const b of blocks) if (b.example) exampleKinds.add(b.example.kind)
  if (observe.example) exampleKinds.add(observe.example.kind)
  if (c.figures.length === 0 && exampleKinds.size <= 1) {
    Wn('figures', '표상 단일',
      `도형이 없고 예시 형태도 ${exampleKinds.size}가지(${[...exampleKinds].join(', ') || '없음'})뿐입니다. ` +
      '하나의 표현 방식에 학습을 걸면 그 방식에서 막힌 학생은 복구할 길이 없습니다 — ' +
      '같은 개념을 다른 표상(그림·표·비교·장면)에서 한 번 더 보여주세요')
  }

  // ── 13. 모형 경계: 조건 없는 규칙은 절대법칙으로 기억된다 ──────────────────
  const boundaries = blocks.filter((b) => b.boundary).length
  if (boundaries === 0) {
    E('concept.blocks', '모형 경계 없음',
      '규칙이 언제 성립하고(holds_when) 언제 깨지는지(breaks_when) 밝힌 블록이 하나도 없습니다. ' +
      '입문용 단순화 자체는 죄가 아니지만, 단순화를 현실의 법칙처럼 숨기면 학생은 규칙만 떼어 기억합니다')
  } else if (boundaries === 1 && blocks.length >= 4) {
    Wn('concept.blocks', '모형 경계 부족',
      `블록 ${blocks.length}개 중 경계를 밝힌 것이 1개뿐입니다. 규칙을 세우는 블록마다 성립 조건과 깨지는 경우가 있어야 합니다`)
  }

  // ── 14. 증거 다양성: 절차 숙련과 개념 이해를 구분할 문제가 있는가 ──────────
  const evidenceSet = new Set(quiz.map((q) => q.evidence))
  const STRONG = ['graph', 'table', 'diagnose', 'edge_case']
  const hasStrong = STRONG.some((k) => evidenceSet.has(k as any))
  if (evidenceSet.size === 3 && !hasStrong) {
    Wn('practice.quiz', '증거 다양성 부족',
      `증거 종류가 ${[...evidenceSet].join(', ')} 3종인데 graph·table·diagnose·edge_case 가 하나도 없습니다. ` +
      '말로 되살리고 절차를 적용하는 것만으로는 개념이 새 표상에서 버티는지 알 수 없습니다')
  }

  // ── 15. 가짜 정밀도: 모형이 만든 숫자를 측정값처럼 내지 않는다 ──────────────
  // 이중 방어(검증기도 막는다). 사람은 숫자를 법칙으로 기억하기 때문에 여기서 한 번 더 본다.
  c.figures.forEach((f, i) => {
    if (f.readout === 'quantitative' && f.spec?.kind !== 'plot') {
      E(`figures[${i}].readout`, '가짜 정밀도',
        `${f.spec?.kind} 는 정성 모형인데 정량 눈금(readout: "quantitative")을 붙였습니다. ` +
        '이 모형에서 나오는 수는 계산된 값이 아니라 그림이 만든 눈금입니다 — qualitative(낮음/중간/높음)로 두세요')
    }
  })
  const everyText: [string, string][] = [
    ...heads,
    ['problem.situation', textOf(c.problem.situation)],
    ...c.problem.objectives.map((o, i) => [`problem.objectives[${i}]`, o] as [string, string]),
    ['predict.hook.prompt', hook.prompt],
    ['predict.reasoning_prompt', c.predict.reasoning_prompt],
    ['observe.intro', textOf(observe.intro)],
    ...observe.notice.map((n, i) => [`observe.notice[${i}]`, n] as [string, string]),
    ['observe.compare.prompt', observe.compare.prompt],
    ['observe.example', observe.example ? observe.example.caption + ' ' + observe.example.body : ''],
    ...blocks.flatMap((b, i) => [
      [`concept.blocks[${i}].activity.prompt`, b.activity?.prompt ?? ''],
      [`concept.blocks[${i}].example`, b.example ? b.example.caption + ' ' + b.example.body : ''],
      [`concept.blocks[${i}].boundary`, b.boundary ? b.boundary.holds_when + ' ' + b.boundary.breaks_when : ''],
    ] as [string, string][]),
    ['concept.context_note.text', noteText],
    ...quiz.flatMap((q, i) => [
      [`practice.quiz[${i}].question`, q.question],
      ...(q.choices ?? []).map((ch, j) => [`practice.quiz[${i}].choices[${j}]`, ch] as [string, string]),
      ...q.misconceptions.map((m, j) => [`practice.quiz[${i}].misconceptions[${j}].why`, m.why] as [string, string]),
    ] as [string, string][]),
    ...c.practice.extended.map((t, i) => [`practice.extended[${i}].detail`, t.detail] as [string, string]),
    ...c.figures.flatMap((f, i) => [
      [`figures[${i}].title`, f.title],
      [`figures[${i}].alt`, f.alt],
      [`figures[${i}].model_note`, f.model_note ?? ''],
      [`figures[${i}].drawTask`, f.drawTask ?? ''],
    ] as [string, string][]),
    ...guards.map((g, i) => [`robustness.guards[${i}].how`, g.how] as [string, string]),
    ['exit_ticket.revisit', c.exit_ticket.revisit],
    ['exit_ticket.apply_tomorrow', c.exit_ticket.apply_tomorrow],
    ...c.exit_ticket.self_check.map((s, i) => [`exit_ticket.self_check[${i}]`, s] as [string, string]),
  ]
  for (const [path, text] of everyText) {
    const m = FAKE_PRECISION.exec(text)
    // 반박 문맥("30% 라는 수치는 이 그림에서 나온 것이 아니에요")은 봐준다.
    if (m && !isRefuted(text, m.index + m[0].length)) {
      E(path, '가짜 정밀도',
        `"${m[0]}" — 정성 모형에서 나온 숫자를 측정값처럼 썼습니다. 근거 없는 퍼센트는 학생이 법칙으로 기억합니다. 낮음/중간/높음으로 쓰세요`)
    }
  }

  // ── 16. 오해 방어 이행: guards 에 적은 오해를 본문이 실제로 막는가 ──────────
  // guards 만 적고 본문에서 안 막는 것을 잡는 게 목적이다. 판정은 보수적으로 —
  // 오해에서 뽑은 긴 열쇳말 셋 중 하나라도 그 섹션에 있으면 다뤘다고 본다.
  const sectionText: Record<string, string> = {
    problem: [textOf(c.problem.situation), c.problem.question, c.problem.why_it_matters, ...c.problem.objectives].join(' '),
    predict: [actText(hook), c.predict.reasoning_prompt].join(' '),
    observe: [textOf(observe.intro), ...observe.notice, actText(observe.compare),
      observe.example ? observe.example.caption + ' ' + observe.example.body : '',
      observe.figure ? figureText(c, observe.figure) : ''].join(' '),
    concept: [c.concept.analogy, noteText,
      ...c.glossary.map((g) => g.term + ' ' + g.plain),
      ...blocks.map((b) => [b.heading, textOf(b.body), b.common_mistake ?? '', actText(b.activity),
        b.boundary ? b.boundary.holds_when + ' ' + b.boundary.breaks_when : '',
        b.example ? b.example.caption + ' ' + b.example.body : '',
        b.figure ? figureText(c, b.figure) : ''].join(' ')),
    ].join(' '),
    practice: [...quiz.map((q) => [q.question, q.answer, q.explanation, ...(q.choices ?? []),
      ...q.misconceptions.map((m) => m.wrong + ' ' + m.why)].join(' ')),
      ...c.practice.extended.map((t) => t.title + ' ' + t.detail)].join(' '),
    exit_ticket: [c.exit_ticket.revisit, c.exit_ticket.one_sentence, actText(c.exit_ticket.misconception_check),
      ...c.exit_ticket.self_check, c.exit_ticket.apply_tomorrow,
      ...c.exit_ticket.next_steps.map((n) => n.title + ' ' + n.why)].join(' '),
  }
  for (const g of c.guide_notes) {
    if (sectionText[g.section] !== undefined) sectionText[g.section] += ' ' + g.note
  }
  let guardsCovered = 0
  guards.forEach((g, i) => {
    const tokens = guardTokens(g.misconception)
    const where = sectionText[g.where] ?? ''
    const covered = tokens.length === 0 || tokens.some((t) => where.includes(t))
    if (covered) guardsCovered++
    else {
      E(`robustness.guards[${i}]`, '오해 방어 미이행',
        `"${g.misconception}" 를 ${g.where} 에서 막는다고 적었지만, 그 섹션 어디에도 이 오해를 다룬 흔적이 없습니다 ` +
        `(찾은 낱말: ${tokens.join(', ')}). guards 는 목록이 아니라 약속입니다 — ${g.where} 본문에서 실제로 막으세요`)
    }
  })

  return {
    ok: errors.length === 0, errors, warnings, releaseBlockers,
    metrics: {
      activityRatio, farTransfer, figures: c.figures.length, enrichmentRatio, verbatimQuiz: verbatim, hookFirst, corePathRatio,
      evidenceKinds: evidenceSet.size, boundaries, guards: guards.length, guardsCovered,
    },
  }
}

/** 도형이 화면에서 말하는 것도 그 섹션의 텍스트다 — 오해를 그림의 캡션으로 막을 수 있다. */
function figureText(c: WorksheetContent, id: string): string {
  const f = c.figures.find((x) => x.id === id)
  return f ? [f.title, f.alt, f.model_note ?? '', f.drawTask ?? ''].join(' ') : ''
}

export function pedagogyIssuesToPrompt(r: PedagogyReport): string {
  return r.errors.map((e) => `- ${e.path}: [${e.rule}] ${e.detail}`).join('\n')
}
