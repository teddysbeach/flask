import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/analytics.dart';
import 'package:onpar/core/analytics_observer.dart';

class _Spy implements Analytics {
  final screens = <String>[];
  @override
  void screen(String name) => screens.add(name);
  @override
  void track(AnalyticsEvent event, {Map<String, Object?> props = const {}}) {}
  @override
  void identify(String? userId) {}
}

void main() {
  test('화면 이름에서 식별자를 뺀다 — 분석 도구에 학습지 id 가 쌓이면 안 된다', () {
    final spy = _Spy();
    final obs = AnalyticsRouteObserver(spy);

    obs.didPush(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: '/worksheet/8f14e45f-ceea-467a-9f2a-1b2c3d4e5f60'),
        pageBuilder: (_, __, ___) => const SizedBox(),
      ),
      null,
    );

    expect(spy.screens.single, '/worksheet/:id');
  });

  test('평범한 경로는 그대로 둔다', () {
    final spy = _Spy();
    final obs = AnalyticsRouteObserver(spy);
    for (final p in ['/home', '/settings/account', '/paywall']) {
      obs.didPush(
        PageRouteBuilder<void>(
          settings: RouteSettings(name: p),
          pageBuilder: (_, __, ___) => const SizedBox(),
        ),
        null,
      );
    }
    expect(spy.screens, ['/home', '/settings/account', '/paywall']);
  });

  test('이름 없는 경로는 무시한다', () {
    final spy = _Spy();
    final obs = AnalyticsRouteObserver(spy);
    obs.didPush(
      PageRouteBuilder<void>(pageBuilder: (_, __, ___) => const SizedBox()),
      null,
    );
    expect(spy.screens, isEmpty);
  });

  test('분석 속성에서 개인정보 키는 통째로 빠진다', () {
    final out = sanitizeProps({
      'email': 'a@b.com',
      'nickname': '파르',
      'access_token': 'eyJhbGciOi...',
      'sheets': 10,
      'note': '문의: user@example.com 로 연락 주세요',
    });
    expect(out.containsKey('email'), isFalse);
    expect(out.containsKey('nickname'), isFalse);
    expect(out.containsKey('access_token'), isFalse);
    expect(out['sheets'], 10);
    // 남는 문자열도 한 번 더 가린다
    expect(out['note'], isNot(contains('user@example.com')));
  });
}
