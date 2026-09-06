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
import { ICON_PATHS } from '../supabase/functions/_shared/icons.g.ts'

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
  poisoned.what_we_learn.analogy = ATTACK
  poisoned.glossary[0].term = ATTACK
  poisoned.glossary[0].plain = ATTACK
  poisoned.guide_notes[0].note = ATTACK
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
  // 우리가 넣은 필기 런타임 <script> 블록은 통째로 걷어내고 검사한다.
  // 허용 목록에 'script' 를 넣어버리면 주입된 스크립트를 못 잡게 된다.
  const body = html
    .slice(html.indexOf('<body>'))
    .replace(/<script>[\s\S]*?<\/script>/g, '')
  assert(!body.includes('<script'), '런타임 블록을 걷어낸 뒤에도 script 태그가 남아있다')

  // 이스케이프된 텍스트에도 'onerror=' 라는 '문자열'은 남는다. 그건 위험하지 않다.
  // 위험한 건 실제 '엘리먼트'가 생기는 것이므로, 문서에 존재하는 태그 이름을 전부 뽑아
  // 우리가 쓰는 것만 있는지 본다. 주입된 태그는 여기서 반드시 잡힌다.
  const ALLOWED = new Set([
    'html', 'head', 'meta', 'title', 'style', 'body', 'div', 'article', 'header', 'footer',
    'section', 'h1', 'h2', 'p', 'span', 'ul', 'ol', 'li', 'strong', 'em', 'code', 'pre',
    'details', 'summary', 'canvas', 'dl', 'dt', 'dd', 'aside', 'svg', 'path',
  ])
  const found = new Set([...body.matchAll(/<\/?([a-zA-Z][\w-]*)/g)].map((m) => m[1].toLowerCase()))
  const injected = [...found].filter((t) => !ALLOWED.has(t))
  assert(injected.length === 0, `주입된 태그가 있다: ${injected.join(', ')}`)

  // svg/path 를 허용 목록에 넣었으므로, 문서의 모든 path 가 실제로 우리 아이콘에서
  // 온 것인지까지 확인한다. 허용만 하고 넘어가면 주입된 path 를 놓친다.
  const known = new Set(Object.values(ICON_PATHS).flat())
  const docPaths = [...body.matchAll(/<path d="([^"]*)"/g)].map((m) => m[1])
  assert(docPaths.length > 0, '아이콘이 하나도 안 들어갔다')
  const foreign = docPaths.filter((d) => !known.has(d))
  assert(foreign.length === 0, `아이콘 상수에 없는 path 가 있다: ${foreign[0]?.slice(0, 40)}`)

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

test('필기 여백이 섹션·문제·활동·그림 과제마다 들어간다', () => {
  const n = (html.match(/class="ink-space"/g) ?? []).length
  // 섹션 10개(문제 섹션 제외) + 문제 5개 + 손을 쓰는 활동 + 그림 위 과제
  const activityInk = content.main_lesson.blocks
    .filter((b) => b.activity && ['compute', 'draw', 'explain'].includes(b.activity.kind)).length
  const figureInk = content.figures.filter((f) => f.drawTask).length
  const expected = 10 + content.quiz.length + activityInk + figureInk
  assert(n === expected, `필기 여백이 ${n}개다 (${expected}개여야 함: 10 + 문제 ${content.quiz.length} + 활동 ${activityInk} + 그림 과제 ${figureInk})`)
  assert(activityInk > 0, '손을 쓰는 활동이 하나도 없다 — 빈 종이는 학습활동이 아니다')
})

test('활동 블록이 본론 절반 이상에 있고, 답은 접혀 있다', () => {
  const acts = (html.match(/class="act act--/g) ?? []).length
  assert(acts * 2 >= content.main_lesson.blocks.length, `활동이 ${acts}/${content.main_lesson.blocks.length} 블록뿐이다`)
  // reveal 은 details 안에 있어야 한다 — 답하기 전에 열려 있으면 활동이 아니다
  const openReveals = (html.match(/<details class="act__reveal" open/g) ?? []).length
  assert(openReveals === 0, '활동의 답이 처음부터 열려 있다')
})

test('도형은 스펙에서 결정론적으로 그려지고 접근성 설명이 붙는다', () => {
  for (const f of content.figures) {
    assert(html.includes(`data-figure="${f.id}"`), `도형 ${f.id} 가 없다`)
    assert(html.includes(`<desc id="fig-${f.id}-d">`), `도형 ${f.id} 에 desc 가 없다`)
  }
  assert(!html.includes('user-scalable=no'), '확대 금지 viewport 가 남아 있다 (WCAG 위반)')
})

test('필기 런타임이 인라인으로 박혀 있다', () => {
  assert(html.includes('ONPAR_INK'), '필기 런타임이 없다')
  assert(html.includes('getCoalescedEvents'), 'ProMotion 샘플 수집이 빠졌다')
  assert(html.includes("pointerType === 'pen'"), '팜 리젝션이 빠졌다')
})

test('섹션마다 아이콘이 붙는다 (Untitled UI)', () => {
  const svgs = (html.match(/class="ico"/g) ?? []).length
  assert(svgs >= 11 + 3, `아이콘이 ${svgs}개뿐이다 (섹션 11 + 문서요소 3 이상)`)
  assert(html.includes('stroke="currentColor"'), '아이콘이 색을 상속하지 않는다')
})

test('일상 비유가 정의보다 먼저 나온다 (설명 사다리 ①단)', () => {
  const analogyPos = html.indexOf('class="analogy"')
  const summaryPos = html.indexOf('class="p"')
  assert(analogyPos > 0, '일상 비유 블록이 없다')
  assert(analogyPos < summaryPos, '비유가 설명보다 뒤에 있다 — 독자가 걸어둘 못이 없어진다')
})

test('용어 풀이가 1번 섹션에 들어간다', () => {
  assert(html.includes('class="glossary"'), '용어 풀이가 없다')
  for (const g of content.glossary) assert(html.includes(esc(g.term)), `용어 누락: ${g.term}`)
})

test('파르의 말이 지정한 섹션에 배치된다', () => {
  const count = (html.match(/class="par"/g) ?? []).length
  assert(count === content.guide_notes.length, `파르 블록이 ${count}개 (${content.guide_notes.length}개여야 함)`)
  for (const g of content.guide_notes) {
    const secStart = html.indexOf(`data-section="${g.section}"`)
    const secEnd = html.indexOf('<section', secStart + 1)
    const section = html.slice(secStart, secEnd === -1 ? undefined : secEnd)
    assert(section.includes(esc(g.note).slice(0, 30)), `파르의 말이 ${g.section} 섹션 밖에 있다`)
  }
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
