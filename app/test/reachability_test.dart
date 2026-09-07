import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/env.dart';
import 'package:onpar/core/routes.dart';

/// **들어갈 수 없는 화면**과 **눌러도 아무 일이 없는 버튼**을 잡는다.
///
/// 이 저장소에서 이미 세 번 났다: /notices, /notifications, 그리고 Google 로그인.
/// 셋 다 코드는 멀쩡하고 테스트도 통과했다 — 다만 **아무도 그리로 갈 수 없었다.**
/// 화면 하나를 만들고 연결을 잊는 것은 눈으로 잡히지 않는 종류의 실수라, 값으로 잰다.
void main() {
  final lib = Directory('lib');
  final sources = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (path: f.path, text: f.readAsStringSync()))
      .toList();

  String allExcept(String pathFragment) => sources
      .where((s) => !s.path.contains(pathFragment))
      .map((s) => s.text)
      .join('\n');

  group('모든 화면에 들어갈 길이 있다', () {
    /// 라우터에 등록만 하고 아무도 안 보내는 경로. 리다이렉트·셸이 맡는 것은 뺀다.
    const reachedByRouter = {
      Routes.splash,        // 앱이 여기서 시작한다
      Routes.gate,          // 부팅 판정이 보낸다
      Routes.onboarding,    // 부팅 판정이 보낸다
      Routes.consent,       // 부팅 판정이 보낸다
      Routes.login,         // 부팅 판정이 보낸다
      Routes.resetPassword, // 비밀번호 재설정 메일의 링크로만 들어온다
      Routes.home,          // 탭
      Routes.library,       // 탭
      Routes.reviewTab,     // 탭
      Routes.settings,      // 탭
      Routes.worksheetPattern,
    };

    test('누르는 곳이 있는지', () {
      final registered = RegExp(r'path:\s*Routes\.(\w+)')
          .allMatches(File('lib/router.dart').readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();

      final byName = <String, String>{
        'notices': Routes.notices, 'notifications': Routes.notifications,
        'stats': Routes.stats, 'tickets': Routes.tickets,
        'contact': Routes.contact, 'faq': Routes.faq, 'support': Routes.support,
        'paywall': Routes.paywall, 'purchases': Routes.purchases,
        'profile': Routes.profile, 'accountSettings': Routes.accountSettings,
        'changePassword': Routes.changePassword, 'withdraw': Routes.withdraw,
        'terms': Routes.terms, 'privacy': Routes.privacy, 'licenses': Routes.licenses,
        'create': Routes.create, 'reviewSession': Routes.reviewSession,
        'signup': Routes.signup, 'verify': Routes.verify, 'findAccount': Routes.findAccount,
        'notificationSettings': Routes.notificationSettings,
      };

      final unreachable = <String>[];
      for (final name in registered) {
        final path = byName[name];
        if (path == null || reachedByRouter.contains(path)) continue;
        // 라우터 자신을 뺀 나머지 어딘가에서 그 경로로 보내야 한다.
        final elsewhere = allExcept('router.dart');
        if (!elsewhere.contains('Routes.$name')) unreachable.add(name);
      }
      expect(unreachable, isEmpty,
          reason: '등록만 되고 아무도 안 보내는 화면: $unreachable');
    });
  });

  group('안 되는 버튼을 두지 않는다', () {
    test('Google 로그인은 설정이 있을 때만 보인다', () {
      // 클라이언트 ID 없이 iOS 의 google_sign_in 은 시작조차 못 한다.
      // 예전에는 Env 에 값이 있는데도 null 을 넘기고 있었다 — 눌러도 아무 일이 안 났다.
      final login = File('lib/features/auth/login_screen.dart').readAsStringSync();
      expect(login, contains('Env.isGoogleSignInConfigured'),
          reason: '설정이 없는 빌드에서도 Google 버튼이 뜬다');
      expect(login, contains('Env.googleIosClientIdOrNull'),
          reason: 'Env 에 값이 있는데 안 넘기고 있다');
      expect(login, isNot(contains('iosClientId: null')));

      // 값이 비어 있는 이 테스트 빌드에서는 감춰지는 것이 맞다.
      expect(Env.isGoogleSignInConfigured, isFalse);
    });

    test('빈 콜백이 없다', () {
      // 눌러도 아무 일이 안 하는 버튼. 자리만 잡고 사용자를 속인다.
      final offenders = <String>[];
      for (final s in sources) {
        for (final m in RegExp(r'on(?:Pressed|Tap|Changed):\s*\(\s*\w*\s*\)\s*\{\s*\}')
            .allMatches(s.text)) {
          offenders.add('${s.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty, reason: '빈 콜백: $offenders');
    });

    test('미뤄 둔 배선(TODO)이 남아 있지 않다', () {
      // 화면에 붙은 TODO 는 대개 "이 버튼은 아직 안 된다" 는 뜻이다.
      final offenders = <String>[];
      for (final s in sources.where((s) => s.path.contains('/features/'))) {
        if (s.text.contains('TODO')) offenders.add(s.path);
      }
      expect(offenders, isEmpty, reason: '화면에 남은 TODO: $offenders');
    });
  });
}
