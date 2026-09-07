# 06. 아이패드 필기 레이어

## 1. 핵심 결정: 필기는 WebView **안에서** 한다

두 가지 방식이 있고, 하나는 함정이다.

| 방식 | 구조 | 판정 |
|---|---|---|
| A. Flutter 오버레이 | WebView 위에 `CustomPaint` 를 얹고 스크롤 offset을 JS 브리지로 받아 캔버스를 이동 | ❌ **기각.** 브리지 지연(1~2프레임) 때문에 스크롤 중 필기가 본문과 따로 논다. 확대/회전 시 누적 오차. 관성 스크롤에서 특히 심함 |
| B. WebView 내부 캔버스 | HTML 문서 흐름 안에 `<canvas>` 를 절대 배치. 브라우저가 본문과 캔버스를 **함께** 스크롤 | ✅ **채택.** 좌표계가 하나뿐이라 동기화 문제 자체가 없음. Pointer Events로 Apple Pencil 필압까지 직접 접근 |

Flutter 쪽은 툴바(펜/형광펜/지우개/색상/실행취소)만 그리고, 선택 상태를 JS로 내려보낸다.
그리기 자체는 전부 WebView 내부 런타임(`assets/webview/worksheet_runtime.js`)이 담당한다.

```
┌─ Flutter Scaffold ──────────────────────────────┐
│ AppBar (제목, 저장 상태)                          │
│ ┌─ InAppWebView ─────────────────────────────┐  │
│ │  <article class="sheet">  본문 (문서 흐름)   │  │
│ │  <canvas id="ink-layer">  필기 (absolute,   │  │
│ │      문서 전체 높이, 같은 스크롤 컨테이너)     │  │
│ └────────────────────────────────────────────┘  │
│ DS 툴바 (design_system 컴포넌트)                  │
└─────────────────────────────────────────────────┘
```

## 2. 좌표계 계약 (v2 — 요소 기준)

**스트로크는 자기가 놓인 학습 요소에 붙는다.** 문서의 절대 좌표가 아니라 그 요소 안의 정규화 좌표로 저장한다.

```jsonc
{ "anchor": "quiz-8", "points": [0.3012, 0.5140, 0.42, ...] }   // x/요소폭, y/요소높이
{ "anchor": null,     "points": [120.4, 331.2, 0.42, ...] }     // v1 호환: 문서 좌표(CSS px)
```

- 앵커는 `[data-ink-anchor]` 가 붙은 요소다. 렌더러가 서술형 응답 자리와 그림 과제에 붙인다(`04-worksheet-spec.md` §6).
- 획을 시작할 때 `elementsFromPoint` 로 앵커를 찾고, 그릴 때는 그 요소의 **현재** rect 로 화면 좌표를 복원한다.
- `ResizeObserver` 가 레이아웃 변화를 잡아 다시 그린다.
- 앵커가 사라진 스트로크(콘텐츠 교체)는 **버리지 않고 보관**하되 그리지 않는다. 필기 삭제는 사용자 데이터 손상급이다.
- 정규화 좌표는 소수 4자리(`ANCHOR_COORD_PRECISION`). 820px 요소에서 0.08px, 390px 에서 0.04px — 눈에 안 보인다.
  1자리로 두면 82px 격자로 뭉개져 필기가 아니라 점묘가 된다. 그래서 문서 좌표(1자리)와 반올림 함수가 따로다.

### 왜 바꿨나

v1 은 문서 폭을 820px 로 **고정**하고 화면 맞춤을 `transform: scale(k)` 로만 했다.
"필기가 안 어긋나는 것" 을 위해 "콘텐츠가 반응형이 되는 것" 을 포기한 설계였다.
390px 폰에서는 배율이 약 0.48 이라 18px 본문이 8.6px 로 보인다 — 읽히지 않는다.
세 번째 외부 평가가 이걸 "필기 엔진이 학습 UI 의 목을 잡고 있다" 고 불렀고, 맞는 말이다.

**콘텐츠가 주체이고 필기가 따라간다.** 요소 기준 좌표면 폭이 820 → 390 으로 바뀌어도
"그 문제 위에 그은 밑줄" 이 계속 그 문제 위에 남는다. `.sheet` 는 이제 고정 폭이 아니라 `max-width` 다.
이 성질은 브라우저 테스트가 실제 Chromium 에서 뷰포트를 바꿔가며 검사한다(`interact.browser.test.ts`).

**캔버스 크기 한계**: 문서가 길면(예: 8,000px) 단일 캔버스는 GPU 메모리 압박을 받는다.
→ **타일링**: 문서를 2,000px 단위 캔버스로 쪼개고 뷰포트 ±1타일만 실제 캔버스로 유지, 나머지는 벡터만 보관.

## 3. 입력 처리 (Apple Pencil)

```js
canvas.style.touchAction = 'none';           // 브라우저 제스처 가로채기 방지
canvas.addEventListener('pointerdown', onDown);
canvas.addEventListener('pointermove', onMove);   // + pointerrawupdate 가능하면 우선
canvas.addEventListener('pointerup', onUp);

function onMove(e) {
  if (!drawing) return;
  // ProMotion 120Hz 샘플을 놓치지 않는다 — 이거 안 하면 빠른 필기가 각져 보인다
  const pts = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
  for (const p of pts) addPoint(toDocCoords(p), p.pressure, p.tiltX, p.tiltY);
}
```

| 항목 | 처리 |
|---|---|
| 팜 리젝션 | `pointerType === 'pen'` 만 그린다. `touch` 는 스크롤/줌으로 넘긴다 |
| 손가락 필기 모드 | 설정에서 켤 수 있게 (Pencil 없는 사용자). 켜면 `touch` 도 그리되 스크롤은 두 손가락으로 |
| 필압 | `pressure`(0~1) → 선 굵기 `w = base * (0.35 + 0.65 * pressure)` |
| 기울기 | `tiltX/tiltY` → 형광펜 각도 (v1.1) |
| 스무딩 | Catmull-Rom → 베지어 변환. 점 간 거리 < 0.7px 는 버림 |
| 렌더 루프 | `requestAnimationFrame` 배칭. 진행 중 스트로크만 별도 캔버스에 그려 재합성 비용 절감 |
| 지우개 | 스트로크 단위 삭제(획 전체). 픽셀 지우개는 벡터 모델과 충돌하므로 v1 제외 |
| 실행취소 | 스트로크 스택 (undo/redo 각 50단계) |

**도구 (v1)**: 펜(3굵기) · 형광펜(`mix-blend-mode: multiply`) · 지우개 · 실행취소/재실행 · 전체 지우기.
**v1 제외**: 올가미 선택, 도형 인식, 텍스트 상자, OCR.

## 4. 데이터 포맷 (`format_version: 2`)

```jsonc
{
  "format_version": 2,
  "sheet_width": 820,             // 기록 당시 폭. v1 스트로크를 펴는 데만 쓴다
  "doc_height": 7420,
  "strokes": [
    {
      "id": "s_01H...",
      "tool": "pen",              // pen | highlighter
      "color": "#1A1A1A",
      "width": 2.4,
      "created_at": 1757000000000,
      "anchor": "quiz-8",         // null 이면 v1 문서 좌표
      // 좌표는 [x, y, pressure] 3개씩 평탄화한 배열 — 객체 배열 대비 JSON 크기 ~60% 감소
      "points": [0.3012, 0.514, 0.42, 0.3105, 0.5162, 0.51]
    }
  ]
}
```

**v1 → v2**: `migrateStrokes()` 가 `anchor: null` 로 읽어 문서 좌표로 계속 그린다.
옛 필기는 그대로 보이고, 새 필기부터 요소에 붙는다. 마이그레이션은 ink-core 테스트가 고정한다.

- 저장: `JSON.stringify` → gzip → Storage `annotations/{user_id}/{worksheet_id}.json.gz`
- 좌표는 소수점 1자리로 반올림 (시각적 차이 없음, 용량 큰 폭 절감)
- 예상 크기: A4 5장 분량 빽빽한 필기 ≈ 압축 후 300~800KB

## 5. 저장 & 동기화

```
필기 이벤트 → 메모리 스트로크 배열
   ├─ 즉시: Drift(SQLite) 에 append (앱이 죽어도 유실 없음)
   └─ 디바운스 3초 + 화면 이탈 시: Storage 업로드 + annotations.rev 증가
```

**충돌 처리 (기기 2대에서 같은 학습지에 필기)**

- `annotations.rev` 로 낙관적 잠금. 업로드 시 `rev = expected_rev` 조건부 UPDATE.
- 충돌 감지 시 **스트로크 단위 병합**을 시도한다. 스트로크는 append-only이고 각각 고유 `id`를 가지므로
  두 집합의 합집합을 취하면 대부분 자연스럽게 합쳐진다 (같은 필기를 두 번 그리는 일은 없으므로).
- 지우개는 "삭제된 스트로크 id 목록"(tombstone)으로 표현해 병합 가능하게 한다.
- 병합 실패(포맷 버전 불일치 등) 시에만 사용자에게 "이 기기 것 / 서버 것" 선택을 묻는다.

## 6. 브리지 (Flutter ↔ WebView)

`flutter_inappwebview` 의 `addJavaScriptHandler` 사용.

| 방향 | 메시지 | 페이로드 |
|---|---|---|
| Flutter → JS | `setTool` | `{tool, color, width}` |
| Flutter → JS | `undo` / `redo` / `clearAll` | — |
| Flutter → JS | `loadStrokes` | 스트로크 JSON |
| Flutter → JS | `scrollToQuiz` | `{quiz_id}` — 복습 알림 탭 시 해당 문제로 이동 |
| Flutter → JS | `setZoom` | `{scale}` |
| JS → Flutter | `strokesChanged` | `{count, dirty: true}` (디바운스 트리거) |
| JS → Flutter | `requestSave` | 전체 스트로크 JSON |
| JS → Flutter | `undoStateChanged` | `{canUndo, canRedo}` (툴바 활성 상태) |

## 7. 성능 목표 & 리스크

| 항목 | 목표 |
|---|---|
| 펜 입력 → 화면 반영 지연 | < 30ms (체감 "붙어 있음"의 경계) |
| 5,000 스트로크 문서 스크롤 | 60fps 유지 (타일링으로 달성) |
| 학습지 열기 → 필기 가능까지 | < 800ms |

**리스크**: iOS WKWebView의 Pointer Events 필압 지원은 iOS 버전에 따라 편차가 있다.
→ **M0에서 최우선으로 기술 검증(spike)한다.** 실제 iPad + Apple Pencil에서
`pressure`, `getCoalescedEvents()`, `touch-action: none` 동작을 확인하고,
필압이 안 나오면 대안(방식 A로 회귀 또는 PencilKit 네이티브 뷰 + 플랫폼 뷰)을 그때 결정한다.
이 spike 결과가 뷰어 아키텍처를 확정한다. (`08-roadmap.md` M0)
