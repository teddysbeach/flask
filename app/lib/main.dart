import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/analytics.dart';
import 'core/bootstrap.dart';
import 'core/logger.dart';
import 'data/supabase.dart';
import 'data/telemetry.dart';

Future<void> main() async {
  // runZonedGuarded 안에서 초기화해야 비동기 오류까지 한 곳으로 모인다.
  // 이 Future 는 앱이 살아 있는 동안 끝나지 않는다 — 기다릴 대상이 아니다.
  unawaited(runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 텔레메트리가 붙기 전에도 오류는 난다(설정 읽기·Supabase 초기화).
    // 그 구간은 콘솔이 받고, 붙은 뒤에는 서버가 받는다.
    CrashReporter reporter = const DebugCrashReporter();

    // 위젯 트리에서 터진 것. 릴리스에서는 빨간 화면 대신 우리 화면을 보여준다.
    FlutterError.onError = (details) {
      reporter.recordError(details.exception, details.stack,
          context: details.context?.toString());
      if (kDebugMode) FlutterError.presentError(details);
    };
    // 플랫폼(엔진) 쪽에서 터진 것.
    PlatformDispatcher.instance.onError = (error, stack) {
      reporter.recordError(error, stack, fatal: true);
      return true;
    };

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      // 아이패드에서 학습지를 가로로 펼쳐 쓰는 사람이 있다. 막지 않는다.
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // 설정이 없어도 앱은 떠야 한다 — 그래야 "설정이 없다" 고 말해 줄 수 있다.
    try {
      await initSupabase();
    } catch (e, st) {
      AppLogger.error('Supabase 초기화 실패', error: e, stack: st);
      reporter.recordError(e, st, context: 'initSupabase');
    }

    final prefs = await SharedPreferences.getInstance();

    // 컨테이너를 먼저 만들어 텔레메트리를 꺼내 쓴다. runApp 안에서 만들면
    // 앱이 뜨기 전 구간의 오류를 받을 곳이 없고, 두 벌을 만들면 큐가 갈라진다.
    late final ProviderContainer container;
    container = ProviderContainer(overrides: [
      // 이미 읽은 값이라 **동기로** 넣는다. Future.value 로 넣으면 첫 프레임이
      // AsyncLoading 이 되고, 그 틈에 라우터가 판정을 돌린다.
      sharedPrefsProvider.overrideWith((_) => prefs),
      // 화면은 analyticsProvider / crashReporterProvider 만 안다. 실제 구현은 여기서 꽂는다.
      analyticsProvider.overrideWith((ref) => ref.watch(telemetryProvider)),
      crashReporterProvider.overrideWith((ref) => ref.watch(telemetryProvider)),
    ]);

    final telemetry = container.read(telemetryProvider);
    unawaited(telemetry.start());
    // 이제부터 오류는 우리 서버로도 간다. 여태 디버그 콘솔에만 찍혀서,
    // 릴리스에서 무슨 일이 나는지 알 방법이 없었다.
    reporter = telemetry;
    _zoneReporter = telemetry;

    runApp(UncontrolledProviderScope(container: container, child: const OnparApp()));
  }, (error, stack) {
    // 존 밖으로 새어 나온 비동기 오류. 여기까지 왔다는 것은 어디선가 안 잡았다는 뜻이다.
    (_zoneReporter ?? const DebugCrashReporter())
        .recordError(error, stack, context: 'zone', fatal: true);
  }));
}

/// 존 핸들러는 클로저 밖에서 불린다. 컨테이너를 붙잡고 있을 수 없어 여기 한 칸을 둔다.
CrashReporter? _zoneReporter;
