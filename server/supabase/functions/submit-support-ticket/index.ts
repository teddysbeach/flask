// POST /functions/v1/submit-support-ticket  { topic, body, app_version?, platform? }
//
// 문의 접수. **로그인하지 않아도 된다.**
// 로그인이 안 돼서 문의하는 사람에게 "문의하려면 로그인하세요" 라고 답하는 앱은 만들지 않는다.
// 로그인했으면 user_id 를 채워서 본인이 나중에 자기 문의를 볼 수 있게 한다.
//
// 앱이 테이블에 직접 넣지 않고 여기로 오는 이유:
//   · 검증을 한곳에 둔다(길이·유형). 화면만 막으면 API 로는 얼마든지 들어온다.
//   · 접수 번호를 돌려줘야 사용자가 "보냈다" 를 믿을 근거가 생긴다.
//   · 도배를 막는다. 열려 있는 입구는 반드시 두들겨 맞는다.
//
// 실패하면 앱은 메일 폴백으로 돌아간다 — 서버가 죽었을 때 사용자가 우리에게 닿을 마지막 길이다.
// 그래서 여기서는 실패를 숨기지 않고 분명한 상태 코드로 돌려준다.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'

/** 앱의 ContactTopic 과 같은 닫힌 목록. DB 의 check 제약과도 같아야 한다. */
const TOPICS = ['payment', 'generation', 'annotation', 'review', 'account', 'other'] as const
const PLATFORMS = ['ios', 'android', 'other'] as const

/** 본문 길이 상한. 화면의 maxLength · DB 의 check 제약과 같은 값이다. */
const BODY_MAX = 2000
const BODY_MIN = 10

/** 1분 안에 이만큼까지만. 넘으면 429. */
const RATE_WINDOW_MS = 60_000
const RATE_LIMIT = 3

export interface TicketInput {
  topic: string
  body: string
  app_version: string | null
  platform: string | null
}

/**
 * 요청 본문 검증. **순수 함수**로 떼어 둔다 — 규칙이 틀리면 조용히 빈 문의가 쌓이는데,
 * 그건 배포한 뒤에는 알아채기 어렵다.
 */
export function validateTicket(raw: any): { ok: true; value: TicketInput } | { ok: false; error: string } {
  const topic = typeof raw?.topic === 'string' ? raw.topic.trim() : ''
  if (!(TOPICS as readonly string[]).includes(topic)) return { ok: false, error: 'invalid_topic' }

  const body = typeof raw?.body === 'string' ? raw.body.trim() : ''
  // 글자 수는 코드 유닛이 아니라 사람이 센 글자로 잰다.
  // "🙂" 를 두 글자로 세면 사용자는 다 적었는데도 짧다는 말을 듣는다.
  const length = [...body].length
  if (length < BODY_MIN) return { ok: false, error: 'body_too_short' }
  if (length > BODY_MAX) return { ok: false, error: 'body_too_long' }

  const version = typeof raw?.app_version === 'string' ? raw.app_version.trim().slice(0, 40) : ''
  const platformRaw = typeof raw?.platform === 'string' ? raw.platform.trim() : ''
  const platform = (PLATFORMS as readonly string[]).includes(platformRaw) ? platformRaw : null

  return {
    ok: true,
    value: { topic, body, app_version: version === '' ? null : version, platform },
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 405)

  // 로그인은 **선택**이다. 토큰이 없거나 만료됐으면 익명 문의로 받는다.
  const auth = req.headers.get('Authorization') ?? ''
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )
  // 토큰이 없거나 만료됐으면 그냥 익명 문의다. 여기서 401 로 끊으면 안 된다.
  let userId: string | null = null
  try {
    const { data } = await supabase.auth.getUser()
    userId = data?.user?.id ?? null
  } catch (_) {
    userId = null
  }

  const parsed = validateTicket(await req.json().catch(() => ({})))
  if (!parsed.ok) {
    return errorResponse(parsed.error, 400, {
      detail: parsed.error === 'invalid_topic'
        ? '문의 유형을 골라 주세요.'
        : `문의 내용은 ${BODY_MIN}~${BODY_MAX}자여야 합니다.`,
    })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // 도배 방지. 실수로 두 번 누른 사람은 막지 않고(3건까지), 스크립트는 막는다.
  //
  // 로그인한 사용자만 정확히 셀 수 있다. 익명 문의는 셀 열쇠가 없는데,
  // 그걸 만들려고 IP 를 저장하면 문의함에 없어도 될 개인정보가 쌓인다 —
  // 도배를 막자고 개인정보를 모으는 건 거래가 맞지 않는다.
  // (익명 문의는 본문 길이 상한과 게이트웨이 단의 호출 제한에 기댄다.)
  if (userId) {
    const since = new Date(Date.now() - RATE_WINDOW_MS).toISOString()
    const { count, error } = await admin
      .from('support_tickets')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .gte('created_at', since)
    // 세는 데 실패했다고 문의를 막지는 않는다. 접수가 도배 방지보다 중요하다.
    if (!error && (count ?? 0) >= RATE_LIMIT) {
      return errorResponse('rate_limited', 429, {
        detail: '문의가 너무 빠르게 들어왔어요. 잠시 뒤에 다시 시도해 주세요.',
      })
    }
  }

  const { data, error } = await admin
    .from('support_tickets')
    .insert({
      user_id: userId,
      topic: parsed.value.topic,
      body: parsed.value.body,
      app_version: parsed.value.app_version,
      platform: parsed.value.platform,
    })
    .select('id')
    .single()

  if (error || !data) {
    // 원문은 로그에만. 사용자에게는 코드만 나가고, 앱은 이걸 보고 메일 폴백으로 간다.
    console.error('[submit-support-ticket] insert 실패', error?.message)
    return errorResponse('insert_failed', 500)
  }

  return json({ ok: true, ticket_id: data.id }, 201)
})
