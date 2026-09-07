import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logger.dart';

/// 우리가 재는 것. 문자열을 아무 데서나 만들지 않으려고 목록으로 묶는다.
///
/// 이름을 자유롭게 쓰면 6개월 뒤에 `signup_done` 과 `signUpComplete` 가 같이 있고
/// 퍼널이 반으로 갈린다. 새 이벤트는 여기에 추가해야만 존재한다.
enum AnalyticsEvent {
  appOpen,
  onboardingStart,
  onboardingComplete,
  onboardingSkip,
  consentAccept,
  signupStart,
  signupComplete,
  loginComplete,
  logout,
  /// 만들기 화면에 들어온 것. 제출(worksheetCreateStart)과 반드시 구분한다 —
  /// 둘을 한 이름으로 쓰면 한 번 만들 때 이벤트가 두세 번 나가서 생성 성공률이 낮게 보인다.
  worksheetCreateEntry,
  worksheetCreateStart,
  worksheetCreateComplete,
  worksheetCreateFailed,
  worksheetOpen,
  worksheetResponse,
  reviewNotificationOpen,
  reviewAnswer,
  paywallView,
  purchaseStart,
  purchaseComplete,
  purchaseFailed,
  purchaseRestore,
  withdrawStart,
  withdrawComplete,
  screenView,
  errorShown,
}

/// 분석 어댑터. 실제 SDK(Firebase/Amplitude/Mixpanel)는 이 뒤에 꽂는다.
///
/// 인터페이스를 두는 이유는 두 가지다. 하나는 SDK 를 바꿔도 화면 코드가 안 바뀌는 것,
/// 다른 하나는 **개인정보가 실수로 실려 나가는 것을 한곳에서 막는 것**이다.
abstract class Analytics {
  void track(AnalyticsEvent event, {Map<String, Object?> props});
  void screen(String name);

  /// 로그인한 사용자를 잇는다. 식별자만 보내고 이메일·전화번호는 절대 보내지 않는다.
  void identify(String? userId);
}

/// 개인정보로 보이는 키는 아예 실어 보내지 않는다.
const _blockedProps = {
  'email', 'phone', 'password', 'token', 'access_token', 'refresh_token',
  'name', 'nickname', 'address', 'birth', 'receipt',
};

Map<String, Object?> sanitizeProps(Map<String, Object?> props) {
  final out = <String, Object?>{};
  props.forEach((k, v) {
    if (_blockedProps.contains(k.toLowerCase())) return;
    out[k] = v is String ? AppLogger.redact(v) : v;
  });
  return out;
}

/// 기본 구현. SDK 를 붙이기 전까지 디버그 빌드에서만 찍는다.
class DebugAnalytics implements Analytics {
  const DebugAnalytics();

  @override
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) {
    if (!kDebugMode) return;
    AppLogger.debug('[analytics] ${event.name} ${sanitizeProps(props)}');
  }

  @override
  void screen(String name) => track(AnalyticsEvent.screenView, props: {'name': name});

  @override
  void identify(String? userId) {
    if (!kDebugMode) return;
    AppLogger.debug('[analytics] identify ${userId ?? '(anonymous)'}');
  }
}

/// 크래시·오류 리포트 어댑터. Sentry/Crashlytics 를 이 뒤에 꽂는다.
abstract class CrashReporter {
  void recordError(Object error, StackTrace? stack, {String? context, bool fatal});
  void setUser(String? userId);
  void leaveBreadcrumb(String message);
}

class DebugCrashReporter implements CrashReporter {
  const DebugCrashReporter();

  @override
  void recordError(Object error, StackTrace? stack, {String? context, bool fatal = false}) {
    AppLogger.error('[crash]${fatal ? ' FATAL' : ''} ${context ?? ''}', error: error, stack: stack);
  }

  @override
  void setUser(String? userId) {}

  @override
  void leaveBreadcrumb(String message) => AppLogger.debug('[crumb] $message');
}

/// 실제 구현은 main 에서 갈아 끼운다. 화면은 이 provider 만 알면 된다.
final analyticsProvider = Provider<Analytics>((_) => const DebugAnalytics());
final crashReporterProvider = Provider<CrashReporter>((_) => const DebugCrashReporter());
