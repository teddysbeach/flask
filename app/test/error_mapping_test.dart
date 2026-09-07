import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 서버가 내는 오류 코드와 앱의 문구가 갈라지지 않았는가.
///
/// 서버에 코드를 하나 더하고 앱에 매핑을 잊으면, 사용자는 그 상황에 **맞지 않는 문구**를
/// 본다. 실제로 그랬다 — 하루 상한(daily_limit_reached)을 서버에 넣었더니 앱이
/// "요청이 너무 빨라요" 라고 했다. 사용자는 빠르게 누른 것이 아니라 오늘 몫을 다 쓴
/// 것이고, 기다려야 하는 시간이 완전히 다르다.
void main() {
  final serverCodes = <String>{};
  final fnDir = Directory('../server/supabase/functions');
  for (final f in fnDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('index.ts')) continue;
    for (final m in RegExp(r"errorResponse\('([a-z_]+)'").allMatches(f.readAsStringSync())) {
      serverCodes.add(m.group(1)!);
    }
  }

  final mapping = File('lib/data/supabase.dart').readAsStringSync();

  /// 굳이 문구를 따로 안 줘도 되는 것들.
  ///
  /// 사용자가 만들 수 없는 상황이거나(잘못된 메서드·형식), 화면이 애초에 못 만드는
  /// 요청이다. 이런 것에까지 전용 문구를 두면 문구가 코드보다 많아진다.
  const genericIsFine = {
    'method_not_allowed',   // 앱이 만들 수 없다
    'unauthorized',         // 로그인 화면으로 보내는 공통 처리가 있다
    'not_found',            // 종류별 문구가 화면에 있다
    'invalid_topic', 'invalid_grade', 'invalid_schedule', 'invalid_worksheet',
    'invalid_platform', 'invalid_transaction', 'invalid_install_id',
    'payload_too_large',    // 앱이 크기를 이미 막는다
    'rate_limited',         // 공통 문구가 맞는 유일한 경우
    'update_failed', 'insert_failed', 'grant_failed',  // 서버 오류 공통 문구
    'duplicate_topic',      // 오류가 아니라 분기다(CreateDuplicate)
  };

  test('서버가 내는 코드에 앱의 문구가 있다', () {
    expect(serverCodes, isNotEmpty, reason: '서버 코드를 못 읽었다');

    final missing = serverCodes
        .where((c) => !genericIsFine.contains(c))
        .where((c) => !mapping.contains("'$c'"))
        .toList()
      ..sort();

    expect(missing, isEmpty,
        reason: '서버가 내지만 앱이 모르는 코드: $missing — 사용자는 상황에 안 맞는 문구를 본다');
  });

  test('앱이 아는 코드는 서버가 실제로 낸다', () {
    // 없어진 코드를 계속 들고 있으면, 그 문구는 영영 안 나오는데 코드만 남는다.
    final appCodes = RegExp(r"code == '([a-z_]+)'")
        .allMatches(mapping)
        .map((m) => m.group(1)!)
        .toSet();
    final stale = appCodes.difference(serverCodes).toList()..sort();
    expect(stale, isEmpty, reason: '서버에 없는 코드를 앱이 들고 있다: $stale');
  });
}
