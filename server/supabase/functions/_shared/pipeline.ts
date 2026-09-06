// 학습지 생성 파이프라인. docs/plan/01-architecture.md §3
//
// 의존성(DB·저장소·LLM·시계·id)을 전부 주입받는다. 그래야 Supabase 없이 테스트할 수 있고,
// 실패 경로 — 특히 "쿼터를 깎았는데 생성이 실패했을 때 되돌리는가" — 를 확인할 수 있다.
// 이게 틀리면 사용자가 돈만 내고 학습지를 못 받는다.

import { validateWorksheet, ValidationError } from './validate.ts'
import { crossCheck } from './cross-check.ts'
import { renderWorksheet } from './render.ts'
import { worksheetCostUsd, draftParams, decideDownshift } from './cost.ts'
import { LlmRefusalError, LlmOutputError } from './claude-parse.ts'
import type { LlmClient, LlmResult } from './claude-parse.ts'
import { createInitialSchedules } from './review-schedule.ts'
import type { WorksheetContent, WorksheetOutline } from './worksheet-types.ts'

export type ErrorCode =
  | 'plan_schema_invalid' | 'draft_schema_invalid' | 'draft_contradicts_plan'
  | 'llm_refused' | 'llm_upstream_error' | 'render_failed'

export class PipelineError extends Error {
  code: ErrorCode
  detail: string
  constructor(code: ErrorCode, detail: string) {
    super(`${code}: ${detail}`)
    this.name = 'PipelineError'
    this.code = code
    this.detail = detail
  }
}

export interface Deps {
  llm: LlmClient
  db: {
    consumeQuota(userId: string): Promise<boolean>
    refundQuota(userId: string): Promise<void>
    createWorksheet(row: { id: string; userId: string; topic: string; level: string }): Promise<void>
    saveContent(worksheetId: string, content: WorksheetContent, meta: {
      quizItemIds: string[]; htmlPath: string; planModel: string; draftModel: string
    }): Promise<void>
    saveSchedules(worksheetId: string, userId: string, seeds: unknown[]): Promise<void>
    failWorksheet(worksheetId: string, code: ErrorCode, detail: string): Promise<void>
    recordJob(job: {
      worksheetId: string; userId: string; attempt: number; stage: string
      status: 'succeeded' | 'failed'; costUsd: number
      planUsage?: unknown; draftUsage?: unknown; errorCode?: ErrorCode
    }): Promise<void>
    recentCostsUsd(limit: number): Promise<number[]>
    userPrefs(userId: string): Promise<{ timeZone: string; reviewHour: number }>
  }
  storage: { putHtml(path: string, html: string): Promise<void> }
  now(): Date
  newId(): string
}

export interface GenerateInput {
  userId: string
  topic: string
  level: 'beginner' | 'intermediate' | 'advanced'
}

export interface GenerateAccepted {
  worksheetId: string
  status: 'queued'
}

/**
 * 1단계: 쿼터를 차감하고 잡을 등록한다. 즉시 반환한다.
 * 쿼터가 없으면 아무것도 만들지 않고 null 을 돌려준다(HTTP 402).
 */
export async function acceptGeneration(deps: Deps, input: GenerateInput): Promise<GenerateAccepted | null> {
  const ok = await deps.db.consumeQuota(input.userId)
  if (!ok) return null

  const worksheetId = deps.newId()
  try {
    await deps.db.createWorksheet({
      id: worksheetId, userId: input.userId, topic: input.topic, level: input.level,
    })
  } catch (e) {
    // 행을 못 만들었으면 차감한 쿼터를 반드시 되돌린다. 안 그러면 아무것도 못 받고 한 장을 잃는다.
    await deps.db.refundQuota(input.userId)
    throw e
  }
  return { worksheetId, status: 'queued' }
}

/**
 * 2단계: 실제 생성. 응답을 보낸 뒤 백그라운드에서 돈다.
 * 실패하면 쿼터를 환불하고 학습지를 failed 로 표시한다.
 */
export async function runGeneration(
  deps: Deps, input: GenerateInput, worksheetId: string, attempt = 1,
): Promise<void> {
  const started = deps.now()
  let planResult: LlmResult | undefined
  let draftResult: LlmResult | undefined
  let stage = 'plan'

  try {
    const downshift = decideDownshift(await deps.db.recentCostsUsd(100))
    const dp = draftParams(downshift)

    // ① 설계 — 판단은 여기서 끝난다
    planResult = await deps.llm.plan(input.topic, input.level, { maxTokens: 1000, effort: 'medium' })
    const outline = planResult.json as WorksheetOutline
    if (!outline || typeof outline !== 'object' || !Array.isArray(outline.quiz_plan)) {
      throw new PipelineError('plan_schema_invalid', '설계도에 quiz_plan 이 없습니다')
    }

    // ② 집필 — 설계도를 문장으로 옮기기만 한다
    stage = 'draft'
    draftResult = await deps.llm.draft(outline, {
      maxTokens: dp.maxTokens, effort: dp.effort, lengthScale: dp.lengthScale,
    })

    let content: WorksheetContent
    try {
      content = validateWorksheet(draftResult.json)
    } catch (e) {
      throw new PipelineError('draft_schema_invalid',
        e instanceof ValidationError ? e.issues.slice(0, 10).join('; ') : String(e))
    }

    // ③ 집필이 설계의 판단을 뒤집지 않았는지 확인 — 2단계 구조의 안전장치
    const check = crossCheck(outline, content)
    if (!check.ok) {
      throw new PipelineError('draft_contradicts_plan', check.violations.slice(0, 10).join('; '))
    }

    // ④ 렌더 — 결정론적 순수 함수
    stage = 'render'
    const quizItemIds = content.quiz.map(() => deps.newId())
    const htmlPath = `${input.userId}/${worksheetId}.html`
    let html: string
    try {
      html = renderWorksheet(content, { worksheetId, quizItemIds, theme: 'light' })
    } catch (e) {
      throw new PipelineError('render_failed', String(e))
    }
    await deps.storage.putHtml(htmlPath, html)

    await deps.db.saveContent(worksheetId, content, {
      quizItemIds, htmlPath,
      planModel: planResult.model, draftModel: draftResult.model,
    })

    // ⑤ 복습 스케줄 5회차
    const prefs = await deps.db.userPrefs(input.userId)
    await deps.db.saveSchedules(worksheetId, input.userId,
      createInitialSchedules(quizItemIds, deps.now(), prefs.timeZone, prefs.reviewHour))

    await deps.db.recordJob({
      worksheetId, userId: input.userId, attempt, stage: 'done', status: 'succeeded',
      costUsd: totalCost(planResult, draftResult),
      planUsage: planResult.usage, draftUsage: draftResult.usage,
    })
  } catch (e) {
    const code = toErrorCode(e)
    // 실패했으면 차감한 쿼터를 되돌린다. 사용자 잘못이 아니다.
    await deps.db.refundQuota(input.userId)
    await deps.db.failWorksheet(worksheetId, code, describe(e))
    await deps.db.recordJob({
      worksheetId, userId: input.userId, attempt, stage, status: 'failed',
      costUsd: totalCost(planResult, draftResult),   // 실패해도 쓴 토큰은 과금된다
      planUsage: planResult?.usage, draftUsage: draftResult?.usage,
      errorCode: code,
    })
    throw e
  } finally {
    void started
  }
}

function totalCost(plan?: LlmResult, draft?: LlmResult): number {
  const stages = []
  if (plan) stages.push({ model: plan.model, usage: plan.usage })
  if (draft) stages.push({ model: draft.model, usage: draft.usage })
  return stages.length ? worksheetCostUsd(stages) : 0
}

export function toErrorCode(e: unknown): ErrorCode {
  if (e instanceof PipelineError) return e.code
  if (e instanceof LlmRefusalError) return 'llm_refused'
  if (e instanceof LlmOutputError) return 'llm_upstream_error'
  return 'llm_upstream_error'
}

const describe = (e: unknown) =>
  e instanceof PipelineError ? e.detail : e instanceof Error ? e.message : String(e)

/** 재시도할 가치가 있는 실패인가. 거절이나 설계 위반은 다시 해도 같다. */
export function isRetryable(code: ErrorCode): boolean {
  return code === 'llm_upstream_error' || code === 'draft_schema_invalid' || code === 'draft_contradicts_plan'
}

export const MAX_ATTEMPTS = 3
export const backoffMs = (attempt: number) => Math.min(1000 * 2 ** (attempt - 1), 8000)
