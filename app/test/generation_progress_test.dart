import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onpar/data/worksheet_repository.dart';
import 'package:onpar/domain/models.dart';

/// 생성 진행 표시.
///
/// 신고: **13분째 "품질을 검사하고 있어요"** 였다.
///
/// 두 가지가 겹쳤다. 화면이 경과 시간만 보고 단계를 지어냈고(서버가 죽어도 계속 말한다),
/// 매달린 생성을 아무도 닫아 주지 않았다(청소가 새 요청 때만 돌았다).
/// 여기서 재는 것은 **앱이 모르는 것을 안다고 말하지 않는가** 다.
void main() {
  WorksheetSummary make({
    String status = 'generating',
    String? stage,
    Duration age = Duration.zero,
    String? stageAt,
  }) {
    final created = DateTime.now().toUtc().subtract(age);
    return WorksheetSummary.fromMap({
      'id': 'w1',
      'topic': '이차함수',
      'status': status,
      'created_at': created.toIso8601String(),
      'stage': stage,
      'stage_at': stageAt,
    });
  }

  group('단계는 서버가 말한 것만 쓴다', () {
    test('서버가 말한 단계를 그대로 읽는다', () {
      expect(make(stage: 'critic').stage, GenerationStage.critic);
      expect(make(stage: 'revise').stage, GenerationStage.revise);
    });

    test('서버가 말하지 않았으면 모른다', () {
      // null 이어야 화면이 "아직 모른다" 고 말할 수 있다.
      // 여기서 아무 단계나 기본값으로 채우면 그 순간부터 화면이 거짓말을 한다.
      expect(make().stage, isNull);
      expect(make(stage: 'nonsense').stage, isNull);
    });

    test('앱이 아는 단계와 서버가 쓰는 단계가 같다', () {
      // 마이그레이션의 제약과 enum 이 갈라지면 화면이 조용히 빈칸이 된다.
      final sql = File('../server/supabase/migrations/'
              '20260101000026_generation_progress.sql')
          .readAsStringSync();
      final m = RegExp(r"worksheets_stage_valid[\s\S]*?stage in \(([^)]*)\)").firstMatch(sql);
      expect(m, isNotNull, reason: 'stage 제약을 못 찾았다');
      final inDb = m!
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll("'", ''))
          .toSet();
      final inApp = GenerationStage.values.map((e) => e.name).toSet();
      expect(inApp, inDb, reason: '앱의 단계 목록과 DB 제약이 갈라졌다');
    });
  });

  group('경과 시간은 서버가 적은 시각으로 잰다', () {
    test('화면이 센 초가 아니라 created_at 을 쓴다', () {
      // 화면이 세면 앱을 껐다 켤 때마다 0부터 다시 센다. 13분을 기다린 사람이
      // "방금 시작했어요" 를 보게 되는 자리가 정확히 여기다.
      final w = make(age: const Duration(minutes: 13));
      expect(w.age(DateTime.now()).inMinutes, 13);
    });

    test('보통 시간을 넘기면 늦다고 말할 수 있다', () {
      expect(make(age: const Duration(seconds: 90)).isSlow(DateTime.now()), isFalse);
      expect(make(age: const Duration(minutes: 13)).isSlow(DateTime.now()), isTrue);
    });

    test('같은 단계에 머문 시간을 안다', () {
      final at = DateTime.now().toUtc().subtract(const Duration(minutes: 9));
      final w = make(stage: 'critic', stageAt: at.toIso8601String());
      expect(w.stuckFor(DateTime.now())!.inMinutes, 9);
      expect(make(stage: 'critic').stuckFor(DateTime.now()), isNull);
    });
  });

  group('기다림에는 끝이 있다', () {
    test('감시 마감이 서버의 청소 기준보다 뒤다', () {
      // 앞서면 사용자는 서버가 곧 내놓을 **진짜 실패 사유** 대신 모호한 화면을 본다.
      final sql = File('../server/supabase/migrations/'
              '20260101000026_generation_progress.sql')
          .readAsStringSync();
      final m = RegExp(r"generation_stall_timeout[\s\S]*?interval '(\d+) minutes'")
          .firstMatch(sql);
      expect(m, isNotNull);
      final serverMinutes = int.parse(m!.group(1)!);
      expect(WorksheetRepository.watchDeadline.inMinutes,
          greaterThan(serverMinutes),
          reason: '앱이 서버보다 먼저 포기한다');
    });

    test('시간 초과로 끊긴 생성에도 환불 안내가 붙는다', () {
      // 사용자가 가장 궁금한 것은 "내 장수는?" 이다. 모든 실패 문구가 그 답을 담아야 한다.
      for (final code in [
        'generation_timeout',
        'generation_stalled',
        'cost_cap_exceeded',
        'llm_refused',
        'draft_quality_rejected',
        'render_failed',
        'something_new_we_never_saw',
      ]) {
        final w = WorksheetSummary.fromMap({
          'id': 'w1', 'topic': 't', 'status': 'failed',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'error_code': code,
        });
        expect(w.failureMessage, contains('돌려'),
            reason: '$code 의 안내에 장수 환불 이야기가 없다');
      }
    });
  });
}
