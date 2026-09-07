import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import 'supabase.dart';

/// 학습 기록.
///
/// 데이터는 진작 쌓이고 있었다 — responses(무엇을 맞고 틀렸는지)와 review_schedules
/// (언제 복습했는지). 쌓아만 두고 안 보여주면 사용자에게는 없는 것과 같고,
/// 다시 오게 하는 장치가 알림 하나뿐인 채로 남는다.
class LearningStats {
  const LearningStats({
    required this.worksheets,
    required this.answered,
    required this.correct,
    required this.reviewsDone,
    required this.reviewsDueToday,
    required this.streakDays,
    required this.activeDays,
  });

  final int worksheets;
  final int answered;
  final int correct;
  final int reviewsDone;
  final int reviewsDueToday;

  /// 연속 학습일. 오늘 아직 안 했어도 어제까지 이어졌으면 살아 있다 —
  /// 하루 늦게 연 사람의 노력을 0 으로 만들면 다시 시작할 마음까지 사라진다.
  final int streakDays;
  final int activeDays;

  static const empty = LearningStats(
    worksheets: 0, answered: 0, correct: 0,
    reviewsDone: 0, reviewsDueToday: 0, streakDays: 0, activeDays: 0,
  );

  /// 처음에 맞힌 비율(0~1). 답한 적이 없으면 null — 0% 로 보여주면 거짓말이다.
  double? get accuracy => answered == 0 ? null : correct / answered;

  factory LearningStats.fromMap(Map<String, dynamic> m) => LearningStats(
        worksheets: (m['worksheets_total'] as num?)?.toInt() ?? 0,
        answered: (m['quiz_answered'] as num?)?.toInt() ?? 0,
        correct: (m['quiz_correct'] as num?)?.toInt() ?? 0,
        reviewsDone: (m['reviews_done'] as num?)?.toInt() ?? 0,
        reviewsDueToday: (m['reviews_due_today'] as num?)?.toInt() ?? 0,
        streakDays: (m['streak_days'] as num?)?.toInt() ?? 0,
        activeDays: (m['active_days'] as num?)?.toInt() ?? 0,
      );
}

class StatsRepository {
  StatsRepository(this._client);
  final SupabaseClient _client;

  Future<LearningStats> load() async {
    try {
      final rows = await _client.rpc('learning_stats').withTimeout();
      if (rows is List && rows.isNotEmpty) {
        return LearningStats.fromMap(Map<String, dynamic>.from(rows.first as Map));
      }
      return LearningStats.empty;
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final statsRepositoryProvider =
    Provider<StatsRepository>((ref) => StatsRepository(ref.watch(supabaseProvider)));

final learningStatsProvider = FutureProvider<LearningStats>((ref) {
  ref.watch(currentUserProvider); // 계정이 바뀌면 남의 기록을 들고 있으면 안 된다
  return ref.watch(statsRepositoryProvider).load();
});
