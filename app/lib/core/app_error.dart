import 'dart:async';
import 'dart:io';

/// 앱이 사용자에게 보여줄 수 있는 실패의 전부.
///
/// 화면마다 정상 상태만 만들면 앱이 무너진다. 그래서 실패를 문자열이 아니라
/// **닫힌 목록**으로 둔다 — 새 실패가 생기면 컴파일러가 처리 안 한 화면을 알려준다.
enum AppErrorKind {
  /// 인터넷이 없다. 사용자 잘못이 아니고, 재시도가 의미 있다.
  offline,

  /// 응답이 너무 늦다.
  timeout,

  /// 로그인이 필요하거나 세션이 끝났다. → 로그인으로 보내고 원래 화면을 기억한다.
  unauthorized,

  /// 로그인은 됐지만 권한이 없다. 재시도해도 소용없다.
  forbidden,

  /// 없는 것(삭제된 학습지, 만료된 링크).
  notFound,

  /// 서버가 깨졌다. 우리 잘못이다.
  server,

  /// 계획된 점검.
  maintenance,

  /// 너무 자주 눌렀다.
  rateLimited,

  /// 쿼터 소진. 실패가 아니라 결제 화면으로 가는 분기다.
  quotaExhausted,

  /// 입력이 규칙에 안 맞는다. 사용자가 고칠 수 있다.
  validation,

  /// 사용자가 스스로 취소했다. 오류 화면을 띄우면 안 된다.
  cancelled,

  unknown,
}

/// 사용자에게 보이는 실패.
///
/// `message` 는 그대로 화면에 나가므로 언제나 우리 탓으로, 다음 행동이 있게 쓴다.
/// 원인(`cause`)은 로그·크래시 리포트에만 가고 화면에는 절대 안 나간다.
class AppError implements Exception {
  const AppError(
    this.kind, {
    required this.message,
    this.cause,
    this.retryable = true,
    this.code,
  });

  final AppErrorKind kind;
  final String message;
  final Object? cause;
  final bool retryable;

  /// 서버가 준 기계용 코드(`quota_exhausted` 등). 화면 분기에만 쓴다.
  final String? code;

  bool get isCancelled => kind == AppErrorKind.cancelled;

  @override
  String toString() => 'AppError(${kind.name}${code == null ? '' : ':$code'})';

  static const _msg = {
    AppErrorKind.offline: '인터넷이 끊긴 것 같아요. 연결을 확인하고 다시 시도해 주세요.',
    AppErrorKind.timeout: '응답이 너무 늦어요. 잠시 뒤에 다시 시도해 주세요.',
    AppErrorKind.unauthorized: '로그인이 필요해요.',
    AppErrorKind.forbidden: '이 내용을 볼 권한이 없어요.',
    AppErrorKind.notFound: '찾을 수 없어요. 삭제되었거나 링크가 만료됐을 수 있어요.',
    AppErrorKind.server: '저희 쪽에서 문제가 생겼어요. 잠시 뒤에 다시 시도해 주세요.',
    AppErrorKind.maintenance: '지금은 점검 중이에요. 끝나면 바로 알려 드릴게요.',
    AppErrorKind.rateLimited: '요청이 너무 빨라요. 잠깐 쉬었다가 다시 해주세요.',
    AppErrorKind.quotaExhausted: '남은 학습지를 다 쓰셨어요.',
    AppErrorKind.validation: '입력을 다시 확인해 주세요.',
    AppErrorKind.cancelled: '취소했어요.',
    AppErrorKind.unknown: '문제가 생겼어요. 잠시 뒤에 다시 시도해 주세요.',
  };

  factory AppError.of(AppErrorKind kind, {Object? cause, String? message, String? code}) => AppError(
        kind,
        message: message ?? _msg[kind]!,
        cause: cause,
        code: code,
        retryable: kind != AppErrorKind.forbidden &&
            kind != AppErrorKind.validation &&
            kind != AppErrorKind.cancelled &&
            kind != AppErrorKind.quotaExhausted,
      );

  /// 아무 예외나 받아 사용자에게 보여줄 수 있는 형태로 바꾼다.
  /// 여기서 걸러지지 않은 것은 전부 `unknown` 이고, 원문은 화면에 새지 않는다.
  factory AppError.from(Object error, [StackTrace? stack]) {
    if (error is AppError) return error;
    if (error is SocketException) return AppError.of(AppErrorKind.offline, cause: error);
    if (error is TimeoutException) return AppError.of(AppErrorKind.timeout, cause: error);
    if (error is HttpException) return AppError.of(AppErrorKind.server, cause: error);
    return AppError.of(AppErrorKind.unknown, cause: error);
  }

  /// HTTP 상태 코드 → 실패 종류.
  static AppErrorKind kindOfStatus(int status) => switch (status) {
        401 => AppErrorKind.unauthorized,
        403 => AppErrorKind.forbidden,
        404 => AppErrorKind.notFound,
        408 => AppErrorKind.timeout,
        429 => AppErrorKind.rateLimited,
        503 => AppErrorKind.maintenance,
        >= 500 => AppErrorKind.server,
        >= 400 => AppErrorKind.validation,
        _ => AppErrorKind.unknown,
      };
}
