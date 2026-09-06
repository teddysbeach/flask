// 생성 비용 계산과 예산 가드. docs/plan/04-worksheet-spec.md §4
//
// 장당 150원 목표는 환율에 종속되므로 실제 관리는 달러로 한다.

export const MODEL_PRICING: Record<string, { inPerM: number; outPerM: number }> = {
  'claude-opus-5':   { inPerM: 5, outPerM: 25 },
  'claude-sonnet-5': { inPerM: 2, outPerM: 10 },
  'claude-haiku-4-5': { inPerM: 1, outPerM: 5 },
}

/** 목표 $0.105/장, 경보 $0.12/장. 150원 = $0.107 @1,400원/USD 기준으로 잡았다. */
export const BUDGET = { targetUsd: 0.105, alertUsd: 0.12 }

/** 표시용 환산에만 쓴다. 예산 판단은 달러로 한다. */
export const KRW_PER_USD = 1400

export interface Usage {
  inputTokens: number
  outputTokens: number
  cacheReadTokens?: number
}

/**
 * 한 번의 호출 비용(USD).
 *
 * 캐시 읽기 토큰은 실제로는 입력가보다 싸지만, 정확한 배율을 모델별로 확정해 두지 않았으므로
 * 여기서는 입력가로 계산한다. 즉 이 값은 항상 실제보다 크거나 같은 '상한'이다.
 * 예산 가드가 보수적으로 동작하는 쪽이 안전하다.
 */
export function callCostUsd(model: string, usage: Usage): number {
  const p = MODEL_PRICING[model]
  if (!p) throw new Error(`가격표에 없는 모델: ${model}`)
  const input = usage.inputTokens + (usage.cacheReadTokens ?? 0)
  return (input / 1e6) * p.inPerM + (usage.outputTokens / 1e6) * p.outPerM
}

export interface StageUsage { model: string; usage: Usage }

/** 학습지 한 장의 총 비용(설계 + 집필). */
export function worksheetCostUsd(stages: StageUsage[]): number {
  return stages.reduce((sum, s) => sum + callCostUsd(s.model, s.usage), 0)
}

export const usdToKrw = (usd: number, rate = KRW_PER_USD) => Math.round(usd * rate)

// ── 예산 가드 ────────────────────────────────────────────────────────────

export type Downshift = 'none' | 'trim' | 'low_effort'

/**
 * 최근 생성들의 실비 이동평균을 보고 다음 생성의 강도를 정한다.
 *
 *   none       예산 안. 그대로.
 *   trim       경보 초과. 집필 분량을 줄인다.
 *   low_effort 경보를 크게 초과. effort 를 내린다. 마지막 수단.
 *
 * 표본이 적을 때 한두 건의 튐으로 품질을 깎지 않도록 최소 표본 수를 둔다.
 */
export function decideDownshift(recentCostsUsd: number[], minSamples = 20): Downshift {
  if (recentCostsUsd.length < minSamples) return 'none'
  const avg = recentCostsUsd.reduce((a, b) => a + b, 0) / recentCostsUsd.length
  if (avg > BUDGET.alertUsd * 1.25) return 'low_effort'
  if (avg > BUDGET.alertUsd) return 'trim'
  return 'none'
}

/** 다운시프트에 따른 집필 단계 파라미터. */
export function draftParams(downshift: Downshift) {
  switch (downshift) {
    case 'low_effort': return { maxTokens: 5000, effort: 'low' as const,    lengthScale: 0.7 }
    case 'trim':       return { maxTokens: 5200, effort: 'medium' as const, lengthScale: 0.85 }
    default:           return { maxTokens: 6000, effort: 'medium' as const, lengthScale: 1 }
  }
}

/** 일일 총지출 상한 초과 여부. 넘으면 생성을 소프트 차단한다. */
export function isDailyBudgetExceeded(spentTodayUsd: number, dailyCapUsd: number): boolean {
  return spentTodayUsd >= dailyCapUsd
}
