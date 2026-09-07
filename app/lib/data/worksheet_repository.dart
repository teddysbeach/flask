import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/request_guard.dart';
import '../domain/models.dart';
import 'supabase.dart';

/// 학습지 목록·생성·본문. 생성은 쿼터를 깎으므로 중복 요청을 여기서 막는다.
class WorksheetRepository {
  WorksheetRepository(this._client, this._guard);

  final SupabaseClient _client;
  final RequestGuard _guard;

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

  /// 생성 요청. 서버는 202 로 바로 답하고 뒤에서 만든다(40~120초).
  ///
  /// 같은 주제로 두 번 눌러도 한 번만 나간다. 이게 없으면 사용자가 두 장을 잃는다.
  Future<String> create({required String topic, required String level}) {
    final key = 'create:${topic.trim()}:$level';
    return _guard.dedupe(key, () async {
      try {
        // 서버는 202 로 바로 답한다. 여기서 오래 기다릴 이유가 없다 —
        // 생성이 끝나는 것은 watch() 가 지켜본다.
        final res = await _client.functions.invoke(
          'generate-worksheet',
          body: {'topic': topic.trim(), 'level': level},
        ).withTimeout();
        final data = res.data;
        if (data is Map && data['worksheet_id'] is String) {
          return data['worksheet_id'] as String;
        }
        throw AppError.of(AppErrorKind.unknown, cause: data);
      } catch (e, st) {
        throw mapSupabaseError(e, st);
      }
    });
  }

  /// 생성이 끝날 때까지 상태를 지켜본다. Realtime 이 끊겨도 폴링이 받쳐 준다 —
  /// 여기서 멈추면 사용자는 영원히 도는 스피너를 본다.
  Stream<WorksheetSummary> watch(String id) async* {
    var last = await get(id);
    yield last;
    if (last.isTerminal) return;

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final next = await get(id);
        if (next.status != last.status || next.isTerminal) yield next;
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
  (ref) => WorksheetRepository(ref.watch(supabaseProvider), ref.watch(requestGuardProvider)),
);
