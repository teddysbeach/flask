import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/bootstrap.dart';
import 'package:onpar/core/routes.dart';
import 'package:onpar/data/notice_repository.dart';
import 'package:onpar/data/profile_repository.dart';
import 'package:onpar/data/topic_picks_repository.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/home/home_screen.dart';
import 'package:onpar/features/review/review_providers.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 홈에 새로 얹은 섹션들 — 공지·이벤트·이어서 하기·추천 주제.
///
/// 이 섹션들은 **서버가 내용을 정한다.** 그래서 잴 것이 둘이다:
/// 조건대로 나타나고 사라지는가, 그리고 **서버가 이상한 값을 줘도 안전한가.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Notice notice(String id, {bool pinned = true, NoticeKind kind = NoticeKind.notice,
          String? ctaLabel, String? ctaRoute}) =>
      Notice(
        id: id,
        title: '$id 제목',
        body: '$id 본문',
        pinned: pinned,
        publishedAt: DateTime(2026),
        kind: kind,
        ctaLabel: ctaLabel,
        ctaRoute: ctaRoute,
      );

  WorksheetSummary sheet(String id, {WorksheetStatus s = WorksheetStatus.ready}) =>
      WorksheetSummary(
        id: id,
        topic: '주제 $id',
        title: '학습지 $id',
        status: s,
        createdAt: DateTime.now(),
      );

  Future<SharedPreferences> pumpHome(
    WidgetTester tester, {
    List<WorksheetSummary> items = const [],
    List<Notice> notices = const [],
    List<TopicPick> picks = const [],
    Map<String, Object> seed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith((_) => prefs),
        worksheetRepositoryProvider.overrideWithValue(_FakeWorksheets(items)),
        profileProvider.overrideWith((_) async => const Profile(
              id: 'u1', quotaTotal: 3, quotaUsed: 0,
              locale: 'ko', reviewHour: 21, timezone: 'Asia/Seoul',
            )),
        dueReviewCountProvider.overrideWith((_) async => 0),
        noticesProvider.overrideWith((_) async => notices),
        topicPicksProvider.overrideWith((_) async => picks),
      ],
      child: MaterialApp(theme: dsThemeData(Brightness.light), home: const HomeScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    return prefs;
  }

  group('공지', () {
    testWidgets('고정 공지가 맨 위에 뜬다', (tester) async {
      await pumpHome(tester, notices: [notice('n1')]);
      expect(find.text('n1 제목'), findsOneWidget);
    });

    testWidgets('닫으면 다시 안 뜬다', (tester) async {
      final prefs = await pumpHome(tester, notices: [notice('n1')]);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('n1 제목'), findsNothing);
      // 기기에 남아야 다음 실행에서도 안 뜬다.
      expect(prefs.getStringList('home_dismissed_notices_v1'), contains('n1'));
    });

    testWidgets('닫은 적 없는 새 공지는 뜬다', (tester) async {
      // 내용이 바뀌면 새 공지이고, 새 공지는 닫은 적이 없으니 다시 떠야 한다.
      await pumpHome(tester,
          notices: [notice('n2')],
          seed: {'home_dismissed_notices_v1': ['n1']});
      expect(find.text('n2 제목'), findsOneWidget);
    });

    testWidgets('공지가 여러 개여도 하나만 뜬다', (tester) async {
      // 셋 쌓인 홈은 공지판이지 학습 앱이 아니다.
      await pumpHome(tester, notices: [notice('n1'), notice('n2'), notice('n3')]);
      expect(find.text('n1 제목'), findsOneWidget);
      expect(find.text('n2 제목'), findsNothing);
    });
  });

  group('이벤트', () {
    testWidgets('이벤트는 공지와 따로, 누를 곳과 함께 뜬다', (tester) async {
      await pumpHome(tester, notices: [
        notice('e1', kind: NoticeKind.event, ctaLabel: '보러 가기', ctaRoute: Routes.paywall),
      ]);
      expect(find.text('이벤트'), findsOneWidget);
      expect(find.text('e1 제목'), findsOneWidget);
      expect(find.text('보러 가기'), findsOneWidget);
    });

    testWidgets('이벤트가 없으면 자리도 없다', (tester) async {
      await pumpHome(tester);
      expect(find.text('이벤트'), findsNothing);
    });
  });

  group('서버가 준 경로', () {
    test('허용 목록에 없는 곳으로는 안 보낸다', () {
      // 여기가 뚫리면 공지 한 줄로 사용자를 앱 안 아무 데나 보낼 수 있다.
      for (final bad in [
        Routes.withdraw,          // 탈퇴 화면으로 보내는 배너
        '/settings/account',
        'https://example.com',
        'javascript:alert(1)',
        '/아무거나',
        '',
      ]) {
        expect(safeCtaRoute(bad), isNull, reason: '$bad 를 통과시켰다');
      }
      expect(safeCtaRoute(null), isNull);
      expect(safeCtaRoute(42), isNull);
    });

    test('홈에서 누를 만한 곳은 통과한다', () {
      for (final ok in [Routes.paywall, Routes.create, Routes.reviewSession, Routes.support]) {
        expect(safeCtaRoute(ok), ok);
      }
    });

    test('라벨과 경로는 함께 있어야 눌린다', () {
      expect(notice('e', ctaLabel: '가기', ctaRoute: null).hasAction, isFalse);
      expect(notice('e', ctaLabel: '가기', ctaRoute: Routes.paywall).hasAction, isTrue);
    });
  });

  group('이어서 하기', () {
    testWidgets('마지막으로 본 학습지로 돌아가는 길이 있다', (tester) async {
      await pumpHome(
        tester,
        items: [sheet('new'), sheet('old')],
        seed: {'home_last_opened_v1': 'old'},
      );
      expect(find.text('이어서 하기'), findsOneWidget);
      expect(find.text('학습지 old'), findsWidgets);
    });

    testWidgets('목록 맨 위에 있는 장은 두 번 보여주지 않는다', (tester) async {
      await pumpHome(
        tester,
        items: [sheet('new'), sheet('old')],
        seed: {'home_last_opened_v1': 'new'},
      );
      expect(find.text('이어서 하기'), findsNothing);
    });

    testWidgets('지운 학습지면 조용히 없던 일로 한다', (tester) async {
      await pumpHome(
        tester,
        items: [sheet('a')],
        seed: {'home_last_opened_v1': 'deleted-id'},
      );
      expect(find.text('이어서 하기'), findsNothing);
    });
  });

  group('추천 주제', () {
    testWidgets('서버가 안 주면 섹션이 없다', (tester) async {
      // 추천은 곁가지라 못 받아도 오류를 낼 자격이 없다. 조용히 사라진다.
      await pumpHome(tester);
      expect(find.text('이런 주제는 어때요'), findsNothing);
    });

    testWidgets('서버가 주면 분야와 함께 보인다', (tester) async {
      await pumpHome(tester, picks: [
        const TopicPick(id: 'p1', topic: '복리가 무서운 이유', category: '경제·금융'),
      ]);
      expect(find.text('이런 주제는 어때요'), findsOneWidget);
      expect(find.text('복리가 무서운 이유'), findsOneWidget);
      expect(find.text('경제·금융'), findsOneWidget);
    });
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
