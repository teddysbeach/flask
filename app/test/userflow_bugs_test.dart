import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/boot_redirect.dart';
import 'package:onpar/core/notifications.dart';
import 'package:onpar/core/routes.dart';
import 'package:onpar/core/version_gate.dart';
import 'package:onpar/data/device_reset.dart';
import 'package:onpar/data/offline_store.dart';
import 'package:onpar/data/review_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:onpar/features/consent/consent_screen.dart';
import 'package:onpar/features/library/library_screen.dart';
import 'package:onpar/features/review/review_providers.dart';
import 'package:onpar/features/review/review_session_screen.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onpar/features/notifications/notification_prefs.dart';

/// 사용자 흐름을 따라가며 잡은 버그들의 재발 방지선.
///
/// 이 파일의 테스트는 전부 "예전에 실제로 이렇게 틀렸다" 에서 왔다.
/// 그래서 각 테스트의 이름은 기능이 아니라 **틀렸던 방식**을 적는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('문의하기', () {
    test('로그인 없이 들어갈 수 있다', () {
      // 문의는 로그인 못 하는 사람이 가장 많이 쓴다(로그인이 안 돼서 문의한다).
      // 여기가 막히면 그 사람에게 남는 길은 앱을 지우는 것뿐이다.
      expect(Routes.isPublic(Routes.contact), isTrue);
      expect(Routes.isPublic(Routes.support), isTrue);
      expect(Routes.isPublic(Routes.faq), isTrue);
    });

    test('로그인이 필요한 곳은 그대로 막힌다', () {
      for (final p in [Routes.home, Routes.library, Routes.create, Routes.paywall]) {
        expect(Routes.isPublic(p), isFalse, reason: '$p 는 세션이 있어야 한다');
      }
    });
  });

  group('학습지 만들기 → 진행 화면', () {
    test('진행 화면은 라우터가 아는 경로다', () {
      // Navigator 로 직접 얹으면 완성 뒤 pushReplacement 가 학습지를 진행 화면 아래에 깐다.
      expect(Routes.createProgress('abc'), '/create/progress/abc');
      expect(Routes.createProgress('abc').startsWith('${Routes.create}/'), isTrue);
    });
  });

  group('약관 버전', () {
    ConsentRecord at(String version) => ConsentRecord(
          terms: true, privacy: true, marketing: false,
          agreedAt: DateTime(2026), version: version,
        );

    test('옛 버전에 동의한 기록은 지금 동의가 아니다', () {
      expect(at(ConsentRecord.currentVersion).isCurrent, isTrue);
      expect(at('0').isCurrent, isFalse);
    });

    test('필수 항목을 안 받은 기록은 버전이 맞아도 아니다', () {
      final partial = ConsentRecord(
        terms: true, privacy: false, marketing: false,
        agreedAt: DateTime(2026), version: ConsentRecord.currentVersion,
      );
      expect(partial.isCurrent, isFalse);
    });

    test('동의 화면과 판정이 같은 버전을 본다', () {
      expect(ConsentScreen.version, ConsentRecord.currentVersion);
    });

    test('약관이 바뀌면 로그인한 사람도 동의 화면으로 간다', () {
      final decision = bootRedirect(const BootInput(
        location: Routes.home,
        configured: true,
        gate: AppGate.pass,
        onboarded: true,
        consented: false, // 옛 버전 동의 = 동의 안 한 것으로 판정된다
        signedIn: true,
      ));
      expect(decision.redirect, Routes.consent);
    });
  });

  group('스토어 주소', () {
    test('스토어가 아닌 주소는 열지 않는다', () {
      for (final bad in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'https://example.com/onpar',
        'https://play.google.com.evil.example/store',
        'onpar://home',
        '한글',
        '',
      ]) {
        expect(AppGate.safeStoreUrl(bad), isNull, reason: '$bad 는 걸러야 한다');
      }
      expect(AppGate.safeStoreUrl(null), isNull);
      expect(AppGate.safeStoreUrl(42), isNull);
    });

    test('진짜 스토어 주소는 통과한다', () {
      for (final ok in [
        'https://apps.apple.com/kr/app/id123456789',
        'https://play.google.com/store/apps/details?id=me.popol.onpar',
        'itms-apps://itunes.apple.com/app/id123456789',
        'market://details?id=me.popol.onpar',
      ]) {
        expect(AppGate.safeStoreUrl(ok), isNotNull, reason: '$ok 는 열려야 한다');
      }
    });

    test('서버가 이상한 주소를 줘도 관문 판정 자체는 살아 있다', () {
      final gate = AppGate.fromJson(
        {'min_build': '99', 'store_url': 'javascript:alert(1)'},
        '1',
      );
      expect(gate.decision, GateDecision.forceUpdate);
      expect(gate.storeUrl, isNull, reason: '주소만 버린다 — 업데이트 안내는 그대로 나간다');
    });
  });

  group('로그아웃', () {
    test('기기에 남는 흔적 세 가지를 모두 지운다', () async {
      SharedPreferences.setMockInitialValues({});
      final offline = _FakeOffline();
      final notifications = _FakeNotifications();
      final prefs = NotificationPrefs(await SharedPreferences.getInstance());

      await DeviceReset(
        offline: offline,
        notifications: notifications,
        prefs: () async => prefs,
      ).wipe();

      expect(offline.cleared, isTrue, reason: '오프라인 학습지가 남으면 다음 사람이 본다');
      expect(notifications.cancelled, isTrue,
          reason: '예약된 알림은 앱 밖이라, 안 걷으면 로그아웃 뒤에도 남의 학습지 제목이 뜬다');
    });

    test('하나가 실패해도 나머지는 지운다', () async {
      SharedPreferences.setMockInitialValues({});
      final notifications = _FakeNotifications();
      await DeviceReset(
        offline: _ThrowingOffline(),
        notifications: notifications,
        prefs: () async => NotificationPrefs(await SharedPreferences.getInstance()),
      ).wipe();

      // 앞 단계가 던졌다고 알림이 남으면, 실패가 흔적을 지키는 셈이 된다.
      expect(notifications.cancelled, isTrue);
    });
  });

  group('화면 이동', () {
    test('화면을 라우터 밖으로 얹는 코드가 없다', () {
      // go_router 의 pushReplacement 는 **라우터의 스택**을 갈아치운다.
      // Navigator 로 직접 얹은 화면은 그 위에 떠 있어서, 갈아치운 화면이 아래에 깔린다.
      // 그러면 사용자는 바뀐 줄 알았던 화면에서 못 빠져나온다.
      final offenders = <String>[];
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final code = f.readAsLinesSync();
        for (var i = 0; i < code.length; i++) {
          final line = code[i];
          if (line.trimLeft().startsWith('///') || line.trimLeft().startsWith('//')) continue;
          if (line.contains('MaterialPageRoute') || line.contains('CupertinoPageRoute')) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '라우터를 거치지 않는 이동: $offenders');
    });
  });

  group('서재 필터', () {
    WorksheetSummary sheet(String id, WorksheetStatus status) => WorksheetSummary(
          id: id,
          topic: '주제 $id',
          status: status,
          createdAt: DateTime(2026, 1, 1).subtract(Duration(minutes: int.parse(id))),
        );

    testWidgets('걸러진 목록이 화면을 못 채우면 스스로 다음 장을 불러온다', (tester) async {
      // 예전 버그: 필터가 화면 쪽 필터라 20장 중 1장만 남으면 스크롤이 안 생기고,
      // 스크롤이 없으면 다음 페이지 요청이 영영 안 나간다 —
      // 사용자는 "실패한 학습지가 1장뿐" 이라고 읽지만 사실은 더 있다.
      final page1 = [
        sheet('1', WorksheetStatus.failed),
        for (var i = 2; i <= 20; i++) sheet('$i', WorksheetStatus.ready),
      ];
      final page2 = [
        sheet('21', WorksheetStatus.failed),
        for (var i = 22; i <= 41; i++) sheet('$i', WorksheetStatus.ready),
      ];
      final repo = _FakeWorksheets([page1, page2, const []]);

      await tester.pumpWidget(ProviderScope(
        overrides: [worksheetRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: dsThemeData(Brightness.light),
          home: const LibraryScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // '실패' 는 칩에도 타일 배지에도 있다. 칩을 콕 집는다.
      await tester.tap(find.widgetWithText(FilterChip, '실패'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.calls, greaterThan(1), reason: '화면이 안 찼으면 더 불러와야 한다');
      expect(find.text('주제 21'), findsOneWidget, reason: '다음 장의 실패 학습지도 보여야 한다');
    });
  });

  group('복습 세션', () {
    ReviewItem item(String id, String q) => ReviewItem(
          scheduleId: id,
          quizItemId: 'q$id',
          worksheetId: 'w1',
          question: q,
          answer: '답$id',
          explanation: '',
          dueAt: DateTime(2026),
          repetition: 0,
        );

    Widget wrap(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: dsThemeData(Brightness.light),
            home: const ReviewSessionScreen(),
          ),
        );

    testWidgets('답한 문제가 큐에서 빠져도 다음 문제를 건너뛰지 않는다', (tester) async {
      // 예전 버그: 서버 큐를 그대로 보면서 _index 를 1 늘렸다.
      // 큐가 [1,2,3] → [2,3] 으로 줄어든 상태에서 index 1 은 3번을 가리킨다.
      final answers = <String>[];
      final remaining = [item('1', '첫째 문제'), item('2', '둘째 문제'), item('3', '셋째 문제')];
      final repo = _FakeReviews(onAnswer: (id) {
        answers.add(id);
        remaining.removeWhere((e) => e.scheduleId == id);
      });

      final container = ProviderContainer(overrides: [
        reviewRepositoryProvider.overrideWithValue(repo),
        dueReviewsProvider.overrideWith((ref) async => List.of(remaining)),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsThemeData(Brightness.light),
          home: const ReviewSessionScreen(),
        ),
      ));
      await tester.pump();

      expect(find.text('첫째 문제'), findsOneWidget);
      await tester.tap(find.text('떠올렸어요'));
      await tester.pump();
      await tester.tap(find.text('보통'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 서버 큐가 줄어든 채로 다시 불려도(다른 화면이 invalidate 했다고 치자)
      // 이번 세션의 순서는 흔들리지 않는다.
      container.invalidate(dueReviewsProvider);
      await container.read(dueReviewsProvider.future); // 새 값이 실제로 도착할 때까지 기다린다
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(answers, ['1']);
      expect(
        container.read(dueReviewsProvider).valueOrNull?.map((e) => e.scheduleId),
        ['2', '3'],
        reason: '서버 큐는 실제로 줄어든 상태여야 이 테스트가 의미가 있다',
      );
      expect(find.text('둘째 문제'), findsOneWidget, reason: '셋째로 건너뛰면 둘째는 영영 안 나온다');
      expect(find.text('셋째 문제'), findsNothing);
    });

    testWidgets('"모르겠음" 은 떠올린 것으로 세지 않는다', (tester) async {
      final repo = _FakeReviews(onAnswer: (_) {});
      await tester.pumpWidget(wrap([
        reviewRepositoryProvider.overrideWithValue(repo),
        dueReviewsProvider.overrideWith((ref) async => [item('1', '하나뿐인 문제')]),
      ]));
      await tester.pump();

      await tester.tap(find.text('떠올렸어요'));
      await tester.pump();
      await tester.tap(find.text('모르겠음'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('오늘 1개를 복습했어요'), findsOneWidget);
      expect(find.textContaining('그중 0개를 떠올렸어요'), findsOneWidget,
          reason: '하나도 못 떠올린 사람에게 "1개를 떠올렸어요" 라고 하면 그 숫자는 거짓말이 된다');
    });
  });
}

class _FakeWorksheets implements WorksheetRepository {
  _FakeWorksheets(this.pages);

  /// 페이지별로 돌려줄 목록. 커서가 오면 다음 페이지를 준다.
  final List<List<WorksheetSummary>> pages;
  int calls = 0;

  @override
  Future<List<WorksheetSummary>> list({DateTime? before}) async {
    final page = calls < pages.length ? pages[calls] : const <WorksheetSummary>[];
    calls += 1;
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeOffline implements OfflineStore {
  bool cleared = false;

  @override
  Future<void> clearAll() async => cleared = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ThrowingOffline implements OfflineStore {
  @override
  Future<void> clearAll() async => throw StateError('디스크가 꽉 찼다');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeNotifications implements NotificationService {
  bool cancelled = false;

  @override
  Future<void> cancelReviewNotifications() async => cancelled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeReviews implements ReviewRepository {
  _FakeReviews({required this.onAnswer});

  final void Function(String scheduleId) onAnswer;

  @override
  Future<void> answer({required String scheduleId, required int grade}) async =>
      onAnswer(scheduleId);

  @override
  Future<List<ReviewItem>> upcoming({int limit = 60}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
