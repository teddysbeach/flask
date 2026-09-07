// POST /functions/v1/delete-worksheet  { worksheet_id }
//
// 학습지 한 장을 지운다.
//
// 앱이 직접 지우지 않고 여기로 오는 이유는 **스토리지 때문**이다. DB 행을 지우면
// quiz_items·responses·review_schedules·annotations 는 FK 로 따라 지워지지만,
// Storage 의 파일(학습지 HTML, 필기 JSON)은 아무도 안 지운다. 앱이 두 번 나눠 지우면
// 중간에 끊겼을 때 주인 없는 파일이 남고, 그건 사용자가 "지웠다" 고 믿는 데이터다.
//
// 순서가 중요하다: **파일 먼저, 행은 나중.**
// 행을 먼저 지우면 경로를 잃어버려서 파일을 영영 못 찾는다.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 405)

  const auth = req.headers.get('Authorization') ?? ''
  const url = Deno.env.get('SUPABASE_URL')!
  const supabase = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
  })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return errorResponse('unauthorized', 401)

  const body = await req.json().catch(() => ({}))
  const id = typeof body.worksheet_id === 'string' ? body.worksheet_id : ''
  if (!id) return errorResponse('invalid_worksheet', 400)

  // 주인 확인은 **사용자 토큰으로** 한다. RLS 가 남의 학습지를 안 보여주므로,
  // 못 읽으면 그 자체가 답이다. 서비스 롤로 조회하면 그 검사를 우리가 다시 짜야 한다.
  const { data: sheet } = await supabase
    .from('worksheets').select('id, html_path').eq('id', id).maybeSingle()
  if (!sheet) return errorResponse('not_found', 404)

  const { data: annotation } = await supabase
    .from('annotations').select('strokes_path').eq('worksheet_id', id).maybeSingle()

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  // ① 파일 먼저. 실패하면 여기서 멈춘다 — 행을 지워 버리면 경로를 잃는다.
  const removals: Array<Promise<{ error: unknown }>> = []
  if (sheet.html_path) {
    removals.push(admin.storage.from('worksheets').remove([sheet.html_path]) as never)
  }
  if (annotation?.strokes_path) {
    removals.push(admin.storage.from('annotations').remove([annotation.strokes_path]) as never)
  }
  for (const r of await Promise.all(removals)) {
    if (r.error) {
      console.error('[delete-worksheet] 파일 삭제 실패', r.error)
      return errorResponse('storage_failed', 500, {
        detail: '학습지 파일을 지우지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
      })
    }
  }

  // ② 행. 나머지(문항·응답·복습 회차·필기 메타)는 FK 로 따라 지워진다.
  const { error } = await supabase.from('worksheets').delete().eq('id', id)
  if (error) {
    console.error('[delete-worksheet] 행 삭제 실패', error.message)
    return errorResponse('delete_failed', 500)
  }

  // 쿼터는 돌려주지 않는다. 이미 만든 학습지이고, 돌려주면 "만들고 지우기" 로
  // 장수를 무한히 쓸 수 있다.
  return json({ ok: true, deleted: id }, 200)
})
