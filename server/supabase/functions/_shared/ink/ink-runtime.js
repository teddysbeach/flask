// 필기 런타임의 DOM 계층. 캔버스·포인터 이벤트·Flutter 브리지만 담당한다.
// 판단이 필요한 로직은 전부 ink-core.js 에 있고 거기서 테스트된다.
//
// 학습지 HTML 안에서 돌아간다. 본문과 캔버스가 같은 스크롤 컨테이너에 있으므로
// 스크롤 동기화 문제가 애초에 생기지 않는다. docs/plan/06-annotation.md §1

import * as core from './ink-core.js'

const DPR_CAP = 3   // 초고해상도에서 캔버스 메모리가 터지지 않게 상한을 둔다

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
  let activePointerId = null
  let allowFinger = false
  let enabled = false
  let rafPending = false

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
    for (const s of state.strokes) drawStroke(s)
    if (drawing) drawStroke(drawing)
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

  function onDown(e) {
    if (!accepts(e) || activePointerId !== null) return
    activePointerId = e.pointerId
    canvas.setPointerCapture(e.pointerId)
    const { x, y } = toDoc(e)

    if (tool.kind === 'eraser') {
      eraseAt(x, y)
      return
    }
    drawing = core.createStroke(
      tool.kind, tool.color, tool.width,
      core.newStrokeId(Date.now()), Date.now(),
    )
    core.appendPoint(drawing, x, y, e.pressure)
    scheduleRedraw()
  }

  function onMove(e) {
    if (e.pointerId !== activePointerId) return
    // ProMotion 120Hz 샘플을 놓치면 빠르게 그은 획이 각져 보인다.
    const events = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : [e]
    let changed = false
    for (const p of events) {
      const { x, y } = toDoc(p)
      if (tool.kind === 'eraser') { changed = eraseAt(x, y) || changed }
      else if (drawing) { changed = core.appendPoint(drawing, x, y, p.pressure) || changed }
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
      scheduleRedraw()
    }
    flushErase()
  }

  // ── 지우개 ─────────────────────────────────────────────────────────────
  let erasedInGesture = []
  function eraseAt(x, y) {
    const radius = 12
    const hit = state.strokes.filter((s) => core.strokeHitTest(s, x, y, radius))
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
    bridge('strokesChanged', {
      count: state.strokes.length,
      canUndo: undo.canUndo,
      canRedo: undo.canRedo,
    })
  }

  // ── 공개 API (Flutter 가 부른다) ────────────────────────────────────────
  const api = {
    setTool(next) {
      tool = { kind: next.tool, color: next.color || tool.color, width: next.width || tool.width }
      // 필기 모드일 때만 캔버스가 포인터를 먹는다. 아니면 본문 스크롤·선택이 막힌다.
      enabled = next.tool !== 'none'
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
    scrollToQuiz(quizId) {
      const el = document.querySelector(`[data-quiz-id="${CSS.escape(quizId)}"]`)
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' })
      return !!el
    },
  }

  canvas.addEventListener('pointerdown', onDown)
  canvas.addEventListener('pointermove', onMove)
  canvas.addEventListener('pointerup', onUp)
  canvas.addEventListener('pointercancel', onUp)
  globalThis.addEventListener('resize', resize)

  api.setTool({ tool: 'none' })
  resize()
  return api
}

// 학습지 HTML 안에서 자동 기동한다.
if (typeof document !== 'undefined') {
  const boot = () => {
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
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot)
  else boot()
}
