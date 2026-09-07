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

## 네이티브 빌드

`ios/` 와 `android/` 는 `flutter create --org me.popol --project-name onpar` 로 만든 뒤
아래 값들을 손으로 맞춘 것이다. 다시 만들면 덮어써지니 `flutter create` 를 다시 돌리지 않는다.

| | 값 | 근거 |
|---|---|---|
| 번들 ID / applicationId | `me.popol.onpar` | `Env.appScheme` 기본값과 같아야 커스텀 스킴이 산다 |
| 표시 이름 | `ONPAR` | `Info.plist` / `res/values/strings.xml` |
| 최소 iOS | **13.0** | `in_app_purchase_storekit`·`image_picker_ios`·`url_launcher_ios`·`shared_preferences_foundation` 이 13.0 을 요구한다. `flutter_inappwebview` 는 12.0 이라 이쪽이 상한 |
| 최소 Android | **minSdk 24** | `image_picker_android`·`url_launcher_android`·`shared_preferences_android` 가 24 를 요구한다 |
| targetSdk / compileSdk | **36** | Play 는 최신 targetSdk 를 요구하고, `flutter_timezone` 이 compileSdk 35 이상을 요구한다 |

```bash
export PATH="/opt/flutter/bin:$PATH"

flutter build apk --debug              # Android SDK 필요
flutter build appbundle --release      # 릴리스 서명 키 필요(아래)
cd ios && pod install && cd ..         # macOS + CocoaPods 필요
flutter build ipa
```

`flutter build bundle` 은 네이티브 툴체인 없이도 돌아서, Dart 쪽만 확인할 때 쓴다.

### 권한 — 쓰는 것과 안 쓰는 것

셋만 쓴다. 알림 · 사진 · 카메라. `lib/core/permissions.dart` 가 다루는 목록과 정확히 같다.

| 권한 | iOS | Android | 언제 |
|---|---|---|---|
| 알림 | 런타임 요청(문구 없음) | `POST_NOTIFICATIONS` | 첫 학습지를 만든 뒤 복습 알림용 |
| 사진 | `NSPhotoLibraryUsageDescription` | (없음 — 시스템 포토 피커) | 프로필 사진을 고를 때 |
| 카메라 | `NSCameraUsageDescription` | `CAMERA` | 프로필 사진을 직접 찍을 때 |

그 밖에 Android 는 `INTERNET`, `SCHEDULE_EXACT_ALARM`, `com.android.vending.BILLING` 세 개를 더 쓴다.
`SCHEDULE_EXACT_ALARM` 은 "야간(22~08시)에는 안 보낸다" 는 약속을 지키기 위한 것이고,
없어도 근사 예약으로 떨어지게 되어 있다. `USE_EXACT_ALARM` 은 넣지 않는다 — 사용자가 끌 수 없는
권한이라 알람시계·캘린더 앱에만 허용된다.

**안 넣은 것:** 위치 · 마이크 · 연락처 · 캘린더 · `READ_MEDIA_IMAGES` · `RECEIVE_BOOT_COMPLETED` ·
원격 푸시(`aps-environment`) · `usesCleartextTraffic`.
이유는 각 파일 주석에 적어 두었다. 안 쓰는 권한을 선언하면 개인정보 고지 항목만 늘어난다.

iOS 는 `Podfile` 의 `post_install` 이 `permission_handler` 를 이 셋만 컴파일하도록 못 박는다.
그렇게 안 하면 위치·마이크 API 참조가 바이너리에 남아 심사에서 걸린다.

### 딥링크

| 형태 | 어디에 | 검증 |
|---|---|---|
| `me.popol.onpar://...` | iOS `CFBundleURLTypes`, Android intent-filter | 없음(항상 동작) |
| `https://onpar.app/...` | iOS `Runner.entitlements` (`applinks:onpar.app`), Android `autoVerify="true"` | 도메인에 올린 파일로 검증 |

Universal Links / App Links 는 **서버에 파일을 올려야** 산다. 안 올려도 앱은 멀쩡히 뜨고
링크만 브라우저로 간다.

- `https://onpar.app/.well-known/apple-app-site-association` — `TEAMID.me.popol.onpar`
- `https://onpar.app/.well-known/assetlinks.json` — Play **앱 서명 키**(업로드 키가 아니다)의 SHA-256

받는 쪽 규칙은 `lib/core/deep_links.dart` 한 곳에 있다. 새 경로를 열려면 거기와 위 두 파일을 같이 고친다.

### 아이콘과 스플래시

`flutter_launcher_icons` / `flutter_native_splash` 를 **쓰지 않는다.** 생성물이 네이티브 파일을
덮어쓰면 왜 바뀌었는지 추적할 수 없다. 대신 SVG 원본 하나에서 필요한 PNG 를 굽는다.

```bash
node design/build_brand.mjs   # Playwright(Chromium)로 SVG → PNG
```

- 심볼: 원 하나(사람) 아래 **길이가 같은 줄 두 개**. par(동등한)가 이름의 절반이고 그 뜻이 두 줄의 같은 길이에 있다. 배경은 `design/design_tokens.json` 의 `brandPrimary`(#FFB800), 마크는 `brandOnPrimary`(#1A1C20) — 노랑 위에 흰 마크를 얹으면 1.7:1 이라 안 보인다
- 앱 안에서 쓰는 로고는 에셋이 아니라 도형이다 — `OnparLogo` · `OnparSymbol` · `OnparWordmark`(디자인 시스템)
- 스크립트가 심볼이 Android 적응형 아이콘의 안전 원(가운데 66%)을 벗어나지 않는지, 스플래시 PNG 가 배율마다 정수 크기로 떨어지는지 검사한다
- `node design/build_brand.mjs --check` 는 브라우저 없이 생성물이 최신인지만 본다(CI 드리프트 검사)
- 스플래시는 `ios/Runner/Base.lproj/LaunchScreen.storyboard` 와
  `android/.../res/drawable*/launch_background.xml`(+ Android 12 이상용 `values-v31/styles.xml`)에 직접 있다

### 릴리스 서명 (Android)

`android/key.properties` 가 있으면 그 키로, 없으면 디버그 키로 서명한다.
클론 직후에도 `flutter build apk` 가 그냥 되게 하려는 것이다. 이 파일은 커밋하지 않는다.

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/절대/경로/upload-keystore.jks
```

릴리스 빌드는 R8 로 축소한다(`isMinifyEnabled`). `flutter_local_notifications` 가 예약 알림을
Gson 으로 직렬화하므로 `proguard-rules.pro` 의 keep 규칙이 필요하다 —
**첫 릴리스 전에 실기기에서 알림 예약을 한 번 확인한다.**

## 아직 안 된 것

- Storage 업로드 배선(필기 파일, 프로필 이미지) — rev 잠금까지는 되어 있다
- Firebase/Sentry — 인터페이스만 있고 SDK 는 계정이 생긴 뒤에
- **실기기 빌드 미검증** — 네이티브 설정은 다 들어갔지만(위 §네이티브 빌드)
  이 환경에 Android SDK 도 Xcode 도 없어서 APK/IPA 를 실제로 구워 보지 못했다
- 릴리스 서명 키(`android/key.properties`)와 Apple Team ID — 계정이 생긴 뒤에
- 도메인 검증 파일 두 개(`assetlinks.json`, `apple-app-site-association`) — onpar.app 에 올려야 딥링크가 산다
- **실기기에서 Apple Pencil 필압 확인** — 이게 가장 큰 미검증 가정이다
