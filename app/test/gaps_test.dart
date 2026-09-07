import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/core/routes.dart';
import 'package:onpar/data/stats_repository.dart';
import 'package:onpar/domain/models.dart';
import 'package:onpar/features/library/library_controller.dart';

/// 앱 점검에서 나온 빈틈들의 재발 방지선.
void main() {
  group('학습 기록', () {
    LearningStats stats({int answered = 0, int correct = 0, int streak = 0}) => LearningStats(
          worksheets: 1,
          answered: answered,
          correct: correct,
          reviewsDone: 0,
          reviewsDueToday: 0,
          streakDays: streak,
          activeDays: 0,
        );

    test('한 문제도 안 풀었으면 정답률은 0% 가 아니라 없음이다', () {
      // 0% 로 보여주면 "다 틀렸다" 로 읽힌다. 시작도 안 한 사람에게 할 말이 아니다.
      expect(stats().accuracy, isNull);
      expect(stats(answered: 4, correct: 3).accuracy, closeTo(0.75, 0.001));
    });
  });

  group('서재 검색', () {
    WorksheetSummary sheet(String id, String topic, {String? title, WorksheetStatus s = WorksheetStatus.ready}) =>
        WorksheetSummary(id: id, topic: topic, title: title, status: s, createdAt: DateTime(2026));

    final items = [
      sheet('1', '미분이 왜 필요한지', title: '변화를 재는 법'),
      sheet('2', '광합성의 명반응', title: '빛이 하는 일'),
      sheet('3', '실패한 것', s: WorksheetStatus.failed),
    ];

    test('제목과 주제를 같이 본다', () {
      // 모델이 붙인 제목만 보면 "내가 뭘 적었는지" 로는 못 찾는다.
      final byTitle = LibraryState(items: items, query: '변화');
      expect(byTitle.visible.map((w) => w.id), ['1']);

      final byTopic = LibraryState(items: items, query: '광합성');
      expect(byTopic.visible.map((w) => w.id), ['2']);
    });

    test('대소문자와 앞뒤 공백은 무시한다', () {
      expect(LibraryState(items: items, query: '  빛이  ').visible.length, 1);
    });

    test('검색과 필터는 같이 걸린다', () {
      final s = LibraryState(items: items, query: '것', filter: LibraryFilter.failed);
      expect(s.visible.map((w) => w.id), ['3']);
    });

    test('좁혀 놓았는지 알 수 있다 — 빈 화면 문구가 갈린다', () {
      // "학습지가 없어요" 와 "찾는 학습지가 없어요" 는 다른 말이다.
      expect(const LibraryState().narrowed, isFalse);
      expect(const LibraryState(query: '미분').narrowed, isTrue);
      expect(const LibraryState(filter: LibraryFilter.failed).narrowed, isTrue);
    });
  });

  group('홈과 찾기는 한 목록을 본다', () {
    WorksheetSummary sheet(String id, {WorksheetStatus s = WorksheetStatus.ready}) =>
        WorksheetSummary(id: id, topic: '주제 $id', status: s, createdAt: DateTime(2026));

    test('홈은 필터·검색을 적용하지 않는다', () {
      // 찾기 탭에서 "실패" 를 걸어 두었다고 홈이 좁아지면 안 된다.
      // 홈은 items 를, 찾기는 visible 을 그린다.
      final state = LibraryState(
        items: [sheet('1'), sheet('2', s: WorksheetStatus.failed)],
        filter: LibraryFilter.failed,
        query: '아무거나',
      );
      expect(state.items.length, 2, reason: '홈이 보는 목록');
      expect(state.visible, isEmpty, reason: '찾기가 보는 목록');
    });
  });

  group('목록이 갱신되는 자리', () {
    test('만들기·완성·삭제·제목수정 뒤에 공유 목록을 다시 받는다', () {
      // 홈과 찾기가 한 컨트롤러를 보므로, 목록을 바꾸는 곳은 모두 새로 받아야 한다.
      // 안 부르면 방금 만든 학습지가 홈에 없고, 지운 학습지가 목록에 남는다.
      const callers = {
        'lib/features/create/create_screen.dart': '만들기 주문',
        'lib/features/create/create_progress_screen.dart': '완성·실패',
        'lib/features/worksheet/worksheet_screen.dart': '삭제·제목 수정',
      };
      for (final entry in callers.entries) {
        final src = File(entry.key).readAsStringSync();
        expect(src, contains('libraryControllerProvider.notifier'),
            reason: '${entry.value} 뒤에 목록을 다시 받지 않는다 (${entry.key})');
      }
    });
  });

  group('경로', () {
    test('학습 기록은 로그인이 필요하다', () {
      // 남의 기록이 보이면 안 되는 화면이다.
      expect(Routes.isPublic(Routes.stats), isFalse);
    });
  });
}
