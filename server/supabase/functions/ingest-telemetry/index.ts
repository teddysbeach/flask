// POST /functions/v1/ingest-telemetry  { install_id, app_version?, platform?, events?, crashes? }
//
// 사용 이벤트와 크래시를 받는다. **로그인하지 않아도 된다** — 온보딩과 가입 실패가
// 로그인 전에 일어나고, 크래시는 특히 로그인 화면에서 난다.
//
// 왜 제3자 SDK 를 안 쓰는가: 개인정보 처리방침에 "제3자 공유 없음" 이라고 적었기 때문이다.
// SDK 를 하나 붙이는 순간 그 줄이 거짓말이 되고 스토어 신고 내용도 바뀐다.
//
// 무엇을 받지 않는가: 주제 원문·답안·이메일·영수증. 앱이 한 번 거르고
// (_shared/telemetry.ts 의 허용 목록) 여기서 또 거른다. 두 겹인 이유는,
// 앱은 사용자 기기에 있어서 고쳐 보낼 수 있기 때문이다.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'
import { cleanCrashes, cleanEvents, cleanInstallId } from '../_shared/telemetry.ts'

const PLATFORMS = ['ios', 'android', 'other']

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 405)

  const body = await req.json().catch(() => ({}))
  const installId = cleanInstallId(body.install_id)
  if (!installId) return errorResponse('invalid_install_id', 400)

  const events = cleanEvents(body.events)
  const crashes = cleanCrashes(body.crashes)
  // 보낼 것이 없으면 성공으로 돌려보낸다. 앱이 재시도할 이유가 없다.
  if (events.length === 0 && crashes.length === 0) return json({ ok: true, stored: 0 }, 200)

  const appVersion = typeof body.app_version === 'string' ? body.app_version.slice(0, 32) : null
  const platform = PLATFORMS.includes(body.platform) ? body.platform : 'other'

  // 로그인 여부는 **선택**이다. 토큰이 있으면 사용자를 잇고, 없으면 익명으로 받는다.
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const url = Deno.env.get('SUPABASE_URL')!
  let userId: string | null = null
  const auth = req.headers.get('Authorization') ?? ''
  if (auth && !auth.includes(anon)) {
    const asUser = createClient(url, anon, { global: { headers: { Authorization: auth } } })
    const { data } = await asUser.auth.getUser()
    userId = data?.user?.id ?? null
  }

  // 쓰기는 service_role 이 한다. 테이블에는 정책이 하나도 없어서 사용자 토큰으로는 못 쓴다 —
  // 열어 두면 남의 계정 이름으로 이벤트를 넣을 수 있게 된다.
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  const common = { user_id: userId, install_id: installId, app_version: appVersion, platform }
  let stored = 0

  if (events.length > 0) {
    const { error } = await admin.from('telemetry_events')
      .insert(events.map((e) => ({ ...common, ...e })))
    // 실패를 앱에 알리지 않는다. 텔레메트리 때문에 사용자 화면에 오류가 뜨면 본말전도다.
    if (error) console.error('[telemetry] events insert 실패', error.message)
    else stored += events.length
  }

  if (crashes.length > 0) {
    const { error } = await admin.from('crash_reports')
      .insert(crashes.map((c) => ({ ...common, ...c })))
    if (error) console.error('[telemetry] crashes insert 실패', error.message)
    else stored += crashes.length
  }

  return json({ ok: true, stored }, 200)
})
