// 필기 엔진의 순수 로직. DOM 을 건드리지 않는다.
//
// DOM 글루(ink-runtime.js)와 분리한 이유는 이 부분이 틀리면 사용자 필기가 어긋나거나
// 사라지는데, 그런 버그는 브라우저에서 눈으로 잡기 어렵기 때문이다. 여기는 전부 테스트한다.
//
// 좌표 규약: 모든 좌표는 "문서 좌표계"다. 단위는 CSS px, 기준은 --ds-sheet-width(820).
// 화면 크기·줌·기기와 무관한 절대 좌표라, 회전하거나 다른 기기에서 열어도 같은 자리에 남는다.
// docs/plan/06-annotation.md §2

export const FORMAT_VERSION = 1

/** 좌표 저장 정밀도. 소수점 1자리면 시각적 차이가 없으면서 용량이 크게 준다. */
export const COORD_PRECISION = 1

/** 점 간 최소 거리(문서 px). 이보다 촘촘한 점은 버린다. */
export const MIN_POINT_DISTANCE = 0.7

export const TOOLS = ['pen', 'highlighter']

const round = (n) => Math.round(n * 10 ** COORD_PRECISION) / 10 ** COORD_PRECISION

// ── 좌표 변환 ────────────────────────────────────────────────────────────

/**
 * 포인터의 화면 좌표 → 문서 좌표.
 *
 * 캔버스가 문서 흐름 안에 있으므로 rect 는 스크롤이 이미 반영된 값이다.
 * 그래서 scrollTop 을 따로 더하지 않는다 — 더하면 두 번 반영되어 어긋난다.
 * (Flutter 오버레이 방식을 버린 이유가 정확히 이 계산을 손으로 해야 해서다.)
 */
export function toDocCoords(clientX, clientY, rect, scale) {
  const s = scale || 1
  return { x: (clientX - rect.left) / s, y: (clientY - rect.top) / s }
}

/** 문서 폭을 화면 폭에 맞추는 배율. 확대는 하지 않고 축소만 한다. */
export function fitScale(viewportWidth, sheetWidth, maxScale = 1) {
  if (!viewportWidth || !sheetWidth) return 1
  return Math.min(viewportWidth / sheetWidth, maxScale)
}

// ── 스트로크 ─────────────────────────────────────────────────────────────

/**
 * 스트로크 하나. points 는 [x, y, pressure] 를 3개씩 평탄화한 배열이다.
 * 객체 배열({x,y,p})보다 JSON 크기가 60% 가까이 작다. 필기가 쌓이면 이 차이가 커진다.
 */
export function createStroke(tool, color, width, id, createdAt) {
  if (!TOOLS.includes(tool)) throw new Error(`알 수 없는 도구: ${tool}`)
  return { id, tool, color, width, createdAt, points: [] }
}

/**
 * 점을 추가한다. 너무 촘촘하면 버리고 false 를 돌려준다.
 * 첫 점은 언제나 추가한다(탭 한 번도 점으로 남아야 한다).
 */
export function appendPoint(stroke, x, y, pressure, minDistance = MIN_POINT_DISTANCE) {
  const p = clampPressure(pressure)
  const n = stroke.points.length
  if (n === 0) {
    stroke.points.push(round(x), round(y), p)
    return true
  }
  const lastX = stroke.points[n - 3]
  const lastY = stroke.points[n - 2]
  if (Math.hypot(x - lastX, y - lastY) < minDistance) return false
  stroke.points.push(round(x), round(y), p)
  return true
}

/** 필압이 없는 입력(마우스/손가락)은 1로 온다. 0 은 '정보 없음'이므로 0.5 로 본다. */
export function clampPressure(pressure) {
  if (typeof pressure !== 'number' || !Number.isFinite(pressure)) return 0.5
  if (pressure <= 0) return 0.5
  return Math.round(Math.min(pressure, 1) * 100) / 100
}

/** 필압 → 선 굵기. 0 압력에서도 선이 사라지지 않게 하한을 둔다. */
export function strokeWidthAt(baseWidth, pressure) {
  return baseWidth * (0.35 + 0.65 * clampPressure(pressure))
}

export function pointCount(stroke) {
  return stroke.points.length / 3
}

export function pointAt(stroke, i) {
  const o = i * 3
  return { x: stroke.points[o], y: stroke.points[o + 1], pressure: stroke.points[o + 2] }
}

/** 스트로크의 경계 상자. 타일링과 지우개 1차 필터에 쓴다. */
export function strokeBounds(stroke) {
  const n = pointCount(stroke)
  if (n === 0) return null
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (let i = 0; i < n; i++) {
    const o = i * 3
    const x = stroke.points[o], y = stroke.points[o + 1]
    if (x < minX) minX = x
    if (x > maxX) maxX = x
    if (y < minY) minY = y
    if (y > maxY) maxY = y
  }
  const pad = stroke.width
  return { minX: minX - pad, minY: minY - pad, maxX: maxX + pad, maxY: maxY + pad }
}

// ── 스무딩 ───────────────────────────────────────────────────────────────

/**
 * Catmull-Rom 스플라인을 3차 베지에 제어점으로 바꾼다.
 * 점을 직선으로 이으면 빠르게 그은 획이 각져 보인다. 사람 눈에 바로 띈다.
 */
export function catmullRomToBezier(points) {
  const n = points.length
  if (n < 2) return []
  const segs = []
  for (let i = 0; i < n - 1; i++) {
    const p0 = points[i - 1] || points[i]
    const p1 = points[i]
    const p2 = points[i + 1]
    const p3 = points[i + 2] || p2
    segs.push({
      cp1x: p1.x + (p2.x - p0.x) / 6,
      cp1y: p1.y + (p2.y - p0.y) / 6,
      cp2x: p2.x - (p3.x - p1.x) / 6,
      cp2y: p2.y - (p3.y - p1.y) / 6,
      x: p2.x,
      y: p2.y,
    })
  }
  return segs
}

export function strokePoints(stroke) {
  const out = []
  for (let i = 0; i < pointCount(stroke); i++) out.push(pointAt(stroke, i))
  return out
}

// ── 지우개 (획 단위) ──────────────────────────────────────────────────────

/** 점과 선분 사이 거리. 지우개 히트 테스트의 핵심. */
export function distanceToSegment(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay
  const lenSq = dx * dx + dy * dy
  if (lenSq === 0) return Math.hypot(px - ax, py - ay)
  let t = ((px - ax) * dx + (py - ay) * dy) / lenSq
  t = Math.max(0, Math.min(1, t))
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
}

/**
 * 지우개가 이 스트로크에 닿았는가.
 * 픽셀 지우개가 아니라 획 단위로 지운다 — 벡터 모델과 충돌하지 않고, 되돌리기가 정확해진다.
 */
export function strokeHitTest(stroke, x, y, radius) {
  const b = strokeBounds(stroke)
  if (!b) return false
  if (x < b.minX - radius || x > b.maxX + radius || y < b.minY - radius || y > b.maxY + radius) {
    return false                       // 경계 상자로 먼저 걸러낸다
  }
  const n = pointCount(stroke)
  const threshold = radius + stroke.width / 2
  if (n === 1) {
    const p = pointAt(stroke, 0)
    return Math.hypot(x - p.x, y - p.y) <= threshold
  }
  for (let i = 0; i < n - 1; i++) {
    const a = pointAt(stroke, i), c = pointAt(stroke, i + 1)
    if (distanceToSegment(x, y, a.x, a.y, c.x, c.y) <= threshold) return true
  }
  return false
}

// ── 타일링 ───────────────────────────────────────────────────────────────

export const TILE_HEIGHT = 2000

/**
 * 문서가 길면 캔버스 하나로는 GPU 메모리를 압박한다. 세로로 잘라 뷰포트 근처만 그린다.
 * 스트로크가 타일 경계를 걸치면 양쪽 타일에 모두 속한다.
 */
export function strokeTileRange(stroke, tileHeight = TILE_HEIGHT) {
  const b = strokeBounds(stroke)
  if (!b) return null
  return {
    first: Math.max(0, Math.floor(b.minY / tileHeight)),
    last: Math.max(0, Math.floor(b.maxY / tileHeight)),
  }
}

export function visibleTiles(scrollTop, viewportHeight, tileHeight = TILE_HEIGHT, overscan = 1) {
  const first = Math.max(0, Math.floor(scrollTop / tileHeight) - overscan)
  const last = Math.floor((scrollTop + viewportHeight) / tileHeight) + overscan
  const tiles = []
  for (let t = first; t <= last; t++) tiles.push(t)
  return tiles
}

// ── 직렬화 ───────────────────────────────────────────────────────────────

export function serialize(strokes, meta) {
  return {
    format_version: FORMAT_VERSION,
    sheet_width: meta.sheetWidth,
    doc_height: meta.docHeight,
    deleted: meta.deleted ? [...meta.deleted].sort() : [],
    strokes: strokes.map((s) => ({
      id: s.id,
      tool: s.tool,
      color: s.color,
      width: s.width,
      created_at: s.createdAt,
      points: s.points,
    })),
  }
}

export function deserialize(data) {
  if (!data || typeof data !== 'object') return { strokes: [], deleted: new Set(), meta: null }
  if (data.format_version !== FORMAT_VERSION) {
    // 미래 포맷을 억지로 읽으면 필기가 깨진 채로 저장될 수 있다. 읽지 않는 쪽이 안전하다.
    throw new Error(`지원하지 않는 필기 포맷 버전: ${data.format_version} (지원: ${FORMAT_VERSION})`)
  }
  const strokes = (data.strokes || []).map((s) => ({
    id: s.id,
    tool: s.tool,
    color: s.color,
    width: s.width,
    createdAt: s.created_at,
    points: s.points || [],
  }))
  return {
    strokes,
    deleted: new Set(data.deleted || []),
    meta: { sheetWidth: data.sheet_width, docHeight: data.doc_height },
  }
}

// ── 병합 (기기 두 대에서 같은 학습지에 필기했을 때) ────────────────────────

/**
 * 스트로크는 append-only 이고 각자 고유 id 를 가지므로 합집합을 취하면 대부분 자연스럽게 합쳐진다.
 * 같은 획을 두 기기에서 똑같이 그리는 일은 없기 때문이다.
 * 지우개는 삭제된 id 목록(tombstone)으로 표현해서 병합 가능하게 만든다.
 *
 * 정렬은 (createdAt, id) 로 한다. 두 기기가 같은 순서에 도달해야 겹친 획의 위아래가 같아진다.
 */
export function mergeAnnotations(local, remote) {
  const byId = new Map()
  for (const s of local.strokes) byId.set(s.id, s)
  for (const s of remote.strokes) if (!byId.has(s.id)) byId.set(s.id, s)

  const deleted = new Set([...(local.deleted || []), ...(remote.deleted || [])])
  for (const id of deleted) byId.delete(id)

  const strokes = [...byId.values()].sort((a, b) =>
    a.createdAt - b.createdAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))

  return { strokes, deleted }
}

// ── 되돌리기 ─────────────────────────────────────────────────────────────

/**
 * 되돌리기 스택. 스트로크 추가와 삭제를 대칭으로 다룬다.
 * 새 동작이 들어오면 redo 스택을 비운다(분기 히스토리는 사용자를 헷갈리게 한다).
 */
export class UndoStack {
  constructor(limit = 50) {
    this.limit = limit
    this.undoable = []
    this.redoable = []
  }
  push(action) {
    this.undoable.push(action)
    if (this.undoable.length > this.limit) this.undoable.shift()
    this.redoable.length = 0
  }
  get canUndo() { return this.undoable.length > 0 }
  get canRedo() { return this.redoable.length > 0 }
  undo() {
    const a = this.undoable.pop()
    if (a) this.redoable.push(a)
    return a || null
  }
  redo() {
    const a = this.redoable.pop()
    if (a) this.undoable.push(a)
    return a || null
  }
  clear() { this.undoable.length = 0; this.redoable.length = 0 }
}

/** 되돌리기 동작을 필기 상태에 적용한다. undo/redo 가 서로 정확히 반대여야 한다. */
export function applyUndo(state, action) {
  if (action.type === 'add') {
    state.strokes = state.strokes.filter((s) => s.id !== action.stroke.id)
  } else if (action.type === 'erase') {
    for (const s of action.strokes) {
      state.deleted.delete(s.id)
      state.strokes.push(s)
    }
    state.strokes.sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1))
  }
  return state
}

export function applyRedo(state, action) {
  if (action.type === 'add') {
    state.strokes.push(action.stroke)
    state.strokes.sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1))
  } else if (action.type === 'erase') {
    const ids = new Set(action.strokes.map((s) => s.id))
    state.strokes = state.strokes.filter((s) => !ids.has(s.id))
    for (const id of ids) state.deleted.add(id)
  }
  return state
}

/** 정렬 가능한 고유 id. 시간 접두사 덕에 병합 정렬이 안정적이다. */
export function newStrokeId(now, random) {
  const t = (now || Date.now()).toString(36).padStart(9, '0')
  const r = Math.floor((random != null ? random : Math.random()) * 0xfffff).toString(36).padStart(4, '0')
  return `s_${t}_${r}`
}
