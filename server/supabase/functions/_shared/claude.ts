// Claude API 어댑터. 2단계 하이브리드: 설계 opus-5 → 집필 sonnet-5.
// docs/plan/04-worksheet-spec.md §4
//
// Deno 전용(npm: 지정자). 응답 해석 로직은 claude-parse.ts 에 있고 거기서 테스트한다.

import Anthropic from 'npm:@anthropic-ai/sdk@0.70.0'
import { extractResult, PLAN_MODEL_DEFAULT, DRAFT_MODEL_DEFAULT } from './claude-parse.ts'
import type { LlmClient } from './claude-parse.ts'

export interface ClaudeConfig {
  planModel?: string
  draftModel?: string
  planSystemPrompt: string
  draftSystemPrompt: string
  outlineSchema: unknown
  worksheetSchema: unknown
}

export function createLlmClient(cfg: ClaudeConfig): LlmClient {
  const client = new Anthropic()   // ANTHROPIC_API_KEY 는 Edge Function secret
  const planModel = cfg.planModel ?? PLAN_MODEL_DEFAULT
  const draftModel = cfg.draftModel ?? DRAFT_MODEL_DEFAULT

  async function call(model: string, system: string, schema: unknown, userText: string, maxTokens: number, effort: string) {
    // max_tokens 가 크면 논스트리밍은 HTTP 타임아웃 위험이 있어 스트리밍으로 받는다.
    const stream = client.messages.stream({
      model,
      max_tokens: maxTokens,
      thinking: { type: 'adaptive' },
      output_config: { effort, format: { type: 'json_schema', schema } },
      // 시스템 프롬프트는 매 요청 동일하므로 캐시한다.
      // 사용자 입력은 반드시 이 브레이크포인트 '뒤'(messages)에 둔다 — 앞에 두면 캐시가 매번 깨진다.
      system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
      messages: [{ role: 'user', content: userText }],
    } as any)
    return extractResult(await stream.finalMessage(), model)
  }

  return {
    plan: (topic, level, opts) => call(
      planModel, cfg.planSystemPrompt, cfg.outlineSchema,
      `주제: ${topic}\n난이도: ${level}`,
      opts.maxTokens, opts.effort,
    ),
    draft: (outline, opts) => call(
      draftModel, cfg.draftSystemPrompt, cfg.worksheetSchema,
      `아래 설계도를 그대로 따라 학습지를 작성하세요. ` +
      `사실성 판단(confidence, mode)과 문제 구성은 설계도의 것을 옮기기만 하고 바꾸지 마세요.\n` +
      `분량 배율: ${opts.lengthScale}\n\n${JSON.stringify(outline)}`,
      opts.maxTokens, opts.effort,
    ),
  }
}
