// 학습지 생성 파이프라인. docs/plan/01-architecture.md §3
//
// 의존성(DB·저장소·LLM·시계·id)을 전부 주입받는다. 그래야 Supabase 없이 테스트할 수 있고,
// 실패 경로 — 특히 "쿼터를 깎았는데 생성이 실패했을 때 되돌리는가" — 를 확인할 수 있다.
// 이게 틀리면 사용자가 돈만 내고 학습지를 못 받는다.

import { validateWorksheet, ValidationError } from './validate.ts'
import { crossCheck } from './cross-check.ts'
import { voiceLint } from './voice-lint.ts'
import { pedagogyLint } from './pedagogy-lint.ts'
import { normalizeVerdict, revisionInstructions, MAX_REVISIONS } from './critic.ts'
import type { CriticVerdict } from './critic.ts'
import { renderWorksheet } from './render.ts'
import { worksheetCostUsd, draftParams, decideDownshift, MAX_WORKSHEET_COST_USD } from './cost.ts'
import { LlmRefusalError, LlmOutputError } from './claude-parse.ts'
import type { LlmClient, LlmResult } from './claude-parse.ts'
import { createInitialSchedules } from './review-schedule.ts'
import type { WorksheetContent, WorksheetOutline } from './worksheet-types.ts'

export type ErrorCode =
  | 'plan_schema_invalid' | 'draft_schema_invalid' | 'draft_contradicts_plan'
  | 'draft_voice_violation' | 'draft_quality_rejected'
  | 'llm_refused' | 'llm_upstream_error' | 'render_failed'
  /** 한 장에 쓸 수 있는 돈을 넘겼다. 재작성이 길어지면 원가가 가격을 넘는다. */
  | 'cost_cap_exceeded'
  /** 청소기가 먼저 이 생성을 실패로 닫고 환불했다. 뒤늦게 끝난 결과는 버린다. */
  | 'generation_superseded'

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
    /**
     * 완성본을 저장한다. **아직 살아 있는 생성에만** 쓴다 —
     * 청소기가 이미 실패로 닫고 환불한 건이면 false 를 돌려주고 아무것도 쓰지 않는다.
     * 안 그러면 환불은 환불대로 되고 학습지는 학습지대로 나가서 공짜 한 장이 된다.
     */
    saveContent(worksheetId: string, content: WorksheetContent, meta: {
      quizItemIds: string[]; htmlPath: string; planModel: string; draftModel: string
      /** 이 학습지를 만든 프롬프트·스키마의 지문. 품질 회귀를 프롬프트와 잇는 유일한 끈이다. */
      promptVersion: string
      qualityScore: number; revisions: number
      /**
       * 출고 블로커. 모델이 다시 써도 못 고치는 것(등록된 사진 자산이 없다 등)이라
       * 생성은 성공시키되 "이대로 내보낼 수는 없다" 는 사실만 함께 넘긴다.
       */
      releaseBlocked?: string[]
    }): Promise<boolean>
    saveSchedules(worksheetId: string, userId: string, seeds: unknown[]): Promise<void>
    /**
     * 생성을 실패로 닫고 **차감한 장수를 되돌린다. 정확히 한 번.**
     *
     * 닫기와 환불이 한 함수인 이유가 있다. 둘을 따로 부르면 청소기
     * (reap_stale_generations)와 이 파이프라인이 같은 건을 각자 환불해서 공짜 장수가 생긴다.
     * 상태 전이에 성공한 쪽만 환불하도록 DB 함수 하나가 자물쇠를 쥔다.
     *
     * @returns 이번 호출이 실제로 닫고 환불했는가. false 면 남이 이미 닫은 건이다.
     */
    failGeneration(worksheetId: string, code: ErrorCode, detail: string): Promise<boolean>
    recordJob(job: {
      worksheetId: string; userId: string; attempt: number; stage: string
      status: 'succeeded' | 'failed'; costUsd: number
      planUsage?: unknown; draftUsage?: unknown; criticUsage?: unknown; errorCode?: ErrorCode
      qualityScore?: number; revisions?: number
      /** 재작성으로 풀 수 없는 출고 블로커. 잡 기록에 남겨 두면 자산이 들어왔을 때 되짚을 수 있다. */
      releaseBlocked?: string[]
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

/**
 * 한 장에 남은 돈. 재시도를 건너 이어진다 —
 * 시도마다 상한을 새로 주면 한 장에 상한 × 시도횟수만큼 쓸 수 있게 된다.
 */
export interface CostBudget {
  remainingUsd: number
}

export const newCostBudget = (): CostBudget => ({ remainingUsd: MAX_WORKSHEET_COST_USD })

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
  budget: CostBudget = newCostBudget(),
): Promise<void> {
  const started = deps.now()
  let planResult: LlmResult | undefined
  let draftResult: LlmResult | undefined
  let criticResult: LlmResult | undefined
  let stage = 'plan'

  // 이번 시도에 쓴 호출들. 기록(generation_jobs)에 남길 실비를 세는 데 쓴다.
  //
  // 예전에는 마지막 집필·검사관 호출만 세서, 두 번 다시 쓴 학습지의 기록된 비용이
  // 실제보다 훨씬 작았다. 원가를 보고 가격을 정하는 제품에서 이건 눈을 가린 것과 같다.
  const spent: { model: string; usage: LlmResult['usage'] }[] = []

  /**
   * 호출 하나의 값을 치른다. 예산이 바닥나면 그 자리에서 생성을 끊는다.
   *
   * 넘겨서 얻는 것이 없기 때문이다 — 실패하면 어차피 환불이라 매출은 0이고 비용만 남는다.
   * 재시도도 하지 않는다(isRetryable 에서 뺐다). 같은 주제로 또 넘길 뿐이다.
   */
  const charge = (r: LlmResult) => {
    spent.push({ model: r.model, usage: r.usage })
    budget.remainingUsd -= worksheetCostUsd([{ model: r.model, usage: r.usage }])
    if (budget.remainingUsd < 0) {
      throw new PipelineError('cost_cap_exceeded',
        `한 장 예산을 넘겼습니다 (남은 돈 $${budget.remainingUsd.toFixed(3)}, 이번 시도 호출 ${spent.length}회)`)
    }
    return r
  }

  try {
    const downshift = decideDownshift(await deps.db.recentCostsUsd(100))
    const dp = draftParams(downshift)

    // ① 설계 — 판단은 여기서 끝난다
    planResult = charge(await deps.llm.plan(input.topic, input.level, { maxTokens: 1000, effort: 'medium' }))
    const outline = planResult.json as WorksheetOutline
    if (!outline || typeof outline !== 'object' || !Array.isArray(outline.quiz_plan)) {
      throw new PipelineError('plan_schema_invalid', '설계도에 quiz_plan 이 없습니다')
    }
    // 흔한 오답은 예측의 진단 가치다. 설계가 안 냈으면 집필이 지어내게 되므로 여기서 막는다.
    if (!outline.prediction || typeof outline.prediction.common_wrong !== 'string' || !Array.isArray(outline.next_steps)) {
      throw new PipelineError('plan_schema_invalid', '설계도에 prediction.common_wrong 이나 next_steps 가 없습니다')
    }

    // ② 집필 — 설계도를 문장으로 옮기기만 한다
    stage = 'draft'
    draftResult = charge(await deps.llm.draft(outline, {
      maxTokens: dp.maxTokens, effort: dp.effort, lengthScale: dp.lengthScale,
    }))

    // ③ 검사 루프 — 정적 린트 → 검사관 → 반려면 재작성. 최대 MAX_REVISIONS 회.
    //    외부 평가에서 "예뻐서 좋은 학습지처럼 느껴진다" 는 말을 들었다. 이 루프가 그걸 막는다.
    let content: WorksheetContent | undefined
    let verdict: CriticVerdict | undefined
    let revisions = 0
    // 출고 블로커는 재작성 사유가 아니다. 다시 쓰라고 해도 모델이 사진 자산을 만들어 낼 수 없어서
    // staticIssues 에 넣으면 두 번 다시 쓰고 환불하며 실패한다. 기록만 하고 파이프라인은 통과시킨다.
    let releaseBlocked: string[] = []

    for (let round = 0; ; round++) {
      // 스키마 — 깨졌으면 검사관까지 갈 것도 없이 지적만 붙여 다시 쓴다
      let candidate: WorksheetContent
      try {
        candidate = validateWorksheet(draftResult.json)
      } catch (e) {
        const issues = (e instanceof ValidationError ? e.issues.slice(0, 12) : [String(e)]).map((i) => `[스키마] ${i}`)
        if (round >= MAX_REVISIONS) throw new PipelineError('draft_schema_invalid', issues.join('; '))
        revisions++
        stage = 'revise'
        draftResult = charge(await deps.llm.revise(outline, draftResult.json, revisionInstructions(issues, emptyVerdict()), { maxTokens: dp.maxTokens, effort: dp.effort }))
        continue
      }

      // 정적 검사 세 겹: 설계 정합성 · 말투 · 학습설계
      const check = crossCheck(outline, candidate)
      const voice = voiceLint(candidate)
      const ped = pedagogyLint(candidate)
      releaseBlocked = ped.releaseBlockers.map((b) => `${b.path}: [${b.rule}] ${b.detail}`)
      const staticIssues = [
        ...check.violations.map((v) => `[설계 위반] ${v}`),
        ...voice.errors.map((e) => `[말투] ${e.path}: ${e.detail}`),
        ...ped.errors.map((e) => `[학습설계] ${e.path}: ${e.detail}`),
      ]

      // 검사관 — 정적 검사 위에서 의미적 판단 (오개념, 전이 거리, 단순화의 정확성)
      stage = 'critic'
      criticResult = charge(await deps.llm.critique(candidate, staticIssues, { maxTokens: 1500 }))
      verdict = normalizeVerdict(criticResult.json)

      if (staticIssues.length === 0 && verdict.verdict === 'pass') {
        content = candidate
        break
      }

      if (round >= MAX_REVISIONS) {
        const why = [...staticIssues.slice(0, 6), ...verdict.must_fix.slice(0, 6).map((m) => `[검사관] ${m.path}: ${m.issue}`)]
        throw new PipelineError('draft_quality_rejected',
          `${MAX_REVISIONS}회 재작성 후에도 반려 (점수 ${verdict.score}): ` + why.join('; '))
      }

      revisions++
      stage = 'revise'
      draftResult = charge(await deps.llm.revise(outline, candidate, revisionInstructions(staticIssues, verdict), { maxTokens: dp.maxTokens, effort: dp.effort }))
    }
    if (!content || !verdict) throw new PipelineError('draft_quality_rejected', '검사 루프가 결과 없이 끝났습니다')

    // ④ 렌더 — 결정론적 순수 함수
    stage = 'render'
    const quizItemIds = content.practice.quiz.map(() => deps.newId())
    const htmlPath = `${input.userId}/${worksheetId}.html`
    let html: string
    try {
      html = renderWorksheet(content, { worksheetId, quizItemIds, theme: 'light' })
    } catch (e) {
      throw new PipelineError('render_failed', String(e))
    }
    await deps.storage.putHtml(htmlPath, html)

    const saved = await deps.db.saveContent(worksheetId, content, {
      quizItemIds, htmlPath,
      planModel: planResult.model, draftModel: draftResult.model,
      promptVersion: deps.llm.version,
      qualityScore: verdict.score, revisions,
      ...(releaseBlocked.length ? { releaseBlocked } : {}),
    })
    // 우리가 도는 사이에 청소기가 이 건을 실패로 닫고 장수를 되돌려 준 경우다.
    // 다 만들어 놓고 버리는 게 아깝지만, 환불했다고 말해 놓고 학습지를 주면
    // 그 한 장은 공짜가 된다. 환불이 이긴다.
    if (!saved) {
      throw new PipelineError('generation_superseded',
        '청소기가 먼저 이 생성을 닫고 환불했습니다. 늦게 끝난 결과는 버립니다')
    }

    // ⑤ 복습 스케줄 5회차
    const prefs = await deps.db.userPrefs(input.userId)
    await deps.db.saveSchedules(worksheetId, input.userId,
      createInitialSchedules(quizItemIds, deps.now(), prefs.timeZone, prefs.reviewHour))

    await deps.db.recordJob({
      worksheetId, userId: input.userId, attempt, stage: 'done', status: 'succeeded',
      costUsd: worksheetCostUsd(spent),   // 재작성까지 전부 더한 실비
      planUsage: planResult.usage, draftUsage: draftResult.usage, criticUsage: criticResult?.usage,
      qualityScore: verdict.score, revisions,
      ...(releaseBlocked.length ? { releaseBlocked } : {}),
    })
  } catch (e) {
    const code = toErrorCode(e)
    // 실패했으면 차감한 쿼터를 되돌린다. 사용자 잘못이 아니다.
    // 닫기와 환불이 한 호출인 이유는 Deps.failGeneration 주석에 있다 — 두 번 환불하지 않기 위해서다.
    await deps.db.failGeneration(worksheetId, code, describe(e))
    await deps.db.recordJob({
      worksheetId, userId: input.userId, attempt, stage, status: 'failed',
      costUsd: worksheetCostUsd(spent),   // 실패해도 쓴 토큰은 과금된다
      planUsage: planResult?.usage, draftUsage: draftResult?.usage, criticUsage: criticResult?.usage,
      errorCode: code,
    })
    throw e
  } finally {
    void started
  }
}

const emptyVerdict = (): CriticVerdict => ({
  score: 0, verdict: 'revise', must_fix: [], should_fix: [], strengths: [], rubric: {} as any,
})

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
  // cost_cap_exceeded 는 뺀다. 다시 해도 같은 주제로 또 넘길 뿐이고, 그동안 돈만 두 배로 쓴다.
  // generation_superseded 도 뺀다. 이미 환불된 건이라 다시 만들 이유가 없다.
  return code === 'llm_upstream_error' || code === 'draft_schema_invalid'
    || code === 'draft_contradicts_plan' || code === 'draft_voice_violation'
}

export const MAX_ATTEMPTS = 3
export const backoffMs = (attempt: number) => Math.min(1000 * 2 ** (attempt - 1), 8000)
