import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar/core/analytics.dart';
import 'package:onpar/core/bootstrap.dart';
import 'package:onpar/core/routes.dart';
import 'package:onpar/features/onboarding/onboarding_demos.dart';
import 'package:onpar/features/onboarding/onboarding_screen.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 온보딩 워크스루.
///
/// 여기서 재는 것은 "화면이 뜨는가" 가 아니라 **데모가 진짜로 동작하는가** 다.
/// 온보딩의 셋째 장은 설명이 아니라 실제 필기칸이고, 그게 죽으면 사용자는
/// 이 앱의 유일한 차별점을 만져 보지 못한 채로 로그인 화면에 도착한다.
/// 죽어도 아무 예외가 안 나는 종류라 값으로 잰다.
class _Spy implements Analytics {
  final events = <(AnalyticsEvent, Map<String, Object?>)>[];

  @override
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) =>
      events.add((event, Map<String, Object?>.of(props)));

  @override
  void screen(String name) {}

  @override
  void identify(String? userId) {}

  Map<String, Object?>? propsOf(AnalyticsEvent e) {
    for (final r in events) {
      if (r.$1 == e) return r.$2;
    }
    return null;
  }
}

/// 온보딩이 끝나면 동의 화면으로 간다. 진짜 동의 화면은 필요 없고,
/// **갔다는 사실**만 확인하면 된다.
const _consentMarker = '동의 화면';

Widget _wrap({
  required Analytics analytics,
  required SharedPreferences prefs,
  bool reduceMotion = false,
}) {
  final router = GoRouter(
    initialLocation: Routes.onboarding,
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(
        path: Routes.consent,
        builder: (_, __) => const Scaffold(body: Center(child: Text(_consentMarker))),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      analyticsProvider.overrideWithValue(analytics),
      sharedPrefsProvider.overrideWith((_) => prefs),
    ],
    child: MaterialApp.router(
      theme: dsThemeData(Brightness.light),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
    ),
  );
}

/// 데모 하나만 띄운다. 온보딩 화면 전체를 거치지 않고 위젯 자체를 잴 때 쓴다.
Widget _bare(Widget child) => MaterialApp(
      theme: dsThemeData(Brightness.light),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

/// 데모들이 무한 반복이라 `pumpAndSettle` 은 영원히 안 끝난다. 정해진 만큼만 돌린다.
Future<void> _advance(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _toPage(WidgetTester tester, int page) async {
  for (var i = 0; i < page; i++) {
    await tester.tap(find.text('다음'));
    await _advance(tester, 6);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, _Spy spy, {bool reduceMotion = false}) async {
    // 아이패드 세로. 워크스루가 스크롤 없이 다 보이는 크기여야
    // 자리를 못 찾은 위젯을 "화면 밖" 으로 변명하지 않는다.
    tester.view.physicalSize = const Size(1000, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
        _wrap(analytics: spy, prefs: prefs, reduceMotion: reduceMotion));
    await tester.pump();
  }

  testWidgets('네 장이고, 마지막 장에서만 버튼이 시작하기가 된다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);

    expect(find.text('다음'), findsOneWidget);
    expect(find.text('시작하기'), findsNothing);

    await _toPage(tester, 3);

    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('다음'), findsNothing);
    expect(spy.events.first.$1, AnalyticsEvent.onboardingStart);
  });

  testWidgets('네 장이 각자 다른 데모를 쓴다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);

    // 데모가 한 장이라도 빠지면 그 장은 글만 남는다 — 예외 없이 조용히 나빠진다.
    final demos = <Type>[
      TopicToSheetDemo,
      WorksheetAnatomyDemo,
      InkDemo,
      ReviewCurveDemo,
    ];
    for (var i = 0; i < demos.length; i++) {
      if (i > 0) await _toPage(tester, 1);
      expect(find.byType(demos[i]), findsOneWidget, reason: '${i + 1}장의 데모가 없다');
    }
  });

  testWidgets('필기 데모: 손짓이 실제로 획이 된다', (tester) async {
    // 화면 없이 잴 수 있는 것을 화면으로 재지 않는다.
    // 예전 판은 "안내 문구가 사라졌는가" 로 갈음했는데, 그건 손가락이 닿았다는 뜻일 뿐이라
    // 점 이동을 통째로 무시해도 통과했다. 이제는 담긴 점의 수를 본다.
    final strokes = InkDemoStrokes();
    addTearDown(strokes.dispose);

    await tester.pumpWidget(_bare(InkDemo(active: true, strokes: strokes)));
    await tester.pump();

    expect(strokes.userPoints, 0);
    expect(strokes.seed, isNotEmpty, reason: '미리 쓰인 손글씨가 없다 — 빈 종이가 뜬다');
    expect(find.text('여기에 직접 써 보세요'), findsOneWidget);

    final box = tester.getRect(find.byKey(inkDemoCanvasKey));
    final g = await tester.startGesture(Offset(box.left + 40, box.center.dy + 40));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(9, -3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();

    expect(strokes.user, hasLength(1));
    expect(strokes.userPoints, greaterThanOrEqualTo(8),
        reason: '손짓은 받았는데 획이 안 자랐다');
    expect(find.text('여기에 직접 써 보세요'), findsNothing);
  });

  testWidgets('필기 데모: 필압이 굵기가 된다', (tester) async {
    // 이 앱이 종이와 겨루는 지점이 여기 하나다. 필압을 버리면 데모는 그냥 그림판이 된다.
    final strokes = InkDemoStrokes();
    addTearDown(strokes.dispose);
    await tester.pumpWidget(_bare(InkDemo(active: true, strokes: strokes)));
    await tester.pump();

    final box = tester.getRect(find.byKey(inkDemoCanvasKey));
    final start = Offset(box.left + 40, box.center.dy + 40);
    final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await g.downWithCustomEvent(
      start,
      PointerDownEvent(
        position: start,
        kind: PointerDeviceKind.stylus,
        pressure: 0.15,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await g.updateWithCustomEvent(PointerMoveEvent(
      position: start + const Offset(30, 0),
      kind: PointerDeviceKind.stylus,
      pressure: 0.95,
      pressureMin: 0,
      pressureMax: 1,
    ));
    await g.up();
    await tester.pump();

    final w = strokes.user.single.widths;
    expect(w, hasLength(2));
    expect(w.last, greaterThan(w.first * 1.5),
        reason: '세게 눌렀는데 굵기가 그대로다 — 필압이 버려지고 있다');
  });

  testWidgets('필기 데모: 전체 지우기가 미리 쓰인 손글씨까지 지운다', (tester) async {
    final strokes = InkDemoStrokes();
    addTearDown(strokes.dispose);
    await tester.pumpWidget(_bare(InkDemo(active: true, strokes: strokes)));
    await tester.pump();

    expect(strokes.strokeCount, greaterThan(1));
    // 지울 것이 있으면 켜져 있고, 없으면 스스로 꺼진다.
    bool clearEnabled() =>
        tester.getSemantics(find.bySemanticsLabel('전체 지우기')).flagsCollection.isEnabled;
    expect(clearEnabled(), isTrue);

    await tester.tap(find.text('전체 지우기'));
    await tester.pump();

    expect(strokes.isEmpty, isTrue, reason: '"전체" 가 거짓말이 됐다');
    expect(clearEnabled(), isFalse);
  });

  testWidgets('필기 데모: 지우개가 닿은 획만 지운다', (tester) async {
    final strokes = InkDemoStrokes();
    addTearDown(strokes.dispose);
    await tester.pumpWidget(_bare(InkDemo(active: true, strokes: strokes)));
    await tester.pump();

    final box = tester.getRect(find.byKey(inkDemoCanvasKey));
    final a = Offset(box.left + 40, box.center.dy + 50);
    final farAway = Offset(box.right - 30, box.top + 10);

    var g = await tester.startGesture(a);
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();
    final seeded = strokes.seed.length;
    expect(strokes.user, hasLength(1));

    await tester.tap(find.text('지우개'));
    await tester.pump();

    // 멀리서 문지르면 아무것도 안 지워진다.
    g = await tester.startGesture(farAway);
    await g.moveBy(const Offset(10, 0));
    await g.up();
    await tester.pump();
    expect(strokes.user, hasLength(1), reason: '안 닿은 획이 지워졌다');
    expect(strokes.seed, hasLength(seeded));

    // 그은 자리를 문지르면 그 획만 지워진다.
    g = await tester.startGesture(a);
    await g.moveBy(const Offset(4, 0));
    await g.up();
    await tester.pump();
    expect(strokes.user, isEmpty, reason: '닿은 획이 안 지워졌다');
  });

  testWidgets('필기 도구를 바꿀 수 있다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);
    await _toPage(tester, 2);

    bool selected(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label)).flagsCollection.isSelected;

    // 처음에는 펜이 선택되어 있다.
    expect(selected('펜'), isTrue);

    await tester.tap(find.text('형광펜'));
    await _advance(tester, 3);

    expect(selected('형광펜'), isTrue);
    expect(selected('펜'), isFalse);
  });

  testWidgets('직접 그어 봤는지가 완료 이벤트에 실린다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);
    await _toPage(tester, 2);
    await _advance(tester);

    final box = tester.getRect(find.byType(InkDemo));
    final g = await tester.startGesture(Offset(box.left + 60, box.bottom - 60));
    await g.moveBy(const Offset(40, -10));
    await g.up();
    await tester.pump();

    await _toPage(tester, 1);
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    expect(spy.propsOf(AnalyticsEvent.onboardingComplete),
        {'pages': 4, 'count': 1});
    expect(find.text(_consentMarker), findsOneWidget);
  });

  testWidgets('건너뛰면 몇 장째였는지가 남는다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);
    await _toPage(tester, 1);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(spy.propsOf(AnalyticsEvent.onboardingSkip), {'page': 1, 'pages': 4});
    expect(find.text(_consentMarker), findsOneWidget);
  });

  testWidgets('건너뛰어도 온보딩을 봤다고 기록한다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy);
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(LocalFlags(prefs).onboarded, isTrue,
        reason: '기록을 안 하면 앱을 켤 때마다 같은 장들을 다시 본다');
  });

  testWidgets('동작 줄이기: 데모가 완성된 모습으로 멈춘다', (tester) async {
    final spy = _Spy();
    await pump(tester, spy, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 300));

    // 타임라인이 끝난 상태 = 학습지가 다 만들어진 화면.
    expect(find.text('학습지가 준비됐어요'), findsOneWidget);

    // 그리고 애니메이션이 안 도는 것이 확인되어야 pumpAndSettle 이 끝난다.
    await tester.pumpAndSettle();
  });
}
