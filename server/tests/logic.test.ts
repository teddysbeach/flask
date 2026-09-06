// 비용 가드 · 정합성 검사 · 복습 스케줄 테스트.
//   node --experimental-strip-types server/tests/logic.test.ts
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as cost from '../supabase/functions/_shared/cost.ts'
import { crossCheck } from '../supabase/functions/_shared/cross-check.ts'
import * as rev from '../supabase/functions/_shared/review-schedule.ts'
import { validateWorksheet } from '../supabase/functions/_shared/validate.ts'
import { validateTopic, validateLevel } from '../supabase/functions/_shared/http.ts'
import { voiceLint } from '../supabase/functions/_shared/voice-lint.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
let passed = 0
const failures: string[] = []
function test(name: string, fn: () => void) {
  try { fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(name); console.log(`  FAIL ${name}\n    ${(e as Error).message}`) }
}

console.log('\n▸ 비용')

test('계획서에 적은 최악 비용과 코드가 일치한다', () => {
  const usd = cost.worksheetCostUsd([
    { model: 'claude-opus-5',   usage: { inputTokens: 2600, outputTokens: 1000 } },
    { model: 'claude-sonnet-5', usage: { inputTokens: 4400, outputTokens: 6000 } },
  ])
  assert.equal(Number(usd.toFixed(4)), 0.1068, `계산이 계획($0.1068)과 다르다: ${usd}`)
  assert.equal(cost.usdToKrw(usd), 150)
})

test('캐시 읽기 토큰을 입력가로 계산한다 (상한이므로 안전)', () => {
  const a = cost.callCostUsd('claude-sonnet-5', { inputTokens: 1000, outputTokens: 0 })
  const b = cost.callCostUsd('claude-sonnet-5', { inputTokens: 500, outputTokens: 0, cacheReadTokens: 500 })
  assert.equal(a, b, '캐시 토큰이 비용에서 빠지면 예산 가드가 과소평가한다')
})

test('가격표에 없는 모델은 조용히 0원으로 처리하지 않는다', () => {
  assert.throws(() => cost.callCostUsd('claude-made-up-9', { inputTokens: 1, outputTokens: 1 }))
})

test('표본이 적으면 다운시프트하지 않는다', () => {
  assert.equal(cost.decideDownshift([0.5, 0.5, 0.5]), 'none', '한두 건 튐으로 품질을 깎으면 안 된다')
})

test('경보를 넘으면 단계적으로 내려간다', () => {
  const n = 20
  assert.equal(cost.decideDownshift(Array(n).fill(0.10)), 'none')
  assert.equal(cost.decideDownshift(Array(n).fill(0.13)), 'trim')
  assert.equal(cost.decideDownshift(Array(n).fill(0.20)), 'low_effort')
})

test('다운시프트가 실제로 출력 예산을 줄인다', () => {
  assert.ok(cost.draftParams('trim').maxTokens < cost.draftParams('none').maxTokens)
  assert.ok(cost.draftParams('low_effort').maxTokens < cost.draftParams('trim').maxTokens)
  assert.equal(cost.draftParams('low_effort').effort, 'low')
})

console.log('\n▸ 단계 간 정합성 (집필이 설계를 뒤집었는지)')

const raw = JSON.parse(readFileSync(resolve(HERE, 'fixtures/worksheet-event-sourcing.json'), 'utf8'))
const content = validateWorksheet(raw)
const outline = {
  schema_version: 1,
  title: content.title,
  topic_normalized: content.topic_normalized,
  level: content.level,
  estimated_minutes: content.estimated_minutes,
  section_briefs: [],
  facts: content.origin_story.timeline.map((t) => ({ when: t.when, what: t.what, confidence: t.confidence })),
  roleplay_mode: content.roleplay.mode,
  quiz_plan: content.quiz.map((q) => ({ asks: q.question, answer_gist: q.answer, source_block: 0, difficulty: q.difficulty })),
  prerequisites: content.prerequisites,
  next_steps: content.next_steps,
}

test('설계대로 쓴 학습지는 통과한다', () => {
  assert.equal(crossCheck(outline, content).ok, true)
})

test('집필이 사실성 등급을 올리면 잡는다', () => {
  const bad = structuredClone(content)
  bad.origin_story.timeline[1].confidence = 'high'   // medium 이었던 것을 확신으로 바꿈
  const r = crossCheck(outline, bad)
  assert.equal(r.ok, false)
  assert.ok(r.violations.some((v) => v.includes('confidence')), r.violations.join(' / '))
})

test('집필이 가상 시나리오를 사실로 바꾸면 잡는다', () => {
  const bad = structuredClone(content)
  bad.roleplay.mode = 'real_case'
  const r = crossCheck(outline, bad)
  assert.equal(r.ok, false)
  assert.ok(r.violations.some((v) => v.includes('roleplay.mode')))
})

test('불확실한 사실이 있는데 고지가 없으면 잡는다', () => {
  const bad = structuredClone(content)
  bad.origin_story.uncertainty_note = null
  assert.equal(crossCheck(outline, bad).ok, false)
})

test('집필이 문제 난이도를 바꾸면 잡는다', () => {
  const bad = structuredClone(content)
  bad.quiz[0].difficulty = 3
  assert.equal(crossCheck(outline, bad).ok, false)
})

test('집필이 사전학습을 새로 지어내면 잡는다', () => {
  const bad = structuredClone(content)
  bad.prerequisites[0].title = '내가 지어낸 주제'
  const r = crossCheck(outline, bad)
  assert.ok(r.violations.some((v) => v.includes('prerequisites[0]')))
})

test('표기 흔들림(공백·괄호)까지 실패로 만들지는 않는다', () => {
  const ok = structuredClone(content)
  ok.prerequisites[0].title = ' 불변성 (Immutability) '
  assert.equal(crossCheck(outline, ok).ok, true)
})

console.log('\n▸ 복습 스케줄')

const SEOUL = 'Asia/Seoul'
const NY = 'America/New_York'
const now = new Date('2026-09-06T05:00:00Z')

test('초기 5회차가 1/3/7/16/35일로 잡힌다', () => {
  const s = rev.createInitialSchedules(['a', 'b', 'c', 'd', 'e'], now, SEOUL, 21)
  assert.deepEqual(s.map((x) => x.intervalDays), [1, 3, 7, 16, 35])
  assert.deepEqual(s.map((x) => x.quizItemId), ['a', 'b', 'c', 'd', 'e'], '회차마다 다른 문제를 낸다')
})

test('알림 시각이 사용자 로컬 21시로 정확히 떨어진다', () => {
  const s = rev.createInitialSchedules(['a'], now, SEOUL, 21)
  // 서울은 UTC+9, DST 없음 → 21시는 UTC 12시
  assert.equal(s[0].dueAt.toISOString(), '2026-09-07T12:00:00.000Z')
})

test('서머타임 경계를 넘어도 로컬 시각이 유지된다', () => {
  // 뉴욕 2026-11-01 새벽에 DST 해제 (UTC-4 → UTC-5)
  const before = new Date('2026-10-30T12:00:00Z')
  const beforeDst = rev.atLocalHour(before, 1, NY, 21)   // 10/31, 아직 EDT
  const afterDst  = rev.atLocalHour(before, 3, NY, 21)   // 11/2, EST
  const hourIn = (d: Date) => Number(new Intl.DateTimeFormat('en-US',
    { timeZone: NY, hour: '2-digit', hourCycle: 'h23' }).format(d))
  assert.equal(hourIn(beforeDst), 21, 'DST 이전 21시가 아니다')
  assert.equal(hourIn(afterDst), 21, 'DST 이후 21시가 아니다 — 알림이 한 시간 어긋난다')
  // UTC 로는 실제로 한 시간 달라야 한다 (오프셋이 바뀌었으므로)
  assert.notEqual(beforeDst.getUTCHours(), afterDst.getUTCHours(), 'DST 를 반영하지 않았다')
})

test('SM-2: 쉽다고 하면 ease 가 오르고 어렵다고 하면 내린다', () => {
  assert.ok(rev.nextEase(2.5, 3) > 2.5)
  assert.ok(rev.nextEase(2.5, 1) < 2.5)
  assert.equal(rev.nextEase(2.5, 2), 2.5, '보통이면 그대로여야 한다')
})

test('ease 는 범위를 벗어나지 않는다', () => {
  let e = 2.5
  for (let i = 0; i < 30; i++) e = rev.nextEase(e, 0)
  assert.ok(e >= rev.EASE_MIN, `하한 이탈: ${e}`)
  let f = 2.5
  for (let i = 0; i < 30; i++) f = rev.nextEase(f, 3)
  assert.ok(f <= rev.EASE_MAX, `상한 이탈: ${f}`)
})

const row = (over: Partial<rev.ReviewRow> = {}): rev.ReviewRow => ({
  id: 'r1', quizItemId: 'q1', repetition: 0, intervalDays: 1,
  ease: 2.5, dueAt: now, state: 'pending', ...over,
})

test('모르겠음이면 내일 같은 문제를 다시 낸다', () => {
  const out = rev.answerReview(row(), 0, now, SEOUL, 21)
  assert.ok(out.relearn, '재복습이 안 잡혔다')
  assert.equal(out.relearn!.intervalDays, 1)
  assert.equal(out.relearn!.quizItemId, 'q1')
})

test('5회차를 보통 이상으로 통과하면 졸업한다', () => {
  assert.equal(rev.answerReview(row({ repetition: 4 }), 2, now, SEOUL, 21).state, 'retired')
  assert.equal(rev.answerReview(row({ repetition: 4 }), 1, now, SEOUL, 21).state, 'done', '어려웠으면 졸업 아님')
  assert.equal(rev.answerReview(row({ repetition: 2 }), 3, now, SEOUL, 21).state, 'done')
})

test('잘못된 grade 는 거부한다', () => {
  assert.throws(() => rev.answerReview(row(), 5, now, SEOUL, 21))
  assert.throws(() => rev.answerReview(row(), -1, now, SEOUL, 21))
})

test('쉽다/어렵다에 따라 남은 회차 간격이 늘고 준다', () => {
  const remaining = [row({ id: 'r4', repetition: 3 })]   // 기본 16일
  const easy = rev.answerReview(row(), 3, now, SEOUL, 21)
  const hard = rev.answerReview(row(), 1, now, SEOUL, 21)
  const longer  = rev.rescheduleRemaining(remaining, easy.ease, now, SEOUL, 21)[0]
  const shorter = rev.rescheduleRemaining(remaining, hard.ease, now, SEOUL, 21)[0]
  assert.ok(longer.intervalDays > rev.BASE_INTERVALS[3], `안 늘었다: ${longer.intervalDays}`)
  assert.ok(shorter.intervalDays < rev.BASE_INTERVALS[3], `안 줄었다: ${shorter.intervalDays}`)
})

test('SM-2 가 응답마다 누적된다 (한 번 계산하고 끝나지 않는다)', () => {
  // 어렵다고 계속 답하면 간격이 계속 짧아져야 한다.
  // rescheduleRemaining 이 ease 를 이어받지 않으면 매번 2.5 에서 출발해 제자리가 된다.
  let ease = rev.EASE_DEFAULT
  const seen: number[] = []
  for (let i = 0; i < 4; i++) {
    ease = rev.answerReview(row({ ease }), 1, now, SEOUL, 21).ease
    const next = rev.rescheduleRemaining([row({ id: 'x', repetition: 4, ease })], ease, now, SEOUL, 21)[0]
    seen.push(next.intervalDays)
    ease = next.ease
  }
  assert.ok(seen[3] < seen[0], `누적되지 않았다: ${seen.join(' → ')}`)
  assert.deepEqual(seen, [...seen].sort((a, b) => b - a), `단조 감소해야 한다: ${seen.join(' → ')}`)
})

test('하루 상한을 넘는 복습은 다음 날로 밀린다', () => {
  const sameDay = Array.from({ length: 7 }, (_, i) => ({ id: `x${i}`, dueAt: new Date('2026-09-07T12:00:00Z') }))
  const capped = rev.applyDailyCap(sameDay, SEOUL, 3)
  const byDay = new Map<string, number>()
  for (const c of capped) {
    const k = new Intl.DateTimeFormat('en-CA', { timeZone: SEOUL }).format(c.dueAt)
    byDay.set(k, (byDay.get(k) ?? 0) + 1)
  }
  assert.equal(capped.length, 7, '항목이 사라지면 안 된다')
  assert.ok([...byDay.values()].every((n) => n <= 3), `하루 상한 초과: ${[...byDay.entries()]}`)
})

test('iOS 64개 한도에 맞춰 임박한 것부터 48개만 고른다', () => {
  const many = Array.from({ length: 120 }, (_, i) => ({
    id: `n${i}`, dueAt: new Date(now.getTime() + (i + 1) * 86400000),
  }))
  const picked = rev.selectForNotifications(many, now)
  assert.equal(picked.length, 48, 'iOS 한도를 넘기면 초과분이 조용히 버려진다')
  assert.equal(picked[0].id, 'n0', '가장 임박한 것이 먼저여야 한다')
})

test('이미 지난 복습은 알림으로 걸지 않는다', () => {
  const past = [{ id: 'old', dueAt: new Date(now.getTime() - 86400000) }]
  assert.equal(rev.selectForNotifications(past, now).length, 0)
})

test('알림 본문은 문장 단위로 자른다', () => {
  const long = '이벤트 스토어에 저장되는 것은 상태인가요 변화인가요? ' + 'x'.repeat(200)
  const body = rev.notificationBody(long)
  assert.ok(body.length <= 101, `너무 길다: ${body.length}`)
  assert.ok(body.endsWith('…'))
  assert.equal(rev.notificationBody('짧은 질문?'), '짧은 질문?', '짧으면 자르지 않는다')
})

console.log('\n▸ 말투 (파르)')

test('픽스처가 말투 규칙을 지킨다', () => {
  const r = voiceLint(content)
  assert.equal(r.errors.length, 0, r.errors.map((e) => `${e.path}: ${e.detail}`).join(' / '))
  assert.ok(r.avgSentenceChars < 60, `평균 문장이 ${r.avgSentenceChars}자로 길다`)
})

test('못 따라온 사람을 소외시키는 말을 잡는다', () => {
  for (const bad of ['이건 쉽죠?', '아주 간단합니다', '당연히 아는 내용이에요', '아시다시피 그렇죠', '별거 아니에요']) {
    const r = voiceLint({ what_we_learn: { analogy: bad } })
    assert.ok(r.errors.length > 0, `"${bad}" 를 못 잡았다`)
  }
})

test('반말을 잡는다 (어미 나열이 아니라 평서형 전체를)', () => {
  for (const bad of [
    '이벤트는 과거형으로 짓는다.',      // '한다|이다|된다' 목록에 없는 어미
    '상태를 저장하지 않는다.',
    '그런 방법은 없다.',
    '일단 해보자.',
  ]) {
    const r = voiceLint({ what_we_learn: { analogy: bad } })
    assert.ok(r.errors.some((e) => e.rule === '반말'), `"${bad}" 를 못 잡았다`)
  }
})

test('합니다체는 반말로 오인하지 않는다', () => {
  for (const ok of ['이벤트를 순서대로 저장합니다.', '그것이 핵심입니다.', '어렵지는 않았습니다.']) {
    const r = voiceLint({ what_we_learn: { analogy: ok } })
    assert.equal(r.errors.filter((e) => e.rule === '반말').length, 0, `"${ok}" 를 반말로 잘못 잡았다`)
  }
})

test('사용자 탓하는 실패 문구를 잡는다', () => {
  const r = voiceLint({ what_we_learn: { analogy: '요청이 올바르지 않습니다' } })
  assert.ok(r.errors.some((e) => e.rule === '사용자 탓'), '실패 문구는 언제나 우리 탓이어야 한다')
})

test('코드 블록은 말투 검사에서 제외한다', () => {
  const r = voiceLint({
    what_we_learn: { summary: [{ type: 'code', value: 'const x = 1; // 간단합니다' }] },
  })
  assert.equal(r.errors.length, 0, '코드 안의 주석까지 말투로 잡으면 안 된다')
})

test('딱딱한 한자어는 경고만 하고 막지는 않는다', () => {
  const r = voiceLint({ what_we_learn: { analogy: '상태를 영속화해서 보관해요' } })
  assert.equal(r.errors.length, 0, '경고가 실패가 되면 안 된다')
  assert.ok(r.warnings.some((w) => w.rule === '딱딱한 한자어'))
})

console.log('\n▸ 입력 검증')

test('주제 길이 제한', () => {
  assert.equal(validateTopic('  이벤트 소싱  '), '이벤트 소싱', '앞뒤 공백은 다듬는다')
  assert.equal(validateTopic(''), null)
  assert.equal(validateTopic('   '), null)
  assert.equal(validateTopic('x'.repeat(121)), null, '길이 제한이 없으면 프롬프트 비용이 튄다')
  assert.equal(validateTopic(123), null)
  assert.equal(validateTopic(null), null)
})

test('알 수 없는 난이도는 입문으로 떨어뜨린다', () => {
  assert.equal(validateLevel('advanced'), 'advanced')
  assert.equal(validateLevel('god_tier'), 'beginner')
  assert.equal(validateLevel(undefined), 'beginner')
})

console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
