import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/boot_redirect.dart';
import 'package:onpar/core/routes.dart';
import 'package:onpar/core/version_gate.dart';

/// 부팅 순서가 어긋나면 사용자는 로그인했는데 온보딩을 다시 보거나,
/// 점검 중인데 홈이 열리거나, 알림을 눌렀는데 홈에 떨어진다.
void main() {
  BootInput input({
    String location = Routes.splash,
    bool configured = true,
    AppGate? gate,
    bool onboarded = true,
    bool consented = true,
    bool signedIn = true,
    String? pending,
  }) =>
      BootInput(
        location: location,
        configured: configured,
        gate: gate,
        onboarded: onboarded,
        consented: consented,
        signedIn: signedIn,
        pending: pending,
      );

  group('순서', () {
    test('설정이 없으면 무엇보다 먼저 막는다', () {
      expect(bootRedirect(input(configured: false, location: Routes.home)).redirect, Routes.gate);
      // 로그인·온보딩 상태와 무관하게
      expect(
        bootRedirect(input(configured: false, onboarded: false, signedIn: false)).redirect,
        Routes.gate,
      );
    });

    test('점검 중이면 온보딩보다 먼저 막는다', () {
      const gate = AppGate(decision: GateDecision.maintenance);
      expect(bootRedirect(input(gate: gate, onboarded: false)).redirect, Routes.gate);
    });

    test('강제 업데이트도 마찬가지', () {
      const gate = AppGate(decision: GateDecision.forceUpdate);
      expect(bootRedirect(input(gate: gate, location: Routes.home)).redirect, Routes.gate);
    });

    test('선택 업데이트는 막지 않는다', () {
      const gate = AppGate(decision: GateDecision.optionalUpdate);
      expect(bootRedirect(input(gate: gate, location: Routes.home)).redirect, isNull);
    });

    test('서버를 못 불러 gate 가 없으면 통과한다 — 우리 실수로 앱을 잠그지 않는다', () {
      expect(bootRedirect(input(gate: null, location: Routes.home)).redirect, isNull);
    });

    test('관문이 풀리면 gate 화면에 머무르지 않는다', () {
      expect(bootRedirect(input(location: Routes.gate)).redirect, Routes.splash);
    });
  });

  group('첫 실행과 약관', () {
    test('온보딩을 안 봤으면 온보딩으로', () {
      expect(bootRedirect(input(onboarded: false, location: Routes.home)).redirect, Routes.onboarding);
    });

    test('온보딩 화면에서는 그대로 둔다 (무한 리다이렉트 방지)', () {
      expect(bootRedirect(input(onboarded: false, location: Routes.onboarding)).redirect, isNull);
    });

    test('필수 약관에 동의하지 않았으면 약관으로', () {
      expect(bootRedirect(input(consented: false, location: Routes.home)).redirect, Routes.consent);
    });

    test('약관 화면에서는 그대로 둔다', () {
      expect(bootRedirect(input(consented: false, location: Routes.consent)).redirect, isNull);
    });
  });

  group('세션', () {
    test('로그아웃 상태로 보호된 곳에 가면 로그인으로 보내고 목적지를 기억한다', () {
      final target = Routes.worksheet('w-1');
      final d = bootRedirect(input(signedIn: false, location: target));
      expect(d.redirect, Routes.login);
      expect(d.holdLocation, target, reason: '목적지를 안 담으면 로그인 뒤 홈에 떨어진다');
    });

    test('로그아웃 상태여도 공개 화면은 그대로 본다', () {
      expect(bootRedirect(input(signedIn: false, location: Routes.terms)).redirect, isNull);
      expect(bootRedirect(input(signedIn: false, location: Routes.login)).redirect, isNull);
    });

    test('로그인하면 보류해 둔 목적지로 간다', () {
      final target = Routes.worksheet('w-9');
      final d = bootRedirect(input(location: Routes.login, pending: target));
      expect(d.redirect, target);
      expect(d.consumePending, isTrue, reason: '한 번 쓴 목적지는 비워야 다음에 또 끌려가지 않는다');
    });

    test('보류함이 비었으면 홈으로', () {
      final d = bootRedirect(input(location: Routes.splash));
      expect(d.redirect, Routes.home);
      expect(d.consumePending, isFalse);
    });

    test('이미 앱 안에 있으면 건드리지 않는다', () {
      expect(bootRedirect(input(location: Routes.library)).redirect, isNull);
      expect(bootRedirect(input(location: Routes.settings)).redirect, isNull);
    });

    test('로그인한 사람은 인증 화면에 머무르지 않는다', () {
      expect(bootRedirect(input(location: Routes.signup)).redirect, Routes.home);
      expect(bootRedirect(input(location: Routes.verify)).redirect, Routes.home);
    });
  });
}
