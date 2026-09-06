// Claude 응답 해석과 타입. SDK 를 import 하지 않는다.
//
// SDK 는 Deno 의 npm: 지정자로 가져오는데 Node 는 그걸 못 읽는다.
// 응답 해석이야말로 반드시 테스트해야 하는 부분(거절·잘림·파싱 실패)이라
// 순수한 이쪽만 떼어 두고 실제 호출은 claude.ts 가 맡는다.

import type { Usage } from './cost.ts'

export const PLAN_MODEL_DEFAULT = 'claude-opus-5'
export const DRAFT_MODEL_DEFAULT = 'claude-sonnet-5'
export const CRITIC_MODEL_DEFAULT = 'claude-opus-5'

/** 호출 결과. 파이프라인은 이 모양만 알면 되므로 테스트에서 쉽게 대체할 수 있다. */
export interface LlmResult {
  json: unknown
  model: string
  usage: Usage
  stopReason: string | null
}

export interface LlmClient {
  plan(topic: string, level: string, opts: { maxTokens: number; effort: string }): Promise<LlmResult>
  draft(outline: unknown, opts: { maxTokens: number; effort: string; lengthScale: number }): Promise<LlmResult>
  /** 검사관. 학습지를 교수설계 기준으로 채점한다. */
  critique(content: unknown, staticIssues: string[], opts: { maxTokens: number }): Promise<LlmResult>
  /** 반려된 초안을 지적 사항과 함께 다시 쓴다. */
  revise(outline: unknown, previous: unknown, instructions: string, opts: { maxTokens: number; effort: string }): Promise<LlmResult>
}

export class LlmRefusalError extends Error {
  category: string | null
  constructor(category: string | null) {
    super(`모델이 요청을 거절했습니다 (${category ?? 'unknown'})`)
    this.name = 'LlmRefusalError'
    this.category = category
  }
}

export class LlmOutputError extends Error {
  constructor(message: string) { super(message); this.name = 'LlmOutputError' }
}

/** SDK 응답에서 우리가 쓰는 것만 뽑는다. 여기가 순수 함수라 테스트할 수 있다. */
export function extractResult(message: any, model: string): LlmResult {
  // 안전 정책상 거절은 예외가 아니라 200 + stop_reason 으로 온다. content 를 읽기 전에 확인한다.
  if (message?.stop_reason === 'refusal') {
    throw new LlmRefusalError(message?.stop_details?.category ?? null)
  }
  if (message?.stop_reason === 'max_tokens') {
    throw new LlmOutputError('출력이 max_tokens 에서 잘렸습니다 — JSON 이 불완전합니다')
  }

  const text = (message?.content ?? [])
    .filter((b: any) => b?.type === 'text')
    .map((b: any) => b.text)
    .join('')

  if (!text.trim()) throw new LlmOutputError('응답에 텍스트 블록이 없습니다')

  let json: unknown
  try {
    json = JSON.parse(text)
  } catch (e) {
    throw new LlmOutputError(`JSON 파싱 실패: ${(e as Error).message}`)
  }

  const u = message?.usage ?? {}
  return {
    json,
    model,
    usage: {
      inputTokens: u.input_tokens ?? 0,
      outputTokens: u.output_tokens ?? 0,
      cacheReadTokens: u.cache_read_input_tokens ?? 0,
    },
    stopReason: message?.stop_reason ?? null,
  }
}

