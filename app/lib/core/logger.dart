import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 로그. 개인정보를 절대 그대로 남기지 않는다.
///
/// 앱 로그는 크래시 리포트·기기 로그·고객 문의 캡처로 빠져나간다.
/// 이메일·전화번호·토큰이 한 번이라도 섞이면 그때부터는 회수할 방법이 없다.
/// 그래서 출력 직전에 무조건 한 번 가린다 — 부르는 쪽이 조심하는 것에 기대지 않는다.
class AppLogger {
  const AppLogger._();

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phone = RegExp(r'(?<!\d)(01[0-9])[- ]?(\d{3,4})[- ]?(\d{4})(?!\d)');
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}');
  // Dart 는 (?i) 인라인 플래그를 지원하지 않는다 — caseSensitive 로 준다.
  static final _bearer = RegExp(r'bearer\s+[A-Za-z0-9._-]+', caseSensitive: false);
  static final _longToken = RegExp(r'(?<![A-Za-z0-9])[A-Za-z0-9_-]{40,}(?![A-Za-z0-9])');

  /// 로그에 나가는 모든 문자열이 지나는 문.
  static String redact(String input) => input
      .replaceAll(_jwt, '[jwt]')
      .replaceAll(_bearer, 'Bearer [token]')
      .replaceAllMapped(_email, (m) {
        final at = m[0]!.indexOf('@');
        return '${m[0]!.substring(0, at.clamp(0, 2))}***${m[0]!.substring(at)}';
      })
      .replaceAllMapped(_phone, (m) => '${m[1]}-****-${m[3]}')
      .replaceAll(_longToken, '[redacted]');

  static void debug(String message, {String name = 'onpar'}) {
    if (!kDebugMode) return;
    developer.log(redact(message), name: name);
  }

  static void info(String message, {String name = 'onpar'}) {
    developer.log(redact(message), name: name);
  }

  static void error(String message, {Object? error, StackTrace? stack, String name = 'onpar'}) {
    developer.log(
      redact(message),
      name: name,
      error: error == null ? null : redact(error.toString()),
      stackTrace: stack,
      level: 1000,
    );
  }
}
