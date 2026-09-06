// 학습지 자가점검. 모든 픽스처를 분야별로 채점한다.
//   node --experimental-strip-types server/tests/selfcheck.ts
//
// 목적은 "통과/실패" 가 아니라 "분야가 바뀌어도 이 구조와 목소리가 버티는가" 를 보는 것이다.
// 컴퓨터 분야에서만 잘 되는 학습지 시스템은 학습지 시스템이 아니다.

import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateWorksheet, ValidationError } from '../supabase/functions/_shared/validate.ts'
import { voiceLint } from '../supabase/functions/_shared/voice-lint.ts'
import { pedagogyLint } from '../supabase/functions/_shared/pedagogy-lint.ts'
import { renderWorksheet } from '../supabase/functions/_shared/render.ts'
import { CATEGORIES } from '../supabase/functions/_shared/worksheet-types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const DIR = resolve(HERE, 'fixtures')

const CATEGORY_LABEL: Record<string, string> = {
  math: '수학', science: '물리·화학', cs: '컴퓨터', art: '미술·디자인',
  music: '음악', language: '언어', finance: '경제', history: '역사',
  business: '비즈니스', health: '건강', cooking: '요리', psychology: '심리',
}

/** 분야별로 자연스러운 예시 종류. 어긋나면 경고한다. */
const NATURAL_EXAMPLE: Record<string, string[]> = {
  math: ['calc', 'steps', 'scene'],
  science: ['scene', 'steps', 'compare'],
  cs: ['code', 'steps', 'compare'],
  art: ['compare', 'steps', 'scene'],
  music: ['steps', 'compare'],
  language: ['compare', 'scene'],
  finance: ['calc', 'compare'],
  history: ['scene', 'compare'],
  business: ['steps', 'compare', 'scene'],
  health: ['steps', 'scene'],
  cooking: ['steps', 'compare'],
  psychology: ['scene', 'steps'],
}

interface Row {
  file: string
  category: string
  title: string
  ok: boolean
  errors: string[]
  warnings: number
  activity: number
  far: number
  figures: number
  avgSentence: number
  glossary: number
  guideNotes: number
  hasAnalogy: boolean
  exampleKinds: string[]
  unnaturalExample: string[]
  quizCount: number
  htmlKb: number
  inkSpaces: number
}

const rows: Row[] = []

for (const file of readdirSync(DIR).filter((f) => f.endsWith('.json')).sort()) {
  const raw = JSON.parse(readFileSync(resolve(DIR, file), 'utf8'))
  const row: Partial<Row> = { file: basename(file, '.json'), errors: [] }

  let content: any
  try {
    content = validateWorksheet(raw)
  } catch (e) {
    rows.push({
      ...(row as Row), category: raw.category ?? '?', title: raw.title ?? '?',
      ok: false, errors: e instanceof ValidationError ? e.issues.slice(0, 5) : [String(e)],
      warnings: 0, activity: 0, far: 0, figures: 0, avgSentence: 0, glossary: 0, guideNotes: 0, hasAnalogy: false,
      exampleKinds: [], unnaturalExample: [], quizCount: 0, htmlKb: 0, inkSpaces: 0,
    })
    continue
  }

  const voice = voiceLint(content)
  const ped = pedagogyLint(content)
  const kinds = content.main_lesson.blocks.map((b: any) => b.example?.kind).filter(Boolean)
  const natural = NATURAL_EXAMPLE[content.category] ?? []
  const unnatural = [...new Set(kinds.filter((k: string) => !natural.includes(k)))] as string[]

  let html = ''
  const errors: string[] = [
    ...voice.errors.map((e) => `[말투] ${e.path}: ${e.detail}`),
    ...ped.errors.map((e) => `[학습설계] ${e.path}: ${e.detail}`),
  ]
  try {
    html = renderWorksheet(content, {
      worksheetId: 'sc', quizItemIds: content.quiz.map((_: unknown, i: number) => `q${i}`), theme: 'light',
    })
  } catch (e) {
    errors.push(`[렌더] ${String(e)}`)
  }

  rows.push({
    file: basename(file, '.json'),
    category: content.category,
    title: content.title,
    ok: errors.length === 0,
    errors,
    warnings: voice.warnings.length + ped.warnings.length,
    activity: Math.round(ped.metrics.activityRatio * 100),
    far: ped.metrics.farTransfer,
    figures: ped.metrics.figures,
    avgSentence: voice.avgSentenceChars,
    glossary: content.glossary.length,
    guideNotes: content.guide_notes.length,
    hasAnalogy: Boolean(content.what_we_learn.analogy),
    exampleKinds: [...new Set(kinds)] as string[],
    unnaturalExample: unnatural,
    quizCount: content.quiz.length,
    htmlKb: Math.round(html.length / 1024),
    inkSpaces: (html.match(/class="ink-space"/g) ?? []).length,
  })
}

// ── 출력 ────────────────────────────────────────────────────────────────
const pad = (s: string, n: number) => {
  const w = [...s].reduce((a, ch) => a + (/[가-힣ㄱ-ㅎ·]/.test(ch) ? 2 : 1), 0)
  return s + ' '.repeat(Math.max(0, n - w))
}

console.log('\n━━━ ONPAR 학습지 자가점검 ━━━\n')
console.log(pad('분야', 14) + pad('제목', 34) + pad('검사', 6) + pad('활동', 6) + pad('far', 5) +
            pad('도형', 6) + pad('평균', 6) + pad('용어', 6) + pad('파르', 6) + pad('예시', 20) + 'HTML')
console.log('─'.repeat(112))

for (const r of rows) {
  console.log(
    pad(CATEGORY_LABEL[r.category] ?? r.category, 14) +
    pad(r.title.slice(0, 14), 34) +
    pad(r.ok ? 'OK' : `✕${r.errors.length}`, 6) +
    pad(`${r.activity}%`, 6) +
    pad(String(r.far), 5) +
    pad(String(r.figures), 6) +
    pad(`${r.avgSentence}자`, 6) +
    pad(String(r.glossary), 6) +
    pad(String(r.guideNotes), 6) +
    pad(r.exampleKinds.join(',') || '-', 20) +
    `${r.htmlKb}KB`,
  )
}

console.log()
const failed = rows.filter((r) => !r.ok)
for (const r of failed) {
  console.log(`✕ ${r.file}`)
  for (const e of r.errors) console.log(`    ${e}`)
}

// ── 종합 ────────────────────────────────────────────────────────────────
const covered = new Set(rows.map((r) => r.category))
const missing = CATEGORIES.filter((c) => !covered.has(c))
const avgAll = Math.round(rows.reduce((a, r) => a + r.avgSentence, 0) / (rows.length || 1))

console.log('── 종합 ──')
console.log(`학습지 ${rows.length}장 · 통과 ${rows.length - failed.length} · 실패 ${failed.length}`)
console.log(`평균 문장 길이 ${avgAll}자 (목표 60자 이하)`)
console.log(`분야 커버리지 ${covered.size}/${CATEGORIES.length} — 남은 분야: ${missing.map((c) => CATEGORY_LABEL[c]).join(', ') || '없음'}`)

const unnatural = rows.filter((r) => r.unnaturalExample.length)
if (unnatural.length) {
  console.log('\n예시 종류가 분야와 어긋남:')
  for (const r of unnatural) {
    console.log(`  ${CATEGORY_LABEL[r.category]}: ${r.unnaturalExample.join(', ')} (자연스러운 것: ${NATURAL_EXAMPLE[r.category].join(', ')})`)
  }
}

const warned = rows.filter((r) => r.warnings > 0)
if (warned.length) {
  console.log('\n말투 경고(실패는 아님):')
  for (const r of warned) console.log(`  ${CATEGORY_LABEL[r.category]}: ${r.warnings}건`)
}

console.log()
process.exit(failed.length ? 1 : 0)
