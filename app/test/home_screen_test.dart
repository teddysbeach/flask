import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/bootstrap.dart';
import 'package:onpar/data/profile_repository.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/home/home_screen.dart';
import 'package:onpar/features/review/review_providers.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 홈은 앱을 열면 처음 보이는 곳이라, 여기가 비면 앱이 빈 것처럼 보인다.
/// 섹션이 **조건대로 나타나고 사라지는지**를 잰다 — 특히 "없을 때 자리를 안 차지하는지".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WorksheetSummary sheet(String id, {WorksheetStatus s = WorksheetStatus.ready, int daysAgo = 0}) =>
      WorksheetSummary(
        id: id,
        topic: '주제 $id',
        title: '학습지 $id',
        status: s,
        createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      );

  Profile profile(int remaining) => Profile(
        id: 'u1',
        quotaTotal: remaining,
        quotaUsed: 0,
        locale: 'ko',
        reviewHour: 21,
        timezone: 'Asia/Seoul',
      );

  Future<void> pumpHome(
    WidgetTester tester, {
    required List<WorksheetSummary> items,
    int dueReviews = 0,
    int quota = 3,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith((_) => prefs),
        worksheetRepositoryProvider.overrideWithValue(_FakeWorksheets(items)),
        profileProvider.overrideWith((_) async => profile(quota)),
        dueReviewCountProvider.overrideWith((_) async => dueReviews),
      ],
      child: MaterialApp(
        theme: dsThemeData(Brightness.light),
        home: const HomeScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400)); // 등장 모션이 끝나기를 기다린다
  }

  testWidgets('만든 학습지가 전부 보인다', (tester) async {
    // 예전 홈은 최근 세 장만 보여줬다. 그래서 네 번째부터는 홈에서 사라졌다.
    await pumpHome(tester, items: [
      for (var i = 1; i <= 6; i++) sheet('$i'),
    ]);

    // 목록은 게으르게 그려지므로 화면 밖의 것은 스크롤해서 확인한다.
    for (var i = 1; i <= 6; i++) {
      await tester.scrollUntilVisible(find.text('학습지 $i'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('학습지 $i'), findsOneWidget, reason: '$i번째 학습지가 홈에 없다');
    }
  });

  testWidgets('날짜로 묶여서 나온다', (tester) async {
    await pumpHome(tester, items: [
      sheet('a'),
      sheet('b', daysAgo: 1),
      sheet('c', daysAgo: 3),
    ]);

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('어제'), findsOneWidget);
    expect(find.text('지난 7일'), findsOneWidget);
  });

  testWidgets('복습이 없는 날은 복습 카드가 자리를 차지하지 않는다', (tester) async {
    // "오늘은 복습이 없어요" 카드는 아무 일도 안 하면서 홈을 한 칸 밀어낸다.
    await pumpHome(tester, items: [sheet('a')], dueReviews: 0);
    expect(find.textContaining('오늘의 복습'), findsNothing);
  });

  testWidgets('복습이 있으면 맨 위에 뜬다', (tester) async {
    await pumpHome(tester, items: [sheet('a')], dueReviews: 4);
    expect(find.text('오늘의 복습 4개'), findsOneWidget);
  });

  testWidgets('만드는 중인 학습지는 목록 위로 올라온다', (tester) async {
    // 기다리는 사람에게는 이게 홈의 전부다. 스크롤해서 찾게 만들 이유가 없다.
    await pumpHome(tester, items: [
      sheet('done'),
      sheet('making', s: WorksheetStatus.generating),
    ]);

    // '만드는 중' 은 위의 카드와 타일의 상태 배지 두 곳에 나온다. 위의 것만 본다.
    final labels = tester.widgetList<Text>(find.text('만드는 중'));
    expect(labels.length, greaterThanOrEqualTo(1));

    final making = tester.getTopLeft(find.text('만드는 중').first).dy;
    final firstTile = tester.getTopLeft(find.text('학습지 done')).dy;
    expect(making, lessThan(firstTile), reason: '만드는 중이 목록보다 아래에 있다');
  });

  testWidgets('남은 장수와 만들기는 언제나 있다', (tester) async {
    await pumpHome(tester, items: const [], quota: 0);
    expect(find.text('남은 학습지'), findsOneWidget);
    expect(find.text('0장'), findsOneWidget);
    expect(find.text('새 학습지 만들기'), findsOneWidget);
    // 한 장도 없을 때는 목록 자리에서 그렇게 말해 준다.
    expect(find.text('아직 만든 학습지가 없어요'), findsOneWidget);
  });
}

class _FakeWorksheets implements WorksheetRepository {
  _FakeWorksheets(this.items);
  final List<WorksheetSummary> items;

  @override
  Future<List<WorksheetSummary>> list({DateTime? before}) async =>
      before == null ? items : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
