// POST /functions/v1/generate-worksheet
//
// 쿼터를 차감하고 202 를 즉시 돌려준 다음, 응답 뒤에 생성을 계속한다.
// Opus + Sonnet 두 번 호출이라 40~120초가 걸리므로 동기 응답은 타임아웃 지옥이 된다.
// docs/plan/01-architecture.md §3

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS, validateTopic, validateLevel } from '../_shared/http.ts'
import { acceptGeneration, runGeneration, toErrorCode, isRetryable, MAX_ATTEMPTS, backoffMs } from '../_shared/pipeline.ts'
import { createLlmClient } from '../_shared/claude.ts'
import { makeDeps } from '../_shared/deps.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 405)

  const auth = req.headers.get('Authorization') ?? ''
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return errorResponse('unauthorized', 401)

  const body = await req.json().catch(() => ({}))
  const topic = validateTopic(body.topic)
  if (!topic) return errorResponse('invalid_topic', 400, { detail: '주제는 1~120자여야 합니다' })
  const level = validateLevel(body.level)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // 사용자당 진행 중인 생성은 하나만
  const { count } = await admin.from('worksheets')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id).in('status', ['queued', 'generating'])
  if ((count ?? 0) > 0) return errorResponse('generation_in_progress', 429)

  const deps = makeDeps(admin, createLlmClient(loadPrompts()))
  const input = { userId: user.id, topic, level }

  const accepted = await acceptGeneration(deps, input)
  if (!accepted) {
    const { data: p } = await admin.from('profiles')
      .select('quota_total, quota_used').eq('id', user.id).single()
    const { data: products } = await admin.from('products')
      .select('id, sheets, price_krw').eq('is_active', true).order('sort_order')
    return errorResponse('quota_exhausted', 402, { ...p, products })
  }

  // 응답을 보낸 뒤에도 계속 돌린다.
  EdgeRuntime.waitUntil(generateWithRetry(deps, input, accepted.worksheetId))

  const { data: p } = await admin.from('profiles')
    .select('quota_total, quota_used').eq('id', user.id).single()
  return json({
    worksheet_id: accepted.worksheetId,
    status: 'queued',
    quota_remaining: (p?.quota_total ?? 0) - (p?.quota_used ?? 0),
  }, 202)
})

async function generateWithRetry(deps: any, input: any, worksheetId: string) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      await runGeneration(deps, input, worksheetId, attempt)
      return
    } catch (e) {
      const code = toErrorCode(e)
      if (!isRetryable(code) || attempt === MAX_ATTEMPTS) return
      // runGeneration 이 이미 환불했으므로 재시도 전에 쿼터를 다시 차감한다.
      if (!await deps.db.consumeQuota(input.userId)) return
      await new Promise((r) => setTimeout(r, backoffMs(attempt)))
    }
  }
}

function loadPrompts() {
  return {
    planModel: Deno.env.get('WORKSHEET_PLAN_MODEL') ?? undefined,
    draftModel: Deno.env.get('WORKSHEET_DRAFT_MODEL') ?? undefined,
    planSystemPrompt: Deno.env.get('PLAN_SYSTEM_PROMPT')!,
    draftSystemPrompt: Deno.env.get('DRAFT_SYSTEM_PROMPT')!,
    outlineSchema: JSON.parse(Deno.env.get('OUTLINE_SCHEMA')!),
    worksheetSchema: JSON.parse(Deno.env.get('WORKSHEET_SCHEMA')!),
  }
}
