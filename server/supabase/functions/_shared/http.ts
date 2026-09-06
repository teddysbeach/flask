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
