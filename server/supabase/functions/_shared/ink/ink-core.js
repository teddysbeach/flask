// 필기 엔진의 순수 로직. DOM 을 건드리지 않는다.
//
// DOM 글루(ink-runtime.js)와 분리한 이유는 이 부분이 틀리면 사용자 필기가 어긋나거나
// 사라지는데, 그런 버그는 브라우저에서 눈으로 잡기 어렵기 때문이다. 여기는 전부 테스트한다.
//
// 좌표 규약(v2): 스트로크마다 둘 중 하나다.
//
//   anchor: "quiz-3"  → points 는 그 요소 기준 정규화 좌표(0~1). 요소 밖으로 삐져나간 획도
//                       담아야 하므로 0~1 을 벗어나는 값을 허용한다.
//   anchor: null      → 예전(v1)처럼 문서 좌표(CSS px, --ds-sheet-width 기준).
//
// 앵커를 도입한 이유: v1 은 "필기가 안 어긋나는 것"을 위해 "콘텐츠가 반응형이 되는 것"을
// 포기한 설계였다. 820px 고정 문서를 390px 폰에서 0.48배로 축소하면 18px 본문이 8.6px 가 된다.
// 콘텐츠가 주체이고 필기가 따라가야 한다. 요소 기준 좌표면 레이아웃이 바뀌어도
// "그 문장 위에 그은 밑줄" 이 계속 그 문장 위에 남는다.
// docs/plan/06-annotation.md §2 (v2 로 갱신 필요)

export const FORMAT_VERSION = 2

/** 문서 좌표 저장 정밀도. 소수점 1자리면 시각적 차이가 없으면서 용량이 크게 준다. */
export const COORD_PRECISION = 1

/**
 * 정규화 좌표 저장 정밀도. 문서 좌표와 단위가 다르므로 자릿수도 다르다.
 * 4자리면 820px 요소에서 0.08px, 390px 요소에서 0.04px — 눈에 보이지 않는다.
 * 1자리로 두면 82px 격자로 뭉개져 필기가 아니라 점묘가 된다.
 */
export const ANCHOR_COORD_PRECISION = 4

/** 점 간 최소 거리(문서 px). 이보다 촘촘한 점은 버린다. */
export const MIN_POINT_DISTANCE = 0.7

/** 앵커 좌표에서의 최소 거리(요소 폭 대비 비율). 390px 요소에서 약 0.8px. */
export const MIN_ANCHOR_POINT_DISTANCE = 0.002

export const TOOLS = ['pen', 'highlighter']

const roundTo = (n, p) => Math.round(n * 10 ** p) / 10 ** p
const round = (n) => roundTo(n, COORD_PRECISION)

/** 정규화 좌표 반올림. 두 좌표계가 섞이므로 반올림 함수도 둘이다. */
export function roundAnchorCoord(n) {
  return roundTo(n, ANCHOR_COORD_PRECISION)
}

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

/**
 * 화면 좌표 → 앵커 요소 기준 정규화 좌표.
 *
 * rect 는 앵커 요소의 사각형(getBoundingClientRect 든, 캔버스 기준으로 옮긴 것이든
 * left/top/width/height 만 있으면 된다). 폭·높이로 나누므로 배율(transform: scale)이
 * 걸려 있어도 결과가 같다 — 이게 반응형에서 필기가 안 어긋나는 이유다.
 *
 * 0~1 로 자르지 않는다. 밑줄이 문장 끝을 살짝 넘어가는 건 정상이고, 자르면 획이 뭉개진다.
 */
export function toAnchorCoords(clientX, clientY, anchorRect) {
  const w = anchorRect.width || 1
  const h = anchorRect.height || 1
  return {
    x: roundAnchorCoord((clientX - anchorRect.left) / w),
    y: roundAnchorCoord((clientY - anchorRect.top) / h),
  }
}

/** 정규화 좌표 → 화면(또는 캔버스) 좌표. toAnchorCoords 의 역함수. */
export function fromAnchorCoords(nx, ny, anchorRect) {
  return {
    x: anchorRect.left + nx * (anchorRect.width || 1),
    y: anchorRect.top + ny * (anchorRect.height || 1),
  }
}

/**
 * 앵커 스트로크를 그릴 수 있는 좌표계로 편다.
 * anchorRect 가 없으면(요소가 사라졌으면) null — 버리는 게 아니라 "이번엔 그리지 않는다".
 */
export function projectStroke(stroke, anchorRect) {
  if (!stroke.anchor) return stroke
  if (!anchorRect) return null
  const points = []
  for (let i = 0; i < stroke.points.length; i += 3) {
    const { x, y } = fromAnchorCoords(stroke.points[i], stroke.points[i + 1], anchorRect)
    points.push(x, y, stroke.points[i + 2])
  }
  return { ...stroke, points }
}

/** 앵커별 스트로크 수. 서술형 응답의 inkStrokes 가 이걸 읽는다. */
export function countByAnchor(strokes) {
  const out = {}
  for (const s of strokes) {
    if (!s.anchor) continue
    out[s.anchor] = (out[s.anchor] || 0) + 1
  }
  return out
}

// ── 스트로크 ─────────────────────────────────────────────────────────────

/**
 * 스트로크 하나. points 는 [x, y, pressure] 를 3개씩 평탄화한 배열이다.
 * 객체 배열({x,y,p})보다 JSON 크기가 60% 가까이 작다. 필기가 쌓이면 이 차이가 커진다.
 */
export function createStroke(tool, color, width, id, createdAt, anchor = null) {
  if (!TOOLS.includes(tool)) throw new Error(`알 수 없는 도구: ${tool}`)
  return { id, tool, color, width, createdAt, anchor: anchor || null, points: [] }
}

/**
 * 점을 추가한다. 너무 촘촘하면 버리고 false 를 돌려준다.
 * 첫 점은 언제나 추가한다(탭 한 번도 점으로 남아야 한다).
 *
 * 반올림 자릿수와 최소 거리는 스트로크의 좌표계를 따른다 — 앵커 스트로크에 문서 좌표용
 * 0.7px 을 쓰면 정규화 공간에서 0.7 은 요소의 70% 라 획이 두 점으로 줄어든다.
 */
export function appendPoint(stroke, x, y, pressure, minDistance) {
  const anchored = !!stroke.anchor
  const r = anchored ? roundAnchorCoord : round
  const min = minDistance != null
    ? minDistance
    : (anchored ? MIN_ANCHOR_POINT_DISTANCE : MIN_POINT_DISTANCE)
  const p = clampPressure(pressure)
  const n = stroke.points.length
  if (n === 0) {
    stroke.points.push(r(x), r(y), p)
    return true
  }
  const lastX = stroke.points[n - 3]
  const lastY = stroke.points[n - 2]
  if (Math.hypot(x - lastX, y - lastY) < min) return false
  stroke.points.push(r(x), r(y), p)
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
      anchor: s.anchor || null,
      points: s.points,
    })),
  }
}

/**
 * 옛 포맷을 현재 포맷으로 올린다. 원본은 건드리지 않는다.
 *
 * v1 → v2: 스트로크에 anchor: null 을 채운다. v1 좌표는 전부 문서 좌표였고
 * anchor: null 이 정확히 그 뜻이므로 좌표는 손대지 않는다. 손대면 옛 필기가 움직인다.
 */
export function migrateStrokes(doc) {
  if (!doc || typeof doc !== 'object') return doc
  const v = doc.format_version
  if (v === FORMAT_VERSION) return doc
  if (v === 1) {
    return {
      ...doc,
      format_version: FORMAT_VERSION,
      strokes: (doc.strokes || []).map((s) => ({ ...s, anchor: s.anchor ?? null })),
    }
  }
  // 미래 포맷을 억지로 읽으면 필기가 깨진 채로 저장될 수 있다. 읽지 않는 쪽이 안전하다.
  throw new Error(`지원하지 않는 필기 포맷 버전: ${v} (지원: ${FORMAT_VERSION} 이하)`)
}

export function deserialize(data) {
  if (!data || typeof data !== 'object') return { strokes: [], deleted: new Set(), meta: null }
  const doc = migrateStrokes(data)
  const strokes = (doc.strokes || []).map((s) => ({
    id: s.id,
    tool: s.tool,
    color: s.color,
    width: s.width,
    createdAt: s.created_at,
    anchor: s.anchor || null,
    points: s.points || [],
  }))
  return {
    strokes,
    deleted: new Set(doc.deleted || []),
    meta: { sheetWidth: doc.sheet_width, docHeight: doc.doc_height },
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
