// pipeline.ts 의 Deps 를 Supabase 로 구현한다.
// 파이프라인 로직은 이 파일을 모르고, 테스트는 이 자리에 가짜를 넣는다.

import type { Deps, ErrorCode } from './pipeline.ts'
import type { LlmClient } from './claude-parse.ts'
import type { WorksheetContent } from './worksheet-types.ts'

/**
 * 학습지 런타임(ONPAR_LEARN.exportResponses())이 내는 응답 이력 한 줄.
 * 이 모양이 worksheet-interact.js 의 RESPONSES 레코드와 그대로 같아야 한다 —
 * 두 벌을 유지하면 반드시 어긋나고, 어긋나면 조용히 잘못된 학습분석이 나온다.
 */
export interface ResponseRow {
  id: string                       // 문서 내 결정론적 id (quiz-3, reason-1 …)
  kind: 'choice' | 'written'
  questionId?: string | null       // quiz_items.id (연습 문제일 때만)
  firstChoice?: number | null
  finalChoice?: number | null
  correct?: boolean | null
  attempts?: unknown[]
  text?: string | null
  chars?: number
  inkStrokes?: number
  msSincePrompt?: number | null
}

/**
 * 응답 저장. 생성 파이프라인과 무관한 경로라 Deps 밖에 둔다
 * (파이프라인은 학습지를 만들고, 이건 학습지를 푼 결과를 받는다).
 *
 * upsert 키는 (worksheet_id, response_id) — 같은 자리에 두 줄이 생기면
 * "마지막 응답"이 무엇인지 알 수 없게 된다. 행은 갱신되지만 attempts 는 클라이언트가
 * 이력 전체를 통째로 보내므로 첫 응답은 그대로 남는다.
 */
export function responsesRepo(admin: any) {
  return {
    async saveResponses(worksheetId: string, userId: string, rows: ResponseRow[]) {
      if (!rows || rows.length === 0) return
      const now = new Date().toISOString()
      const { error } = await admin.from('responses').upsert(
        rows.map((r) => ({
          worksheet_id: worksheetId,
          user_id: userId,
          response_id: r.id,
          quiz_item_id: r.questionId ?? null,
          kind: r.kind,
          first_choice: r.firstChoice ?? null,
          final_choice: r.finalChoice ?? null,
          correct: r.correct ?? null,
          attempts: r.attempts ?? [],
          text: r.text ?? null,
          chars: r.chars ?? 0,
          ink_strokes: r.inkStrokes ?? 0,
          ms_since_prompt: r.msSincePrompt ?? null,
          updated_at: now,
        })),
        { onConflict: 'worksheet_id,response_id' },
      )
      if (error) throw error
    },
  }
}

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
        // 문제와 "이게 막히면 먼저" 제안은 jsonb 에 묻지 않고 테이블로 꺼낸다.
        // 복습 스케줄이 quiz_items.id 를 참조해야 하기 때문이다.
        // 아직 살아 있는 생성에만 쓴다. 청소기가 먼저 닫은 건이면 여기서 0행이 나오고,
        // 그때는 아무것도 저장하지 않고 false 를 돌려준다(파이프라인이 결과를 버린다).
        const { data: ws, error: e0 } = await admin.from('worksheets')
          .update({
            status: 'ready',
            title: content.title,
            content,
            html_path: meta.htmlPath,
            plan_model: meta.planModel,
            draft_model: meta.draftModel,
            prompt_version: meta.promptVersion,
            quality_score: meta.qualityScore,
            revisions: meta.revisions,
            ready_at: new Date().toISOString(),
          })
          .eq('id', worksheetId)
          .in('status', ['queued', 'generating'])
          .select('user_id')
          .maybeSingle()
        if (e0) throw e0
        if (!ws) return false

        const userId = ws.user_id
        const { error: e1 } = await admin.from('quiz_items').insert(
          content.practice.quiz.map((q, i) => ({
            id: meta.quizItemIds[i],
            worksheet_id: worksheetId, user_id: userId, idx: i,
            kind: q.kind, question: q.question, choices: q.choices,
            answer: q.answer, explanation: q.explanation, difficulty: q.difficulty,
          })),
        )
        if (e1) throw e1

        // V5 에는 사전학습 섹션이 없다. 다음 단계 중 easier("이게 막히면 먼저")가 그 자리를 이어받는다.
        // 테이블은 그대로 두고 여기서 최대 3개만 뽑아 넣는다. one_liner 는 이제 설계가 내지 않는다.
        const easier = content.exit_ticket.next_steps
          .filter((n) => n.difficulty_delta === 'easier').slice(0, 3)
        if (easier.length) {
          const { error: e2 } = await admin.from('prerequisite_suggestions').insert(
            easier.map((p, i) => ({
              worksheet_id: worksheetId, user_id: userId, idx: i,
              title: p.title, why: p.why, one_liner: null,
            })),
          )
          if (e2) throw e2
        }
        return true
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

      async failGeneration(worksheetId, code: ErrorCode, detail: string) {
        // 닫기와 환불을 DB 함수 하나가 한다. 상태 전이에 성공한 쪽만 환불하므로
        // 청소기와 겹쳐도 장수가 두 번 돌아가지 않는다.
        const { data, error } = await admin.rpc('fail_generation', {
          p_worksheet: worksheetId, p_code: code,
        })
        if (error) throw error
        void detail   // 상세는 generation_jobs 에 남긴다 (사용자에게 노출하지 않는다)
        return data === true
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
