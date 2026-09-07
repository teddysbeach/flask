# ONPAR 앱

Flutter. 아이패드 1순위, 폰에서도 열린다.

## 실행

비밀은 소스에 없다. `--dart-define` 으로 주입한다.

```bash
export PATH="/opt/flutter/bin:$PATH"

flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=APP_SCHEME=me.popol.onpar \
  --dart-define=UNIVERSAL_LINK_HOST=onpar.app \
  --dart-define=TERMS_URL=https://onpar.app/terms \
  --dart-define=PRIVACY_URL=https://onpar.app/privacy \
  --dart-define=SUPPORT_EMAIL=help@onpar.app
```

설정을 안 넣어도 앱은 뜬다 — 뜬 다음 "설정이 없다" 고 말한다.
조용히 빈 화면을 보여주는 것보다 낫다.

`--dart-define-from-file=env.json` 도 된다. `env.json` 은 커밋하지 않는다.

## 검사

```bash
flutter analyze          # 경고 0 이 기준이다
flutter test
```

## 구조

```
lib/
  core/       설정 · 오류 분류 · 로그 · 분석 · 권한 · 딥링크 · 부팅 판정 · 경로 상수
  data/       Supabase 클라이언트와 리포지터리
  domain/     화면이 쓰는 모델 (DB 컬럼 이름은 여기서 끊긴다)
  ui/         테마 · 공용 상태 화면 · 공용 위젯
  features/   화면
```

### 지키는 규칙

- **화면에 서버 원문 메시지를 띄우지 않는다.** `AppError.message` 만 나간다.
- **실패는 언제나 우리 탓으로 쓴다.** "잘못 입력하셨습니다" 가 아니라 "다시 확인해 주세요".
- **화면마다 Loading / Empty / Error 를 다 그린다.** 정상 상태만 만든 화면은 반려한다.
- **`print` 금지**(린트가 막는다). 로그는 `AppLogger` 로만 — 이메일·전화·토큰을 출력 직전에 가린다.
- **분석 이벤트에 개인정보를 싣지 않는다.** `sanitizeProps` 가 키 단위로 막고, 화면 이름에서 id 를 뺀다.
- 터치 영역 48dp, 접근성 라벨, 색만으로 상태를 표현하지 않는다.

### 시험하기 어려운 것을 순수 함수로 뺀다

앱을 띄워야만 확인되는 로직은 아무도 확인하지 않는다. 그래서 아래는 위젯 밖에 있다.

| 파일 | 무엇 | 테스트 |
|---|---|---|
| `core/boot_redirect.dart` | 부팅 순서 판정(설정→점검→온보딩→약관→로그인→목적지 복귀) | `test/boot_redirect_test.dart` |
| `core/deep_links.dart` | 외부 URI → 앱 경로 | `test/deep_links_test.dart` |
| `core/logger.dart` | 개인정보 가리기 | `test/logger_redaction_test.dart` |
| `features/auth/password_policy.dart` | 비밀번호 규칙 | `test/password_policy_test.dart` |
| `features/worksheet/worksheet_response_mapping.dart` | 브리지 응답 → DB 행 | `test/worksheet_response_mapping_test.dart` |

## 학습지 뷰어

학습지는 서버가 만든 **완결형 HTML** 이고 앱은 `flutter_inappwebview` 로 연다.
필기 엔진과 상호작용 런타임은 그 HTML 안에 인라인으로 들어 있다(`server/build-runtime.mjs`).

브리지 두 개로 주고받는다.

| 채널 | 방향 | 무엇 |
|---|---|---|
| `ink` | JS → Flutter | 필기 변경. 디바운스 후 저장 |
| `learn` | JS → Flutter | 학습 응답(무엇을 골랐고 무엇을 썼는지) |
| `ONPAR_INK.*` | Flutter → JS | 도구 전환 · 실행취소 · 확대 · 문제로 스크롤 |

**필기 좌표는 요소 기준 정규화(v2)** 라 화면 폭이 바뀌어도 필기가 자기 문제에 붙어 있다.
자세한 것은 `docs/plan/06-annotation.md`.

## 아직 안 된 것

- Storage 업로드 배선(필기 파일, 프로필 이미지) — rev 잠금까지는 되어 있다
- Firebase/Sentry — 인터페이스만 있고 SDK 는 계정이 생긴 뒤에
- iOS/Android 네이티브 설정(번들 ID · 딥링크 · 권한 문구 · 아이콘)
- **실기기에서 Apple Pencil 필압 확인** — 이게 가장 큰 미검증 가정이다
