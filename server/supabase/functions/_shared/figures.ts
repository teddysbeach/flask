// 도형 렌더러. 구조화된 스펙 → 결정론적 인라인 SVG.
//
// LLM 은 SVG 를 쓰지 않는다. 스펙만 낸다. 그래야 렌더가 깨지지 않고 XSS 가 열리지 않는다.
// 모든 숫자는 소수 2자리로 고정해 같은 스펙이면 바이트 단위로 같은 SVG 가 나온다.
// 색은 currentColor 와 CSS 변수만 쓴다 — 디자인 시스템을 갈아끼워도 도형이 따라간다.

import type { Figure, FigureSpec } from './worksheet-types.ts'
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

export function renderFigure(fig: Figure): string {
  let body: string
  switch (fig.spec.kind) {
    case 'plot': body = plot(fig.spec); break
    case 'distribution': body = distribution(fig.spec); break
    case 'tonecurve': body = tonecurve(fig.spec); break
    default: body = swatches(fig.spec)
  }
  const id = esc(fig.id)
  const inter = (fig.spec as any).interactive
    ? ` data-interactive="${fig.spec.kind}"` +
      (fig.spec.kind === 'plot' ? plotDataAttrs(fig.spec) : '')
    : ''
  return `<figure class="fig" id="fig-${id}" data-figure="${id}"${inter}>` +
    `<svg class="fig__svg" viewBox="0 0 ${W} ${H}" role="img" aria-labelledby="fig-${id}-t" aria-describedby="fig-${id}-d">` +
    `<title id="fig-${id}-t">${esc(fig.title)}</title><desc id="fig-${id}-d">${esc(fig.alt)}</desc>${body}</svg>` +
    ((fig.spec as any).interactive ? interactiveControls(fig) : '') +
    `<figcaption class="fig__cap">${esc(fig.title)}${
      fig.spec.kind === 'distribution' ? ' <span class="fig__note">슬릿 폭을 무시한 이상화 모델이에요. 실제 무늬는 회절 봉투 안에 나타나요.</span>' : ''
    }</figcaption>` +
    (fig.drawTask ? `<p class="fig__task">${esc(fig.drawTask)}</p><div class="ink-space" data-ink-space="md"></div>` : '') +
    `</figure>`
}

/** 런타임이 SVG 좌표를 재현하는 데 필요한 값. plot() 과 같은 plotFrame() 에서 나온다. */
function plotDataAttrs(s: Extract<FigureSpec, { kind: 'plot' }>): string {
  const { x0, x1, yMin, yMax, pad } = plotFrame(s)
  const a = s.secant?.[0] ?? s.tangentAt ?? 0
  return ` data-fn="${esc(s.fn)}" data-x0="${f2(x0)}" data-x1="${f2(x1)}" data-a="${f2(a)}"` +
    ` data-pad="${f2(pad)}" data-ymin="${f2(yMin)}" data-ymax="${f2(yMax)}"`
}

/** 슬라이더. 실제 계산은 런타임(worksheet-interact.js)이 한다 — 여기서는 자리만. */
function interactiveControls(fig: Figure): string {
  const id = esc(fig.id)
  if (fig.spec.kind === 'plot') {
    return `<div class="fig__ctl"><label for="h-${id}">h (두 번째 점까지의 거리)</label>` +
      `<input type="range" id="h-${id}" class="fig__slider" min="-2" max="2" step="0.01" value="2" data-for="${id}">` +
      `<output class="fig__readout" data-for="${id}">h = 2.00 → 할선 기울기 <b>8.00</b></output></div>`
  }
  return `<div class="fig__ctl"><label for="v-${id}">경로 정보 (0 = 없음, 1 = 충분)</label>` +
    `<input type="range" id="v-${id}" class="fig__slider" min="0" max="1" step="0.01" value="0" data-for="${id}">` +
    `<output class="fig__readout" data-for="${id}">간섭 가시도 <b>100%</b></output></div>`
}

export const FIGURE_CSS = `
.fig__note { font-weight: 400; color: var(--ds-color-text-tertiary); }
.fig__ctl { margin: 12px 0 0; display: grid; gap: 6px; font-size: 14px; color: var(--ds-color-text-secondary); }
.fig__slider { width: 100%; accent-color: var(--ds-color-brand-primary); }
.fig__readout { font-family: var(--ds-font-mono); font-size: 14px; color: var(--ds-color-text-primary); }
.fig__readout b { color: var(--ds-color-brand-primary); }
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
.fig__task::before { content: "✎ "; color: var(--ds-color-brand-primary); }
.fig-axis { stroke: var(--ds-color-border-strong); stroke-width: 1.2; }
.fig-guide { stroke: var(--ds-color-border-default); stroke-width: 1; stroke-dasharray: 4 4; }
.fig-panel { fill: var(--ds-color-surface-sunken); stroke: var(--ds-color-border-subtle); rx: 8; }
.fig-curve { fill: none; stroke: var(--ds-color-text-primary); stroke-width: 2.4; stroke-linecap: round; }
.fig-secant { stroke: var(--ds-color-status-info); stroke-width: 2; stroke-dasharray: 6 5; }
.fig-tangent { stroke: var(--ds-color-brand-primary); stroke-width: 2.4; }
.fig-pt { fill: var(--ds-color-text-primary); }
.fig-pt--secant { fill: var(--ds-color-status-info); }
.fig-pt--tangent { fill: var(--ds-color-brand-primary); }
.fig-area { fill: var(--ds-color-brand-primary); fill-opacity: .28; stroke: var(--ds-color-brand-primary); stroke-width: 1.5; }
.fig-bar { fill: var(--ds-color-text-tertiary); }
.fig-bar--clip { fill: var(--ds-color-status-danger); }
.fig-tick { font-size: 12px; fill: var(--ds-color-text-tertiary); font-family: var(--ds-font-sans); }
.fig-tick--clip { fill: var(--ds-color-status-danger); font-weight: 700; }
.fig-label { font-size: 13px; font-weight: 700; fill: var(--ds-color-text-secondary); font-family: var(--ds-font-sans); }
`
