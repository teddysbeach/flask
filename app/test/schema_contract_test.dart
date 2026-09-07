import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/data/purchase_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/create/create_screen.dart';
import 'package:onpar/features/support/contact_screen.dart';

/// 앱의 enum 과 DB 의 check 제약은 **같은 목록의 두 벌**이다.
///
/// 한쪽만 고치면 화면은 멀쩡한데 서버가 행을 거부한다. 그 실패는 사용자가 버튼을 누른
/// 뒤에야 나타나고, 로그에는 제약 위반 문구만 남는다 — 어느 화면에서 온 것인지 모른다.
///
/// 그래서 목록을 값으로 맞춰 본다. 마이그레이션 파일을 읽어서 비교하는 이유는,
/// DB 를 띄우지 않고도 앱 테스트가 이 어긋남을 잡을 수 있어야 하기 때문이다.
void main() {
  final migrations = Directory('../server/supabase/migrations')
      .listSync()
      .whereType<File>()
      .map((f) => f.readAsStringSync())
      .join('\n');

  /// `... in ('a','b','c')` 에서 목록을 꺼낸다. 제약 이름으로 찾는다.
  Set<String> constraintValues(String constraintName) {
    final at = migrations.indexOf(constraintName);
    expect(at, isNot(-1), reason: '$constraintName 제약을 못 찾았다');
    final tail = migrations.substring(at);
    final m = RegExp(r"in\s*\(([^)]*)\)").firstMatch(tail);
    expect(m, isNotNull, reason: '$constraintName 의 목록을 못 읽었다');
    return RegExp(r"'([a-z_]+)'")
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1)!)
        .toSet();
  }

  test('학습지 상태', () {
    // 여기가 갈라지면 서버가 만든 상태를 앱이 못 읽어서 목록이 통째로 안 뜬다.
    expect(WorksheetStatus.values.map((e) => e.name).toSet(),
        constraintValues('worksheets_status_valid'));
  });

  test('난이도', () {
    expect(CreateLevel.values.map((e) => e.value).toSet(),
        constraintValues('worksheets_level_valid'));
  });

  test('문의 유형', () {
    // 앱의 enum 이름이 그대로 support_tickets.topic 으로 간다.
    expect(ContactTopic.values.map((e) => e.name).toSet(),
        constraintValues('support_tickets_topic_known'));
  });

  test('문의 상태', () {
    // 문의함 화면이 이 값들로 배지를 고른다. 모르는 값이 오면 '접수됨' 으로 떨어진다.
    expect(constraintValues('support_tickets_status_known'), {'open', 'answered', 'closed'});
  });

  test('복습 회차 상태', () {
    // due() 가 'pending' 만 고른다. 이름이 바뀌면 복습 큐가 통째로 빈다.
    expect(constraintValues('review_state_valid'), contains('pending'));
  });

  test('상품 id', () {
    // 앱의 상수와 products 테이블 씨앗이 같아야 결제가 성립한다.
    // 스토어에 올린 상품 id 와도 같아야 하는데, 그건 사람이 맞춰야 한다.
    for (final id in [kProductIdSheets3, kProductIdSheets10, kProductIdSheets30]) {
      expect(migrations, contains("('$id'"), reason: '$id 가 products 씨앗에 없다');
    }
  });

  test('공지 종류', () {
    expect(constraintValues('notices_kind_valid'), {'notice', 'event'});
  });
}
