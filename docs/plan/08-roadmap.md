# 08. 로드맵 & 작업 분해

## 마일스톤 요약

| M | 이름 | 산출물 | 선행 조건 |
|---|---|---|---|
| M0 | 기반 & 기술 검증 | 리스크 두 개 해소, 프로젝트 뼈대 | — |
| M1 | 인증 & 쿼터 | 가입/로그인, 무료 2장 카운트 | M0 |
| M2 | 생성 파이프라인 | 주제 → 학습지 JSON → HTML | M0 |
| M3 | 뷰어 & 필기 | iPad에서 학습지에 필기 | M0 spike, M2 |
| M4 | 복습 & 알림 | 망각곡선 로컬 알림 | M2 |
| M5 | 다듬기 & 베타 | TestFlight 배포 | M1~M4 |

**M2는 디자인 토큰 없이도 진행 가능하다** (JSON 생성이 본질). 토큰 확보와 병렬로 간다.
반대로 **M3는 토큰이 없으면 시작하지 않는다** (`02-design-system.md` 참조).

---

## M0 — 기반 & 기술 검증

이 마일스톤의 목적은 코드가 아니라 **두 개의 미확정 리스크를 없애는 것**이다.

- [ ] **[리스크1] Pencil 필압 spike** — 실제 iPad + Apple Pencil에서 WKWebView 안의
      Pointer Events가 `pressure` / `getCoalescedEvents()` / `touch-action:none` 을 제대로 주는지 확인.
      → 최소 재현 HTML + Flutter 껍데기로 30분 안에 판정 가능. **결과가 M3 아키텍처를 확정한다.**
      실패 시 대안: PencilKit 네이티브 플랫폼 뷰. (`06-annotation.md` §7)
- [ ] **[리스크2] popol.me 디자인 토큰 확보** — `design/design_tokens.json` 채우기. (`02-design-system.md` §3)
- [ ] Flutter 프로젝트 생성 (`app/`), 멀티 플레이버(dev/prod), `--dart-define-from-file`
- [ ] `packages/design_system` 스켈레톤 + `design/build_tokens.dart` 코드 생성기
- [ ] Supabase 프로젝트 생성, 로컬 개발 스택(`supabase start`)
- [ ] 마이그레이션 001~006 작성 및 적용 (`03-data-model.md` §5)
- [ ] Edge Function 배포 파이프라인 + `_shared/` (auth 검증, admin client, 에러 타입)
- [ ] CI: `flutter analyze` / `flutter test` / `deno check` / 마이그레이션 드라이런 / **토큰 drift 체크**
- [ ] `.gitignore` 보강 (`.env`, `env/*.json`, `*.secrets.*`, `supabase/.env`)
- [ ] 기존 `langhelper/` 처리 결정 (`09-open-questions.md` Q7)

## M1 — 인증 & 쿼터

- [ ] Supabase Auth 설정: 이메일+비번, **Sign in with Apple**(iOS 소셜 로그인 시 필수), Google
- [ ] `handle_new_user()` 트리거 → `profiles` 자동 생성 (`quota_total = 2`)
- [ ] `consume_quota` / `refund_quota` SECURITY DEFINER 함수 + 권한 회수
- [ ] 앱: 로그인/가입/비번 재설정 화면, 세션 영속화, 토큰 갱신
- [ ] 앱: 홈 — 내 학습지 목록 + **남은 무료 장수 표시**
- [ ] 쿼터 소진 화면 ("곧 제공" — 결제는 v1 제외)
- [ ] 테스트: 동시 요청 2개로 쿼터 레이스 검증 (3장 생성되면 실패)

## M2 — 생성 파이프라인 ⭐ 제품의 심장

- [ ] `WorksheetContent` Zod 스키마 + JSON Schema 생성 (`04-worksheet-spec.md` §3)
- [ ] `server/prompts/worksheet.v1.md` 시스템 프롬프트 (정직성 규칙 포함, §5)
- [ ] `generate-worksheet` Edge Function
  - [ ] JWT 검증 → `consume_quota` → 202 즉시 반환
  - [ ] `EdgeRuntime.waitUntil` 백그라운드 생성
  - [ ] Claude API 스트리밍 + structured output + 프롬프트 캐싱
  - [ ] 스키마 실패 시 1회 재요청, 잡 재시도 2회(지수 백오프)
  - [ ] 실패 시 `refund_quota` + `error_code` 기록
- [ ] `quiz_items` / `prerequisite_suggestions` 분해 INSERT
- [ ] **HTML 렌더러** (순수 함수, 인라인 CSS·폰트) + 골든 파일 테스트
- [ ] XSS 이스케이프 + `InlineNode` 렌더링
- [ ] Storage 업로드 + 서명 URL
- [ ] 앱: 주제 입력 화면 → 생성 대기 화면(진행 문구 회전) → Realtime 구독 → 완료 전환
- [ ] 앱: 실패 화면 + 재시도
- [ ] 프롬프트 회귀 테스트 10주제 (`04-worksheet-spec.md` §7)
- [ ] 비용 계측: `tokens_in/out`, 캐시 히트율 → `generation_jobs`

## M3 — 뷰어 & 필기 ⭐ 제품의 차별점

- [ ] `flutter_inappwebview` 뷰어, 로컬 HTML 로드, 서명 URL 캐싱
- [ ] `worksheet_runtime.js` 필기 엔진
  - [ ] Pointer Events + `getCoalescedEvents` + 팜 리젝션
  - [ ] 문서 좌표계 변환 (`06-annotation.md` §2)
  - [ ] 캔버스 타일링 (2,000px 단위)
  - [ ] 펜/형광펜/지우개(획 단위)/실행취소·재실행
  - [ ] 필압 → 선 굵기, Catmull-Rom 스무딩
- [ ] Flutter ↔ JS 브리지 (§6 메시지 표)
- [ ] DS 필기 툴바 위젯
- [ ] Drift 스키마: 스트로크 로컬 저장 (즉시 append)
- [ ] Storage 동기화 (디바운스 3초 + 이탈 시) + `rev` 낙관적 잠금 + 스트로크 병합
- [ ] `scrollToQuiz` 딥링크 동작
- [ ] 오프라인: HTML + 스트로크 캐시로 완전 오프라인 열람·필기
- [ ] 성능 검증: 5,000 스트로크 60fps, 입력 지연 < 30ms

## M4 — 복습 & 알림

- [ ] 학습지 완성 시 `review_schedules` 5회차 생성 (1/3/7/16/35일)
- [ ] `review-answer` Edge Function: SM-2 lite 간격 재계산 (`07-review-notifications.md` §2)
- [ ] 알림 권한 요청 타이밍 = **첫 학습지 완성 직후**
- [ ] `flutter_local_notifications` + `timezone` 설정 (iOS/Android)
- [ ] **롤링 재스케줄러** (48개 상한, 4개 트리거) — §4
- [ ] 일일 알림 상한 3개 + 방해 금지 구간
- [ ] 복습 카드 화면 (정답 가리기 → 공개 → grade 선택)
- [ ] 알림 payload → `/review/{id}` 딥링크 (콜드 스타트 포함)
- [ ] 홈 "오늘의 복습 N개" 카드 (알림 거부 사용자용 대체 경로)
- [ ] 오프라인 응답 큐잉 → 온라인 시 동기화
- [ ] 설정: 복습 시간대, 방해 금지, 알림 On/Off

## M5 — 다듬기 & 베타

- [ ] 온보딩 3화면 (가치 제안 → 주제 예시 → 첫 생성)
- [ ] 빈 상태 / 에러 / 로딩 스켈레톤 전수 점검
- [ ] 접근성: 대비비, 터치 타깃, VoiceOver (`02-design-system.md` §6)
- [ ] popol.me 원본 대조 (Widgetbook 카탈로그 vs 원본)
- [ ] 앱 아이콘 / 스플래시 / 스토어 스크린샷
- [ ] 개인정보처리방침 · 이용약관 (LLM 사용 및 데이터 처리 고지 포함)
- [ ] 계정 삭제 기능 (App Store 심사 필수 요건)
- [ ] Sentry 크래시 리포팅 + 익명 사용 분석
- [ ] LLM 비용 알람 및 소프트 차단 (`05-api-spec.md` §5)
- [ ] TestFlight 베타 → 피드백 1라운드

---

## 진행 순서 요약

```
M0 ──┬── M1 (인증·쿼터) ──┐
     ├── M2 (생성) ───────┼── M5 (베타)
     ├── M3 (필기) ───────┤     ↑
     └── M4 (복습·알림) ──┘   M3는 M0 spike + 토큰 확보 후에만 착수
```

## 착수 전 필수 확인 (블로커)

1. **디자인 토큰** — 없으면 M3/M5 착수 불가. (Q2)
2. **Pencil 필압 spike** — 결과에 따라 M3 아키텍처가 바뀐다. (M0 리스크1)
3. **Supabase 프로젝트 / Anthropic API 키** — 없으면 M2 착수 불가. (Q5)
