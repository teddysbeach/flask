// 텔레메트리 정제기. **무엇이 들어오는가가 아니라 무엇만 들어오는가**를 잰다.
//   node --experimental-strip-types server/tests/telemetry.test.ts

import { cleanCrashes, cleanEvents, cleanInstallId, ALLOWED_PROP_KEYS, EVENT_NAMES } from '../supabase/functions/_shared/telemetry.ts'
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'

const HERE = dirname(fileURLToPath(import.meta.url))
let passed = 0
const failures: string[] = []
function test(name: string, fn: () => void) {
  try { fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(name); console.log(`  FAIL ${name}\n    ${(e as Error).message}`) }
}

console.log('\n▸ 텔레메트리')

const now = new Date().toISOString()

test('허용 목록에 없는 키는 통째로 버린다', () => {
  const [e] = cleanEvents([{
    name: 'worksheetCreateStart',
    occurred_at: now,
    props: { topic_length: 12, topic: '이벤트 소싱', email: 'a@b.com', answer: '학생이 쓴 답' },
  }])
  assert.deepEqual(e.props, { topic_length: 12 })
})

test('중첩 값은 받지 않는다 — 중첩이 곧 유출 경로다', () => {
  const [e] = cleanEvents([{
    name: 'appOpen', occurred_at: now,
    props: { name: { nested: '본문' }, count: [1, 2, 3], kind: 'ok' },
  }])
  assert.deepEqual(e.props, { kind: 'ok' })
})

test('모르는 이벤트 이름은 버린다', () => {
  assert.equal(cleanEvents([{ name: 'sendEverything', occurred_at: now }]).length, 0)
})

test('시각이 없거나 이상하면 버린다', () => {
  assert.equal(cleanEvents([{ name: 'appOpen' }]).length, 0)
  assert.equal(cleanEvents([{ name: 'appOpen', occurred_at: '어제' }]).length, 0)
})

test('한 번에 받는 개수와 문자열 길이에 상한이 있다', () => {
  const many = Array.from({ length: 500 }, () => ({ name: 'appOpen', occurred_at: now }))
  assert.equal(cleanEvents(many).length, 50)
  const [e] = cleanEvents([{ name: 'screenView', occurred_at: now, props: { name: 'x'.repeat(999) } }])
  assert.equal((e.props.name as string).length, 120)
})

test('install_id 는 UUID 형식만 받는다', () => {
  assert.equal(cleanInstallId('아무거나'), null)
  assert.equal(cleanInstallId('3F2504E0-4F89-11D3-9A0C-0305E82C3301'), '3f2504e0-4f89-11d3-9a0c-0305e82c3301')
})

test('크래시는 길이를 자르고 fatal 을 강제로 불리언으로 만든다', () => {
  const [c] = cleanCrashes([{
    message: 'x'.repeat(5000), stack: 'y'.repeat(20000),
    occurred_at: now, fatal: 'yes', fingerprint: 'z'.repeat(200),
  }])
  assert.equal(c.message.length, 2000)
  assert.equal(c.stack!.length, 8000)
  assert.equal(c.fatal, false, '문자열 "yes" 를 참으로 읽으면 안 된다')
  assert.equal(c.fingerprint, 'unknown', '너무 긴 열쇠는 버리고 기본값으로 묶는다')
})

test('이벤트 목록이 앱의 enum 과 같다', () => {
  // 두 벌이 되면 앱이 보내는 이벤트를 서버가 조용히 버린다 — 지표가 비는데 아무도 모른다.
  const dart = readFileSync(resolve(HERE, '../../app/lib/core/analytics.dart'), 'utf8')
  const block = dart.slice(dart.indexOf('enum AnalyticsEvent {'), dart.indexOf('}', dart.indexOf('enum AnalyticsEvent {')))
  const names = [...block.matchAll(/^\s*([a-z][A-Za-z]*),/gm)].map((m) => m[1])
  assert.ok(names.length > 20, `enum 을 못 읽었다 (${names.length}개)`)
  for (const n of names) {
    assert.ok((EVENT_NAMES as readonly string[]).includes(n), `서버가 모르는 이벤트: ${n}`)
  }
})

test('앱이 실제로 쓰는 props 키가 전부 허용 목록에 있다', () => {
  // 화면이 새 키를 넣었는데 서버 목록에 없으면 그 값만 조용히 사라진다.
  const dir = resolve(HERE, '../../app/lib')
  const files: string[] = []
  const walk = (p: string) => {
    for (const f of readdirSync(p, { withFileTypes: true })) {
      const full = resolve(p, f.name)
      if (f.isDirectory()) walk(full)
      else if (f.name.endsWith('.dart')) files.push(full)
    }
  }
  walk(dir)
  const used = new Set<string>()
  for (const f of files) {
    const src = readFileSync(f, 'utf8')
    for (const m of src.matchAll(/props:\s*\{([^}]*)\}/g)) {
      for (const k of m[1].matchAll(/'([a-z_]+)'\s*:/g)) used.add(k[1])
    }
  }
  assert.ok(used.size > 3, `props 를 못 읽었다 (${used.size}개)`)
  const missing = [...used].filter((k) => !ALLOWED_PROP_KEYS.has(k))
  assert.deepEqual(missing, [], `서버 허용 목록에 없는 키: ${missing.join(', ')}`)
})

test('열린 입구에 상한이 걸려 있다', () => {
  // 이 엔드포인트는 로그인 없이 열려 있다(온보딩·로그인 화면의 크래시를 받아야 하므로).
  // 열려 있는 입구는 반드시 두들겨 맞는다 — 상한이 없으면 남의 돈으로 테이블이 찬다.
  const src = readFileSync(resolve(HERE, '../supabase/functions/ingest-telemetry/index.ts'), 'utf8')
  assert.ok(/RATE_LIMIT/.test(src), '속도 제한이 없다')
  assert.ok(/MAX_BODY_BYTES/.test(src), '본문 크기 상한이 없다')
  assert.ok(/content-length/.test(src), '파싱 전에 크기를 재지 않는다')
  // 429 를 주면 앱이 큐를 들고 계속 재시도한다. 조용히 버리는 편이 낫다.
  assert.ok(/stored: 0/.test(src), '상한에 걸렸을 때 조용히 버리지 않는다')
})

console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
