// 검사관 단계. 집필된 학습지를 교수설계 기준으로 채점하고, 미달이면 재작성 사유를 돌려준다.
//
// 정적 린트(voice-lint, pedagogy-lint)는 기계적으로 잡히는 것만 본다.
// 오개념이 굳는지, 문제가 실제로 새 상황인지, 단순화가 거짓이 되는지는 판단이 필요하다.
// 그래서 이 단계는 설계 단계와 같은 모델(claude-opus-5)이 맡는다.
//
// 외부 평가에서 "예뻐서 좋은 학습지처럼 느껴진다" 는 말을 들었다. 이 단계가 그걸 막는 마지막 문이다.

import type { WorksheetContent } from './worksheet-types.ts'

export const CRITIC_MODEL_DEFAULT = 'claude-opus-5'
export const PASS_SCORE = 75
export const MAX_REVISIONS = 2

export interface CriticVerdict {
  score: number
  verdict: 'pass' | 'revise'
  /** 이대로 나가면 안 되는 것. 하나라도 있으면 revise. */
  must_fix: { path: string; issue: string; fix: string }[]
  /** 고치면 좋은 것. 점수에만 반영. */
  should_fix: { path: string; issue: string; fix: string }[]
  strengths: string[]
  /** 항목별 점수 (0~10) */
  rubric: Record<RubricKey, number>
}

export type RubricKey =
  | 'activity' | 'representation' | 'transfer' | 'misconception'
  | 'feedback' | 'alignment' | 'honesty' | 'voice'

export const RUBRIC: Record<RubricKey, string> = {
  activity: '설명 한 단위마다 학생이 결정·예측·계산·표시·설명하는가. 읽기가 학습의 대부분이면 0점.',
  representation: '과목 특유의 표상(그래프·패턴·커브·비교)이 실제로 있고 본문이 그것을 쓰는가. "머릿속으로 그려 보세요" 는 표상이 아니다.',
  transfer: '문제가 본문의 예시를 숫자만 바꾼 것이 아니라 새 상황·반례·오류 분석인가. 정답이 본문에 그대로 있으면 0점.',
  misconception: '입문용 단순화가 잘못된 개념으로 굳지 않는가. 제목·헤드라인이 오개념을 먼저 심지 않는가. 은유와 사실의 경계를 표시하는가.',
  feedback: '오답 유형별 진단이 있는가. "본론 N번에서 말했어요" 는 해설이 아니다. 정답 보기 전에 학생이 답하게 만드는가.',
  alignment: '학습 목표·활동·평가가 1:1로 맞는가. 목표에 "그림으로 설명" 이라 했으면 그림이 있고 그림으로 답하는 문제가 있는가.',
  honesty: '시간이 본학습/연습/선택과제로 나뉘어 있고 서로 맞는가. "입문" 이 전제하는 선수지식을 밝히는가. 미검증 사실을 배지로 내보내지 않는가.',
  voice: '파르가 오개념 교정·힌트에만 쓰였는가. "저도 처음엔…" 이 반복되어 문체 템플릿이 되지 않았는가.',
}

/** 정적 린트가 먼저 잡은 것을 함께 넘긴다. 검사관은 그 위에서 판단만 한다. */
export function buildCriticPrompt(content: WorksheetContent, staticIssues: string[]): string {
  const rubric = Object.entries(RUBRIC).map(([k, v]) => `- ${k}: ${v}`).join('\n')
  return [
    '아래 학습지를 교수설계 관점에서 채점하세요. 디자인이나 말투의 친절함은 채점 대상이 아닙니다.',
    '기준은 하나입니다: 이 학습지로 학습이 실제로 일어나는가.',
    '',
    '루브릭 (각 0~10):',
    rubric,
    '',
    '판정 규칙:',
    `- 총점은 루브릭 합계를 100점 만점으로 환산합니다. ${PASS_SCORE}점 미만이면 revise.`,
    '- must_fix 가 하나라도 있으면 점수와 무관하게 revise.',
    '- must_fix 는 "이대로 나가면 학생이 틀린 것을 배운다" 수준만 넣습니다. 취향은 should_fix 로.',
    '- fix 는 구체적으로 씁니다. "더 좋게" 가 아니라 "Q1 을 고전적 입자 모델로는 왜 설명 못 하는지 묻는 문제로 바꾼다".',
    '',
    staticIssues.length
      ? `정적 검사가 이미 잡은 것 (이것들은 must_fix 에 다시 넣지 말고, 이것 외의 문제를 찾으세요):\n${staticIssues.map((s) => `- ${s}`).join('\n')}`
      : '정적 검사는 통과했습니다.',
    '',
    '학습지 JSON:',
    JSON.stringify(content),
  ].join('\n')
}

export const CRITIC_SYSTEM_PROMPT = `당신은 학습지 검사관입니다. 예쁘게 만들어졌는지, 친절한지는 보지 않습니다.
학생이 이 학습지를 끝냈을 때 실제로 무엇을 할 수 있게 되는지만 봅니다.

특히 경계할 것:
- 매끄러운 UX 가 수동적 읽기, 얕은 문제, 개념적 단순화를 가립니다. 겉모습에 속지 마세요.
- "입문자를 위해" 라는 이유로 핵심 표상(수식·그래프)을 제거한 경우, 그건 배려가 아니라 결함입니다.
- 쉬운 설명은 정확한 표상으로 가는 다리여야지 표상을 대체하면 안 됩니다.
- 헤드라인이 오개념을 심으면 본문에서 아무리 정정해도 늦습니다.

지정된 JSON 스키마로만 답합니다.`

export const CRITIC_OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['score', 'verdict', 'must_fix', 'should_fix', 'strengths', 'rubric'],
  properties: {
    score: { type: 'integer', minimum: 0, maximum: 100 },
    verdict: { type: 'string', enum: ['pass', 'revise'] },
    must_fix: { type: 'array', maxItems: 10, items: {
      type: 'object', additionalProperties: false, required: ['path', 'issue', 'fix'],
      properties: { path: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } } } },
    should_fix: { type: 'array', maxItems: 10, items: {
      type: 'object', additionalProperties: false, required: ['path', 'issue', 'fix'],
      properties: { path: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } } } },
    strengths: { type: 'array', maxItems: 5, items: { type: 'string' } },
    rubric: { type: 'object', additionalProperties: false,
      required: Object.keys(RUBRIC),
      properties: Object.fromEntries(Object.keys(RUBRIC).map((k) => [k, { type: 'integer', minimum: 0, maximum: 10 }])) },
  },
}

/** 검사관 응답을 정규화한다. 점수와 must_fix 가 어긋나면 엄격한 쪽을 따른다. */
export function normalizeVerdict(raw: unknown): CriticVerdict {
  const r = (raw ?? {}) as any
  const must = Array.isArray(r.must_fix) ? r.must_fix : []
  const score = Number.isFinite(r.score) ? Math.max(0, Math.min(100, Math.round(r.score))) : 0
  const verdict: 'pass' | 'revise' = must.length > 0 || score < PASS_SCORE ? 'revise' : 'pass'
  return {
    score, verdict,
    must_fix: must,
    should_fix: Array.isArray(r.should_fix) ? r.should_fix : [],
    strengths: Array.isArray(r.strengths) ? r.strengths : [],
    rubric: r.rubric ?? {},
  }
}

/** 재작성 프롬프트에 붙일 문구. 정적 린트 + 검사관 must_fix 를 합친다. */
export function revisionInstructions(staticIssues: string[], verdict: CriticVerdict): string {
  const lines = [
    '이전 초안은 검사에서 반려되었습니다. 아래를 모두 고쳐서 다시 쓰세요.',
    '설계도의 사실 판단과 문제 구성은 그대로 두고, 지적된 부분만 고칩니다.',
    '',
  ]
  if (staticIssues.length) lines.push('정적 검사 지적:', ...staticIssues.map((s) => `- ${s}`), '')
  if (verdict.must_fix.length) {
    lines.push(`검사관 반려 사유 (점수 ${verdict.score}/100):`)
    for (const m of verdict.must_fix) lines.push(`- ${m.path}: ${m.issue} → ${m.fix}`)
  }
  return lines.join('\n')
}
