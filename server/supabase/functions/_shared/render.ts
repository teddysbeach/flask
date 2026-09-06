// 학습지 JSON → 완결형 HTML. 순수 함수.
//
// 두 가지 성질이 반드시 지켜져야 한다.
//   1. 결정론: 같은 입력 → 바이트 단위로 같은 출력.
//      깨지면 재렌더 시 DOM 이 미묘하게 달라져 기존 필기가 어긋난다. 사용자 데이터 손상급이다.
//   2. 이스케이프: LLM 이 만든 문자열은 전부 이스케이프한다. 예외 없음.
//      태그가 필요한 자리는 InlineNode 배열로 받아 렌더러가 태그를 만든다.

import { TOKENS_CSS } from './tokens.css.ts'
import { WORKSHEET_CSS } from './worksheet-css.ts'
import { INK_RUNTIME_JS } from './ink-runtime.g.ts'
import { SECTIONS } from './worksheet-types.ts'
import { icon } from './icons.g.ts'
import type { WorksheetContent, InlineNode, RenderContext } from './worksheet-types.ts'

/** HTML 텍스트 이스케이프. 속성값까지 안전하도록 따옴표도 처리한다. */
export function esc(s: string): string {
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

/** InlineNode 배열 → 태그. 값은 언제나 이스케이프하고 태그는 우리가 고른 것만 쓴다. */
export function inlineToHtml(nodes: InlineNode[]): string {
  return nodes.map((n) => {
    const v = esc(n.value)
    switch (n.type) {
      case 'bold': return `<strong>${v}</strong>`
      case 'em':   return `<em>${v}</em>`
      case 'code': return `<code>${v}</code>`
      default:     return v
    }
  }).join('')
}

const p = (nodes: InlineNode[]) => `<p class="p">${inlineToHtml(nodes)}</p>`
const ul = (items: string[], cls = 'list') =>
  `<ul class="${cls}">${items.map((i) => `<li>${esc(i)}</li>`).join('')}</ul>`

const inkSpace = (size: 'sm' | 'md' | 'lg') =>
  `<div class="ink-space" data-ink-space="${size}"></div>`

const CALLOUT_ICON = { story: 'secRoleplay', tip: 'secProTips', caution: 'warning' } as const

const callout = (kind: 'story' | 'tip' | 'caution', label: string, body: string) =>
  `<div class="callout callout--${kind}">` +
  `<p class="callout__label">${icon(CALLOUT_ICON[kind], 16)}${esc(label)}</p>${body}</div>`

/** 파르(먼저 헤맨 사람)의 한마디. 선생이 아니라 옆자리 사람의 목소리다. */
const guideNote = (note: string) =>
  `<aside class="par"><span class="par__badge">${icon('guide', 20)}</span>` +
  `<div><span class="par__name">파르</span>` +
  `<p class="par__note">${esc(note)}</p></div></aside>`

/**
 * 예시는 분야마다 모양이 다르다. 전부 코드 블록으로 그리면
 * 수학 학습지에 미분 계산이 등폭 글꼴로 들어간다.
 */
function renderExample(ex: { kind: string; caption: string; body: string; language: string | null }): string {
  const cap = `<p class="example__caption">${esc(ex.caption)}</p>`
  const lines = ex.body.split('\n').map((l) => l.trim()).filter(Boolean)

  let inner: string
  switch (ex.kind) {
    case 'code':
      inner = `<pre class="ex-code"><code${ex.language ? ` class="lang-${esc(ex.language)}"` : ''}>${esc(ex.body)}</code></pre>`
      break
    case 'calc':
      // 계산은 줄마다 한 단계씩. 눈으로 따라가며 손으로 따라 쓰게 만든다.
      inner = `<ol class="ex-calc">${lines.map((l) => `<li>${esc(l)}</li>`).join('')}</ol>`
      break
    case 'steps':
      inner = `<ol class="ex-steps">${lines.map((l) => `<li>${esc(l)}</li>`).join('')}</ol>`
      break
    case 'compare': {
      // "전 | 후" 로 나눈다. 구분자가 없으면 한 덩어리로 둔다.
      const rows = lines.map((l) => {
        const i = l.indexOf('|')
        return i === -1
          ? `<div class="ex-compare__row"><span class="ex-compare__full">${esc(l)}</span></div>`
          : `<div class="ex-compare__row"><span class="ex-compare__before">${esc(l.slice(0, i).trim())}</span>` +
            `<span class="ex-compare__arrow" aria-hidden="true">→</span>` +
            `<span class="ex-compare__after">${esc(l.slice(i + 1).trim())}</span></div>`
      })
      inner = `<div class="ex-compare">${rows.join('')}</div>`
      break
    }
    default:  // scene
      inner = `<blockquote class="ex-scene">${lines.map((l) => `<p>${esc(l)}</p>`).join('')}</blockquote>`
  }
  return `<div class="example" data-example-kind="${esc(ex.kind)}">${cap}${inner}</div>`
}

const LEVEL_LABEL: Record<string, string> = {
  beginner: '입문', intermediate: '중급', advanced: '심화',
}
const CONF_LABEL: Record<string, string> = {
  high: '', medium: '확실하지 않음', low: '불확실',
}

// ── 섹션 렌더러 ──────────────────────────────────────────────────────────
// 인덱스 = 섹션 번호 - 1. SECTIONS 와 순서가 1:1로 맞아야 한다(테스트가 검사).
const RENDERERS: ((c: WorksheetContent, ctx: RenderContext) => string)[] = [
  // ① 무엇을 배우는가 — 비유가 정의보다 먼저 온다 (설명 사다리 ①단)
  (c) => [
    `<p class="analogy">${esc(c.what_we_learn.analogy)}</p>`,
    p(c.what_we_learn.summary),
    `<p class="h3">이 학습지를 마치면</p>`,
    ul(c.what_we_learn.objectives),
    `<p class="h3">${icon('glossary', 18)}먼저 풀고 갈 말들</p>`,
    `<dl class="glossary">${c.glossary.map((g) =>
      `<dt>${esc(g.term)}</dt><dd>${esc(g.plain)}</dd>`).join('')}</dl>`,
  ].join(''),

  // ② 이것이 생기기 전에는
  (c) => [
    p(c.before_and_need.world_before),
    callout('caution', '그때의 불편', ul(c.before_and_need.pain_points)),
    `<p class="h3">그래서 무엇이 필요했나</p>`,
    p(c.before_and_need.why_it_emerged),
  ].join(''),

  // ③ 먼저 보면 좋은 학습지 3개
  (c) => `<div class="cards">${c.prerequisites.map((q) => `
    <div class="card">
      <p class="card__title">${esc(q.title)}</p>
      <p class="card__why">${esc(q.why)}</p>
      <p class="card__hint">${esc(q.one_liner)}</p>
    </div>`).join('')}</div>`,

  // ④ 탄생 배경
  (c) => [
    `<ul class="timeline">${c.origin_story.timeline.map((t) => {
      const badge = t.confidence === 'high' ? ''
        : `<span class="conf conf--${t.confidence}">${esc(CONF_LABEL[t.confidence])}</span>`
      return `<li><span class="timeline__when">${esc(t.when)}</span>` +
             `<p class="timeline__what">${esc(t.what)}${badge}</p></li>`
    }).join('')}</ul>`,
    p(c.origin_story.narrative),
    c.origin_story.uncertainty_note
      ? callout('caution', '확실하지 않은 부분',
          `<p class="p">${esc(c.origin_story.uncertainty_note)}</p>`)
      : '',
  ].join(''),

  // ⑤ 상황극 & 예시
  (c) => [
    `<p class="scene">${esc(c.roleplay.scene)}</p>`,
    `<div class="dialogue">${c.roleplay.dialogue.map((d) => `
      <div class="dialogue__line">
        <span class="dialogue__speaker">${esc(d.speaker)}</span>
        <p class="dialogue__text">${esc(d.line)}</p>
      </div>`).join('')}</div>`,
    callout('story', '그래서 무슨 뜻이냐면', p(c.roleplay.takeaway)),
    // 가상 시나리오는 반드시 가상이라고 밝힌다. 검증기가 disclaimer 를 강제한다.
    c.roleplay.mode === 'hypothetical' && c.roleplay.disclaimer
      ? `<p class="card__hint">${esc(c.roleplay.disclaimer)}</p>`
      : '',
  ].join(''),

  // ⑥ 본론
  (c) => c.main_lesson.blocks.map((b) => [
    `<p class="h3">${esc(b.heading)}</p>`,
    p(b.body),
    b.example ? renderExample(b.example) : '',
    b.common_mistake
      ? callout('caution', '흔한 실수', `<p class="p">${esc(b.common_mistake)}</p>`)
      : '',
  ].join('')).join(''),

  // ⑦ 꿀팁
  (c) => c.pro_tips.map((t) =>
    callout('tip', t.tip, `<p class="p">${esc(t.why)}</p>`)).join(''),

  // ⑧ 질의 5개
  (c, ctx) => `<ol class="quiz">${c.quiz.map((q, i) => {
    // data-quiz-id 는 quiz_items.id. 복습 알림이 이 id 로 해당 문제에 스크롤한다.
    const id = ctx.quizItemIds[i] ?? ''
    return `<li class="quiz__item" data-quiz-id="${esc(id)}">
      <p class="quiz__q">${esc(q.question)}</p>
      ${q.choices ? `<ul class="quiz__choices">${q.choices.map((ch) => `<li>${esc(ch)}</li>`).join('')}</ul>` : ''}
      ${inkSpace(q.kind === 'explain' ? 'md' : 'sm')}
      <details class="quiz__a">
        <summary>${icon('info', 15)}정답 보기</summary>
        <div class="quiz__a-body">
          <p><span class="quiz__a-label">정답</span>${esc(q.answer)}</p>
          <p>${esc(q.explanation)}</p>
        </div>
      </details>
    </li>`
  }).join('')}</ol>`,

  // ⑨ 숙제 & 과제
  (c) => [
    c.homework.tasks.map((t) => `
      <div class="card">
        <p class="card__title">${esc(t.title)}</p>
        <p class="card__why">${esc(t.detail)}</p>
        <p class="card__hint">예상 ${t.estimated_minutes}분</p>
      </div>`).join(''),
    `<p class="card__hint">${esc(c.homework.submission_hint)}</p>`,
  ].join(''),

  // ⑩ 마무리 팁
  (c) => [
    `<p class="h3">이렇게 씁니다</p>`,
    ul(c.wrap_up.usage_examples),
    `<p class="h3">일상에 붙이기</p>`,
    p(c.wrap_up.daily_life_guide),
    `<p class="h3">스스로 점검</p>`,
    ul(c.wrap_up.checklist, 'checklist'),
  ].join(''),

  // ⑪ 다음 단계 제안
  (c) => `<div class="cards">${c.next_steps.map((n) => `
    <div class="card">
      <p class="card__title">${esc(n.title)}</p>
      <p class="card__why">${esc(n.why)}</p>
      <p class="card__hint">${n.difficulty_delta === 'harder' ? '한 단계 더 깊게' : '같은 난이도'}</p>
    </div>`).join('')}</div>`,
]

/** 섹션 키 → 아이콘 이름. Untitled UI 아이콘을 섹션 제목 앞에 놓는다. */
const SECTION_ICON: Record<string, string> = {
  what_we_learn: 'secWhatWeLearn', before_and_need: 'secBeforeAndNeed',
  prerequisites: 'secPrerequisites', origin_story: 'secOriginStory',
  roleplay: 'secRoleplay', main_lesson: 'secMainLesson', pro_tips: 'secProTips',
  quiz: 'secQuiz', homework: 'secHomework', wrap_up: 'secWrapUp', next_steps: 'secNextSteps',
}

/** 여러 줄에 걸친 템플릿 리터럴 때문에 생긴 공백을 걷어낸다(결정론적 출력을 위해). */
const tidy = (html: string) => html.replace(/>\s+</g, '><').replace(/\s{2,}/g, ' ').trim()

export function renderWorksheet(c: WorksheetContent, ctx: RenderContext): string {
  if (RENDERERS.length !== SECTIONS.length) {
    throw new Error(`섹션 렌더러 수(${RENDERERS.length})가 SECTIONS(${SECTIONS.length})와 다릅니다`)
  }

  // 파르의 말은 해당 섹션 본문 뒤, 필기 여백 앞에 놓는다.
  const notesBySection = new Map<string, string[]>()
  for (const g of c.guide_notes) {
    const list = notesBySection.get(g.section) ?? []
    list.push(g.note)
    notesBySection.set(g.section, list)
  }

  const sections = SECTIONS.map((s, i) => {
    const num = String(i + 1).padStart(2, '0')
    const body = tidy(RENDERERS[i](c, ctx))
    const notes = (notesBySection.get(s.key) ?? []).map(guideNote).join('')
    // 문제 섹션은 문제마다 필기 칸이 이미 있으므로 섹션 끝 여백을 붙이지 않는다.
    const trailing = s.key === 'quiz' ? '' : inkSpace(s.ink)
    return `<section class="sec" id="sec-${i + 1}" data-section="${s.key}">` +
      `<header class="sec__head">` +
      `<p class="sec__label">${icon(SECTION_ICON[s.key], 17)}<span class="sec__num">${num}</span></p>` +
      `<h2 class="sec__title">${esc(s.title)}</h2></header>` +
      `<div class="sec__body">${body}${notes}</div>${trailing}</section>`
  }).join('')

  const meta = [
    LEVEL_LABEL[c.level] ?? c.level,
    `약 ${c.estimated_minutes}분`,
    `문제 ${c.quiz.length}개`,
    `복습 ${c.quiz.length}회`,
  ].map((m) => `<span>${esc(m)}</span>`).join('')

  return `<!doctype html>
<html lang="ko" data-theme="${ctx.theme ?? 'light'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>${esc(c.title)}</title>
<style>${TOKENS_CSS}${WORKSHEET_CSS}</style>
</head>
<body>
<div class="sheet-scaler">
<article class="sheet" data-worksheet-id="${esc(ctx.worksheetId)}" data-schema-version="${c.schema_version}">
<header class="sheet__header">
<p class="sheet__eyebrow">${icon('secMainLesson', 16)}ONPAR 학습지</p>
<h1 class="sheet__title">${esc(c.title)}</h1>
<p class="sheet__one-liner">${esc(c.what_we_learn.one_liner)}</p>
<div class="sheet__meta">${meta}</div>
</header>
${sections}
<footer class="sheet__footer"><span>${esc(c.topic_normalized)}</span><span>ONPAR</span></footer>
<canvas class="ink-layer" id="ink-layer" aria-hidden="true"></canvas>
</article>
</div>
<script>${INK_RUNTIME_JS}</script>
</body>
</html>`
}
