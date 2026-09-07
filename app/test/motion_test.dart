import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 모션의 규칙을 값으로 지킨다.
///
/// 움직임은 눈으로 봐야 아는 것이라 테스트하기 어렵다고들 하지만, 정작 틀리는 것은
/// 눈에 안 보이는 쪽이다 — 동작 줄이기를 안 지키거나, 앱과 학습지의 값이 갈라지거나,
/// 곡선이 감속이 아니라 가속이 되어 있거나. 그건 전부 값으로 잴 수 있다.
void main() {
  group('토큰', () {
    final tokens = jsonDecode(File('../design/design_tokens.json').readAsStringSync())
        as Map<String, Object?>;
    final motion = tokens['motion']! as Map<String, Object?>;
    final easing = motion['easing']! as Map<String, Object?>;
    final duration = motion['duration']! as Map<String, Object?>;

    test('생성된 Dart 곡선이 SSOT 와 같다', () {
      // 예전에는 생성기가 JSON 을 안 읽고 곡선을 직접 적어 두었다. 그래서 학습지 CSS 는
      // Material 곡선으로, 앱은 다른 곡선으로 움직였고 아무도 몰랐다.
      List<double> parse(String v) => RegExp(r'-?[\d.]+')
          .allMatches(v)
          .map((m) => double.parse(m.group(0)!))
          .toList();

      final expected = <String, Cubic>{
        'standard': DsCurve.standard,
        'enter': DsCurve.enter,
        'exit': DsCurve.exit,
        'emphasized': DsCurve.emphasized,
        'spring': DsCurve.spring,
      };
      for (final entry in expected.entries) {
        final n = parse(easing[entry.key]! as String);
        expect([entry.value.a, entry.value.b, entry.value.c, entry.value.d], n,
            reason: '${entry.key} 곡선이 design_tokens.json 과 다르다');
      }
    });

    test('생성된 Dart 시간이 SSOT 와 같다', () {
      expect(DsMotion.instant.inMilliseconds, duration['instant']);
      expect(DsMotion.fast.inMilliseconds, duration['fast']);
      expect(DsMotion.base.inMilliseconds, duration['base']);
      expect(DsMotion.slow.inMilliseconds, duration['slow']);
      expect(DsMotion.slower.inMilliseconds, duration['slower']);
    });

    test('학습지 CSS 에도 같은 값이 실린다', () {
      // 앱만 고치고 학습지를 안 고치면 같은 제품이 두 속도로 움직인다.
      final css = File('../server/supabase/functions/_shared/tokens.css.ts').readAsStringSync();
      for (final e in easing.entries) {
        expect(css, contains('--ds-ease-${e.key}: ${e.value}'),
            reason: '학습지 CSS 에 ${e.key} 곡선이 없다');
      }
      for (final d in duration.entries) {
        expect(css, contains('--ds-duration-${d.key}: ${d.value}ms'));
      }
    });

    test('들어오는 곡선은 전부 감속이다', () {
      // 애플의 움직임이 그렇다. 첫 구간에서 이미 절반 넘게 가 있고, 끝에서 길게 눕는다.
      // 가속 곡선으로 들어오면 "느리게 시작해 튀어나오는" 느낌이 되고, 그건 광고 배너의 움직임이다.
      for (final c in [DsCurve.standard, DsCurve.enter, DsCurve.emphasized]) {
        expect(c.transform(0.5), greaterThan(0.5),
            reason: '$c 는 절반 시점에 절반을 못 갔다 — 감속이 아니다');
      }
      // 나가는 곡선만 반대다. 사라지는 것은 천천히 시작해 빨리 끝난다.
      expect(DsCurve.exit.transform(0.5), lessThan(0.5));
    });

    test('스프링만 1 을 넘겼다 돌아온다', () {
      // 넘김(overshoot)이 있는 곡선은 색 보간에 쓰면 범위를 벗어난다.
      // 그래서 축하하는 자리에만 쓰고, 나머지 곡선에는 넘김이 없어야 한다.
      double peak(Cubic c) {
        var m = 0.0;
        for (var i = 0; i <= 100; i++) {
          final v = c.transform(i / 100);
          if (v > m) m = v;
        }
        return m;
      }

      expect(peak(DsCurve.spring), greaterThan(1.0));
      for (final c in [DsCurve.standard, DsCurve.enter, DsCurve.exit, DsCurve.emphasized]) {
        expect(peak(c), lessThanOrEqualTo(1.0001), reason: '$c 에 넘김이 있다');
      }
    });
  });

  group('동작 줄이기', () {
    Widget wrap(Widget child, {required bool reduce}) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: MaterialApp(theme: dsThemeData(Brightness.light), home: Scaffold(body: child)),
        );

    testWidgets('켜면 시간이 0 이 된다', (tester) async {
      late Duration on;
      late Duration off;
      await tester.pumpWidget(wrap(
        Builder(builder: (c) {
          on = dsDuration(c, DsMotion.base);
          return const SizedBox();
        }),
        reduce: true,
      ));
      await tester.pumpWidget(wrap(
        Builder(builder: (c) {
          off = dsDuration(c, DsMotion.base);
          return const SizedBox();
        }),
        reduce: false,
      ));
      expect(on, Duration.zero);
      expect(off, DsMotion.base);
    });

    testWidgets('켜도 내용은 그대로 보인다', (tester) async {
      // 움직임을 줄여 달라는 요청이지 내용을 빼 달라는 요청이 아니다.
      // 첫 프레임부터 완전히 불투명해야 한다 — 페이드가 남아 있으면 안 지킨 것이다.
      await tester.pumpWidget(wrap(
        const DsFadeSlide(child: Text('보여야 한다')),
        reduce: true,
      ));
      await tester.pump();

      expect(find.text('보여야 한다'), findsOneWidget);
      // 페이지 전환 등 바깥의 것과 섞이지 않게 DsFadeSlide 안쪽만 본다.
      final inside = find.descendant(of: find.byType(DsFadeSlide), matching: find.byType(FadeTransition));
      expect(inside, findsNothing, reason: '동작 줄이기를 켰는데 페이드가 남아 있다');
      expect(find.descendant(of: find.byType(DsFadeSlide), matching: find.byType(Transform)),
          findsNothing, reason: '동작 줄이기를 켰는데 이동이 남아 있다');
    });

    testWidgets('꺼져 있으면 흐릿하게 시작해 또렷해진다', (tester) async {
      await tester.pumpWidget(wrap(
        const DsFadeSlide(child: Text('들어온다')),
        reduce: false,
      ));
      await tester.pump();
      final fade = find.descendant(of: find.byType(DsFadeSlide), matching: find.byType(FadeTransition));
      final start = tester.widget<FadeTransition>(fade).opacity.value;
      expect(start, lessThan(1.0));

      await tester.pump(DsMotion.slower);
      final end = tester.widget<FadeTransition>(fade).opacity.value;
      expect(end, 1.0);
    });
  });

  group('화면 전환', () {
    test('모든 플랫폼이 같은 전환을 쓴다', () {
      // iOS 만 애플처럼 움직이고 안드로이드는 Material 로 움직이면, 같은 앱을 두 사람이
      // 다르게 쓴다. 우리 화면이니 우리 규칙으로 통일한다.
      final theme = dsThemeData(Brightness.light);
      for (final p in TargetPlatform.values) {
        expect(theme.pageTransitionsTheme.builders[p], isA<DsPageTransitionsBuilder>(),
            reason: '$p 의 화면 전환이 기본값(Material/Cupertino)이다');
      }
    });

    testWidgets('새 화면은 오른쪽에서 들어오고 이전 화면은 덜 움직인다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: dsThemeData(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('다음 화면'))),
              ),
              child: const Text('가기'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('가기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final slides = tester.widgetList<SlideTransition>(find.byType(SlideTransition)).toList();
      expect(slides, isNotEmpty, reason: '밀려 들어오는 전환이 없다');

      final offsets = slides.map((s) => s.position.value.dx).toList();
      // 들어오는 쪽은 오른쪽(양수)에 있고, 나가는 쪽은 왼쪽(음수)으로 조금만 간다.
      expect(offsets.any((dx) => dx > 0), isTrue, reason: '새 화면이 오른쪽에서 오지 않는다');
      expect(offsets.every((dx) => dx > -0.25), isTrue,
          reason: '이전 화면이 새 화면만큼 움직인다 — 시차가 없으면 어디서 왔는지 안 보인다');

      await tester.pumpAndSettle();
      expect(find.text('다음 화면'), findsOneWidget);
    });
  });
}
