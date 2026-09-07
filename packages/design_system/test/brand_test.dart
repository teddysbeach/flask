import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 로고 테스트.
///
/// 픽셀을 고정하지는 않는다(골든은 Flutter 판 올릴 때마다 흔들린다).
/// 대신 **로고가 로고인 조건**을 고정한다 — 비율, 하나의 이름, 색을 따르는 것.
Widget _wrap(Widget child) => MaterialApp(
      theme: dsThemeData(Brightness.light),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('심볼은 1:2 비율을 지킨다', (tester) async {
    await tester.pumpWidget(_wrap(const OnparSymbol(height: 96)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(OnparSymbol));
    expect(size.height, 96);
    expect(size.width, closeTo(48, 0.01), reason: '심볼 비율이 바뀌면 앱 아이콘·스플래시와 갈라진다');
  });

  testWidgets('워드마크는 생성물의 비율을 따른다', (tester) async {
    await tester.pumpWidget(_wrap(const OnparWordmark(height: 36)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(OnparWordmark));
    expect(size.height, 36);
    expect(size.width, closeTo(36 * DsBrand.wordmarkAspect, 0.01));
  });

  testWidgets('로고는 심볼과 이름을 함께 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const OnparLogo(symbolHeight: 80)));
    await tester.pumpAndSettle();
    expect(find.byType(OnparSymbol), findsOneWidget);
    expect(find.byType(OnparWordmark), findsOneWidget);
  });

  testWidgets('로고의 이름은 한 번만 읽힌다', (tester) async {
    await tester.pumpWidget(_wrap(const OnparLogo(symbolHeight: 64)));
    await tester.pumpAndSettle();
    // 심볼과 워드마크가 각자 이름을 읽으면 스크린리더가 "온파 온파" 로 읽는다.
    expect(find.bySemanticsLabel('온파'), findsOneWidget);
  });

  testWidgets('가로 배치도 같은 부품을 쓴다', (tester) async {
    await tester.pumpWidget(_wrap(
      const OnparLogo(layout: OnparLogoLayout.inline, symbolHeight: 28),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Row), findsWidgets);
    final symbol = tester.getSize(find.byType(OnparSymbol));
    expect(symbol.height, 28);
  });

  testWidgets('색을 넘기지 않으면 브랜드 색을 따른다', (tester) async {
    await tester.pumpWidget(_wrap(const OnparSymbol(height: 40)));
    await tester.pumpAndSettle();
    // 도형이 currentColor 로 그려지므로, 색을 안 넘겼을 때 테마를 못 읽으면 여기서 터진다.
    expect(tester.takeException(), isNull);
  });

  test('생성물이 비어 있지 않다', () {
    expect(DsBrand.symbol, contains('currentColor'));
    expect(DsBrand.wordmark, contains('currentColor'));
    expect(DsBrand.symbolAspect, closeTo(0.5, 0.0001));
  });
}
