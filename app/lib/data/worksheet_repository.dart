import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/request_guard.dart';
import '../domain/models.dart';
import 'offline_store.dart';
import 'supabase.dart';

/// 학습지를 만들어 달라고 했을 때 서버가 하는 답 두 가지.
sealed class CreateResult {
  const CreateResult();
}

/// 접수됐다. 생성은 뒤에서 돈다.
class CreateAccepted extends CreateResult {
  const CreateAccepted(this.worksheetId);
  final String worksheetId;
}

/// 같은 주제로 이미 만든 학습지가 있다. **장수는 아직 깎이지 않았다.**
class CreateDuplicate extends CreateResult {
  const CreateDuplicate({required this.worksheetId, this.title, this.createdAt});
  final String worksheetId;
  final String? title;
  final DateTime? createdAt;
}

/// Edge Function 의 409(duplicate_topic) 응답을 결과로 옮긴다.
/// 여기서 못 알아보면 "알 수 없는 오류" 가 뜨고, 사용자는 같은 주제를 또 만든다.
CreateDuplicate? duplicateFromError(Object e) {
  if (e is! FunctionException) return null;
  final d = e.details;
  if (d is! Map || d['error'] != 'duplicate_topic') return null;
  final id = d['worksheet_id'];
  if (id is! String || id.isEmpty) return null;
  return CreateDuplicate(
    worksheetId: id,
    title: d['title'] as String?,
    createdAt: DateTime.tryParse('${d['created_at']}')?.toLocal(),
  );
}

/// 학습지 목록·생성·본문. 생성은 쿼터를 깎으므로 중복 요청을 여기서 막는다.
class WorksheetRepository {
  WorksheetRepository(this._client, this._guard, this._offline);

  final SupabaseClient _client;
  final RequestGuard _guard;
  final OfflineStore _offline;

  static const pageSize = 20;

  /// 목록. 커서(마지막 created_at)로 넘긴다 — offset 은 새 항목이 생기면 건너뛰거나 겹친다.
  Future<List<WorksheetSummary>> list({DateTime? before}) async {
    try {
      var q = _client.from('worksheets').select();
      if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
      final rows = await q.order('created_at', ascending: false).limit(pageSize).withTimeout();
      return rows.map((r) => WorksheetSummary.fromMap(r)).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<WorksheetSummary> get(String id) async {
    try {
      final row = await _client.from('worksheets').select().eq('id', id).single().withTimeout();
      return WorksheetSummary.fromMap(row);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 생성 중인 학습지의 상태. 진행 화면이 3초마다 부른다.
  ///
  /// 평범한 select 가 아니라 RPC 인 이유가 있다. **읽는 행위가 곧 고치는 행위**다 —
  /// 서버의 백그라운드가 죽어 매달려 있는 건이면 이 호출이 그 자리에서 닫고 장수를 돌려준다.
  /// 예전에는 그 청소가 "같은 사용자가 새 생성을 요청할 때" 만 돌았고, 그래서 아무것도
  /// 하지 않으면 화면은 13분이고 30분이고 "만드는 중" 이었다.
  Future<WorksheetSummary> status(String id) async {
    try {
      final rows = await _client.rpc('worksheet_status', params: {'p_id': id}).withTimeout();
      final list = rows as List<dynamic>;
      if (list.isEmpty) {
        // 남의 것이거나 지워진 것. 있음/없음을 구분해 알려주지 않는다.
        throw AppError.of(AppErrorKind.notFound, message: '학습지를 찾을 수 없어요.');
      }
      return WorksheetSummary.fromMap(Map<String, dynamic>.from(list.first as Map));
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 생성 요청. 서버는 202 로 바로 답하고 뒤에서 만든다(40~120초).
  ///
  /// 같은 주제로 두 번 눌러도 한 번만 나간다. 이게 없으면 사용자가 두 장을 잃는다.
  Future<CreateResult> create({
    required String topic,
    required String level,
    bool force = false,
  }) {
    final key = 'create:${topic.trim()}:$level:$force';
    return _guard.dedupe(key, () async {
      try {
        // 서버는 202 로 바로 답한다. 여기서 오래 기다릴 이유가 없다 —
        // 생성이 끝나는 것은 watch() 가 지켜본다.
        final res = await _client.functions.invoke(
          'generate-worksheet',
          body: {'topic': topic.trim(), 'level': level, if (force) 'force': true},
        ).withTimeout();
        final data = res.data;
        if (data is Map && data['worksheet_id'] is String) {
          return CreateAccepted(data['worksheet_id'] as String);
        }
        throw AppError.of(AppErrorKind.unknown, cause: data);
      } catch (e, st) {
        // 같은 주제로 이미 만든 것이 있다. 오류가 아니라 **물어볼 일**이다 —
        // 장수는 아직 안 깎였고, 다시 만들지 말지는 사용자가 정한다.
        final dupe = duplicateFromError(e);
        if (dupe != null) return dupe;
        throw mapSupabaseError(e, st);
      }
    });
  }

  /// 서버가 매달린 생성을 닫아 주는 기준(generation_stall_timeout, 10분)보다 조금 뒤.
  ///
  /// 앞서면 안 된다. 앞서면 사용자는 **서버가 곧 내놓을 진짜 실패 사유** 대신
  /// "오래 걸리네요" 라는 모호한 화면을 보게 되고, 장수를 돌려받았는지도 알 수 없다.
  static const watchDeadline = Duration(minutes: 11);

  /// 생성이 끝날 때까지 상태를 지켜본다. Realtime 이 끊겨도 폴링이 받쳐 준다 —
  /// 여기서 멈추면 사용자는 영원히 도는 스피너를 본다.
  ///
  /// 마감은 **학습지가 만들어진 시각** 기준이다. 스트림이 시작한 시각으로 재면
  /// 화면을 나갔다 들어올 때마다 시계가 0으로 돌아가서, 30분이 지나도 영원히
  /// "곧 됩니다" 상태에 머문다. 실제로 그렇게 13분을 기다린 신고가 있었다.
  Stream<WorksheetSummary> watch(String id) async* {
    var last = await status(id);
    yield last;
    if (last.isTerminal) return;

    final deadline = last.createdAt.add(watchDeadline);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final next = await status(id);
        // 단계가 바뀐 것도 화면이 알아야 한다. 상태만 보면 진행 표시가 안 움직인다.
        if (next.status != last.status || next.stage != last.stage || next.isTerminal) {
          yield next;
        }
        last = next;
        if (next.isTerminal) return;
      } on AppError catch (e) {
        // 잠깐 끊긴 것으로 스트림을 죽이지 않는다. 화면은 마지막 상태를 그대로 들고 있는다.
        if (!e.retryable) rethrow;
      }
    }
    throw AppError.of(AppErrorKind.timeout,
        message: '학습지를 만드는 데 예상보다 오래 걸리고 있어요. 목록에서 다시 확인해 주세요.');
  }

  /// 제목 바꾸기.
  ///
  /// 서버는 진작 허용하고 있었다 — `grant update (title) on worksheets to authenticated`.
  /// 정작 앱에 부르는 곳이 없어서, 모델이 붙인 제목을 사용자가 고칠 방법이 없었다.
  /// 다른 컬럼은 서버 소유라 여기서도 title 만 보낸다.
  Future<void> rename(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw AppError.of(AppErrorKind.validation, message: '제목을 한 글자 이상 적어 주세요.');
    }
    if (clean.length > 120) {
      throw AppError.of(AppErrorKind.validation, message: '제목이 너무 길어요. 120자까지 쓸 수 있어요.');
    }
    try {
      await _client.from('worksheets').update({'title': clean}).eq('id', id).withTimeout();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 학습지 한 장을 지운다.
  ///
  /// 서버 함수를 거치는 이유는 **스토리지** 때문이다. 행만 지우면 학습지 HTML 과 필기
  /// 파일이 주인 없이 남는다 — 사용자는 지웠다고 믿는데 데이터는 남아 있는 상태다.
  /// 기기에 둔 사본도 여기서 같이 지운다. 서버에서 지운 것이 기기에 남아 있으면
  /// 오프라인에서 그 학습지가 되살아난다.
  Future<void> delete(String id) async {
    try {
      await _client.functions
          .invoke('delete-worksheet', body: {'worksheet_id': id})
          .withTimeout(kTransferTimeout);
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
    await _offline.forget(id);
  }

  /// 학습지 HTML. Storage 의 비공개 파일이라 서명 URL 로 연다.
  Future<String> signedHtmlUrl(String htmlPath, {Duration ttl = const Duration(hours: 1)}) async {
    try {
      return await _client.storage
          .from('worksheets')
          .createSignedUrl(htmlPath, ttl.inSeconds)
          .withTimeout();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 필기 저장. `rev` 로 낙관적 잠금을 건다.
  ///
  /// 아이패드에서 쓰고 폰에서 열면 두 기기가 같은 행을 쓴다. 그냥 덮어쓰면
  /// 나중에 저장한 쪽이 먼저 쓴 필기를 **말없이 지운다** — 사용자 데이터 손상이다.
  /// 그래서 "내가 읽은 rev 가 아직 그대로일 때만" 쓴다(compare-and-set).
  ///
  /// annotations 는 RLS 로 사용자가 직접 쓰는 테이블이라 서버 함수가 없다.
  /// rev 증가를 클라이언트가 계산하지만, `eq('rev', rev)` 가 있어서 경쟁에서는 한쪽만 이긴다.
  Future<int> saveAnnotations({
    required String worksheetId,
    required String strokesPath,
    required int strokeCount,
    required int bytes,
    required int rev,
    String? deviceId,
  }) async {
    final next = rev + 1;
    final patch = <String, Object?>{
      'strokes_path': strokesPath,
      'stroke_count': strokeCount,
      'bytes': bytes,
      'rev': next,
      'updated_by_device': deviceId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      // 첫 저장이면 아직 행이 없다.
      if (rev == 0) {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) throw AppError.of(AppErrorKind.unauthorized);
        final inserted = await _client
            .from('annotations')
            .insert({...patch, 'worksheet_id': worksheetId, 'user_id': userId, 'format_version': 2})
            .select('rev')
            .withTimeout();
        return (inserted.first['rev'] as num).toInt();
      }

      final rows = await _client
          .from('annotations')
          .update(patch)
          .eq('worksheet_id', worksheetId)
          .eq('rev', rev)
          .select('rev')
          .withTimeout();

      if (rows.isEmpty) {
        throw AppError.of(
          AppErrorKind.validation,
          message: '다른 기기에서 먼저 저장했어요. 최신 필기를 불러온 뒤 다시 저장할게요.',
          code: 'annotation_conflict',
        );
      }
      return (rows.first['rev'] as num).toInt();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 저장된 필기 메타. 없으면 rev 0 으로 시작한다.
  Future<({String? path, int rev, int formatVersion})> annotationMeta(String worksheetId) async {
    try {
      final rows = await _client
          .from('annotations')
          .select('strokes_path, rev, format_version')
          .eq('worksheet_id', worksheetId)
          .limit(1)
          .withTimeout();
      if (rows.isEmpty) return (path: null, rev: 0, formatVersion: 2);
      final r = rows.first;
      return (
        path: r['strokes_path'] as String?,
        rev: (r['rev'] as num?)?.toInt() ?? 0,
        formatVersion: (r['format_version'] as num?)?.toInt() ?? 1,
      );
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  /// 학습 응답(선택·서술)을 올린다. 무엇을 골랐고 무엇을 썼는지가 여기 남는다.
  ///
  /// `user_id` 를 여기서 붙인다. 테이블이 NOT NULL 이고 RLS 가 `auth.uid() = user_id` 라
  /// 빠지면 첫 저장부터 통째로 실패한다 — 화면에는 저장된 것처럼 보인 채로.
  Future<void> saveResponses(String worksheetId, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AppError.of(AppErrorKind.unauthorized);
    try {
      await _client.from('responses').upsert(
            rows.map((r) => {...r, 'worksheet_id': worksheetId, 'user_id': userId}).toList(),
            onConflict: 'worksheet_id,response_id',
          ).withTimeout();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }
}

final requestGuardProvider = Provider<RequestGuard>((ref) => RequestGuard());

final worksheetRepositoryProvider = Provider<WorksheetRepository>(
  (ref) => WorksheetRepository(
    ref.watch(supabaseProvider),
    ref.watch(requestGuardProvider),
    ref.watch(offlineStoreProvider),
  ),
);
