import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/notifications.dart';
import 'package:onpar/domain/models.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 알림 규칙을 고정한다.
///
/// 여기 있는 함수들은 순수 함수다 — 서버(`_shared/review-schedule.ts`)와 **같은 규칙**을 옮긴 것이라
/// 조용히 갈라지면 앱과 서버가 서로 다른 알림을 약속하게 된다. 그래서 규칙을 말이 아니라 테스트로 적는다.
void main() {
  late tz.Location seoul;

  setUpAll(() {
    tzdata.initializeTimeZones();
    seoul = tz.getLocation('Asia/Seoul');
  });

  ReviewItem item(
    String id,
    tz.TZDateTime due, {
    String question = '문제',
    String? title = '학습지',
  }) =>
      ReviewItem(
        scheduleId: id,
        quizItemId: 'quiz-$id',
        worksheetId: 'sheet-$id',
        question: question,
        answer: '정답',
        explanation: '해설',
        dueAt: due,
        repetition: 0,
        worksheetTitle: title,
      );

  tz.TZDateTime at(int year, int month, int day, [int hour = 9]) =>
      tz.TZDateTime(seoul, year, month, day, hour);

  group('예약이 마르는 자리 — 돌아오라는 한 번의 신호', () {
    test('슬롯이 모자라면 마지막 예약 다음 날 한 번 부른다', () {
      // 로컬 알림은 앱을 열어야 다시 걸린다. 이게 없으면 슬롯이 마른 뒤 앱은 조용해지고,
      // 사용자는 우리가 포기했다고 느낀다.
      final items = [for (var i = 1; i <= 10; i++) item('s$i', at(2026, 3, i))];
      final plan = planReviewNotifications(
        upcoming: items,
        location: seoul,
        now: DateTime.utc(2026, 2, 20),
        reviewHour: 21,
        slots: 3,
      );

      // 총 개수는 슬롯 수를 넘지 않는다. 마지막 한 자리를 "돌아오라" 가 쓴다 —
      // OS 대기열을 넘긴 알림은 조용히 버려지고 우리는 그걸 알 방법이 없다.
      expect(plan.length, 3);
      expect(plan.where((p) => p.kind == NotificationKind.review).length, 2);
      final nudge = plan.last;
      expect(nudge.kind, NotificationKind.returning);
      expect(nudge.at.day, plan[1].at.day + 1, reason: '예약이 마르는 다음 날이어야 한다');
      expect(nudge.at.hour, 21);
    });

    test('전부 예약했으면 부르지 않는다 — 조용해질 일이 없다', () {
      final items = [for (var i = 1; i <= 3; i++) item('s$i', at(2026, 3, i))];
      final plan = planReviewNotifications(
        upcoming: items,
        location: seoul,
        now: DateTime.utc(2026, 2, 20),
        reviewHour: 21,
        slots: 10,
      );
      expect(plan.every((p) => p.kind == NotificationKind.review), isTrue);
    });

    test('걸 것이 하나도 없으면 부르지 않는다', () {
      final plan = planReviewNotifications(
        upcoming: const [],
        location: seoul,
        now: DateTime.utc(2026, 2, 20),
        reviewHour: 21,
        slots: 0,
      );
      expect(plan, isEmpty);
    });

    test('눌러서 열면 복습 큐로 간다 — 특정 학습지를 가리키지 않는다', () {
      final items = [for (var i = 1; i <= 5; i++) item('s$i', at(2026, 3, i))];
      final plan = planReviewNotifications(
        upcoming: items, location: seoul, now: DateTime.utc(2026, 2, 20),
        reviewHour: 21, slots: 2,
      );
      final nudge = plan.last;
      expect(routeFromPayload(nudge.payload), '/review/session');
      // id 가 복습 id 공간 안이어야 기존 정리 규칙(범위 취소)이 이 알림도 치운다.
      expect(isReviewNotificationId(nudge.id), isTrue);
    });
  });

  group('notificationBody — 서버 notificationBody 와 같은 규칙', () {
    test('100자 이하면 그대로 둔다', () {
      const q = '이벤트 스토어에 저장되는 것은 상태인가, 변화인가?';
      expect(notificationBody(q), q);
    });

    test('문장 경계에서 자른다', () {
      final q = '${'가' * 60}. ${'나' * 60}';
      final body = notificationBody(q);
      expect(body, '${'가' * 60}.…');
    });

    test('문장 경계가 앞쪽(절반 이전)에만 있으면 그냥 100자에서 자른다', () {
      final q = '짧다. ${'가' * 200}';
      final body = notificationBody(q);
      expect(body.endsWith('…'), isTrue);
      expect(body.length, 101); // 100자 + 말줄임표
    });

    test('경계가 없으면 100자에서 자르고 말줄임표를 붙인다', () {
      final q = '가' * 300;
      expect(notificationBody(q), '${'가' * 100}…');
    });

    test('자른 끝의 공백은 남기지 않는다', () {
      final q = '${'가' * 99} ${'나' * 50}';
      expect(notificationBody(q), '${'가' * 99}…');
    });

    test('한국어 종결 어미(요 )도 문장 경계로 본다', () {
      final q = '${'가' * 55}해요 ${'나' * 80}';
      expect(notificationBody(q), '${'가' * 55}해요…');
    });
  });

  group('알림 id 규칙', () {
    test('같은 schedule_id 는 언제나 같은 id 가 된다', () {
      expect(reviewNotificationId('abc-123'), reviewNotificationId('abc-123'));
    });

    test('우리 구간 안에만 만든다 — cancelAll 없이 우리 것만 지우려는 이유다', () {
      for (final id in ['a', 'b-1', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee']) {
        expect(isReviewNotificationId(reviewNotificationId(id)), isTrue);
      }
      expect(isReviewNotificationId(0), isFalse);
      expect(isReviewNotificationId(kReviewIdBase - 1), isFalse);
      expect(isReviewNotificationId(kReviewIdBase + kReviewIdSpan), isFalse);
    });
  });

  group('planReviewNotifications', () {
    test('지난 것은 예약하지 않는다', () {
      final now = at(2026, 3, 10, 12);
      final plan = planReviewNotifications(
        upcoming: [
          item('past', at(2026, 3, 9, 21)),
          item('now', now),
          item('future', at(2026, 3, 11, 21)),
        ],
        location: seoul,
        now: now,
        reviewHour: 21,
      );
      expect(plan.map((p) => p.scheduleId), ['future']);
    });

    test('임박한 것부터 채운다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          item('c', at(2026, 3, 13, 21)),
          item('a', at(2026, 3, 11, 21)),
          item('b', at(2026, 3, 12, 21)),
        ],
        location: seoul,
        now: now,
        reviewHour: 21,
      );
      expect(plan.map((p) => p.scheduleId), ['a', 'b', 'c']);
    });

    test('하루 상한 3개 — 넘치면 다음 날 복습 시각으로 민다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          for (var i = 0; i < 5; i++) item('s$i', at(2026, 3, 11, 20)),
        ],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(plan.length, 5);
      final firstDay = plan.where((p) => p.at.day == 11).length;
      final secondDay = plan.where((p) => p.at.day == 12).length;
      expect(firstDay, kMaxReviewsPerDay);
      expect(secondDay, 2);
      expect(plan.where((p) => p.at.day == 12).every((p) => p.at.hour == 20), isTrue);
    });

    test('하루 상한은 날짜별로 따로 센다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          for (var i = 0; i < 3; i++) item('a$i', at(2026, 3, 11, 20)),
          for (var i = 0; i < 3; i++) item('b$i', at(2026, 3, 12, 20)),
        ],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(plan.where((p) => p.at.day == 11).length, 3);
      expect(plan.where((p) => p.at.day == 12).length, 3);
    });

    test('48개(iOS 64개 한도 대응) 넘게 걸지 않는다 — 임박한 것부터 남는다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          for (var i = 0; i < 120; i++) item('s$i', at(2026, 3, 11 + i, 20)),
        ],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(plan.length, kNotificationSlots);
      expect(plan.first.scheduleId, 's0');
      expect(plan.last.at.isBefore(at(2026, 3, 11 + kNotificationSlots, 20)), isTrue);
    });

    test('야간(22~08시)에는 보내지 않고 복습 시각으로 민다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          item('night', at(2026, 3, 11, 23)), // 밤 11시 → 다음 날
          item('dawn', at(2026, 3, 12, 3)), // 새벽 3시 → 같은 날
          item('day', at(2026, 3, 13, 15)), // 낮 → 그대로
        ],
        location: seoul,
        now: now,
        reviewHour: 9,
      );
      final byId = {for (final p in plan) p.scheduleId: p.at};
      expect(byId['night']!.day, 12);
      expect(byId['night']!.hour, 9);
      expect(byId['dawn']!.day, 12);
      expect(byId['dawn']!.hour, 9);
      expect(byId['day']!.day, 13);
      expect(byId['day']!.hour, 15);
    });

    test('복습 시각이 야간이면 발송 가능한 범위로 가둔다 — 안 그러면 영원히 밀린다', () {
      expect(clampReviewHour(23), kLatestReviewHour);
      expect(clampReviewHour(3), kEarliestReviewHour);

      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [item('x', at(2026, 3, 11, 2))],
        location: seoul,
        now: now,
        reviewHour: 23,
      );
      expect(plan.single.at.hour, kLatestReviewHour);
      expect(plan.single.at.day, 11);
    });

    test('같은 회차가 두 번 와도 한 번만 건다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [item('dup', at(2026, 3, 11, 20)), item('dup', at(2026, 3, 12, 20))],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(plan.length, 1);
    });

    test('제목은 학습지 제목, 본문은 문제 원문이다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [
          item('a', at(2026, 3, 11, 20), question: '이벤트 스토어에 저장되는 것은?', title: '이벤트 소싱'),
          item('b', at(2026, 3, 12, 20), title: null),
        ],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(plan.first.title, '🧠 이벤트 소싱');
      expect(plan.first.body, '이벤트 스토어에 저장되는 것은?');
      expect(plan.last.title, '🧠 복습할 시간이에요');
    });

    test('payload 에서 학습지 딥링크를 복원한다', () {
      final now = at(2026, 3, 10, 9);
      final plan = planReviewNotifications(
        upcoming: [item('a', at(2026, 3, 11, 20))],
        location: seoul,
        now: now,
        reviewHour: 20,
      );
      expect(routeFromPayload(plan.single.payload), '/worksheet/sheet-a?quizId=quiz-a');
      expect(routeFromPayload('망가진 payload'), isNull);
      expect(routeFromPayload(null), isNull);
    });

    test('서머타임이 있는 지역에서도 로컬 벽시계 시각을 지킨다', () {
      final ny = tz.getLocation('America/New_York');
      // 2026-03-08 에 미국 서머타임이 시작한다. 그 주에 걸린 알림도 로컬 9시여야 한다.
      final plan = planReviewNotifications(
        upcoming: [
          item('before', tz.TZDateTime(ny, 2026, 3, 7, 2)),
          item('after', tz.TZDateTime(ny, 2026, 3, 9, 2)),
        ],
        location: ny,
        now: tz.TZDateTime(ny, 2026, 3, 6, 9),
        reviewHour: 9,
      );
      expect(plan.every((p) => p.at.hour == 9), isTrue);
      expect(plan.map((p) => p.at.day), [7, 9]);
    });
  });
}
