# 02. 디자인 시스템 — SEED Design System (당근)

## 0. 결정 요약

| 항목 | 내용 |
|---|---|
| 베이스 | **SEED Design System** — [github.com/daangn/seed-design](https://github.com/daangn/seed-design) |
| 라이선스 | **Apache License 2.0** (Copyright 2025 주식회사 당근마켓) — 상업적 사용·수정·재배포 가능 |
| 아이콘 | **Untitled UI Icons** — [untitledui-js](https://www.npmjs.com/package/untitledui-js) (MIT) |
| 서체 | Pretendard Variable (OFL-1.1) |
| 교체 가능성 | **`design/design_tokens.json` 하나만 갈아끼우면 전체가 바뀐다** |

> 이전 베이스였던 Orca Design System 에서 교체했다. 교체에 든 작업은
> `design_tokens.json` 재작성과 생성기 실행뿐이고, **앱 코드와 학습지 렌더러는 한 줄도 고치지 않았다.**
> 이게 토큰 SSOT 구조를 만든 이유다.

## 1. Seed 에서 그대로 가져온 것

`packages/rootage/__generated__` 의 시맨틱 토큰을 참조까지 풀어서 가져왔다.

| 우리 토큰 | Seed 토큰 | 라이트 | 다크 |
|---|---|---|---|
| `brand.primary` | `bg.brand-solid` | `#FF6600` | `#FF6600` |
| `brand.primaryPressed` | `bg.brand-solid-pressed` | `#E14D00` | `#FF9E65` |
| `brand.primarySubtle` | `bg.brand-weak` | `#FFF2EC` | `#31241F` |
| `surface.base` | `bg.layer-basement` | `#F3F4F5` | `#000000` |
| `surface.raised` | `bg.layer-default` | `#FFFFFF` | `#16171B` |
| `surface.sunken` | `bg.layer-fill` | `#F7F8F9` | `#1D2025` |
| `text.primary` | `fg.neutral` | `#1A1C20` | `#F3F4F5` |
| `text.secondary` | `fg.neutral-muted` | `#555D6D` | `#DCDEE3` |
| `border.default` | `stroke.neutral-muted` | `#00000010` | — |
| `status.danger` | `fg.critical` | `#FA342C` | `#FF6E60` |
| radius | `$radius.r1~r6` | 4·6·8·12·16·20·24 | 동일 |
| shadow | `$shadow.s1~s3` | `0 1px 4px #00000014` 외 | 동일 |
| 타입 스케일 | `$font-size.t1~t14` | 11~48px, line-height 쌍 | 동일 |
| 모션 | `$duration.d1~d6` | 50~300ms | 동일 |

### 매핑에서 조심한 세 가지

1. **`fg.brand-contrast` 는 solid 위 글자가 아니다.** 이름만 보면 브랜드색 배경 위 글자 같지만
   실제 값은 `#E14D00`(진한 주황)이고, `bg.brand-weak`(연한 살구) 위에 쓰는 색이다.
   solid 주황 버튼 위 글자로 쓰면 주황 위에 주황이 된다. → `brand.textOnSubtle` 로 이름을 바꿔 담았다.
2. **`surface.base` 와 `sunken` 이 겹치면 안 된다.** 처음에 `bg.neutral-weak` 를 sunken 으로 잡았더니
   `layer-basement` 와 같은 `#F3F4F5` 가 나와 층이 무너졌다. `bg.layer-fill`(`#F7F8F9`)이 맞다.
3. **Seed 에는 hover 가 없다.** 모바일 우선 시스템이라 pressed 만 있다. 웹/데스크톱에서는
   `primaryPressed` 를 hover 로 함께 쓴다.

## 2. 우리가 얹은 것

| 추가 | 내용 |
|---|---|
| `ink.*` | 필기 잉크 — Seed 팔레트의 gray-1000 / blue-600 / red-600 / yellow-400 에서 가져왔다 |
| `worksheet.*` | 학습지 문서 계층. 본문은 Seed 의 t4(14px)가 아니라 **t6(18px) + 행간 1.78** |
| `icon.*` | Untitled UI 규격 (선 굵기 2, 24×24 뷰박스, 16/20/24/32) |
| `brand.onPrimary` | Seed 에 solid 위 글자 토큰이 없어 `#FFFFFF` 로 직접 지정 (§6 접근성 주의) |

**학습지 본문을 키운 이유**: Seed 는 손안의 화면을 위한 시스템이라 본문이 14px 다.
학습지는 아이패드에서 **읽고 그 위에 쓰는** 문서라서, 글자 크기와 행간이 앱 UI 기준보다 커야 한다.

## 3. 아이콘 — Untitled UI

`untitledui-js`(MIT, Untitled UI Icons 의 MIT 포팅)에서 **쓰는 것만 35개** 뽑아 쓴다.
1,172개를 전부 담지 않는 이유는 학습지 HTML 에 인라인으로 들어가서 파일 크기가 곧 비용이기 때문이다.

```
node design/build_icons.mjs         # 생성
node design/build_icons.mjs --check # 드리프트 검사 (CI)
```

| 쓰임 | 아이콘 |
|---|---|
| 학습지 11개 섹션 | Target01 · ClockRewind · BookOpen01 · Hourglass01 · MessageChatCircle · GraduationHat01 · Lightbulb02 · HelpCircle · CheckSquare · Flag01 · Rocket01 |
| 문서 요소 | Stars01(비유) · BookOpen02(용어) · MessageChatSquare(파르) |
| 필기 툴바 | PenTool02 · Brush01 · Eraser · FlipBackward · FlipForward · Trash01 · ZoomIn |
| 내비게이션 | Home01 · BookOpen01 · RefreshCcw01 · Settings01 · User01 |
| 동작·상태 | Plus · SearchLg · ChevronLeft · XClose · DotsVertical · CheckCircle · AlertTriangle · AlertCircle · InfoCircle |

아이콘은 `stroke="currentColor"` 로 넣어 색을 주변 텍스트에서 상속한다.
학습지 HTML 은 여전히 **외부 요청 0회**다.

## 4. 토큰 SSOT — 교체 지점은 여기 하나

```
design/design_tokens.json          ← 유일한 교체 지점
        │
        ├─ node design/build_tokens.mjs
        │
        ├──► packages/design_system/lib/src/tokens/tokens.g.dart   (Flutter UI)
        └──► server/supabase/functions/_shared/tokens.css.ts       (학습지 HTML)
```

생성기는 Dart 가 아니라 **Node(의존성 0)** 로 짰다. 서버(TypeScript)와 툴체인이 같고,
Flutter SDK 없이도 CI 에서 토큰 드리프트를 검사할 수 있기 때문이다.

- 생성물은 `// GENERATED` 배너를 달고 **직접 편집 금지**.
- 생성기는 **라이트/다크 팔레트의 키 집합이 정확히 일치하는지 검사**한다. 어긋나면 빌드가 실패한다
  (한쪽에만 있는 색은 테마 전환 시 구멍이 된다).
- `node design/build_tokens.mjs --check` 로 드리프트만 검사한다 (CI용).
- CI 에서 `build_tokens.mjs` 재실행 후 diff 가 있으면 빌드 실패 → 토큰 드리프트 차단.
- **코드 어디에도 색·간격·서체 리터럴이 없어야 한다.** 이게 "마지막에 갈아끼우기"의 전제다.

**나중에 디자인을 교체할 때 하는 일** (예: popol.me 값 확보 시)
1. `design_tokens.json` 의 `color` / `colorDark` / `typography` / `radius` / `shadow` 값 교체
2. `meta.base` 갱신
3. `node design/build_tokens.mjs`
4. Widgetbook 카탈로그로 눈 검수

앱 코드도 학습지 렌더러도 **한 줄도 안 고친다.**

## 5. `packages/design_system` 구조

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

## 6. 학습지 HTML 매핑

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

## 7. 접근성

- 본문 대비: `#1A1C20` on `#FFFFFF` ≈ 17:1, `#555D6D` on `#FFFFFF` ≈ 7.2:1 — 둘 다 AA 통과.
- ⚠️ **흰 글자 / 브랜드 주황(`#FF6600`) 대비는 약 2.9:1 로 WCAG AA(4.5:1) 미달이다.**
  → 큰 글자(18px+), 굵은 짧은 라벨, 아이콘에만 쓰고 **본문 텍스트에는 쓰지 않는다.**
  연한 배경 위 브랜드 텍스트가 필요하면 `brand.textOnSubtle`(`#E14D00`)을 쓴다.
- 터치 타깃 최소 44×44pt.
- 아이콘은 전부 `aria-hidden="true"` — 의미는 옆 텍스트가 전달한다.
- 학습지는 고정 폭이므로 Dynamic Type 대신 자체 확대 슬라이더를 제공한다.

## 8. 라이선스와 상표 ⚠️

### 코드는 문제없다

Seed 는 Apache License 2.0 이라 **상업적 사용·수정·재배포가 자유롭다.**
재배포 시 라이선스 사본과 귀속 고지를 전달하면 된다(Apache 2.0 제4조).

앱 "오픈소스 라이선스" 화면에 포함할 것:
- SEED Design System — Apache 2.0, Copyright 2025 주식회사 당근마켓
- untitledui-js — MIT, Copyright (c) 2025 Emmanuel C. Alozie
- Pretendard — SIL Open Font License 1.1

### 브랜드 색은 별개 문제다 🚨

Seed 의 NOTICE 는 이렇게 말한다.

> 이 저장소에서 제공하는 "브랜드 리소스"는 주식회사 당근마켓의 자산으로 대한민국 상표법의 보호를 받습니다.
> 브랜드 리소스란 로고, 상호명, 캐릭터 등 **당근마켓이나 당근마켓의 제품으로 식별될 수 있는 모든 요소**를 의미합니다.
> (…) 당근마켓의 제품 또는 서비스와 제휴, 후원, 보증, 그 밖의 관련이 있는 것처럼 오인하게 하는 사용은 할 수 없습니다.

**`#FF6600` 은 당근의 시그니처 컬러다.** 이걸 ONPAR 의 주 브랜드 색으로 쓰면
사용자가 당근 계열 서비스로 오인할 여지가 생긴다. Apache 2.0 은 코드에 대한 허가이고,
상표는 그 라이선스가 다루지 않는 별개 영역이라는 점을 NOTICE 가 명시하고 있다.

**권고: 상용 출시 전 `brand.*` 를 ONPAR 고유 색으로 교체한다.**

교체는 `design/design_tokens.json` 의 `color.brand` / `colorDark.brand` 여섯 줄이면 끝난다.
Seed 의 나머지(중립 팔레트·타입 스케일·radius·shadow·모션)는 기능적 설계라 그대로 써도 무방하다.

```jsonc
// design/design_tokens.json — 이 부분만 바꾸면 된다
"brand": {
  "primary": "#FF6600",        // ← ONPAR 고유 색으로
  "primaryPressed": "#E14D00", // ← 그보다 어둡게
  "primarySubtle": "#FFF2EC",  // ← 아주 연하게
  ...
}
```

법적 판단이 필요한 사안이므로, 출시 전 변호사·변리사 확인을 권한다.
