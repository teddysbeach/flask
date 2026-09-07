import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/analytics.dart';
import '../core/bootstrap.dart';
import '../core/app_error.dart';
import '../core/env.dart';
import '../core/logger.dart';
import '../core/version_gate.dart';
import 'app_config_repository.dart';
import 'supabase.dart';

/// 우리 서버로 보내는 분석·크래시.
///
/// 제3자 SDK 를 안 쓰는 이유는 개인정보 처리방침에 "제3자 공유 없음" 이라고 적었기
/// 때문이다. SDK 하나를 붙이는 순간 그 줄이 거짓말이 되고, 스토어 데이터 세이프티
/// 신고 내용도 바뀐다. 우리가 재려는 것은 퍼널 몇 개와 실패율, 크래시가 전부다.
///
/// 세 가지를 지킨다.
///
///   1. **화면을 막지 않는다.** 전송은 전부 뒤에서, 실패해도 조용하다 —
///      텔레메트리 때문에 사용자가 오류를 보면 본말전도다.
///   2. **잃어버리지 않는다.** 못 보낸 것은 기기에 쌓아 두고 다음에 같이 보낸다.
///      크래시는 특히 그렇다 — 앱이 죽는 순간이 네트워크가 있는 순간이라는 법이 없다.
///   3. **넘치지 않는다.** 큐에 상한을 둔다. 상한이 없으면 오프라인이 길어진 기기의
///      저장소가 조용히 찬다.
class Telemetry implements Analytics, CrashReporter {
  Telemetry({
    required SupabaseClient client,
    required SharedPreferences prefs,
    required String appVersion,
    required String platform,
    this.flushEvery = const Duration(seconds: 20),
  })  : _client = client,
        _prefs = prefs,
        _appVersion = appVersion,
        _platform = platform;

  final SupabaseClient _client;
  final SharedPreferences _prefs;
  final String _appVersion;
  final String _platform;
  final Duration flushEvery;

  static const _kInstallId = 'telemetry_install_id_v1';
  static const _kQueue = 'telemetry_queue_v1';

  /// 큐 상한. 넘으면 **오래된 이벤트부터** 버린다 —
  /// 방금 난 크래시가 3주 전 화면 조회 때문에 밀려나면 안 된다.
  static const maxQueued = 300;

  final _events = <Map<String, Object?>>[];
  final _crashes = <Map<String, Object?>>[];
  Timer? _timer;
  bool _sending = false;

  /// 기기마다 하나. 로그인 전 이벤트(온보딩·가입 시작)를 잇는 유일한 열쇠다.
  /// 재설치하면 새로 생긴다 — 사람이 아니라 설치를 가리키는 값이라 그게 맞다.
  String get installId {
    final saved = _prefs.getString(_kInstallId);
    if (saved != null) return saved;
    final id = _uuidV4();
    unawaited(_prefs.setString(_kInstallId, id));
    return id;
  }

  /// 앱이 켜질 때 한 번. 지난번에 못 보낸 것을 읽어 들이고 주기 전송을 건다.
  Future<void> start() async {
    _restore();
    _timer?.cancel();
    _timer = Timer.periodic(flushEvery, (_) => unawaited(flush()));
    unawaited(flush());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _persist();
  }

  // ── Analytics ────────────────────────────────────────────────────────

  @override
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) {
    final clean = sanitizeProps(props);
    _push(_events, {
      'name': event.name,
      // 앱에서 한 번 거른다. 서버도 거르지만, 애초에 안 싣는 것과 서버가 지우는 것은 다르다.
      'props': clean,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (kDebugMode) AppLogger.debug('[analytics] ${event.name} $clean');
  }

  @override
  void screen(String name) => track(AnalyticsEvent.screenView, props: {'name': name});

  /// 사용자 식별자는 **보내지 않는다.** 서버가 요청의 토큰에서 직접 읽는다 —
  /// 앱이 주장하는 id 를 그대로 믿으면 남의 이름으로 이벤트를 넣을 수 있다.
  @override
  void identify(String? userId) {}

  // ── CrashReporter ────────────────────────────────────────────────────

  @override
  void recordError(Object error, StackTrace? stack, {String? context, bool fatal = false}) {
    // 원문에 토큰·이메일이 섞여 들어올 수 있다. 로거의 마스킹을 그대로 쓴다.
    final message = AppLogger.redact(error.toString());
    _push(_crashes, {
      'fingerprint': crashFingerprint(message, context),
      'message': message,
      'stack': stack == null ? null : AppLogger.redact(stack.toString()),
      'context': context,
      'fatal': fatal,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
    AppLogger.error('[crash]${fatal ? ' FATAL' : ''} ${context ?? ''}', error: error, stack: stack);
    // 죽는 중일 수 있다. 주기 전송을 기다리지 않고 지금 시도하되, 실패해도 큐에 남는다.
    if (fatal) unawaited(flush());
  }

  @override
  void setUser(String? userId) {}

  @override
  void leaveBreadcrumb(String message) => AppLogger.debug('[crumb] $message');

  // ── 전송 ─────────────────────────────────────────────────────────────

  /// 쌓인 것을 보낸다. **던지지 않는다.**
  Future<void> flush() async {
    if (_sending || !Env.isConfigured) return;
    if (_events.isEmpty && _crashes.isEmpty) return;
    _sending = true;

    // 보내는 동안 새로 쌓이는 것과 섞이지 않게 지금 것만 떼어 낸다.
    final events = List<Map<String, Object?>>.from(_events);
    final crashes = List<Map<String, Object?>>.from(_crashes);
    try {
      await _client.functions.invoke('ingest-telemetry', body: {
        'install_id': installId,
        'app_version': _appVersion,
        'platform': _platform,
        if (events.isNotEmpty) 'events': events,
        if (crashes.isNotEmpty) 'crashes': crashes,
      }).withTimeout(const Duration(seconds: 10));
      _events.removeRange(0, events.length);
      _crashes.removeRange(0, crashes.length);
    } catch (e) {
      // 실패는 정상이다(오프라인·서버 점검). 다음에 같이 보낸다.
      AppLogger.debug('텔레메트리 전송 실패 — 다음에 다시 보냅니다: $e');
    } finally {
      _sending = false;
      await _persist();
    }
  }

  void _push(List<Map<String, Object?>> into, Map<String, Object?> item) {
    into.add(item);
    final over = _events.length + _crashes.length - maxQueued;
    // 오래된 이벤트부터 버린다. 크래시는 마지막까지 지킨다.
    if (over > 0) _events.removeRange(0, min(over, _events.length));
  }

  void _restore() {
    final raw = _prefs.getString(_kQueue);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      for (final e in (map['events'] as List? ?? const [])) {
        _events.add(Map<String, Object?>.from(e as Map));
      }
      for (final c in (map['crashes'] as List? ?? const [])) {
        _crashes.add(Map<String, Object?>.from(c as Map));
      }
    } catch (e) {
      // 형식이 깨졌으면 버린다. 텔레메트리 때문에 앱이 못 뜨는 일은 없어야 한다.
      AppLogger.debug('텔레메트리 큐를 읽지 못했어요: $e');
      unawaited(_prefs.remove(_kQueue));
    }
  }

  Future<void> _persist() async {
    if (_events.isEmpty && _crashes.isEmpty) {
      await _prefs.remove(_kQueue);
      return;
    }
    await _prefs.setString(_kQueue, jsonEncode({'events': _events, 'crashes': _crashes}));
  }

  String _uuidV4() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    String h(int a, int z) =>
        b.sublist(a, z).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }
}

/// 같은 크래시를 묶는 열쇠.
///
/// 메시지에는 매번 달라지는 조각이 섞인다 — 인스턴스 주소, uuid, 줄 번호, 시각.
/// 그대로 세면 같은 버그가 200개의 다른 버그로 보이고, 그러면 어느 것부터 고칠지 알 수 없다.
/// **가변 부분을 지운 뒤** 해시한다.
String crashFingerprint(String message, String? context) {
  final normalized = message
      .replaceAll(
          RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
              caseSensitive: false),
          '<id>')
      .replaceAll(RegExp(r'0x[0-9a-fA-F]+'), '<addr>')
      .replaceAll(RegExp(r'\d+'), '<n>')
      .trim()
      .toLowerCase();
  // FNV-1a. 재현 가능하면 충분하다 — 암호용이 아니다.
  var hash = 0x811c9dc5;
  for (final unit in '${context ?? ''}|$normalized'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

final telemetryProvider = Provider<Telemetry>((ref) {
  final info = ref.watch(appInfoProvider).valueOrNull;
  final t = Telemetry(
    client: ref.watch(supabaseProvider),
    prefs: ref.watch(sharedPrefsProvider).requireValue,
    appVersion: info?.display ?? 'unknown',
    platform: ref.watch(appPlatformProvider),
  );
  ref.onDispose(() => unawaited(t.dispose()));
  return t;
});
