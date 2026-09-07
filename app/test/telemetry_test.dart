import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/analytics.dart';
import 'package:onpar/data/telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 분석·크래시가 실제로 나가는가, 그리고 **무엇이 나가지 않는가**.
///
/// 예전에는 릴리스에서 아무것도 안 나갔다(DebugAnalytics 만 꽂혀 있었다). 출시 후 지표를
/// 잴 수단이 없었고 크래시도 안 보였다. 이제 나가는 만큼, 나가면 안 되는 것을 지켜야 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Telemetry make(SharedPreferences prefs) => Telemetry(
        // 전송은 Env.isConfigured 가 false 라 시도되지 않는다(테스트에서는 dart-define 이 없다).
        // 여기서 보는 것은 "무엇을 큐에 담는가" 다.
        client: SupabaseClient('https://example.invalid', 'anon'),
        prefs: prefs,
        appVersion: '1.0.0 (1)',
        platform: 'ios',
      );

  Future<SharedPreferences> fresh([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return SharedPreferences.getInstance();
  }

  test('설치 id 는 UUID 이고 한 번 정해지면 안 바뀐다', () async {
    final prefs = await fresh();
    final t = make(prefs);
    final first = t.installId;
    expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-')));
    expect(t.installId, first, reason: '부를 때마다 새로 만들면 기기 하나가 여러 대로 보인다');
    // 다음 실행에서도 같아야 로그인 전 퍼널이 이어진다.
    expect(make(prefs).installId, first);
  });

  test('개인정보로 보이는 키는 큐에 담기지도 않는다', () async {
    final prefs = await fresh();
    final t = make(prefs);
    t.track(AnalyticsEvent.worksheetCreateStart, props: {
      'topic_length': 12,
      'email': 'a@b.com',
      'token': 'secret',
      'nickname': '홍길동',
    });
    await t.dispose();

    final raw = prefs.getString('telemetry_queue_v1')!;
    expect(raw, contains('topic_length'), reason: '주제 길이는 재야 한다');
    for (final leaked in ['a@b.com', 'secret', '홍길동']) {
      expect(raw, isNot(contains(leaked)), reason: '$leaked 이(가) 실려 나갔다');
    }
  });

  test('큐는 기기에 남아 다음 실행에서 이어진다', () async {
    final prefs = await fresh();
    final t = make(prefs);
    t.track(AnalyticsEvent.appOpen);
    await t.dispose();

    final raw = prefs.getString('telemetry_queue_v1');
    expect(raw, isNotNull, reason: '못 보낸 이벤트를 버리면 오프라인 사용자의 기록이 통째로 사라진다');
    expect(raw, contains('appOpen'));
    // 개인정보가 섞여 들어가지 않았는지 저장된 원문으로 직접 확인한다.
    expect(raw, isNot(contains('@')));
  });

  test('크래시는 마스킹해서 담고, 큐가 넘쳐도 살아남는다', () async {
    final prefs = await fresh();
    final t = make(prefs);
    // 상한을 넘기도록 이벤트를 잔뜩 넣는다.
    for (var i = 0; i < Telemetry.maxQueued + 50; i++) {
      t.track(AnalyticsEvent.screenView, props: {'name': 'screen$i'});
    }
    t.recordError(Exception('token=abcdef 로 실패'), StackTrace.current, context: 'test');
    await t.dispose();

    final raw = prefs.getString('telemetry_queue_v1')!;
    expect(raw, contains('"crashes"'));
    expect(raw, contains('test'), reason: '크래시가 오래된 화면 조회에 밀려나면 안 된다');
    expect(raw, isNot(contains('abcdef')), reason: '토큰이 그대로 실려 나갔다');
  });

  group('크래시 묶음(fingerprint)', () {
    test('가변 부분이 달라도 같은 버그는 같은 열쇠다', () {
      final a = crashFingerprint(
          'Bad state: worksheet 3f2504e0-4f89-11d3-9a0c-0305e82c3301 not found at 0x1a2b', 'load');
      final b = crashFingerprint(
          'Bad state: worksheet 9c858901-8a57-4791-81fe-4c455b099bc9 not found at 0xffee', 'load');
      expect(a, b, reason: '같은 버그가 두 개로 세어지면 어느 것부터 고칠지 알 수 없다');
    });

    test('다른 버그는 다른 열쇠다', () {
      expect(crashFingerprint('Network unreachable', 'save'),
          isNot(crashFingerprint('Bad state: no element', 'save')));
    });

    test('같은 메시지라도 난 자리가 다르면 나눈다', () {
      expect(crashFingerprint('timeout', 'save'), isNot(crashFingerprint('timeout', 'load')));
    });
  });
}
