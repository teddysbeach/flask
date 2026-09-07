// 학습 상호작용 런타임을 실제 Chromium 에서 돌려 본다.
//   node --experimental-strip-types server/tests/interact.browser.test.ts
//
// 렌더 테스트는 마크업만 본다. 여기서는 "고르기 전엔 답이 안 열리는가", "고른 오답에 맞는
// 피드백만 뜨는가", "슬라이더가 곡선 위를 달리는가" 를 브라우저가 답한다.
// V3 평가: "외형은 interactive worksheet 인데 데이터 모델은 static document" 에 대한 검증.
//
// Playwright 는 전역 설치본을 쓴다 (이 저장소는 node_modules 를 두지 않는다).

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'
import { execSync } from 'node:child_process'
import { validateWorksheet } from '../supabase/functions/_shared/validate.ts'
import { renderWorksheet } from '../supabase/functions/_shared/render.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = process.env.ONPAR_SCRATCH ?? resolve(HERE, '../../.scratch')
mkdirSync(OUT, { recursive: true })

function loadPlaywright(): any {
  try { return createRequire(import.meta.url)('playwright') } catch { /* 전역으로 */ }
  const root = execSync('npm root -g', { encoding: 'utf8' }).trim()
  return createRequire(import.meta.url)(resolve(root, 'playwright'))
}

const CTX = { worksheetId: 'w-browser', quizItemIds: ['q1', 'q2', 'q3', 'q4', 'q5'] }
function renderFixture(name: string): string {
  const raw = JSON.parse(readFileSync(resolve(HERE, `fixtures/worksheet-${name}.json`), 'utf8'))
  const html = renderWorksheet(validateWorksheet(raw), CTX)
  const file = resolve(OUT, `${name}.browser.html`)
  writeFileSync(file, html)
  return pathToFileURL(file).href
}

let passed = 0
const failures: string[] = []
async function test(name: string, fn: () => Promise<void>) {
  try { await fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(name); console.log(`  FAIL ${name}\n    ${(e as Error).message}`) }
}
const assert = (cond: unknown, msg: string) => { if (!cond) throw new Error(msg) }

const { chromium } = loadPlaywright()
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 900, height: 1200 } })
const consoleErrors: string[] = []
page.on('pageerror', (e: Error) => consoleErrors.push(e.message))
page.on('console', (m: any) => { if (m.type() === 'error') consoleErrors.push(m.text()) })

console.log('\n▸ 상호작용 런타임 (Chromium)')

await page.goto(renderFixture('calculus'))

await test('런타임이 오류 없이 뜬다', async () => {
  assert(consoleErrors.length === 0, `콘솔 오류: ${consoleErrors.join(' | ')}`)
  assert(await page.evaluate(() => typeof (globalThis as any).ONPAR_LEARN === 'object'), 'ONPAR_LEARN 이 없다')
})

await test('첫 활동(hook): 고르기 전에는 답이 열리지 않는다', async () => {
  const hook = page.locator('#sec-2 .act').first()
  await hook.locator('details.act__reveal summary').click()
  await page.waitForTimeout(50)
  assert(!(await hook.locator('details.act__reveal').evaluate((d: HTMLDetailsElement) => d.open)), '고르기 전에 답이 열렸다')
  assert(await hook.evaluate((el: HTMLElement) => el.classList.contains('is-nudge')), '안내(nudge)가 뜨지 않았다')
})

await test('첫 활동(hook): 고르면 답이 열리고 응답이 기록된다', async () => {
  const hook = page.locator('#sec-2 .act').first()
  await hook.locator('input[type="radio"]').nth(1).check()
  await page.waitForTimeout(50)
  assert(await hook.locator('details.act__reveal').evaluate((d: HTMLDetailsElement) => d.open), '고른 뒤에도 답이 닫혀 있다')
  const id = await hook.getAttribute('data-response-id')
  const rec = await page.evaluate((id: string) => (globalThis as any).ONPAR_RESPONSES[id], id)
  assert(rec && rec.type === 'choice' && rec.choice === 1, `응답 기록이 없다: ${JSON.stringify(rec)}`)
})

await test('선택형 문제: 오답을 제출하면 그 오답에 맞는 피드백만 뜬다', async () => {
  const item = page.locator('.quiz__item[data-response-kind="choice"]').first()
  const answer = Number(await item.getAttribute('data-answer'))
  const labels = item.locator('label.act__opt')
  const n = await labels.count()
  // 피드백이 붙은 오답을 하나 고른다
  let wrongIdx = -1
  for (let i = 0; i < n; i++) {
    if (i !== answer && (await labels.nth(i).getAttribute('data-feedback'))) { wrongIdx = i; break }
  }
  assert(wrongIdx >= 0, '피드백이 붙은 오답 선택지가 없다')
  // 제출 전에는 답이 안 열린다
  await item.locator('details.quiz__a summary').click()
  await page.waitForTimeout(50)
  assert(!(await item.locator('details.quiz__a').evaluate((d: HTMLDetailsElement) => d.open)), '제출 전에 답이 열렸다')

  await labels.nth(wrongIdx).locator('input').check()
  assert(!(await item.locator('details.quiz__a').evaluate((d: HTMLDetailsElement) => d.open)), '고르기만 했는데 답이 열렸다 (제출이 있어야 한다)')
  await item.locator('[data-submit]').click()
  await page.waitForTimeout(50)
  assert(await labels.nth(wrongIdx).evaluate((el: HTMLElement) => el.classList.contains('is-wrong')), '오답 표시가 없다')
  assert(await labels.nth(answer).evaluate((el: HTMLElement) => el.classList.contains('is-correct')), '정답 표시가 없다')
  const fb = item.locator('[data-feedback-slot]')
  assert(await fb.evaluate((el: HTMLElement) => !el.hidden), '피드백이 숨겨져 있다')
  const expected = await labels.nth(wrongIdx).getAttribute('data-feedback')
  assert((await fb.textContent())!.includes(expected!.slice(0, 20)), '고른 오답의 피드백이 아니다')
  assert(await item.locator('details.quiz__a').evaluate((d: HTMLDetailsElement) => d.open), '제출 후 답이 안 열렸다')
  const rec = await page.evaluate((id: string) => (globalThis as any).ONPAR_RESPONSES[id], (await item.getAttribute('data-response-id'))!)
  assert(rec && rec.correct === false, `오답 채점이 기록되지 않았다: ${JSON.stringify(rec)}`)
})

await test('서술형 문제: 시도 체크 전에는 답이 열리지 않는다', async () => {
  const item = page.locator('.quiz__item[data-response-kind="written"]').first()
  await item.locator('details.quiz__a summary').click()
  await page.waitForTimeout(50)
  assert(!(await item.locator('details.quiz__a').evaluate((d: HTMLDetailsElement) => d.open)), '시도 전에 답이 열렸다')
  await item.locator('input[data-attempted]').check()
  await item.locator('details.quiz__a summary').click()
  await page.waitForTimeout(50)
  assert(await item.locator('details.quiz__a').evaluate((d: HTMLDetailsElement) => d.open), '시도 체크 후에도 답이 안 열린다')
})

await test('할선 슬라이더: 두 번째 점이 곡선 위를 달리고 h<0 도 된다', async () => {
  const fig = page.locator('figure[data-interactive="plot"]').first()
  const d = await fig.evaluate((el: HTMLElement) => ({ ...el.dataset }))
  const pad = +d.pad, x0 = +d.x0, x1 = +d.x1, yMin = +d.ymin, yMax = +d.ymax, a = +d.a
  const sx = (x: number) => pad + ((x - x0) / (x1 - x0)) * (600 - pad * 2)
  const sy = (y: number) => 340 - pad - ((y - yMin) / (yMax - yMin)) * (340 - pad * 2)
  const slider = fig.locator('.fig__slider')
  const before = await fig.locator('.fig-secant').getAttribute('x2')

  await slider.evaluate((s: HTMLInputElement) => { s.value = '-1'; s.dispatchEvent(new Event('input', { bubbles: true })) })
  await page.waitForTimeout(30)
  const pt = fig.locator('.fig-pt--secant').nth(1)
  const cx = Number(await pt.getAttribute('cx')), cy = Number(await pt.getAttribute('cy'))
  const b = a - 1
  assert(Math.abs(cx - sx(b)) < 0.02 && Math.abs(cy - sy(b * b)) < 0.02,
    `점이 곡선 밖에 있다: (${cx}, ${cy}) vs (${sx(b).toFixed(2)}, ${sy(b * b).toFixed(2)})`)
  const after = await fig.locator('.fig-secant').getAttribute('x2')
  assert(before !== after, '할선이 움직이지 않았다')
  const readout = await fig.locator('.fig__readout').textContent()
  const m = (a * a - b * b) / 1   // (f(a)-f(b))/(a-b)
  assert(readout!.includes(m.toFixed(2)), `기울기 표시가 틀렸다: ${readout} (기대 ${m.toFixed(2)})`)
  assert(readout!.includes('-1.00'), 'h 가 음수로 표시되지 않았다')

  // h=0 은 정의되지 않는다 — 0 을 대입하지 않고 ±0.01 로 비껴간다
  await slider.evaluate((s: HTMLInputElement) => { s.value = '0'; s.dispatchEvent(new Event('input', { bubbles: true })) })
  await page.waitForTimeout(30)
  const r0 = await fig.locator('.fig__readout').textContent()
  assert(!/NaN|Infinity/.test(r0!), `h=0 에서 깨졌다: ${r0}`)
  assert(r0!.includes('양쪽'), 'h≈0 근처에서 양쪽 접근 안내가 없다')
})

await page.goto(renderFixture('double-slit'))

await test('경로정보 슬라이더: 간섭무늬가 연속적으로 사라진다 (스위치가 아니다)', async () => {
  const fig = page.locator('figure[data-interactive="distribution"]').first()
  const path = () => fig.locator('.fig-area').last().getAttribute('d')
  const d0 = await path()
  const set = async (v: string) => {
    await fig.locator('.fig__slider').evaluate((s: HTMLInputElement, v: string) => { s.value = v; s.dispatchEvent(new Event('input', { bubbles: true })) }, v)
    await page.waitForTimeout(30)
  }
  await set('0.5'); const dHalf = await path()
  await set('1'); const d1 = await path()
  assert(d0 !== dHalf && dHalf !== d1, '슬라이더에 따라 분포가 바뀌지 않는다')
  const vis = await fig.locator('.fig__readout').textContent()
  assert(/0\s*%/.test(vis!), `경로정보 1 에서 가시도가 0% 가 아니다: ${vis}`)
})

await test('예측 이유 칸: 체크하면 시도로 기록된다', async () => {
  const reason = page.locator('#sec-2 [data-response-kind="written"]').first()
  await reason.locator('input[data-attempted]').check()
  await page.waitForTimeout(30)
  const id = await reason.getAttribute('data-response-id')
  const rec = await page.evaluate((id: string) => (globalThis as any).ONPAR_RESPONSES[id], id)
  assert(rec && rec.type === 'attempt', `이유 쓰기 시도가 기록되지 않았다: ${JSON.stringify(rec)}`)
})

await test('맥락 노트는 접혀 있고 펼칠 수 있다 (있을 때)', async () => {
  const fold = page.locator('#sec-4 details.context')
  if (await fold.count() === 0) { console.log('    (이 학습지엔 맥락 노트가 없어요)'); return }
  assert(!(await fold.evaluate((d: HTMLDetailsElement) => d.open)), '맥락 노트가 처음부터 펼쳐져 있다')
  await fold.locator('summary').click()
  assert(await fold.evaluate((d: HTMLDetailsElement) => d.open), '펼쳐지지 않는다')
})

await test('나가기 전에: 틀린 문장 고르기가 고르기 전엔 잠겨 있다', async () => {
  const act = page.locator('#sec-6 .act--decide').first()
  await act.locator('details.act__reveal summary').click()
  await page.waitForTimeout(50)
  assert(!(await act.locator('details.act__reveal').evaluate((d: HTMLDetailsElement) => d.open)), '고르기 전에 답이 열렸다')
  await act.locator('input[type="radio"]').first().check()
  await page.waitForTimeout(50)
  assert(await act.locator('details.act__reveal').evaluate((d: HTMLDetailsElement) => d.open), '고른 뒤에도 답이 닫혀 있다')
})

await test('두 학습지를 지나는 동안 콘솔 오류가 없다', async () => {
  assert(consoleErrors.length === 0, `콘솔 오류: ${consoleErrors.join(' | ')}`)
})

await browser.close()
console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
