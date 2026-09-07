// 학습 상호작용 런타임. 활동·문제의 선택, 제출, 오답별 피드백, 서술형 답, 슬라이더 도형.
//
// 외부 평가 1: "'썼다'는 아는데 무엇을 썼는지는 모른다."
//   - 서술형은 attempted=true 만 남았다. 깊은 학습과 아무 말이나 쓰는 행위가 데이터상 같았다.
//   - 선택형은 RESPONSES[id] = ... 로 덮어써서, 첫 오답을 고르고 정답으로 고치면
//     처음 오개념이 사라졌다. 학습분석에서 중요한 건 first → feedback → retry → final 이다.
//
// 그래서 응답은 "덮어쓰기"가 아니라 "이력"이다. firstChoice 는 절대 덮어쓰지 않는다.
//
//   선택형 { id, kind:'choice', questionId, firstChoice, finalChoice,
//            attempts:[{choice,text,correct,at,msSincePrompt}],
//            correct, feedbackSeen, changedMind, firstCorrect }
//   서술형 { id, kind:'written', questionId, text, chars, inkStrokes,
//            revisionHistory:[{chars,at}], submittedAt, msSincePrompt }
//
// 외부 평가 3: 필기만 강제하지 않는다. 타이핑(textarea)과 필기(ink-space)를 함께 지원하고,
// 셋 중 하나라도 시도가 있으면 답이 열린다. JS 가 죽어도 본문·문제·선택지·해설은 읽힌다.

const RESPONSES = {}
const LOAD_AT = Date.now()
const TEXT_DEBOUNCE_MS = 400
const MAX_REVISIONS = 100        // 이력이 무한정 늘면 저장이 아니라 로그가 된다

/** 학습지 id. localStorage 키가 학습지마다 갈라져야 다른 학습지의 답이 섞이지 않는다. */
function worksheetId() {
  const el = document.querySelector('[data-worksheet-id]')
  return (el && el.dataset.worksheetId) || 'unknown'
}

function markRuntimeFailed(e) {
  try { document.documentElement.dataset.onparRuntime = 'failed' } catch { /* 무시 */ }
  try { console.error('[onpar] 학습 런타임 오류', e) } catch { /* 무시 */ }
}

// ── 저장 (새로고침에 답이 사라지면 학습자가 화낸다) ──────────────────────
const storeKey = (id) => `onpar:${worksheetId()}:${id}`

function loadText(id) {
  try {
    const v = globalThis.localStorage ? globalThis.localStorage.getItem(storeKey(id)) : null
    return typeof v === 'string' ? v : null
  } catch { return null }        // 사파리 프라이빗 모드 등에서 접근 자체가 throw 한다
}

function saveText(id, text) {
  try {
    if (!globalThis.localStorage) return
    if (text) globalThis.localStorage.setItem(storeKey(id), text)
    else globalThis.localStorage.removeItem(storeKey(id))
  } catch { /* 저장 못 해도 학습은 계속돼야 한다 */ }
}

// ── 응답 이력 ───────────────────────────────────────────────────────────
/** 요소가 처음 화면에 보인 시각. 없으면 페이지 로드 시각. 체류시간의 기준점이다. */
const promptSeenAt = new Map()
const markSeen = (id) => { if (id && !promptSeenAt.has(id)) promptSeenAt.set(id, Date.now()) }
const msSincePrompt = (id) => Date.now() - (promptSeenAt.has(id) ? promptSeenAt.get(id) : LOAD_AT)

function record(root) {
  const id = root.dataset.responseId
  let rec = RESPONSES[id]
  if (rec) return rec
  const questionId = root.dataset.quizId || null
  rec = root.dataset.responseKind === 'choice'
    ? {
        id, kind: 'choice', questionId,
        firstChoice: null, finalChoice: null, attempts: [],
        correct: null, feedbackSeen: false, changedMind: false, firstCorrect: null,
      }
    : {
        id, kind: 'written', questionId,
        text: '', chars: 0, inkStrokes: 0, revisionHistory: [],
        submittedAt: null, msSincePrompt: null,
      }
  RESPONSES[id] = rec
  return rec
}

const snapshot = (rec) => JSON.parse(JSON.stringify(rec))

/** Flutter 로 나가는 payload 는 저장 스키마와 같은 모양이다. 두 벌을 유지하면 반드시 어긋난다. */
function bridge(type, payload) {
  try {
    const h = globalThis.flutter_inappwebview
    if (h && typeof h.callHandler === 'function') h.callHandler('learn', { type, payload })
  } catch { /* 브리지가 없으면 조용히 무시한다 (브라우저에서 그냥 열었을 때) */ }
}

// ── 활동 / 선택형 문제 ─────────────────────────────────────────────────
function wireChoice(root) {
  const id = root.dataset.responseId
  const rec = record(root)
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
      const label = radios[choiceIdx] ? radios[choiceIdx].closest('label') : null
      const fb = label ? label.dataset.feedback : null
      feedback.textContent = correct === true ? '' : (fb || '')
      feedback.hidden = !feedback.textContent
      if (!feedback.hidden) rec.feedbackSeen = true   // 실제로 표시됐을 때만 true
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

    // ── 이력. 여기가 이 파일의 핵심이다 ──
    rec.attempts.push({
      choice: choiceIdx, text: choiceText, correct,
      at: Date.now(), msSincePrompt: msSincePrompt(id),
    })
    if (rec.firstChoice === null) {
      // 첫 응답은 절대 덮어쓰지 않는다. 첫 오답이 그 학생의 오개념이고,
      // 그걸 지우면 남는 건 "결국 맞혔다" 뿐이다.
      rec.firstChoice = choiceIdx
      rec.firstCorrect = correct === null ? null : correct === true
    }
    rec.finalChoice = choiceIdx
    rec.correct = correct
    rec.changedMind = rec.firstChoice !== choiceIdx
    bridge('choice', snapshot(rec))
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

// ── 서술형: 타이핑과 필기를 나란히 지원한다 ─────────────────────────────
//
// 렌더러 계약:
//   <div class="answer" data-answer-for="{responseId}">
//     <textarea class="answer__text" data-answer-text rows="3"></textarea>
//     <div class="ink-space" data-ink-space="sm" data-ink-anchor="{responseId}"></div>
//   </div>
//   <label class="act__attempt"><input type="checkbox" data-attempted> 내 답을 적었어요</label>
//
// 셋(체크박스·글자·필기) 중 하나라도 있으면 시도로 본다. 손으로만 쓰라고 강요하지 않는다.
function wireWritten(root) {
  const id = root.dataset.responseId
  const rec = record(root)
  const reveal = root.querySelector('details.act__reveal, details.quiz__a')
  const attempted = root.querySelector('input[type="checkbox"][data-attempted]')
  const box = root.querySelector('[data-answer-for="' + cssAttr(id) + '"]') || root
  const textarea = box.querySelector('[data-answer-text]') || root.querySelector('[data-answer-text]')
  const inkEl = root.querySelector('[data-ink-anchor]')
  const anchorId = inkEl ? inkEl.dataset.inkAnchor : null

  const hasEvidence = () =>
    (attempted ? attempted.checked : false) ||
    rec.chars > 0 || rec.inkStrokes > 0

  function markSubmitted() {
    if (rec.submittedAt != null) return
    rec.submittedAt = Date.now()
    rec.msSincePrompt = msSincePrompt(id)
  }

  /** 시도가 생기면 체크박스를 대신 켜 준다. 끄는 건 사용자 몫이다(직접 풀 수 있어야 한다). */
  function reflectAttempt(push) {
    if (!hasEvidence()) return
    markSubmitted()
    if (attempted && !attempted.checked) attempted.checked = true
    root.dataset.answered = '1'
    root.classList.add('is-answered')
    if (push) bridge('written', snapshot(rec))
  }

  // 답은 시도가 있어야 열린다 — 체크박스만 보지 않는다.
  if (reveal) reveal.addEventListener('toggle', () => {
    if (reveal.open && !hasEvidence()) {
      reveal.open = false
      root.classList.add('is-nudge')
      setTimeout(() => root.classList.remove('is-nudge'), 900)
    }
  })

  if (attempted) attempted.addEventListener('change', () => {
    if (attempted.checked) { markSubmitted(); root.dataset.answered = '1'; root.classList.add('is-answered'); bridge('written', snapshot(rec)) }
  })

  if (textarea) {
    // 새로고침 복원. 답이 사라지는 학습지는 두 번 쓰이지 않는다.
    const saved = loadText(id)
    if (saved) {
      textarea.value = saved
      rec.text = saved
      rec.chars = saved.trim().length
      // 언제 썼는지는 모른다. 모르는 값을 지어내지 않는다(submittedAt 은 이 세션 기준).
      reflectAttempt(false)
    }

    let timer = null
    const commit = () => {
      const value = textarea.value
      const chars = value.trim().length
      const changed = value !== rec.text
      rec.text = value
      rec.chars = chars
      if (changed) {
        rec.revisionHistory.push({ chars, at: Date.now() })
        // 첫 판은 남기고 그 다음 것부터 버린다 — "처음 얼마나 썼는가"가 이력의 시작점이다.
        if (rec.revisionHistory.length > MAX_REVISIONS) rec.revisionHistory.splice(1, 1)
      }
      saveText(id, value)
      if (chars > 0) reflectAttempt(false)
      bridge('written', snapshot(rec))
    }
    textarea.addEventListener('input', () => {
      if (timer) clearTimeout(timer)
      timer = setTimeout(commit, TEXT_DEBOUNCE_MS)
    })
    // 화면을 떠나면 디바운스를 기다리지 않는다.
    textarea.addEventListener('blur', () => { if (timer) { clearTimeout(timer); timer = null; commit() } })
  }

  if (anchorId) {
    // 필기 런타임이 획 수를 알려준다. 필기도 "답을 적었다"는 증거다.
    document.addEventListener('onpar:ink', (e) => {
      const by = e && e.detail ? e.detail.byAnchor : null
      const n = by && by[anchorId] ? by[anchorId] : 0
      if (n === rec.inkStrokes) return
      rec.inkStrokes = n
      if (n > 0) reflectAttempt(true)
    })
  }
}

/** 속성 선택자에 넣을 값. id 는 우리가 만들지만 셀렉터 주입은 원천 차단한다. */
function cssAttr(v) {
  return String(v).replace(/["\\]/g, '\\$&')
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
  // JS 가 붙었다는 표시. 안 붙었으면 슬라이더는 아무것도 안 하므로 CSS 가 숨긴다.
  fig.dataset.wired = '1'
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

  // 슬라이더가 움직이는 것은 간섭항의 결맞음 |γ| 다.
  //   I = I₁ + I₂ + 2|γ|√(I₁I₂)cos φ  —  가운데 항만 줄어든다.
  //
  // 여기에 퍼센트를 찍으면 안 된다. 예전 눈금은 "간섭 가시도 = (1 − v) × 100%" 였는데
  // 그런 보편 법칙은 없다. 표준 상보성이 주는 것은 D² + V² ≤ 1 같은 부등식이고,
  // 그마저 이 그림에서 계산되는 값이 아니다. 본문에 '대략적 모형' 이라 적어도
  // 63% 가 움직이면 사람은 그 수를 법칙으로 기억한다. 그래서 낮음/중간/높음 만 낸다.
  const BANDS = ['낮음', '중간', '높음']
  const band = (v) => BANDS[v < 1 / 3 ? 0 : v < 2 / 3 ? 1 : 2]

  function update() {
    const gamma = +slider.value                   // 1 = 결맞음 최대(간섭 뚜렷), 0 = 경로가 구별됨
    const N = 60, pts = []
    for (let k = 0; k <= N; k++) {
      const t = k / N
      const env = g(t, 0.5, 0.22)
      const fringes = 0.5 + 0.5 * gamma * Math.cos((t - 0.5) * 2 * Math.PI * 6)
      const humps = 0.9 * (g(t, 0.34, 0.09) + g(t, 0.66, 0.09))
      const y = gamma * env * fringes + (1 - gamma) * humps
      pts.push(`${f2(x + t * pw)} ${f2(top + ph - y * (ph - 8))}`)
    }
    area.setAttribute('d', `M${f2(x)} ${f2(top + ph)}L${pts.join('L')}L${f2(x + pw)} ${f2(top + ph)}Z`)
    if (out) out.innerHTML = `간섭 <b>${band(gamma)}</b>`
    bridge('slider', { id: fig.dataset.figure, coherence: gamma, band: band(gamma) })
  }
  slider.addEventListener('input', update)
  update()
  fig.dataset.wired = '1'
}

// ── 기동 ───────────────────────────────────────────────────────────────
/** 요소가 처음 보인 시각을 잡는다. IntersectionObserver 가 없으면 페이지 로드 시각으로 본다. */
function observePrompts(roots) {
  if (typeof IntersectionObserver !== 'function') return
  const io = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (!en.isIntersecting) continue
      markSeen(en.target.dataset.responseId)
      io.unobserve(en.target)
    }
  }, { threshold: 0.25 })
  for (const el of roots) io.observe(el)
}

/** 하나가 터져도 나머지는 붙어야 한다. 문제 하나 때문에 학습지 전체가 죽지 않게. */
function each(selector, fn) {
  for (const el of document.querySelectorAll(selector)) {
    try { fn(el) } catch (e) { markRuntimeFailed(e) }
  }
}

function boot() {
  try {
    const choices = [...document.querySelectorAll('[data-response-id][data-response-kind="choice"]')]
    const written = [...document.querySelectorAll('[data-response-id][data-response-kind="written"]')]
    observePrompts([...choices, ...written])
    each('[data-response-id][data-response-kind="choice"]', wireChoice)
    each('[data-response-id][data-response-kind="written"]', wireWritten)
    each('figure[data-interactive="plot"]', wirePlot)
    each('figure[data-interactive="distribution"]', wireDistribution)

    globalThis.ONPAR_RESPONSES = RESPONSES
    globalThis.ONPAR_LEARN = {
      /** id → 응답 이력 (그대로). */
      export: () => ({ ...RESPONSES }),
      /** 저장·전송용 배열. DB 의 responses 행과 1:1 이다. */
      exportResponses: () => Object.keys(RESPONSES).map((k) => snapshot(RESPONSES[k])),
      answeredCount: () => Object.keys(RESPONSES).filter((k) => {
        const r = RESPONSES[k]
        return r.kind === 'choice' ? r.attempts.length > 0 : (r.chars > 0 || r.inkStrokes > 0 || r.submittedAt != null)
      }).length,
    }
    if (document.documentElement.dataset.onparRuntime !== 'failed') {
      document.documentElement.dataset.onparRuntime = 'ready'
    }
  } catch (e) {
    markRuntimeFailed(e)
  }
}

if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot)
  else boot()
}
