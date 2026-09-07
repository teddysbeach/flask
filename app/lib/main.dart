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

Future<void> main() async {
  // runZonedGuarded 안에서 초기화해야 비동기 오류까지 한 곳으로 모인다.
  // 이 Future 는 앱이 살아 있는 동안 끝나지 않는다 — 기다릴 대상이 아니다.
  unawaited(runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    const crash = DebugCrashReporter();

    // 위젯 트리에서 터진 것. 릴리스에서는 빨간 화면 대신 우리 화면을 보여준다.
    FlutterError.onError = (details) {
      crash.recordError(details.exception, details.stack, context: details.context?.toString());
      if (kDebugMode) FlutterError.presentError(details);
    };
    // 플랫폼(엔진) 쪽에서 터진 것.
    PlatformDispatcher.instance.onError = (error, stack) {
      crash.recordError(error, stack, fatal: true);
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
      crash.recordError(e, st, context: 'initSupabase');
    }

    final prefs = await SharedPreferences.getInstance();

    runApp(
      ProviderScope(
        overrides: [
          // 부팅 직후 동기적으로 읽어야 하는 값이라 미리 채워 넣는다.
          sharedPrefsProvider.overrideWith((_) => Future.value(prefs)),
          analyticsProvider.overrideWithValue(const DebugAnalytics()),
          crashReporterProvider.overrideWithValue(crash),
        ],
        child: const OnparApp(),
      ),
    );
  }, (error, stack) {
    const DebugCrashReporter().recordError(error, stack, context: 'zone', fatal: true);
  }));
}
