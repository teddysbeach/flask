// POST /functions/v1/delete-account  { reason, detail? }
//
// 회원탈퇴. auth.users 삭제는 서비스 롤만 할 수 있어서 서버가 한다 —
// 앱이 직접 지울 수 있으면 남의 계정도 지울 수 있다는 뜻이다.
//
// 지우는 것과 남기는 것을 분명히 한다:
//   지운다  학습지 · 필기 · 복습 일정 · 응답 · 프로필 (on delete cascade)
//   남긴다  구매 내역 — 법정 보존 의무가 있다. 대신 **익명화**해서 사람과 잇지 못하게 한다.
//
// 남은 장수는 환불하지 않는다(앱이 탈퇴 전에 그렇게 고지한다).

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'

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
  const reason = typeof body.reason === 'string' ? body.reason.slice(0, 40) : 'unspecified'
  const detail = typeof body.detail === 'string' ? body.detail.slice(0, 500) : null

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // 1. 탈퇴 사유는 사람과 잇지 않고 통계로만 남긴다.
  //    사유를 계정에 붙여 두면 "탈퇴한 사람이 왜 나갔는지" 를 나중에 되짚을 수 있게 되고,
  //    그건 지웠다고 말한 것을 안 지운 셈이다.
  await admin.from('withdrawal_reasons').insert({ reason, detail }).select().maybeSingle();

  // 2. 구매 내역 익명화. 행은 남기되 사용자와 끊는다.
  await admin.from('purchases')
    .update({ user_id: null, anonymized_at: new Date().toISOString() })
    .eq('user_id', user.id)

  // 3. 저장소에 올린 학습지 HTML 과 필기 파일. DB cascade 가 지우지 못하는 것들이다.
  for (const bucket of ['worksheets', 'annotations']) {
    const { data: files } = await admin.storage.from(bucket).list(user.id)
    if (files && files.length) {
      await admin.storage.from(bucket).remove(files.map((f) => `${user.id}/${f.name}`))
    }
  }

  // 4. 계정 삭제. profiles → worksheets → quiz_items/annotations/review_schedules/responses 가
  //    전부 on delete cascade 로 따라 지워진다.
  const { error } = await admin.auth.admin.deleteUser(user.id)
  if (error) {
    console.error('[delete-account] 삭제 실패', error.message)
    return errorResponse('delete_failed', 500)
  }

  return json({ ok: true }, 200)
})
