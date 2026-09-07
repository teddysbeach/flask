# 16. 앱 출시 체크리스트 — ONPAR 매핑

일반 앱 출시 체크리스트를 ONPAR 에 맞춰 옮긴 것이다.
관리 단위는 **화면 / 기능 / API / 상태 / 예외 / Analytics / 출시 필수**의 7열이다.

**빼는 것을 먼저 적는다.** 목록을 다 채우는 것보다 왜 안 만드는지가 중요하다.

| 일반 체크리스트 항목 | ONPAR 판단 |
|---|---|
| 검색(자동완성·인기검색어·검색기록) | **없음.** ONPAR 은 검색이 아니라 **주제 입력**이다. 사용자가 치는 문장은 찾는 말이 아니라 만들 것의 정의다. 서재 필터(전체/완성/실패)로 충분하다 |
| UGC 신고·차단·댓글 | **없음.** 사용자 간 콘텐츠가 없다. 학습지는 본인만 본다(RLS). 심사에서 요구되는 UGC 조항이 애초에 적용되지 않는다 |
| 위치·마이크 권한 | **없음.** 쓸 일이 없는 권한은 요청하지 않는다. 요청 자체가 개인정보 수집 고지 항목을 늘린다 |
| 소셜 로그인 Kakao/Naver | **1차 제외.** Apple·Google 로 시작한다. 국내 사용자 비중을 보고 추가한다 |
| 어드민 앱 | **Flutter 앱으로 만들지 않는다.** 운영 도구는 별도 웹이다(§운영). 사용자 앱에 관리자 경로를 두면 그 자체가 공격면이다 |
| 다국어 | **한국어만.** 파르의 말투가 제품의 일부라 기계 번역으로 늘리면 목소리가 죽는다. `locale` 컬럼은 이미 있다 |
| 구독 | **없음.** 소모품(장수) 결제다. 그래서 "구독 중 탈퇴 제한" 이 적용되지 않는다 |

---

## 1. 앱 진입 / 첫 실행

| 화면 | 기능 | API | 상태 | 예외 | Analytics | 필수 |
|---|---|---|---|---|---|---|
| `SplashScreen` | 브랜드 표시, 부팅 판정 대기 | — | Loading | 설정 없음(`Env.isConfigured=false`) → 안내 | `appOpen` | ✅ |
| `GateScreen` | 점검 · 강제/선택 업데이트 | `appGateProvider` | Loading/Error | 서버 못 부르면 **통과**(우리 실수로 앱을 잠그지 않는다) | — | ✅ |
| `OnboardingScreen` | 3장 + 건너뛰기 | 로컬 | — | — | `onboardingStart/Complete/Skip` | ✅ |
| `ConsentScreen` | 필수/선택 약관 구분, 동의 이력 저장 | 로컬 + 서버 | — | 필수 미동의 시 진행 불가 | `consentAccept` | ✅ |

**권한은 첫 실행에 몰아 묻지 않는다.** 알림은 첫 학습지를 만든 뒤, 사진은 프로필을 바꿀 때 묻는다.
한 번 거절당하면 되돌리기 어렵고, 맥락 없는 요청은 대부분 거절당한다.

## 2~4. 가입 · 로그인 · 계정 찾기

| 화면 | 기능 | API | 예외 | 필수 |
|---|---|---|---|---|
| `SignupScreen` | 이메일 가입, 비밀번호 정책 실시간 표시 | `auth.signUp` | 이미 가입된 이메일 → 로그인 유도 | ✅ |
| `VerifyScreen` | 이메일 인증 안내 / 휴대폰 OTP | `auth.verifyOTP` | 재전송 60초 쿨다운, 만료, 오입력 | ✅ |
| `LoginScreen` | 이메일 · Apple · Google | `signInWithPassword` / `signInWithIdToken` | 취소는 오류가 아니다, 잘못된 비밀번호 | ✅ |
| `FindAccountScreen` | 재설정 메일 | `resetPasswordForEmail` | **계정 존재 여부를 알려주지 않는다**, 소셜 계정 안내 | ✅ |
| `ResetPasswordScreen` | 새 비밀번호 | `updateUser` | 링크 만료, 기존 세션 종료 고지 | ✅ |

- 자동 로그인 / 세션 유지: `supabase_flutter` 가 refresh token 을 **보안 저장소**(Keychain / EncryptedSharedPreferences)에 둔다. SharedPreferences 평문 저장은 쓰지 않는다.
- 세션 만료: 라우터가 `currentUserProvider` 를 보고 로그인으로 보내며 **원래 목적지를 보류함에 담는다**.
- 로그인 실패 횟수 제한: Supabase 쪽 rate limit 에 맡긴다. 앱에서 세면 앱을 지웠다 깔면 초기화된다.

## 5. 홈 · 서재

| 화면 | 상태 | 예외 |
|---|---|---|
| `HomeScreen` | Skeleton / Empty / Error+재시도 / Offline 배너 | 남은 장수 0 → 결제 유도 |
| `LibraryScreen` | 무한 스크롤(커서 기반), Pull to refresh | 중복 요청 방지, 마지막 페이지 도달, 생성 중/실패 항목 |

offset 이 아니라 **`created_at` 커서**로 넘긴다. offset 은 목록이 바뀌면 건너뛰거나 겹친다.

## 6. 학습지 만들기 · 뷰어 (제품의 핵심)

| 화면 | 기능 | 예외 |
|---|---|---|
| `CreateScreen` | 주제 1~120자, 난이도 | 쿼터 0 → 결제, 생성 중 → 안내, **연타 방지**(쿼터를 깎는 버튼) |
| `CreateProgressScreen` | 40~120초 진행 표시 | 실패 시 사유 + **환불 안내**, 타임아웃 |
| `WorksheetScreen` | WebView + 필기 + 응답 수집 | 삭제/권한 없음, 오프라인, 저장 충돌(rev), 백그라운드 전환 시 즉시 저장 |

- 응답(`learn` 브리지) → `responses` 테이블. 무엇을 골랐고 무엇을 썼는지가 남는다.
- 필기(`ink` 브리지) → `annotations`, **rev 로 낙관적 잠금**. 두 기기가 같이 쓰면 나중 것이 앞엣것을 말없이 지우면 안 된다.

## 7. 복습 · 알림

| 화면 | 기능 | 예외 |
|---|---|---|
| `ReviewSessionScreen` | 인출 → 정답 공개 → 자기평가 4단계 | 오늘 없음(Empty), 중간 이탈 |
| `NotificationSettingsScreen` | 전체/유형별 ON·OFF, 복습 시각 | **OS 권한 꺼짐 → 설정으로 보내는 안내** |
| `NotificationListScreen` | 읽음/안읽음, 전체 읽음 | 삭제된 학습지 알림 |

- 서버가 스케줄의 source of truth, 로컬 알림은 파생 캐시다. 알림이 유실돼도 앱을 열면 큐가 복원된다.
- iOS 64개 한도 → 48개만 예약, 하루 3개 상한, 야간(22~08시) 발송 금지.

## 8~9. 마이페이지 · 설정

프로필(닉네임·이미지), 계정(연결 수단·비밀번호 변경), 알림, 화면(라이트/다크/시스템),
약관·개인정보·**오픈소스 라이선스**(SEED Apache-2.0 / Untitled UI MIT 고지 필수), 고객센터, 앱 버전, 로그아웃, 회원탈퇴.

## 10. 회원탈퇴 (심사 필수)

3단계: 주의사항 → 사유 → 재확인. 서버는 `delete-account` Edge Function 이 한다(앱이 직접 지울 수 있으면 남의 계정도 지울 수 있다는 뜻이다).
- 지워지는 것: 학습지·필기·복습 일정·응답. **남은 장수는 환불되지 않는다**고 미리 밝힌다.
- 구매 내역은 법정 보존 기간 동안 **익명화**해 보관.
- 탈퇴 후 토큰·보안 저장소·로컬 플래그·예약된 알림을 모두 지운다.
- 같은 이메일로 재가입 가능(무료 2장은 재지급하지 않는 정책이 필요 — **미결정**).

## 11. 보안 · 개인정보

| 항목 | 상태 |
|---|---|
| 토큰 저장 | ✅ Keychain / EncryptedSharedPreferences |
| 로그에 개인정보 | ✅ `AppLogger` 가 이메일·전화·JWT·긴 토큰을 출력 직전에 가린다. `print` 는 린트가 막는다 |
| 분석 이벤트에 개인정보 | ✅ `sanitizeProps` 가 email/phone/token/name 등을 통째로 뺀다 |
| 남의 데이터 접근 | ✅ RLS. 앱이 아니라 DB 가 막는다 |
| 서버 결제 검증 | ✅ 영수증은 서버가 검증하고 `unique(platform, transaction_id)` 가 중복 지급을 막는다 |
| HTTPS | ✅ Supabase |
| API 키 | ✅ Anthropic 키는 Edge Function secret. 앱은 근처에도 가지 않는다 |
| Rate limit | 서버 쪽. 앱은 `RequestGuard` 로 중복 요청만 막는다 |

## 16. 앱 상태 처리

`AppErrorKind` 로 닫아 두었다: offline / timeout / unauthorized / forbidden / notFound / server / maintenance / rateLimited / quotaExhausted / validation / cancelled / unknown.
새 실패가 생기면 컴파일러가 처리 안 한 화면을 알려준다. 화면마다 Loading / Empty / Error 를 다 그리는 것이 규칙이고, 정상만 만든 화면은 리뷰에서 반려한다.

## 22. 분석 · 크래시

`Analytics` / `CrashReporter` 인터페이스만 두고 SDK 는 뒤에 꽂는다. 이유는 둘이다:
SDK 교체가 화면 코드를 건드리지 않게, 그리고 **개인정보가 실려 나가는 것을 한곳에서 막게**.
현재는 디버그 구현이고, Firebase/Sentry 배선은 계정이 생긴 뒤에 붙인다(`09-open-questions.md` Q5).

## 25. 스토어 제출

앱 아이콘, 스플래시, 버전/빌드, 개인정보처리방침 URL, 이용약관 URL, 고객지원 URL,
스크린샷, 설명·키워드, 연령 등급, **Apple Privacy Nutrition Label / Google Data Safety**(수집 항목: 이메일, 사용 데이터·학습 응답), 심사용 테스트 계정, **계정 삭제 기능**(✅ 구현).

---

## 아직 안 된 것 (정직하게)

| 항목 | 왜 |
|---|---|
| Storage 필기 업로드 | 뷰어가 rev 잠금까지는 하지만 실제 파일 업로드는 배선 전 |
| 프로필 이미지 업로드 | UI 흐름은 완성, Storage 배선 전 |
| 문의 티켓 테이블 | 지금은 메일 폴백 |
| Firebase/Sentry | 계정 필요 |
| iOS/Android 네이티브 설정 | 번들 ID·딥링크·권한 문구·아이콘. 실기기 빌드 때 |
| 실기기 검증 | **Apple Pencil 필압이 WKWebView 안에서 나오는지**가 가장 큰 미검증 가정이다(`08-roadmap.md` M0) |
