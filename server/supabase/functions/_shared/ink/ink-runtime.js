// 필기 런타임의 DOM 계층. 캔버스·포인터 이벤트·Flutter 브리지만 담당한다.
// 판단이 필요한 로직은 전부 ink-core.js 에 있고 거기서 테스트된다.
//
// 학습지 HTML 안에서 돌아간다. 본문과 캔버스가 같은 스크롤 컨테이너에 있으므로
// 스크롤 동기화 문제가 애초에 생기지 않는다. docs/plan/06-annotation.md §1
//
// v2: 획은 가능하면 [data-ink-anchor] 요소에 묶인다(요소 기준 정규화 좌표).
// 콘텐츠가 주체다 — 레이아웃이 바뀌면 필기가 따라간다. 앵커 밖(여백)에 그은 획만 문서 좌표다.

import * as core from './ink-core.js'

const DPR_CAP = 3   // 초고해상도에서 캔버스 메모리가 터지지 않게 상한을 둔다

const cssEscape = (s) =>
  (typeof CSS !== 'undefined' && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\]/g, '\\$&')

export function createInkLayer(opts) {
  const canvas = opts.canvas
  const sheet = opts.sheet
  const ctx = canvas.getContext('2d')
  const bridge = opts.bridge || (() => {})

  const state = { strokes: [], deleted: new Set() }
  const undo = new core.UndoStack(50)

  let tool = { kind: 'pen', color: '#111111', width: 2.4 }
  let scale = 1
  let drawing = null
  let drawingAnchorRect = null   // 획을 긋는 동안 앵커 요소의 화면 사각형(레이아웃 재측정 방지)
  let activePointerId = null
  let allowFinger = false
  let enabled = false
  let rafPending = false

  // ── 앵커 ───────────────────────────────────────────────────────────────
  const anchorEl = (id) =>
    id ? document.querySelector(`[data-ink-anchor="${cssEscape(id)}"]`) : null

  /**
   * 앵커 요소의 사각형을 캔버스 로컬 좌표(그리기 좌표계)로 옮긴다.
   * getBoundingClientRect 는 transform: scale 이 반영된 값이라 배율로 나눠야 한다.
   * 한 프레임 안에서 같은 앵커를 여러 번 묻게 되므로 캐시를 만들어 쓴다(레이아웃 스래싱 방지).
   */
  function rectResolver() {
    const c = canvas.getBoundingClientRect()
    const memo = new Map()
    return (id) => {
      if (!id) return null
      if (memo.has(id)) return memo.get(id)
      const el = anchorEl(id)
      let r = null
      if (el) {
        const b = el.getBoundingClientRect()
        r = {
          left: (b.left - c.left) / scale, top: (b.top - c.top) / scale,
          width: b.width / scale, height: b.height / scale,
        }
      }
      memo.set(id, r)     // 요소가 사라졌으면 null 을 기억한다 — 획은 남기되 그리지 않는다
      return r
    }
  }

  /** 포인터 아래에서 가장 가까운 필기 앵커. 없으면 null(= 문서 좌표로 저장). */
  function anchorAt(clientX, clientY) {
    if (typeof document.elementsFromPoint !== 'function') return null
    const hits = document.elementsFromPoint(clientX, clientY) || []
    for (const el of hits) {
      const id = el && el.dataset ? el.dataset.inkAnchor : null
      if (id) return id
    }
    return null
  }

  // ── 캔버스 크기 ────────────────────────────────────────────────────────
  function resize() {
    const dpr = Math.min(globalThis.devicePixelRatio || 1, DPR_CAP)
    const w = sheet.offsetWidth
    const h = sheet.offsetHeight
    canvas.width = Math.round(w * dpr)
    canvas.height = Math.round(h * dpr)
    canvas.style.width = w + 'px'
    canvas.style.height = h + 'px'
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    redraw()
  }

  // ── 그리기 ─────────────────────────────────────────────────────────────
  function drawStroke(s) {
    const pts = core.strokePoints(s)
    if (pts.length === 0) return

    ctx.save()
    ctx.strokeStyle = s.color
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    if (s.tool === 'highlighter') {
      // 형광펜은 밑의 글자가 비쳐야 한다
      ctx.globalAlpha = 0.35
      ctx.globalCompositeOperation = 'multiply'
      ctx.lineWidth = s.width * 6
    }

    if (pts.length === 1) {
      ctx.fillStyle = s.color
      ctx.beginPath()
      ctx.arc(pts[0].x, pts[0].y, core.strokeWidthAt(s.width, pts[0].pressure) / 2, 0, Math.PI * 2)
      ctx.fill()
      ctx.restore()
      return
    }

    const segs = core.catmullRomToBezier(pts)
    if (s.tool === 'highlighter') {
      // 형광펜은 굵기가 일정해야 얼룩지지 않는다 — 한 번에 긋는다
      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (const g of segs) ctx.bezierCurveTo(g.cp1x, g.cp1y, g.cp2x, g.cp2y, g.x, g.y)
      ctx.stroke()
    } else {
      // 펜은 필압에 따라 굵기가 변하므로 구간마다 따로 긋는다
      for (let i = 0; i < segs.length; i++) {
        const g = segs[i]
        ctx.beginPath()
        ctx.lineWidth = core.strokeWidthAt(s.width, pts[i + 1].pressure)
        ctx.moveTo(pts[i].x, pts[i].y)
        ctx.bezierCurveTo(g.cp1x, g.cp1y, g.cp2x, g.cp2y, g.x, g.y)
        ctx.stroke()
      }
    }
    ctx.restore()
  }

  function redraw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const rectOf = rectResolver()
    for (const s of state.strokes) {
      // 앵커가 사라진 획(콘텐츠가 바뀐 경우)은 이번 프레임에 그리지 않을 뿐, 데이터는 그대로 둔다.
      const p = core.projectStroke(s, rectOf(s.anchor))
      if (p) drawStroke(p)
    }
    if (drawing) {
      const live = drawing.anchor
        ? core.projectStroke(drawing, rectOf(drawing.anchor))
        : drawing
      if (live) drawStroke(live)
    }
  }

  function scheduleRedraw() {
    if (rafPending) return
    rafPending = true
    globalThis.requestAnimationFrame(() => { rafPending = false; redraw() })
  }

  // ── 포인터 ─────────────────────────────────────────────────────────────
  function accepts(e) {
    if (!enabled) return false
    if (e.pointerType === 'pen') return true          // Apple Pencil
    if (e.pointerType === 'mouse') return true
    return allowFinger                                 // 손가락은 설정에서 켤 때만 (팜 리젝션)
  }

  const toDoc = (e) => core.toDocCoords(e.clientX, e.clientY, canvas.getBoundingClientRect(), scale)

  /** 진행 중인 획의 좌표계로 포인터를 옮긴다. 앵커가 있으면 정규화 좌표, 없으면 문서 좌표. */
  function toStrokeCoords(e) {
    if (drawing && drawing.anchor && drawingAnchorRect) {
      return core.toAnchorCoords(e.clientX, e.clientY, drawingAnchorRect)
    }
    return toDoc(e)
  }

  function onDown(e) {
    if (!accepts(e) || activePointerId !== null) return
    activePointerId = e.pointerId
    canvas.setPointerCapture(e.pointerId)

    if (tool.kind === 'eraser') {
      const { x, y } = toDoc(e)
      eraseAt(x, y)
      return
    }
    // 획을 시작한 자리 아래에 필기 앵커가 있으면 그 요소에 묶는다.
    // 한 획이 두 좌표계를 오갈 수는 없으므로 앵커는 시작점에서 한 번만 정한다.
    const anchor = anchorAt(e.clientX, e.clientY)
    const el = anchorEl(anchor)
    drawingAnchorRect = el ? el.getBoundingClientRect() : null
    drawing = core.createStroke(
      tool.kind, tool.color, tool.width,
      core.newStrokeId(Date.now()), Date.now(),
      drawingAnchorRect ? anchor : null,
    )
    const { x, y } = toStrokeCoords(e)
    core.appendPoint(drawing, x, y, e.pressure)
    scheduleRedraw()
  }

  function onMove(e) {
    if (e.pointerId !== activePointerId) return
    // ProMotion 120Hz 샘플을 놓치면 빠르게 그은 획이 각져 보인다.
    const events = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : [e]
    let changed = false
    const rectOf = tool.kind === 'eraser' ? rectResolver() : null
    for (const p of events) {
      if (tool.kind === 'eraser') {
        const { x, y } = toDoc(p)
        changed = eraseAt(x, y, rectOf) || changed
      } else if (drawing) {
        const { x, y } = toStrokeCoords(p)
        changed = core.appendPoint(drawing, x, y, p.pressure) || changed
      }
    }
    if (changed) scheduleRedraw()
  }

  function onUp(e) {
    if (e.pointerId !== activePointerId) return
    activePointerId = null
    try { canvas.releasePointerCapture(e.pointerId) } catch { /* 이미 해제됨 */ }

    if (drawing) {
      if (core.pointCount(drawing) > 0) {
        state.strokes.push(drawing)
        undo.push({ type: 'add', stroke: drawing })
        notifyChanged()
      }
      drawing = null
      drawingAnchorRect = null
      scheduleRedraw()
    }
    flushErase()
  }

  // ── 지우개 ─────────────────────────────────────────────────────────────
  // 히트 테스트는 캔버스 로컬 좌표에서 한다. 앵커 획은 그 좌표계로 펴서 비교한다 —
  // 정규화 좌표와 문서 좌표를 그냥 비교하면 지우개가 엉뚱한 획을 지운다.
  let erasedInGesture = []
  function eraseAt(x, y, rectOf) {
    const radius = 12
    const resolve = rectOf || rectResolver()
    const hit = state.strokes.filter((s) => {
      const p = core.projectStroke(s, resolve(s.anchor))
      return p ? core.strokeHitTest(p, x, y, radius) : false   // 안 보이는 획은 못 지운다
    })
    if (hit.length === 0) return false
    const ids = new Set(hit.map((s) => s.id))
    state.strokes = state.strokes.filter((s) => !ids.has(s.id))
    for (const id of ids) state.deleted.add(id)
    erasedInGesture.push(...hit)
    return true
  }
  function flushErase() {
    if (erasedInGesture.length === 0) return
    // 한 번의 지우개 제스처는 하나의 되돌리기 단위여야 한다
    undo.push({ type: 'erase', strokes: erasedInGesture })
    erasedInGesture = []
    notifyChanged()
    scheduleRedraw()
  }

  // ── 브리지 알림 ────────────────────────────────────────────────────────
  function notifyChanged() {
    const byAnchor = core.countByAnchor(state.strokes)
    bridge('strokesChanged', {
      count: state.strokes.length,
      byAnchor,
      canUndo: undo.canUndo,
      canRedo: undo.canRedo,
    })
    // 학습 런타임(worksheet-interact)이 같은 번들의 다른 스코프에 있다. DOM 이벤트로 알린다.
    // 필기도 "답을 적었다"는 증거이므로 서술형 응답의 inkStrokes 가 이 값을 읽는다.
    try {
      document.dispatchEvent(new CustomEvent('onpar:ink', {
        detail: { count: state.strokes.length, byAnchor },
      }))
    } catch { /* CustomEvent 가 없는 아주 오래된 엔진 */ }
  }

  // ── 공개 API (Flutter 가 부른다) ────────────────────────────────────────
  const api = {
    setTool(next) {
      // 문자열로 부르는 실수가 잦다. 상태를 망가뜨린 뒤 스트로크를 만들 때 터지면
      // 원인을 찾기 어렵다 — 여기서 바로 막고, 도구는 이전 값을 유지한다.
      const kind = typeof next === 'string' ? next : next && next.tool
      if (kind !== 'none' && !core.TOOLS.includes(kind)) {
        throw new Error(`알 수 없는 도구: ${kind} (${core.TOOLS.join(', ')} 또는 none)`)
      }
      const opts = typeof next === 'string' ? {} : next
      tool = { kind, color: opts.color || tool.color, width: opts.width || tool.width }
      // 필기 모드일 때만 캔버스가 포인터를 먹는다. 아니면 본문 스크롤·선택이 막힌다.
      enabled = kind !== 'none'
      canvas.style.pointerEvents = enabled ? 'auto' : 'none'
    },
    setFingerDrawing(on) { allowFinger = !!on },
    setZoom(next) {
      scale = next || 1
      sheet.parentElement.style.transform = `scale(${scale})`
      resize()
    },
    undo() {
      const a = undo.undo()
      if (!a) return
      core.applyUndo(state, a)
      notifyChanged(); scheduleRedraw()
    },
    redo() {
      const a = undo.redo()
      if (!a) return
      core.applyRedo(state, a)
      notifyChanged(); scheduleRedraw()
    },
    clearAll() {
      if (state.strokes.length === 0) return
      undo.push({ type: 'erase', strokes: [...state.strokes] })
      for (const s of state.strokes) state.deleted.add(s.id)
      state.strokes = []
      notifyChanged(); scheduleRedraw()
    },
    loadStrokes(data) {
      const parsed = core.deserialize(data)
      state.strokes = parsed.strokes
      state.deleted = parsed.deleted
      undo.clear()
      notifyChanged(); scheduleRedraw()
    },
    /** 저장용 스냅샷. Flutter 가 디바운스해서 가져간다. */
    exportStrokes() {
      return core.serialize(state.strokes, {
        sheetWidth: sheet.offsetWidth,
        docHeight: sheet.offsetHeight,
        deleted: state.deleted,
      })
    },
    /** 앵커별 스트로크 수. 서술형 응답이 "필기로 답했다"를 판단하는 근거. */
    strokeCountByAnchor() { return core.countByAnchor(state.strokes) },
    strokeCountFor(anchorId) { return core.countByAnchor(state.strokes)[anchorId] || 0 },
    /** 레이아웃이 바뀐 뒤 앵커 좌표를 다시 펴서 그린다. */
    refresh() { scheduleRedraw() },
    scrollToQuiz(quizId) {
      const el = document.querySelector(`[data-quiz-id="${cssEscape(quizId)}"]`)
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' })
      return !!el
    },
  }

  canvas.addEventListener('pointerdown', onDown)
  canvas.addEventListener('pointermove', onMove)
  canvas.addEventListener('pointerup', onUp)
  canvas.addEventListener('pointercancel', onUp)
  globalThis.addEventListener('resize', resize)

  // 앵커 좌표는 요소의 현재 크기에 매달려 있다. 레이아웃이 바뀌면 다시 그려야 제자리에 남는다.
  // (textarea 가 늘어나거나, 폰트가 늦게 로드되거나, 화면을 돌렸을 때)
  if (typeof ResizeObserver === 'function') {
    const ro = new ResizeObserver(() => resize())
    ro.observe(sheet)
    for (const el of document.querySelectorAll('[data-ink-anchor]')) ro.observe(el)
  }

  api.setTool({ tool: 'none' })
  resize()
  return api
}

// 학습지 HTML 안에서 자동 기동한다.
// 어디서 터지든 문서는 읽을 수 있어야 한다 — 필기가 안 되는 학습지는 불편하지만,
// 본문이 안 보이는 학습지는 쓸모가 없다.
if (typeof document !== 'undefined') {
  const boot = () => {
    try {
      const canvas = document.getElementById('ink-layer')
      const sheet = document.querySelector('.sheet')
      if (!canvas || !sheet) return
      globalThis.ONPAR_INK = createInkLayer({
        canvas,
        sheet,
        bridge: (type, payload) => {
          // Flutter(flutter_inappwebview)가 핸들러를 심어두면 그쪽으로, 없으면 조용히 무시한다.
          const h = globalThis.flutter_inappwebview
          if (h && typeof h.callHandler === 'function') h.callHandler('ink', { type, payload })
        },
      })
    } catch (e) {
      try { document.documentElement.dataset.onparRuntime = 'failed' } catch { /* 무시 */ }
      try { console.error('[onpar] 필기 런타임 기동 실패', e) } catch { /* 무시 */ }
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot)
  else boot()
}
