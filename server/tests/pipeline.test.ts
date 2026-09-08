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
  schema_version: 2, title: CONTENT.title, topic_normalized: CONTENT.topic_normalized,
  level: CONTENT.level, category: CONTENT.category,
  problem_gist: CONTENT.problem.question,
  prediction: { question: CONTENT.predict.hook.prompt, options: CONTENT.predict.hook.options,
                common_wrong: CONTENT.predict.hook.options[CONTENT.predict.hook.options.length - 1] },
  observation_gist: '관찰 요지',
  concept_blocks: CONTENT.concept.blocks.map((b: any) => ({ heading: b.heading, gist: b.heading, activity_kind: b.activity?.kind ?? null })),
  facts: (CONTENT.concept.context_note?.facts ?? []).map((t: any) => ({ when: t.when, what: t.what, confidence: t.confidence })),
  quiz_plan: CONTENT.practice.quiz.map((q: any) => ({ asks: q.question, answer_gist: q.answer, source_block: 0, difficulty: q.difficulty, transfer: q.transfer, evidence: q.evidence })),
  next_steps: CONTENT.exit_ticket.next_steps,
  guards: CONTENT.robustness.guards,
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
    schedules: [], jobs: [], failures: [], uploads: [], critiques: 0, revisions: 0, lastInstructions: '',
    stages: [] as string[],
  }
  let idSeq = 0
  const usage = { inputTokens: 2600, outputTokens: 1000, cacheReadTokens: 0 }

  const deps: any = {
    llm: {
      version: 'testfp01',
      plan: async () => over.planThrows ? Promise.reject(over.planThrows)
        : { json: over.outline ?? OUTLINE, model: 'claude-opus-5', usage, stopReason: 'end_turn' },
      draft: async () => over.draftThrows ? Promise.reject(over.draftThrows)
        : { json: over.content ?? CONTENT, model: 'claude-sonnet-5',
            usage: { inputTokens: 4400, outputTokens: 6000, cacheReadTokens: 0 }, stopReason: 'end_turn' },
      // 검사관: 기본은 통과. over.verdicts 로 회차별 판정을 지정한다.
      critique: async () => {
        log.critiques++
        const v = Array.isArray(over.verdicts) ? (over.verdicts[log.critiques - 1] ?? over.verdicts[over.verdicts.length - 1]) : { score: 88, must_fix: [] }
        return { json: { verdict: v.must_fix?.length ? 'revise' : 'pass', should_fix: [], strengths: [], rubric: {}, ...v },
                 model: 'claude-opus-5', usage: { inputTokens: 9000, outputTokens: 800, cacheReadTokens: 0 }, stopReason: 'end_turn' }
      },
      // 재작성: over.revised 가 있으면 그것을, 없으면 원본을 다시 낸다
      revise: async (_o: unknown, _prev: unknown, instructions: string) => {
        log.revisions++; log.lastInstructions = instructions
        return { json: over.revised ?? over.content ?? CONTENT, model: 'claude-sonnet-5',
                 usage: { inputTokens: 9000, outputTokens: 6000, cacheReadTokens: 0 }, stopReason: 'end_turn' }
      },
    },
    db: {
      consumeQuota: async () => { if (over.noQuota) return false; log.quotaConsumed++; return true },
      refundQuota: async () => { log.quotaRefunded++ },
      createWorksheet: async (r: any) => {
        if (over.createThrows) throw over.createThrows
        log.worksheets.push(r)
      },
      saveContent: async (id: string, c: any, meta: any) => {
        // 청소기가 먼저 닫은 상황을 흉내 낸다(over.reaped). 그때 DB 는 아무것도 쓰지 않고 false 를 준다.
        if (over.reaped) return false
        log.contents.push({ id, c, meta })
        return true
      },
      saveSchedules: async (id: string, u: string, seeds: any[]) => log.schedules.push({ id, seeds }),
      // 닫기와 환불이 한 번에 일어난다. 이미 닫힌 건이면 false 를 주고 환불하지 않는다.
      failGeneration: async (id: string, code: string, detail: string) => {
        log.failures.push({ id, code, detail })
        if (over.alreadyClosed) return false
        log.quotaRefunded++
        return true
      },
      setStage: async (_id: string, stage: string) => {
        if (over.setStageThrows) throw over.setStageThrows
        log.stages.push(stage)
      },
      recordJob: async (j: any) => log.jobs.push(j),
      recentCostsUsd: async () => over.recentCosts ?? [],
      userPrefs: async () => ({ timeZone: 'Asia/Seoul', reviewHour: 21 }),
    },
    storage: { putHtml: async (p: string, h: string) => log.uploads.push({ path: p, bytes: h.length }) },
    // 기본은 멈춘 시계다. over.clock 을 주면 부를 때마다 그만큼 흐른다 —
    // 벽시계 예산을 재는 테스트가 진짜로 8분을 기다릴 수는 없다.
    now: over.clock ?? (() => new Date('2026-09-06T05:00:00Z')),
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
  assert.equal(log.contents[0].meta.quizItemIds.length, CONTENT.practice.quiz.length)
  assert.equal(log.schedules[0].seeds.length, CONTENT.practice.quiz.length, '문항 수만큼 복습이 안 생겼다')
  assert.equal(log.quotaRefunded, 0, '성공했는데 환불했다')
})

await test('성공 잡에 단계별 사용량과 실비가 기록된다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'ws1')
  const job = log.jobs[0]
  assert.equal(job.status, 'succeeded')
  // 설계 0.0380 + 집필 0.0688 + 검사관(opus 9000in/800out) 0.0650 = 0.1718
  assert.equal(Number(job.costUsd.toFixed(4)), 0.1718, `실비 계산이 다르다: ${job.costUsd}`)
  assert.ok(job.criticUsage, '검사관 사용량이 안 남았다')
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
  ['집필이 스키마를 계속 어기면', { content: { ...CONTENT, practice: { ...CONTENT.practice, quiz: CONTENT.practice.quiz.slice(0, 3) } } }, 'draft_schema_invalid'],
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

await test('집필이 예측 선택지에서 흔한 오답을 빼면 실패시킨다', async () => {
  const twisted = structuredClone(CONTENT)
  twisted.predict.hook.options = twisted.predict.hook.options.map((o: string) =>
    o === OUTLINE.prediction.common_wrong ? '설계에 없던 선택지' : o)
  const { deps, log } = makeDeps({ content: twisted })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  // 정적 지적이 남아 있으면 상한까지 재작성 후 반려된다
  assert.equal(log.failures[0].code, 'draft_quality_rejected', `흔한 오답이 빠졌는데 통과했다: ${log.failures[0].code}`)
  assert.ok(log.failures[0].detail.includes('[설계 위반]'), `사유에 정합성 지적이 없다: ${log.failures[0].detail.slice(0, 80)}`)
  assert.equal(log.quotaRefunded, 1)
})

await test('집필이 문제 난이도를 바꾸면 draft_contradicts_plan 으로 잡는다', async () => {
  const twisted = structuredClone(CONTENT)
  twisted.practice.quiz[0].difficulty = twisted.practice.quiz[0].difficulty === 3 ? 1 : 3
  const { deps, log } = makeDeps({ content: twisted })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.equal(log.failures[0].code, 'draft_quality_rejected')
  assert.ok(log.failures[0].detail.includes('[설계 위반]'), `사유에 정합성 지적이 없다: ${log.failures[0].detail.slice(0, 80)}`)
})

await test('실패해도 이미 쓴 토큰의 실비는 기록한다', async () => {
  const { deps, log } = makeDeps({ draftThrows: new LlmOutputError('끊김') })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.ok(log.jobs[0].costUsd > 0, '실패해도 설계 단계 토큰은 과금된다 — 기록해야 예산이 맞는다')
})

console.log('\n▸ 검사 루프 (반려 → 재작성)')

await test('검사관이 통과시키면 재작성 없이 끝난다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.equal(log.critiques, 1)
  assert.equal(log.revisions, 0)
  assert.equal(log.contents[0].meta.qualityScore, 88)
  assert.equal(log.contents[0].meta.revisions, 0)
})

await test('검사관이 반려하면 사유를 붙여 재작성하고, 통과하면 저장한다', async () => {
  const { deps, log } = makeDeps({ verdicts: [
    { score: 55, must_fix: [{ path: 'quiz[0]', issue: '본문 복사', fix: '새 상황으로' }] },
    { score: 84, must_fix: [] },
  ] })
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.equal(log.revisions, 1, '반려됐는데 재작성이 없다')
  assert.equal(log.critiques, 2, '재작성 후 다시 검사하지 않았다')
  assert.ok(log.lastInstructions.includes('본문 복사'), '재작성 지시에 반려 사유가 없다')
  assert.equal(log.contents[0].meta.qualityScore, 84)
  assert.equal(log.contents[0].meta.revisions, 1)
})

await test('정적 린트에 걸리면 검사관 점수가 높아도 재작성한다', async () => {
  const rude = structuredClone(CONTENT)
  rude.concept.analogy = '이건 당연히 아는 내용이라 아주 간단합니다. 쉽죠?'
  const { deps, log } = makeDeps({ content: rude, revised: CONTENT, verdicts: [{ score: 95, must_fix: [] }] })
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.equal(log.revisions, 1, '말투 위반인데 그냥 통과시켰다')
  assert.ok(log.lastInstructions.includes('[말투]'), '재작성 지시에 말투 지적이 없다')
  assert.equal(log.uploads.length, 1, '고쳐진 뒤에는 올라가야 한다')
})

await test('재작성 상한을 넘겨도 반려면 draft_quality_rejected 로 실패하고 환불한다', async () => {
  const { deps, log } = makeDeps({ verdicts: [{ score: 40, must_fix: [{ path: 'title', issue: '오개념 헤드라인', fix: '바꿔라' }] }] })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'ws1'))
  assert.equal(log.failures[0].code, 'draft_quality_rejected')
  assert.equal(log.revisions, 2, `재작성이 ${log.revisions}회 (상한 2회여야 함)`)
  assert.equal(log.critiques, 3, '초안 + 재작성 2회 = 검사 3회')
  assert.equal(log.quotaRefunded, 1)
  assert.equal(log.uploads.length, 0, '반려된 학습지가 올라갔다')
  assert.ok(log.failures[0].detail.includes('오개념 헤드라인'), '실패 사유에 검사관 지적이 없다')
})

await test('품질 반려는 잡 단위로 재시도하지 않는다 (루프 안에서 이미 다 써봤다)', () => {
  assert.equal(pipe.isRetryable('draft_quality_rejected'), false)
})

await test('만든 프롬프트의 지문을 학습지에 남긴다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'ws1')
  assert.equal(log.contents[0].meta.promptVersion, 'testfp01',
    '프롬프트 지문이 저장되지 않으면 점수가 떨어져도 어느 프롬프트 때문인지 되짚을 수 없다')
})

console.log('\n▸ 비용 벽 · 늦게 끝난 생성')

await test('한 장 예산을 넘기면 그 자리에서 끊고 환불한다', async () => {
  const { deps, log } = makeDeps()
  // 설계 한 번도 못 낼 만큼 작은 예산. 벽이 실제로 막는지만 본다.
  await assert.rejects(
    () => pipe.runGeneration(deps, INPUT, 'ws1', 1, { remainingUsd: 0.001 }),
    (e: any) => e.code === 'cost_cap_exceeded')
  assert.equal(log.failures[0]?.code, 'cost_cap_exceeded')
  assert.equal(log.quotaRefunded, 1, '예산 때문에 끊었는데 장수를 안 돌려줬다')
  assert.equal(log.uploads.length, 0, '끊었는데 HTML 이 올라갔다')
})

await test('예산은 재시도를 건너 이어진다', async () => {
  const { deps } = makeDeps()
  const budget = { remainingUsd: 0.4 }
  await pipe.runGeneration(deps, INPUT, 'ws1', 1, budget)
  const afterFirst = budget.remainingUsd
  assert.ok(afterFirst < 0.4, '한 장을 만들었는데 예산이 줄지 않았다')

  // 같은 예산으로 두 번째를 돌리면 남은 돈에서 또 깎인다.
  const { deps: deps2 } = makeDeps()
  await pipe.runGeneration(deps2, INPUT, 'ws2', 2, budget)
  assert.ok(budget.remainingUsd < afterFirst, '두 번째 시도가 예산을 안 깎았다')
})

await test('예산을 넘긴 실패는 재시도하지 않는다', () => {
  assert.equal(pipe.isRetryable('cost_cap_exceeded'), false)
  assert.equal(pipe.isRetryable('generation_superseded'), false)
})

await test('기록되는 비용은 재작성까지 전부 더한 값이다', async () => {
  const once = makeDeps()
  await pipe.runGeneration(once.deps, INPUT, 'ws1')
  const plain = once.log.jobs[0].costUsd

  // 한 번 반려됐다가 통과하는 경우. 집필과 검사관이 한 번씩 더 돈다.
  const revised = makeDeps({ verdicts: [{ score: 50, must_fix: [{ path: 'x', issue: 'y' }] }, { score: 90 }] })
  await pipe.runGeneration(revised.deps, INPUT, 'ws2')
  assert.equal(revised.log.revisions, 1, '재작성이 일어나지 않아 비교가 성립하지 않는다')
  assert.ok(revised.log.jobs[0].costUsd > plain,
    `재작성한 쪽이 더 싸게 기록됐다: ${revised.log.jobs[0].costUsd} <= ${plain}`)
})

await test('청소기가 먼저 닫은 건이면 완성본을 버린다', async () => {
  // 10분을 넘겨 청소기가 이미 실패로 닫고 환불한 상황.
  // 여기서 학습지를 저장해 버리면 환불은 환불대로 되고 학습지는 학습지대로 나간다 — 공짜 한 장이다.
  const { deps, log } = makeDeps({ reaped: true, alreadyClosed: true })
  await assert.rejects(
    () => pipe.runGeneration(deps, INPUT, 'ws1'),
    (e: any) => e.code === 'generation_superseded')
  assert.equal(log.contents.length, 0, '이미 닫힌 건인데 내용을 저장했다')
  assert.equal(log.schedules.length, 0, '이미 닫힌 건인데 복습 스케줄을 만들었다')
  assert.equal(log.quotaRefunded, 0, '청소기가 이미 환불한 건을 또 환불했다')
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

// ── 진행 보고와 벽시계 ────────────────────────────────────────────────────
//
// 13분째 "품질을 검사하고 있어요" 를 보고 있었다는 신고에서 나온 검사들이다.
// 화면이 거짓말을 한 것이 절반, 아무도 그 생성을 닫아 주지 않은 것이 절반이었다.

await test('단계를 밟는 대로 서버에 보고한다', async () => {
  const { deps, log } = makeDeps()
  await pipe.runGeneration(deps, INPUT, 'w1')
  assert.deepEqual(log.stages, ['plan', 'draft', 'critic', 'render', 'save'],
    '진행 화면이 읽을 단계가 실제 순서와 다르다')
})

await test('재작성을 하면 revise 도 보고된다', async () => {
  const { deps, log } = makeDeps({
    verdicts: [{ score: 60, must_fix: [{ path: 'concept', issue: '얕다' }] }, { score: 90, must_fix: [] }],
  })
  await pipe.runGeneration(deps, INPUT, 'w1')
  assert.ok(log.stages.includes('revise'), '다시 쓰는 동안 화면은 여전히 "검사 중" 이라고 말한다')
  assert.equal(log.stages.filter((s: string) => s === 'critic').length, 2)
})

await test('단계 보고가 실패해도 학습지는 나온다', async () => {
  // 진행 막대 하나 때문에 학습지를 잃을 수는 없다.
  const { deps, log } = makeDeps({ setStageThrows: new Error('DB 잠깐 끊김') })
  await pipe.runGeneration(deps, INPUT, 'w1')
  assert.equal(log.contents.length, 1)
  assert.equal(log.quotaRefunded, 0)
})

await test('벽시계 예산을 넘기면 스스로 닫고 환불한다', async () => {
  // 런타임이 우리를 죽이면 아무도 이 행을 못 닫는다. 죽기 전에 우리가 먼저 끊는다.
  let t = Date.parse('2026-09-06T05:00:00Z')
  const { deps, log } = makeDeps({
    clock: () => { const d = new Date(t); t += pipe.GENERATION_BUDGET_MS; return d },
  })
  await assert.rejects(() => pipe.runGeneration(deps, INPUT, 'w1'))
  assert.equal(log.failures[0].code, 'generation_timeout')
  assert.equal(log.quotaRefunded, 1, '시간 초과로 끊었으면 장수는 돌려줘야 한다')
})

await test('시간 초과는 다시 시도하지 않는다', () => {
  // 8분을 태운 뒤 또 8분을 태우는 것은 기다림을 두 배로 만들 뿐이다.
  assert.equal(pipe.isRetryable('generation_timeout'), false)
})

await test('마감 시각은 시도들이 함께 쓴다', async () => {
  // 시도마다 8분을 새로 주면 살아 있는 생성이 DB 청소 기준(10분)을 넘겨
  // "연결이 끊겼다" 며 환불당한다. 다 만든 학습지를 버리는 자리가 여기다.
  const base = Date.parse('2026-09-06T05:00:00Z')
  const { deps, log } = makeDeps({ clock: () => new Date(base) })
  // 1차 시도가 이미 다 써 버린 마감 시각을 그대로 물려받는다.
  const alreadySpent = new Date(base - 1)
  await assert.rejects(
    () => pipe.runGeneration(deps, INPUT, 'w1', 2, pipe.newCostBudget(), alreadySpent),
    /generation_timeout/,
    '두 번째 시도가 시간을 새로 받아 갔다')
  assert.equal(log.stages.length, 0, '시간이 없는데 첫 단계를 시작했다')

  // 넘기지 않으면 이번 시도가 새로 8분을 받는다(첫 시도의 정상 경로).
  const fresh = makeDeps({ clock: () => new Date(base) })
  await fresh.deps.db.setStage('w1', 'plan')
  await pipe.runGeneration(fresh.deps, INPUT, 'w1')
  assert.equal(fresh.log.contents.length, 1)
})

await test('generateWithRetry 가 마감 시각을 반복문 밖에서 만든다', () => {
  // 반복문 안으로 들어가는 순간 시도마다 8분이 새로 생긴다. 눈으로는 안 보이는 실수라
  // 코드 모양을 직접 잰다.
  const src = readFileSync(
    resolve(HERE, '../supabase/functions/generate-worksheet/index.ts'), 'utf8')
  const body = /async function generateWithRetry[\s\S]*?\n}/.exec(src)
  assert.ok(body, 'generateWithRetry 를 못 찾았다')
  const [before, after] = body[0].split(/for \(let attempt/)
  assert.ok(/newDeadline\(/.test(before), '마감 시각을 반복문 밖에서 안 만든다')
  assert.ok(!/newDeadline\(/.test(after ?? ''), '마감 시각을 시도마다 새로 만들고 있다')
  assert.ok(/runGeneration\([^)]*deadline/.test(after ?? ''), '마감 시각을 넘기지 않는다')
})

await test('예산은 8분이고 DB 청소 기준(10분)보다 짧다', () => {
  // 순서가 뒤집히면 정상적으로 살아 있는 생성이 먼저 청소당한다.
  const sql = readFileSync(
    resolve(HERE, '../supabase/migrations/20260101000026_generation_progress.sql'), 'utf8')
  const m = /generation_stall_timeout[\s\S]*?interval '(\d+) minutes'/.exec(sql)
  assert.ok(m, 'DB 의 청소 기준을 못 찾았다')
  assert.ok(pipe.GENERATION_BUDGET_MS < Number(m[1]) * 60_000,
    `파이프라인 예산(${pipe.GENERATION_BUDGET_MS / 60000}분)이 청소 기준(${m[1]}분)보다 길다`)
})

await test('단계 이름이 DB 제약과 같다', () => {
  const sql = readFileSync(
    resolve(HERE, '../supabase/migrations/20260101000026_generation_progress.sql'), 'utf8')
  const m = /worksheets_stage_valid[\s\S]*?stage in \(([^)]*)\)/.exec(sql)
  assert.ok(m, 'stage 제약을 못 찾았다')
  const allowed = new Set(m[1].split(',').map((x) => x.trim().replace(/'/g, '')))
  const { deps, log } = makeDeps({
    verdicts: [{ score: 60, must_fix: [{ path: 'c', issue: 'x' }] }, { score: 90, must_fix: [] }],
  })
  return pipe.runGeneration(deps, INPUT, 'w1').then(() => {
    for (const st of log.stages) {
      assert.ok(allowed.has(st), `파이프라인이 보고하는 '${st}' 를 DB 가 거부한다`)
    }
  })
})


console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
