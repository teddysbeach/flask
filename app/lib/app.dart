import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import 'core/purchase_watcher.dart';
import 'features/settings/theme_controller.dart';
import 'router.dart';

/// 앱 껍데기. 테마와 라우터만 얹는다.
class OnparApp extends ConsumerWidget {
  const OnparApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    // 결제 결과를 듣는 귀. 화면이 아니라 앱이 들고 있어야 한다 —
    // 결제 화면을 닫은 뒤에 도착하는 결제가 실제로 있다.
    ref.watch(purchaseWatcherProvider);

    return MaterialApp.router(
      title: 'ONPAR',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // 우리 문구는 전부 한국어인데 Material 위젯만 영어였다 —
      // 글을 길게 눌렀을 때 뜨는 "Cut / Copy / Paste" 가 대표적이다.
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: dsThemeData(Brightness.light),
      darkTheme: dsThemeData(Brightness.dark),
      themeMode: mode,
      // 접근성: 시스템 글꼴 확대를 존중하되, 레이아웃이 완전히 무너지는 배율에서 멈춘다.
      // 여기서 1.0 으로 고정해 버리면 큰 글씨가 필요한 사람이 앱을 못 쓴다.
      builder: (context, child) {
        final scaler = MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.6);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
