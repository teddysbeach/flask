import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/app.dart';
import 'package:onpar/core/bootstrap.dart';
import 'package:onpar/core/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱이 실제로 뜨는지. 라우터·테마·부팅 판정이 한 번이라도 같이 돌아본 적 없으면
/// "각 조각은 통과하는데 켜면 검은 화면" 이 된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('설정이 없으면 죽지 않고 관문 화면을 보여준다', (tester) async {
    // Env.isConfigured 는 --dart-define 이 없으면 false 다. 테스트가 곧 그 상황이다.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith((_) => prefs),
          // 알림 서비스는 플랫폼 채널을 쓴다. 부팅 경로만 보려는 것이므로 가짜로 둔다.
          notificationServiceProvider.overrideWithValue(_SilentNotifications()),
        ],
        child: const OnparApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull, reason: '앱이 켜지자마자 죽었다');
    expect(find.byType(MaterialApp), findsOneWidget);
    // 설정이 없으면 어디로 가든 빈 화면이면 안 된다 — 무언가는 말해 줘야 한다.
    expect(find.byType(Scaffold), findsWidgets);
  });
}

class _SilentNotifications implements NotificationService {
  @override
  Stream<String> get onOpenRoute => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
