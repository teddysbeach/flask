// 도형 렌더러. 구조화된 스펙 → 결정론적 인라인 SVG.
//
// LLM 은 SVG 를 쓰지 않는다. 스펙만 낸다. 그래야 렌더가 깨지지 않고 XSS 가 열리지 않는다.
// 모든 숫자는 소수 2자리로 고정해 같은 스펙이면 바이트 단위로 같은 SVG 가 나온다.
// 색은 currentColor 와 CSS 변수만 쓴다 — 디자인 시스템을 갈아끼워도 도형이 따라간다.

import type { Figure, FigureSpec } from './worksheet-types.ts'
import { ASSETS } from './assets.g.ts'
import { esc } from './render.ts'

const W = 600, H = 340
const f2 = (n: number) => (Math.round(n * 100) / 100).toFixed(2)

const FN: Record<string, (x: number) => number> = {
  'x^2': (x) => x * x,
  'x^3': (x) => x * x * x,
  'sin': (x) => Math.sin(x),
  'exp': (x) => Math.exp(x),
  'linear': (x) => 0.8 * x + 1,
  'abs': (x) => Math.abs(x),
}

/** plot 의 좌표계. SVG 와 런타임(worksheet-interact.js)이 같은 값을 써야 슬라이더가 곡선 위를 달린다. */
function plotFrame(s: Extract<FigureSpec, { kind: 'plot' }>) {
  const fn = FN[s.fn]
  const [x0, x1] = s.xRange
  const N = 80
  const xs = Array.from({ length: N + 1 }, (_, i) => x0 + ((x1 - x0) * i) / N)
  const ys = xs.map(fn)
  const yMin = Math.min(...ys, 0), yMax = Math.max(...ys, 0)
  const pad = 44
  return { fn, x0, x1, xs, ys, yMin, yMax, pad }
}

function plot(s: Extract<FigureSpec, { kind: 'plot' }>): string {
  const { fn, x0, x1, xs, ys, yMin, yMax, pad } = plotFrame(s)
  const sx = (x: number) => pad + ((x - x0) / (x1 - x0)) * (W - pad * 2)
  const sy = (y: number) => H - pad - ((y - yMin) / (yMax - yMin || 1)) * (H - pad * 2)

  const path = xs.map((x, i) => `${i ? 'L' : 'M'}${f2(sx(x))} ${f2(sy(ys[i]))}`).join('')
  const axisY = sy(0), axisX = sx(Math.max(x0, Math.min(0, x1)))

  const parts: string[] = [
    `<line class="fig-axis" x1="${f2(pad)}" y1="${f2(axisY)}" x2="${f2(W - pad)}" y2="${f2(axisY)}"/>`,
    `<line class="fig-axis" x1="${f2(axisX)}" y1="${f2(pad)}" x2="${f2(axisX)}" y2="${f2(H - pad)}"/>`,
    `<path class="fig-curve" d="${path}"/>`,
  ]

  // 할선: 두 점을 잇고 양쪽으로 조금 연장한다
  if (s.secant) {
    const [a, b] = s.secant
    const ya = fn(a), yb = fn(b), m = (yb - ya) / (b - a || 1)
    const ext = (x1 - x0) * 0.12
    const xa = a - ext, xb = b + ext
    parts.push(`<line class="fig-secant" x1="${f2(sx(xa))}" y1="${f2(sy(ya + m * (xa - a)))}" x2="${f2(sx(xb))}" y2="${f2(sy(ya + m * (xb - a)))}"/>`)
    for (const x of [a, b]) parts.push(`<circle class="fig-pt fig-pt--secant" cx="${f2(sx(x))}" cy="${f2(sy(fn(x)))}" r="5"/>`)
  }
  // 접선: 수치 미분
  if (s.tangentAt != null) {
    const a = s.tangentAt, h = 1e-4
    const m = (fn(a + h) - fn(a - h)) / (2 * h)
    const ext = (x1 - x0) * 0.22
    parts.push(`<line class="fig-tangent" x1="${f2(sx(a - ext))}" y1="${f2(sy(fn(a) - m * ext))}" x2="${f2(sx(a + ext))}" y2="${f2(sy(fn(a) + m * ext))}"/>`)
    parts.push(`<circle class="fig-pt fig-pt--tangent" cx="${f2(sx(a))}" cy="${f2(sy(fn(a)))}" r="5"/>`)
  }
  for (const x of s.points ?? []) {
    parts.push(`<circle class="fig-pt" cx="${f2(sx(x))}" cy="${f2(sy(fn(x)))}" r="4"/>`)
    parts.push(`<text class="fig-tick" x="${f2(sx(x))}" y="${f2(H - pad + 18)}" text-anchor="middle">${f2(x).replace(/\.?0+$/, '')}</text>`)
  }
  if (s.label) parts.push(`<text class="fig-label" x="${f2(W - pad)}" y="${f2(pad - 14)}" text-anchor="end">${esc(s.label)}</text>`)
  return parts.join('')
}

/** 분포 곡선. 간섭무늬는 cos² 에 가우시안 봉투를 씌운 것, 두 봉우리는 가우시안 둘의 합. */
function profileY(kind: string, t: number): number {
  const g = (c: number, w: number) => Math.exp(-((t - c) ** 2) / (2 * w * w))
  switch (kind) {
    // 슬릿 하나의 회절: 넓은 중앙 최대 + 양옆의 약한 측면 최대. '봉우리 하나' 가 아니다.
    case 'single': return g(0.5, 0.11) + 0.12 * (g(0.24, 0.045) + g(0.76, 0.045))
    case 'two-humps': return 0.9 * (g(0.34, 0.09) + g(0.66, 0.09)) + 0.08 * (g(0.1, 0.04) + g(0.9, 0.04))
    case 'fringes': return g(0.5, 0.22) * (0.5 + 0.5 * Math.cos((t - 0.5) * 2 * Math.PI * 6))
    case 'fringes-weak': return g(0.5, 0.22) * (0.5 + 0.18 * Math.cos((t - 0.5) * 2 * Math.PI * 6))
    default: return g(0.5, 0.13)
  }
}

function distribution(s: Extract<FigureSpec, { kind: 'distribution' }>): string {
  const n = s.panels.length
  const gap = 16, pad = 24
  const pw = (W - pad * 2 - gap * (n - 1)) / n
  const ph = H - pad * 2 - 28
  return s.panels.map((p, i) => {
    const x = pad + i * (pw + gap)
    const top = pad + 28
    const N = 60
    const pts = Array.from({ length: N + 1 }, (_, k) => {
      const t = k / N
      return `${f2(x + t * pw)} ${f2(top + ph - profileY(p.profile, t) * (ph - 8))}`
    })
    const area = `M${f2(x)} ${f2(top + ph)}L${pts.join('L')}L${f2(x + pw)} ${f2(top + ph)}Z`
    return `<text class="fig-label" x="${f2(x + pw / 2)}" y="${f2(pad + 8)}" text-anchor="middle">${esc(p.title)}</text>` +
      `<rect class="fig-panel" x="${f2(x)}" y="${f2(top)}" width="${f2(pw)}" height="${f2(ph)}"/>` +
      `<path class="fig-area" d="${area}"/>`
  }).join('')
}

function tonecurve(s: Extract<FigureSpec, { kind: 'tonecurve' }>): string {
  const size = 240, pad = 40
  const ox = (W - size) / 2 - 60, oy = pad
  const sx = (t: number) => ox + t * size
  const sy = (t: number) => oy + size - t * size
  const curveFn: Record<string, (t: number) => number> = {
    'linear': (t) => t,
    's-mild': (t) => t + 0.10 * Math.sin(2 * Math.PI * (t - 0.5)) * -1,
    's-strong': (t) => t + 0.24 * Math.sin(2 * Math.PI * (t - 0.5)) * -1,
    'inverse-s': (t) => t + 0.14 * Math.sin(2 * Math.PI * (t - 0.5)),
  }
  const fn = curveFn[s.curve]
  const clamp = (v: number) => Math.max(0, Math.min(1, v))
  const N = 40
  const path = Array.from({ length: N + 1 }, (_, i) => {
    const t = i / N
    return `${i ? 'L' : 'M'}${f2(sx(t))} ${f2(sy(clamp(fn(t))))}`
  }).join('')
  const parts = [
    `<rect class="fig-panel" x="${f2(ox)}" y="${f2(oy)}" width="${size}" height="${size}"/>`,
    `<line class="fig-guide" x1="${f2(ox)}" y1="${f2(oy + size)}" x2="${f2(ox + size)}" y2="${f2(oy)}"/>`,
    `<path class="fig-curve" d="${path}"/>`,
    `<text class="fig-tick" x="${f2(ox)}" y="${f2(oy + size + 18)}">어두움</text>`,
    `<text class="fig-tick" x="${f2(ox + size)}" y="${f2(oy + size + 18)}" text-anchor="end">밝음</text>`,
  ]
  // 히스토그램 (합성) — 커브가 세면 양끝으로 몰린다
  const hx = ox + size + 40, hw = 200, hh = 120, hy = oy + size - hh
  const bars = 24
  const strength = s.curve === 's-strong' ? 1 : s.curve === 's-mild' ? 0.45 : s.curve === 'inverse-s' ? -0.4 : 0
  for (let i = 0; i < bars; i++) {
    const t = (i + 0.5) / bars
    let v = Math.exp(-((t - 0.5) ** 2) / (2 * 0.2 * 0.2))
    v = v * (1 - 0.5 * strength) + strength * 0.9 * (Math.exp(-((t - 0.04) ** 2) / 0.006) + Math.exp(-((t - 0.96) ** 2) / 0.006))
    v = clamp(v)
    const clipped = s.clipHighlights && i >= bars - 2
    parts.push(`<rect class="fig-bar${clipped ? ' fig-bar--clip' : ''}" x="${f2(hx + (i * hw) / bars)}" y="${f2(hy + hh - v * hh)}" width="${f2(hw / bars - 1)}" height="${f2(v * hh)}"/>`)
  }
  parts.push(`<text class="fig-label" x="${f2(hx)}" y="${f2(hy - 10)}">히스토그램</text>`)
  if (s.clipHighlights) parts.push(`<text class="fig-tick fig-tick--clip" x="${f2(hx + hw)}" y="${f2(hy + hh + 18)}" text-anchor="end">밝은 쪽이 벽에 붙음</text>`)
  return parts.join('')
}

function swatches(s: Extract<FigureSpec, { kind: 'swatches' }>): string {
  const pad = 24, labelW = 120, rowH = Math.min(56, (H - pad * 2) / s.rows.length)
  return s.rows.map((r, i) => {
    const y = pad + i * rowH
    const sw = (W - pad * 2 - labelW) / r.colors.length
    return `<text class="fig-label" x="${f2(pad)}" y="${f2(y + rowH / 2 + 5)}">${esc(r.label)}</text>` +
      r.colors.map((col, j) =>
        `<rect x="${f2(pad + labelW + j * sw)}" y="${f2(y + 6)}" width="${f2(sw - 4)}" height="${f2(rowH - 12)}" rx="6" fill="${esc(col)}"/>`).join('')
  }).join('')
}

/**
 * 실물 자극. 도식으로 대신할 수 없는 지각 판단(색·질감·노출)을 가르칠 때만 쓴다.
 *
 * 매니페스트에 없는 id 는 검증기가 이미 막는다. 그래도 렌더러가 조용히 빈 그림을 내면
 * "사진이 있어야 배울 수 있다" 는 게이트가 무력해지므로 여기서 다시 던진다.
 * 빈 자리는 버그가 아니라 잘못 출고된 학습지다.
 */
function asset(assetId: string) {
  const a = ASSETS[assetId]
  if (!a) {
    throw new Error(
      `등록되지 않은 실물 자극입니다: ${assetId}. ` +
      `server/assets/manifest.json 에 라이선스·출처와 함께 등록하고 node server/build-assets.mjs 를 실행하세요`)
  }
  return a
}

const photoAssetIds = (s: Extract<FigureSpec, { kind: 'photo' }>): string[] =>
  s.compareAssetId ? [s.assetId, s.compareAssetId] : [s.assetId]

/** width/height 를 박지 않는다 — 폭은 CSS 가 정하고 좁은 화면에서 줄어들어야 한다. */
function photo(fig: Figure, s: Extract<FigureSpec, { kind: 'photo' }>): string {
  const ids = photoAssetIds(s)
  const imgs = ids.map((aid, i) => {
    const a = asset(aid)
    // 두 장을 나란히 둘 때 같은 alt 를 두 번 읽어 주면 스크린리더에서 어느 쪽인지 알 수 없다.
    const alt = i === 0 ? fig.alt : `${fig.alt} — 비교용 두 번째 사진`
    return `<img class="fig-photo__img" src="${esc(a.dataUri)}" alt="${esc(alt)}" loading="eager" decoding="async">`
  })
  return `<div class="fig-photo${ids.length > 1 ? ' fig-photo--pair' : ''}">${imgs.join('')}</div>`
}

/** 출처·라이선스는 선택이 아니다. 사진을 쓰면 반드시 그림 아래에 남는다. */
function photoCredits(s: Extract<FigureSpec, { kind: 'photo' }>): string {
  return photoAssetIds(s).map((aid) => {
    const a = asset(aid)
    return `<p class="fig__credit">${esc(a.credit)} · ${esc(a.license)}</p>`
  }).join('')
}

export function renderFigure(fig: Figure): string {
  const id = esc(fig.id)
  let stage: string
  if (fig.spec.kind === 'photo') {
    stage = photo(fig, fig.spec)
  } else {
    let body: string
    switch (fig.spec.kind) {
      case 'plot': body = plot(fig.spec); break
      case 'distribution': body = distribution(fig.spec); break
      case 'tonecurve': body = tonecurve(fig.spec); break
      default: body = swatches(fig.spec)
    }
    stage = `<svg class="fig__svg" viewBox="0 0 ${W} ${H}" role="img" aria-labelledby="fig-${id}-t" aria-describedby="fig-${id}-d">` +
      `<title id="fig-${id}-t">${esc(fig.title)}</title><desc id="fig-${id}-d">${esc(fig.alt)}</desc>${body}</svg>`
  }
  const interactive = (fig.spec as any).interactive === true
  const inter = interactive
    ? ` data-interactive="${fig.spec.kind}"` +
      (fig.spec.kind === 'plot' ? plotDataAttrs(fig.spec) : '')
    : ''
  // 눈금 방식은 런타임이 읽는다. 정성 모형에 숫자를 찍는 것을 막는 스위치라 모든 도형에 낸다.
  return `<figure class="fig" id="fig-${id}" data-figure="${id}" data-readout="${esc(fig.readout)}"${inter}>` +
    stage +
    (interactive ? interactiveControls(fig) : '') +
    `<figcaption class="fig__cap">${esc(fig.title)}</figcaption>` +
    (fig.spec.kind === 'photo' ? photoCredits(fig.spec) : '') +
    // 이상화 표상이 무엇을 생략했는지 스스로 말한다. 캡션 바로 아래, 본문은 밀지 않는 크기로.
    (fig.model_note ? `<p class="fig__limits">이 그림이 생략한 것 — ${esc(fig.model_note)}</p>` : '') +
    (fig.drawTask
      ? `<p class="fig__task">${esc(fig.drawTask)}</p>` +
        `<div class="ink-space" data-ink-space="md" data-ink-anchor="fig-${id}"></div>`
      : '') +
    `</figure>`
}

/** 런타임이 SVG 좌표를 재현하는 데 필요한 값. plot() 과 같은 plotFrame() 에서 나온다. */
function plotDataAttrs(s: Extract<FigureSpec, { kind: 'plot' }>): string {
  const { x0, x1, yMin, yMax, pad } = plotFrame(s)
  const a = s.secant?.[0] ?? s.tangentAt ?? 0
  return ` data-fn="${esc(s.fn)}" data-x0="${f2(x0)}" data-x1="${f2(x1)}" data-a="${f2(a)}"` +
    ` data-pad="${f2(pad)}" data-ymin="${f2(yMin)}" data-ymax="${f2(yMax)}"`
}

/**
 * 정성 눈금의 세 단계. 이 세 문자열 말고 다른 것이 나오면 안 된다.
 * 런타임(worksheet-interact.js)도 같은 경계(1/3, 2/3)를 쓴다.
 */
export const QUALITATIVE_BANDS = ['낮음', '중간', '높음'] as const
export const qualitativeBand = (v: number): string =>
  v < 1 / 3 ? QUALITATIVE_BANDS[0] : v < 2 / 3 ? QUALITATIVE_BANDS[1] : QUALITATIVE_BANDS[2]

/** distribution 슬라이더의 초기값. 결맞음 0 = 두 경로가 구분된 상태 = 간섭 낮음. */
const COHERENCE_INITIAL = 0

/** 슬라이더. 실제 계산은 런타임(worksheet-interact.js)이 한다 — 여기서는 자리만. */
function interactiveControls(fig: Figure): string {
  const id = esc(fig.id)
  if (fig.spec.kind === 'plot') {
    // 정량이 정직한 유일한 자리. 화면의 8.00 은 이 그림에서 실제로 계산되는 할선의 기울기다.
    return `<div class="fig__ctl"><label for="h-${id}">h (두 번째 점까지의 거리)</label>` +
      `<input type="range" id="h-${id}" class="fig__slider" min="-2" max="2" step="0.01" value="2" data-for="${id}">` +
      `<output class="fig__readout" data-for="${id}">h = 2.00 → 할선 기울기 <b>8.00</b></output></div>`
  }
  // 여기에 퍼센트를 찍으면 안 된다.
  // 예전 눈금은 "간섭 가시도 = (1 − v) × 100%" 였는데 그런 보편 법칙은 없다.
  // 표준 상보성이 주는 것은 D² + V² ≤ 1 같은 부등식이고, 그마저 이 그림에서 계산되지 않는다.
  // 본문에 '대략적 모형' 이라고 적어도 63% 가 움직이면 사람은 그걸 법칙으로 기억한다.
  return `<div class="fig__ctl"><label for="v-${id}">두 경로의 결맞음 |γ| — 정성 모형</label>` +
    `<input type="range" id="v-${id}" class="fig__slider" min="0" max="1" step="0.01" value="${COHERENCE_INITIAL}" data-for="${id}">` +
    `<output class="fig__readout" data-for="${id}">간섭 <b>${qualitativeBand(COHERENCE_INITIAL)}</b></output>` +
    `<p class="fig__ctl-note">이건 정성 모형이에요. '경로 정보 40%면 간섭 60%' 같은 보편 법칙은 없어요.</p></div>`
}

export const FIGURE_CSS = `
.fig__note { font-weight: 400; color: var(--ds-color-text-tertiary); }
.fig__ctl { margin: 12px 0 0; display: grid; gap: 6px; font-size: 14px; color: var(--ds-color-text-secondary); }
.fig__slider {
  width: 100%; accent-color: var(--ds-color-brand-text);
  /* 슬라이더는 손가락으로 끄는 것이다. 트랙은 얇아도 잡는 면적은 44px 이어야 한다. */
  min-height: 44px;
}
.fig__readout { font-family: var(--ds-font-mono); font-size: 14px; color: var(--ds-color-text-primary); }
.fig__readout b { color: var(--ds-color-brand-text); }
/* 정성 모형이라는 고정 문구. 슬라이더 바로 아래에 붙어 있어야 눈금과 함께 읽힌다. */
.fig__ctl-note {
  margin: 2px 0 0; font-size: 13px; line-height: 1.6;
  color: var(--ds-color-text-tertiary);
}
/* JS 가 붙기 전에는 죽은 컨트롤이다. 런타임이 data-wired 를 달면 그때 보인다.
   그림 자체(정적 SVG)는 그대로 보여야 하므로 컨트롤만 감춘다. */
figure[data-interactive]:not([data-wired]) .fig__ctl { display: none; }
/* 이 그림이 생략한 것. 눈에 띄되 본문을 밀어내지 않는 크기 — 점선 하나와 작은 글씨. */
.fig__limits {
  margin: 8px 0 0; padding-top: 8px;
  border-top: 1px dashed var(--ds-color-border-subtle);
  font-size: 13px; line-height: 1.65;
  color: var(--ds-color-text-secondary);
  max-width: 40em;
}
/* 출처·라이선스. 조용하지만 지울 수 없다. */
.fig__credit {
  margin: 8px 0 0; font-size: 12px; line-height: 1.6;
  color: var(--ds-color-text-tertiary);
}
/* 실물 사진 */
.fig-photo {
  display: grid; gap: 10px;
  border-radius: var(--ds-radius-xl); overflow: hidden;
}
.fig-photo--pair { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.fig-photo__img {
  display: block; width: 100%; max-width: 100%; height: auto;
  border-radius: var(--ds-radius-xl);
  background: var(--ds-color-surface-sunken);
}
.fig-secant--live { stroke: var(--ds-color-status-info); stroke-width: 2.4; }
.fig { margin: 0 0 var(--ds-sheet-block-gap); max-width: 40em; }
.fig__svg {
  display: block; width: 100%; height: auto;
  background: var(--ds-color-surface-raised);
  border: 1px solid var(--ds-color-border-subtle);
  border-radius: var(--ds-radius-xl);
}
.fig__cap { font-size: 14px; color: var(--ds-color-text-tertiary); margin: 10px 0 0; }
.fig__task {
  font-size: 16px; font-weight: 700; margin: 14px 0 0;
  color: var(--ds-color-text-primary);
}
.fig__task::before { content: "✎ "; color: var(--ds-color-brand-text); }
.fig-axis { stroke: var(--ds-color-border-strong); stroke-width: 1.2; }
.fig-guide { stroke: var(--ds-color-border-default); stroke-width: 1; stroke-dasharray: 4 4; }
.fig-panel { fill: var(--ds-color-surface-sunken); stroke: var(--ds-color-border-subtle); rx: 8; }
.fig-curve { fill: none; stroke: var(--ds-color-text-primary); stroke-width: 2.4; stroke-linecap: round; }
.fig-secant { stroke: var(--ds-color-status-info); stroke-width: 2; stroke-dasharray: 6 5; }
.fig-tangent { stroke: var(--ds-color-brand-text); stroke-width: 2.4; }
.fig-pt { fill: var(--ds-color-text-primary); }
.fig-pt--secant { fill: var(--ds-color-status-info); }
.fig-pt--tangent { fill: var(--ds-color-brand-text); }
.fig-area { fill: var(--ds-color-brand-primary); fill-opacity: .28; stroke: var(--ds-color-brand-text); stroke-width: 1.5; }
.fig-bar { fill: var(--ds-color-text-tertiary); }
.fig-bar--clip { fill: var(--ds-color-status-danger); }
.fig-tick { font-size: 12px; fill: var(--ds-color-text-tertiary); font-family: var(--ds-font-sans); }
.fig-tick--clip { fill: var(--ds-color-status-danger); font-weight: 700; }
.fig-label { font-size: 13px; font-weight: 700; fill: var(--ds-color-text-secondary); font-family: var(--ds-font-sans); }

@media (max-width: 640px) {
  /* 두 장을 나란히 두면 각각이 손톱만 해진다. 좁은 화면에서는 위아래로 쌓는다. */
  .fig-photo--pair { grid-template-columns: minmax(0, 1fr); }
  .fig__task { font-size: 15px; }
  .fig__ctl { font-size: 13px; }
}
@media print {
  .fig-photo__img { break-inside: avoid; }
}
`
