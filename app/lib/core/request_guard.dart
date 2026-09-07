import 'dart:async';
import 'dart:math';

import 'app_error.dart';
import 'logger.dart';

/// 같은 요청이 두 번 나가지 않게 하고, 실패하면 물러섰다 다시 시도한다.
///
/// 중복 요청은 버튼 두 번 누르기로 늘 생기고, 학습지 생성처럼 **쿼터를 깎는 요청**에서는
/// 사용자가 돈을 두 번 낸다. 그래서 UI 의 disabled 에 기대지 않고 여기서 막는다.
class RequestGuard {
  RequestGuard({this.maxAttempts = 3, this.baseDelay = const Duration(milliseconds: 400)});

  final int maxAttempts;
  final Duration baseDelay;

  final _inFlight = <String, Future<Object?>>{};
  final _rng = Random();

  /// 같은 key 의 요청이 이미 날아가 있으면 그 결과를 함께 기다린다.
  Future<T> dedupe<T>(String key, Future<T> Function() run) {
    final existing = _inFlight[key];
    if (existing != null) return existing.then((v) => v as T);

    final future = run();
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  /// 다시 해볼 가치가 있는 실패만 다시 한다.
  /// 401·403·검증 실패는 백 번 해도 같으므로 즉시 올린다.
  Future<T> retry<T>(
    Future<T> Function() run, {
    String? label,
    bool Function(AppError)? retryIf,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await run();
      } catch (e, st) {
        final err = AppError.from(e, st);
        final worth = retryIf?.call(err) ?? _defaultRetryIf(err);
        if (!worth || attempt >= maxAttempts) rethrow;

        // 지터를 섞는다. 안 섞으면 장애 복구 순간에 모든 기기가 동시에 다시 때린다.
        final backoff = baseDelay * (1 << (attempt - 1));
        final jitter = Duration(milliseconds: _rng.nextInt(200));
        AppLogger.debug('재시도 ${label ?? ''} $attempt/$maxAttempts (${err.kind.name})');
        await Future<void>.delayed(backoff + jitter);
      }
    }
  }

  static bool _defaultRetryIf(AppError e) => switch (e.kind) {
        AppErrorKind.offline || AppErrorKind.timeout || AppErrorKind.server => true,
        _ => false,
      };
}

/// 버튼 연타 방지. 화면에서 쓰는 가장 흔한 형태.
class Debouncer {
  Debouncer(this.duration);
  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() => _timer?.cancel();
}
