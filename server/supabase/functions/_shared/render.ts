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
import { renderFigure, FIGURE_CSS } from './figures.ts'
import type { WorksheetContent, InlineNode, RenderContext, Activity } from './worksheet-types.ts'

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

/** 콜아웃. 남은 용도는 '흔한 실수' 하나뿐이라 종류를 고정한다. */
const callout = (label: string, body: string) =>
  `<div class="callout callout--caution">` +
  `<p class="callout__label">${icon('warning', 16)}${esc(label)}</p>${body}</div>`

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
//
// 필기 여백(.ink-space) 규칙: 인지 명령이 붙은 자리에만 있다.
//   act__prompt(활동·이유 쓰기) · quiz__q(서술형 문제) · fig__task(그림 위 과제) · reflect__prompt(나가기 전에)
// 빈 종이는 학습활동이 아니다. 프롬프트 없이 여백만 두는 일은 없다(테스트가 검사).
const NEXT_STEP_HINT: Record<string, string> = {
  easier: '이게 막히면 먼저', same: '같은 난이도', harder: '한 단계 더 깊게',
}

const RENDERERS: ((c: WorksheetContent, ctx: RenderContext) => string)[] = [
  // ① 문제 제시 — 개념 이름이 아니라 아직 못 푸는 상황. 활동도 필기칸도 없다. 질문 하나가 전부다.
  (c) => [
    p(c.problem.situation),
    `<div class="problem"><p class="problem__q">${esc(c.problem.question)}</p>` +
    `<p class="problem__why">${esc(c.problem.why_it_matters)}</p></div>`,
    `<p class="h3">이 학습지를 마치면</p>`,
    ul(c.problem.objectives),
  ].join(''),

  // ② 예측 — 설명을 하나도 읽기 전에 고르고, 왜 골랐는지 한 줄 적는다.
  //    이유를 적어야 ⑥에서 자기 생각과 비교할 것이 남는다.
  (c) => {
    const hook = renderActivity(c.predict.hook, { prefix: 'hook' })   // id 순서 = 문서 순서
    const rid = nextResponseId('reason')
    return [
      hook,
      `<div class="act act--explain" data-response-id="${rid}" data-response-kind="written">` +
      `<p class="act__label">${icon('activity', 15)}왜 그렇게 골랐나요</p>` +
      `<p class="act__prompt">${esc(c.predict.reasoning_prompt)}</p>${inkSpace('sm')}` +
      `<label class="act__attempt"><input type="checkbox" data-attempted> 내 생각을 적었어요</label></div>`,
    ].join('')
  },

  // ③ 관찰 — 예측을 시험할 증거. 무엇을 봐야 하는지 짚어 주고, 예측과 비교하게 한다.
  (c) => {
    const figById = new Map(c.figures.map((f) => [f.id, f]))
    return [
      p(c.observe.intro),
      c.observe.figure && figById.has(c.observe.figure) ? renderFigure(figById.get(c.observe.figure)!) : '',
      c.observe.example ? renderExample(c.observe.example) : '',
      `<p class="h3">여기를 보세요</p>`,
      `<ol class="notice">${c.observe.notice.map((n) => `<li>${esc(n)}</li>`).join('')}</ol>`,
      renderActivity(c.observe.compare, { prefix: 'compare' }),
    ].join('')
  },

  // ④ 개념 — 비유 → 블록(설명 → 표상 → 예시 → 활동 → 흔한 실수) → 용어 → 접힌 맥락 노트.
  //    활동 없는 설명은 절반을 넘지 못한다(검증기).
  (c) => {
    const figById = new Map(c.figures.map((f) => [f.id, f]))
    const blocks = c.concept.blocks.map((b) => [
      `<p class="h3">${esc(b.heading)}</p>`,
      p(b.body),
      b.figure && figById.has(b.figure) ? renderFigure(figById.get(b.figure)!) : '',
      b.example ? renderExample(b.example) : '',
      b.activity ? renderActivity(b.activity) : '',
      b.common_mistake ? callout('흔한 실수', `<p class="p">${esc(b.common_mistake)}</p>`) : '',
    ].join('')).join('')
    const glossary = `<p class="h3">${icon('glossary', 18)}먼저 풀고 갈 말들</p>` +
      `<dl class="glossary">${c.glossary.map((g) => `<dt>${esc(g.term)}</dt><dd>${esc(g.plain)}</dd>`).join('')}</dl>`
    const note = c.concept.context_note
    const context = note
      ? `<details class="context"><summary class="context__summary">${icon('context', 15)}이게 어디서 왔는지 (짧은 맥락)</summary>` +
        `<div class="context__body">${p(note.text)}${note.facts.length
          ? `<ul class="timeline">${note.facts.map((t) => {
              const badge = t.confidence === 'high' ? ''
                : `<span class="conf conf--${t.confidence}">${esc(CONF_LABEL[t.confidence])}</span>`
              return `<li><span class="timeline__when">${esc(t.when)}</span>` +
                     `<p class="timeline__what">${esc(t.what)}${badge}</p></li>`
            }).join('')}</ul>`
          : ''}</div></details>`
      : ''
    return `<p class="analogy">${esc(c.concept.analogy)}</p>${blocks}${glossary}${context}`
  },

  // ⑤ 연습 — 선택형은 고른 오답에 맞는 피드백만, 서술형은 시도 후에 답. 그 뒤 확장 과제(선택).
  (c, ctx) => {
    const quiz = `<ol class="quiz">${c.practice.quiz.map((q, i) => {
      const id = ctx.quizItemIds[i] ?? ''
      const rid = nextResponseId('quiz')
      const norm = (t: string) => t.replace(/[\s.,!?()'"]/g, '')
      const answerIdx = q.choices ? q.choices.findIndex((ch) => norm(ch) === norm(q.answer)) : -1
      const fbFor = (ch: string) => q.misconceptions.find((m) => norm(ch).includes(norm(m.wrong).slice(0, 8)) || norm(m.wrong).includes(norm(ch).slice(0, 8)))?.why
      const choices = q.choices
        ? `<div class="quiz__choices" role="radiogroup">${q.choices.map((ch, j) => {
            const fb = fbFor(ch)
            return `<label class="act__opt"${fb ? ` data-feedback="${esc(fb)}"` : ''}>` +
              `<input type="radio" name="${rid}" value="${esc(ch)}"><span class="act__key">${String.fromCharCode(9312 + j)}</span><span>${esc(ch)}</span></label>`
          }).join('')}</div><p class="act__fb" data-feedback-slot hidden></p>` +
          `<button type="button" class="quiz__submit" data-submit>제출</button>`
        : `${inkSpace(q.kind === 'explain' ? 'md' : 'sm')}<label class="act__attempt"><input type="checkbox" data-attempted> 내 답을 적었어요</label>`
      return `<li class="quiz__item" data-quiz-id="${esc(id)}" data-response-id="${rid}" data-response-kind="${q.choices ? 'choice' : 'written'}"${answerIdx >= 0 ? ` data-answer="${answerIdx}"` : ''}>
        <p class="quiz__q">${esc(q.question)}</p>
        ${choices}
        <details class="quiz__a">
          <summary>${icon('info', 15)}${q.choices ? '제출하면 열려요' : '적고 나서 열기'}</summary>
          <div class="quiz__a-body">
            <p><span class="quiz__a-label">정답</span>${esc(q.answer)}</p>
            <p>${esc(q.explanation)}</p>
            ${q.misconceptions.length && !q.choices ? `<div class="quiz__mis"><p class="quiz__a-label">이렇게 답했다면</p><ul>${
              q.misconceptions.map((m) => `<li><strong>${esc(m.wrong)}</strong> — ${esc(m.why)}</li>`).join('')}</ul></div>` : ''}
          </div>
        </details>
      </li>`
    }).join('')}</ol>`
    const extended = c.practice.extended.length
      ? `<p class="h3">더 해보기 (선택)</p><div class="cards">${c.practice.extended.map((t) => `
          <div class="card">
            <p class="card__title">${esc(t.title)}</p>
            <p class="card__why">${esc(t.detail)}</p>
            <p class="card__hint">예상 ${t.estimated_minutes}분</p>
          </div>`).join('')}</div>`
      : ''
    return quiz + extended
  },

  // ⑥ 나가기 전에 — 처음 예측으로 돌아가고, 한 문장으로 말하고, 틀린 문장을 골라낸다.
  //    완료감이 아니라 증거를 남기는 단계라 필기칸 두 개는 전부 프롬프트 뒤에만 있다.
  (c) => [
    `<div class="reflect"><p class="reflect__prompt">${icon('pen', 16)}${esc(c.exit_ticket.revisit)}</p>${inkSpace('md')}</div>`,
    `<div class="reflect"><p class="reflect__prompt">${icon('pen', 16)}${esc(c.exit_ticket.one_sentence)}</p>${inkSpace('sm')}</div>`,
    renderActivity(c.exit_ticket.misconception_check, { prefix: 'exit' }),
    `<p class="h3">스스로 점검</p>`,
    ul(c.exit_ticket.self_check, 'checklist'),
    `<p class="h3">내일 해볼 것</p>`,
    `<p class="p">${esc(c.exit_ticket.apply_tomorrow)}</p>`,
    `<div class="cards">${c.exit_ticket.next_steps.map((n) => `
      <div class="card">
        <p class="card__title">${esc(n.title)}</p>
        <p class="card__why">${esc(n.why)}</p>
        <p class="card__hint">${NEXT_STEP_HINT[n.difficulty_delta] ?? ''}</p>
      </div>`).join('')}</div>`,
  ].join(''),
]

const ACTIVITY_LABEL: Record<string, string> = {
  predict: '먼저 예측해 보세요', decide: '골라 보세요', compute: '직접 계산해 보세요',
  draw: '그림에 표시해 보세요', explain: '한 문장으로 써 보세요',
}

/**
 * 활동. 설명 뒤에 학생이 결정·예측·계산·표시하게 만든다.
 * reveal 은 접어 둔다 — 답하기 전에 열면 활동이 아니다.
 */
let responseSeq = 0
const nextResponseId = (prefix: string) => `${prefix}-${++responseSeq}`

function renderActivity(a: Activity, opts: { prefix: string; feedbackByOption?: (string | undefined)[] } = { prefix: 'act' }): string {
  const rid = nextResponseId(opts.prefix)
  const choice = a.kind === 'predict' || a.kind === 'decide'
  const written = !choice
  const opts_ = a.options
    ? `<div class="act__options" role="radiogroup">${a.options.map((o, i) => {
        const fb = opts.feedbackByOption?.[i]
        return `<label class="act__opt"${fb ? ` data-feedback="${esc(fb)}"` : ''}>` +
          `<input type="radio" name="${rid}" value="${esc(o)}"><span class="act__key">${String.fromCharCode(9312 + i)}</span><span>${esc(o)}</span></label>`
      }).join('')}</div>` +
      `<p class="act__fb" data-feedback-slot hidden></p>`
    : ''
  const ink = a.kind === 'compute' || a.kind === 'draw' || a.kind === 'explain'
    ? inkSpace(a.kind === 'explain' ? 'sm' : 'md') : ''
  // 채점은 못 하지만 시도했는지는 기록한다. 시도 전에는 답이 열리지 않는다.
  const attempted = written
    ? `<label class="act__attempt"><input type="checkbox" data-attempted> 내 답을 적었어요</label>` : ''
  return `<div class="act act--${a.kind}" data-response-id="${rid}" data-response-kind="${choice ? 'choice' : 'written'}">` +
    `<p class="act__label">${icon('activity', 15)}${esc(ACTIVITY_LABEL[a.kind])}</p>` +
    `<p class="act__prompt">${esc(a.prompt)}</p>${opts_}${ink}${attempted}` +
    `<details class="act__reveal"><summary>${icon('info', 14)}${choice ? '고르면 열려요' : '적고 나서 열기'}</summary>` +
    `<div class="act__reveal-body">${esc(a.reveal)}</div></details></div>`
}

/** 섹션 키 → 아이콘 이름. Untitled UI 아이콘을 섹션 제목 앞에 놓는다. */
const SECTION_ICON: Record<string, string> = {
  problem: 'secProblem', predict: 'secPredict', observe: 'secObserve',
  concept: 'secConcept', practice: 'secPractice', exit_ticket: 'secExitTicket',
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

  responseSeq = 0   // 결정론: 렌더마다 id 가 같은 순서로 나와야 골든 파일이 맞는다

  // 6단계는 전부 핵심 경로다. 접히는 것은 개념 안의 맥락 노트뿐, 섹션 자체는 접지 않는다.
  const sections = SECTIONS.map((s, i) => {
    const num = String(i + 1).padStart(2, '0')
    const body = tidy(RENDERERS[i](c, ctx))
    const notes = (notesBySection.get(s.key) ?? []).map(guideNote).join('')
    const head = `<header class="sec__head">` +
      `<p class="sec__label">${icon(SECTION_ICON[s.key], 17)}<span class="sec__num">${num}</span></p>` +
      `<h2 class="sec__title">${esc(s.title)}</h2>` +
      `<p class="sec__lead">${esc(s.lead)}</p></header>`
    // 섹션 끝의 빈 필기칸은 없다. 빈 종이는 학습활동이 아니다.
    // 필기칸은 활동·그림 과제·문제·나가기 전에 성찰처럼 인지 명령이 붙은 자리에만 있다.
    return `<section class="sec sec--core" id="sec-${i + 1}" data-section="${s.key}">` +
      `${head}<div class="sec__body">${body}${notes}</div></section>`
  }).join('')

  const meta = [
    LEVEL_LABEL[c.level] ?? c.level,
    `본학습 ${c.time.core}분`,
    `연습 ${c.time.practice}분`,
    `선택 과제 ${c.time.optional}분`,
  ].map((m) => `<span>${esc(m)}</span>`).join('')
  const assumes = `<p class="sheet__assumes"><span class="sheet__assumes-label">이 학습지는 이걸 안다고 봐요</span>${
    c.assumes.map((a) => `<span>${esc(a)}</span>`).join('')}</p>`

  return `<!doctype html>
<html lang="ko" data-theme="${ctx.theme ?? 'light'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(c.title)}</title>
<style>${TOKENS_CSS}${WORKSHEET_CSS}${FIGURE_CSS}</style>
</head>
<body>
<div class="sheet-scaler">
<article class="sheet" data-worksheet-id="${esc(ctx.worksheetId)}" data-schema-version="${c.schema_version}">
<header class="sheet__header">
<p class="sheet__eyebrow">${icon('secConcept', 16)}ONPAR 학습지</p>
<h1 class="sheet__title">${esc(c.title)}</h1>
<p class="sheet__one-liner">${esc(c.one_liner)}</p>
<div class="sheet__meta">${meta}</div>
${assumes}
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
