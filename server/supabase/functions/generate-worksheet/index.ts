// POST /functions/v1/generate-worksheet
//
// 쿼터를 차감하고 202 를 즉시 돌려준 다음, 응답 뒤에 생성을 계속한다.
// Opus + Sonnet 두 번 호출이라 40~120초가 걸리므로 동기 응답은 타임아웃 지옥이 된다.
// docs/plan/01-architecture.md §3

import { createClient } from 'npm:@supabase/supabase-js@2'

/** 하루에 만들 수 있는 학습지 상한. 쿼터(장수)와 별개로 도는 남용 방지선이다. */
const DAILY_LIMIT = 30
import { json, errorResponse, CORS, validateTopic, validateLevel, normalizeTopicForMatch } from '../_shared/http.ts'
import { acceptGeneration, runGeneration, toErrorCode, isRetryable, MAX_ATTEMPTS, backoffMs, newCostBudget, newDeadline } from '../_shared/pipeline.ts'
import { createLlmClient } from '../_shared/claude.ts'
import { makeDeps } from '../_shared/deps.ts'
import { PLAN_SYSTEM_PROMPT, DRAFT_SYSTEM_PROMPT, OUTLINE_SCHEMA, WORKSHEET_SCHEMA } from '../_shared/prompts.ts'

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

  // 끊긴 생성부터 치운다.
  //
  // 생성은 응답을 보낸 뒤 waitUntil 안에서 도는데, 그 백그라운드가 죽으면(배포·인스턴스 회수·
  // wall clock 초과) 행이 'generating' 인 채 남는다. 그러면 차감한 장수가 안 돌아오고,
  // 바로 아래 "하나만" 가드가 그 행을 보고 **영원히** 429 를 돌려준다.
  // 돈 낸 사람이 다시는 학습지를 못 만드는 상태라 재설치로도 안 풀린다.
  // 그래서 새 요청을 받을 때마다 10분 넘게 매달린 것을 실패로 닫고 장수를 되돌린다.
  const { error: reapError } = await admin.rpc('reap_stale_generations', { p_user: user.id })
  // 청소에 실패해도 생성 요청 자체를 막지는 않는다. 아래 가드가 어차피 한 번 더 본다.
  if (reapError) console.error('[generate] 청소 실패', reapError.message)

  // 같은 주제로 이미 만든 것이 있으면 먼저 알려 준다. 막지는 않는다 —
  // 다시 만들 이유는 사용자에게 있을 수 있고(난이도를 바꾸고 싶다, 지난번이 마음에 안 들었다)
  // 그건 우리가 판단할 일이 아니다. 다만 **모르고 한 장을 더 쓰는 것**은 막아야 한다.
  if (body.force !== true) {
    const { data: dupes } = await admin.from('worksheets')
      .select('id, topic, title, created_at')
      .eq('user_id', user.id).eq('status', 'ready')
      .order('created_at', { ascending: false }).limit(50)
    const key = normalizeTopicForMatch(topic)
    const hit = (dupes ?? []).find((w: { topic: string }) => normalizeTopicForMatch(w.topic) === key)
    if (hit) {
      return errorResponse('duplicate_topic', 409, {
        worksheet_id: hit.id, title: hit.title, created_at: hit.created_at,
      })
    }
  }

  // 하루 상한.
  //
  // 무료 2장은 계정을 새로 만들면 또 2장이라, 지금까지 상한이 없었다. 기기 지문은
  // 못 믿고 만들어서도 안 되므로 **하루에 만드는 장수**에 상한을 둔다 — 남용의 비용은
  // 결국 생성 요청(모델에 내는 돈)이라 거기에 거는 것이 맞다.
  // 정상 사용은 닿지 않는다. 하루 30장을 만드는 사람은 학습을 하는 것이 아니다.
  const madeToday = await admin.rpc('daily_generation_count', { p_user: user.id })
  if ((madeToday.data ?? 0) >= DAILY_LIMIT) {
    return errorResponse('daily_limit_reached', 429, {
      detail: `하루에 만들 수 있는 학습지는 ${DAILY_LIMIT}장이에요. 내일 다시 시도해 주세요.`,
      limit: DAILY_LIMIT,
    })
  }

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
  // 예산은 시도들이 함께 쓴다. 시도마다 새로 주면 한 장에 상한 × 3 을 쓸 수 있다.
  const budget = newCostBudget()
  // 시간도 마찬가지다. 시도마다 8분을 새로 주면 살아 있는 생성이 DB 청소 기준(10분)을
  // 넘겨 환불당하고, 다 만든 학습지를 버리게 된다.
  const deadline = newDeadline(deps.now())
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      await runGeneration(deps, input, worksheetId, attempt, budget, deadline)
      return
    } catch (e) {
      const code = toErrorCode(e)
      if (!isRetryable(code) || attempt === MAX_ATTEMPTS) return
      // runGeneration 이 이미 환불했으므로 재시도 전에 쿼터를 다시 차감한다.
      // 차감이 실패하면(그 사이 장수가 없어졌다면) 조용히 멈춘다 — 이미 환불은 끝났다.
      if (!await deps.db.consumeQuota(input.userId)) return
      await new Promise((r) => setTimeout(r, backoffMs(attempt)))
    }
  }
}

/**
 * 프롬프트와 스키마는 저장소(prompts.ts)가 기본값이고, 환경변수는 실험용 덮어쓰기다.
 * 예전에는 환경변수만 있어서 프롬프트가 저장소에 없었다 — 버전 추적이 안 됐다.
 */
function loadPrompts() {
  const env = (k: string) => {
    const v = Deno.env.get(k)
    return v && v.trim() ? v : undefined
  }
  const schema = (k: string, fallback: unknown) => {
    const v = env(k)
    return v ? JSON.parse(v) : fallback
  }
  return {
    planModel: env('WORKSHEET_PLAN_MODEL'),
    draftModel: env('WORKSHEET_DRAFT_MODEL'),
    criticModel: env('WORKSHEET_CRITIC_MODEL'),
    planSystemPrompt: env('PLAN_SYSTEM_PROMPT') ?? PLAN_SYSTEM_PROMPT,
    draftSystemPrompt: env('DRAFT_SYSTEM_PROMPT') ?? DRAFT_SYSTEM_PROMPT,
    outlineSchema: schema('OUTLINE_SCHEMA', OUTLINE_SCHEMA),
    worksheetSchema: schema('WORKSHEET_SCHEMA', WORKSHEET_SCHEMA),
  }
}
