// 필기 코어 테스트.  node app/tests/ink-core.test.mjs
import assert from 'node:assert/strict'
import * as ink from '../../server/supabase/functions/_shared/ink/ink-core.js'

let passed = 0
const failures = []
function test(name, fn) {
  try { fn(); passed++; console.log(`  PASS ${name}`) }
  catch (e) { failures.push(name); console.log(`  FAIL ${name}\n    ${e.message}`) }
}

const stroke = (pts, over = {}) => {
  const s = ink.createStroke(over.tool || 'pen', over.color || '#111', over.width || 2, over.id || 's1', over.createdAt ?? 1000)
  for (const [x, y, p] of pts) ink.appendPoint(s, x, y, p ?? 1, 0)
  return s
}

console.log('\n▸ 좌표 변환')

test('화면 좌표를 문서 좌표로 바꾼다', () => {
  const rect = { left: 20, top: 100 }
  assert.deepEqual(ink.toDocCoords(120, 300, rect, 1), { x: 100, y: 200 })
})

test('축소된 화면에서도 문서 좌표는 그대로다', () => {
  const rect = { left: 0, top: 0 }
  // 0.5배로 축소된 상태에서 화면상 (100,200)을 찍으면 문서 좌표는 (200,400)
  assert.deepEqual(ink.toDocCoords(100, 200, rect, 0.5), { x: 200, y: 400 })
})

test('스크롤은 rect 에 이미 반영되어 있으므로 따로 더하지 않는다', () => {
  // 문서 좌표 y=1000 지점이 화면 상단에 왔을 때 rect.top 은 -1000 이 된다.
  const scrolled = { left: 0, top: -1000 }
  const { y } = ink.toDocCoords(0, 0, scrolled, 1)
  assert.equal(y, 1000, '스크롤을 두 번 반영하면 필기가 어긋난다')
})

test('fitScale 은 축소만 하고 확대하지 않는다', () => {
  assert.equal(ink.fitScale(410, 820), 0.5)
  assert.equal(ink.fitScale(1640, 820), 1, '큰 화면에서 문서를 늘리면 안 된다')
})

console.log('\n▸ 요소 기준 좌표 (v2 앵커)')

const rect = (left, top, width, height) => ({ left, top, width, height })

test('정규화 좌표 왕복(round-trip)이 정확하다', () => {
  const r = rect(40, 200, 820, 120)
  for (const [cx, cy] of [[40, 200], [450, 260], [860, 320], [123.45, 271.8]]) {
    const n = ink.toAnchorCoords(cx, cy, r)
    const back = ink.fromAnchorCoords(n.x, n.y, r)
    assert.ok(Math.abs(back.x - cx) < 0.06, `x 왕복 오차: ${cx} → ${back.x}`)
    assert.ok(Math.abs(back.y - cy) < 0.02, `y 왕복 오차: ${cy} → ${back.y}`)
  }
})

test('요소 폭이 820 → 390 으로 바뀌어도 같은 상대 위치에 남는다', () => {
  // 820px 데스크톱에서 문장 한가운데(정확히는 60% 지점)에 밑줄을 긋는다
  const wide = rect(0, 0, 820, 100)
  const n = ink.toAnchorCoords(492, 40, wide)          // 60%, 40%
  assert.deepEqual(n, { x: 0.6, y: 0.4 })
  // 390px 폰에서 같은 요소가 좁아지고 아래로 밀려도
  const narrow = rect(12, 640, 390, 180)
  const p = ink.fromAnchorCoords(n.x, n.y, narrow)
  assert.equal(p.x, 12 + 390 * 0.6, '가로 상대 위치가 유지되어야 한다')
  assert.equal(p.y, 640 + 180 * 0.4, '세로 상대 위치가 유지되어야 한다')
})

test('요소 밖으로 삐져나간 획도 담는다 (0~1 로 자르지 않는다)', () => {
  const r = rect(100, 100, 200, 50)
  const n = ink.toAnchorCoords(320, 90, r)
  assert.ok(n.x > 1 && n.y < 0, `밑줄이 문장 끝을 넘어가는 건 정상이다: ${JSON.stringify(n)}`)
  const back = ink.fromAnchorCoords(n.x, n.y, r)
  assert.ok(Math.abs(back.x - 320) < 0.02 && Math.abs(back.y - 90) < 0.02)
})

test('정규화 좌표는 소수 4자리로 반올림한다 (문서 좌표는 1자리 그대로)', () => {
  const r = rect(0, 0, 3, 7)                            // 1/3, 1/7 → 무한소수
  const n = ink.toAnchorCoords(1, 1, r)
  assert.equal(n.x, 0.3333, `4자리여야 한다: ${n.x}`)
  assert.equal(n.y, 0.1429, `4자리여야 한다: ${n.y}`)
  assert.equal(ink.COORD_PRECISION, 1, '문서 좌표 정밀도는 그대로여야 한다')
  assert.equal(ink.ANCHOR_COORD_PRECISION, 4)

  // 스트로크에 담을 때도 좌표계에 맞는 자릿수를 쓴다 — 섞이면 필기가 뭉개진다
  const anchored = ink.createStroke('pen', '#111', 2, 'a1', 0, 'quiz-1')
  ink.appendPoint(anchored, 0.123456, 0.987654, 1, 0)
  assert.deepEqual(anchored.points.slice(0, 2), [0.1235, 0.9877])
  const doc = ink.createStroke('pen', '#111', 2, 'd1', 0)
  ink.appendPoint(doc, 0.123456, 0.987654, 1, 0)
  assert.deepEqual(doc.points.slice(0, 2), [0.1, 1])
})

test('앵커 스트로크의 최소 거리는 요소 비율 기준이다', () => {
  const s = ink.createStroke('pen', '#111', 2, 'a2', 0, 'quiz-1')
  assert.equal(ink.appendPoint(s, 0.5, 0.5, 1), true)
  assert.equal(ink.appendPoint(s, 0.5005, 0.5, 1), false, '요소의 0.05% 이동은 버려야 한다')
  assert.equal(ink.appendPoint(s, 0.52, 0.5, 1), true)
  assert.equal(ink.pointCount(s), 2, '문서 좌표용 0.7 을 쓰면 획이 두 점으로 줄어든다')
})

test('앵커 스트로크를 화면 좌표로 편다 (projectStroke)', () => {
  const s = ink.createStroke('pen', '#111', 2, 'a3', 0, 'q')
  ink.appendPoint(s, 0, 0, 1, 0)
  ink.appendPoint(s, 1, 1, 0.5, 0)
  const p = ink.projectStroke(s, rect(10, 20, 100, 40))
  assert.deepEqual(p.points, [10, 20, 1, 110, 60, 0.5])
  assert.deepEqual(s.points, [0, 0, 1, 1, 1, 0.5], '원본은 그대로여야 한다')
})

test('앵커가 사라진 획은 버리지 않고 이번 프레임만 건너뛴다', () => {
  const s = ink.createStroke('pen', '#111', 2, 'a4', 0, '사라진-요소')
  ink.appendPoint(s, 0.5, 0.5, 1, 0)
  assert.equal(ink.projectStroke(s, null), null, '그릴 수 없다는 신호는 null 이다')
  const data = ink.serialize([s], { sheetWidth: 820, docHeight: 1000 })
  const back = ink.deserialize(JSON.parse(JSON.stringify(data)))
  assert.equal(back.strokes.length, 1, '데이터 손실은 사용자 데이터 손상급이다')
  assert.equal(back.strokes[0].anchor, '사라진-요소')
})

test('앵커 없는 획은 예전처럼 문서 좌표 그대로 그린다', () => {
  const s = stroke([[100, 200]])
  assert.equal(s.anchor, null)
  assert.equal(ink.projectStroke(s, null), s, '문서 좌표 획은 앵커 rect 가 없어도 그린다')
})

test('앵커별 획 수를 센다 (서술형의 inkStrokes)', () => {
  const a = ink.createStroke('pen', '#111', 2, 'x1', 1, 'quiz-1')
  const b = ink.createStroke('pen', '#111', 2, 'x2', 2, 'quiz-1')
  const c = ink.createStroke('pen', '#111', 2, 'x3', 3, null)
  assert.deepEqual(ink.countByAnchor([a, b, c]), { 'quiz-1': 2 })
})

console.log('\n▸ 스트로크')

test('점을 [x,y,pressure] 3개씩 평탄화해서 담는다', () => {
  const s = stroke([[10, 20, 0.5], [30, 40, 0.8]])
  assert.deepEqual(s.points, [10, 20, 0.5, 30, 40, 0.8])
  assert.equal(ink.pointCount(s), 2)
  assert.deepEqual(ink.pointAt(s, 1), { x: 30, y: 40, pressure: 0.8 })
})

test('너무 촘촘한 점은 버린다', () => {
  const s = ink.createStroke('pen', '#111', 2, 'a', 0)
  assert.equal(ink.appendPoint(s, 0, 0, 1), true, '첫 점은 언제나 들어가야 한다')
  assert.equal(ink.appendPoint(s, 0.3, 0, 1), false, '0.3px 이동은 버려야 한다')
  assert.equal(ink.appendPoint(s, 5, 0, 1), true)
  assert.equal(ink.pointCount(s), 2)
})

test('좌표를 소수점 1자리로 줄인다', () => {
  const s = stroke([[10.16666, 20.4444]])
  assert.deepEqual(s.points.slice(0, 2), [10.2, 20.4])
})

test('필압 없는 입력(마우스)도 안전하게 처리한다', () => {
  assert.equal(ink.clampPressure(0), 0.5, 'pressure 0 은 정보 없음이지 압력 0 이 아니다')
  assert.equal(ink.clampPressure(undefined), 0.5)
  assert.equal(ink.clampPressure(NaN), 0.5)
  assert.equal(ink.clampPressure(2), 1, '1을 넘는 값은 잘라야 한다')
})

test('필압이 0이어도 선이 사라지지 않는다', () => {
  assert.ok(ink.strokeWidthAt(4, 0.001) > 0, '굵기 하한이 없으면 획이 증발한다')
  assert.ok(ink.strokeWidthAt(4, 1) > ink.strokeWidthAt(4, 0.2), '세게 누르면 굵어져야 한다')
})

test('알 수 없는 도구는 거부한다', () => {
  assert.throws(() => ink.createStroke('laser', '#111', 2, 'x', 0))
})

console.log('\n▸ 스무딩')

test('Catmull-Rom 이 점 개수에 맞는 베지에 구간을 만든다', () => {
  const pts = [{ x: 0, y: 0 }, { x: 10, y: 10 }, { x: 20, y: 0 }, { x: 30, y: 10 }]
  const segs = ink.catmullRomToBezier(pts)
  assert.equal(segs.length, 3)
  assert.equal(segs[2].x, 30, '마지막 구간이 마지막 점에서 끝나야 한다')
})

test('점이 하나뿐이면 구간이 없다', () => {
  assert.equal(ink.catmullRomToBezier([{ x: 0, y: 0 }]).length, 0)
})

console.log('\n▸ 지우개')

test('선분까지의 거리를 정확히 잰다', () => {
  assert.equal(ink.distanceToSegment(5, 5, 0, 0, 10, 0), 5)
  assert.equal(ink.distanceToSegment(-5, 0, 0, 0, 10, 0), 5, '선분 밖은 끝점까지 거리여야 한다')
  assert.equal(ink.distanceToSegment(0, 0, 3, 3, 3, 3), Math.hypot(3, 3), '길이 0 선분도 처리해야 한다')
})

test('획 위를 지우면 맞고, 멀리 있으면 안 맞는다', () => {
  const s = stroke([[0, 0], [100, 0]])
  assert.equal(ink.strokeHitTest(s, 50, 2, 5), true)
  assert.equal(ink.strokeHitTest(s, 50, 400, 5), false)
})

test('점 하나짜리 획(탭)도 지울 수 있다', () => {
  const s = stroke([[50, 50]])
  assert.equal(ink.strokeHitTest(s, 51, 51, 5), true)
})

console.log('\n▸ 타일링')

test('긴 획은 걸친 타일 전부에 속한다', () => {
  const s = stroke([[0, 100], [0, 4500]])
  assert.deepEqual(ink.strokeTileRange(s, 2000), { first: 0, last: 2 })
})

test('뷰포트 근처 타일만 그린다', () => {
  assert.deepEqual(ink.visibleTiles(4000, 1000, 2000, 1), [1, 2, 3])
})

console.log('\n▸ 직렬화')

test('직렬화 → 역직렬화가 원본을 보존한다', () => {
  const s = stroke([[1, 2, 0.4], [30, 40, 0.9]])
  const data = ink.serialize([s], { sheetWidth: 820, docHeight: 7000, deleted: new Set(['x']) })
  const back = ink.deserialize(JSON.parse(JSON.stringify(data)))
  assert.equal(back.strokes.length, 1)
  assert.deepEqual(back.strokes[0].points, s.points)
  assert.equal(back.strokes[0].createdAt, 1000)
  assert.ok(back.deleted.has('x'))
  assert.equal(back.meta.sheetWidth, 820)
})

test('직렬화에 앵커가 실린다', () => {
  const s = ink.createStroke('pen', '#111', 2, 's9', 5, 'quiz-2')
  ink.appendPoint(s, 0.25, 0.75, 1, 0)
  const data = ink.serialize([s], { sheetWidth: 390, docHeight: 4000 })
  assert.equal(data.format_version, 2)
  assert.equal(data.strokes[0].anchor, 'quiz-2')
  assert.equal(ink.deserialize(data).strokes[0].anchor, 'quiz-2')
})

test('v1(문서좌표) 데이터를 읽어도 깨지지 않는다', () => {
  const v1 = {
    format_version: 1, sheet_width: 820, doc_height: 7000, deleted: ['gone'],
    strokes: [{ id: 'old', tool: 'pen', color: '#111', width: 2.4, created_at: 900, points: [120.4, 331.2, 0.42] }],
  }
  const migrated = ink.migrateStrokes(v1)
  assert.equal(migrated.format_version, ink.FORMAT_VERSION)
  assert.equal(migrated.strokes[0].anchor, null, 'v1 좌표는 전부 문서 좌표였다')
  assert.deepEqual(migrated.strokes[0].points, [120.4, 331.2, 0.42], '좌표를 손대면 옛 필기가 움직인다')
  assert.equal(v1.format_version, 1, '원본을 변형하면 안 된다')

  const back = ink.deserialize(v1)
  assert.equal(back.strokes.length, 1)
  assert.equal(back.strokes[0].anchor, null)
  assert.deepEqual(back.strokes[0].points, [120.4, 331.2, 0.42])
  assert.ok(back.deleted.has('gone'))
})

test('이미 v2 인 데이터는 그대로 통과한다', () => {
  const v2 = { format_version: 2, strokes: [] }
  assert.equal(ink.migrateStrokes(v2), v2)
})

test('모르는 포맷 버전은 읽지 않는다', () => {
  assert.throws(() => ink.deserialize({ format_version: 99, strokes: [] }),
    /지원하지 않는 필기 포맷/, '억지로 읽으면 깨진 채로 덮어쓸 수 있다')
  assert.throws(() => ink.migrateStrokes({ format_version: 99, strokes: [] }),
    /지원하지 않는 필기 포맷/)
})

test('빈 데이터도 안전하다', () => {
  assert.deepEqual(ink.deserialize(null).strokes, [])
})

console.log('\n▸ 병합 (기기 2대)')

test('양쪽에서 그린 획이 모두 살아남는다', () => {
  const local  = { strokes: [stroke([[0, 0]], { id: 'a', createdAt: 1 })], deleted: new Set() }
  const remote = { strokes: [stroke([[1, 1]], { id: 'b', createdAt: 2 })], deleted: new Set() }
  const m = ink.mergeAnnotations(local, remote)
  assert.deepEqual(m.strokes.map((s) => s.id), ['a', 'b'])
})

test('한쪽에서 지운 획은 다른 쪽에 남아 있어도 지워진다', () => {
  const shared = stroke([[0, 0]], { id: 'a', createdAt: 1 })
  const local  = { strokes: [shared], deleted: new Set() }
  const remote = { strokes: [], deleted: new Set(['a']) }
  const m = ink.mergeAnnotations(local, remote)
  assert.equal(m.strokes.length, 0, 'tombstone 이 무시되면 지운 획이 부활한다')
  assert.ok(m.deleted.has('a'))
})

test('병합 순서가 어느 쪽에서 하든 같다 (겹친 획의 위아래가 같아진다)', () => {
  const a = { strokes: [stroke([[0, 0]], { id: 'z', createdAt: 5 })], deleted: new Set() }
  const b = { strokes: [stroke([[1, 1]], { id: 'a', createdAt: 5 })], deleted: new Set() }
  const ab = ink.mergeAnnotations(a, b).strokes.map((s) => s.id)
  const ba = ink.mergeAnnotations(b, a).strokes.map((s) => s.id)
  assert.deepEqual(ab, ba, '기기마다 순서가 다르면 겹친 필기가 다르게 보인다')
  assert.deepEqual(ab, ['a', 'z'], '같은 시각이면 id 로 결정론적으로 정렬')
})

test('같은 획이 양쪽에 있어도 한 번만 남는다', () => {
  const s = stroke([[0, 0]], { id: 'dup', createdAt: 1 })
  const m = ink.mergeAnnotations({ strokes: [s], deleted: new Set() }, { strokes: [s], deleted: new Set() })
  assert.equal(m.strokes.length, 1)
})

console.log('\n▸ 되돌리기')

test('undo 와 redo 가 정확히 반대다 (그리기)', () => {
  const s = stroke([[0, 0]], { id: 'a', createdAt: 1 })
  const state = { strokes: [s], deleted: new Set() }
  const action = { type: 'add', stroke: s }
  ink.applyUndo(state, action)
  assert.equal(state.strokes.length, 0)
  ink.applyRedo(state, action)
  assert.equal(state.strokes.length, 1)
  assert.equal(state.strokes[0].id, 'a')
})

test('undo 와 redo 가 정확히 반대다 (지우기)', () => {
  const s = stroke([[0, 0]], { id: 'a', createdAt: 1 })
  const state = { strokes: [], deleted: new Set(['a']) }
  const action = { type: 'erase', strokes: [s] }
  ink.applyUndo(state, action)
  assert.equal(state.strokes.length, 1, '지운 걸 되돌리면 획이 돌아와야 한다')
  assert.equal(state.deleted.has('a'), false, 'tombstone 도 함께 걷혀야 한다')
  ink.applyRedo(state, action)
  assert.equal(state.strokes.length, 0)
  assert.ok(state.deleted.has('a'))
})

test('새 동작이 들어오면 redo 가 비워진다', () => {
  const st = new ink.UndoStack()
  st.push({ type: 'add', stroke: { id: 'a' } })
  st.undo()
  assert.equal(st.canRedo, true)
  st.push({ type: 'add', stroke: { id: 'b' } })
  assert.equal(st.canRedo, false, '분기 히스토리는 사용자를 헷갈리게 한다')
})

test('스택 상한을 넘으면 오래된 것부터 버린다', () => {
  const st = new ink.UndoStack(3)
  for (let i = 0; i < 5; i++) st.push({ type: 'add', stroke: { id: `s${i}` } })
  assert.equal(st.undoable.length, 3)
  assert.equal(st.undoable[0].stroke.id, 's2')
})

test('빈 스택에서 undo 해도 터지지 않는다', () => {
  const st = new ink.UndoStack()
  assert.equal(st.undo(), null)
  assert.equal(st.canUndo, false)
})

console.log('\n▸ id')

test('스트로크 id 는 시간순으로 정렬 가능하다', () => {
  const a = ink.newStrokeId(1000, 0.1)
  const b = ink.newStrokeId(2000, 0.1)
  assert.ok(a < b, '시간 접두사가 있어야 병합 정렬이 안정적이다')
})

console.log('\n▸ 도구 모드')

// 지우개는 획을 만드는 도구가 아니라 모드다. 이 구분이 무너지면 둘 중 하나가 깨진다:
// TOOLS 에 넣으면 지우개로 획이 그려지고, TOOL_MODES 에서 빼면 지우개를 켤 수 없다.
test('지우개와 읽기 모드는 도구 모드이지 획 도구가 아니다', () => {
  assert.ok(ink.TOOL_MODES.includes('eraser'), '지우개를 켤 수 없다')
  assert.ok(ink.TOOL_MODES.includes('none'), '읽기 모드를 켤 수 없다')
  assert.ok(!ink.TOOLS.includes('eraser'), '지우개로 획이 만들어진다')
  assert.throws(() => ink.createStroke('eraser', '#000', 2, 'x', 0))
  for (const t of ink.TOOLS) assert.ok(ink.TOOL_MODES.includes(t))
})

console.log(`\n${failures.length ? '실패 ' + failures.length + '개' : '전부 통과'} (통과 ${passed}개)\n`)
if (failures.length) process.exit(1)
