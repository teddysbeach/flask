import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/analytics.dart';
import 'package:onpar/core/bootstrap.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:onpar/data/profile_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/consent/consent_screen.dart';
import 'package:onpar/features/create/create_screen.dart';
import 'package:onpar/ui/widgets/feedback.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 분석 배선 테스트.
///
/// 여기서 지키는 것은 "이벤트가 나가는가" 가 아니다. 그건 SDK 를 붙이면 알 수 있다.
/// 지키는 것은 **무엇이 실려 나가는가** 다 — 한 번 새어 나간 개인정보는 되돌릴 수 없고,
/// 분석 도구에 쌓인 뒤에는 우리가 지울 수도 없다.
///
///   1. 주제 원문이 아니라 길이가 실린다.
///   2. 어떤 이벤트의 props 에도 개인정보로 보이는 키가 없다(= sanitizeProps 를 통과해도 그대로다).
///   3. 화면 조회는 라우터만 기록한다 — 화면이 screen() 을 또 부르지 않는다.
class _RecordingAnalytics implements Analytics {
  final events = <(AnalyticsEvent, Map<String, Object?>)>[];
  final screens = <String>[];

  @override
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) =>
      // **일부러 sanitize 하지 않고 그대로 담는다.** 어댑터가 가려 주는 것과
      // 부르는 쪽이 애초에 안 싣는 것은 다르다 — 여기서 보려는 건 후자다.
      events.add((event, Map<String, Object?>.of(props)));

  @override
  void screen(String name) => screens.add(name);

  @override
  void identify(String? userId) {}

  Map<String, Object?>? propsOf(AnalyticsEvent e) {
    for (final r in events) {
      if (r.$1 == e) return r.$2;
    }
    return null;
  }
}

/// 서버를 부르지 않는 학습지 리포지터리.
class _FakeWorksheets implements WorksheetRepository {
  String? lastTopic;

  @override
  Future<CreateResult> create({
    required String topic,
    required String level,
    bool force = false,
  }) async {
    lastTopic = topic;
    return const CreateAccepted('ws-0001');
  }

  @override
  Stream<WorksheetSummary> watch(String id) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Profile _profile() => const Profile(
      id: 'u-1',
      quotaTotal: 3,
      quotaUsed: 1,
      locale: 'ko',
      reviewHour: 21,
      timezone: 'Asia/Seoul',
    );

Widget _wrap(Widget child, {required List<Override> overrides}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: dsThemeData(Brightness.light), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('학습지 만들기: 주제 원문이 아니라 길이가 실린다', (tester) async {
    final analytics = _RecordingAnalytics();
    final worksheets = _FakeWorksheets();
    const topic = '광합성의 명반응과 암반응';

    // ListView 는 화면 밖 자식을 아예 만들지 않는다. 창을 크게 잡아 버튼까지 그린다.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      const CreateScreen(),
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        worksheetRepositoryProvider.overrideWithValue(worksheets),
        profileProvider.overrideWith((ref) async => _profile()),
      ],
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), topic);
    await tester.pump();
    // AppBar 제목과 버튼 글자가 같다. 타입으로 집는다.
    await tester.tap(find.byType(OnceButton));
    await tester.pump();
    await tester.pump();

    // 진행 화면의 타이머가 남지 않게 트리를 내린다.
    await tester.pumpWidget(const SizedBox());

    final props = analytics.propsOf(AnalyticsEvent.worksheetCreateStart);
    expect(props, isNotNull, reason: '제출했는데 worksheetCreateStart 가 안 나갔다');
    expect(worksheets.lastTopic, topic, reason: '서버에는 주제가 그대로 가야 한다');

    // 길이는 실리고, 원문은 어디에도 없다.
    expect(props!['topic_length'], topic.runes.length);
    expect(props['level'], 'beginner');
    expect(props.values.whereType<String>(), isNot(contains(topic)));
    expect(props.keys, isNot(contains('topic')));
    for (final v in props.values) {
      expect('$v', isNot(contains('광합성')), reason: '주제 원문이 props 어딘가에 실렸다');
    }
  });

  testWidgets('약관 동의: 동의 여부와 버전만 실린다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final analytics = _RecordingAnalytics();

    await tester.pumpWidget(_wrap(
      ConsentScreen(onDone: () {}),
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        sharedPrefsProvider.overrideWith((_) => prefs),
      ],
    ));
    await tester.pump();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('동의하고 시작하기'));
    await tester.pump();
    await tester.pump();

    final props = analytics.propsOf(AnalyticsEvent.consentAccept);
    expect(props, isNotNull, reason: '동의했는데 consentAccept 가 안 나갔다');
    expect(props!['version'], ConsentScreen.version);
    expect(props['marketing'], isTrue);
  });

  testWidgets('화면이 기록한 props 는 sanitizeProps 를 통과해도 그대로다', (tester) async {
    // 통과해도 그대로라는 것은 = 가릴 것이 애초에 없었다는 뜻이다.
    // 어댑터가 가려 주니까 괜찮다고 두면, 어댑터를 갈아끼우는 날 그대로 새어 나간다.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final analytics = _RecordingAnalytics();

    await tester.pumpWidget(_wrap(
      ConsentScreen(onDone: () {}),
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        sharedPrefsProvider.overrideWith((_) => prefs),
      ],
    ));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('동의하고 시작하기'));
    await tester.pump();
    await tester.pump();

    expect(analytics.events, isNotEmpty);
    for (final (event, props) in analytics.events) {
      expect(sanitizeProps(props), props,
          reason: '${event.name} 의 props 가 sanitizeProps 에서 걸렸다 — 개인정보가 실렸다는 뜻이다');
    }
  });

  testWidgets('화면은 screen() 을 부르지 않는다 — 화면 조회는 라우터가 잡는다', (tester) async {
    final analytics = _RecordingAnalytics();
    await tester.pumpWidget(_wrap(
      const CreateScreen(),
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        worksheetRepositoryProvider.overrideWithValue(_FakeWorksheets()),
        profileProvider.overrideWith((ref) async => _profile()),
      ],
    ));
    await tester.pump();

    expect(analytics.screens, isEmpty);
    expect(analytics.events.map((e) => e.$1), isNot(contains(AnalyticsEvent.screenView)));
  });

  group('배선 전체 훑기 (소스 검사)', () {
    // 위젯 테스트로 모든 호출 지점을 띄울 수는 없다(결제 스트림, 탈퇴, 소셜 로그인…).
    // 그 자리들까지 규칙을 지키게 하려면 소스를 한 번 훑는 수밖에 없다.
    // 규칙이 깨진 자리를 배포 뒤에 발견하면 이미 늦는다.

    /// analytics.dart 의 차단 목록과 같은 값. 여기에도 적어 두는 이유는
    /// 그 목록이 줄었을 때 이 테스트가 조용히 약해지지 않게 하려는 것이다.
    const blocked = [
      'email', 'phone', 'password', 'token', 'access_token', 'refresh_token',
      'name', 'nickname', 'address', 'birth', 'receipt',
      // 목록에는 없지만 이 앱에서 실리면 안 되는 것들.
      'topic', 'body', 'message', 'detail', 'title', 'question', 'answer', 'display_name',
    ];

    List<File> dartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    /// `track(` 한 번의 인자 전체(괄호 균형)를 잘라 낸다.
    List<String> trackCalls(String src) {
      final out = <String>[];
      for (var i = src.indexOf('.track('); i >= 0; i = src.indexOf('.track(', i + 1)) {
        var depth = 0;
        final start = src.indexOf('(', i);
        for (var j = start; j < src.length; j++) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') depth--;
          if (depth == 0) {
            out.add(src.substring(start, j + 1));
            break;
          }
        }
      }
      return out;
    }

    test('어떤 track 호출에도 개인정보로 보이는 키가 없다', () {
      final offenders = <String>[];
      for (final f in dartFiles()) {
        for (final call in trackCalls(f.readAsStringSync())) {
          for (final key in blocked) {
            if (call.contains("'$key':") || call.contains('"$key":')) {
              offenders.add('${f.path}: $key');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: '분석 이벤트에 개인정보로 보이는 키가 실렸다');
    });

    test('화면은 analytics.screen() 을 부르지 않는다', () {
      final offenders = dartFiles()
          .where((f) => !f.path.contains('analytics_observer.dart'))
          .where((f) => !f.path.endsWith('core/analytics.dart'))
          .where((f) => f.readAsStringSync().contains('.screen('))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty,
          reason: '화면이 screen() 을 또 불렀다 — 라우터가 이미 잡고 있어서 두 번 세어진다');
    });
  });
}
