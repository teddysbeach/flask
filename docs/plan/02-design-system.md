# 02. 디자인 시스템 — Orca Design System 기반

## 0. 결정 요약

| 항목 | 내용 |
|---|---|
| 베이스 | **Orca Design System** — [github.com/stablyai/orca](https://github.com/stablyai/orca) `src/renderer/src/assets/main.css` |
| 라이선스 | **MIT** (Copyright (c) 2026 Lovecast Inc.) — 상업적 사용·수정·재배포 가능 |
| 계보 | Tailwind v4 + shadcn/ui 계열 중립 팔레트. Geist Variable 서체. `--radius: 0.625rem` 배수 체계 |
| 교체 가능성 | **`design/design_tokens.json` 하나만 갈아끼우면 전체가 바뀐다.** 코드에 색·간격·서체 리터럴 없음 |

> 이전 계획에 있던 `popol.me/designsystem` 은 이 작업 환경의 네트워크 정책에서 차단되어 값을 읽지 못했다.
> Orca 를 베이스로 삼되, **나중에 popol.me 든 무엇이든 마지막에 갈아끼울 수 있도록** 토큰 SSOT 구조를 유지한다.

## 1. Orca 에서 그대로 가져온 것

`main.css` 의 `:root` / `.dark` 블록 원본값을 그대로 쓴다.

| 토큰 | 라이트 | 다크 |
|---|---|---|
| `--background` | `#FFFFFF` | `#0A0A0A` |
| `--foreground` | `#0A0A0A` | `#FAFAFA` |
| `--card` | `#FFFFFF` | `#171717` |
| `--secondary` / `--muted` | `#F5F5F5` | `#262626` |
| `--muted-foreground` | `#737373` | `#A1A1A1` |
| `--primary` / `--primary-foreground` | `#171717` / `#FAFAFA` | `#E5E5E5` / `#171717` |
| `--destructive` | `#E40014` | `#FF6568` |
| `--border` / `--input` | `#E5E5E5` | `rgb(255 255 255 / 0.07)` / `0.15` |
| `--ring` | `#A1A1A1` | `#737373` |
| `--status-success` | `#15803D` | `#86EFAC` |
| `--annotation-highlight` | `#F59E0B` | `#F59E0B` |
| `--radius` | `0.625rem` (10px), 배수 `0.6 / 0.8 / 1.0 / 1.4 / 1.8 / 2.2 / 2.6` | 동일 |
| `--shadow-floating` | `0 10px 24px rgb(0 0 0 / 0.18)` | 동일 |
| `--font-sans` | `'Geist', -apple-system, ...` | 동일 |

**행운의 발견**: Orca 에는 이미 `--annotation-highlight: #F59E0B` 라는 **주석/하이라이트 전용 토큰**이 있다.
우리 형광펜 잉크 색으로 그대로 승격했다. 필기 앱과 궁합이 맞는 베이스라는 신호다.

### Orca 가 스스로 정의한 "공개 토큰 계약"을 그대로 차용

Orca 는 서드파티 플러그인 패널에 노출하는 **큐레이션된 20개 토큰 화이트리스트**를 갖고 있다
(`src/shared/plugins/plugin-panel-shell.ts` 의 `PANEL_DESIGN_TOKEN_ALLOWLIST`):

```
--background --foreground --card --card-foreground --popover --popover-foreground
--primary --primary-foreground --secondary --secondary-foreground
--muted --muted-foreground --accent --accent-foreground
--destructive --destructive-foreground --border --input --ring --radius
```

이건 Orca 자신이 내린 **"어떤 토큰이 안정적인 공개 표면인가"** 에 대한 답이다.
우리도 이 20개를 **불변 코어**로 두고, 디자인 교체 시 이 20개의 값만 바꾸면 되도록 설계한다.
나머지(브랜드 액센트, 잉크, 학습지 계층)는 이 코어 위의 확장 레이어다.

## 2. 우리가 추가한 것 (그리고 왜)

### ① 브랜드 액센트 — 보라

Orca 는 `--primary` 를 **중립 근사흑(#171717)** 으로 두고, 보라(`--ai-action-accent: violet`)를
**"AI 동작"에만** 쓴다. 색을 아껴 쓰고 의미가 있을 때만 칠하는 시스템이다.

이 앱은 **AI가 학습지를 만들어주는 앱**이므로 그 보라를 브랜드로 승격했다.

| 토큰 | 라이트 | 다크 | 쓰는 곳 |
|---|---|---|---|
| `brand.primary` | `#7C5CFF` | `#A78BFA` | 생성 CTA, 섹션 번호 뱃지, 진행 인디케이터, 링크 |
| `brand.primarySubtle` | `#F1EDFF` | `#241E3D` | 생성 중 배경, 선택 상태 |
| `neutralPrimary.base` | `#171717` | `#E5E5E5` | 일반 버튼, 강조 텍스트 |

**규칙: 보라는 "만들어지는 순간"에만.** 주제 입력 → 생성 버튼 → 로딩 → 완성 애니메이션까지가 보라 구간이고,
그 뒤 학습지를 읽고 쓰는 시간은 중립 크롬으로 돌아온다. 학습 중에는 UI가 조용해야 한다.

### ② 한글 서체 — Pretendard 폴백 (필수 추가)

**Geist 에는 한글 글리프가 없다.** 이 앱은 한국어가 본문이므로 그대로 쓸 수 없다.

```
'Geist', 'Pretendard Variable', Pretendard, -apple-system, 'Apple SD Gothic Neo', sans-serif
```

라틴·숫자는 Geist, 한글은 Pretendard 가 받는다. 둘 다 OFL-1.1 이라 임베드에 문제없다.
Geist 와 Pretendard 는 둘 다 기하학적 산세리프 계열이라 섞어도 이질감이 적다.

**학습지 HTML 폰트 임베드 전략**
- Geist Variable: 69KB → 통째로 base64 임베드
- Pretendard: 전체 1MB+ → **학습지별 동적 서브셋**. 서버가 학습지를 렌더할 때 실제 등장하는 글리프만
  추려 서브셋하면 30~60KB로 떨어진다. 학습지마다 쓰는 한자·한글이 다르므로 이게 맞는 방법이다.

### ③ 잉크 팔레트 (필기 전용)

| 토큰 | 값 | 출처 |
|---|---|---|
| `ink.pen` | `#111111` / 다크 `#FAFAFA` | own |
| `ink.penBlue` | `#2563EB` | Orca `--terminal-pane-locate` (blue-600) |
| `ink.penRed` | `#E40014` | Orca `--destructive` |
| `ink.highlighter` | `#F59E0B` | **Orca `--annotation-highlight` 원본** |

### ④ 타이포 스케일 · 모션 · 학습지 문서 계층

Orca 는 타이포를 Tailwind 유틸리티로 처리해서 별도 스케일 토큰이 없다. 그래서 이 셋은 우리가 정의했다.
(`design/design_tokens.json` 의 `typography.scale`, `motion`, `worksheet`)

## 3. 토큰 SSOT — 교체 지점은 여기 하나

```
design/design_tokens.json          ← 유일한 교체 지점
        │
        ├─ dart run design/build_tokens.dart
        │
        ├──► packages/design_system/lib/src/tokens/tokens.g.dart   (Flutter UI)
        └──► server/supabase/functions/_shared/worksheet.css.ts    (학습지 HTML)
```

- 생성물은 `// GENERATED` 배너를 달고 **직접 편집 금지**.
- CI 에서 `build_tokens.dart` 재실행 후 diff 가 있으면 빌드 실패 → 토큰 드리프트 차단.
- **코드 어디에도 색·간격·서체 리터럴이 없어야 한다.** 이게 "마지막에 갈아끼우기"의 전제다.

**나중에 디자인을 교체할 때 하는 일** (예: popol.me 값 확보 시)
1. `design_tokens.json` 의 `color` / `colorDark` / `typography` / `radius` / `shadow` 값 교체
2. `meta.base` 갱신
3. `dart run design/build_tokens.dart`
4. Widgetbook 카탈로그로 눈 검수

앱 코드도 학습지 렌더러도 **한 줄도 안 고친다.**

## 4. `packages/design_system` 구조

```
packages/design_system/lib/
├─ design_system.dart
└─ src/
   ├─ tokens/
   │  ├─ tokens.g.dart             # GENERATED
   │  └─ app_theme.dart            # 토큰 → ThemeData (라이트/다크)
   └─ components/
      ├─ ds_button.dart            # brand / neutral / ghost / danger × sm·md·lg
      ├─ ds_text_field.dart
      ├─ ds_card.dart              # radius.xl(14) + shadow.sm
      ├─ ds_chip.dart
      ├─ ds_app_bar.dart
      ├─ ds_bottom_sheet.dart      # radius.3xl(22) 상단
      ├─ ds_dialog.dart
      ├─ ds_toast.dart
      ├─ ds_empty_state.dart
      ├─ ds_progress.dart          # 생성 대기 — brand 구간
      ├─ ds_skeleton.dart
      └─ ds_ink_toolbar.dart       # 필기 툴바
```

**강제 규칙 (CI 로 잡는다)**
- `features/` 아래에서 `Color(0x...)`, `Colors.*`, 하드코딩 `TextStyle`, 생 `EdgeInsets` 숫자 금지
- 새 화면은 `design_system` 컴포넌트 조합으로만. 없으면 컴포넌트를 먼저 추가한다
- Widgetbook 카탈로그로 컴포넌트 전수 시각 검수

## 5. 학습지 HTML 매핑

학습지는 "디지털 종이"다. 앱 토큰을 상속하되 `worksheet.*` 로 덮어쓴다.

| 학습지 요소 | 토큰 |
|---|---|
| 페이지 배경 | `worksheet.paper` (라이트 `#FFFFFF` / 다크 `#141414`) |
| 섹션 카드 | `surface.raised` + `radius.xl` + `shadow.sm` |
| 섹션 번호 뱃지 | `brand.primary` + `text.onBrand`, `radius.full` |
| 본문 | `worksheet.typography.body` — 17px / **행간 1.78** |
| 상황극 블록 | `worksheet.callout.story` — 좌측 보라 바 4px + `#F7F5FF` |
| 꿀팁 블록 | `worksheet.callout.tip` — 좌측 앰버 바 + `#FFFBEB` |
| 문제 | `worksheet.typography.quizQuestion` — 18px / 600 |
| 필기 여백 | `worksheet.inkSpace` — sm 96 / md 160 / lg 240 px |
| 형광펜 | `ink.highlighter` + `mix-blend-mode: multiply` |

**행간 1.78의 이유**: 펜으로 줄 사이에 메모를 끼워 넣을 물리적 여지를 남긴다.
읽기만 하는 문서면 1.6이면 충분하지만, 이건 쓰는 문서다.

**필기 좌표계 제약** — `worksheet.sheetWidth: 820` 은 **확정 후 변경 금지**.
문서 폭이 바뀌면 리플로우가 일어나 기존 필기가 전부 어긋난다.
화면 맞춤은 `transform: scale()` 로만. 상세는 `06-annotation.md` §2.

## 6. 접근성

- Orca 팔레트 기준 본문 대비비: `#0A0A0A` on `#FFFFFF` ≈ 20:1, `#737373` on `#FFFFFF` ≈ 4.7:1 — 둘 다 WCAG AA 통과.
- 주의 지점: `brand.primary #7C5CFF` on `#FFFFFF` 는 약 4.0:1 로 **본문 텍스트에는 미달**.
  → 보라는 **큰 텍스트(18px+ / 14px+ bold)와 면(배경) 용도로만** 쓰고, 작은 본문 텍스트에는 쓰지 않는다.
  링크는 보라 + 밑줄로 색 의존을 피한다.
- 터치 타깃 최소 44×44pt.
- 학습지 HTML 은 시맨틱 태그(`<section>`, `<h2>`, `<ol>`) 사용 → VoiceOver 대응.
- 학습지는 고정 폭이므로 Dynamic Type 대신 **자체 확대 슬라이더**(`transform: scale`)를 제공한다.

## 7. 라이선스 준수

- Orca: MIT. 저작권 고지 유지 필요 → 앱 "오픈소스 라이선스" 화면에 Orca(Lovecast Inc.) MIT 전문 포함.
- Geist: OFL-1.1 → 동일 화면에 고지.
- Pretendard: OFL-1.1 → 동일 화면에 고지.
- 우리는 Orca 의 **토큰 값과 팔레트 구조**를 참조하는 것이고 Orca 의 UI 코드를 복사하지 않는다
  (Orca 는 Electron/React, 우리는 Flutter). 컴포넌트는 Flutter 로 새로 구현한다.
