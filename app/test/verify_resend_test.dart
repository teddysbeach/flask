import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/data/auth_repository.dart';
import 'package:onpar/features/auth/verify_screen.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

/// 인증 화면의 재전송.
///
/// 여기서 지키는 것은 두 가지다.
///   1. 들어오자마자 다시 보낼 수 없다 — 가입 때 이미 한 통 나갔고, 두 통이 연달아 가면
///      사용자는 어느 링크가 살아 있는지 모른다.
///   2. 메일 화면은 메일을, 문자 화면은 문자를 다시 보낸다. 한쪽 API 로 둘 다 부르면
///      메일을 기다리는 사람에게 문자 발송이 나간다.
class _FakeAuth implements AuthRepository {
  final resentEmails = <String>[];
  final sentOtps = <String>[];

  @override
  Future<void> resendEmailVerification(String email) async => resentEmails.add(email);

  @override
  Future<void> sendPhoneOtp(String phone) async => sentOtps.add(phone);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 는 이 테스트에서 부르면 안 된다');
}

Widget _wrap(Widget child, _FakeAuth auth) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(theme: dsThemeData(Brightness.light), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('메일 인증: 들어오자마자는 못 보내고, 쿨다운이 끝나면 메일을 다시 보낸다', (tester) async {
    final auth = _FakeAuth();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      const VerifyScreen(mode: VerifyMode.email, target: 'a@b.com'),
      auth,
    ));
    await tester.pump();

    // 들어오자마자는 잠겨 있고, 남은 초가 글자로 보인다.
    expect(find.textContaining('메일을 다시 보낼 수 있어요'), findsOneWidget);
    final button = find.widgetWithText(TextButton, '다시 보내기');
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(auth.resentEmails, isEmpty, reason: '화면에 들어온 것만으로 메일이 또 나가면 안 된다');

    // 쿨다운이 끝나면 열린다.
    await tester.pump(VerifyScreen.resendCooldown + const Duration(seconds: 1));
    expect(find.text('메일이 안 왔나요?'), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pump();

    expect(auth.resentEmails, ['a@b.com']);
    expect(auth.sentOtps, isEmpty, reason: '메일 화면에서 문자를 보내면 안 된다');

    // 다시 잠긴다. 연타로 메일함을 채우지 않는다.
    expect(tester.widget<TextButton>(button).onPressed, isNull);

    await tester.pumpWidget(const SizedBox()); // 타이머 정리
  });

  testWidgets('문자 인증: 아직 안 보낸 상태로 들어오면 바로 한 번 보낸다', (tester) async {
    final auth = _FakeAuth();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      const VerifyScreen(
        mode: VerifyMode.phone,
        target: '01012345678',
        codeAlreadySent: false,
      ),
      auth,
    ));
    await tester.pump();
    await tester.pump();

    expect(auth.sentOtps, ['01012345678']);
    expect(auth.resentEmails, isEmpty, reason: '문자 화면에서 메일을 보내면 안 된다');

    await tester.pumpWidget(const SizedBox());
  });
}
