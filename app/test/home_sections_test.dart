import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/home/home_sections.dart';

/// 홈의 날짜 묶음.
///
/// 목록이 통째로 이상해 보이는 종류의 버그라, 화면을 띄워서 눈으로 잡기 어렵다.
/// 경계(오늘/어제/지난 7일/이번 달/작년)를 값으로 잰다.
void main() {
  final now = DateTime(2026, 3, 15, 14, 0); // 일요일 낮

  WorksheetSummary at(String id, DateTime when) => WorksheetSummary(
        id: id,
        topic: '주제 $id',
        status: WorksheetStatus.ready,
        createdAt: when,
      );

  test('빈 목록은 묶음도 없다', () {
    expect(groupWorksheetsByDate(const [], now: now), isEmpty);
  });

  test('오늘·어제·지난 7일·이번 달·지난달로 갈린다', () {
    final groups = groupWorksheetsByDate([
      at('a', now.subtract(const Duration(hours: 2))),
      at('b', now.subtract(const Duration(days: 1))),
      at('c', now.subtract(const Duration(days: 3))),
      at('d', now.subtract(const Duration(days: 10))),
      at('e', DateTime(2026, 2, 20)),
      at('f', DateTime(2025, 12, 1)),
    ], now: now);

    expect(groups.map((g) => g.label).toList(),
        ['오늘', '어제', '지난 7일', '이번 달', '2월', '2025년 12월']);
    expect(groups.first.items.single.id, 'a');
  });

  test('같은 날짜는 한 묶음으로 모인다', () {
    final groups = groupWorksheetsByDate([
      at('a', now),
      at('b', now.subtract(const Duration(hours: 5))),
      at('c', now.subtract(const Duration(days: 1))),
    ], now: now);

    expect(groups.length, 2);
    expect(groups.first.items.map((w) => w.id), ['a', 'b']);
  });

  test('서버가 준 순서를 다시 정렬하지 않는다', () {
    // 여기서 또 정렬하면 서버 순서와 화면 순서가 두 벌이 되고, 커서 페이징과 어긋난다.
    final groups = groupWorksheetsByDate([
      at('first', now.subtract(const Duration(hours: 1))),
      at('second', now.subtract(const Duration(hours: 9))),
    ], now: now);
    expect(groups.single.items.map((w) => w.id), ['first', 'second']);
  });

  test('자정 직후에 만든 것도 오늘이다', () {
    // 시각이 아니라 날짜로 가른다. 00:10 에 만든 것이 "어제" 로 보이면 안 된다.
    final groups = groupWorksheetsByDate(
      [at('a', DateTime(2026, 3, 15, 0, 10))],
      now: now,
    );
    expect(groups.single.label, '오늘');
  });

  test('미래 시각(기기 시계가 어긋난 경우)도 오늘로 둔다', () {
    // 시계가 조금 앞선 기기가 있다. "내일" 묶음을 만들면 목록 맨 위가 이상해진다.
    final groups = groupWorksheetsByDate(
      [at('a', now.add(const Duration(hours: 3)))],
      now: now,
    );
    expect(groups.single.label, '오늘');
  });
}
