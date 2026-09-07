// POST /functions/v1/answer-review  { schedule_id, grade }
//
// 복습 한 문제에 답했을 때 다음 회차를 잡는다.
//
// 왜 앱이 직접 안 쓰고 여기로 오는가:
//   SM-2 를 앱에 넣으면 서버(review-schedule.ts)와 두 벌이 되고, 두 벌은 갈라진다.
//   갈라지면 "쉽다고 했는데 내일 또 나오는" 식으로 조용히 틀린다 — 사용자는 원인을 모른다.
// RLS 로 남의 회차는 못 읽으므로 사용자 토큰으로 그대로 일한다(서비스 롤이 필요 없다).

import { createClient } from 'npm:@supabase/supabase-js@2'
import { json, errorResponse, CORS } from '../_shared/http.ts'
import { planAnswer } from '../_shared/review-answer.ts'

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
  const scheduleId = typeof body.schedule_id === 'string' ? body.schedule_id : ''
  const grade = Number(body.grade)
  if (!scheduleId) return errorResponse('invalid_schedule', 400)
  if (!Number.isInteger(grade) || grade < 0 || grade > 3) {
    return errorResponse('invalid_grade', 400, { detail: 'grade 는 0~3 이어야 합니다' })
  }

  const { data: row, error: e0 } = await supabase
    .from('review_schedules')
    .select('id, worksheet_id, quiz_item_id, repetition, interval_days, ease, due_at, state')
    .eq('id', scheduleId)
    .single()
  if (e0 || !row) return errorResponse('not_found', 404)

  // 이미 답한 회차에 또 답하면 조용히 성공으로 둔다.
  // 알림을 두 번 눌렀을 뿐인데 오류를 띄우면 사용자는 자기가 뭘 잘못했다고 생각한다.
  if (row.state !== 'pending') return json({ ok: true, already: true }, 200)

  const { data: prefs } = await supabase
    .from('profiles').select('timezone, review_hour').eq('id', user.id).single()
  const timeZone = prefs?.timezone ?? 'Asia/Seoul'
  const reviewHour = prefs?.review_hour ?? 21

  const { data: remaining } = await supabase
    .from('review_schedules')
    .select('id, worksheet_id, quiz_item_id, repetition, interval_days, ease, due_at, state')
    .eq('worksheet_id', row.worksheet_id)
    .eq('state', 'pending')

  const toRow = (r: any) => ({
    id: r.id, quizItemId: r.quiz_item_id, repetition: r.repetition,
    intervalDays: r.interval_days, ease: Number(r.ease),
    dueAt: new Date(r.due_at), state: r.state,
  })

  const plan = planAnswer(
    toRow(row), (remaining ?? []).map(toRow), grade, new Date(), timeZone, reviewHour,
  )

  const { error: e1 } = await supabase.from('review_schedules').update({
    state: plan.update.state,
    ease: plan.update.ease,
    grade: plan.update.grade,
    answered_at: plan.update.answeredAt,
  }).eq('id', plan.update.id)
  if (e1) return errorResponse('update_failed', 500)

  // 남은 회차의 간격을 새 ease 로 다시 잡는다. 하나가 실패해도 나머지는 살린다 —
  // 여기서 통째로 실패시키면 방금 답한 것까지 되돌릴 방법이 없다.
  for (const r of plan.reschedule) {
    await supabase.from('review_schedules')
      .update({ interval_days: r.intervalDays, ease: r.ease, due_at: r.dueAt })
      .eq('id', r.id)
  }

  if (plan.relearn) {
    await supabase.from('review_schedules').insert({
      user_id: user.id,
      worksheet_id: row.worksheet_id,
      quiz_item_id: plan.relearn.quizItemId,
      repetition: plan.relearn.repetition,
      interval_days: plan.relearn.intervalDays,
      ease: plan.relearn.ease,
      due_at: plan.relearn.dueAt,
      state: 'pending',
    })
  }

  return json({
    ok: true,
    state: plan.update.state,
    ease: plan.update.ease,
    rescheduled: plan.reschedule.length,
    relearn: plan.relearn != null,
  }, 200)
})
