// pipeline.ts 의 Deps 를 Supabase 로 구현한다.
// 파이프라인 로직은 이 파일을 모르고, 테스트는 이 자리에 가짜를 넣는다.

import type { Deps, ErrorCode } from './pipeline.ts'
import type { LlmClient } from './claude-parse.ts'
import type { WorksheetContent } from './worksheet-types.ts'

export function makeDeps(admin: any, llm: LlmClient): Deps {
  return {
    llm,
    storage: {
      async putHtml(path: string, html: string) {
        const { error } = await admin.storage.from('worksheets').upload(
          path, new Blob([html], { type: 'text/html; charset=utf-8' }),
          { upsert: true, contentType: 'text/html; charset=utf-8' },
        )
        if (error) throw error
      },
    },
    now: () => new Date(),
    newId: () => crypto.randomUUID(),

    db: {
      async consumeQuota(userId) {
        const { data, error } = await admin.rpc('consume_quota', { p_user: userId })
        if (error) throw error
        return data === true
      },
      async refundQuota(userId) {
        const { error } = await admin.rpc('refund_quota', { p_user: userId })
        if (error) throw error
      },
      async createWorksheet(row) {
        const { error } = await admin.from('worksheets').insert({
          id: row.id, user_id: row.userId, topic: row.topic, level: row.level, status: 'queued',
        })
        if (error) throw error
      },

      async saveContent(worksheetId, content: WorksheetContent, meta) {
        // 문제와 사전학습 제안은 jsonb 에 묻지 않고 테이블로 꺼낸다.
        // 복습 스케줄이 quiz_items.id 를 참조해야 하기 때문이다.
        const { data: ws, error: e0 } = await admin.from('worksheets')
          .update({
            status: 'ready',
            title: content.title,
            content,
            html_path: meta.htmlPath,
            plan_model: meta.planModel,
            draft_model: meta.draftModel,
            quality_score: meta.qualityScore,
            revisions: meta.revisions,
            ready_at: new Date().toISOString(),
          })
          .eq('id', worksheetId).select('user_id').single()
        if (e0) throw e0

        const userId = ws.user_id
        const { error: e1 } = await admin.from('quiz_items').insert(
          content.quiz.map((q, i) => ({
            id: meta.quizItemIds[i],
            worksheet_id: worksheetId, user_id: userId, idx: i,
            kind: q.kind, question: q.question, choices: q.choices,
            answer: q.answer, explanation: q.explanation, difficulty: q.difficulty,
          })),
        )
        if (e1) throw e1

        const { error: e2 } = await admin.from('prerequisite_suggestions').insert(
          content.prerequisites.map((p, i) => ({
            worksheet_id: worksheetId, user_id: userId, idx: i,
            title: p.title, why: p.why, one_liner: p.one_liner,
          })),
        )
        if (e2) throw e2
      },

      async saveSchedules(worksheetId, userId, seeds: any[]) {
        const { error } = await admin.from('review_schedules').insert(
          seeds.map((s) => ({
            user_id: userId, worksheet_id: worksheetId, quiz_item_id: s.quizItemId,
            repetition: s.repetition, interval_days: s.intervalDays,
            ease: s.ease, due_at: s.dueAt.toISOString(), state: 'pending',
          })),
        )
        if (error) throw error
      },

      async failWorksheet(worksheetId, code: ErrorCode, detail: string) {
        await admin.from('worksheets')
          .update({ status: 'failed', error_code: code })
          .eq('id', worksheetId)
        void detail   // 상세는 generation_jobs 에 남긴다 (사용자에게 노출하지 않는다)
      },

      async recordJob(job) {
        const p: any = job.planUsage ?? {}
        const d: any = job.draftUsage ?? {}
        const k: any = job.criticUsage ?? {}
        await admin.from('generation_jobs').insert({
          worksheet_id: job.worksheetId, user_id: job.userId,
          attempt: job.attempt, stage: job.stage, status: job.status,
          error_code: job.errorCode ?? null,
          plan_tokens_in: p.inputTokens ?? 0, plan_tokens_out: p.outputTokens ?? 0,
          draft_tokens_in: d.inputTokens ?? 0, draft_tokens_out: d.outputTokens ?? 0,
          critic_tokens_in: k.inputTokens ?? 0, critic_tokens_out: k.outputTokens ?? 0,
          cache_read_tokens: (p.cacheReadTokens ?? 0) + (d.cacheReadTokens ?? 0) + (k.cacheReadTokens ?? 0),
          quality_score: job.qualityScore ?? null,
          revisions: job.revisions ?? 0,
          cost_usd: job.costUsd,
          finished_at: new Date().toISOString(),
        })
      },

      async recentCostsUsd(limit) {
        const { data } = await admin.from('generation_jobs')
          .select('cost_usd').eq('status', 'succeeded')
          .order('finished_at', { ascending: false }).limit(limit)
        return (data ?? []).map((r: any) => Number(r.cost_usd)).filter((n: number) => Number.isFinite(n))
      },

      async userPrefs(userId) {
        const { data } = await admin.from('profiles')
          .select('timezone, review_hour').eq('id', userId).single()
        return { timeZone: data?.timezone ?? 'Asia/Seoul', reviewHour: data?.review_hour ?? 21 }
      },
    },
  }
}
