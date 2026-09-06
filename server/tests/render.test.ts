// 렌더러 · 검증기 테스트.
//   node --experimental-strip-types server/tests/render.test.ts
//
// 골든 파일 갱신: UPDATE_GOLDEN=1 node --experimental-strip-types server/tests/render.test.ts

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateWorksheet, ValidationError } from '../supabase/functions/_shared/validate.ts'
import { renderWorksheet, esc, inlineToHtml } from '../supabase/functions/_shared/render.ts'
import { SECTIONS } from '../supabase/functions/_shared/worksheet-types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const FIXTURE = resolve(HERE, 'fixtures/worksheet-event-sourcing.json')
const GOLDEN = resolve(HERE, 'golden/worksheet-event-sourcing.html')

let passed = 0
const failures: string[] = []

function test(name: string, fn: () => void) {
  try { fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(`${name}\n    ${(e as Error).message}`); console.log(`  FAIL ${name}\n    ${(e as Error).message}`) }
}
function assert(cond: unknown, msg: string) { if (!cond) throw new Error(msg) }

const raw = JSON.parse(readFileSync(FIXTURE, 'utf8'))
const CTX = {
  worksheetId: 'ws-0000-1111-2222',
  quizItemIds: ['q0', 'q1', 'q2', 'q3', 'q4'],
  theme: 'light' as const,
}

console.log('\n▸ 검증기')

test('정상 픽스처는 통과한다', () => {
  const c = validateWorksheet(raw)
  assert(c.quiz.length === 5, '문제가 5개가 아니다')
  assert(c.prerequisites.length === 3, '사전학습이 3개가 아니다')
})

test('개수 제약을 어기면 정확한 메시지를 낸다', () => {
  const bad = structuredClone(raw); bad.quiz.pop()
  try { validateWorksheet(bad); assert(false, '4개인데 통과했다') }
  catch (e) {
    const issues = (e as ValidationError).issues
    assert(issues.some((i) => i.includes('quiz') && i.includes('5개') && i.includes('4개')),
      `메시지가 부정확: ${issues.join(' / ')}`)
  }
})

test('hypothetical 인데 disclaimer 가 없으면 거부한다', () => {
  const bad = structuredClone(raw); bad.roleplay.disclaimer = null
  try { validateWorksheet(bad); assert(false, 'disclaimer 없이 통과했다') }
  catch (e) {
    assert((e as ValidationError).issues.some((i) => i.includes('disclaimer')), '정직성 규칙이 안 걸렸다')
  }
})

test('multiple_choice 가 아닌데 choices 가 있으면 거부한다', () => {
  const bad = structuredClone(raw); bad.quiz[0].choices = ['a', 'b', 'c']
  try { validateWorksheet(bad); assert(false, '통과했다') }
  catch (e) { assert((e as ValidationError).issues.some((i) => i.includes('choices')), '') }
})

test('InlineNode 타입이 이상하면 거부한다', () => {
  const bad = structuredClone(raw)
  bad.what_we_learn.summary[0] = { type: 'script', value: 'x' }
  try { validateWorksheet(bad); assert(false, '통과했다') }
  catch (e) { assert((e as ValidationError).issues.some((i) => i.includes('summary[0].type')), '') }
})

console.log('\n▸ 이스케이프')

test('esc 가 HTML 특수문자를 전부 막는다', () => {
  assert(esc('<script>') === '&lt;script&gt;', '<> 미처리')
  assert(esc('a"b') === 'a&quot;b', '따옴표 미처리')
  assert(esc("a'b") === 'a&#39;b', '작은따옴표 미처리')
  assert(esc('a&b') === 'a&amp;b', '앰퍼샌드 미처리')
  // & 를 먼저 치환하지 않으면 이중 인코딩이 난다
  assert(esc('<a>') === '&lt;a&gt;', '이중 인코딩')
})

test('inlineToHtml 은 값을 이스케이프하고 우리가 고른 태그만 만든다', () => {
  const html = inlineToHtml([
    { type: 'bold', value: '<b>주입</b>' },
    { type: 'code', value: '" onload="alert(1)' },
  ])
  assert(html.includes('<strong>&lt;b&gt;주입&lt;/b&gt;</strong>'), `bold 이스케이프 실패: ${html}`)
  assert(!html.includes('onload="'), `속성 주입이 살아있다: ${html}`)
})

test('XSS: 모든 문자열 필드에 공격 문자열을 넣어도 태그가 살아나지 않는다', () => {
  const ATTACK = '<img src=x onerror=alert(1)>"\'</script>'
  const poisoned = structuredClone(raw)
  poisoned.title = ATTACK
  poisoned.topic_normalized = ATTACK
  poisoned.what_we_learn.one_liner = ATTACK
  poisoned.what_we_learn.objectives[0] = ATTACK
  poisoned.what_we_learn.summary[0] = { type: 'text', value: ATTACK }
  poisoned.roleplay.dialogue[0].line = ATTACK
  poisoned.roleplay.dialogue[0].speaker = ATTACK
  poisoned.main_lesson.blocks[0].heading = ATTACK
  poisoned.main_lesson.blocks[0].example.code = ATTACK
  // language 는 30자 제한이 있어 짧은 공격 문자열을 쓴다 (class 속성에 들어가는 자리)
  poisoned.main_lesson.blocks[0].example.language = 'js" onload="x'
  poisoned.quiz[0].question = ATTACK
  poisoned.quiz[1].choices[0] = ATTACK
  poisoned.quiz[0].answer = ATTACK
  poisoned.origin_story.timeline[0].what = ATTACK
  poisoned.homework.tasks[0].detail = ATTACK
  poisoned.wrap_up.checklist[0] = ATTACK
  poisoned.next_steps[0].title = ATTACK

  const html = renderWorksheet(validateWorksheet(poisoned), CTX)
  const body = html.slice(html.indexOf('<body>'))

  // 이스케이프된 텍스트에도 'onerror=' 라는 '문자열'은 남는다. 그건 위험하지 않다.
  // 위험한 건 실제 '엘리먼트'가 생기는 것이므로, 문서에 존재하는 태그 이름을 전부 뽑아
  // 우리가 쓰는 것만 있는지 본다. 주입된 태그는 여기서 반드시 잡힌다.
  const ALLOWED = new Set([
    'html', 'head', 'meta', 'title', 'style', 'body', 'div', 'article', 'header', 'footer',
    'section', 'h1', 'h2', 'p', 'span', 'ul', 'ol', 'li', 'strong', 'em', 'code', 'pre',
    'details', 'summary', 'canvas',
  ])
  const found = new Set([...body.matchAll(/<\/?([a-zA-Z][\w-]*)/g)].map((m) => m[1].toLowerCase()))
  const injected = [...found].filter((t) => !ALLOWED.has(t))
  assert(injected.length === 0, `주입된 태그가 있다: ${injected.join(', ')}`)

  // 속성 문맥 탈출도 막혀야 한다
  assert(!body.includes('<img'), 'img 엘리먼트가 생겼다')
  assert(!body.includes('class="lang-js" onload='), 'class 속성에서 따옴표 탈출이 일어났다')
  assert(body.includes('class="lang-js&quot; onload=&quot;x"'), 'class 속성값이 이스케이프되지 않았다')

  // 공격 문자열은 텍스트로만 살아남아야 한다
  assert(!body.includes(ATTACK), '공격 문자열이 원본 그대로 들어갔다')
  assert(body.includes('&lt;img src=x onerror=alert(1)&gt;'), '이스케이프된 형태가 안 보인다')
})

test('quizItemIds 도 이스케이프된다', () => {
  const html = renderWorksheet(validateWorksheet(raw), { ...CTX, quizItemIds: ['" onload="x', 'b', 'c', 'd', 'e'] })
  assert(!html.includes('" onload="x"'), '속성값 주입이 뚫렸다')
  assert(html.includes('&quot; onload=&quot;x'), '이스케이프된 형태가 안 보인다')
})

console.log('\n▸ 렌더러')

const content = validateWorksheet(raw)
const html = renderWorksheet(content, CTX)

test('11개 섹션이 전부, 순서대로 나온다', () => {
  for (let i = 0; i < SECTIONS.length; i++) {
    assert(html.includes(`id="sec-${i + 1}" data-section="${SECTIONS[i].key}"`),
      `섹션 ${i + 1} (${SECTIONS[i].key}) 이 없거나 순서가 다르다`)
  }
  const count = (html.match(/class="sec"/g) ?? []).length
  assert(count === 11, `섹션이 ${count}개다 (11개여야 함)`)
})

test('문제마다 quiz_items.id 가 붙는다 (복습 알림 딥링크용)', () => {
  for (const id of CTX.quizItemIds) {
    assert(html.includes(`data-quiz-id="${id}"`), `quiz id ${id} 가 없다`)
  }
})

test('필기 레이어와 문서 폭 고정이 살아있다', () => {
  assert(html.includes('id="ink-layer"'), '필기 캔버스가 없다')
  assert(html.includes('--ds-sheet-width: 820px'), '문서 폭 토큰이 없다')
  assert(html.includes(`data-worksheet-id="${CTX.worksheetId}"`), 'worksheet id 가 없다')
})

test('필기 여백이 섹션마다 들어간다', () => {
  const n = (html.match(/class="ink-space"/g) ?? []).length
  // 섹션 10개(문제 섹션 제외) + 문제 5개
  assert(n === 15, `필기 여백이 ${n}개다 (15개여야 함)`)
})

test('외부 리소스를 하나도 참조하지 않는다 (오프라인 렌더)', () => {
  assert(!/<link[^>]+href=/i.test(html), '외부 스타일시트를 참조한다')
  assert(!/<script[^>]+src=/i.test(html), '외부 스크립트를 참조한다')
  assert(!/https?:\/\//.test(html.slice(html.indexOf('<body>'))), '본문에 외부 URL 이 있다')
})

test('결정론: 같은 입력이면 바이트 단위로 같다', () => {
  const a = renderWorksheet(validateWorksheet(structuredClone(raw)), CTX)
  const b = renderWorksheet(validateWorksheet(structuredClone(raw)), CTX)
  assert(a === b, '두 번 렌더한 결과가 다르다 — 재렌더 시 기존 필기가 어긋난다')
  assert(a.length === html.length, '길이가 다르다')
})

test('골든 파일과 일치한다', () => {
  if (process.env.UPDATE_GOLDEN === '1' || !existsSync(GOLDEN)) {
    mkdirSync(dirname(GOLDEN), { recursive: true })
    writeFileSync(GOLDEN, html)
    console.log(`    (골든 파일 갱신: ${GOLDEN.replace(process.cwd() + '/', '')})`)
    return
  }
  const golden = readFileSync(GOLDEN, 'utf8')
  assert(golden === html,
    `출력이 골든 파일과 다르다 (${golden.length} → ${html.length} bytes).\n` +
    `    의도한 변경이면 UPDATE_GOLDEN=1 로 갱신하되, 기존 학습지의 필기 좌표가 어긋나지 않는지 확인할 것.`)
})

console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
