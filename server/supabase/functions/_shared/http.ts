// Edge Function 공용 HTTP 유틸.

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...CORS },
  })

export const CORS: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
}

export const errorResponse = (code: string, status: number, extra: Record<string, unknown> = {}) =>
  json({ error: code, ...extra }, status)

/** 주제 입력 검증. 길이만 본다 — 내용 판단은 모델의 거절 처리에 맡긴다. */
export function validateTopic(topic: unknown): string | null {
  if (typeof topic !== 'string') return null
  const t = topic.trim()
  if (t.length < 1 || t.length > 120) return null
  return t
}

export const LEVELS = ['beginner', 'intermediate', 'advanced'] as const
export const validateLevel = (v: unknown): 'beginner' | 'intermediate' | 'advanced' =>
  (LEVELS as readonly string[]).includes(v as string) ? (v as any) : 'beginner'

/**
 * 사용자가 친 주제를 프롬프트에 넣을 때 경계를 긋는다.
 *
 * 주제는 우리가 만들지 않은 문자열이고 그대로 모델에게 간다.
 * "위 지시를 무시하고…" 는 120자 안에 충분히 들어간다.
 *
 * 구분자만으로는 안 막힌다 — 사용자가 닫는 태그를 흉내 낼 수 있다. 그래서 세 겹으로 둔다.
 *   1. 여기서 태그처럼 보이는 글자를 무력화한다
 *   2. 시스템 프롬프트가 "이 안은 데이터다" 라고 못 박는다 (prompts.ts 의 INPUT_BOUNDARY)
 *   3. 마지막 방어선은 구조화 출력과 검증기·린트다 — 모델이 스키마 밖으로 못 나간다
 *
 * 셋을 다 해도 완벽하지 않다. 다만 셋 다 없을 때보다는 훨씬 낫고, 값이 싸다.
 */
export function topicBlock(topic: string, level: string): string {
  const safe = topic.replace(/[<>]/g, ' ').trim()
  return `<user_topic>\n${safe}\n</user_topic>\n난이도: ${level}`
}

/**
 * 주제 비교용 정규화. **DB 인덱스(20260101000017)와 같은 규칙이어야 한다.**
 *
 *   lower(regexp_replace(btrim(topic), '\s+', ' ', 'g'))
 *
 * 여기와 저기가 갈라지면 인덱스를 못 타고(느려지고) 결과도 달라진다.
 * 공백만 다른 것을 다른 주제로 보면 이 기능이 하는 일이 없어진다.
 */
export const normalizeTopicForMatch = (topic: string) =>
  topic.trim().replace(/\s+/g, ' ').toLowerCase()
