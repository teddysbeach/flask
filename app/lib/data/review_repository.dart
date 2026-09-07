import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../domain/models.dart';
import 'supabase.dart';

/// 복습 큐. **서버의 `review_schedules` 가 소스 오브 트루스다.**
///
/// 앱은 간격을 계산하지 않는다. 로컬 알림은 여기서 읽은 예정 목록에서 파생된 캐시일 뿐이라,
/// 알림이 유실되거나 기기를 바꿔도 앱을 열면 큐가 서버 기준으로 정확히 복원된다.
class ReviewRepository {
  ReviewRepository(this._client);

  final SupabaseClient _client;

  /// 조인 한 번으로 문제·정답·해설·학습지 제목까지 가져온다.
  /// 화면이 문항을 다시 조회하면 목록을 그리는 동안 N+1 이 된다.
  static const _select =
      'id, repetition, due_at, worksheet_id, '
      'quiz_items(id, question, answer, explanation, choices), '
      'worksheets(title)';

  /// 오늘 풀 것. `due_at <= now` 이고 아직 `pending` 인 것만.
  Future<List<ReviewItem>> due({int limit = 50}) async {
    try {
      final rows = await _client
          .from('review_schedules')
          .select(_select)
          .eq('state', 'pending')
          .lte('due_at', DateTime.now().toUtc().toIso8601String())
          .order('due_at', ascending: true)
          .limit(limit);
      return _map(rows);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 앞으로 예정된 것. 로컬 알림 예약에 쓴다.
  ///
  /// iOS 는 대기 중인 로컬 알림을 64개까지만 들고 있으므로 여기서 다 받아올 필요가 없다 —
  /// 임박한 것부터 넉넉히 받아 놓고 실제 예약은 [NotificationService] 가 상한을 적용해 고른다.
  Future<List<ReviewItem>> upcoming({int limit = 60}) async {
    try {
      final rows = await _client
          .from('review_schedules')
          .select(_select)
          .eq('state', 'pending')
          .gt('due_at', DateTime.now().toUtc().toIso8601String())
          .order('due_at', ascending: true)
          .limit(limit);
      return _map(rows);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 자기 평가를 올린다. grade 0=모르겠음 1=어려움 2=보통 3=쉬움.
  ///
  /// TODO(server): answer_review RPC — SM-2(ease 재계산·다음 회차 due_at·relearn 삽입·retired 졸업)는
  /// `server/supabase/functions/_shared/review-schedule.ts` 의 `answerReview`/`rescheduleRemaining` 에만 있고,
  /// 그걸 호출하는 RPC/엣지 함수가 아직 없다. 앱에 SM-2 를 다시 구현하면 규칙이 두 벌이 되어
  /// 반드시 어긋나므로(그리고 어긋난 쪽은 언제나 클라이언트다) 여기서는 응답 사실만 기록한다.
  /// RPC 가 생기면 이 update 를 `_client.rpc('answer_review', params: {...})` 로 갈아끼우면 된다.
  Future<void> answer({required String scheduleId, required int grade}) async {
    // 서버 제약(0~3)과 같은 범위다. 화면 버그로 범위를 벗어난 값이 나가면 여기서 먼저 잡는다 —
    // 서버가 뱉은 제약 위반 문구가 사용자 화면에 나가면 안 된다.
    if (grade < 0 || grade > 3) {
      throw AppError.of(AppErrorKind.validation,
          message: '평가를 다시 골라 주세요.', code: 'grade_out_of_range');
    }
    try {
      await _client.from('review_schedules').update({
        'state': 'done',
        'grade': grade,
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', scheduleId);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  List<ReviewItem> _map(List<Map<String, dynamic>> rows) {
    final items = <ReviewItem>[];
    for (final r in rows) {
      final item = _toItem(r);
      // 문항이 지워졌으면(학습지 삭제 등) 화면에 그릴 것이 없다. 조용히 건너뛴다.
      if (item != null) items.add(item);
    }
    return items;
  }

  ReviewItem? _toItem(Map<String, dynamic> row) {
    final quiz = _one(row['quiz_items']);
    if (quiz == null) return null;
    final sheet = _one(row['worksheets']);

    return ReviewItem(
      scheduleId: row['id'] as String,
      quizItemId: quiz['id'] as String,
      worksheetId: row['worksheet_id'] as String,
      question: quiz['question'] as String? ?? '',
      answer: quiz['answer'] as String? ?? '',
      explanation: quiz['explanation'] as String? ?? '',
      dueAt: DateTime.parse(row['due_at'] as String).toLocal(),
      repetition: (row['repetition'] as num?)?.toInt() ?? 0,
      choices: _choices(quiz['choices']),
      worksheetTitle: sheet?['title'] as String?,
    );
  }

  /// PostgREST 는 관계를 객체로 줄 때도 있고 배열로 줄 때도 있다(스키마 캐시 상태에 따라).
  /// 한쪽만 가정하면 어느 날 조용히 빈 목록이 된다.
  Map<String, dynamic>? _one(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  List<String>? _choices(Object? value) {
    if (value is! List || value.isEmpty) return null;
    return value.map((c) => '$c').toList(growable: false);
  }
}

final reviewRepositoryProvider =
    Provider<ReviewRepository>((ref) => ReviewRepository(ref.watch(supabaseProvider)));
