// 학습 상호작용 런타임. 활동·문제의 선택, 제출, 오답별 피드백, 슬라이더 도형.
//
// 외부 평가: "외형은 interactive worksheet 인데 데이터 모델은 static document".
// 선택지가 <li> 라서 시스템은 학생이 A 를 골랐는지 답부터 열었는지 모른다.
// 여기서부터는 라디오로 고르고, 고르기 전에는 답이 열리지 않고, 고른 오답에 맞는 피드백만 뜬다.
// 모든 응답은 브리지로 나가고 ONPAR_RESPONSES 에 남는다.

const RESPONSES = {}

function bridge(type, payload) {
  const h = globalThis.flutter_inappwebview
  if (h && typeof h.callHandler === 'function') h.callHandler('learn', { type, payload })
  RESPONSES[payload.id] = { type, ...payload, at: Date.now() }
}

// ── 활동 / 선택형 문제 ─────────────────────────────────────────────────
function wireChoice(root) {
  const id = root.dataset.responseId
  const reveal = root.querySelector('details.act__reveal, details.quiz__a')
  const submit = root.querySelector('[data-submit]')
  const feedback = root.querySelector('[data-feedback-slot]')
  const radios = [...root.querySelectorAll('input[type="radio"]')]
  if (!reveal) return

  // 고르기 전에는 답을 못 연다. 열려고 하면 안내만.
  reveal.addEventListener('toggle', () => {
    if (reveal.open && !root.dataset.answered) {
      reveal.open = false
      root.classList.add('is-nudge')
      setTimeout(() => root.classList.remove('is-nudge'), 900)
    }
  })

  function answer(choiceIdx, choiceText) {
    root.dataset.answered = '1'
    const correct = root.dataset.answer != null ? String(choiceIdx) === root.dataset.answer : null
    // 고른 오답에 맞는 피드백만 보여준다. 전부 나열하면 진단이 아니다.
    if (feedback) {
      const label = radios[choiceIdx]?.closest('label')
      const fb = label?.dataset.feedback
      feedback.textContent = correct === true ? '' : (fb || '')
      feedback.hidden = !feedback.textContent
    }
    radios.forEach((r, i) => {
      const l = r.closest('label'); if (!l) return
      l.classList.toggle('is-picked', i === choiceIdx)
      // 답이 열리는 순간이므로 정답 칸도 같이 보여준다. 어디가 맞았는지 모르면 피드백이 반쪽이다.
      if (correct !== null) l.classList.toggle('is-correct', String(i) === root.dataset.answer)
      if (correct !== null) l.classList.toggle('is-wrong', i === choiceIdx && correct === false)
    })
    root.classList.add('is-answered')
    if (correct === true) root.classList.add('is-right')
    reveal.open = true
    bridge('choice', { id, choice: choiceIdx, text: choiceText, correct })
  }

  if (submit) {
    submit.addEventListener('click', () => {
      const i = radios.findIndex((r) => r.checked)
      if (i === -1) { root.classList.add('is-nudge'); setTimeout(() => root.classList.remove('is-nudge'), 900); return }
      answer(i, radios[i].value)
    })
  } else {
    radios.forEach((r, i) => r.addEventListener('change', () => answer(i, r.value)))
  }
}

// ── 서술형: 채점은 못 하지만 시도했는지는 안다 ──────────────────────────
function wireWritten(root) {
  const id = root.dataset.responseId
  const reveal = root.querySelector('details.act__reveal, details.quiz__a')
  const attempted = root.querySelector('input[type="checkbox"][data-attempted]')
  if (!reveal || !attempted) return
  reveal.addEventListener('toggle', () => {
    if (reveal.open && !attempted.checked) {
      reveal.open = false
      root.classList.add('is-nudge')
      setTimeout(() => root.classList.remove('is-nudge'), 900)
    }
  })
  attempted.addEventListener('change', () => {
    if (attempted.checked) { root.dataset.answered = '1'; root.classList.add('is-answered'); bridge('attempt', { id }) }
  })
}

// ── 슬라이더 도형 ───────────────────────────────────────────────────────
const FN = { 'x^2': (x) => x * x, 'x^3': (x) => x * x * x, 'sin': Math.sin, 'exp': Math.exp, 'linear': (x) => 0.8 * x + 1, 'abs': Math.abs }
const f2 = (n) => (Math.round(n * 100) / 100).toFixed(2)

/** 할선의 두 번째 점을 h 만큼 옮긴다. h 는 음수도 된다 — 왼쪽 접근을 반드시 보게 한다. */
function wirePlot(fig) {
  const svg = fig.querySelector('svg')
  const fn = FN[fig.dataset.fn]; if (!fn || !svg) return
  const a = +fig.dataset.a, x0 = +fig.dataset.x0, x1 = +fig.dataset.x1
  const pad = +fig.dataset.pad, yMin = +fig.dataset.ymin, yMax = +fig.dataset.ymax
  const W = 600, H = 340
  const sx = (x) => pad + ((x - x0) / (x1 - x0)) * (W - pad * 2)
  const sy = (y) => H - pad - ((y - yMin) / (yMax - yMin || 1)) * (H - pad * 2)
  const line = svg.querySelector('.fig-secant')
  const pts = svg.querySelectorAll('.fig-pt--secant')
  const slider = fig.querySelector('.fig__slider')
  const out = fig.querySelector('.fig__readout')
  if (!line || pts.length < 2 || !slider) return
  line.classList.add('fig-secant--live')

  function update() {
    let h = +slider.value
    if (Math.abs(h) < 0.01) h = h < 0 ? -0.01 : 0.01   // h=0 은 정의되지 않는다. 대입하는 게 아니다.
    const b = a + h
    const ya = fn(a), yb = fn(b), m = (yb - ya) / h
    const ext = (x1 - x0) * 0.15
    const xa = Math.min(a, b) - ext, xb = Math.max(a, b) + ext
    line.setAttribute('x1', f2(sx(xa))); line.setAttribute('y1', f2(sy(ya + m * (xa - a))))
    line.setAttribute('x2', f2(sx(xb))); line.setAttribute('y2', f2(sy(ya + m * (xb - a))))
    pts[1].setAttribute('cx', f2(sx(b))); pts[1].setAttribute('cy', f2(sy(yb)))
    if (out) out.innerHTML = `h = ${h >= 0 ? '+' : ''}${f2(h)} → 할선 기울기 <b>${f2(m)}</b>` +
      (Math.abs(h) <= 0.05 ? ' <span>(양쪽 다 가까워지는지 보세요)</span>' : '')
    bridge('slider', { id: fig.dataset.figure, h, slope: m })
  }
  slider.addEventListener('input', update)
  update()
}

/** 마지막 패널을 경로정보 v 로 다시 그린다. 스위치가 아니라 연속이라는 걸 손으로 느끼게. */
function wireDistribution(fig) {
  const svg = fig.querySelector('svg')
  const panels = svg ? [...svg.querySelectorAll('.fig-panel')] : []
  const areas = svg ? [...svg.querySelectorAll('.fig-area')] : []
  const slider = fig.querySelector('.fig__slider'), out = fig.querySelector('.fig__readout')
  if (!panels.length || !areas.length || !slider) return
  const rect = panels[panels.length - 1], area = areas[areas.length - 1]
  const x = +rect.getAttribute('x'), top = +rect.getAttribute('y')
  const pw = +rect.getAttribute('width'), ph = +rect.getAttribute('height')
  const g = (t, c, w) => Math.exp(-((t - c) ** 2) / (2 * w * w))

  function update() {
    const v = +slider.value                       // 0 = 경로정보 없음
    const N = 60, pts = []
    for (let k = 0; k <= N; k++) {
      const t = k / N
      const env = g(t, 0.5, 0.22)
      const fringes = 0.5 + 0.5 * (1 - v) * Math.cos((t - 0.5) * 2 * Math.PI * 6)
      const humps = 0.9 * (g(t, 0.34, 0.09) + g(t, 0.66, 0.09))
      const y = (1 - v) * env * fringes + v * humps
      pts.push(`${f2(x + t * pw)} ${f2(top + ph - y * (ph - 8))}`)
    }
    area.setAttribute('d', `M${f2(x)} ${f2(top + ph)}L${pts.join('L')}L${f2(x + pw)} ${f2(top + ph)}Z`)
    if (out) out.innerHTML = `간섭 가시도 <b>${Math.round((1 - v) * 100)}%</b>`
    bridge('slider', { id: fig.dataset.figure, pathInfo: v })
  }
  slider.addEventListener('input', update)
  update()
}

function boot() {
  document.querySelectorAll('[data-response-id][data-response-kind="choice"]').forEach(wireChoice)
  document.querySelectorAll('[data-response-id][data-response-kind="written"]').forEach(wireWritten)
  document.querySelectorAll('figure[data-interactive="plot"]').forEach(wirePlot)
  document.querySelectorAll('figure[data-interactive="distribution"]').forEach(wireDistribution)
  globalThis.ONPAR_RESPONSES = RESPONSES
  globalThis.ONPAR_LEARN = {
    export: () => ({ ...RESPONSES }),
    answeredCount: () => Object.keys(RESPONSES).filter((k) => RESPONSES[k].type !== 'slider').length,
  }
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot)
  else boot()
}
