// 생성 파이프라인 테스트. 의존성을 전부 가짜로 넣어 실패 경로를 확인한다.
//   node --experimental-strip-types server/tests/pipeline.test.ts
//
// 가장 중요한 것: 쿼터를 깎았는데 생성이 실패하면 반드시 되돌려야 한다.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as pipe from '../supabase/functions/_shared/pipeline.ts'
import { LlmRefusalError, LlmOutputError } from '../supabase/functions/_shared/claude-parse.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const CONTENT = JSON.parse(readFileSync(resolve(HERE, 'fixtures/worksheet-event-sourcing.json'), 'utf8'))
const OUTLINE = {
  schema_version: 1, title: CONTENT.title, topic_normalized: CONTENT.topic_normalized,
  level: CONTENT.level, estimated_minutes: CONTENT.estimated_minutes,
  section_briefs: [], roleplay_mode: CONTENT.roleplay.mode,
  facts: CONTENT.origin_story.timeline.map((t: any) => ({ when: t.when, what: t.what, confidence: t.confidence })),
  quiz_plan: CONTENT.quiz.map((q: any) => ({ asks: q.question, answer_gist: q.answer, source_block: 0, difficulty: q.difficulty })),
  prerequisites: CONTENT.prerequisites, next_steps: CONTENT.next_steps,
}

let passed = 0
const failures: string[] = []
async function test(name: string, fn: () => Promise<void> | void) {
  try { await fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(name); console.log(`  FAIL ${name}\n    ${(e as Error).message}`) }
}

// ── 가짜 의존성 ──────────────────────────────────────────────────────────
function makeDeps(over: any = {}) {
  const log: any = {
    quotaConsumed: 0, quotaRefunded: 0, worksheets: [], contents: [],
    schedules: [], jobs: [], failures: [], uploads: [],
  }
  let idSeq = 0
  const usage = { inputTokens: 2600, outputTokens: 1000, cacheReadTokens: 0 }

  const deps: any = {
    llm: {
      plan: async () => over.planThrows ? Promise.reject(over.planThrows)
        : { json: over.outline ?? OUTLINE, model: 'claude-opus-5', usage, stopReason: 'end_turn' },
      draft: async () => over.draftThrows ? Promise.reject(over.draftThrows)
        : { json: over.content ?? CONTENT, model: 'claude-sonnet-5',
            usage: { inputTokens: 4400, outputTokens: 6000, cacheReadTokens: 0 }, stopReason: 'end_turn' },
    },
    db: {
      consumeQuota: async () => { if (over.noQuota) return false; log.quotaConsumed++; return true },
      refundQuota: async () => { log.quotaRefunded++ },
      createWorksheet: async (r: any) => {
        if (over.createThrows) throw over.createThrows
        log.worksheets.push(r)
      },
      saveContent: async (id: string, c: any, meta: any) => log.contents.push({ id, c, meta }),
      saveSchedules: async (id: string, u: string, seeds: any[]) => log.schedules.push({ id, seeds }),
      failWorksheet: async (id: string, code: string, detail: string) => log.failures.push({ id, code, detail }),
      recordJob: async (j: any) => log.jobs.push(j),
      recentCostsUsd: async () => over.recentCosts ?? [],
      userPrefs: async () => ({ timeZone: 'Asia/Seoul', reviewHour: 21 }),
    },
    storage: { putHtml: async (p: string, h: string) => log.uploads.push({ path: p, bytes: h.length }) },
    now: () => new Date('2026-09-06T05:00:00Z'),
    newId: () => `id${++idSeq}`,
  }
  return { deps, log }
}

const INPUT = { userId: 'u1', topic: '이벤트 소싱', level: 'beginner' as const }

console.log('\n▸ 접수 (쿼터)')

await test('쿼터가 있으면 학습지 행을 만들고 즉시 반환한다', async () => {
  const { deps, log } = makeDeps()
  const r = await pipe.acceptGeneration(deps, INPUT)
  assert.equal(r?.status, 'queued')
  assert.equal(log.quotaConsumed, 1)
  assert.equal(log.worksheets.length, 1)
})

await test('쿼터가 없으면 아무것도 만들지 않는다', async () => {
  const { deps, log } = makeDeps({ noQuota: true })
  assert.equal(await pipe.acceptGeneration(deps, INPUT), null)
  assert.equal(log.worksheets.length, 0, '쿼터 없이 학습지 행이 생겼다')
  assert.equal(log.quotaRefunded, 0)
})

await test('행 생성이 실패하면 차감한 쿼터를 되돌린다', async () => {
  const { deps, log } = makeDeps({ createThrows: new Error('db down') })
  await assert.rejects(() => pipe.acceptGeneration(deps, INPUT))
  assert.equal(log.quotaRefunded, 1, '쿼터를 깎고 아무것도 안 주면 사용자가 한 장을 잃는다')
})

console.log('\n▸ 생성 성공 경로')

await test('설계 → 집필 → 렌더 → 저장 → 복습 스케줄까지 이어진다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.equal(log.uploads.length, 1, 'HTML 이 업로드되지 않았다')
  assert.ok(log.uploads[0].path.startsWith('u1/'), `경로 규약 위반: ${log.uploads[0].path}`)
  assert.ok(log.uploads[0].bytes > 20000, '렌더 결과가 비정상적으로 작다')
  assert.equal(log.contents.length, 1)
  assert.equal(log.contents[0].meta.quizItemIds.length, 5)
  assert.equal(log.schedules[0].seeds.length, 5, '복습 5회차가 안 생겼다')
  assert.equal(log.quotaRefunded, 0, '성공했는데 환불했다')
})

await test('성공 잡에 단계별 사용량과 실비가 기록된다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'ws1')
  const job = log.jobs[0]
  assert.equal(job.status, 'succeeded')
  assert.equal(Number(job.costUsd.toFixed(4)), 0.1068, `실비 계산이 다르다: ${job.costUsd}`)
  assert.ok(job.planUsage && job.draftUsage, '단계별 사용량이 안 남았다')
})

await test('예산 경보를 넘으면 집필 분량을 줄인다', async () => {
  let captured: any
  const { deps } = makeDeps({ recentCosts: Array(30).fill(0.15) })
  deps.llm.draft = async (_o: unknown, opts: any) => {
    captured = opts
    return { json: CONTENT, model: 'claude-sonnet-5', usage: { inputTokens: 1, outputTokens: 1 }, stopReason: 'end_turn' }
  }
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.ok(captured.maxTokens < 6000, `다운시프트가 안 걸렸다: ${JSON.stringify(captured)}`)
})

console.log('\n▸ 실패 경로 (쿼터 환불이 핵심)')

const failCases: [string, any, string][] = [
  ['모델이 거절하면', { planThrows: new LlmRefusalError('cyber') }, 'llm_refused'],
  ['설계 응답이 깨졌으면', { planThrows: new LlmOutputError('JSON 파싱 실패') }, 'llm_upstream_error'],
  ['설계도에 quiz_plan 이 없으면', { outline: { title: 'x' } }, 'plan_schema_invalid'],
  ['집필이 스키마를 어기면', { content: { ...CONTENT, quiz: CONTENT.quiz.slice(0, 4) } }, 'draft_schema_invalid'],
]

for (const [label, over, expected] of failCases) {
  await test(`${label} ${expected} 로 실패하고 쿼터를 환불한다`, async () => {
    const { deps, log } = makeDeps(over)
    await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
    assert.equal(log.quotaRefunded, 1, '실패했는데 쿼터를 안 돌려줬다')
    assert.equal(log.failures[0]?.code, expected, `코드가 ${log.failures[0]?.code}`)
    assert.equal(log.jobs[0]?.status, 'failed')
    assert.equal(log.uploads.length, 0, '실패했는데 HTML 이 올라갔다')
    assert.equal(log.schedules.length, 0, '실패했는데 복습 스케줄이 생겼다')
  })
}

await test('집필이 설계의 사실성 판단을 뒤집으면 실패시킨다', async () => {
  const twisted = structuredClone(CONTENT)
  twisted.roleplay.mode = 'real_case'          // 설계는 hypothetical 이었다
  twisted.roleplay.disclaimer = null
  const { deps, log } = makeDeps({ content: twisted })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  // 검증기가 먼저 잡든(disclaimer) 정합성 검사가 잡든, 통과하지 않는 것이 핵심이다
  assert.ok(['draft_contradicts_plan', 'draft_schema_invalid'].includes(log.failures[0].code),
    `가상 시나리오가 사실로 둔갑했다: ${log.failures[0].code}`)
  assert.equal(log.quotaRefunded, 1)
})

await test('집필이 소외시키는 말투를 쓰면 draft_voice_violation 으로 잡는다', async () => {
  const rude = structuredClone(CONTENT)
  rude.what_we_learn.analogy = '이건 당연히 아는 내용이라 아주 간단합니다. 쉽죠?'
  const { deps, log } = makeDeps({ content: rude })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.equal(log.failures[0].code, 'draft_voice_violation',
    '어려운 학습지는 이 제품의 존재 이유와 어긋난다')
  assert.equal(log.quotaRefunded, 1)
  assert.equal(log.uploads.length, 0, '말투 위반 학습지가 업로드됐다')
})

await test('말투 위반은 재시도한다 (다시 쓰면 고쳐질 수 있다)', () => {
  assert.equal(pipe.isRetryable('draft_voice_violation'), true)
})

await test('집필이 문제 난이도를 바꾸면 draft_contradicts_plan 으로 잡는다', async () => {
  const twisted = structuredClone(CONTENT)
  twisted.quiz[0].difficulty = twisted.quiz[0].difficulty === 3 ? 1 : 3
  const { deps, log } = makeDeps({ content: twisted })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.equal(log.failures[0].code, 'draft_contradicts_plan')
})

await test('실패해도 이미 쓴 토큰의 실비는 기록한다', async () => {
  const { deps, log } = makeDeps({ draftThrows: new LlmOutputError('끊김') })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.ok(log.jobs[0].costUsd > 0, '실패해도 설계 단계 토큰은 과금된다 — 기록해야 예산이 맞는다')
})

console.log('\n▸ 재시도 정책')

await test('거절과 설계 위반은 다시 해도 같으므로 재시도하지 않는다', () => {
  assert.equal(pipe.isRetryable('llm_refused'), false)
  assert.equal(pipe.isRetryable('plan_schema_invalid'), false)
  assert.equal(pipe.isRetryable('render_failed'), false, '렌더 실패는 코드 버그다')
})

await test('일시적 실패는 재시도한다', () => {
  assert.equal(pipe.isRetryable('llm_upstream_error'), true)
  assert.equal(pipe.isRetryable('draft_schema_invalid'), true)
})

await test('백오프가 지수적으로 늘고 상한이 있다', () => {
  assert.equal(pipe.backoffMs(1), 1000)
  assert.equal(pipe.backoffMs(2), 2000)
  assert.ok(pipe.backoffMs(10) <= 8000, '상한 없이 늘면 잡이 영영 안 끝난다')
})

console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
