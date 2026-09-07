import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/app_error.dart';
import 'package:onpar/ui/states/app_state_views.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 테마와 공용 상태 화면은 앱 전체가 쓰므로, 여기가 깨지면 모든 화면이 깨진다.
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
        theme: dsThemeData(brightness),
        home: Scaffold(body: child),
      );

  group('테마', () {
    testWidgets('라이트/다크 양쪽에서 팔레트가 붙는다', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(wrap(
          Builder(builder: (context) {
            final p = DsTheme.of(context);
            return Text('${p.brandPrimary.toARGB32()}');
          }),
          brightness: b,
        ));
        expect(find.byType(Text), findsOneWidget);
      }
    });

    testWidgets('DsTheme.of 는 확장이 없어도 라이트 팔레트로 떨어진다', (tester) async {
      // 테마 확장을 안 단 화면(테스트·미리보기)에서 죽으면 안 된다.
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => Text('${DsTheme.of(context).textPrimary.toARGB32()}')),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('상태 화면', () {
    testWidgets('로딩은 스크린리더가 읽을 수 있다', (tester) async {
      await tester.pumpWidget(wrap(const LoadingView(label: '학습지를 불러오는 중')));
      expect(find.text('학습지를 불러오는 중'), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(LoadingView));
      expect(semantics.label, contains('학습지를 불러오는 중'));
    });

    testWidgets('빈 상태는 다음 행동을 준다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyView(
        title: '아직 학습지가 없어요',
        description: '배우고 싶은 걸 하나 넣어 보세요.',
        actionLabel: '학습지 만들기',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('학습지 만들기'));
      expect(tapped, isTrue);
    });

    testWidgets('오류 화면은 서버 원문이 아니라 우리 문구를 쓴다', (tester) async {
      final err = AppError.of(AppErrorKind.server, cause: 'PostgrestException(code: 500, detail: ...)');
      await tester.pumpWidget(wrap(ErrorView(error: err, onRetry: () {})));
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.text(err.message), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('되돌릴 수 없는 실패에는 재시도를 주지 않는다', (tester) async {
      final err = AppError.of(AppErrorKind.forbidden);
      await tester.pumpWidget(wrap(ErrorView(error: err, onRetry: () {})));
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets('오프라인 배너는 내용을 가리지 않고 읽힌다', (tester) async {
      await tester.pumpWidget(wrap(const OfflineBanner()));
      expect(find.textContaining('오프라인'), findsOneWidget);
    });

    testWidgets('큰 글꼴에서도 상태 화면이 넘치지 않는다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: dsThemeData(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6), size: Size(320, 640)),
          child: const Scaffold(
            body: EmptyView(
              title: '아직 학습지가 없어요',
              description: '배우고 싶은 개념을 한 줄로 적으면 6단계 학습지를 만들어 드려요.',
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
