# 02. 디자인 시스템 — popol.me/designsystem 준수

## ⚠️ 현재 상태: 토큰 값 미확보

`https://popol.me/designsystem` 은 **이 작업 세션의 네트워크 egress 정책에서 차단**되어 있어
(도메인 차단 — 일시적 오류가 아님) 실제 토큰 값을 읽어오지 못했다.

따라서 이 문서는 **값이 아니라 계약(contract)** 을 정의한다.
아래 §3 표의 `TBD` 칸만 채우면 앱·학습지 HTML 양쪽에 자동 반영되도록 구조를 잡아 둔다.

**토큰 확보 방법 (택 1)** — `09-open-questions.md` Q2:
1. popol.me/designsystem 의 토큰 표를 그대로 붙여넣기 (가장 빠름)
2. Figma Variables / Tokens Studio JSON export 제공
3. 사이트 접근이 허용된 환경에서 `design/design_tokens.json` 을 채워 커밋

**토큰이 채워지기 전까지는 UI 구현을 시작하지 않는다.** 하드코딩된 임시 색상은
나중에 전수 치환이 불가능해지고, "반드시 popol.me 디자인을 따를 것"이라는 요구를 위반한다.
M0~M2(백엔드·생성 파이프라인)는 토큰 없이도 진행 가능하므로 병렬로 간다. (`08-roadmap.md`)

## 1. 핵심 원칙: 토큰 SSOT 하나로 앱과 학습지를 동시에 지배

학습지는 HTML이고 앱은 Flutter다. 두 곳에 색을 각각 적으면 100% 어긋난다.

```
design/design_tokens.json          ← 단일 진실 공급원 (popol.me 값)
        │
        ├─ dart run design/build_tokens.dart
        │
        ├──► packages/design_system/lib/src/tokens/tokens.g.dart   (Flutter UI)
        └──► server/supabase/functions/_shared/worksheet.css.ts    (학습지 HTML)
```

- `tokens.g.dart` / `worksheet.css.ts` 는 **생성물이며 직접 편집 금지** (파일 상단에 `// GENERATED` 배너).
- CI에서 `build_tokens.dart` 재실행 후 diff가 있으면 빌드 실패 → 토큰 드리프트 차단.
- 학습지 HTML은 **CSS를 인라인으로 임베드**한다 (외부 CSS 요청 없이 오프라인·WebView에서 즉시 렌더).

## 2. `design_tokens.json` 스키마

```jsonc
{
  "$schema": "./design_tokens.schema.json",
  "meta": { "source": "https://popol.me/designsystem", "version": "TBD", "fetchedAt": "TBD" },
  "color": {
    "brand":   { "primary": "TBD", "primaryHover": "TBD", "onPrimary": "TBD" },
    "surface": { "base": "TBD", "raised": "TBD", "sunken": "TBD", "overlay": "TBD" },
    "text":    { "primary": "TBD", "secondary": "TBD", "tertiary": "TBD", "onBrand": "TBD" },
    "border":  { "subtle": "TBD", "default": "TBD", "strong": "TBD" },
    "status":  { "success": "TBD", "warning": "TBD", "danger": "TBD", "info": "TBD" },
    "ink":     { "pen": "TBD", "highlighter": "TBD" }   // 필기 기본 색 (§5)
  },
  "typography": {
    "fontFamily": { "sans": "TBD", "mono": "TBD" },
    "scale": {
      "display": { "size": "TBD", "lineHeight": "TBD", "weight": "TBD", "letterSpacing": "TBD" },
      "h1": {}, "h2": {}, "h3": {}, "bodyLg": {}, "body": {}, "caption": {}, "code": {}
    }
  },
  "space":  { "0": 0, "1": "TBD", "2": "TBD", "3": "TBD", "4": "TBD", "6": "TBD", "8": "TBD", "12": "TBD", "16": "TBD" },
  "radius": { "sm": "TBD", "md": "TBD", "lg": "TBD", "full": 9999 },
  "shadow": { "sm": "TBD", "md": "TBD", "lg": "TBD" },
  "motion": { "durationFast": "TBD", "durationBase": "TBD", "easingStandard": "TBD" },
  "breakpoint": { "phone": 0, "tablet": 768, "desktop": 1200 }
}
```

## 3. popol.me 에서 추출해야 할 항목 체크리스트

| # | 항목 | 세부 | 상태 |
|---|---|---|---|
| 1 | 컬러 팔레트 | primary/surface/text/border/status 전체 hex, 라이트·다크 각각 | ☐ TBD |
| 2 | 다크 모드 지원 여부 | 지원 시 각 토큰의 다크 대응값 | ☐ TBD |
| 3 | 서체 | 한글 본문 서체 + 웹폰트 라이선스/CDN 여부 (학습지 HTML에 임베드 필요) | ☐ TBD |
| 4 | 타이포 스케일 | size / line-height / weight / letter-spacing | ☐ TBD |
| 5 | 스페이싱 스케일 | 4pt 그리드인지 8pt 그리드인지 | ☐ TBD |
| 6 | 라운딩 · 그림자 | 카드/버튼 반경, elevation 단계 | ☐ TBD |
| 7 | 컴포넌트 스펙 | Button(variant/size/state), Input, Card, Chip, Tab, BottomSheet, Toast, Dialog | ☐ TBD |
| 8 | 아이콘 세트 | 아이콘 라이브러리 이름/굵기 | ☐ TBD |
| 9 | 모션 | duration / easing 커브 | ☐ TBD |
| 10 | 그리드·레이아웃 | 컨테이너 최대폭, 거터, 브레이크포인트 | ☐ TBD |

## 4. `packages/design_system` 구조

```
packages/design_system/lib/
├─ design_system.dart              # 배럴 export
└─ src/
   ├─ tokens/
   │  ├─ tokens.g.dart             # GENERATED — 원시 값
   │  └─ app_theme.dart            # 토큰 → ThemeData (라이트/다크)
   └─ components/
      ├─ ds_button.dart            # primary / secondary / ghost / danger × sm/md/lg
      ├─ ds_text_field.dart
      ├─ ds_card.dart
      ├─ ds_chip.dart
      ├─ ds_app_bar.dart
      ├─ ds_bottom_sheet.dart
      ├─ ds_dialog.dart
      ├─ ds_toast.dart
      ├─ ds_empty_state.dart
      ├─ ds_progress.dart          # 생성 대기 화면용
      └─ ds_skeleton.dart
```

**강제 규칙 (린트로 잡는다)**

- `features/` 아래 코드에서 `Color(0x...)`, `Colors.*`, 하드코딩 `TextStyle`, 생 `EdgeInsets` 숫자 금지
  → `custom_lint` 규칙 또는 최소한 CI grep 스크립트로 차단.
- 새 화면은 `design_system` 컴포넌트 조합으로만 만든다. 없으면 컴포넌트를 먼저 추가한다.
- 위젯북(`widgetbook` 패키지)으로 컴포넌트 카탈로그를 만들어 popol.me 원본과 눈으로 대조한다.

## 5. 학습지 HTML의 디자인 시스템 매핑

학습지는 "디지털 종이"다. 앱 UI 토큰을 그대로 쓰되, **문서용 오버라이드**를 얹는다.

| 학습지 요소 | 사용 토큰 | 비고 |
|---|---|---|
| 페이지 배경 | `color.surface.base` | 종이 느낌. 다크모드에서도 필기 대비 확보 필요 |
| 섹션 카드 | `color.surface.raised` + `radius.lg` + `shadow.sm` | 11개 섹션 각각 |
| 섹션 번호 뱃지 | `color.brand.primary` / `color.text.onBrand` | |
| 본문 | `typography.scale.body` | 한글 가독성 위해 line-height ≥ 1.7 권장 |
| 인용/상황극 블록 | `color.surface.sunken` + 좌측 `border.strong` 4px | |
| 문제 번호 | `typography.scale.h3` | |
| 필기 여백 | 각 섹션 하단 `space.16` 확보 | 펜으로 쓸 자리 (§6) |
| 펜 잉크 | `color.ink.pen` | 기본 잉크 색 |
| 형광펜 | `color.ink.highlighter` + `mix-blend-mode: multiply` | |

**필기용 레이아웃 제약**

- 학습지 본문은 **고정 폭 문서**로 렌더한다 (기본 `--sheet-width: 820px`, iPad 세로 기준).
  가변 리플로우를 허용하면 회전/분할뷰 시 문서 좌표가 바뀌어 **기존 필기가 어긋난다.**
  화면 폭에 맞추는 것은 CSS `transform: scale()` 로만 처리하고, 문서 좌표계는 불변으로 유지한다.
  → 이 결정은 `06-annotation.md` §2 의 좌표계 계약과 직결된다.
- 폰트도 문서에 임베드(base64 WOFF2)해서 오프라인 렌더 시 줄바꿈이 달라지지 않게 한다.

## 6. 접근성

- 본문 대비비 WCAG AA (4.5:1) 이상. popol.me 토큰이 미달하면 **문서용 텍스트 색만** 예외 토큰으로 승격.
- 터치 타깃 최소 44×44pt.
- 학습지 HTML에 시맨틱 태그(`<section>`, `<h2>`, `<ol>`) 사용 → VoiceOver 대응.
- 동적 타입(iOS Dynamic Type) 대응: 앱 UI는 대응, 학습지 문서는 고정 폭 유지를 위해 자체 확대 슬라이더 제공.
